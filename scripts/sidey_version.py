#!/usr/bin/env python3
"""Resolve and validate SIDEY product and platform update versions."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import re
import subprocess
import sys
from pathlib import Path
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
SEMVER = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
MAX_MSIX_COMPONENT = 65535
MAX_WINDOWS_REVISION = 999


class VersionError(RuntimeError):
    """Raised when version metadata is malformed or inconsistent."""


@dataclass(frozen=True)
class SideyVersion:
    product_version: str
    windows_revision: int
    mac_build: int
    major: int
    minor: int
    patch: int

    @property
    def msix_build(self) -> int:
        return self.patch * 1000 + self.windows_revision

    @property
    def msix_version(self) -> str:
        return f"{self.major}.{self.minor}.{self.msix_build}.0"

    @property
    def windows_update_version(self) -> str:
        return f"{self.major}.{self.minor}.{self.msix_build}"

    @property
    def windows_release_version(self) -> str:
        return (
            self.product_version
            if self.windows_revision == 0
            else self.windows_update_version
        )

    @property
    def assembly_version(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}.0"

    def as_dict(self) -> dict[str, object]:
        return {
            "productVersion": self.product_version,
            "windowsRevision": self.windows_revision,
            "macBuild": self.mac_build,
            "msixBuild": self.msix_build,
            "msixVersion": self.msix_version,
            "windowsUpdateVersion": self.windows_update_version,
            "windowsReleaseVersion": self.windows_release_version,
            "assemblyVersion": self.assembly_version,
        }


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VersionError(message)


def _integer(data: dict[str, object], key: str) -> int:
    value = data.get(key)
    require(
        isinstance(value, int) and not isinstance(value, bool),
        f"{key} must be an integer",
    )
    return value


def parse_version_data(data: dict[str, object]) -> SideyVersion:
    expected = {"schema", "productVersion", "windowsRevision", "macBuild"}
    require(set(data) == expected, f"version source must contain exactly {sorted(expected)}")
    require(data["schema"] == 1, "version source has an unsupported schema")

    product_version = data["productVersion"]
    require(isinstance(product_version, str), "productVersion must be a string")
    match = SEMVER.fullmatch(product_version)
    require(match is not None, "productVersion must use stable Major.Minor.Patch format")
    major, minor, patch = (int(part) for part in match.groups())

    windows_revision = _integer(data, "windowsRevision")
    mac_build = _integer(data, "macBuild")
    require(major >= 1, "Product Version major must be at least 1 for Microsoft Store")
    require(major <= MAX_MSIX_COMPONENT, "Product Version major exceeds the MSIX limit 65535")
    require(minor <= MAX_MSIX_COMPONENT, "Product Version minor exceeds the MSIX limit 65535")
    require(
        0 <= windows_revision <= MAX_WINDOWS_REVISION,
        "windowsRevision must be between 0 and 999",
    )
    require(mac_build >= 1, "macBuild must be a positive integer")

    version = SideyVersion(
        product_version=product_version,
        windows_revision=windows_revision,
        mac_build=mac_build,
        major=major,
        minor=minor,
        patch=patch,
    )
    require(
        version.msix_build <= MAX_MSIX_COMPONENT,
        "Patch * 1000 + windowsRevision exceeds the MSIX Build limit 65535: "
        f"{patch} * 1000 + {windows_revision} = {version.msix_build}",
    )
    return version


def load_version(root: Path = ROOT) -> SideyVersion:
    path = root / "release" / "version.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise VersionError(f"cannot read {path}: {error}") from error
    require(isinstance(data, dict), f"{path} must contain a JSON object")
    return parse_version_data(data)


def load_version_at_git_ref(reference: str, root: Path = ROOT) -> SideyVersion:
    def show(path: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", "show", f"{reference}:{path}"],
            cwd=root,
            check=False,
            capture_output=True,
            text=True,
        )

    completed = show("release/version.json")
    if completed.returncode != 0:
        windows = show("release/windows.json")
        macos = show("release/macos.json")
        require(
            windows.returncode == 0 and macos.returncode == 0,
            f"cannot read version metadata at {reference}",
        )
        try:
            windows_data = json.loads(windows.stdout)
            macos_data = json.loads(macos.stdout)
        except json.JSONDecodeError as error:
            raise VersionError(
                f"legacy release metadata at {reference} is invalid JSON: {error}"
            ) from error
        return parse_version_data({
            "schema": 1,
            "productVersion": windows_data.get("version"),
            "windowsRevision": 0,
            "macBuild": macos_data.get("build"),
        })
    try:
        data = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise VersionError(
            f"release/version.json at {reference} is invalid JSON: {error}"
        ) from error
    require(isinstance(data, dict), f"release/version.json at {reference} must be an object")
    return parse_version_data(data)


def validate_transition(previous: SideyVersion, current: SideyVersion) -> None:
    previous_semver = (previous.major, previous.minor, previous.patch)
    current_semver = (current.major, current.minor, current.patch)
    require(
        current_semver >= previous_semver,
        "Product Version must not decrease",
    )
    if current_semver != previous_semver:
        require(
            current.windows_revision == 0,
            "windowsRevision must reset to 0 when Product Version changes",
        )
    else:
        require(
            current.windows_revision >= previous.windows_revision,
            "windowsRevision must not decrease within the same Product Version",
        )
    require(current.mac_build >= previous.mac_build, "macBuild must not decrease")


def render_windows_props(version: SideyVersion) -> str:
    return f"""<Project>
  <!-- Generated by scripts/sidey_version.py from release/version.json. -->
  <PropertyGroup>
    <SideyProductVersion>{version.product_version}</SideyProductVersion>
    <SideyWindowsRevision>{version.windows_revision}</SideyWindowsRevision>
    <SideyWindowsUpdateVersion>{version.windows_update_version}</SideyWindowsUpdateVersion>
    <SideyWindowsReleaseVersion>{version.windows_release_version}</SideyWindowsReleaseVersion>
    <SideyMsixVersion>{version.msix_version}</SideyMsixVersion>
    <Version>{version.product_version}</Version>
    <VersionPrefix>{version.product_version}</VersionPrefix>
    <AssemblyVersion>{version.assembly_version}</AssemblyVersion>
    <FileVersion>{version.msix_version}</FileVersion>
    <InformationalVersion>{version.product_version}</InformationalVersion>
    <IncludeSourceRevisionInInformationalVersion>false</IncludeSourceRevisionInInformationalVersion>
  </PropertyGroup>
</Project>
"""


def render_macos_xcconfig(version: SideyVersion) -> str:
    return (
        "// Generated by scripts/sidey_version.py from release/version.json.\n"
        f"MARKETING_VERSION = {version.product_version}\n"
        f"CURRENT_PROJECT_VERSION = {version.mac_build}\n"
    )


def render_release_manifest(platform: str, version: SideyVersion) -> str:
    if platform == "windows":
        data = {
            "schema": 1,
            "platform": "windows",
            "channel": "production",
            "version": version.product_version,
            "windowsRevision": version.windows_revision,
            "updateVersion": version.windows_update_version,
            "releaseVersion": version.windows_release_version,
            "msixVersion": version.msix_version,
        }
    elif platform == "macos":
        data = {
            "schema": 1,
            "platform": "macos",
            "channel": "appstore",
            "version": version.product_version,
            "build": version.mac_build,
        }
    else:
        raise VersionError(f"unsupported platform: {platform}")
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


def _expected_files(platform: str, version: SideyVersion) -> dict[Path, str]:
    if platform == "windows":
        return {
            Path("release/windows.json"): render_release_manifest("windows", version),
            Path("windows/Version.props"): render_windows_props(version),
        }
    if platform == "macos":
        return {
            Path("release/macos.json"): render_release_manifest("macos", version),
            Path("macos/Config/Version.xcconfig"): render_macos_xcconfig(version),
        }
    raise VersionError(f"unsupported platform: {platform}")


def check_platform(platform: str, root: Path = ROOT) -> None:
    version = load_version(root)
    for relative_path, expected in _expected_files(platform, version).items():
        path = root / relative_path
        require(path.is_file(), f"generated version mirror is missing: {relative_path}")
        require(
            path.read_text(encoding="utf-8") == expected,
            f"generated version mirror is stale: {relative_path}; run "
            f"python3 scripts/sidey_version.py --write {platform}",
        )

    if platform == "windows":
        try:
            ET.parse(root / "windows" / "Version.props")
        except ET.ParseError as error:
            raise VersionError(f"windows/Version.props is invalid XML: {error}") from error


def write_platform(platform: str, root: Path = ROOT) -> None:
    version = load_version(root)
    for relative_path, content in _expected_files(platform, version).items():
        path = root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--check", choices=("windows", "macos"))
    action.add_argument("--write", choices=("windows", "macos"))
    action.add_argument("--json", action="store_true")
    action.add_argument("--check-transition", metavar="GIT_REF")
    action.add_argument(
        "--get",
        choices=(
            "productVersion",
            "windowsRevision",
            "macBuild",
            "msixBuild",
            "msixVersion",
            "windowsUpdateVersion",
            "windowsReleaseVersion",
            "assemblyVersion",
        ),
    )
    args = parser.parse_args()
    try:
        if args.check:
            check_platform(args.check)
            print(f"{args.check} version metadata is current")
        elif args.write:
            write_platform(args.write)
            print(f"updated {args.write} version mirrors")
        elif args.check_transition:
            current = load_version()
            previous = load_version_at_git_ref(args.check_transition)
            validate_transition(previous, current)
            print(f"version transition from {args.check_transition} is valid")
        else:
            version = load_version()
            data = version.as_dict()
            if args.json:
                print(json.dumps(data, separators=(",", ":")))
            else:
                print(data[args.get])
    except VersionError as error:
        print(f"version error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
