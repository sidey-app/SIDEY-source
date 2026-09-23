from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from app_store_connect.model import (  # noqa: E402
    APP_STORE_LOCALES,
    ValidationError,
    load_desired_state,
    validate_manifest,
)


class AppStoreConnectManifestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest_path = ROOT / "release" / "app-store-localizations.json"
        self.commerce_path = ROOT / "assets" / "v1" / "commerce-localizations.json"
        self.catalog_path = ROOT / "assets" / "v1" / "commerce-catalog.json"

    def test_repository_sources_cover_all_app_and_iap_localizations(self) -> None:
        desired = load_desired_state(
            self.manifest_path,
            self.commerce_path,
            self.catalog_path,
        )

        self.assertEqual(tuple(desired.manifest["app_localizations"]), APP_STORE_LOCALES)
        apple_ids = {
            candidate
            for product in desired.products
            for candidate in (
                product["app_store_product_id"],
                *product["legacy_app_store_product_ids"],
            )
        }
        self.assertEqual(len(apple_ids), sum(
            1 + len(product["legacy_app_store_product_ids"])
            for product in desired.products
        ))

    def test_rejects_missing_required_locale(self) -> None:
        manifest = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        del manifest["app_localizations"]["zh-Hant"]

        with self.assertRaisesRegex(ValidationError, "exactly"):
            validate_manifest(manifest)

    def test_rejects_iap_description_over_45_characters(self) -> None:
        document = json.loads(self.commerce_path.read_text(encoding="utf-8"))
        document = deepcopy(document)
        document["products"][0]["localizations"]["en"]["iap_description"] = "x" * 46
        temporary = self.commerce_path.parent / ".invalid-app-store-commerce.json"
        # Validate through the public source function without writing a fixture into the repository.
        from app_store_connect.model import read_json, validate_products

        catalog = read_json(self.catalog_path)
        with self.assertRaisesRegex(ValidationError, "exceeds 45"):
            validate_products(document, catalog)

    def test_rejects_unsafe_screenshot_path(self) -> None:
        manifest = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        manifest["app_localizations"]["ko"]["screenshots"][0]["path"] = "../secret.png"

        with self.assertRaisesRegex(ValidationError, "inside the repository"):
            validate_manifest(manifest)

    def test_rejects_keywords_over_100_utf8_bytes(self) -> None:
        manifest = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        manifest["app_localizations"]["ja"]["keywords"] = "長い言葉" * 9

        with self.assertRaisesRegex(ValidationError, "100 UTF-8 bytes"):
            validate_manifest(manifest)

    def test_rejects_keywords_that_do_not_exceed_two_characters(self) -> None:
        manifest = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        manifest["app_localizations"]["ko"]["keywords"] = "친구,메신저"

        with self.assertRaisesRegex(ValidationError, "exceed two characters"):
            validate_manifest(manifest)


if __name__ == "__main__":
    unittest.main()
