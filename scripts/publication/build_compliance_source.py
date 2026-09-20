#!/usr/bin/env python3
"""Build an exact, deterministic source archive declared for release migration."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
from typing import Any


DEFAULT_CONTRACT = Path(__file__).with_name("compliance-source-assets.json")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return "sha256:" + digest.hexdigest()


def load_contract(path: Path) -> dict[str, Any]:
    contract = json.loads(path.read_text(encoding="utf-8"))
    if contract.get("schema") != 1 or not isinstance(contract.get("assets"), list):
        raise ValueError(f"Unsupported compliance source contract: {path}")
    return contract


def find_asset(contract: dict[str, Any], tag: str) -> dict[str, Any]:
    matches = [asset for asset in contract["assets"] if asset.get("tag") == tag]
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one compliance source asset for {tag}")
    return matches[0]


def validate_asset(asset: dict[str, Any]) -> None:
    for field in ("source_commit", "license_introduction_commit"):
        if re.fullmatch(r"[0-9a-f]{40}", str(asset.get(field, ""))) is None:
            raise ValueError(f"Invalid {field} for {asset.get('tag')}")
    if re.fullmatch(r"sha256:[0-9a-f]{64}", str(asset.get("digest", ""))) is None:
        raise ValueError(f"Invalid digest for {asset.get('tag')}")
    if not isinstance(asset.get("size"), int) or asset["size"] <= 0:
        raise ValueError(f"Invalid size for {asset.get('tag')}")
    name = str(asset.get("name", ""))
    prefix = str(asset.get("archive_prefix", ""))
    if Path(name).name != name or not name.endswith(".tar"):
        raise ValueError(f"Invalid compliance source filename: {name}")
    if not prefix or not prefix.endswith("/") or ".." in Path(prefix).parts:
        raise ValueError(f"Invalid archive prefix for {asset.get('tag')}")


def run_git(repository: Path, *arguments: str) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["git", "-C", str(repository), *arguments],
        check=False,
        capture_output=True,
    )


def build(repository: Path, output_dir: Path, asset: dict[str, Any]) -> Path:
    validate_asset(asset)
    repository = repository.resolve(strict=True)
    source_commit = str(asset["source_commit"])
    license_commit = str(asset["license_introduction_commit"])
    ancestry = run_git(repository, "merge-base", "--is-ancestor", license_commit, source_commit)
    if ancestry.returncode != 0:
        raise ValueError(
            f"{source_commit} does not descend from licensing commit {license_commit}"
        )

    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / str(asset["name"])
    archive = run_git(
        repository,
        "archive",
        "--format=tar",
        f"--prefix={asset['archive_prefix']}",
        source_commit,
    )
    if archive.returncode != 0:
        detail = archive.stderr.decode(errors="replace").strip()
        raise RuntimeError(f"git archive failed: {detail}")
    output.write_bytes(archive.stdout)

    actual_size = output.stat().st_size
    actual_digest = sha256(output)
    if actual_size != asset["size"] or actual_digest != asset["digest"]:
        output.unlink(missing_ok=True)
        raise ValueError(
            "Compliance source archive does not match its declared size and digest: "
            f"expected {asset['size']} / {asset['digest']}, "
            f"got {actual_size} / {actual_digest}"
        )
    return output


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    parser.add_argument("--repository", type=Path, default=Path.cwd())
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--contract", type=Path, default=DEFAULT_CONTRACT)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    contract = load_contract(args.contract)
    asset = find_asset(contract, args.tag)
    output = build(args.repository, args.output_dir, asset)
    print(f"ComplianceSourceArchive={output}")
    print(f"ComplianceSourceDigest={asset['digest']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
