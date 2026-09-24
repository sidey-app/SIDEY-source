import importlib.util
import plistlib
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "scripts/macos/verify_app_version.py"
SPEC = importlib.util.spec_from_file_location("verify_app_version", MODULE_PATH)
APP_VERSION = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(APP_VERSION)


class BuiltAppVersionTests(unittest.TestCase):
    def write_info_plist(self, product_version="2.7.3", build="4821"):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "SIDEY.app/Contents/Info.plist"
        path.parent.mkdir(parents=True)
        path.write_bytes(
            plistlib.dumps(
                {
                    "CFBundleShortVersionString": product_version,
                    "CFBundleVersion": build,
                }
            )
        )
        return path

    def test_built_metadata_matches_product_and_mac_update_versions(self):
        APP_VERSION.verify_info_plist(self.write_info_plist(), "2.7.3", "4821")

    def test_mismatched_product_or_build_version_fails_with_the_metadata_key(self):
        info_plist = self.write_info_plist()
        for product_version, build, key in (
            ("2.7.4", "4821", "CFBundleShortVersionString"),
            ("2.7.3", "4822", "CFBundleVersion"),
        ):
            with self.subTest(key=key), self.assertRaisesRegex(
                APP_VERSION.AppVersionError, key
            ):
                APP_VERSION.verify_info_plist(info_plist, product_version, build)

if __name__ == "__main__":
    unittest.main()
