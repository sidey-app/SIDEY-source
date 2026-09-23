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


ROOT = Path(__file__).resolve().parents[1]
CATALOG = "assets/v1/commerce-catalog.json"
LOCALIZATIONS = "assets/v1/commerce-localizations.json"

SCHEMA = 1
LOCALES = ("ko", "en", "ja", "zh-Hant")
FIELDS = (
    "display_name",
    "iap_description",
    "marketing_description",
)
CONSUMERS = ("macos", "web", "storekit", "app-store")

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

    return json.loads(path.read_text(encoding="utf-8"))


def validate_source(catalog, source):
    """Validate completeness, ordering and legacy Korean compatibility."""

    if not isinstance(source, dict) or set(source) != {
        "schema",
        "locales",
        "products",
    }:
        raise ValueError("Localization source has unknown or missing keys")
    if type(source["schema"]) is not int or source["schema"] != SCHEMA:
        raise ValueError(f"Unsupported localization schema: {source['schema']}")
    if source["locales"] != list(LOCALES):
        raise ValueError("Localization locales or locale order differ")

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
        if not isinstance(product, dict) or set(product) != {
            "id",
            "localizations",
        }:
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
            if (
                not isinstance(translation, dict)
                or list(translation) != list(FIELDS)
            ):
                raise ValueError(
                    f"Fields or field order differ: {entry['id']} ({locale})"
                )
            for field, value in translation.items():
                if (
                    not isinstance(value, str)
                    or not value
                    or value != value.strip()
                    or "\n" in value
                    or "\r" in value
                ):
                    raise ValueError(
                        f"Invalid {field}: {entry['id']} ({locale})"
                    )
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
        "schema": SCHEMA,
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
        "schema": SCHEMA,
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
    return {"schema": SCHEMA, "products": products}


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
