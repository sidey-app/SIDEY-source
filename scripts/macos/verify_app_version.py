#!/usr/bin/env python3
"""Verify the user-facing and update versions embedded in a SIDEY app bundle."""

from __future__ import annotations

import argparse
import plistlib
import sys
from pathlib import Path


class AppVersionError(RuntimeError):
    pass


def verify_info_plist(
    info_plist: Path, expected_product_version: str, expected_build: str
) -> None:
    try:
        info = plistlib.loads(info_plist.read_bytes())
    except (OSError, plistlib.InvalidFileException) as error:
        raise AppVersionError(
            f"cannot read built app metadata at {info_plist}: {error}"
        ) from error
    if not isinstance(info, dict):
        raise AppVersionError(f"built app metadata at {info_plist} must be a dictionary")

    actual_product_version = info.get("CFBundleShortVersionString")
    if actual_product_version != expected_product_version:
        raise AppVersionError(
            "built app CFBundleShortVersionString mismatch: "
            f"expected {expected_product_version!r}, found {actual_product_version!r}"
        )

    actual_build = info.get("CFBundleVersion")
    if actual_build != expected_build:
        raise AppVersionError(
            "built app CFBundleVersion mismatch: "
            f"expected {expected_build!r}, found {actual_build!r}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--product-version", required=True)
    parser.add_argument("--build", required=True)
    args = parser.parse_args()

    info_plist = args.app / "Contents" / "Info.plist"
    try:
        verify_info_plist(info_plist, args.product_version, args.build)
    except AppVersionError as error:
        print(f"app version error: {error}", file=sys.stderr)
        return 1

    print(
        f"verified built SIDEY.app version: {args.product_version} ({args.build})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
