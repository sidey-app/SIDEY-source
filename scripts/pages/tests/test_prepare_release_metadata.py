from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "pages"))
from prepare_release_metadata import prepare, validate_repository


class PrepareReleaseMetadataTests(unittest.TestCase):
    def test_prepares_localized_pages_and_windows_manifests(self) -> None:
        with tempfile.TemporaryDirectory(prefix="SIDEY-Pages-") as temporary:
            test_root = Path(temporary)
            release_dir = test_root / "release"
            release_dir.mkdir()
            windows_manifest_path = ROOT / "release" / "windows.json"
            windows_manifest = json.loads(windows_manifest_path.read_text(encoding="utf-8"))
            windows_installer = release_dir / (
                f"SIDEY-Windows-x64-v{windows_manifest['version']}-Setup.exe"
            )
            shutil.copyfile(windows_manifest_path, windows_installer)
            output_dir = test_root / "site"

            prepare(
                ROOT / "website" / "dist",
                output_dir,
                windows_manifest_path,
                windows_installer,
            )

            windows_hash = hashlib.sha256(windows_installer.read_bytes()).hexdigest()
            published = json.loads(
                (output_dir / "windows-latest.json").read_text(encoding="utf-8")
            )
            self.assertEqual(published["sha256"], windows_hash)
            self.assertEqual(
                published,
                json.loads((output_dir / "windows" / "update.json").read_text(encoding="utf-8")),
            )
            app_store_urls = {
                "ko": "https://apps.apple.com/kr/app/sidey/id6808528060?mt=12",
                "en": "https://apps.apple.com/us/app/sidey/id6808528060?mt=12",
                "ja": "https://apps.apple.com/jp/app/sidey/id6808528060?mt=12",
                "zh-hant": "https://apps.apple.com/tw/app/sidey/id6808528060?mt=12",
            }
            for locale, app_store_url in app_store_urls.items():
                html = (output_dir / locale / "index.html").read_text(encoding="utf-8")
                self.assertNotIn("macos-download-sha256", html)
                self.assertNotIn(".dmg", html)
                self.assertNotIn("brew-command", html)
                self.assertIn(f'href="{app_store_url}"', html)
                self.assertIn(
                    f'<code id="windows-download-sha256" data-release-platform="windows">{windows_hash}</code>',
                    html,
                )

    def test_uses_an_explicit_staging_repository_in_download_urls(self) -> None:
        with tempfile.TemporaryDirectory(prefix="SIDEY-Pages-") as temporary:
            test_root = Path(temporary)
            release_dir = test_root / "release"
            release_dir.mkdir()
            windows_manifest_path = ROOT / "release" / "windows.json"
            windows_manifest = json.loads(windows_manifest_path.read_text(encoding="utf-8"))
            installer_name = (
                f"SIDEY-Windows-x64-v{windows_manifest['version']}-Setup.exe"
            )
            windows_installer = release_dir / installer_name
            shutil.copyfile(windows_manifest_path, windows_installer)
            output_dir = test_root / "site"

            prepare(
                ROOT / "website" / "dist",
                output_dir,
                windows_manifest_path,
                windows_installer,
                "sidey-app/SIDEY-public-staging",
            )

            published = json.loads(
                (output_dir / "windows-latest.json").read_text(encoding="utf-8")
            )
            self.assertEqual(
                published["installer_url"],
                "https://github.com/sidey-app/SIDEY-public-staging/releases/"
                f"download/windows-v{windows_manifest['version']}/{installer_name}",
            )
            html = (output_dir / "ko" / "index.html").read_text(encoding="utf-8")
            self.assertIn(f'href="{published["installer_url"]}"', html)
            self.assertIn(
                f'data-windows-url="{published["installer_url"]}"', html
            )

    def test_rejects_invalid_public_repository(self) -> None:
        for repository in ("SIDEY", "sidey-app/SIDEY/extra", "sidey app/SIDEY"):
            with self.subTest(repository=repository):
                with self.assertRaisesRegex(ValueError, "Invalid GitHub repository"):
                    validate_repository(repository)


if __name__ == "__main__":
    unittest.main()
