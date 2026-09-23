from __future__ import annotations

from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from app_store_connect.api import collect_snapshot  # noqa: E402


class SnapshotTransport:
    def __init__(self) -> None:
        self.paths: list[str] = []

    def request(self, method, path_or_url, body=None, headers=None):
        self.paths.append(path_or_url)
        if path_or_url.startswith("/v1/apps?"):
            return {
                "data": [
                    {
                        "type": "apps",
                        "id": "app-id",
                        "attributes": {"primaryLocale": "ko"},
                    }
                ]
            }
        if path_or_url.startswith("/v1/apps/app-id/appInfos"):
            return {"data": [{"type": "appInfos", "id": "info-id"}]}
        if path_or_url.startswith("/v1/apps/app-id/appStoreVersions"):
            return {
                "data": [
                    {
                        "type": "appStoreVersions",
                        "id": "version-id",
                        "attributes": {"appStoreState": "PREPARE_FOR_SUBMISSION"},
                    }
                ]
            }
        if path_or_url.startswith("/v1/apps/app-id/preReleaseVersions"):
            return {
                "data": [
                    {
                        "type": "preReleaseVersions",
                        "id": "pre-release-1.3.0",
                        "attributes": {"version": "1.3.0", "platform": "MAC_OS"},
                    }
                ]
            }
        if path_or_url.startswith(
            "/v1/preReleaseVersions/pre-release-1.3.0/builds"
        ):
            return {
                "data": [
                    {
                        "type": "builds",
                        "id": "build-31",
                        "attributes": {
                            "version": "31",
                            "uploadedDate": "2026-09-20T00:00:00Z",
                            "processingState": "VALID",
                            "expired": False,
                        },
                    }
                ]
            }
        if path_or_url.startswith("/v1/appInfos/info-id/appInfoLocalizations"):
            return {
                "data": [
                    {
                        "type": "appInfoLocalizations",
                        "id": "info-ja",
                        "attributes": {"locale": "ja", "name": "SIDEY"},
                    }
                ]
            }
        if path_or_url.startswith(
            "/v1/appStoreVersions/version-id/appStoreVersionLocalizations"
        ):
            return {
                "data": [
                    {
                        "type": "appStoreVersionLocalizations",
                        "id": "version-ja",
                        "attributes": {"locale": "ja", "description": "説明"},
                    }
                ]
            }
        if path_or_url.startswith(
            "/v1/appStoreVersionLocalizations/version-ja/appScreenshotSets"
        ):
            return {
                "data": [
                    {
                        "type": "appScreenshotSets",
                        "id": "set-ja",
                        "attributes": {"screenshotDisplayType": "APP_DESKTOP"},
                    }
                ]
            }
        if path_or_url.startswith("/v1/appScreenshotSets/set-ja/appScreenshots"):
            return {
                "data": [
                    {
                        "type": "appScreenshots",
                        "id": "shot-ja",
                        "attributes": {"sourceFileChecksum": "checksum"},
                    }
                ]
            }
        if path_or_url.startswith("/v1/apps/app-id/appAvailabilityV2"):
            return {"data": {"type": "appAvailabilities", "id": "availability-id"}}
        if path_or_url.startswith(
            "/v2/appAvailabilities/availability-id/territoryAvailabilities"
        ):
            return {
                "data": [
                    {
                        "type": "territoryAvailabilities",
                        "id": "territory-jpn",
                        "attributes": {"available": True},
                        "relationships": {
                            "territory": {"data": {"type": "territories", "id": "JPN"}}
                        },
                    }
                ]
            }
        if path_or_url.startswith("/v1/apps/app-id/inAppPurchasesV2"):
            return {
                "data": [
                    {
                        "type": "inAppPurchases",
                        "id": "iap-id",
                        "attributes": {"productId": "product-id", "state": "APPROVED"},
                    }
                ]
            }
        if path_or_url.startswith(
            "/v2/inAppPurchases/iap-id/inAppPurchaseLocalizations"
        ):
            return {
                "data": [
                    {
                        "type": "inAppPurchaseLocalizations",
                        "id": "iap-ja",
                        "attributes": {"locale": "ja", "name": "商品", "description": "説明"},
                    }
                ]
            }
        if path_or_url.startswith(
            "/v2/inAppPurchases/iap-id/inAppPurchaseAvailability"
        ):
            return {
                "data": {
                    "type": "inAppPurchaseAvailabilities",
                    "id": "iap-availability",
                    "attributes": {"availableInNewTerritories": True},
                }
            }
        if path_or_url.startswith(
            "/v1/inAppPurchaseAvailabilities/iap-availability/availableTerritories"
        ):
            return {
                "data": [
                    {"type": "territories", "id": "JPN"},
                    {"type": "territories", "id": "FRA"},
                ]
            }
        raise AssertionError(f"Unexpected request: {method} {path_or_url}")


class AppStoreConnectSnapshotTests(unittest.TestCase):
    def test_collects_normalized_read_only_snapshot_with_full_availability(self) -> None:
        transport = SnapshotTransport()

        snapshot = collect_snapshot(
            transport,
            bundle_id="app.sidey.desktop.appstore",
            version="1.3.0",
            platform="MAC_OS",
        )

        self.assertEqual(snapshot["app"]["territory_availabilities"]["JPN"]["id"], "territory-jpn")
        purchase = snapshot["in_app_purchases"]["product-id"]
        self.assertEqual(purchase["available_territories"], ["FRA", "JPN"])
        self.assertTrue(purchase["available_in_new_territories"])
        self.assertEqual(purchase["localizations"]["ja"]["name"], "商品")
        self.assertEqual(snapshot["build_history"]["max_build"], 31)
        self.assertEqual(snapshot["app"]["version_state"], "PREPARE_FOR_SUBMISSION")
        self.assertTrue(all(path.startswith("/") for path in transport.paths))


if __name__ == "__main__":
    unittest.main()
