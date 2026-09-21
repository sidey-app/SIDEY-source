import json
from pathlib import Path
import subprocess
import sys
import unittest


ROOT = Path(__file__).resolve().parents[3]


class CommerceLocalizationAssetTests(unittest.TestCase):
    def test_generated_bundle_and_storekit_metadata_are_current(self):
        result = subprocess.run(
            [sys.executable, "scripts/macos/sync_commerce_localizations.py"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_current_products_have_four_locales_and_legacy_products_stay_restore_only(self):
        catalog = json.loads(
            (ROOT / "assets/v1/commerce-catalog.json").read_text(encoding="utf-8")
        )
        storekit = json.loads(
            (ROOT / "macos/SIDEYAppStore.storekit").read_text(encoding="utf-8")
        )
        by_id = {product["productID"]: product for product in storekit["products"]}
        current_ids = {entry["app_store_product_id"] for entry in catalog}
        legacy_ids = {
            product_id
            for entry in catalog
            for product_id in entry["legacy_app_store_product_ids"]
        }

        self.assertEqual(len(current_ids), 33)
        self.assertEqual(len(legacy_ids), 10)
        self.assertEqual(set(by_id), current_ids | legacy_ids)
        for product_id in current_ids:
            self.assertEqual(
                [item["locale"] for item in by_id[product_id]["localizations"]],
                ["ko_KR", "en_US", "ja", "zh_Hant"],
            )
        for product_id in legacy_ids:
            self.assertEqual(len(by_id[product_id]["localizations"]), 1)


if __name__ == "__main__":
    unittest.main()
