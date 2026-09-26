#!/usr/bin/env python3
"""Snapshot, diff, and explicitly approved App Store Connect localizations."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time
from typing import Any

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from app_store_connect.api import Transport, URLTransport, collect_snapshot
    from app_store_connect.auth import generate_token, load_credentials
    from app_store_connect.model import (
        APP_STORE_LOCALES,
        DesiredState,
        ValidationError,
        expanded_iap_localizations,
        load_desired_state,
        read_json,
    )
else:
    from .api import Transport, URLTransport, collect_snapshot
    from .auth import generate_token, load_credentials
    from .model import (
        APP_STORE_LOCALES,
        DesiredState,
        ValidationError,
        expanded_iap_localizations,
        load_desired_state,
        read_json,
    )


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = ROOT / "release" / "app-store-localizations.json"
DEFAULT_COMMERCE = ROOT / "assets" / "v1" / "locale" / "commerce"
DEFAULT_CATALOG = ROOT / "assets" / "v1" / "commerce-catalog.json"
APP_INFO_FIELDS = ("name", "subtitle", "privacyPolicyUrl")
VERSION_FIELDS = ("description", "keywords", "supportUrl", "whatsNew")
REMOTE_APP_INFO_NAMES = {
    "name": "name",
    "subtitle": "subtitle",
    "privacy_policy_url": "privacyPolicyUrl",
}
REMOTE_VERSION_NAMES = {
    "description": "description",
    "keywords": "keywords",
    "support_url": "supportUrl",
    "release_notes": "whatsNew",
}
EDITABLE_VERSION_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
}


def _operation(action: str, resource: str, **values: Any) -> dict[str, Any]:
    return {"action": action, "resource": resource, **values}


def _metadata_attributes(value: dict[str, Any], names: dict[str, str]) -> dict[str, str]:
    return {remote: value[local] for local, remote in names.items()}


def _changed(desired: dict[str, Any], current: dict[str, Any] | None) -> bool:
    return current is None or any(current.get(key) != value for key, value in desired.items())


def _screenshot_md5(repository_root: Path, relative_path: str) -> str | None:
    path = repository_root / relative_path
    if not path.is_file():
        return None
    return hashlib.md5(path.read_bytes()).hexdigest()  # nosec: Apple upload contract uses MD5


def build_plan(
    desired: DesiredState,
    snapshot: dict[str, Any],
    *,
    repository_root: Path = ROOT,
) -> dict[str, Any]:
    if snapshot.get("schema") != 1 or not isinstance(snapshot.get("app"), dict):
        raise ValidationError("Snapshot schema must be 1 and include app state")
    manifest = desired.manifest
    app = snapshot["app"]
    if app.get("bundle_id") != manifest["app"]["bundle_id"]:
        raise ValidationError("Snapshot bundle ID differs from the desired app")
    if app.get("version") != manifest["release"]["version"]:
        raise ValidationError("Snapshot version differs from the desired release")
    if app.get("primary_locale") != "ko":
        raise ValidationError("App Store primary locale is no longer ko")

    operations: list[dict[str, Any]] = []
    blockers: list[str] = []
    build_history = snapshot.get("build_history")
    if not isinstance(build_history, dict) or type(build_history.get("max_build")) is not int:
        raise ValidationError("Snapshot requires normalized macOS build_history")
    desired_build = manifest["release"]["build"]
    max_build = build_history["max_build"]
    if desired_build <= max_build:
        blockers.append(
            f"Manifest build {desired_build} is already used; App Store Connect max is {max_build}"
        )
        build_status = "already-used"
    elif desired_build != max_build + 1:
        blockers.append(
            f"Manifest build {desired_build} must be App Store Connect max + 1 ({max_build + 1})"
        )
        build_status = "not-max-plus-one"
    else:
        build_status = "ready-max-plus-one"
    version_state = app.get("version_state")
    if version_state not in EDITABLE_VERSION_STATES:
        blockers.append(
            f"App Store version {manifest['release']['version']} is not editable: {version_state}; "
            "audit whether the release must move to the next minor version"
        )
    app_info_current = app.get("app_info_localizations", {})
    version_current = app.get("version_localizations", {})
    screenshot_sets = app.get("screenshot_sets", {})
    screenshots_current = app.get("screenshots", {})
    for locale in APP_STORE_LOCALES:
        localized = manifest["app_localizations"][locale]
        app_info_attributes = _metadata_attributes(localized, REMOTE_APP_INFO_NAMES)
        current = app_info_current.get(locale)
        if _changed(app_info_attributes, current):
            operations.append(
                _operation(
                    "update" if current else "create",
                    "app_info_localization",
                    id=current.get("id") if current else None,
                    locale=locale,
                    parent_id=app.get("app_info_id"),
                    attributes=app_info_attributes,
                )
            )

        version_attributes = _metadata_attributes(localized, REMOTE_VERSION_NAMES)
        current_version = version_current.get(locale)
        if _changed(version_attributes, current_version):
            operations.append(
                _operation(
                    "update" if current_version else "create",
                    "version_localization",
                    id=current_version.get("id") if current_version else None,
                    locale=locale,
                    parent_id=app.get("version_id"),
                    attributes=version_attributes,
                )
            )

        current_screenshots = screenshots_current.get(locale, [])
        desired_screenshots: list[dict[str, str]] = []
        for screenshot in localized["screenshots"]:
            checksum = _screenshot_md5(repository_root, screenshot["path"])
            if checksum is None:
                blockers.append(f"Missing screenshot file: {screenshot['path']}")
                continue
            desired_screenshots.append({**screenshot, "checksum": checksum})
        current_checksums = [
            value.get("sourceFileChecksum") for value in current_screenshots
        ]
        desired_checksums = [value["checksum"] for value in desired_screenshots]
        if (
            len(desired_screenshots) == len(localized["screenshots"])
            and current_checksums != desired_checksums
        ):
            if len(current_screenshots) + len(desired_screenshots) > 10:
                blockers.append(
                    f"Replacing {locale} screenshots would exceed Apple's ten-image limit"
                )
                continue
            # Upload the complete ordered replacement before removing old images.
            # If any upload fails, the previously published set remains intact.
            for screenshot in desired_screenshots:
                operations.append(
                    _operation(
                        "upload",
                        "screenshot",
                        locale=locale,
                        scene=screenshot["scene"],
                        path=screenshot["path"],
                        checksum=screenshot["checksum"],
                        screenshot_set_id=screenshot_sets.get(locale),
                        version_localization_id=(current_version or {}).get("id"),
                        display_type=manifest["screenshot_display_type"],
                    )
                )
            operations.extend(
                _operation(
                    "delete",
                    "screenshot",
                    locale=locale,
                    id=screenshot.get("id"),
                )
                for screenshot in current_screenshots
                if screenshot.get("id")
            )

    territory_state = app.get("territory_availabilities", {})
    for territory in manifest["target_territories"]:
        state = territory_state.get(territory)
        if not state:
            blockers.append(f"Snapshot omitted app territory availability: {territory}")
        elif not state.get("available"):
            operations.append(
                _operation(
                    "enable",
                    "app_territory",
                    id=state.get("id"),
                    territory=territory,
                )
            )

    remote_iaps = snapshot.get("in_app_purchases")
    if not isinstance(remote_iaps, dict):
        raise ValidationError("Snapshot requires in_app_purchases")
    for product in desired.products:
        product_id = product["app_store_product_id"]
        remote = remote_iaps.get(product_id)
        if not remote:
            blockers.append(f"Current App Store product is missing: {product_id}")
            continue
        for locale, localized in expanded_iap_localizations(product).items():
            current = remote.get("localizations", {}).get(locale)
            if _changed(localized, current):
                operations.append(
                    _operation(
                        "update" if current else "create",
                        "iap_localization",
                        id=current.get("id") if current else None,
                        locale=locale,
                        parent_id=remote.get("id"),
                        product_id=product_id,
                        attributes=localized,
                    )
                )
        existing_territories = set(remote.get("available_territories", []))
        required = set(manifest["target_territories"])
        if not required <= existing_territories:
            # Apple replaces this relationship. Always submit the union so existing
            # storefronts can never be removed by this tool.
            operations.append(
                _operation(
                    "expand",
                    "iap_territories",
                    parent_id=remote.get("id"),
                    product_id=product_id,
                    territories=sorted(existing_territories | required),
                    added=sorted(required - existing_territories),
                    available_in_new_territories=bool(
                        remote.get("available_in_new_territories")
                    ),
                )
            )

    return {
        "schema": 1,
        "mode": "read-only-diff",
        "approval_id": desired.approval_id,
        "summary": {
            "operation_count": len(operations),
            "blocker_count": len(blockers),
            "build_provenance": {
                "manifest_build": desired_build,
                "app_store_max_used_build": max_build,
                "status": build_status,
                "manifest_is_provisional_until_snapshot": True,
            },
        },
        "blockers": sorted(set(blockers)),
        "operations": operations,
    }


def _json_api(resource_type: str, attributes: dict[str, Any], *, resource_id: str | None = None, relationships: dict[str, Any] | None = None) -> dict[str, Any]:
    data: dict[str, Any] = {"type": resource_type, "attributes": attributes}
    if resource_id:
        data["id"] = resource_id
    if relationships:
        data["relationships"] = relationships
    return {"data": data}


def _apply_screenshot(
    transport: Transport,
    operation: dict[str, Any],
    repository_root: Path,
) -> str:
    set_id = operation.get("screenshot_set_id")
    if not set_id:
        localization_id = operation.get("version_localization_id")
        if not localization_id:
            raise RuntimeError(
                f"Create metadata for {operation['locale']} before uploading screenshots; rerun diff"
            )
        response = transport.request(
            "POST",
            "/v1/appScreenshotSets",
            _json_api(
                "appScreenshotSets",
                {"screenshotDisplayType": operation["display_type"]},
                relationships={
                    "appStoreVersionLocalization": {
                        "data": {"type": "appStoreVersionLocalizations", "id": localization_id}
                    }
                },
            ),
        )
        set_id = response.get("data", {}).get("id")
        if not set_id:
            raise RuntimeError("App Store Connect did not return a screenshot set ID")

    path = repository_root / operation["path"]
    content = path.read_bytes()
    reservation = transport.request(
        "POST",
        "/v1/appScreenshots",
        _json_api(
            "appScreenshots",
            {"fileSize": len(content), "fileName": path.name},
            relationships={
                "appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}
            },
        ),
    )
    resource = reservation.get("data", {})
    screenshot_id = resource.get("id")
    upload_operations = resource.get("attributes", {}).get("uploadOperations", [])
    if not screenshot_id or not upload_operations:
        raise RuntimeError("App Store Connect did not return screenshot upload operations")
    for upload in upload_operations:
        offset = upload["offset"]
        length = upload["length"]
        headers = {value["name"]: value["value"] for value in upload.get("requestHeaders", [])}
        transport.request(
            upload["method"],
            upload["url"],
            content[offset : offset + length],
            headers,
        )
    transport.request(
        "PATCH",
        f"/v1/appScreenshots/{screenshot_id}",
        _json_api(
            "appScreenshots",
            {"uploaded": True, "sourceFileChecksum": operation["checksum"]},
            resource_id=screenshot_id,
        ),
    )
    for _ in range(90):
        status = transport.request("GET", f"/v1/appScreenshots/{screenshot_id}")
        delivery = status.get("data", {}).get("attributes", {}).get(
            "assetDeliveryState", {}
        )
        state = delivery.get("state")
        if state == "COMPLETE":
            return set_id
        if state == "FAILED":
            raise RuntimeError(
                f"App Store Connect rejected screenshot {operation['path']}: "
                f"{delivery.get('errors', [])}"
            )
        time.sleep(2)
    raise RuntimeError(
        f"Timed out waiting for App Store Connect screenshot processing: {operation['path']}"
    )


def apply_plan(
    transport: Transport,
    plan: dict[str, Any],
    *,
    apply: bool = False,
    release_approval: str | None = None,
    approval_environment: str | None = None,
    repository_root: Path = ROOT,
) -> list[dict[str, Any]]:
    if not apply:
        return []
    expected = plan.get("approval_id")
    if not expected or release_approval != expected or approval_environment != expected:
        raise PermissionError(
            "Remote mutation requires --apply, matching --release-approval, and a matching "
            "SIDEY_APP_STORE_RELEASE_APPROVAL environment gate"
        )
    if plan.get("blockers"):
        raise RuntimeError("Cannot apply a plan with blockers")

    results: list[dict[str, Any]] = []
    created_version_localizations: dict[str, str] = {}
    created_screenshot_sets: dict[str, str] = {}
    for operation in plan.get("operations", []):
        resource = operation["resource"]
        action = operation["action"]
        if resource == "app_info_localization":
            if action == "create":
                body = _json_api(
                    "appInfoLocalizations",
                    {"locale": operation["locale"], **operation["attributes"]},
                    relationships={
                        "appInfo": {"data": {"type": "appInfos", "id": operation["parent_id"]}}
                    },
                )
                result = transport.request("POST", "/v1/appInfoLocalizations", body)
            else:
                body = _json_api(
                    "appInfoLocalizations",
                    operation["attributes"],
                    resource_id=operation["id"],
                )
                result = transport.request("PATCH", f"/v1/appInfoLocalizations/{operation['id']}", body)
        elif resource == "version_localization":
            if action == "create":
                body = _json_api(
                    "appStoreVersionLocalizations",
                    {"locale": operation["locale"], **operation["attributes"]},
                    relationships={
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": operation["parent_id"]}
                        }
                    },
                )
                result = transport.request("POST", "/v1/appStoreVersionLocalizations", body)
                created_id = result.get("data", {}).get("id")
                if not created_id:
                    raise RuntimeError(
                        "App Store Connect omitted the new version localization ID: "
                        + operation["locale"]
                    )
                created_version_localizations[operation["locale"]] = created_id
            else:
                body = _json_api(
                    "appStoreVersionLocalizations",
                    operation["attributes"],
                    resource_id=operation["id"],
                )
                result = transport.request("PATCH", f"/v1/appStoreVersionLocalizations/{operation['id']}", body)
        elif resource == "iap_localization":
            if action == "create":
                body = _json_api(
                    "inAppPurchaseLocalizations",
                    {"locale": operation["locale"], **operation["attributes"]},
                    relationships={
                        "inAppPurchaseV2": {
                            "data": {"type": "inAppPurchases", "id": operation["parent_id"]}
                        }
                    },
                )
                result = transport.request("POST", "/v1/inAppPurchaseLocalizations", body)
            else:
                body = _json_api(
                    "inAppPurchaseLocalizations",
                    operation["attributes"],
                    resource_id=operation["id"],
                )
                result = transport.request("PATCH", f"/v1/inAppPurchaseLocalizations/{operation['id']}", body)
        elif resource == "app_territory":
            body = _json_api(
                "territoryAvailabilities",
                {"available": True},
                resource_id=operation["id"],
            )
            result = transport.request("PATCH", f"/v1/territoryAvailabilities/{operation['id']}", body)
        elif resource == "iap_territories":
            body = _json_api(
                "inAppPurchaseAvailabilities",
                {
                    "availableInNewTerritories": operation[
                        "available_in_new_territories"
                    ]
                },
                relationships={
                    "availableTerritories": {
                        "data": [
                            {"type": "territories", "id": territory}
                            for territory in operation["territories"]
                        ]
                    },
                    "inAppPurchase": {
                        "data": {"type": "inAppPurchases", "id": operation["parent_id"]}
                    },
                },
            )
            result = transport.request("POST", "/v1/inAppPurchaseAvailabilities", body)
        elif resource == "screenshot":
            if action == "delete":
                result = transport.request(
                    "DELETE", f"/v1/appScreenshots/{operation['id']}"
                )
            else:
                locale = operation["locale"]
                screenshot_operation = dict(operation)
                screenshot_operation["version_localization_id"] = (
                    screenshot_operation.get("version_localization_id")
                    or created_version_localizations.get(locale)
                )
                screenshot_operation["screenshot_set_id"] = (
                    screenshot_operation.get("screenshot_set_id")
                    or created_screenshot_sets.get(locale)
                )
                created_screenshot_sets[locale] = _apply_screenshot(
                    transport, screenshot_operation, repository_root
                )
                result = {"uploaded": operation["path"]}
        else:
            raise RuntimeError(f"Unsupported plan operation: {resource}")
        results.append({"operation": operation, "response": result})
    return results


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--commerce-localizations", type=Path, default=DEFAULT_COMMERCE)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--snapshot", type=Path, help="Use an existing read-only snapshot")
    parser.add_argument("--snapshot-output", type=Path, help="Write the fetched snapshot")
    parser.add_argument("--plan-output", type=Path, help="Write the deterministic diff plan")
    parser.add_argument("--apply", action="store_true", help="Apply the generated plan")
    parser.add_argument(
        "--release-approval",
        help="Approved release identity in macos-<version>-build-<build> format",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    desired = load_desired_state(args.manifest, args.commerce_localizations, args.catalog)
    approval_environment = os.environ.get("SIDEY_APP_STORE_RELEASE_APPROVAL")
    if args.apply:
        if args.snapshot:
            raise PermissionError(
                "Apply must fetch a fresh App Store Connect snapshot; --snapshot is dry-run only"
            )
        if (
            args.release_approval != desired.approval_id
            or approval_environment != desired.approval_id
        ):
            raise PermissionError(
                "Apply requires matching --release-approval and "
                "SIDEY_APP_STORE_RELEASE_APPROVAL gates"
            )
    transport: Transport | None = None
    if args.snapshot:
        snapshot = read_json(args.snapshot)
    else:
        issuer_id, key_id, private_key = load_credentials()
        transport = URLTransport(generate_token(issuer_id, key_id, private_key))
        snapshot = collect_snapshot(
            transport,
            bundle_id=desired.manifest["app"]["bundle_id"],
            version=desired.manifest["release"]["version"],
            platform=desired.manifest["app"]["platform"],
        )
    if args.snapshot_output:
        args.snapshot_output.write_text(
            json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    plan = build_plan(desired, snapshot)
    rendered = json.dumps(plan, ensure_ascii=False, indent=2) + "\n"
    if args.plan_output:
        args.plan_output.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")
    if args.apply:
        if transport is None:
            issuer_id, key_id, private_key = load_credentials()
            transport = URLTransport(generate_token(issuer_id, key_id, private_key))
        apply_plan(
            transport,
            plan,
            apply=True,
            release_approval=args.release_approval,
            approval_environment=approval_environment,
        )
    return 2 if plan["blockers"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
