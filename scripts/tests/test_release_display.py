from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / 'skills'))
import verify_release_consistency as v


VALID_README = f"""# SIDEY

## Installation

### macOS

[Download SIDEY]({v.APP_STORE_URL})

#### App Store

Install from the Mac App Store.

### Windows

<a href="{v.RELEASES_URL}">Download SIDEY</a>

## Contribute
"""


class ReleaseDisplayTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        for path in v.README_PATHS:
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(VALID_README, encoding="utf-8")
        root_patch = patch.object(v, "ROOT", self.root)
        root_patch.start()
        self.addCleanup(root_patch.stop)

    def write_readme(self, content, path="README.md"):
        (self.root / path).write_text(content, encoding="utf-8")

    def test_version_free_markdown_and_html_links_pass_for_all_languages(self):
        for platform in ("macos", "windows"):
            v.validate_readme_release_links(platform)

    def test_installation_section_includes_subheadings_but_stops_at_next_peer(self):
        macos = v.release_display("macos")
        self.assertIn("#### App Store", macos)
        self.assertNotIn("### Windows", macos)
        self.assertNotIn("## Contribute", v.release_display("windows"))

    def test_missing_and_duplicate_platform_sections_fail(self):
        for platform, heading in (("macos", "macOS"), ("windows", "Windows")):
            for content in (VALID_README.replace(f"### {heading}", "### Other"),
                            VALID_README + f"\n### {heading}\n"):
                with self.subTest(platform=platform, content=content):
                    self.write_readme(content)
                    with self.assertRaisesRegex(v.ConsistencyError, "exactly one"):
                        v.validate_readme_release_links(platform)

    def test_link_in_other_section_does_not_satisfy_installation_section(self):
        self.write_readme(VALID_README.replace(f"[Download SIDEY]({v.APP_STORE_URL})", ""))
        with self.assertRaisesRegex(v.ConsistencyError, "must link to"):
            v.validate_readme_release_links("macos")

    def test_plain_url_without_clickable_link_fails(self):
        self.write_readme(VALID_README.replace(
            f"[Download SIDEY]({v.APP_STORE_URL})", v.APP_STORE_URL))
        with self.assertRaisesRegex(v.ConsistencyError, "must link to"):
            v.validate_readme_release_links("macos")

    def test_wrong_or_pinned_release_links_fail_even_with_official_link(self):
        for url in (
            "https://github.com/another-owner/SIDEY/releases",
            f"{v.RELEASES_URL}/tag/v1.2.1",
            f"{v.RELEASES_URL}/download/windows-v1.3.0/SIDEY-Windows-x64-v1.3.0-Setup.exe",
            f"{v.RELEASES_URL}/latest",
        ):
            with self.subTest(url=url):
                self.write_readme(VALID_README.replace(
                    "### Windows\n", f"### Windows\n\n[Other download]({url})\n"))
                with self.assertRaisesRegex(v.ConsistencyError, "release URL"):
                    v.validate_readme_release_links("windows")

    def test_versioned_installer_names_fail(self):
        for name in ("SIDEY-macOS-arm64-v1.2.1.dmg", "SIDEY-Windows-x64-v1.3.0-Setup.exe"):
            with self.subTest(name=name):
                self.write_readme(VALID_README.replace("### Windows\n", f"### Windows\n\n`{name}`\n"))
                with self.assertRaisesRegex(v.ConsistencyError, "pin an installer"):
                    v.validate_readme_release_links("windows")

    def test_each_translation_is_checked(self):
        for path in v.README_PATHS[1:]:
            with self.subTest(path=path):
                self.write_readme(VALID_README.replace(v.APP_STORE_URL, "https://example.com"), path)
                with self.assertRaisesRegex(v.ConsistencyError, "must link to"):
                    v.validate_readme_release_links("macos")
                self.write_readme(VALID_README, path)

    def test_retired_macos_installers_are_rejected_even_with_app_store_link(self):
        for retired in ("[Download](https://example.com/SIDEY.dmg)",
                        "brew install --cask sidey-app/tap/sidey",
                        f"[Releases]({v.RELEASES_URL})"):
            with self.subTest(retired=retired):
                self.write_readme(VALID_README.replace("#### App Store", retired))
                with self.assertRaisesRegex(v.ConsistencyError, "only the Mac App Store"):
                    v.validate_readme_release_links("macos")

    def test_missing_translation_fails(self):
        (self.root / v.README_PATHS[-1]).unlink()
        with self.assertRaisesRegex(v.ConsistencyError, "translation is missing"):
            v.validate_readme_release_links("windows")
