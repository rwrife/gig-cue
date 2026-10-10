#!/usr/bin/env python3
"""Platform and device policy contract checks for Gig Cue."""

from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBXPROJ = ROOT / "GigCue.xcodeproj" / "project.pbxproj"
TOOLCHAIN = ROOT / "toolchain.json"

EXPECTED_BUNDLE_ID = "com.infinityball.gigcue"


def check_toolchain(data: dict) -> None:
    if data.get("bundle_identifier") != EXPECTED_BUNDLE_ID:
        raise ValueError(
            f"toolchain bundle_identifier must be {EXPECTED_BUNDLE_ID}, "
            f"got {data.get('bundle_identifier')!r}"
        )
    if data.get("targeted_device_family") != "1":
        raise ValueError(
            f"toolchain targeted_device_family must be '1', "
            f"got {data.get('targeted_device_family')!r}"
        )
    if data.get("native_ipad_support") is not False:
        raise ValueError("toolchain native_ipad_support must be false")
    if data.get("platform") != "ios":
        raise ValueError(f"toolchain platform must be 'ios', got {data.get('platform')!r}")


def check_pbxproj(content: str) -> int:
    matches = re.findall(r"TARGETED_DEVICE_FAMILY = ([^;]+);", content)
    if not matches:
        raise ValueError("TARGETED_DEVICE_FAMILY not found in pbxproj")
    for val in matches:
        if val.strip() != "1":
            raise ValueError(
                f"TARGETED_DEVICE_FAMILY must be 1 across all configurations, observed: {val.strip()}"
            )
    configs = re.findall(r"isa = XCBuildConfiguration;\s*buildSettings = \{(.*?)\};", content, re.S)
    targets = [config for config in configs if 'PRODUCT_NAME' in config]
    if not targets:
        raise ValueError("No app/test target configurations found")
    for config in targets:
        family = re.findall(r"TARGETED_DEVICE_FAMILY = ([^;]+);", config)
        bundle = re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", config)
        if family != ["1"] or len(bundle) != 1:
            raise ValueError("Each target configuration requires explicit family and bundle ID")
        if bundle[0] not in (EXPECTED_BUNDLE_ID, EXPECTED_BUNDLE_ID + ".uitests"):
            raise ValueError(f"Unexpected bundle identifier: {bundle[0]}")
    if not any(f"PRODUCT_BUNDLE_IDENTIFIER = {EXPECTED_BUNDLE_ID};" in config for config in targets):
        raise ValueError("No Gig Cue app configuration found")
    return len(matches)


def run_checks() -> None:
    toolchain_data = json.loads(TOOLCHAIN.read_text(encoding="utf-8"))
    check_toolchain(toolchain_data)
    count = check_pbxproj(PBXPROJ.read_text(encoding="utf-8"))
    print(f"Platform contract check: PASS (TARGETED_DEVICE_FAMILY=1 in {count} configs, bundle={EXPECTED_BUNDLE_ID})")


class ContractCanaryTests(unittest.TestCase):
    def test_pbxproj_rejects_family_two(self):
        with self.assertRaises(ValueError):
            check_pbxproj("TARGETED_DEVICE_FAMILY = 2;")

    def test_pbxproj_rejects_universal_family(self):
        with self.assertRaises(ValueError):
            check_pbxproj("TARGETED_DEVICE_FAMILY = 1,2;")

    def test_pbxproj_rejects_wrong_bundle_prefix(self):
        # Must reach the bundle-prefix rejection itself, not the generic
        # "no configurations" error: fixture carries a valid target config.
        with self.assertRaisesRegex(ValueError, "Unexpected bundle identifier"):
            check_pbxproj(
                "isa = XCBuildConfiguration; buildSettings = {"
                "PRODUCT_NAME = GigCue; TARGETED_DEVICE_FAMILY = 1; "
                "PRODUCT_BUNDLE_IDENTIFIER = com.other.gigcue;};"
            )

    def test_toolchain_rejects_ipad_support(self):
        with self.assertRaises(ValueError):
            check_toolchain({
                "bundle_identifier": EXPECTED_BUNDLE_ID,
                "targeted_device_family": "1",
                "native_ipad_support": True,
                "platform": "ios"
            })


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        unittest.main(argv=[sys.argv[0]])
    else:
        run_checks()
