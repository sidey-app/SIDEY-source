#!/usr/bin/env python3
"""Validate and export SIDEY's canonical native UI localizations."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
from typing import Any

import commerce_localizations as commerce


ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path("assets/v1/ui-localizations.json")
SCHEMA = 1
CANONICAL_LOCALES = ("ko", "en", "ja", "zh-Hans", "zh-Hant", "uk", "ru")
CONSUMERS = {
    "macos": {
        "locales": {"ko": "ko", "en": "en", "ja": "ja", "zh-Hant": "zh-Hant"},
        "output": Path("macos/SIDEY/Resources/Localizable.xcstrings"),
    },
    "windows": {
        "locales": {
            "ko": "ko-KR",
            "en": "en-US",
            "ja": "ja-JP",
            "zh-Hans": "zh-CN",
            "zh-Hant": "zh-TW",
            "uk": "uk-UA",
            "ru": "ru-RU",
        },
        "output": Path("windows/src/Sidey.App/Langs"),
    },
}
SEMANTIC_KEY = re.compile(r"^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+$")
PRINTF_TOKEN = re.compile(r"%(?:(?P<position>[1-9][0-9]*)\$)?(?P<kind>lld|ld|d|@)")
DOTNET_TOKEN = re.compile(r"\{(?P<position>[0-9]+)(?::(?P<format>[^{}]+))?\}")
HANGUL = re.compile(r"[\u1100-\u11ff\u3130-\u318f\uac00-\ud7af]")


class LocalizationError(ValueError):
    """Raised when the canonical catalog cannot be exported safely."""


def read_json(path: Path) -> Any:
    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        output: dict[str, Any] = {}
        for key, value in pairs:
            if key in output:
                raise LocalizationError(f"{path}: duplicate JSON key: {key}")
            output[key] = value
        return output

    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicates)


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def printf_signature(value: str) -> tuple[tuple[int, str], ...]:
    implicit = 1
    signature: list[tuple[int, str]] = []
    cursor = 0
    while cursor < len(value):
        percent = value.find("%", cursor)
        if percent < 0:
            break
        if percent + 1 < len(value) and value[percent + 1] == "%":
            cursor = percent + 2
            continue
        match = PRINTF_TOKEN.match(value, percent)
        if match is None:
            raise LocalizationError(
                f"unsupported or malformed printf placeholder at offset {percent}: {value!r}"
            )
        raw_position = match.group("position")
        position = int(raw_position) if raw_position else implicit
        if raw_position is None:
            implicit += 1
        signature.append((position, match.group("kind")))
        cursor = match.end()
    return tuple(sorted(signature))


def dotnet_signature(value: str) -> tuple[tuple[int, str], ...]:
    signature: list[tuple[int, str]] = []
    cursor = 0
    while cursor < len(value):
        character = value[cursor]
        if character == "{":
            if cursor + 1 < len(value) and value[cursor + 1] == "{":
                cursor += 2
                continue
            match = DOTNET_TOKEN.match(value, cursor)
            if match is None:
                raise LocalizationError(
                    f"unsupported or malformed .NET placeholder at offset {cursor}: {value!r}"
                )
            signature.append((int(match.group("position")), match.group("format") or ""))
            cursor = match.end()
            continue
        if character == "}":
            if cursor + 1 < len(value) and value[cursor + 1] == "}":
                cursor += 2
                continue
            raise LocalizationError(
                f"unescaped closing brace at offset {cursor}: {value!r}"
            )
        cursor += 1
    return tuple(sorted(signature))


def mac_values(localization: Any, label: str) -> list[str]:
    if not isinstance(localization, dict):
        raise LocalizationError(f"{label}: macOS localization must be an object")
    if set(localization) == {"stringUnit"}:
        unit = localization["stringUnit"]
        if not isinstance(unit, dict) or set(unit) != {"state", "value"}:
            raise LocalizationError(f"{label}: invalid stringUnit")
        if unit["state"] != "translated" or not isinstance(unit["value"], str) or not unit["value"]:
            raise LocalizationError(f"{label}: invalid translated value")
        return [unit["value"]]
    if set(localization) == {"variations"}:
        variations = localization["variations"]
        if not isinstance(variations, dict) or set(variations) != {"plural"}:
            raise LocalizationError(f"{label}: only plural variations are supported")
        plural = variations["plural"]
        if not isinstance(plural, dict) or set(plural) != {"one", "other"}:
            raise LocalizationError(f"{label}: plural requires one and other")
        values: list[str] = []
        for category in ("one", "other"):
            unit = plural[category]
            if not isinstance(unit, dict) or set(unit) != {"stringUnit"}:
                raise LocalizationError(f"{label}: invalid plural category {category}")
            values.extend(mac_values(unit, f"{label}.{category}"))
        return values
    raise LocalizationError(f"{label}: unsupported macOS localization shape")


def validate_localizations(
    entry: Any,
    locales: tuple[str, ...],
    label: str,
    consumer: str,
) -> None:
    if not isinstance(entry, dict) or set(entry) != {"localizations"}:
        raise LocalizationError(f"{label}: entry must contain only localizations")
    localizations = entry["localizations"]
    if not isinstance(localizations, dict) or tuple(localizations) != locales:
        raise LocalizationError(f"{label}: locale set or order differs")
    signatures: dict[str, tuple[Any, ...]] = {}
    for locale, localization in localizations.items():
        if consumer == "macos":
            values = mac_values(localization, f"{label}.{locale}")
            if locale != "ko" and any(HANGUL.search(value) for value in values):
                raise LocalizationError(f"{label}.{locale}: untranslated Hangul remains")
            variants = {printf_signature(value) for value in values}
            if len(variants) != 1:
                raise LocalizationError(f"{label}.{locale}: plural placeholders differ")
            signatures[locale] = next(iter(variants))
        else:
            if not isinstance(localization, str) or not localization:
                raise LocalizationError(f"{label}.{locale}: value must be non-empty")
            if locale != "ko" and HANGUL.search(localization):
                raise LocalizationError(f"{label}.{locale}: untranslated Hangul remains")
            signatures[locale] = dotnet_signature(localization)
    if len(set(signatures.values())) != 1:
        raise LocalizationError(f"{label}: placeholders differ by locale: {signatures}")


def validate_shared(entry: Any, label: str) -> None:
    if not isinstance(entry, dict) or set(entry) != {"localizations"}:
        raise LocalizationError(f"{label}: entry must contain only localizations")
    localizations = entry["localizations"]
    if not isinstance(localizations, dict) or tuple(localizations) != CANONICAL_LOCALES:
        raise LocalizationError(f"{label}: shared locale set or order differs")
    if any(not isinstance(value, str) or not value for value in localizations.values()):
        raise LocalizationError(f"{label}: shared values must be non-empty strings")
    for locale, value in localizations.items():
        if locale != "ko" and HANGUL.search(value):
            raise LocalizationError(f"{label}.{locale}: untranslated Hangul remains")
    signatures = {locale: dotnet_signature(value) for locale, value in localizations.items()}
    if len(set(signatures.values())) != 1:
        raise LocalizationError(f"{label}: shared placeholders differ: {signatures}")
    if next(iter(signatures.values())):
        raise LocalizationError(f"{label}: formatted shared messages require platform-specific entries")


def validate_source(source: Any) -> None:
    expected = {"schema", "canonical_locales", "consumers", "shared", "macos", "windows"}
    if not isinstance(source, dict) or set(source) != expected:
        raise LocalizationError("Canonical source has unknown or missing keys")
    if source["schema"] != SCHEMA:
        raise LocalizationError(f"Unsupported UI localization schema: {source['schema']}")
    if tuple(source["canonical_locales"]) != CANONICAL_LOCALES:
        raise LocalizationError("Canonical locale set or order differs")
    if source["consumers"] != {
        "macos": {"locales": list(CONSUMERS["macos"]["locales"])},
        "windows": {"locales": list(CONSUMERS["windows"]["locales"])},
    }:
        raise LocalizationError("Consumer locale contract differs")
    sections = {name: source[name] for name in ("shared", "macos", "windows")}
    if any(not isinstance(section, dict) for section in sections.values()):
        raise LocalizationError("Localization sections must be objects")
    if set(sections["shared"]) & (set(sections["macos"]) | set(sections["windows"])):
        raise LocalizationError("Shared output keys must not be duplicated by platform sections")
    commerce_keys = set(next(iter(commerce_windows_overlays().values())))
    duplicated_commerce = commerce_keys & (
        set(sections["shared"]) | set(sections["windows"])
    )
    if duplicated_commerce:
        raise LocalizationError(
            f"Windows commerce keys must be owned by the commerce source: "
            f"{sorted(duplicated_commerce)}"
        )
    for key, entry in sections["shared"].items():
        if SEMANTIC_KEY.fullmatch(key) is None:
            raise LocalizationError(f"Invalid shared output key: {key}")
        validate_shared(entry, f"shared.{key}")
    for key, entry in sections["macos"].items():
        if SEMANTIC_KEY.fullmatch(key) is None:
            raise LocalizationError(f"Invalid macOS output key: {key}")
        validate_localizations(entry, tuple(CONSUMERS["macos"]["locales"]), f"macos.{key}", "macos")
    for key, entry in sections["windows"].items():
        if SEMANTIC_KEY.fullmatch(key) is None:
            raise LocalizationError(f"Invalid Windows output key: {key}")
        validate_localizations(entry, tuple(CONSUMERS["windows"]["locales"]), f"windows.{key}", "windows")


def mac_shared_localization(value: str) -> dict[str, Any]:
    return {"stringUnit": {"state": "translated", "value": value}}


def render_macos(source: dict[str, Any]) -> bytes:
    strings: dict[str, Any] = {}
    locale_map = CONSUMERS["macos"]["locales"]
    for key, entry in source["shared"].items():
        strings[key] = {
            "extractionState": "manual",
            "localizations": {
                output_locale: mac_shared_localization(entry["localizations"][canonical_locale])
                for canonical_locale, output_locale in locale_map.items()
            },
        }
    for key, entry in source["macos"].items():
        strings[key] = {
            "extractionState": "manual",
            "localizations": {
                locale_map[canonical_locale]: localization
                for canonical_locale, localization in entry["localizations"].items()
            },
        }
    return json_bytes({"sourceLanguage": "en", "strings": dict(sorted(strings.items())), "version": "1.0"})


def assign_nested(root: dict[str, Any], dotted_key: str, value: str) -> None:
    parts = dotted_key.split(".")
    if not parts or any(not part for part in parts):
        raise LocalizationError(f"Invalid Windows output key: {dotted_key}")
    current = root
    for part in parts[:-1]:
        existing = current.setdefault(part, {})
        if not isinstance(existing, dict):
            raise LocalizationError(f"Windows key prefix collision: {dotted_key}")
        current = existing
    if parts[-1] in current:
        raise LocalizationError(f"Duplicate Windows output key: {dotted_key}")
    current[parts[-1]] = value


def commerce_windows_overlays() -> dict[str, dict[str, str]]:
    catalog = commerce.read_json(commerce.ROOT / commerce.CATALOG)
    source = commerce.read_json(commerce.ROOT / commerce.LOCALIZATIONS)
    return commerce.windows_overlays(catalog, source)


def render_windows(
    source: dict[str, Any],
    commerce_overlays: dict[str, dict[str, str]] | None = None,
) -> dict[str, bytes]:
    rendered: dict[str, bytes] = {}
    locale_map = CONSUMERS["windows"]["locales"]
    commerce_overlays = commerce_overlays or commerce_windows_overlays()
    for canonical_locale, output_locale in locale_map.items():
        catalog: dict[str, Any] = {}
        for key, entry in source["shared"].items():
            assign_nested(catalog, key, entry["localizations"][canonical_locale])
        for key, entry in source["windows"].items():
            assign_nested(catalog, key, entry["localizations"][canonical_locale])
        for key, value in commerce_overlays[canonical_locale].items():
            assign_nested(catalog, key, value)
        rendered[f"{output_locale}.json"] = json_bytes(catalog)
    return rendered


def expected_outputs(source: dict[str, Any], consumer: str, output_root: Path) -> dict[Path, bytes]:
    outputs: dict[Path, bytes] = {}
    if consumer in {"macos", "all"}:
        outputs[output_root / CONSUMERS["macos"]["output"]] = render_macos(source)
    if consumer in {"windows", "all"}:
        directory = output_root / CONSUMERS["windows"]["output"]
        outputs.update({directory / name: data for name, data in render_windows(source).items()})
    return outputs


def write_outputs(outputs: dict[Path, bytes]) -> None:
    for path, data in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)


def check_outputs(outputs: dict[Path, bytes]) -> list[Path]:
    stale = [path for path, data in outputs.items() if not path.is_file() or path.read_bytes() != data]
    expected_windows = {
        path for path in outputs if path.parent.name == CONSUMERS["windows"]["output"].name
    }
    if expected_windows:
        directory = next(iter(expected_windows)).parent
        if directory.is_dir():
            stale.extend(sorted(set(directory.glob("*.json")) - expected_windows))
    return stale


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--consumer", choices=("macos", "windows", "all"), required=True)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--write", action="store_true")
    action.add_argument("--check", action="store_true")
    parser.add_argument("--source", type=Path, default=ROOT / SOURCE)
    parser.add_argument("--output-root", type=Path, default=ROOT)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    source = read_json(args.source)
    validate_source(source)
    outputs = expected_outputs(source, args.consumer, args.output_root)
    if args.write:
        write_outputs(outputs)
        return 0
    stale = check_outputs(outputs)
    if stale:
        for path in stale:
            print(f"stale UI localization output: {path}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
