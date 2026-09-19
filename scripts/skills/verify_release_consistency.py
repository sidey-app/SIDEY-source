#!/usr/bin/env python3
"""Validate SIDEY's authoritative platform release manifests and their mirrors."""

from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SEMVER = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
APP_STORE_URL = "https://apps.apple.com/kr/app/sidey/id6808528060"
RELEASES_URL = "https://github.com/sidey-app/SIDEY/releases"
README_PATHS = ("README.md",) + tuple(
    f"docs/readme/README.{language}.md"
    for language in ("en", "ja", "ru", "uk", "zh-Hans", "zh-Hant")
)


class ConsistencyError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ConsistencyError(message)


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def release_display(platform: str, path: str = "README.md") -> str:
    source = read(path)
    heading = {"macos": "macOS", "windows": "Windows"}[platform]
    sections = list(re.finditer(rf"^### {heading}[ \t]*$", source, re.MULTILINE))
    require(len(sections) == 1,
            f"{path} must have exactly one ### {heading} installation section")
    following = source[sections[0].end():]
    return re.split(r"^#{1,3} ", following, maxsplit=1, flags=re.MULTILINE)[0]


def validate_readme_release_links(platform: str) -> None:
    for path in README_PATHS:
        require((ROOT / path).is_file(), f"README translation is missing: {path}")
        display = release_display(platform, path)
        expected_url = APP_STORE_URL if platform == "macos" else RELEASES_URL
        official_link = re.escape(expected_url)
        require(re.search(rf'\]\({official_link}\)|href=[\"\']{official_link}[\"\']',
                          display) is not None,
                f"{path} {platform} installation must link to {expected_url}")
        if platform == "macos":
            require(not re.search(r"\.dmg|Homebrew|brew install|/releases", display, re.I),
                    f"{path} macOS installation must use only the Mac App Store")
        urls = re.findall(r'https?://[^\s<>\"\'`)\]]+', display)
        require(all(url == RELEASES_URL for url in urls if "/releases" in url),
                f"{path} {platform} installation has a noncanonical or versioned release URL")
        require(re.search(r"SIDEY-(?:macOS|Windows)-[^\s/<>]*v[0-9]+\.[0-9]+\.[0-9]+",
                          display) is None,
                f"{path} {platform} installation must not pin an installer version")


def load_manifest(platform: str) -> dict[str, object]:
    path = ROOT / "release" / f"{platform}.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    required = {"schema", "platform", "channel", "version"}
    if platform == "macos":
        required.add("build")
    require(set(data) == required, f"{path} must contain exactly {sorted(required)}")
    require(data["schema"] == 1, f"{path} has an unsupported schema")
    require(data["platform"] == platform, f"{path} has the wrong platform")
    expected_channel = "appstore" if platform == "macos" else "production"
    require(data["channel"] == expected_channel,
            f"{path} must use the {expected_channel} channel")
    require(
        isinstance(data["version"], str) and SEMVER.fullmatch(data["version"]),
        f"{path} must contain a stable semantic version",
    )
    if platform == "macos":
        require(
            isinstance(data["build"], int) and data["build"] > 0,
            f"{path} must contain a positive numeric build",
        )
    return data


def project_values_for_bundle_identifier(
    source: str, bundle_identifier: str, setting: str
) -> set[str]:
    values: set[str] = set()
    matching_configurations = 0
    for body in re.findall(r"buildSettings = \{(.*?)\n\s*\};", source, re.DOTALL):
        settings = dict(re.findall(r"\b([A-Z][A-Z0-9_]*) = ([^;]+);", body))
        configured_bundle = settings.get("PRODUCT_BUNDLE_IDENTIFIER", "").strip('"')
        if configured_bundle != bundle_identifier:
            continue
        matching_configurations += 1
        if setting in settings:
            values.add(settings[setting].strip('"'))
    require(
        matching_configurations > 0,
        f"no build configurations found for {bundle_identifier}",
    )
    require(
        len(values) == 1,
        f"{setting} for {bundle_identifier} must have one value, found {sorted(values)}",
    )
    return values


def project_value_for_bundle_identifier(
    source: str, bundle_identifier: str, setting: str
) -> str:
    return next(iter(project_values_for_bundle_identifier(
        source, bundle_identifier, setting
    )))


def validate_macos() -> dict[str, str]:
    manifest = load_manifest("macos")
    version = str(manifest["version"])
    build = str(manifest["build"])
    project = read("macos/SIDEY.xcodeproj/project.pbxproj")
    bundle = "app.sidey.desktop.appstore"
    require(project_value_for_bundle_identifier(project, bundle, "MARKETING_VERSION") == version,
            "Mac App Store project version does not match release/macos.json")
    require(project_value_for_bundle_identifier(project, bundle, "CURRENT_PROJECT_VERSION") == build,
            "Mac App Store project build does not match release/macos.json")
    release_data = read("website/src/data/releases.ts")
    require(APP_STORE_URL in release_data and "url: appStoreURL" in release_data,
            "website macOS installation must use the Mac App Store")
    require(".dmg" not in release_data,
            "website release data must not offer retired macOS installers")
    validate_readme_release_links("macos")
    return {"version": version, "build": build, "tag": f"appstore-{version}-{build}"}


def validate_windows(allow_unreleased_source: bool = False) -> dict[str, str]:
    manifest = load_manifest("windows")
    version = str(manifest["version"])
    tag = f"windows-v{version}"
    installer_name = f"SIDEY-Windows-x64-v{version}-Setup.exe"
    installer_url = (
        f"https://github.com/sidey-app/SIDEY/releases/download/{tag}/{installer_name}"
    )
    notes = f"docs/releases/{tag}.md"

    project = ET.parse(ROOT / "windows" / "src" / "Sidey.App" / "Sidey.App.csproj")
    values = {element.tag: (element.text or "") for element in project.getroot().iter()}
    source_version = values.get("Version", "")
    require(SEMVER.fullmatch(source_version) is not None,
            "Windows project must contain a stable semantic version")
    if source_version != version:
        require(allow_unreleased_source,
                "Windows project version does not match release/windows.json")
        require(
            tuple(map(int, source_version.split(".")))
            > tuple(map(int, version.split("."))),
                "unreleased Windows source version must be newer than the public release")
    require(values.get("FileVersion") == f"{source_version}.0",
            "Windows file version does not match the project version")
    require(values.get("AssemblyVersion") == f"{source_version}.0",
            "Windows assembly version does not match the project version")
    update_source_paths = sorted(
        (ROOT / "windows" / "src" / "Sidey.Platform.Windows").rglob(
            "WindowsUpdateService.cs"
        )
    )
    require(
        len(update_source_paths) == 1,
        "Windows updater source must resolve to exactly one WindowsUpdateService.cs",
    )
    update_source = update_source_paths[0].read_text(encoding="utf-8")
    require(f'CurrentVersion = "{source_version}"' in update_source,
            "Windows updater version does not match the project version")
    require((ROOT / notes).is_file(), f"Windows release notes are missing: {notes}")

    validate_readme_release_links("windows")
    release_data = read("website/src/data/releases.ts")
    require("version: windowsRelease.version" in release_data,
            "website release data must derive the Windows version from release/windows.json")
    require("SIDEY-Windows-x64-v${windowsRelease.version}-Setup.exe" in release_data,
            "website release data has the wrong Windows installer URL template")
    require("releases/tag/windows-v${windowsRelease.version}" in release_data,
            "website release data has the wrong Windows release URL template")

    return {
        "version": version,
        "tag": tag,
        "installer_name": installer_name,
        "installer_url": installer_url,
        "release_notes": notes,
        "source_version": source_version,
    }


def write_github_output(path: Path, values: dict[str, str]) -> None:
    with path.open("a", encoding="utf-8", newline="\n") as output:
        for key, value in values.items():
            require("\n" not in value and "\r" not in value, f"invalid output: {key}")
            output.write(f"{key}={value}\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=("all", "macos", "windows"), default="all")
    parser.add_argument("--github-output", type=Path)
    parser.add_argument(
        "--allow-unreleased-source",
        action="store_true",
        help="allow a Windows source version newer than the current public manifest",
    )
    args = parser.parse_args()

    outputs: dict[str, str] = {}
    try:
        if args.platform in ("all", "macos"):
            outputs = validate_macos()
        if args.platform in ("all", "windows"):
            windows = validate_windows(args.allow_unreleased_source)
            outputs = windows if args.platform == "windows" else outputs
    except (ConsistencyError, ET.ParseError, json.JSONDecodeError) as error:
        print(f"release consistency error: {error}", file=sys.stderr)
        return 1

    if args.github_output:
        write_github_output(args.github_output, outputs)
    if args.platform == "all":
        print("release metadata is consistent for macOS and Windows")
    else:
        print(f"release metadata is consistent for {args.platform}: {outputs['tag']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
