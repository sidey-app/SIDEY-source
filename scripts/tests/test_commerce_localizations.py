import copy
import json
from pathlib import Path
import sys
import unittest


SCRIPTS = Path(__file__).parents[1]
sys.path.insert(0, str(SCRIPTS))

import commerce_localizations as localization_tool  # noqa: E402


class CommerceLocalizationTests(unittest.TestCase):
    def setUp(self):
        self.catalog = localization_tool.read_json(
            localization_tool.ROOT / localization_tool.CATALOG
        )
        self.source = localization_tool.read_json(
            localization_tool.ROOT / localization_tool.LOCALIZATIONS
        )

    def test_canonical_source_is_complete_and_matches_korean_catalog(self):
        localization_tool.validate_source(self.catalog, self.source)

        self.assertEqual(len(self.catalog), 33)
        self.assertEqual(len(self.source["products"]), 33)
        self.assertEqual(self.source["locales"], list(localization_tool.LOCALES))
        for catalog_entry, localized in zip(
            self.catalog,
            self.source["products"],
        ):
            self.assertEqual(localized["id"], catalog_entry["id"])
            self.assertEqual(
                set(localized["localizations"]),
                set(localization_tool.LOCALES),
            )
            korean = localized["localizations"]["ko"]
            self.assertEqual(korean["display_name"], catalog_entry["name"])
            self.assertEqual(
                korean["iap_description"],
                catalog_entry["description"],
            )
            self.assertEqual(
                korean["marketing_description"],
                catalog_entry["description"],
            )

    def test_missing_stale_empty_and_overlong_values_are_rejected(self):
        mutations = []

        missing_product = copy.deepcopy(self.source)
        missing_product["products"].pop()
        mutations.append(missing_product)

        stale_product = copy.deepcopy(self.source)
        stale_product["products"].append(
            copy.deepcopy(stale_product["products"][0])
        )
        mutations.append(stale_product)

        missing_locale = copy.deepcopy(self.source)
        del missing_locale["products"][0]["localizations"]["ja"]
        mutations.append(missing_locale)

        stale_field = copy.deepcopy(self.source)
        stale_field["products"][0]["localizations"]["en"]["stale"] = "value"
        mutations.append(stale_field)

        empty_value = copy.deepcopy(self.source)
        empty_value["products"][0]["localizations"]["en"]["display_name"] = ""
        mutations.append(empty_value)

        overlong_description = copy.deepcopy(self.source)
        overlong_description["products"][0]["localizations"]["en"][
            "iap_description"
        ] = "x" * 46
        mutations.append(overlong_description)

        stale_korean = copy.deepcopy(self.source)
        stale_korean["products"][0]["localizations"]["ko"][
            "marketing_description"
        ] = "이전 설명"
        mutations.append(stale_korean)

        for source in mutations:
            with self.subTest(source=source), self.assertRaises(ValueError):
                localization_tool.validate_source(self.catalog, source)

    def test_exports_are_deterministic_and_consumer_specific(self):
        payloads = {}
        for consumer in localization_tool.CONSUMERS:
            first = localization_tool.generated(
                self.catalog,
                self.source,
                consumer,
            )
            self.assertEqual(
                first,
                localization_tool.generated(
                    self.catalog,
                    self.source,
                    consumer,
                ),
            )
            payloads[consumer] = json.loads(first)

        macos = payloads["macos"]
        self.assertEqual(len(macos["products"]), 33)
        self.assertEqual(
            macos["products"][0]["app_store_product_id"],
            self.catalog[0]["app_store_product_id"],
        )

        web = payloads["web"]
        self.assertEqual(list(web["locales"]), list(localization_tool.LOCALES))
        for translations in web["locales"].values():
            self.assertEqual(len(translations), 33)
            self.assertEqual(
                set(next(iter(translations.values()))),
                {"display_name", "marketing_description"},
            )

        for consumer, locale_codes in (
            ("storekit", localization_tool.STOREKIT_LOCALES),
            ("app-store", localization_tool.APP_STORE_LOCALES),
        ):
            products = payloads[consumer]["products"]
            self.assertEqual(len(products), 33)
            self.assertEqual(
                [product["product_id"] for product in products],
                [entry["app_store_product_id"] for entry in self.catalog],
            )
            for product in products:
                self.assertEqual(
                    [item["locale"] for item in product["localizations"]],
                    list(locale_codes.values()),
                )
                for item in product["localizations"]:
                    self.assertTrue(2 <= len(item["display_name"]) <= 30)
                    self.assertTrue(0 < len(item["description"]) <= 45)

    def test_short_iap_names_use_kind_suffix_without_changing_source(self):
        korean_name = next(
            product["localizations"]["ko"]["display_name"]
            for product in self.source["products"]
            if product["id"] == "character_poop"
        )
        self.assertEqual(korean_name, "똥")
        self.assertEqual(
            localization_tool.app_store_display_name(
                "character_poop",
                "ko",
                korean_name,
                "character",
            ),
            "똥 캐릭터",
        )
        self.assertEqual(korean_name, "똥")

        for kind, suffixes in localization_tool.IAP_NAME_SUFFIXES.items():
            for locale, suffix in suffixes.items():
                self.assertEqual(
                    localization_tool.app_store_display_name(
                        "future_product",
                        locale,
                        "X",
                        kind,
                    ),
                    "X" + suffix,
                )

    def test_storekit_has_all_current_and_restore_only_apple_ids(self):
        configuration = localization_tool.read_json(
            localization_tool.ROOT / "macos/SIDEYAppStore.storekit"
        )
        current_ids = {
            entry["app_store_product_id"] for entry in self.catalog
        }
        legacy_ids = {
            apple_id
            for entry in self.catalog
            for apple_id in entry["legacy_app_store_product_ids"]
        }
        storekit_ids = {
            product["productID"] for product in configuration["products"]
        }

        self.assertEqual(len(current_ids), 33)
        self.assertEqual(len(legacy_ids), 10)
        self.assertEqual(len(storekit_ids), 43)
        self.assertEqual(storekit_ids, current_ids | legacy_ids)

        for consumer in ("storekit", "app-store"):
            payload = json.loads(
                localization_tool.generated(
                    self.catalog,
                    self.source,
                    consumer,
                )
            )
            exported_ids = {
                product["product_id"] for product in payload["products"]
            }
            self.assertEqual(exported_ids, current_ids)
            self.assertTrue(exported_ids.isdisjoint(legacy_ids))


if __name__ == "__main__":
    unittest.main()
