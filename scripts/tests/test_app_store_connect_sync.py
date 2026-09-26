from __future__ import annotations

from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from app_store_connect.model import (  # noqa: E402
    APP_STORE_LOCALES,
    DesiredState,
    expanded_iap_localizations,
    load_desired_state,
    validate_manifest,
)
from app_store_connect.sync import apply_plan, build_plan  # noqa: E402


class FakeTransport:
    def __init__(self) -> None:
        self.requests: list[tuple[str, str, object, object]] = []

    def request(self, method, path_or_url, body=None, headers=None):
        self.requests.append((method, path_or_url, body, headers))
        return {"data": {"id": "fake-response"}}


class ScreenshotTransport(FakeTransport):
    def request(self, method, path_or_url, body=None, headers=None):
        self.requests.append((method, path_or_url, body, headers))
        if path_or_url == "/v1/appStoreVersionLocalizations":
            return {"data": {"id": "created-version-localization"}}
        if path_or_url == "/v1/appScreenshotSets":
            return {"data": {"id": "created-screenshot-set"}}
        if path_or_url == "/v1/appScreenshots":
            return {
                "data": {
                    "id": f"screenshot-{len(self.requests)}",
                    "attributes": {
                        "uploadOperations": [
                            {
                                "method": "PUT",
                                "url": "https://upload.example/part",
                                "offset": 0,
                                "length": len(body["data"]["attributes"]["fileName"]),
                                "requestHeaders": [],
                            }
                        ]
                    },
                }
            }
        if method == "GET" and path_or_url.startswith("/v1/appScreenshots/"):
            return {
                "data": {
                    "attributes": {"assetDeliveryState": {"state": "COMPLETE"}}
                }
            }
        return {}


def desired_with_test_screenshots(root: Path) -> DesiredState:
    desired = load_desired_state(
        ROOT / "release" / "app-store-localizations.json",
        ROOT / "assets" / "v1" / "locale" / "commerce",
        ROOT / "assets" / "v1" / "commerce-catalog.json",
    )
    manifest = deepcopy(desired.manifest)
    source_by_locale = {
        "ko": "ko",
        "en-US": "en",
        "en-GB": "en",
        "en-CA": "en",
        "en-AU": "en",
        "ja": "ja",
        "zh-Hant": "zh-Hant",
    }
    for locale, source_locale in source_by_locale.items():
        for index, screenshot in enumerate(manifest["app_localizations"][locale]["screenshots"]):
            path = Path("shots") / source_locale / f"{index}.png"
            screenshot["path"] = path.as_posix()
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(f"{source_locale}-{index}".encode())
    validate_manifest(manifest)
    return DesiredState(manifest=manifest, products=desired.products)


def matching_snapshot(desired: DesiredState, repository_root: Path) -> dict:
    manifest = desired.manifest
    app_info = {}
    version_info = {}
    screenshot_sets = {}
    screenshots = {}
    for locale, localized in manifest["app_localizations"].items():
        app_info[locale] = {
            "id": f"info-{locale}",
            "locale": locale,
            "name": localized["name"],
            "subtitle": localized["subtitle"],
            "privacyPolicyUrl": localized["privacy_policy_url"],
        }
        version_info[locale] = {
            "id": f"version-{locale}",
            "locale": locale,
            "description": localized["description"],
            "keywords": localized["keywords"],
            "supportUrl": localized["support_url"],
            "whatsNew": localized["release_notes"],
        }
        screenshot_sets[locale] = f"set-{locale}"
        screenshots[locale] = [
            {
                "id": f"shot-{locale}-{index}",
                "sourceFileChecksum": hashlib.md5(
                    (repository_root / screenshot["path"]).read_bytes()
                ).hexdigest(),
            }
            for index, screenshot in enumerate(localized["screenshots"])
        ]
    iaps = {}
    for product in desired.products:
        iaps[product["app_store_product_id"]] = {
            "id": f"iap-{product['id']}",
            "state": "APPROVED",
            "localizations": {
                locale: {"id": f"loc-{product['id']}-{locale}", **value}
                for locale, value in expanded_iap_localizations(product).items()
            },
            "available_territories": [*manifest["target_territories"], "FRA"],
            "available_in_new_territories": True,
        }
    return {
        "schema": 1,
        "app": {
            "id": "app-id",
            "bundle_id": manifest["app"]["bundle_id"],
            "primary_locale": "ko",
            "app_info_id": "app-info-id",
            "app_info_localizations": app_info,
            "version_id": "version-id",
            "version": manifest["release"]["version"],
            "version_state": "PREPARE_FOR_SUBMISSION",
            "version_localizations": version_info,
            "screenshot_sets": screenshot_sets,
            "screenshots": screenshots,
            "territory_availabilities": {
                territory: {"id": f"territory-{territory}", "available": True}
                for territory in [*manifest["target_territories"], "FRA"]
            },
        },
        "build_history": {
            "platform": "MAC_OS",
            "max_build": manifest["release"]["build"] - 1,
            "builds": [],
        },
        "in_app_purchases": iaps,
    }


class AppStoreConnectSyncTests(unittest.TestCase):
    def test_diff_updates_localization_and_only_expands_iap_territories(self) -> None:
        with tempfile.TemporaryDirectory(prefix="SIDEY-ASC-") as temporary:
            test_root = Path(temporary)
            desired = desired_with_test_screenshots(test_root)
            snapshot = matching_snapshot(desired, test_root)
            product = desired.products[0]
            product_id = product["app_store_product_id"]
            snapshot["in_app_purchases"][product_id]["localizations"]["ja"]["description"] = "old"
            snapshot["in_app_purchases"][product_id]["available_territories"].remove("JPN")

            plan = build_plan(desired, snapshot, repository_root=test_root)

            self.assertEqual(plan["blockers"], [])
            operations = plan["operations"]
            self.assertEqual(len(operations), 2)
            localization = next(value for value in operations if value["resource"] == "iap_localization")
            self.assertEqual(localization["product_id"], product_id)
            expansion = next(value for value in operations if value["resource"] == "iap_territories")
            self.assertEqual(expansion["added"], ["JPN"])
            self.assertIn("FRA", expansion["territories"])
            self.assertTrue(expansion["available_in_new_territories"])
            self.assertEqual(
                set(expansion["territories"]),
                set(desired.manifest["target_territories"]) | {"FRA"},
            )

    def test_diff_never_disables_an_existing_app_storefront(self) -> None:
        with tempfile.TemporaryDirectory(prefix="SIDEY-ASC-") as temporary:
            test_root = Path(temporary)
            desired = desired_with_test_screenshots(test_root)
            snapshot = matching_snapshot(desired, test_root)
            snapshot["app"]["territory_availabilities"]["JPN"]["available"] = False

            plan = build_plan(desired, snapshot, repository_root=test_root)

            territory_operations = [
                value for value in plan["operations"] if value["resource"] == "app_territory"
            ]
            self.assertEqual(
                territory_operations,
                [
                    {
                        "action": "enable",
                        "resource": "app_territory",
                        "id": "territory-JPN",
                        "territory": "JPN",
                    }
                ],
            )
            self.assertFalse(any(value["action"] == "disable" for value in plan["operations"]))

    def test_missing_screenshots_are_blockers_not_remote_operations(self) -> None:
        with tempfile.TemporaryDirectory(prefix="SIDEY-ASC-") as temporary:
            test_root = Path(temporary)
            desired = desired_with_test_screenshots(test_root)
            snapshot = matching_snapshot(desired, test_root)
            missing = test_root / desired.manifest["app_localizations"]["ja"]["screenshots"][0]["path"]
            missing.unlink()
            snapshot["app"]["screenshots"]["ja"] = []

            plan = build_plan(desired, snapshot, repository_root=test_root)

            self.assertIn("Missing screenshot file:", "\n".join(plan["blockers"]))

    def test_screenshot_replacement_keeps_each_source_checksum(self) -> None:
        with tempfile.TemporaryDirectory(prefix="SIDEY-ASC-") as temporary:
            test_root = Path(temporary)
            desired = desired_with_test_screenshots(test_root)
            snapshot = matching_snapshot(desired, test_root)
            snapshot["app"]["screenshots"]["ja"] = []

            plan = build_plan(desired, snapshot, repository_root=test_root)

            uploads = [
                value
                for value in plan["operations"]
                if value["resource"] == "screenshot"
                and value["action"] == "upload"
                and value["locale"] == "ja"
            ]
            expected = [
                hashlib.md5(
                    (test_root / screenshot["path"]).read_bytes()
                ).hexdigest()
                for screenshot in desired.manifest["app_localizations"]["ja"]["screenshots"]
            ]
            self.assertEqual([value["checksum"] for value in uploads], expected)

    def test_used_build_and_consumed_version_are_blockers(self) -> None:
        with tempfile.TemporaryDirectory(prefix="SIDEY-ASC-") as temporary:
            test_root = Path(temporary)
            desired = desired_with_test_screenshots(test_root)
            snapshot = matching_snapshot(desired, test_root)
            snapshot["build_history"]["max_build"] = desired.manifest["release"]["build"]
            snapshot["app"]["version_state"] = "READY_FOR_SALE"

            plan = build_plan(desired, snapshot, repository_root=test_root)

            blockers = "\n".join(plan["blockers"])
            self.assertIn("already used", blockers)
            self.assertIn("next minor version", blockers)
            provenance = plan["summary"]["build_provenance"]
            self.assertEqual(provenance["status"], "already-used")
            self.assertTrue(provenance["manifest_is_provisional_until_snapshot"])

    def test_apply_requires_both_explicit_gates(self) -> None:
        transport = FakeTransport()
        plan = {
            "approval_id": "macos-1.3.0-build-32",
            "blockers": [],
            "operations": [
                {
                    "action": "update",
                    "resource": "iap_localization",
                    "id": "localization-id",
                    "locale": "ja",
                    "parent_id": "iap-id",
                    "product_id": "product-id",
                    "attributes": {"name": "商品", "description": "説明"},
                }
            ],
        }

        self.assertEqual(apply_plan(transport, plan), [])
        self.assertEqual(transport.requests, [])
        with self.assertRaises(PermissionError):
            apply_plan(
                transport,
                plan,
                apply=True,
                release_approval="macos-1.3.0-build-32",
                approval_environment=None,
            )
        self.assertEqual(transport.requests, [])

        apply_plan(
            transport,
            plan,
            apply=True,
            release_approval="macos-1.3.0-build-32",
            approval_environment="macos-1.3.0-build-32",
        )
        self.assertEqual(
            [(method, path) for method, path, _, _ in transport.requests],
            [("PATCH", "/v1/inAppPurchaseLocalizations/localization-id")],
        )

    def test_apply_reuses_created_localization_and_screenshot_set(self) -> None:
        with tempfile.TemporaryDirectory(prefix="SIDEY-ASC-Upload-") as temporary:
            root = Path(temporary)
            (root / "one.png").write_bytes(b"one.png")
            (root / "two.png").write_bytes(b"two.png")
            plan = {
                "approval_id": "macos-1.3.0-build-32",
                "blockers": [],
                "operations": [
                    {
                        "action": "create",
                        "resource": "version_localization",
                        "id": None,
                        "locale": "ja",
                        "parent_id": "version-id",
                        "attributes": {
                            "description": "説明",
                            "keywords": "友だち",
                            "supportUrl": "https://example.com/support",
                            "whatsNew": "更新",
                        },
                    },
                    *[
                        {
                            "action": "upload",
                            "resource": "screenshot",
                            "locale": "ja",
                            "scene": path.stem,
                            "path": path.name,
                            "checksum": hashlib.md5(path.read_bytes()).hexdigest(),
                            "screenshot_set_id": None,
                            "version_localization_id": None,
                            "display_type": "APP_DESKTOP",
                        }
                        for path in (root / "one.png", root / "two.png")
                    ],
                ],
            }
            transport = ScreenshotTransport()

            apply_plan(
                transport,
                plan,
                apply=True,
                release_approval="macos-1.3.0-build-32",
                approval_environment="macos-1.3.0-build-32",
                repository_root=root,
            )

            paths = [path for _, path, _, _ in transport.requests]
            self.assertEqual(paths.count("/v1/appScreenshotSets"), 1)
            reservations = [
                body
                for method, path, body, _ in transport.requests
                if method == "POST" and path == "/v1/appScreenshots"
            ]
            self.assertEqual(len(reservations), 2)
            relationship = reservations[0]["data"]["relationships"]["appScreenshotSet"]
            self.assertEqual(relationship["data"]["id"], "created-screenshot-set")


if __name__ == "__main__":
    unittest.main()
