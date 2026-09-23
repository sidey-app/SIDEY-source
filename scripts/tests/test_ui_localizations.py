import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest


SCRIPTS = Path(__file__).parents[1]
sys.path.insert(0, str(SCRIPTS))

import ui_localizations as tool  # noqa: E402


def flatten(value, prefix=""):
    output = {}
    for key, child in value.items():
        path = f"{prefix}.{key}" if prefix else key
        if isinstance(child, dict):
            output.update(flatten(child, path))
        else:
            output[path] = child
    return output


class UILocalizationTests(unittest.TestCase):
    def setUp(self):
        self.source = tool.read_json(tool.ROOT / tool.SOURCE)

    def test_canonical_source_is_complete_and_deterministic(self):
        tool.validate_source(self.source)
        first = tool.render_macos(self.source)
        second = tool.render_macos(self.source)
        self.assertEqual(first, second)
        mac = json.loads(first)
        self.assertEqual(len(mac["strings"]), 502)
        self.assertEqual(mac["sourceLanguage"], "en")
        self.assertIn("firebase.auth.error.session_mismatch", mac["strings"])
        self.assertIn("realtime.kill_switch.transition_failed", mac["strings"])

        windows = tool.render_windows(self.source)
        self.assertEqual(
            set(windows),
            {f"{locale}.json" for locale in tool.CONSUMERS["windows"]["locales"].values()},
        )
        for rendered in windows.values():
            self.assertEqual(len(flatten(json.loads(rendered))), 533)

    def test_windows_migration_preserves_every_existing_value(self):
        for filename, rendered in tool.render_windows(self.source).items():
            checked_in = tool.read_json(
                tool.ROOT / tool.CONSUMERS["windows"]["output"] / filename
            )
            self.assertEqual(json.loads(rendered), checked_in, filename)

    def test_shared_messages_are_identical_for_both_consumers(self):
        self.assertEqual(len(self.source["shared"]), 8)
        self.assertIn("common.cancel", self.source["shared"])
        self.assertNotIn("history.title", self.source["shared"])
        mac = json.loads(tool.render_macos(self.source))["strings"]
        windows = {
            locale: flatten(json.loads(rendered))
            for locale, rendered in tool.render_windows(self.source).items()
        }
        for key, entry in self.source["shared"].items():
            for canonical, output in tool.CONSUMERS["macos"]["locales"].items():
                self.assertEqual(
                    mac[key]["localizations"][output]["stringUnit"]["value"],
                    entry["localizations"][canonical],
                )
            for canonical, output in tool.CONSUMERS["windows"]["locales"].items():
                self.assertEqual(
                    windows[f"{output}.json"][key],
                    entry["localizations"][canonical],
                )

    def test_placeholder_drift_is_rejected(self):
        invalid = copy.deepcopy(self.source)
        invalid["windows"]["history.title"]["localizations"]["en"] = "History"
        with self.assertRaisesRegex(tool.LocalizationError, "placeholders differ"):
            tool.validate_source(invalid)

    def test_malformed_placeholders_are_rejected(self):
        invalid = copy.deepcopy(self.source)
        for locale in tool.CONSUMERS["windows"]["locales"]:
            invalid["windows"]["history.title"]["localizations"][locale] = "History {name}"
        with self.assertRaisesRegex(tool.LocalizationError, "malformed .NET placeholder"):
            tool.validate_source(invalid)

        invalid = copy.deepcopy(self.source)
        for locale in tool.CONSUMERS["windows"]["locales"]:
            invalid["windows"]["history.title"]["localizations"][locale] = "History {broken"
        with self.assertRaisesRegex(tool.LocalizationError, "malformed .NET placeholder"):
            tool.validate_source(invalid)

        invalid = copy.deepcopy(self.source)
        for locale in tool.CONSUMERS["macos"]["locales"]:
            invalid["macos"]["message.send.failed"]["localizations"][locale]["stringUnit"]["value"] = "Failed: %s"
        with self.assertRaisesRegex(tool.LocalizationError, "malformed printf placeholder"):
            tool.validate_source(invalid)

        invalid = copy.deepcopy(self.source)
        invalid["macos"]["message.send.failed"]["localizations"]["ja"]["stringUnit"]["value"] = "失敗"
        with self.assertRaisesRegex(tool.LocalizationError, "placeholders differ"):
            tool.validate_source(invalid)

    def test_plural_shape_and_output_key_collisions_are_rejected(self):
        invalid = copy.deepcopy(self.source)
        plural = invalid["macos"]["history.retention_notice"]["localizations"]["en"]["variations"]["plural"]
        plural.pop("one")
        with self.assertRaisesRegex(tool.LocalizationError, "plural requires"):
            tool.validate_source(invalid)

        with self.assertRaisesRegex(tool.LocalizationError, "prefix collision"):
            catalog = {}
            tool.assign_nested(catalog, "a", "first")
            tool.assign_nested(catalog, "a.b", "second")

    def test_write_and_check_detect_stale_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            outputs = tool.expected_outputs(self.source, "all", root)
            tool.write_outputs(outputs)
            self.assertEqual(tool.check_outputs(outputs), [])
            first = next(iter(outputs))
            first.write_text("stale", encoding="utf-8")
            self.assertEqual(tool.check_outputs(outputs), [first])

    def test_duplicate_json_keys_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "duplicate.json"
            source.write_text('{"schema": 1, "schema": 2}', encoding="utf-8")
            with self.assertRaisesRegex(tool.LocalizationError, "duplicate JSON key: schema"):
                tool.read_json(source)

    def test_extra_windows_locale_is_stale(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            outputs = tool.expected_outputs(self.source, "windows", root)
            tool.write_outputs(outputs)
            extra = root / tool.CONSUMERS["windows"]["output"] / "stale.json"
            extra.write_text("{}\n", encoding="utf-8")
            self.assertEqual(tool.check_outputs(outputs), [extra])


if __name__ == "__main__":
    unittest.main()
