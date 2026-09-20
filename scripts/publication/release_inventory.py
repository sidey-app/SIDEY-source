#!/usr/bin/env python3
"""Capture and compare deterministic GitHub Release migration inventories."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from typing import Any


DEFAULT_SOURCE_REPOSITORY = "sidey-app/SIDEY-source"
DEFAULT_TARGET_REPOSITORY = "sidey-app/SIDEY"
DEFAULT_COMPLIANCE_CONTRACT = Path(__file__).with_name("compliance-source-assets.json")


def validate_repository(repository: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository) is None:
        raise ValueError(f"Invalid GitHub repository: {repository}")
    return repository


def _asset(asset: dict[str, Any]) -> dict[str, Any]:
    digest = asset.get("digest")
    return {
        "name": str(asset.get("name", "")),
        "size": int(asset.get("size", 0)),
        "digest": str(digest) if digest else None,
    }


def normalize(releases: list[dict[str, Any]], repository: str) -> dict[str, Any]:
    repository = validate_repository(repository)
    normalized: list[dict[str, Any]] = []
    for release in releases:
        body = str(release.get("body") or "")
        normalized.append(
            {
                "tag": str(release.get("tag_name", "")),
                "name": str(release.get("name") or ""),
                "draft": bool(release.get("draft", False)),
                "prerelease": bool(release.get("prerelease", False)),
                "published_at": release.get("published_at"),
                "target_commitish": str(release.get("target_commitish") or ""),
                "body": body,
                "body_sha256": hashlib.sha256(body.encode("utf-8")).hexdigest(),
                "assets": sorted(
                    (_asset(asset) for asset in release.get("assets", [])),
                    key=lambda item: item["name"],
                ),
            }
        )
    normalized.sort(key=lambda item: item["tag"])
    return {"schema": 1, "repository": repository, "releases": normalized}


def fetch(repository: str) -> list[dict[str, Any]]:
    repository = validate_repository(repository)
    completed = subprocess.run(
        [
            "gh",
            "api",
            "--paginate",
            "--slurp",
            f"repos/{repository}/releases?per_page=100",
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or "gh api failed without an error message"
        raise RuntimeError(f"Could not read releases from {repository}: {detail}")
    pages = json.loads(completed.stdout)
    return [release for page in pages for release in page]


def load_inventory(path: Path) -> dict[str, Any]:
    inventory = json.loads(path.read_text(encoding="utf-8"))
    if inventory.get("schema") != 1 or not isinstance(inventory.get("releases"), list):
        raise ValueError(f"Unsupported release inventory: {path}")
    return inventory


def load_compliance_contract(path: Path) -> dict[str, Any]:
    contract = json.loads(path.read_text(encoding="utf-8"))
    if contract.get("schema") != 1 or not isinstance(contract.get("assets"), list):
        raise ValueError(f"Unsupported compliance source contract: {path}")
    return contract


def canonical_release_body(body: Any) -> str:
    """Ignore only terminal line endings that GitHub strips during publication."""
    return str(body or "").rstrip("\r\n")


def comparable_release(
    release: dict[str, Any], assets: list[dict[str, Any]], body: str
) -> dict[str, Any]:
    return {
        **{
            key: release.get(key)
            for key in ("tag", "name", "draft", "prerelease")
        },
        "body_sha256": hashlib.sha256(body.encode("utf-8")).hexdigest(),
        "assets": assets,
    }


def compliance_assets_by_tag(
    contract: dict[str, Any] | None,
) -> tuple[dict[str, list[dict[str, Any]]], dict[str, str], list[str]]:
    by_tag: dict[str, list[dict[str, Any]]] = {}
    body_appends_by_tag: dict[str, str] = {}
    errors: list[str] = []
    if contract is None:
        return by_tag, body_appends_by_tag, errors
    if contract.get("schema") != 1 or not isinstance(contract.get("assets"), list):
        return by_tag, body_appends_by_tag, ["unsupported compliance source contract"]
    for asset in contract["assets"]:
        tag = str(asset.get("tag", ""))
        source_commit = str(asset.get("source_commit", ""))
        license_commit = str(asset.get("license_introduction_commit", ""))
        body_append = asset.get("release_body_append")
        projected = {
            "name": str(asset.get("name", "")),
            "size": asset.get("size"),
            "digest": asset.get("digest"),
        }
        if not tag or not projected["name"]:
            errors.append("compliance source asset must declare tag and name")
            continue
        if re.fullmatch(r"[0-9a-f]{40}", source_commit) is None:
            errors.append(f"compliance source asset has invalid source commit: {tag}")
        if re.fullmatch(r"[0-9a-f]{40}", license_commit) is None:
            errors.append(f"compliance source asset has invalid license commit: {tag}")
        if not isinstance(projected["size"], int) or projected["size"] <= 0:
            errors.append(f"compliance source asset has invalid size: {tag}/{projected['name']}")
        if re.fullmatch(r"sha256:[0-9a-f]{64}", str(projected["digest"])) is None:
            errors.append(
                f"compliance source asset has invalid digest: {tag}/{projected['name']}"
            )
        if body_append is not None:
            if not isinstance(body_append, str) or not canonical_release_body(body_append):
                errors.append(f"compliance release body append must be non-empty: {tag}")
            else:
                canonical_append = canonical_release_body(body_append)
                existing_append = body_appends_by_tag.get(tag)
                if existing_append is not None and existing_append != canonical_append:
                    errors.append(f"conflicting compliance release body append: {tag}")
                body_appends_by_tag[tag] = canonical_append
        by_tag.setdefault(tag, []).append(projected)
    for tag, assets in by_tag.items():
        names = [asset["name"] for asset in assets]
        if len(names) != len(set(names)):
            errors.append(f"duplicate compliance source asset name: {tag}")
        assets.sort(key=lambda item: item["name"])
    return by_tag, body_appends_by_tag, errors


def verify(
    source: dict[str, Any],
    target: dict[str, Any],
    target_repository: str,
    compliance_contract: dict[str, Any] | None = None,
) -> None:
    target_repository = validate_repository(target_repository)
    if target.get("repository") != target_repository:
        raise ValueError(
            "Target inventory repository mismatch: "
            f"expected {target_repository}, got {target.get('repository')}"
        )

    source_by_tag = {release["tag"]: release for release in source["releases"]}
    target_by_tag = {release["tag"]: release for release in target["releases"]}
    compliance_by_tag, body_appends_by_tag, errors = compliance_assets_by_tag(
        compliance_contract
    )
    for tag in sorted(compliance_by_tag.keys() - source_by_tag.keys()):
        errors.append(f"compliance source asset references unknown release: {tag}")
    if compliance_contract is not None:
        for declared in compliance_contract["assets"]:
            tag = str(declared.get("tag", ""))
            release = source_by_tag.get(tag)
            if release is None:
                continue
            target_commitish = str(release.get("target_commitish", ""))
            if re.fullmatch(r"[0-9a-f]{40}", target_commitish) and target_commitish != declared.get(
                "source_commit"
            ):
                errors.append(f"compliance source commit differs from source release: {tag}")
    for label, releases in (("source", source_by_tag), ("target", target_by_tag)):
        for tag, release in sorted(releases.items()):
            for asset in release.get("assets", []):
                digest = asset.get("digest")
                if not digest:
                    errors.append(
                        f"{label} asset is missing a digest: {tag}/{asset.get('name')}"
                    )
                elif re.fullmatch(r"sha256:[0-9a-f]{64}", str(digest)) is None:
                    errors.append(
                        f"{label} asset has an invalid digest: {tag}/{asset.get('name')}"
                    )
    for tag in sorted(source_by_tag.keys() - target_by_tag.keys()):
        errors.append(f"missing target release: {tag}")
    for tag in sorted(target_by_tag.keys() - source_by_tag.keys()):
        errors.append(f"unexpected target release: {tag}")
    for tag in sorted(source_by_tag.keys() & target_by_tag.keys()):
        expected_assets = sorted(
            source_by_tag[tag].get("assets", []) + compliance_by_tag.get(tag, []),
            key=lambda item: item["name"],
        )
        actual_assets = sorted(
            target_by_tag[tag].get("assets", []), key=lambda item: item["name"]
        )
        expected_body = canonical_release_body(source_by_tag[tag].get("body"))
        body_append = body_appends_by_tag.get(tag)
        if body_append:
            expected_body = (
                f"{expected_body}\n\n{body_append}" if expected_body else body_append
            )
        actual_body = canonical_release_body(target_by_tag[tag].get("body"))
        if comparable_release(
            source_by_tag[tag], expected_assets, expected_body
        ) != comparable_release(
            target_by_tag[tag], actual_assets, actual_body
        ):
            errors.append(f"release metadata or assets differ: {tag}")
    if errors:
        raise ValueError("Release inventory verification failed:\n" + "\n".join(errors))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    capture = subparsers.add_parser("capture")
    capture.add_argument("--repository", default=DEFAULT_SOURCE_REPOSITORY)
    capture.add_argument("--api-json", type=Path)
    capture.add_argument("--output", type=Path, required=True)

    compare = subparsers.add_parser("verify")
    compare.add_argument("--source", type=Path, required=True)
    compare.add_argument("--target", type=Path)
    compare.add_argument("--target-repository", default=DEFAULT_TARGET_REPOSITORY)
    compare.add_argument(
        "--compliance-contract", type=Path, default=DEFAULT_COMPLIANCE_CONTRACT
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.command == "capture":
        raw = (
            json.loads(args.api_json.read_text(encoding="utf-8"))
            if args.api_json
            else fetch(args.repository)
        )
        inventory = normalize(raw, args.repository)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps(inventory, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
            newline="\n",
        )
        print(f"ReleaseInventoryCaptured={args.repository}")
        print(f"ReleaseCount={len(inventory['releases'])}")
        return 0

    source = load_inventory(args.source)
    target = (
        load_inventory(args.target)
        if args.target
        else normalize(fetch(args.target_repository), args.target_repository)
    )
    contract = load_compliance_contract(args.compliance_contract)
    verify(source, target, args.target_repository, contract)
    print(f"ReleaseInventoryVerified={args.target_repository}")
    print(f"ReleaseCount={len(source['releases'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
