#!/usr/bin/env python3
"""Verify every Mach-O shipped inside SIDEY supports Apple Silicon and macOS 26."""

import argparse
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys


REQUIRED_ARCHITECTURES = frozenset({"arm64"})
MAXIMUM_MINIMUM_OS = (26, 0, 0)
MACH_O_MAGICS = {
    bytes.fromhex(value) for value in (
        "feedface", "cefaedfe", "feedfacf", "cffaedfe",
        "cafebabe", "bebafeca", "cafebabf", "bfbafeca",
    )
}


def parse_version(value: str) -> tuple[int, int, int]:
    if not re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
        raise ValueError(f"Invalid macOS version: {value!r}")
    parts = [int(part) for part in value.split(".")]
    return tuple(parts + [0] * (3 - len(parts)))


def parse_minimum_os(output: str) -> tuple[int, int, int]:
    versions = []
    for command in re.split(r"(?m)^Load command \d+\s*$", output):
        if re.search(r"(?m)^\s*cmd LC_BUILD_VERSION\s*$", command):
            if not re.search(r"(?m)^\s*platform (?:1|MACOS)\s*$", command):
                raise ValueError("Mach-O build platform is not macOS")
            field = "minos"
        elif re.search(r"(?m)^\s*cmd LC_VERSION_MIN_MACOSX\s*$", command):
            field = "version"
        else:
            continue
        value = re.search(rf"(?m)^\s*{field} (\S+)\s*$", command)
        if value is None:
            raise ValueError(f"Mach-O load command is missing {field}")
        versions.append(parse_version(value.group(1)))
    if len(versions) != 1:
        raise ValueError("Expected exactly one macOS minimum-version load command per slice")
    return versions[0]


def is_mach_o(path: Path) -> bool:
    with path.open("rb") as binary:
        return binary.read(4) in MACH_O_MAGICS


def embedded_binaries(app: Path) -> list[Path]:
    binaries = set()
    for directory, directories, files in os.walk(app, followlinks=False):
        # Framework aliases point at files also reachable through Versions/A.
        for name in directories + files:
            path = Path(directory) / name
            resolved = path.resolve()
            if not resolved.is_relative_to(app):
                raise ValueError(f"Bundle symlink escapes the app: {path}")
        for name in files:
            path = (Path(directory) / name).resolve()
            if path.is_file() and is_mach_o(path):
                binaries.add(path)
    return sorted(binaries)


def run_tool(arguments: list[str]) -> str:
    try:
        return subprocess.run(arguments, check=True, capture_output=True, text=True).stdout
    except subprocess.CalledProcessError as error:
        raise ValueError(f"{' '.join(arguments)} failed: {error.stderr.strip()}") from error


def verify_app(app: Path) -> int:
    app = app.resolve()
    with (app / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    if info.get("LSMinimumSystemVersion") != "26.0":
        raise ValueError("App LSMinimumSystemVersion must be 26.0")
    executable_name = info.get("CFBundleExecutable")
    if not isinstance(executable_name, str) or not executable_name or Path(executable_name).name != executable_name:
        raise ValueError("App CFBundleExecutable must name its main executable")
    executable = app / "Contents/MacOS" / executable_name
    if not executable.is_file() or not is_mach_o(executable):
        raise ValueError(f"Main executable is missing or not Mach-O: {executable}")

    binaries = embedded_binaries(app)
    for binary in binaries:
        architectures = set(run_tool(["/usr/bin/lipo", "-archs", str(binary)]).split())
        if architectures != REQUIRED_ARCHITECTURES:
            raise ValueError(f"{binary}: expected arm64 only, found {sorted(architectures)}")
        for architecture in sorted(architectures):
            try:
                minimum = parse_minimum_os(run_tool([
                    "/usr/bin/otool", "-arch", architecture, "-l", str(binary),
                ]))
            except ValueError as error:
                raise ValueError(f"{binary} ({architecture}): {error}") from error
            if minimum > MAXIMUM_MINIMUM_OS:
                version = ".".join(str(part) for part in minimum)
                raise ValueError(f"{binary} ({architecture}): requires macOS {version}, above 26.0")
    return len(binaries)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    arguments = parser.parse_args()
    try:
        count = verify_app(arguments.app)
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"Binary compatibility verification failed: {error}", file=sys.stderr)
        return 1
    print(f"Verified {count} Mach-O binaries: arm64 only, macOS 26.0 or earlier")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
