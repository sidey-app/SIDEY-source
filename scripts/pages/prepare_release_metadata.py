#!/usr/bin/env python3
"""Prepare the verified SIDEY artifact served by GitHub Pages."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil


APP_STORE_URL = "https://apps.apple.com/kr/app/sidey/id6808528060?mt=12"
LOCALES = ("ko", "en", "ja")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--website-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--windows-release-manifest", type=Path, required=True)
    parser.add_argument("--windows-release-installer", type=Path, required=True)
    return parser.parse_args()


def read_manifest(path: Path, platform: str) -> dict[str, object]:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    version = str(manifest.get("version", ""))
    if (
        manifest.get("schema") != 1
        or manifest.get("platform") != platform
        or manifest.get("channel") != "production"
        or re.fullmatch(r"\d+\.\d+\.\d+", version) is None
    ):
        raise ValueError(
            f"release/{platform}.json must describe a stable production {platform} release."
        )
    return manifest


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_anchor(html: str, element_id: str, **attributes: str) -> None:
    lookaheads = [rf'(?=[^>]*\bid="{re.escape(element_id)}")']
    lookaheads.extend(
        rf'(?=[^>]*\b{re.escape(name)}="{re.escape(value)}")'
        for name, value in attributes.items()
    )
    if re.search("<a" + "".join(lookaheads) + "[^>]*>", html) is None:
        raise ValueError(f"Verified download link is missing: {element_id}")


def replace_checksum(html: str, platform: str, digest: str) -> str:
    element_id = f"{platform}-download-sha256"
    pattern = re.compile(
        rf'(<code(?=[^>]*\bid="{re.escape(element_id)}")'
        rf'(?=[^>]*\bdata-release-platform="{platform}")[^>]*>)[^<]*(</code>)'
    )
    updated, replacements = pattern.subn(rf"\g<1>{digest}\g<2>", html)
    if replacements == 0:
        raise ValueError(f"Release SHA-256 field is missing: {platform}")
    return updated


def prepare(
    website_dir: Path,
    output_dir: Path,
    windows_release_manifest: Path,
    windows_release_installer: Path,
) -> tuple[str, str]:
    website_dir = website_dir.resolve(strict=True)
    windows_release_manifest = windows_release_manifest.resolve(strict=True)
    windows_release_installer = windows_release_installer.resolve(strict=True)
    output_dir = output_dir.resolve()

    windows_manifest = read_manifest(windows_release_manifest, "windows")
    windows_version = str(windows_manifest["version"])
    windows_name = f"SIDEY-Windows-x64-v{windows_version}-Setup.exe"
    if windows_release_installer.name != windows_name:
        raise ValueError(
            "Windows release installer filename does not match the public contract: "
            + windows_name
        )
    if output_dir.exists() and any(output_dir.iterdir()):
        raise ValueError(f"Pages output directory must be empty: {output_dir}")

    output_dir.mkdir(parents=True, exist_ok=True)
    shutil.copytree(website_dir, output_dir, dirs_exist_ok=True)
    windows_hash = sha256(windows_release_installer)
    windows_url = (
        "https://github.com/sidey-app/SIDEY/releases/download/"
        f"windows-v{windows_version}/{windows_name}"
    )
    published_windows_manifest = {
        "channel": "production",
        "version": windows_version,
        "tag": f"windows-v{windows_version}",
        "installer_url": windows_url,
        "sha256": windows_hash,
    }
    manifest_text = json.dumps(published_windows_manifest, indent=2) + "\n"
    for relative_path in ("windows-latest.json", "windows/update.json"):
        path = output_dir / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(manifest_text, encoding="utf-8", newline="\n")

    for locale in LOCALES:
        relative_path = Path(locale) / "index.html"
        path = output_dir / relative_path
        if not path.is_file():
            raise ValueError(f"Localized landing page is missing: {relative_path.as_posix()}")
        html = path.read_text(encoding="utf-8")
        require_anchor(
            html,
            "primary-download-action",
            href=APP_STORE_URL,
            **{"data-macos-url": APP_STORE_URL, "data-windows-url": windows_url},
        )
        require_anchor(html, "macos-download-action", href=APP_STORE_URL)
        require_anchor(html, "windows-download-action", href=windows_url)
        html = replace_checksum(html, "windows", windows_hash)
        path.write_text(html, encoding="utf-8", newline="\n")

    return windows_version, windows_hash


def main() -> int:
    args = parse_args()
    windows_version, windows_hash = prepare(
        args.website_dir,
        args.output_dir,
        args.windows_release_manifest,
        args.windows_release_installer,
    )
    print("ReleaseMetadataPrepared=true")
    print(f"WindowsVersion={windows_version}")
    print(f"WindowsSHA256={windows_hash}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
