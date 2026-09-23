#!/usr/bin/env python3
"""Synchronize macOS commerce localization artifacts from the shared source."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = ROOT / "assets/v1/commerce-catalog.json"
SOURCE_PATH = ROOT / "assets/v1/commerce-localizations.json"
BUNDLE_PATH = ROOT / "macos/SIDEY/Resources/Commerce/commerce-localizations.json"
STOREKIT_PATH = ROOT / "macos/SIDEYAppStore.storekit"


def load_shared_exporter():
    if str(ROOT) not in sys.path:
        sys.path.insert(0, str(ROOT))
    from scripts import commerce_localizations

    return commerce_localizations


def encoded(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()


def expected_artifacts() -> tuple[bytes, bytes]:
    exporter = load_shared_exporter()
    catalog = exporter.read_json(CATALOG_PATH)
    source = exporter.read_json(SOURCE_PATH)
    exporter.validate_source(catalog, source)

    bundle = exporter.generated(catalog, source, "macos")
    storekit_export = json.loads(
        exporter.generated(catalog, source, "storekit")
    )
    expected_current = {
        product["product_id"]: product for product in storekit_export["products"]
    }
    legacy_ids = {
        product_id
        for entry in catalog
        for product_id in entry["legacy_app_store_product_ids"]
    }
    if set(expected_current) & legacy_ids:
        raise ValueError("Current and restore-only StoreKit IDs overlap")
    if len(expected_current) != 33 or len(legacy_ids) != 10:
        raise ValueError("Expected 33 current and 10 restore-only StoreKit IDs")

    storekit = json.loads(STOREKIT_PATH.read_text(encoding="utf-8"))
    records = storekit.get("products")
    if not isinstance(records, list):
        raise ValueError("StoreKit products must be an array")
    actual_ids = [record.get("productID") for record in records]
    if len(actual_ids) != len(set(actual_ids)):
        raise ValueError("StoreKit product IDs must be unique")
    if set(actual_ids) != set(expected_current) | legacy_ids:
        raise ValueError("StoreKit product IDs differ from current and restore-only IDs")

    for record in records:
        exported = expected_current.get(record["productID"])
        if exported is None:
            continue
        record["localizations"] = [
            {
                "description": localization["description"],
                "displayName": localization["display_name"],
                "locale": localization["locale"],
            }
            for localization in exported["localizations"]
        ]

    return bundle, encoded(storekit)


def check_or_write(write: bool) -> None:
    expected_bundle, expected_storekit = expected_artifacts()
    artifacts = (
        (BUNDLE_PATH, expected_bundle),
        (STOREKIT_PATH, expected_storekit),
    )
    stale: list[str] = []
    for path, expected in artifacts:
        if write:
            path.write_bytes(expected)
        elif not path.exists() or path.read_bytes() != expected:
            stale.append(str(path.relative_to(ROOT)))
    if stale:
        raise ValueError(
            "Generated commerce localization artifacts are stale: "
            + ", ".join(stale)
            + ". Run scripts/macos/sync_commerce_localizations.py --write"
        )


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--write",
        action="store_true",
        help="Rewrite generated macOS bundle and StoreKit artifacts",
    )
    args = parser.parse_args(argv)
    check_or_write(args.write)


if __name__ == "__main__":
    try:
        main()
    except (KeyError, TypeError, ValueError, RuntimeError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
