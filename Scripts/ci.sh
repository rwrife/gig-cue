#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

expected_sha="${1:-}"
if [[ -z "$expected_sha" ]]; then
  echo "usage: Scripts/ci.sh <expected-commit-sha>" >&2
  exit 2
fi

artifact_root="${GIGCUE_ARTIFACT_DIR:-$repo_root/build/ci-artifacts}"
mkdir -p "$artifact_root" "$repo_root/build"
artifact_dir="$(mktemp -d "$artifact_root/run.XXXXXX")"
derived_data="$(mktemp -d "$repo_root/build/DerivedData.XXXXXX")"
phase="initialization"

write_provenance() {
  local result=$?
  {
    echo "expected_sha=$expected_sha"
    echo "actual_sha=$(git rev-parse HEAD 2>/dev/null || echo unavailable)"
    echo "runner_os=${RUNNER_OS:-unknown}"
    echo "runner_arch=${RUNNER_ARCH:-unknown}"
    echo "developer_dir=${DEVELOPER_DIR:-unselected}"
    echo "simulator_udid=${simulator_udid:-unselected}"
    echo "phase=$phase"
    echo "exit_status=$result"
  } > "$artifact_dir/provenance.txt"
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    python3 Scripts/boot_simulator.py capture \
      --timeout 15 --output "$artifact_dir/xcode-version.txt" \
      -- xcodebuild -version || true
    python3 Scripts/boot_simulator.py capture \
      --timeout 15 --output "$artifact_dir/iphoneos-sdk-version.txt" \
      -- xcrun --sdk iphoneos --show-sdk-version || true
    python3 Scripts/boot_simulator.py capture \
      --timeout 20 --output "$artifact_dir/simulator-devices-exit.log" \
      -- xcrun simctl list devices available --json || true
  fi
}
trap write_provenance EXIT

actual_sha="$(git rev-parse HEAD)"
if [[ "$actual_sha" != "$expected_sha" ]]; then
  echo "Checked out SHA $actual_sha does not equal requested SHA $expected_sha" >&2
  exit 1
fi

phase="helper_tests"
python3 -m unittest discover -s Scripts/tests -v 2>&1 | tee "$artifact_dir/helper-tests.log"

phase="zero_network_gate"
bash scripts/check_zero_network.sh 2>&1 | tee "$artifact_dir/zero-network-gate.log"

phase="signing_material_gitignore_check"
# Secret material (ASC_KEY_P8 etc.) must never be committable.
for f in fake.p8 fake.p12 fake.mobileprovision fake.cer; do
  touch "$f"
  git check-ignore -q "$f" || { echo "FAIL: $f is not gitignored"; rm -f "$f"; exit 1; }
  rm -f "$f"
done
echo "Signing-material gitignore check: PASS" | tee "$artifact_dir/gitignore-check.log"

phase="platform_contract"
python3 Scripts/check_contract.py | tee "$artifact_dir/platform-contract.log"
bash scripts/check_native_only.sh | tee "$artifact_dir/native-only.log"
python3 Scripts/check_contract.py --self-test | tee "$artifact_dir/platform-contract-tests.log"

phase="toolchain_selection"
python3 Scripts/select_xcode.py \
  --toolchain toolchain.json \
  > "$artifact_dir/developer-dir.txt" \
  2> >(tee "$artifact_dir/toolchain-selection.log" >&2)
export DEVELOPER_DIR
DEVELOPER_DIR="$(<"$artifact_dir/developer-dir.txt")"

phase="simulator_runtime"
# macos-26 may omit the runtime matching pinned Xcode's SDK. Download only
# that platform; never substitute another Xcode or simulator runtime.
python3 - "$artifact_dir/platform-runtime.log" <<'PYTHON'
import json
import subprocess
import sys

sdk = subprocess.run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"],
                     capture_output=True, text=True, check=True, timeout=30).stdout.strip()
runtime = "com.apple.CoreSimulator.SimRuntime.iOS-" + sdk.replace(".", "-")
log = sys.argv[1]

def present():
    data = subprocess.run(["xcrun", "simctl", "list", "runtimes", "--json"],
                          capture_output=True, text=True, check=True, timeout=60).stdout
    return any(item.get("identifier") == runtime and item.get("isAvailable") is True
               for item in json.loads(data)["runtimes"])

with open(log, "w", encoding="utf-8") as output:
    print(f"Required SDK/runtime: {sdk} / {runtime}", file=output, flush=True)
    if not present():
        print("Pinned runtime missing; downloading platform", file=output, flush=True)
        # runner-images#13570: warm CoreSimulator, then request this Xcode's
        # compatible platform. Verify the exact runtime ID after downloading.
        subprocess.run(["xcrun", "simctl", "list"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
        try:
            subprocess.run(["xcodebuild", "-downloadPlatform", "iOS", "-architectureVariant", "universal"],
                           stdout=output, stderr=subprocess.STDOUT, check=True, timeout=900)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            raise SystemExit(f"Pinned iOS simulator platform download failed; see {log}: {error}") from error
    if not present():
        raise SystemExit(f"ACCEPTANCE BLOCKER: pinned runtime {runtime} unavailable; see {log}")
    print("Pinned runtime available", file=output)
PYTHON

phase="simulator_selection"
sdk_version="$(python3 -c 'import json; print(json.load(open("toolchain.json", encoding="utf-8"))["iphoneos_sdk"])')"
simulator_udid="$(python3 Scripts/select_simulator.py \
  --sdk "$sdk_version" \
  --devices-json-out "$artifact_dir/simulator-devices.json")"
echo "platform=iOS Simulator,id=$simulator_udid" > "$artifact_dir/destination.txt"

phase="simulator_boot"
python3 Scripts/boot_simulator.py boot \
  --udid "$simulator_udid" \
  --devices-json "$artifact_dir/simulator-devices.json" \
  --log "$artifact_dir/simulator-boot.log" \
  --boot-timeout 120 \
  --bootstatus-timeout 180 \
  2> >(tee -a "$artifact_dir/simulator-boot.log" >&2)

phase="domain_tests"
xcrun swift test \
  --package-path Packages/GigCueKit \
  2>&1 | tee "$artifact_dir/domain-tests.log"

phase="app_build"
xcodebuild build \
  -project GigCue.xcodeproj \
  -scheme GigCue \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_udid" \
  -derivedDataPath "$derived_data" \
  -resultBundlePath "$artifact_dir/build.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee "$artifact_dir/xcodebuild-build.log"

phase="device_family_guard"
app_plist="$derived_data/Build/Products/Debug-iphonesimulator/GigCue.app/Info.plist"
if [[ ! -f "$app_plist" ]]; then
  echo "Built app Info.plist missing at $app_plist" >&2
  exit 1
fi
plutil -convert json -o "$artifact_dir/app-info.json" "$app_plist"
python3 - "$artifact_dir/app-info.json" <<'PYTHON'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    info = json.load(handle)
family = info.get("UIDeviceFamily")
if family != [1]:
    raise SystemExit(f"Built app UIDeviceFamily must be [1], observed {family!r}")
bundle_id = info.get("CFBundleIdentifier")
if bundle_id != "com.infinityball.gigcue":
    raise SystemExit(
        "Built app CFBundleIdentifier must be com.infinityball.gigcue, "
        f"observed {bundle_id!r}"
    )
print("Verified built app UIDeviceFamily == [1] (iPhone only)")
print("Verified built app CFBundleIdentifier == com.infinityball.gigcue")
PYTHON

phase="ui_tests"
xcodebuild test \
  -project GigCue.xcodeproj \
  -scheme GigCue \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_udid" \
  -derivedDataPath "$derived_data" \
  -resultBundlePath "$artifact_dir/tests.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee "$artifact_dir/xcodebuild-test.log"

phase="complete"
