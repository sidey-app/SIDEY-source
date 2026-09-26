#!/usr/bin/env python3
"""Validate and export SIDEY's canonical native UI localizations."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
from typing import Any

try:
    import commerce_localizations as commerce
except ModuleNotFoundError:  # Support `python -m scripts...` package imports.
    from . import commerce_localizations as commerce


ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path("assets/v1/ui-localizations.json")
LOCALE_ROOT = Path("assets/v1/locale/client")
INTERNAL_LOCALE_ROOT = Path("assets/v1/locale/internal")
SCHEMA = 2
CANONICAL_LOCALES = (
    "ko", "en", "ja", "zh-Hans", "zh-Hant", "uk", "ru",
    "it", "pt-PT", "es", "cs", "tr", "ro", "bg", "pt-BR",
    "sr-Cyrl", "pl", "sr-Latn", "nl-BE", "fr", "nl", "he", "de",
)
CONSUMERS = {
    "macos": {
        "locales": {"ko": "ko", "en": "en", "ja": "ja", "zh-Hant": "zh-Hant"},
        "output": Path("macos/SIDEY/Resources/Localizable.xcstrings"),
        "internal_output": Path("macos/SIDEY/Resources/InternalLocalizable.xcstrings"),
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
        },
        "output": Path("windows/src/Sidey.App/Langs"),
        "internal_output": Path("windows/src/Sidey.App/InternalLangs"),
    },
}
SEMANTIC_KEY = re.compile(r"^[a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+$")
NESTED_KEY_SEGMENT = re.compile(r"^[a-z][a-z0-9_]*$")
WINDOWS_NONFUNCTIONAL_ROOTS = frozenset(
    {
        "about", "backend", "dialogs", "error", "launcher", "navigation",
        "preferences", "preview", "unsupported", "window",
    }
)
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


def _mac_localization(value: Any, label: str) -> dict[str, Any]:
    if isinstance(value, str) and value:
        return {"stringUnit": {"state": "translated", "value": value}}
    if (
        isinstance(value, dict)
        and tuple(value) == ("one", "other")
        and all(isinstance(item, str) and item for item in value.values())
    ):
        return {
            "variations": {
                "plural": {
                    category: {
                        "stringUnit": {
                            "state": "translated",
                            "value": value[category],
                        }
                    }
                    for category in ("one", "other")
                }
            }
        }
    raise LocalizationError(f"{label}: macOS value must be a string or one/other plural")


def flatten_locale_tree(value: Any, label: str, consumer: str) -> dict[str, Any]:
    """Flatten nested locale objects while preserving explicit prefix values."""

    if not isinstance(value, dict):
        raise LocalizationError(f"{label}: localization section must be an object")
    output: dict[str, Any] = {}

    def add(path: str, raw: Any) -> None:
        if not path:
            raise LocalizationError(f"{label}: root value is not allowed")
        if path in output:
            raise LocalizationError(f"{label}: duplicate localization key: {path}")
        if consumer == "macos":
            output[path] = _mac_localization(raw, f"{label}.{path}")
        elif isinstance(raw, str) and raw:
            output[path] = raw
        else:
            raise LocalizationError(f"{label}.{path}: value must be a non-empty string")

    def visit(node: Any, prefix: str) -> None:
        if consumer == "macos" and isinstance(node, dict) and set(node) == {"one", "other"}:
            add(prefix, node)
            return
        if not isinstance(node, dict):
            add(prefix, node)
            return
        if not node and prefix:
            raise LocalizationError(f"{label}.{prefix}: empty object is not allowed")
        if "$value" in node:
            add(prefix, node["$value"])
        for key, child in node.items():
            if key == "$value":
                continue
            if (
                not isinstance(key, str)
                or NESTED_KEY_SEGMENT.fullmatch(key) is None
                or key == "platforms"
            ):
                raise LocalizationError(f"{label}: invalid nested key: {key!r}")
            path = f"{prefix}.{key}" if prefix else key
            visit(child, path)

    visit(value, "")
    return output


def read_source(
    metadata_path: Path | None = None,
    locale_root: Path | None = None,
) -> dict[str, Any]:
    """Load nested per-locale client files into the validated consumer model."""

    metadata_path = metadata_path or ROOT / SOURCE
    locale_root = locale_root or ROOT / LOCALE_ROOT
    metadata = read_json(metadata_path)
    if not isinstance(metadata, dict) or set(metadata) != {
        "schema",
        "canonical_locales",
        "consumers",
    }:
        raise LocalizationError("UI localization metadata has unknown or missing keys")
    if metadata["schema"] != SCHEMA:
        raise LocalizationError(f"Unsupported UI localization schema: {metadata['schema']}")
    if tuple(metadata["canonical_locales"]) != CANONICAL_LOCALES:
        raise LocalizationError("Canonical locale set or order differs")
    expected_consumers = {
        "macos": {"locales": list(CONSUMERS["macos"]["locales"])},
        "windows": {"locales": list(CONSUMERS["windows"]["locales"])},
    }
    if metadata["consumers"] != expected_consumers:
        raise LocalizationError("Consumer locale contract differs")

    expected_files = {locale_root / f"{locale}.json" for locale in CANONICAL_LOCALES}
    actual_files = set(locale_root.glob("*.json")) if locale_root.is_dir() else set()
    if actual_files != expected_files:
        missing = sorted(path.name for path in expected_files - actual_files)
        extra = sorted(path.name for path in actual_files - expected_files)
        raise LocalizationError(
            f"Client locale files differ: missing={missing}, extra={extra}"
        )

    shared_by_locale: dict[str, dict[str, Any]] = {}
    platform_by_locale: dict[str, dict[str, dict[str, Any]]] = {}
    for locale in CANONICAL_LOCALES:
        document = read_json(locale_root / f"{locale}.json")
        if not isinstance(document, dict) or "platforms" not in document:
            raise LocalizationError(f"{locale}: locale file must contain platforms")
        shared_by_locale[locale] = flatten_locale_tree(
            {key: value for key, value in document.items() if key != "platforms"},
            locale,
            "shared",
        )
        platforms = document["platforms"]
        if (
            not isinstance(platforms, dict)
            or set(platforms) != set(CONSUMERS)
        ):
            raise LocalizationError(
                f"{locale}: every client locale must contain all platforms"
            )
        windows = platforms.get("windows", {})
        nonfunctional_roots = WINDOWS_NONFUNCTIONAL_ROOTS & set(windows)
        if nonfunctional_roots:
            raise LocalizationError(
                f"{locale}: Windows localization uses nonfunctional roots: "
                f"{sorted(nonfunctional_roots)}"
            )
        platform_by_locale[locale] = {
            consumer: flatten_locale_tree(
                platforms[consumer],
                f"{locale}.platforms.{consumer}",
                consumer,
            )
            for consumer in platforms
        }

    shared_keys = tuple(shared_by_locale[CANONICAL_LOCALES[0]])
    for locale in CANONICAL_LOCALES[1:]:
        if tuple(shared_by_locale[locale]) != shared_keys:
            raise LocalizationError(f"{locale}: shared key set or order differs")

    source: dict[str, Any] = {
        **metadata,
        "shared": {
            key: {
                "localizations": {
                    locale: shared_by_locale[locale][key]
                    for locale in CANONICAL_LOCALES
                }
            }
            for key in shared_keys
        },
    }
    for consumer in CONSUMERS:
        locales = tuple(CONSUMERS[consumer]["locales"])
        keys = tuple(platform_by_locale[locales[0]][consumer])
        available_locales = tuple(
            locale
            for locale in CANONICAL_LOCALES
            if consumer in platform_by_locale[locale]
        )
        for locale in available_locales[1:]:
            if tuple(platform_by_locale[locale][consumer]) != keys:
                raise LocalizationError(
                    f"{locale}: {consumer} key set or order differs"
                )
        for locale in available_locales:
            if locale in locales:
                continue
            for key in keys:
                validate_localizations(
                    {
                        "localizations": {
                            locales[0]: platform_by_locale[locales[0]][consumer][key],
                            locale: platform_by_locale[locale][consumer][key],
                        }
                    },
                    (locales[0], locale),
                    f"{locale}.optional.{consumer}.{key}",
                    consumer,
                )
        source[consumer] = {
            key: {
                "localizations": {
                    locale: platform_by_locale[locale][consumer][key]
                    for locale in locales
                }
            }
            for key in keys
        }
    return source


def read_internal_source(locale_root: Path | None = None) -> dict[str, Any]:
    """Load development-only localizations kept out of production catalogs."""

    locale_root = locale_root or ROOT / INTERNAL_LOCALE_ROOT
    expected_files = {locale_root / f"{locale}.json" for locale in CANONICAL_LOCALES}
    actual_files = set(locale_root.glob("*.json")) if locale_root.is_dir() else set()
    if actual_files != expected_files:
        missing = sorted(path.name for path in expected_files - actual_files)
        extra = sorted(path.name for path in actual_files - expected_files)
        raise LocalizationError(
            f"Internal locale files differ: missing={missing}, extra={extra}"
        )

    by_locale: dict[str, dict[str, dict[str, Any]]] = {}
    for locale in CANONICAL_LOCALES:
        document = read_json(locale_root / f"{locale}.json")
        if not isinstance(document, dict) or set(document) != {"platforms"}:
            raise LocalizationError(f"{locale}: internal locale file must contain platforms")
        platforms = document["platforms"]
        if (
            not isinstance(platforms, dict)
            or set(platforms) != set(CONSUMERS)
        ):
            raise LocalizationError(
                f"{locale}: every internal locale must contain all platforms"
            )
        by_locale[locale] = {
            consumer: flatten_locale_tree(
                platforms[consumer],
                f"{locale}.internal.{consumer}",
                consumer,
            )
            for consumer in platforms
        }

    source: dict[str, Any] = {}
    for consumer in CONSUMERS:
        locales = tuple(CONSUMERS[consumer]["locales"])
        keys = tuple(by_locale[locales[0]][consumer])
        available_locales = tuple(
            locale
            for locale in CANONICAL_LOCALES
            if consumer in by_locale[locale]
        )
        for locale in available_locales[1:]:
            if tuple(by_locale[locale][consumer]) != keys:
                raise LocalizationError(
                    f"{locale}: internal {consumer} key set or order differs"
                )
        for locale in available_locales:
            if locale in locales:
                continue
            for key in keys:
                validate_localizations(
                    {
                        "localizations": {
                            locales[0]: by_locale[locales[0]][consumer][key],
                            locale: by_locale[locale][consumer][key],
                        }
                    },
                    (locales[0], locale),
                    f"{locale}.optional.internal.{consumer}.{key}",
                    consumer,
                )
        source[consumer] = {
            key: {
                "localizations": {
                    locale: by_locale[locale][consumer][key]
                    for locale in locales
                }
            }
            for key in keys
        }
    return source


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
    macos_commerce_keys = set(next(iter(commerce_macos_overlays().values())))
    duplicated_macos_commerce = macos_commerce_keys & (
        set(sections["shared"]) | set(sections["macos"])
    )
    if duplicated_macos_commerce:
        raise LocalizationError(
            f"macOS commerce keys must be owned by the commerce source: "
            f"{sorted(duplicated_macos_commerce)}"
        )
    windows_commerce_keys = set(next(iter(commerce_windows_overlays().values())))
    duplicated_windows_commerce = windows_commerce_keys & (
        set(sections["shared"]) | set(sections["windows"])
    )
    if duplicated_windows_commerce:
        raise LocalizationError(
            f"Windows commerce keys must be owned by the commerce source: "
            f"{sorted(duplicated_windows_commerce)}"
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


def validate_internal_source(source: Any, production: dict[str, Any]) -> None:
    if not isinstance(source, dict) or set(source) != set(CONSUMERS):
        raise LocalizationError("Internal localization source must contain macos and windows")
    for consumer in CONSUMERS:
        section = source[consumer]
        if not isinstance(section, dict) or not section:
            raise LocalizationError(f"Internal {consumer} localization section must not be empty")
        duplicated = set(section) & (set(production["shared"]) | set(production[consumer]))
        if duplicated:
            raise LocalizationError(
                f"Internal {consumer} keys duplicate production keys: {sorted(duplicated)}"
            )
        locales = tuple(CONSUMERS[consumer]["locales"])
        for key, entry in section.items():
            if SEMANTIC_KEY.fullmatch(key) is None:
                raise LocalizationError(f"Invalid internal {consumer} output key: {key}")
            validate_localizations(
                entry,
                locales,
                f"internal.{consumer}.{key}",
                consumer,
            )


def mac_shared_localization(value: str) -> dict[str, Any]:
    return {"stringUnit": {"state": "translated", "value": value}}


def render_macos(
    source: dict[str, Any],
    commerce_overlays: dict[str, dict[str, str]] | None = None,
) -> bytes:
    strings: dict[str, Any] = {}
    locale_map = CONSUMERS["macos"]["locales"]
    commerce_overlays = commerce_overlays or commerce_macos_overlays()
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
    for key in commerce_overlays[next(iter(locale_map))]:
        strings[key] = {
            "extractionState": "manual",
            "localizations": {
                output_locale: mac_shared_localization(
                    commerce_overlays[canonical_locale][key]
                )
                for canonical_locale, output_locale in locale_map.items()
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


def commerce_macos_overlays() -> dict[str, dict[str, str]]:
    catalog = commerce.read_json(commerce.ROOT / commerce.CATALOG)
    source = commerce.read_source()
    return commerce.macos_character_overlays(catalog, source)


def commerce_windows_overlays() -> dict[str, dict[str, str]]:
    catalog = commerce.read_json(commerce.ROOT / commerce.CATALOG)
    source = commerce.read_source()
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


def render_internal_macos(source: dict[str, Any]) -> bytes:
    locale_map = CONSUMERS["macos"]["locales"]
    strings = {
        key: {
            "extractionState": "manual",
            "localizations": {
                locale_map[canonical_locale]: localization
                for canonical_locale, localization in entry["localizations"].items()
            },
        }
        for key, entry in source["macos"].items()
    }
    return json_bytes(
        {"sourceLanguage": "en", "strings": dict(sorted(strings.items())), "version": "1.0"}
    )


def render_internal_windows(source: dict[str, Any]) -> dict[str, bytes]:
    rendered: dict[str, bytes] = {}
    for canonical_locale, output_locale in CONSUMERS["windows"]["locales"].items():
        catalog: dict[str, Any] = {}
        for key, entry in source["windows"].items():
            assign_nested(catalog, key, entry["localizations"][canonical_locale])
        rendered[f"{output_locale}.json"] = json_bytes(catalog)
    return rendered


def expected_outputs(
    source: dict[str, Any],
    consumer: str,
    output_root: Path,
    internal_source: dict[str, Any] | None = None,
) -> dict[Path, bytes]:
    internal_source = internal_source or read_internal_source()
    validate_internal_source(internal_source, source)
    outputs: dict[Path, bytes] = {}
    if consumer in {"macos", "all"}:
        outputs[output_root / CONSUMERS["macos"]["output"]] = render_macos(source)
        outputs[output_root / CONSUMERS["macos"]["internal_output"]] = render_internal_macos(
            internal_source
        )
    if consumer in {"windows", "all"}:
        directory = output_root / CONSUMERS["windows"]["output"]
        outputs.update({directory / name: data for name, data in render_windows(source).items()})
        internal_directory = output_root / CONSUMERS["windows"]["internal_output"]
        outputs.update(
            {
                internal_directory / name: data
                for name, data in render_internal_windows(internal_source).items()
            }
        )
    return outputs


def write_outputs(outputs: dict[Path, bytes]) -> None:
    for path, data in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)


def check_outputs(outputs: dict[Path, bytes]) -> list[Path]:
    stale = [path for path, data in outputs.items() if not path.is_file() or path.read_bytes() != data]
    for output_key in ("output", "internal_output"):
        expected_windows = {
            path
            for path in outputs
            if path.parent.name == CONSUMERS["windows"][output_key].name
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
    parser.add_argument("--locale-root", type=Path, default=ROOT / LOCALE_ROOT)
    parser.add_argument(
        "--internal-locale-root",
        type=Path,
        default=ROOT / INTERNAL_LOCALE_ROOT,
    )
    parser.add_argument("--output-root", type=Path, default=ROOT)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    source = read_source(args.source, args.locale_root)
    internal_source = read_internal_source(args.internal_locale_root)
    validate_source(source)
    validate_internal_source(internal_source, source)
    outputs = expected_outputs(source, args.consumer, args.output_root, internal_source)
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
