# Issue #1 bootstrap evidence

Dated record of what was actually verified, where, and what remains CI-only.

## What this bootstrap adds

- `GigCue.xcodeproj` with shared `GigCue` scheme (app + UI-test targets),
  bundle id `com.infinityball.gigcue`, `TARGETED_DEVICE_FAMILY = 1` in every
  build configuration, iOS 26.0 deployment target, Swift 6 language mode.
- `App/`: SwiftUI launch-only placeholder (`GigCueApp` + `BootstrapHomeView`)
  wired to `Packages/GigCueKit`.
- `Packages/GigCueKit`: pure Swift 6 package (Foundation only) with
  swift-testing placeholder tests proving the Linux lane works.
- `UITests/GigCueLaunchTests.swift`: simulator launch smoke test asserting
  the `bootstrap.home` accessibility identifier and home-screen copy.
- `Scripts/`: pinned toolchain selection (measured version/build/SDK match with bounded 30 s inspection timeouts),
  simulator selection/boot helpers with bounded subprocess timeouts, runtime
  download verification, bounded one-shot retry for hosted-runner wedges, and
  the CI entrypoint `Scripts/ci.sh` (phase-tracked provenance on every exit).
- `scripts/check_zero_network.sh`: empty-allowlist scan of `App/`, `UITests/`,
  and `Packages/*/Sources/` for network APIs (`.build` dirs excluded), failing on scan errors (>1 exit code).
- `scripts/check_native_only.sh`: gate rejecting Flutter/React Native/Expo/KMP/.NET MAUI/Unity.
- `Scripts/check_contract.py`: pre-build assertion verifying `TARGETED_DEVICE_FAMILY = 1`
  and `PRODUCT_BUNDLE_IDENTIFIER = com.infinityball.gigcue` across configurations.
- `.github/workflows/ci.yml`: Linux package job (`swift:6.2-noble`) plus a
  macos-26 job with exact-head checkout, pinned-toolchain validation, and
  always-upload artifacts.

## Toolchain enforcement

`toolchain.json` pins Xcode 26.0.1 (17A400) / iPhoneOS SDK 26.0 / Swift 6 mode /
deployment target 26.0, exactly as the README and PLAN require. `Scripts/select_xcode.py`
measures `xcodebuild -version` and `xcrun --sdk iphoneos --show-sdk-version` for every
installation under `/Applications` and only accepts an actual version/build/SDK match;
a missing pin is a hard CI failure (`PinError`), never a silent fallback. The workflow
checks out `github.event.pull_request.head.sha` explicitly, so CI tests the exact PR
head commit, not a synthetic merge ref.

## iPhone-only and zero-network enforcement

`Scripts/ci.sh` enforces iPhone-only policy twice: `Scripts/check_contract.py`
fails before compiling unless every `TARGETED_DEVICE_FAMILY` setting in
`GigCue.xcodeproj` is exactly `1` (any `1,2` or `2` fails), and after the build the
`device_family_guard` phase converts the built `GigCue.app/Info.plist` to JSON and
fails unless `UIDeviceFamily == [1]`; the JSON is uploaded as `app-info.json`.

The zero-network gate scans app sources, UI tests, and package sources against an
explicit EMPTY allowlist; any match on URLSession/Network.framework/CFNetwork/POSIX
socket vocabulary fails the run. The native-only gate rejects non-Swift/hybrid
manifests and files. A signing-material gitignore probe asserts `*.p8`, `*.p12`,
`*.mobileprovision`, and `*.cer` cannot be committed.

All simulator subprocesses are bounded (30 s enumeration, 120 s boot, 180 s
bootstatus) with logs preserved in `build/ci-artifacts`, and the workflow uploads
artifacts with `if: always()` so failures keep their provenance
(`provenance.txt` records expected/actual SHA, phase, and exit status).

## Verification actually performed (Linux executor, no Swift/Xcode on host)

- `python3 -m unittest discover -s Scripts/tests -v` — 32 helper unit tests pass locally (including scanner-error regressions for both native-only and zero-network gates, already-booted retry-reboots, and bounded Xcode-probe regressions).
- `python3 Scripts/check_contract.py --self-test` — 4 contract canaries pass locally. The wrong-bundle-prefix canary uses a complete valid target configuration, so passing it proves the bundle check rejects that identifier rather than a missing-configuration error.
- Independent fail-closed review of the staged patch (tree `4c804a0479223e7e6bb0c3b954271dfeca1ad5cd`) returned **FAIL** with the blocker that simulator creation used `Gig Cue CI`, which `select_destination` could not subsequently recognize. `CREATED_DEVICE_NAME` is now `iPhone Gig Cue CI`, and the creation test uses that constant. Restoring the rejected value made `test_missing_device_is_created_only_for_available_exact_runtime` fail (`1 != 0`); restoring the fix made it pass. The repair also made `find`/`grep` scan errors fail closed, corrected already-booted retry behavior, and narrowed the Swift skeleton test's purity claim.
- `swift test --package-path Packages/GigCueKit` — 3/3 tests pass inside Docker container (`swift:6.2-noble`).
- `swiftc -frontend -parse App/*.swift UITests/*.swift` — parse-clean syntax check inside Docker container (`swift:6.2-noble`).
- `bash -n Scripts/ci.sh`, `bash -n scripts/check_zero_network.sh`, `bash -n scripts/check_native_only.sh` — syntax OK.
- `scripts/check_zero_network.sh` run against the tree — PASS (empty allowlist).
- `scripts/check_native_only.sh` run against the tree — PASS.
- pbxproj object-ID closure probe (defined == referenced, all 24-hex) — clean.
- Workflow YAML and `toolchain.json` parse; `git diff --check` clean.
- grep: `TARGETED_DEVICE_FAMILY = 1;` present in all target configurations,
  zero iPad variants, bundle id `com.infinityball.gigcue` in all app configs.

## CI-pending claims (NOT claimed from this host)

- The macOS Xcode/SDK pin measurement, simulator build, launch XCUITest, embedded
  `Info.plist` `UIDeviceFamily == [1]` check, and built-app bundle-id check are
  **CI-pending**: the authoritative evidence is the macOS CI run for this PR's
  exact head SHA, retained in the `ios-ci-<sha>` artifact. Results are recorded
  on the PR when they exist, never pre-declared.

## Explicit non-claims

- No physical-device, VoiceOver, or signed-archive evidence exists or is claimed.
- No TestFlight/upload path exists (issue #7 owns that).
- The simulator test proves launch + home-screen rendering only; product journeys
  arrive with issues #2–#6.
- Hosted `simctl` startup has known transient hangs; a red CI run at a proven
  unchanged tree is retried once before being reported as an environment blocker.
