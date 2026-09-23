import plistlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import verify_binary_compatibility as compatibility


BUILD_VERSION = """fixture (architecture arm64):
Load command 0
      cmd LC_SEGMENT_64
  cmdsize 72
Load command 1
      cmd LC_BUILD_VERSION
  cmdsize 32
 platform 1
    minos 15.0
      sdk 26.4
   ntools 1
     tool 3
  version 1234.5
"""
LEGACY_VERSION = """fixture (architecture x86_64):
Load command 0
      cmd LC_VERSION_MIN_MACOSX
  cmdsize 16
  version 10.15
      sdk 15.0
"""


class BinaryCompatibilityTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.app = Path(temporary.name).resolve() / "SIDEY.app"
        self.main_binary = self.app / "Contents/MacOS/SIDEY"
        self.main_binary.parent.mkdir(parents=True)
        self.main_binary.write_bytes(bytes.fromhex("cafebabe") + b"fixture")
        self.info = {"CFBundleExecutable": "SIDEY", "LSMinimumSystemVersion": "15.0"}
        self.write_info()
        self.outputs = {}
        self.commands = []
        self.tool = patch.object(compatibility, "run_tool", side_effect=self.run_tool)
        self.tool.start()
        self.addCleanup(self.tool.stop)

    def write_info(self):
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps(self.info))

    def run_tool(self, command):
        self.commands.append(command)
        path = Path(command[-1])
        if command[0] == "/usr/bin/lipo":
            return self.outputs.get((path, "architectures"), "x86_64 arm64\n")
        architecture = command[2]
        return self.outputs.get((path, architecture), BUILD_VERSION)

    def add_framework(self):
        framework = self.app / "Contents/Frameworks/Fixture.framework"
        binary = framework / "Versions/A/Fixture"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(bytes.fromhex("cafebabe") + b"fixture")
        (framework / "Versions/Current").symlink_to("A", target_is_directory=True)
        (framework / "Fixture").symlink_to("Versions/Current/Fixture")
        return binary

    def test_universal_app_and_framework_aliases_are_verified_once_per_binary(self):
        binary = self.add_framework()
        self.outputs[(binary, "x86_64")] = LEGACY_VERSION
        self.assertEqual(compatibility.verify_app(self.app), 2)
        lipo_calls = [call for call in self.commands if call[0] == "/usr/bin/lipo"]
        self.assertEqual({Path(call[-1]) for call in lipo_calls}, {binary, self.main_binary})
        self.assertEqual(len(lipo_calls), 2)
        self.assertEqual(len(self.commands), 6)

    def test_main_executable_must_exist_and_be_mach_o(self):
        self.main_binary.unlink()
        with self.assertRaisesRegex(ValueError, "Main executable is missing"):
            compatibility.verify_app(self.app)
        self.main_binary.write_text("not a binary")
        with self.assertRaisesRegex(ValueError, "not Mach-O"):
            compatibility.verify_app(self.app)

    def test_root_minimum_os_must_match_supported_contract(self):
        for minimum in (None, "14.0", "15.1", "26.0"):
            with self.subTest(minimum=minimum):
                self.info["LSMinimumSystemVersion"] = minimum or ""
                self.write_info()
                with self.assertRaisesRegex(ValueError, "LSMinimumSystemVersion"):
                    compatibility.verify_app(self.app)

    def test_missing_intel_slice_is_rejected_in_main_or_embedded_framework(self):
        binary = self.add_framework()
        for target in (self.main_binary, binary):
            with self.subTest(binary=target):
                self.outputs = {(target, "architectures"): "arm64"}
                with self.assertRaisesRegex(ValueError, "expected arm64 and x86_64"):
                    compatibility.verify_app(self.app)

    def test_newer_minimum_os_in_either_embedded_slice_is_rejected(self):
        binary = self.add_framework()
        for architecture in ("arm64", "x86_64"):
            with self.subTest(architecture=architecture):
                self.outputs = {(binary, architecture): BUILD_VERSION.replace("minos 15.0", "minos 15.1")}
                with self.assertRaisesRegex(ValueError, rf"{architecture}.*above 15.0"):
                    compatibility.verify_app(self.app)

    def test_external_bundle_link_is_rejected(self):
        external = self.app.parent / "external"
        external.write_text("fixture")
        (self.app / "Contents/alias").symlink_to(external)
        with self.assertRaisesRegex(ValueError, "symlink escapes"):
            compatibility.verify_app(self.app)

    def test_load_command_parser_reads_minimum_instead_of_sdk_or_tool_version(self):
        self.assertEqual(compatibility.parse_minimum_os(BUILD_VERSION), (15, 0, 0))
        self.assertEqual(compatibility.parse_minimum_os(LEGACY_VERSION), (10, 15, 0))
        self.assertEqual(compatibility.parse_minimum_os(BUILD_VERSION.replace("platform 1", "platform MACOS")), (15, 0, 0))

    def test_missing_malformed_or_non_macos_load_commands_are_rejected(self):
        for output in ("", BUILD_VERSION + LEGACY_VERSION,
                       BUILD_VERSION.replace("minos 15.0", "minos invalid"),
                       BUILD_VERSION.replace("minos 15.0", ""),
                       BUILD_VERSION.replace("platform 1", "platform 2")):
            with self.subTest(output=output), self.assertRaises(ValueError):
                compatibility.parse_minimum_os(output)

    def test_tool_failure_is_reported(self):
        self.tool.stop()
        error = subprocess.CalledProcessError(1, ["/usr/bin/lipo"], stderr="truncated file")
        with patch.object(compatibility.subprocess, "run", side_effect=error):
            with self.assertRaisesRegex(ValueError, "truncated file"):
                compatibility.verify_app(self.app)


if __name__ == "__main__":
    unittest.main()
