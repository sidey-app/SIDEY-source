import json
from pathlib import Path
import sys
import tempfile
import unittest


sys.path.insert(0, str(Path(__file__).parents[1]))
import sidey_version as versions


class SideyVersionTests(unittest.TestCase):
    def parse(self, product="2.7.3", revision=0, mac_build=4821):
        return versions.parse_version_data({
            "schema": 1,
            "productVersion": product,
            "windowsRevision": revision,
            "macBuild": mac_build,
        })

    def test_platform_versions_are_derived_from_one_source(self):
        version = self.parse(revision=1)
        self.assertEqual(version.product_version, "2.7.3")
        self.assertEqual(version.mac_build, 4821)
        self.assertEqual(version.assembly_version, "2.7.3.0")
        self.assertEqual(version.windows_update_version, "2.7.3001")
        self.assertEqual(version.windows_release_version, "2.7.3001")
        self.assertEqual(version.msix_version, "2.7.3001.0")
        self.assertIn("<FileVersion>2.7.3001.0</FileVersion>",
                      versions.render_windows_props(version))
        self.assertIn("<SideyWindowsUpdateVersion>2.7.3001</SideyWindowsUpdateVersion>",
                      versions.render_windows_props(version))
        self.assertIn("MARKETING_VERSION = 2.7.3",
                      versions.render_macos_xcconfig(version))

    def test_msix_formula_covers_revision_range_and_patch_reset(self):
        expected = {
            ("2.7.3", 0): "2.7.3000.0",
            ("2.7.3", 1): "2.7.3001.0",
            ("2.7.3", 105): "2.7.3105.0",
            ("2.7.3", 999): "2.7.3999.0",
            ("2.7.4", 0): "2.7.4000.0",
            ("2.8.0", 0): "2.8.0.0",
        }
        for (product, revision), result in expected.items():
            with self.subTest(product=product, revision=revision):
                self.assertEqual(self.parse(product, revision).msix_version, result)

    def test_revision_zero_keeps_legacy_product_release_identity(self):
        version = self.parse("2.7.3", revision=0)
        self.assertEqual(version.windows_update_version, "2.7.3000")
        self.assertEqual(version.windows_release_version, "2.7.3")
        manifest = json.loads(versions.render_release_manifest("windows", version))
        self.assertEqual(manifest, {
            "schema": 1,
            "platform": "windows",
            "channel": "production",
            "version": "2.7.3",
            "windowsRevision": 0,
            "updateVersion": "2.7.3000",
            "releaseVersion": "2.7.3",
            "msixVersion": "2.7.3000.0",
        })

    def test_invalid_msix_values_fail_instead_of_being_adjusted(self):
        invalid = (
            ("0.7.3", 0, "major must be at least 1"),
            ("65536.0.0", 0, "major exceeds"),
            ("1.65536.0", 0, "minor exceeds"),
            ("1.0.0", -1, "between 0 and 999"),
            ("1.0.0", 1000, "between 0 and 999"),
            ("1.0.65", 536, "exceeds the MSIX Build limit"),
        )
        for product, revision, message in invalid:
            with self.subTest(product=product, revision=revision):
                with self.assertRaisesRegex(versions.VersionError, message):
                    self.parse(product, revision)

    def test_stable_semver_and_positive_mac_build_are_required(self):
        for product in ("2.7", "2.7.3.1", "02.7.3", "2.7.3-beta"):
            with self.subTest(product=product):
                with self.assertRaisesRegex(versions.VersionError, "Major.Minor.Patch"):
                    self.parse(product)
        with self.assertRaisesRegex(versions.VersionError, "positive"):
            self.parse(mac_build=0)

    def test_product_version_change_requires_windows_revision_reset(self):
        previous = self.parse("2.7.3", revision=12, mac_build=4821)
        versions.validate_transition(
            previous,
            self.parse("2.7.4", revision=0, mac_build=4821),
        )
        with self.assertRaisesRegex(versions.VersionError, "reset to 0"):
            versions.validate_transition(
                previous,
                self.parse("2.7.4", revision=1, mac_build=4821),
            )

    def test_platform_counters_and_product_version_do_not_decrease(self):
        previous = self.parse("2.7.3", revision=12, mac_build=4821)
        invalid = (
            (self.parse("2.7.2", revision=0, mac_build=4821), "must not decrease"),
            (self.parse("2.7.3", revision=11, mac_build=4821), "windowsRevision"),
            (self.parse("2.7.3", revision=12, mac_build=4820), "macBuild"),
        )
        for current, message in invalid:
            with self.subTest(current=current):
                with self.assertRaisesRegex(versions.VersionError, message):
                    versions.validate_transition(previous, current)

    def test_check_detects_stale_generated_mirror(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "release").mkdir()
            (root / "release/version.json").write_text(json.dumps({
                "schema": 1,
                "productVersion": "2.7.3",
                "windowsRevision": 1,
                "macBuild": 4821,
            }), encoding="utf-8")
            versions.write_platform("windows", root)
            versions.check_platform("windows", root)
            (root / "windows/Version.props").write_text(
                "<Project />\n", encoding="utf-8")
            with self.assertRaisesRegex(versions.VersionError, "stale"):
                versions.check_platform("windows", root)


if __name__ == "__main__":
    unittest.main()
