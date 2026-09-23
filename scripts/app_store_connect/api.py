"""Minimal App Store Connect JSON:API client and snapshot collector."""

from __future__ import annotations

from datetime import datetime, timezone
import json
from typing import Any, Protocol
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen


API_ROOT = "https://api.appstoreconnect.apple.com"


class APIError(RuntimeError):
    """Raised when App Store Connect returns an invalid or failed response."""


class Transport(Protocol):
    def request(
        self,
        method: str,
        path_or_url: str,
        body: dict[str, Any] | bytes | None = None,
        headers: dict[str, str] | None = None,
    ) -> dict[str, Any]: ...


class URLTransport:
    def __init__(self, token: str) -> None:
        self.token = token

    def request(
        self,
        method: str,
        path_or_url: str,
        body: dict[str, Any] | bytes | None = None,
        headers: dict[str, str] | None = None,
    ) -> dict[str, Any]:
        if "://" in path_or_url and not path_or_url.startswith("https://"):
            raise APIError("App Store Connect transport refuses non-HTTPS URLs")
        url = path_or_url if path_or_url.startswith("https://") else API_ROOT + path_or_url
        request_headers = dict(headers or {})
        request_headers.setdefault("Accept", "application/json")
        if urlparse(url).hostname == "api.appstoreconnect.apple.com":
            request_headers["Authorization"] = f"Bearer {self.token}"
        data: bytes | None
        if isinstance(body, dict):
            data = json.dumps(body, separators=(",", ":")).encode("utf-8")
            request_headers.setdefault("Content-Type", "application/json")
        else:
            data = body
        request = Request(url, data=data, method=method, headers=request_headers)
        try:
            with urlopen(request, timeout=60) as response:
                payload = response.read()
        except HTTPError as error:
            detail = error.read().decode("utf-8", "replace")
            raise APIError(f"App Store Connect {method} {url} failed: {error.code} {detail}") from error
        except URLError as error:
            raise APIError(f"App Store Connect {method} {url} failed: {error.reason}") from error
        if not payload:
            return {}
        try:
            return json.loads(payload)
        except json.JSONDecodeError as error:
            raise APIError(f"App Store Connect returned non-JSON for {method} {url}") from error


def _query(path: str, **values: str | int) -> str:
    return path + "?" + urlencode(values)


def _data_list(response: dict[str, Any], context: str) -> list[dict[str, Any]]:
    data = response.get("data")
    if not isinstance(data, list):
        raise APIError(f"{context} did not return a JSON:API collection")
    return data


def _one(response: dict[str, Any], context: str) -> dict[str, Any]:
    values = _data_list(response, context)
    if len(values) != 1:
        raise APIError(f"Expected exactly one {context}, found {len(values)}")
    return values[0]


def _all(transport: Transport, path: str) -> list[dict[str, Any]]:
    values: list[dict[str, Any]] = []
    next_path: str | None = path
    while next_path:
        response = transport.request("GET", next_path)
        values.extend(_data_list(response, next_path))
        next_value = response.get("links", {}).get("next")
        next_path = next_value if isinstance(next_value, str) else None
    return values


def _attributes_by_locale(values: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for value in values:
        attributes = dict(value.get("attributes") or {})
        locale = attributes.get("locale")
        if isinstance(locale, str):
            result[locale] = {"id": value.get("id"), **attributes}
    return result


def collect_snapshot(
    transport: Transport,
    *,
    bundle_id: str,
    version: str,
    platform: str,
) -> dict[str, Any]:
    app = _one(
        transport.request(
            "GET", _query("/v1/apps", **{"filter[bundleId]": bundle_id, "limit": 2})
        ),
        "app",
    )
    app_id = app["id"]
    app_info = _one(
        transport.request("GET", _query(f"/v1/apps/{app_id}/appInfos", limit=2)),
        "app info",
    )
    version_resource = _one(
        transport.request(
            "GET",
            _query(
                f"/v1/apps/{app_id}/appStoreVersions",
                **{
                    "filter[platform]": platform,
                    "filter[versionString]": version,
                    "limit": 2,
                },
            ),
        ),
        "editable App Store version",
    )

    pre_release_versions = _all(
        transport,
        _query(
            f"/v1/apps/{app_id}/preReleaseVersions",
            **{"filter[platform]": platform, "limit": 200},
        ),
    )
    builds: list[dict[str, Any]] = []
    for pre_release_version in pre_release_versions:
        marketing_version = pre_release_version.get("attributes", {}).get("version")
        for build in _all(
            transport,
            f"/v1/preReleaseVersions/{pre_release_version['id']}/builds?limit=200",
        ):
            attributes = build.get("attributes", {})
            build_number = attributes.get("version")
            builds.append(
                {
                    "id": build.get("id"),
                    "marketing_version": marketing_version,
                    "build": build_number,
                    "uploaded_date": attributes.get("uploadedDate"),
                    "processing_state": attributes.get("processingState"),
                    "expired": attributes.get("expired"),
                }
            )
    numeric_builds = [
        int(value["build"])
        for value in builds
        if isinstance(value.get("build"), str) and value["build"].isdigit()
    ]

    app_info_localizations = _all(
        transport, f"/v1/appInfos/{app_info['id']}/appInfoLocalizations?limit=200"
    )
    version_localizations = _all(
        transport,
        f"/v1/appStoreVersions/{version_resource['id']}/appStoreVersionLocalizations?limit=200",
    )
    version_by_locale = _attributes_by_locale(version_localizations)
    screenshots: dict[str, list[dict[str, Any]]] = {}
    screenshot_sets: dict[str, str] = {}
    for locale, localization in version_by_locale.items():
        sets = _all(
            transport,
            f"/v1/appStoreVersionLocalizations/{localization['id']}/appScreenshotSets?limit=200",
        )
        desktop = next(
            (item for item in sets if item.get("attributes", {}).get("screenshotDisplayType") == "APP_DESKTOP"),
            None,
        )
        if desktop:
            screenshot_sets[locale] = desktop["id"]
            screenshot_values = _all(
                transport, f"/v1/appScreenshotSets/{desktop['id']}/appScreenshots?limit=200"
            )
            screenshots[locale] = [
                {"id": value.get("id"), **dict(value.get("attributes") or {})}
                for value in screenshot_values
            ]
        else:
            screenshots[locale] = []

    availability = transport.request(
        "GET",
        f"/v1/apps/{app_id}/appAvailabilityV2?include=territoryAvailabilities&limit[territoryAvailabilities]=50",
    )
    availability_id = availability.get("data", {}).get("id")
    if not availability_id:
        raise APIError("App availability response omitted its resource ID")
    availability_values = _all(
        transport,
        f"/v2/appAvailabilities/{availability_id}/territoryAvailabilities?include=territory&limit=200",
    )
    territory_availabilities: dict[str, dict[str, Any]] = {}
    for value in availability_values:
        territory = value.get("relationships", {}).get("territory", {}).get("data", {})
        territory_id = territory.get("id")
        if isinstance(territory_id, str):
            territory_availabilities[territory_id] = {
                "id": value.get("id"),
                "available": bool(value.get("attributes", {}).get("available")),
            }

    purchases = _all(transport, f"/v1/apps/{app_id}/inAppPurchasesV2?limit=200")
    iaps: dict[str, dict[str, Any]] = {}
    for purchase in purchases:
        attributes = purchase.get("attributes", {})
        product_id = attributes.get("productId")
        if not isinstance(product_id, str):
            continue
        purchase_id = purchase["id"]
        localizations = _all(
            transport, f"/v2/inAppPurchases/{purchase_id}/inAppPurchaseLocalizations?limit=200"
        )
        purchase_availability = transport.request(
            "GET",
            f"/v2/inAppPurchases/{purchase_id}/inAppPurchaseAvailability?include=availableTerritories&limit[availableTerritories]=50",
        )
        availability_id = purchase_availability.get("data", {}).get("id")
        if not availability_id:
            raise APIError(f"IAP availability response omitted its ID: {product_id}")
        available_territories = sorted(
            value["id"]
            for value in _all(
                transport,
                f"/v1/inAppPurchaseAvailabilities/{availability_id}/availableTerritories?limit=200",
            )
        )
        iaps[product_id] = {
            "id": purchase_id,
            "state": attributes.get("state"),
            "localizations": _attributes_by_locale(localizations),
            "availability_id": availability_id,
            "available_in_new_territories": bool(
                purchase_availability.get("data", {})
                .get("attributes", {})
                .get("availableInNewTerritories")
            ),
            "available_territories": available_territories,
        }

    return {
        "schema": 1,
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "app": {
            "id": app_id,
            "bundle_id": bundle_id,
            "primary_locale": app.get("attributes", {}).get("primaryLocale"),
            "app_info_id": app_info["id"],
            "app_info_localizations": _attributes_by_locale(app_info_localizations),
            "version_id": version_resource["id"],
            "version": version,
            "version_state": version_resource.get("attributes", {}).get("appStoreState"),
            "version_localizations": version_by_locale,
            "screenshot_sets": screenshot_sets,
            "screenshots": screenshots,
            "territory_availabilities": territory_availabilities,
        },
        "build_history": {
            "platform": platform,
            "max_build": max(numeric_builds, default=0),
            "builds": sorted(
                builds,
                key=lambda value: (
                    int(value["build"])
                    if isinstance(value.get("build"), str)
                    and value["build"].isdigit()
                    else -1
                ),
            ),
        },
        "in_app_purchases": iaps,
    }
