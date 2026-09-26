#!/usr/bin/env python3
"""Validate and export the canonical commerce localization source.

The source keeps logical product names identical to the Korean legacy catalog.
App Store Connect requires IAP display names to contain at least two characters.
Exports use the approved Korean name 똥이 for character_poop and a localized,
kind-based suffix for other names shorter than that limit. The source value
itself is never rewritten.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

try:
    from catalog_source import load_source, supported_catalog
except ModuleNotFoundError:  # Support `python -m scripts...` package imports.
    from .catalog_source import load_source, supported_catalog


ROOT = Path(__file__).resolve().parents[1]
CATALOG = Path("assets/v1/commerce-catalog.json")
LOCALIZATIONS = Path("assets/v1/locale/commerce")

SCHEMA = 2
CONSUMER_SCHEMA = 1
IAP_DISPLAY_NAME_LIMIT = 30
IAP_DESCRIPTION_LIMIT = 45
LOCALES = ("ko", "en", "ja", "zh-Hant")
WINDOWS_ONLY_LOCALES = (
    "zh-Hans", "uk", "ru", "it", "pt-PT", "es", "cs", "tr", "ro",
    "bg", "pt-BR", "sr-Cyrl", "pl", "sr-Latn", "nl-BE", "fr", "nl",
    "he", "de",
)
FIELDS = (
    "display_name",
    "description",
)
IAP_FIELDS = (*FIELDS, "iap_description")
CONSUMERS = ("macos", "web", "storekit", "app-store", "windows")

WINDOWS_LOCALES = {
    "ko": "ko-KR",
    "en": "en-US",
    "ja": "ja-JP",
    "zh-Hans": "zh-CN",
    "zh-Hant": "zh-TW",
    "uk": "uk-UA",
    "ru": "ru-RU",
    "it": "it-IT",
    "pt-PT": "pt-PT",
    "es": "es-ES",
    "cs": "cs-CZ",
    "tr": "tr-TR",
    "ro": "ro-RO",
    "bg": "bg-BG",
    "pt-BR": "pt-BR",
    "sr-Cyrl": "sr-Cyrl-RS",
    "pl": "pl-PL",
    "sr-Latn": "sr-Latn-RS",
    "nl-BE": "nl-BE",
    "fr": "fr-FR",
    "nl": "nl-NL",
    "he": "he-IL",
    "de": "de-DE",
}
WINDOWS_FIELDS = IAP_FIELDS
HANGUL = re.compile(r"[\u1100-\u11ff\u3130-\u318f\uac00-\ud7af]")

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


def read_source(directory: Path | None = None):
    """Load per-locale commerce files into the validated consumer model."""

    directory = directory or ROOT / LOCALIZATIONS
    locales = LOCALES + WINDOWS_ONLY_LOCALES
    expected_files = {directory / f"{locale}.json" for locale in locales}
    actual_files = set(directory.glob("*.json")) if directory.is_dir() else set()
    if actual_files != expected_files:
        missing = sorted(path.name for path in expected_files - actual_files)
        extra = sorted(path.name for path in actual_files - expected_files)
        raise ValueError(
            f"Commerce locale files differ: missing={missing}, extra={extra}"
        )

    documents = {locale: read_json(directory / f"{locale}.json") for locale in locales}
    if any(not isinstance(document, dict) for document in documents.values()):
        raise ValueError("Commerce locale files must contain objects")

    product_ids = list(documents[LOCALES[0]])
    for locale in LOCALES[1:]:
        if list(documents[locale]) != product_ids:
            raise ValueError(f"Commerce product order differs: {locale}")

    windows_ids = list(documents[WINDOWS_ONLY_LOCALES[0]])
    for locale in WINDOWS_ONLY_LOCALES[1:]:
        if list(documents[locale]) != windows_ids:
            raise ValueError(f"Windows commerce product order differs: {locale}")
    unknown_windows_ids = sorted(set(windows_ids) - set(product_ids))
    if unknown_windows_ids:
        raise ValueError(
            f"Windows commerce files contain unknown products: {unknown_windows_ids}"
        )

    products = []
    windows_id_set = set(windows_ids)
    for product_id in product_ids:
        product = {
            "id": product_id,
            "localizations": {
                locale: documents[locale][product_id]
                for locale in LOCALES
            },
        }
        if product_id in windows_id_set:
            product["windows_localizations"] = {
                locale: documents[locale][product_id]
                for locale in WINDOWS_ONLY_LOCALES
            }
        products.append(product)

    return {
        "schema": SCHEMA,
        "locales": list(LOCALES),
        "windows_locales": list(WINDOWS_ONLY_LOCALES),
        "products": products,
    }


def windows_catalog():
    """Return the exact reviewed catalog subset supported by Windows."""

    catalog, manifest, _ = load_source(ROOT, "windows")
    return supported_catalog(catalog, manifest, "windows")


def canonical_windows_catalog(catalog):
    """Return products currently declared Windows-compatible by the source."""

    manifest = read_json(ROOT / "assets/v1/manifest.json")
    return supported_catalog(catalog, manifest, "windows")


def validate_translation(
    translation,
    fields,
    product_id,
    locale,
):
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
        if locale != "ko" and HANGUL.search(value):
            raise ValueError(
                f"Untranslated Hangul remains: {product_id} "
                f"({locale}.{field})"
            )
    if len(translation["display_name"]) > IAP_DISPLAY_NAME_LIMIT:
        raise ValueError(
            f"IAP display name exceeds {IAP_DISPLAY_NAME_LIMIT} characters: "
            f"{product_id} ({locale})"
        )
    if len(translation["iap_description"]) > IAP_DESCRIPTION_LIMIT:
        raise ValueError(
            f"IAP description exceeds {IAP_DESCRIPTION_LIMIT} characters: "
            f"{product_id} ({locale})"
        )
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
    # Translation handoff can precede the reviewed Windows mirror's source pin.
    # Require strings for both the staged canonical support and pinned exports.
    windows_ids = {entry["id"] for entry in platform_catalog}
    windows_ids.update(entry["id"] for entry in canonical_windows_catalog(catalog))

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
            validate_translation(
                translation,
                IAP_FIELDS,
                entry["id"],
                locale,
            )
            if len(translation["display_name"]) > 30:
                raise ValueError(
                    f"Display name exceeds 30 characters: "
                    f"{entry['id']} ({locale})"
                )
        korean = translations["ko"]
        if korean["display_name"] != entry["name"]:
            raise ValueError(f"Korean catalog name differs: {entry['id']}")
        if korean["description"] != entry["description"]:
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

    name = "똥이" if (product_id, locale) == ("character_poop", "ko") else display_name
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
                "localizations": {
                    locale: {
                        "display_name": translation["display_name"],
                        "description": translation["description"],
                    }
                    for locale, translation in localized[entry["id"]][
                        "localizations"
                    ].items()
                },
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
                    "description": localized[entry["id"]]["localizations"][
                        locale
                    ]["description"],
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
                        "description": translations[locale]["iap_description"],
                    }
                    for locale in LOCALES
                ],
            }
        )
    return {"schema": CONSUMER_SCHEMA, "products": products}


def windows_name_key(entry):
    """Return the shared character key or store product key for one product."""

    if entry["kind"] == "character":
        character_id = entry.get("character_id") or entry["item_id"]
        return f"character.{character_id}.display_name"
    return f"store.catalog.{entry['id']}.name"


def macos_character_overlays(catalog, source):
    """Build commerce-owned macOS character-name resources by canonical locale."""

    validate_source(catalog, source)
    localized = products_by_id(source)
    manifest = read_json(ROOT / "assets/v1/manifest.json")
    platform_catalog = supported_catalog(catalog, manifest, "macos")
    output = {locale: {} for locale in LOCALES}
    for entry in platform_catalog:
        if entry["kind"] != "character":
            continue
        character_id = entry.get("character_id") or entry["item_id"]
        key = f"character.{character_id}.display_name"
        product = localized[entry["id"]]
        for locale in LOCALES:
            output[locale][key] = product["localizations"][locale]["display_name"]
    return output


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
            output[locale][windows_name_key(entry)] = translations[
                "display_name"
            ]
            output[locale][
                f"store.catalog.{entry['id']}.description"
            ] = translations["description"]
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
    source = read_source()
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
