#!/usr/bin/env python3
"""Validate and export the canonical commerce localization source.

The source keeps logical product names identical to the Korean legacy catalog.
App Store Connect requires IAP display names to contain at least two characters,
so exports append a localized, kind-based suffix only when a source name is
shorter than that limit. The source value itself is never rewritten.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

from catalog_source import load_source, supported_catalog


ROOT = Path(__file__).resolve().parents[1]
CATALOG = "assets/v1/commerce-catalog.json"
LOCALIZATIONS = "assets/v1/commerce-localizations.json"

SCHEMA = 2
CONSUMER_SCHEMA = 1
LOCALES = ("ko", "en", "ja", "zh-Hant")
WINDOWS_ONLY_LOCALES = ("zh-Hans", "uk", "ru")
FIELDS = (
    "display_name",
    "iap_description",
    "marketing_description",
)
CONSUMERS = ("macos", "web", "storekit", "app-store", "windows")

WINDOWS_LOCALES = {
    "ko": "ko-KR",
    "en": "en-US",
    "ja": "ja-JP",
    "zh-Hans": "zh-CN",
    "zh-Hant": "zh-TW",
    "uk": "uk-UA",
    "ru": "ru-RU",
}
WINDOWS_CHARACTER_NAME_KEYS = {
    "character_starlight_upalupa": "characters.starlightUpalupa",
    "character_guinea_pig": "characters.guineaPig",
    "character_monkey": "characters.monkey",
    "character_chinchilla": "characters.chinchilla",
    "character_otter": "characters.otter",
    "character_pig": "characters.pig",
    "character_tree": "characters.tree",
}
WINDOWS_FIELDS = ("display_name", "marketing_description")

STOREKIT_LOCALES = {
    "ko": "ko_KR",
    "en": "en_US",
    "ja": "ja",
    "zh-Hant": "zh_Hant",
}
APP_STORE_LOCALES = {
    "ko": "ko",
    "en": "en-US",
    "ja": "ja",
    "zh-Hant": "zh-Hant",
}
IAP_NAME_SUFFIXES = {
    "character": {
        "ko": " 캐릭터",
        "en": " Character",
        "ja": "キャラクター",
        "zh-Hant": "角色",
    },
    "bubble": {
        "ko": " 말풍선",
        "en": " Bubble",
        "ja": "吹き出し",
        "zh-Hant": "對話框",
    },
    "throwable": {
        "ko": " 투척물",
        "en": " Throwable",
        "ja": "投げアイテム",
        "zh-Hant": "投擲物",
    },
}


def read_json(path: Path):
    """Read a UTF-8 JSON document."""

    def reject_duplicates(pairs):
        output = {}
        for key, value in pairs:
            if key in output:
                raise ValueError(f"{path}: duplicate JSON key: {key}")
            output[key] = value
        return output

    return json.loads(
        path.read_text(encoding="utf-8"),
        object_pairs_hook=reject_duplicates,
    )


def windows_catalog():
    """Return the exact reviewed catalog subset supported by Windows."""

    catalog, manifest, _ = load_source(ROOT, "windows")
    return supported_catalog(catalog, manifest, "windows")


def validate_translation(translation, fields, product_id, locale):
    """Validate one product translation without platform assumptions."""

    if not isinstance(translation, dict) or list(translation) != list(fields):
        raise ValueError(
            f"Fields or field order differ: {product_id} ({locale})"
        )
    for field, value in translation.items():
        if (
            not isinstance(value, str)
            or not value
            or value != value.strip()
            or "\n" in value
            or "\r" in value
        ):
            raise ValueError(f"Invalid {field}: {product_id} ({locale})")


def validate_source(catalog, source, platform_catalog=None):
    """Validate completeness, ordering and legacy Korean compatibility."""

    if not isinstance(source, dict) or set(source) != {
        "schema",
        "locales",
        "windows_locales",
        "products",
    }:
        raise ValueError("Localization source has unknown or missing keys")
    if type(source["schema"]) is not int or source["schema"] != SCHEMA:
        raise ValueError(f"Unsupported localization schema: {source['schema']}")
    if source["locales"] != list(LOCALES):
        raise ValueError("Localization locales or locale order differ")
    if source["windows_locales"] != list(WINDOWS_ONLY_LOCALES):
        raise ValueError("Windows-only localization locales or order differ")

    platform_catalog = platform_catalog or windows_catalog()
    windows_ids = {entry["id"] for entry in platform_catalog}

    catalog_ids = [entry["id"] for entry in catalog]
    products = source["products"]
    if not isinstance(products, list):
        raise ValueError("Localization products must be an array")
    if any(not isinstance(product, dict) for product in products):
        raise ValueError("Localization products must contain objects")
    localization_ids = [product.get("id") for product in products]
    if localization_ids != catalog_ids:
        raise ValueError("Localization products or product order differ")

    for entry, product in zip(catalog, products):
        expected_keys = {
            "id",
            "localizations",
        }
        if entry["id"] in windows_ids:
            expected_keys.add("windows_localizations")
        if not isinstance(product, dict) or set(product) != expected_keys:
            raise ValueError(
                f"Localization product has unknown or missing keys: {entry['id']}"
            )
        translations = product["localizations"]
        if (
            not isinstance(translations, dict)
            or list(translations) != list(LOCALES)
        ):
            raise ValueError(f"Locales differ: {entry['id']}")

        for locale, translation in translations.items():
            validate_translation(translation, FIELDS, entry["id"], locale)
            if len(translation["display_name"]) > 30:
                raise ValueError(
                    f"Display name exceeds 30 characters: "
                    f"{entry['id']} ({locale})"
                )
            if len(translation["iap_description"]) > 45:
                raise ValueError(
                    f"IAP description exceeds 45 characters: "
                    f"{entry['id']} ({locale})"
                )

        korean = translations["ko"]
        if korean["display_name"] != entry["name"]:
            raise ValueError(f"Korean catalog name differs: {entry['id']}")
        if (
            korean["iap_description"] != entry["description"]
            or korean["marketing_description"] != entry["description"]
        ):
            raise ValueError(
                f"Korean catalog description differs: {entry['id']}"
            )

        if entry["id"] in windows_ids:
            windows_translations = product["windows_localizations"]
            if (
                not isinstance(windows_translations, dict)
                or list(windows_translations) != list(WINDOWS_ONLY_LOCALES)
            ):
                raise ValueError(f"Windows locales differ: {entry['id']}")
            for locale, translation in windows_translations.items():
                validate_translation(
                    translation,
                    WINDOWS_FIELDS,
                    entry["id"],
                    locale,
                )

    return source


def products_by_id(source):
    """Index validated localization products by logical product ID."""

    return {product["id"]: product for product in source["products"]}


def app_store_display_name(product_id, locale, display_name, kind):
    """Return a deterministic App Store-safe IAP display name."""

    name = display_name
    if len(name) < 2:
        name += IAP_NAME_SUFFIXES[kind][locale]
    if not 2 <= len(name) <= 30:
        raise ValueError(
            f"Exported IAP display name length differs: "
            f"{product_id} ({locale})"
        )
    return name


def macos_payload(catalog, source):
    """Build native bundle metadata keyed by logical product ID."""

    localized = products_by_id(source)
    return {
        "schema": CONSUMER_SCHEMA,
        "locales": list(LOCALES),
        "products": [
            {
                "id": entry["id"],
                "app_store_product_id": entry["app_store_product_id"],
                "localizations": localized[entry["id"]]["localizations"],
            }
            for entry in catalog
        ],
    }


def web_payload(catalog, source):
    """Build web display and marketing metadata by locale and product ID."""

    localized = products_by_id(source)
    return {
        "schema": CONSUMER_SCHEMA,
        "locales": {
            locale: {
                entry["id"]: {
                    "display_name": localized[entry["id"]]["localizations"][
                        locale
                    ]["display_name"],
                    "marketing_description": localized[entry["id"]][
                        "localizations"
                    ][locale]["marketing_description"],
                }
                for entry in catalog
            }
            for locale in LOCALES
        },
    }


def iap_payload(catalog, source, locale_codes):
    """Build current, sellable IAP metadata without legacy restore IDs."""

    localized = products_by_id(source)
    products = []
    for entry in catalog:
        translations = localized[entry["id"]]["localizations"]
        products.append(
            {
                "product_id": entry["app_store_product_id"],
                "logical_product_id": entry["id"],
                "localizations": [
                    {
                        "locale": locale_codes[locale],
                        "display_name": app_store_display_name(
                            entry["id"],
                            locale,
                            translations[locale]["display_name"],
                            entry["kind"],
                        ),
                        "description": translations[locale][
                            "iap_description"
                        ],
                    }
                    for locale in LOCALES
                ],
            }
        )
    return {"schema": CONSUMER_SCHEMA, "products": products}


def windows_name_key(product_id):
    """Return the existing Windows resource key for one product name."""

    return WINDOWS_CHARACTER_NAME_KEYS.get(
        product_id,
        f"store.product.{product_id}",
    )


def windows_overlays(catalog, source, platform_catalog=None):
    """Build flat commerce-owned Windows resources by canonical locale."""

    platform_catalog = platform_catalog or windows_catalog()
    validate_source(catalog, source, platform_catalog)
    localized = products_by_id(source)
    output = {locale: {} for locale in WINDOWS_LOCALES}
    for entry in platform_catalog:
        product = localized[entry["id"]]
        for locale in WINDOWS_LOCALES:
            translations = (
                product["localizations"][locale]
                if locale in LOCALES
                else product["windows_localizations"][locale]
            )
            output[locale][windows_name_key(entry["id"])] = translations[
                "display_name"
            ]
            output[locale][
                f"store.productDescriptions.{entry['id']}"
            ] = translations["marketing_description"]
    return output


def windows_payload(catalog, source):
    """Build the canonical flat overlay consumed by the UI generator."""

    overlays = windows_overlays(catalog, source)
    return {
        "schema": CONSUMER_SCHEMA,
        "locales": {
            WINDOWS_LOCALES[locale]: values
            for locale, values in overlays.items()
        },
    }


def generated(catalog, source, consumer):
    """Return one consumer's deterministic JSON payload as UTF-8 bytes."""

    validate_source(catalog, source)
    if consumer == "macos":
        payload = macos_payload(catalog, source)
    elif consumer == "web":
        payload = web_payload(catalog, source)
    elif consumer == "storekit":
        payload = iap_payload(catalog, source, STOREKIT_LOCALES)
    elif consumer == "app-store":
        payload = iap_payload(catalog, source, APP_STORE_LOCALES)
    elif consumer == "windows":
        payload = windows_payload(catalog, source)
    else:
        raise ValueError(f"Unknown localization consumer: {consumer}")
    return (json.dumps(payload, ensure_ascii=False, indent=2) + "\n").encode()


def parse_args(argv=None):
    """Parse command-line arguments."""

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--consumer",
        choices=CONSUMERS,
        help="Print a deterministic consumer payload after validation",
    )
    return parser.parse_args(argv)


def main(argv=None):
    """Validate the source and optionally print a generated payload."""

    args = parse_args(argv)
    catalog = read_json(ROOT / CATALOG)
    source = read_json(ROOT / LOCALIZATIONS)
    validate_source(catalog, source)
    if args.consumer:
        sys.stdout.buffer.write(generated(catalog, source, args.consumer))
    else:
        legacy_ids = sum(
            len(entry["legacy_app_store_product_ids"])
            for entry in catalog
        )
        print(
            f"{len(catalog)} products, {len(LOCALES)} locales and "
            f"{legacy_ids} restore-only Apple IDs verified"
        )


if __name__ == "__main__":
    try:
        main()
    except (TypeError, ValueError, KeyError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
