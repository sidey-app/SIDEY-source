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
        self.windows_catalog = localization_tool.windows_catalog()

    def test_canonical_source_is_complete_and_matches_korean_catalog(self):
        localization_tool.validate_source(self.catalog, self.source)

        self.assertEqual(self.source["locales"], list(localization_tool.LOCALES))
        self.assertEqual(
            self.source["windows_locales"],
            list(localization_tool.WINDOWS_ONLY_LOCALES),
        )
        windows_ids = {entry["id"] for entry in self.windows_catalog}
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
            if catalog_entry["id"] in windows_ids:
                self.assertEqual(
                    list(localized["windows_localizations"]),
                    list(localization_tool.WINDOWS_ONLY_LOCALES),
                )
            else:
                self.assertNotIn("windows_localizations", localized)

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

        missing_windows_locale = copy.deepcopy(self.source)
        del missing_windows_locale["products"][0]["windows_localizations"]["uk"]
        mutations.append(missing_windows_locale)

        windows_data_on_unsupported_product = copy.deepcopy(self.source)
        unsupported = next(
            product
            for product in windows_data_on_unsupported_product["products"]
            if product["id"]
            not in {entry["id"] for entry in self.windows_catalog}
        )
        unsupported["windows_localizations"] = copy.deepcopy(
            self.source["products"][0]["windows_localizations"]
        )
        mutations.append(windows_data_on_unsupported_product)

        untranslated_windows_value = copy.deepcopy(self.source)
        untranslated_windows_value["products"][0]["windows_localizations"]["ru"][
            "display_name"
        ] = "미번역"
        mutations.append(untranslated_windows_value)

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
        self.assertEqual(len(macos["products"]), len(self.catalog))
        self.assertEqual(
            macos["products"][0]["app_store_product_id"],
            self.catalog[0]["app_store_product_id"],
        )

        web = payloads["web"]
        self.assertEqual(list(web["locales"]), list(localization_tool.LOCALES))
        for translations in web["locales"].values():
            self.assertEqual(len(translations), len(self.catalog))
            self.assertEqual(
                set(next(iter(translations.values()))),
                {"display_name", "marketing_description"},
            )

        for consumer, locale_codes in (
            ("storekit", localization_tool.STOREKIT_LOCALES),
            ("app-store", localization_tool.APP_STORE_LOCALES),
        ):
            products = payloads[consumer]["products"]
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

        windows = payloads["windows"]
        self.assertEqual(
            list(windows["locales"]),
            list(localization_tool.WINDOWS_LOCALES.values()),
        )
        for values in windows["locales"].values():
            self.assertEqual(
                len(values),
                len(self.windows_catalog) * 2,
            )

    def test_windows_overlay_uses_only_supported_products(self):
        overlays = localization_tool.windows_overlays(
            self.catalog,
            self.source,
            self.windows_catalog,
        )
        supported_ids = {entry["id"] for entry in self.windows_catalog}
        unsupported_ids = {entry["id"] for entry in self.catalog} - supported_ids
        for locale, values in overlays.items():
            self.assertEqual(len(values), len(supported_ids) * 2, locale)
            for product_id in unsupported_ids:
                self.assertNotIn(
                    f"store.productDescriptions.{product_id}",
                    values,
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
