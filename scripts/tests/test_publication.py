from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "publication"))
from build_compliance_source import sha256, validate_asset
from release_inventory import normalize, verify
from validate_public_tree import validate_tree


class PublicTreeTests(unittest.TestCase):
    def make_valid_tree(self, root: Path) -> None:
        for relative in (
            "index.html",
            "ko/index.html",
            "en/index.html",
            "ja/index.html",
        ):
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("<!doctype html>", encoding="utf-8")
        for relative in ("windows-latest.json", "windows/update.json"):
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("{}\n", encoding="utf-8")
        (root / ".nojekyll").write_text("", encoding="utf-8")

    def test_accepts_generated_pages_for_staging_repository(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_valid_tree(root)
            (root / "assets").mkdir()
            (root / "assets" / "site.js").write_text("const ok = true;", encoding="utf-8")
            files = validate_tree(root, "sidey-app/SIDEY-public-staging")
            self.assertIn("assets/site.js", files)

    def test_rejects_source_maps_and_secrets(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_valid_tree(root)
            (root / "bundle.js.map").write_text("{}", encoding="utf-8")
            (root / "leak.txt").write_text(
                "github_pat_012345678901234567890123456789", encoding="utf-8"
            )
            with self.assertRaises(ValueError) as caught:
                validate_tree(root)
            message = str(caught.exception)
            self.assertIn("bundle.js.map", message)
            self.assertIn("GitHub token detected", message)


class ReleaseInventoryTests(unittest.TestCase):
    def raw_release(self, *, name: str = "SIDEY v1", size: int = 3) -> dict:
        return {
            "tag_name": "v1.0.0",
            "name": name,
            "draft": False,
            "prerelease": False,
            "published_at": "2026-01-01T00:00:00Z",
            "target_commitish": "a" * 40,
            "body": "변경 사항",
            "assets": [
                {
                    "name": "SIDEY.zip",
                    "size": size,
                    "digest": "sha256:" + ("a" * 64),
                }
            ],
        }

    def test_normalization_is_deterministic(self) -> None:
        inventory = normalize([self.raw_release()], "sidey-app/SIDEY-source")
        self.assertEqual(inventory["schema"], 1)
        self.assertEqual(
            inventory["releases"][0]["assets"][0]["digest"],
            "sha256:" + ("a" * 64),
        )
        json.dumps(inventory, ensure_ascii=False, sort_keys=True)

    def test_verify_allows_changed_publication_time(self) -> None:
        source = normalize([self.raw_release()], "sidey-app/SIDEY-source")
        target_release = self.raw_release()
        target_release["published_at"] = "2026-09-20T00:00:00Z"
        target = normalize([target_release], "sidey-app/SIDEY-public-staging")
        verify(source, target, "sidey-app/SIDEY-public-staging")

    def test_verify_rejects_asset_mismatch(self) -> None:
        source = normalize([self.raw_release()], "sidey-app/SIDEY-source")
        target = normalize(
            [self.raw_release(size=4)], "sidey-app/SIDEY-public-staging"
        )
        with self.assertRaisesRegex(ValueError, "metadata or assets differ"):
            verify(source, target, "sidey-app/SIDEY-public-staging")

    def test_verify_rejects_assets_without_sha256_digest(self) -> None:
        release = self.raw_release()
        release["assets"][0]["digest"] = None
        source = normalize([release], "sidey-app/SIDEY-source")
        target = normalize([release], "sidey-app/SIDEY-public-staging")
        with self.assertRaisesRegex(ValueError, "missing a digest"):
            verify(source, target, "sidey-app/SIDEY-public-staging")

    def test_verify_accepts_only_declared_compliance_source_asset(self) -> None:
        source = normalize([self.raw_release()], "sidey-app/SIDEY-source")
        target_release = self.raw_release()
        compliance_asset = {
            "name": "SIDEY-v1-corresponding-source.tar",
            "size": 123,
            "digest": "sha256:" + ("b" * 64),
        }
        target_release["assets"].append(compliance_asset)
        target = normalize([target_release], "sidey-app/SIDEY-public-staging")
        contract = {
            "schema": 1,
            "assets": [
                {
                    "tag": "v1.0.0",
                    "source_commit": "a" * 40,
                    "license_introduction_commit": "9" * 40,
                    **compliance_asset,
                }
            ],
        }

        verify(source, target, "sidey-app/SIDEY-public-staging", contract)
        with self.assertRaisesRegex(ValueError, "metadata or assets differ"):
            verify(source, target, "sidey-app/SIDEY-public-staging")

    def test_verify_rejects_missing_declared_compliance_source_asset(self) -> None:
        source = normalize([self.raw_release()], "sidey-app/SIDEY-source")
        target = normalize([self.raw_release()], "sidey-app/SIDEY-public-staging")
        contract = {
            "schema": 1,
            "assets": [
                {
                    "tag": "v1.0.0",
                    "source_commit": "a" * 40,
                    "license_introduction_commit": "9" * 40,
                    "name": "SIDEY-v1-corresponding-source.tar",
                    "size": 123,
                    "digest": "sha256:" + ("b" * 64),
                }
            ],
        }
        with self.assertRaisesRegex(ValueError, "metadata or assets differ"):
            verify(source, target, "sidey-app/SIDEY-public-staging", contract)


class ComplianceSourceTests(unittest.TestCase):
    def test_validates_declared_archive_and_hashes_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / "source.tar"
            archive.write_bytes(b"corresponding source")
            digest = sha256(archive)
            self.assertEqual(
                digest,
                "sha256:" + hashlib.sha256(b"corresponding source").hexdigest(),
            )
            validate_asset(
                {
                    "tag": "windows-v2.0.0",
                    "source_commit": "a" * 40,
                    "license_introduction_commit": "b" * 40,
                    "name": "SIDEY-source.tar",
                    "archive_prefix": "SIDEY-source/",
                    "size": archive.stat().st_size,
                    "digest": digest,
                }
            )


if __name__ == "__main__":
    unittest.main()
