#!/usr/bin/env python3
"""Validate SIDEY's shipped macOS localization contract."""

from __future__ import annotations

from collections import Counter
import json
from pathlib import Path
import re
from typing import Any, Iterator


ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "macos" / "SIDEY" / "Resources" / "Localizable.xcstrings"
SOURCE_ROOT = ROOT / "macos" / "SIDEY"
SUPPORTED_LOCALES = ("en", "ko", "ja", "zh-Hant")
SEMANTIC_KEY = re.compile(r"^[a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+$")
LOCALIZATION_CALL = re.compile(
    r'(?:L10n\.(?:text|format)|Text|Button|Toggle|Label|TextField|SecureField|'
    r'navigationTitle|accessibilityLabel|accessibilityHint|help|confirmationDialog)'
    r'\(\s*"([a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+)"'
)
RESOURCE_LITERAL = re.compile(
    r'(?:LocalizedStringResource\s*=|->\s*LocalizedStringResource\s*\{)'
    r'[^\n]{0,200}?"([a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+)"'
)
PLACEHOLDER = re.compile(r"%(?:(\d+)\$)?([@dDuUxXoOfFeEgGcCsSp])")
HANGUL = re.compile(r"[가-힣]")
DEBUG_HANGUL_ALLOWLIST = {
    "Features/PixelWorld/CharacterFeedbackDebugRoom.swift",
    "Features/Store/StoreReviewDebugWindow.swift",
}


class LocalizationError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise LocalizationError(message)


def _string_units(value: Any, context: str) -> Iterator[str]:
    require(isinstance(value, dict), f"{context} must be an object")
    if "stringUnit" in value:
        unit = value["stringUnit"]
        require(isinstance(unit, dict), f"{context}.stringUnit must be an object")
        require(unit.get("state") == "translated", f"{context} is not translated")
        text = unit.get("value")
        require(isinstance(text, str) and text.strip(), f"{context} is empty")
        yield text
        return
    variations = value.get("variations")
    require(isinstance(variations, dict) and variations, f"{context} has no string value")
    plural = variations.get("plural")
    require(isinstance(plural, dict) and "other" in plural, f"{context} needs plural.other")
    for category, child in plural.items():
        yield from _string_units(child, f"{context}.plural.{category}")


def _placeholder_signature(value: str) -> Counter[str]:
    return Counter(match.group(2).lower() for match in PLACEHOLDER.finditer(value))


def load_and_validate_catalog(path: Path = CATALOG) -> dict[str, Any]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise LocalizationError(f"Cannot read String Catalog {path}: {error}") from error
    require(document.get("sourceLanguage") == "en", "String Catalog sourceLanguage must be en")
    require(document.get("version") == "1.0", "String Catalog version must be 1.0")
    strings = document.get("strings")
    require(isinstance(strings, dict) and strings, "String Catalog must contain strings")

    for key, entry in strings.items():
        require(SEMANTIC_KEY.fullmatch(key) is not None, f"Non-semantic localization key: {key}")
        require(isinstance(entry, dict), f"{key} must be an object")
        localizations = entry.get("localizations")
        require(
            isinstance(localizations, dict)
            and set(localizations) == set(SUPPORTED_LOCALES),
            f"{key} must contain exactly {', '.join(SUPPORTED_LOCALES)}",
        )
        values = {
            locale: list(_string_units(localizations[locale], f"{key}.{locale}"))
            for locale in SUPPORTED_LOCALES
        }
        uses_plural = {
            locale: "variations" in localizations[locale] for locale in SUPPORTED_LOCALES
        }
        require(
            len(set(uses_plural.values())) == 1,
            f"{key} mixes plural and non-plural localizations",
        )
        reference_signatures = [_placeholder_signature(value) for value in values["en"]]
        reference = reference_signatures[0]
        require(
            all(signature == reference for signature in reference_signatures),
            f"{key}.en plural placeholders differ",
        )
        for locale, localized_values in values.items():
            for value in localized_values:
                require(
                    _placeholder_signature(value) == reference,
                    f"{key}.{locale} placeholder types differ from English",
                )
    return strings


def referenced_keys(source_root: Path = SOURCE_ROOT) -> set[str]:
    keys: set[str] = set()
    for path in source_root.rglob("*.swift"):
        source = path.read_text(encoding="utf-8")
        keys.update(LOCALIZATION_CALL.findall(source))
        keys.update(RESOURCE_LITERAL.findall(source))
    return keys


def validate_key_coverage(strings: dict[str, Any]) -> None:
    referenced = referenced_keys()
    catalog_keys = set(strings)
    missing = sorted(referenced - catalog_keys)
    stale = sorted(
        key
        for key in catalog_keys - referenced
        if not any(key in path.read_text(encoding="utf-8") for path in SOURCE_ROOT.rglob("*.swift"))
    )
    require(not missing, f"Missing localization keys: {missing}")
    require(not stale, f"Stale localization keys: {stale}")


def _swift_string_literals(source: str) -> Iterator[tuple[int, str]]:
    """Yield ordinary Swift string literals while skipping line and block comments."""

    index = 0
    line = 1
    length = len(source)
    while index < length:
        if source.startswith("//", index):
            end = source.find("\n", index)
            index = length if end == -1 else end
            continue
        if source.startswith("/*", index):
            end = source.find("*/", index + 2)
            segment = source[index:] if end == -1 else source[index : end + 2]
            line += segment.count("\n")
            index = length if end == -1 else end + 2
            continue
        if source[index] == '"':
            start_line = line
            index += 1
            value: list[str] = []
            while index < length:
                character = source[index]
                if character == "\\" and index + 1 < length:
                    value.extend((character, source[index + 1]))
                    index += 2
                    continue
                if character == '"':
                    index += 1
                    break
                if character == "\n":
                    line += 1
                value.append(character)
                index += 1
            yield start_line, "".join(value)
            continue
        if source[index] == "\n":
            line += 1
        index += 1


def validate_no_shipped_hangul(source_root: Path = SOURCE_ROOT) -> None:
    violations: list[str] = []
    for path in source_root.rglob("*.swift"):
        relative = path.relative_to(source_root).as_posix()
        if relative in DEBUG_HANGUL_ALLOWLIST:
            continue
        for line, value in _swift_string_literals(path.read_text(encoding="utf-8")):
            if HANGUL.search(value):
                violations.append(f"{relative}:{line}")
    require(not violations, "Shipped Swift contains Hangul literals: " + ", ".join(violations))


def validate_project_regions() -> None:
    project = (ROOT / "macos" / "SIDEY.xcodeproj" / "project.pbxproj").read_text(
        encoding="utf-8"
    )
    require("developmentRegion = en;" in project, "Xcode developmentRegion must be en")
    known = re.search(r"knownRegions = \((.*?)\);", project, re.DOTALL)
    require(known is not None, "Xcode knownRegions is missing")
    values = {value.strip().strip('"') for value in known.group(1).split(",") if value.strip()}
    require(set(SUPPORTED_LOCALES) <= values, "Xcode knownRegions lacks a supported locale")


def main() -> int:
    strings = load_and_validate_catalog()
    validate_key_coverage(strings)
    validate_no_shipped_hangul()
    validate_project_regions()
    print(
        f"Validated {len(strings)} macOS localization keys across "
        f"{', '.join(SUPPORTED_LOCALES)}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
