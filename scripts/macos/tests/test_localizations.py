import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


MODULE_PATH = Path(__file__).resolve().parents[1] / "verify_localizations.py"
SPEC = importlib.util.spec_from_file_location("verify_localizations", MODULE_PATH)
LOCALIZATIONS = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(LOCALIZATIONS)


def catalog_entry(value: str):
    return {
        "localizations": {
            locale: {"stringUnit": {"state": "translated", "value": value}}
            for locale in LOCALIZATIONS.SUPPORTED_LOCALES
        }
    }


class LocalizationValidationTests(unittest.TestCase):
    def write_catalog(self, document):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "Localizable.xcstrings"
        path.write_text(json.dumps(document), encoding="utf-8")
        return path

    def test_catalog_requires_every_supported_locale(self):
        entry = catalog_entry("Profile")
        del entry["localizations"]["ja"]
        path = self.write_catalog(
            {"sourceLanguage": "en", "strings": {"settings.profile.title": entry}, "version": "1.0"}
        )

        with self.assertRaisesRegex(LOCALIZATIONS.LocalizationError, "exactly"):
            LOCALIZATIONS.load_and_validate_catalog(path)

    def test_catalog_rejects_placeholder_type_mismatch(self):
        entry = catalog_entry("Removed %lld members")
        entry["localizations"]["ja"]["stringUnit"]["value"] = "%@人を削除"
        path = self.write_catalog(
            {"sourceLanguage": "en", "strings": {"group.members.removed": entry}, "version": "1.0"}
        )

        with self.assertRaisesRegex(LOCALIZATIONS.LocalizationError, "placeholder types"):
            LOCALIZATIONS.load_and_validate_catalog(path)

    def test_hangul_scan_ignores_comments_but_rejects_shipped_literals(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        source_root = Path(directory.name)
        (source_root / "Safe.swift").write_text('// "설명"\nlet key = "settings.title"\n', encoding="utf-8")
        LOCALIZATIONS.validate_no_shipped_hangul(source_root)
        (source_root / "Unsafe.swift").write_text('let title = "설정"\n', encoding="utf-8")

        with self.assertRaisesRegex(LOCALIZATIONS.LocalizationError, "Unsafe.swift:1"):
            LOCALIZATIONS.validate_no_shipped_hangul(source_root)

    def test_repository_catalog_covers_shipped_source_and_project_regions(self):
        strings = LOCALIZATIONS.load_and_validate_catalog()
        internal_strings = LOCALIZATIONS.load_and_validate_catalog(
            LOCALIZATIONS.INTERNAL_CATALOG
        )

        LOCALIZATIONS.validate_key_coverage(strings)
        LOCALIZATIONS.validate_internal_key_coverage(internal_strings)
        LOCALIZATIONS.validate_no_shipped_hangul()
        LOCALIZATIONS.validate_project_regions()

if __name__ == "__main__":
    unittest.main()
