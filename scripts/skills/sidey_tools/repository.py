"""Git queries and branch ownership policy for repository tools."""

from __future__ import annotations

import re
from pathlib import Path

from .errors import WorkflowError
from .process import run


def git(root: str | Path, *args: str) -> str:
    """Run Git from *root* and return its standard output."""

    return run(root, "git", *args)


def root_at(path: str | Path) -> Path:
    """Return the repository root containing *path*."""

    return Path(git(path, "rev-parse", "--show-toplevel")).resolve()


def branch(root: str | Path) -> str:
    """Return the current branch name for *root*."""

    return git(root, "symbolic-ref", "--quiet", "--short", "HEAD")


def changed_paths(
    root: str | Path,
    base: str,
    revision: str = "HEAD",
) -> list[str]:
    """Return paths changed since the merge base of two revisions."""

    merge_base = git(root, "merge-base", base, revision)
    output = git(
        root,
        "diff",
        "--no-renames",
        "--name-only",
        "-z",
        merge_base,
        revision,
    )
    return sorted(set(output.split("\0")) - {""})


def platform_for(path: str) -> str:
    """Return the branch platform that owns *path*."""

    if path in {"release/macos.json", "release/app-store-localizations.json"}:
        return "macos"
    if path == "release/windows.json":
        return "windows"
    if path.startswith(("macos/", "scripts/macos/")):
        return "macos"
    if path in {
        ".github/workflows/macos-build-and-tests.yml",
        ".github/workflows/validate-macos.yml",
    }:
        return "macos"
    if path.startswith(("windows/", "scripts/windows/")):
        return "windows"
    if re.fullmatch(
        r"\.github/workflows/"
        r"(?:publish-windows-release|validate-windows|"
        r"windows-build-and-tests|windows-release)\.yml",
        path,
    ):
        return "windows"
    return "shared"


def validate_paths(branch_name: str, paths: list[str]) -> str:
    """Validate that changed paths belong to the branch platform."""

    match = re.fullmatch(
        r"(shared|macos|windows)/[A-Za-z0-9][A-Za-z0-9._/-]*",
        branch_name,
    )
    if not match:
        raise WorkflowError(
            "Implementation requires shared/*, macos/* or windows/* "
            "(never main)"
        )

    platform = match[1]
    invalid = [path for path in paths if platform_for(path) != platform]
    if invalid:
        changed = ", ".join(invalid)
        raise WorkflowError(
            f"{branch_name} crosses its platform boundary: {changed}"
        )
    return platform
