#!/usr/bin/env python3
"""Reject source, credentials, and other private files from a Pages artifact."""

from __future__ import annotations

import argparse
from pathlib import Path
import re


DEFAULT_PUBLIC_REPOSITORY = "sidey-app/SIDEY"
ALLOWED_SUFFIXES = {
    ".avif",
    ".css",
    ".gif",
    ".html",
    ".ico",
    ".jpeg",
    ".jpg",
    ".js",
    ".json",
    ".mjs",
    ".mp3",
    ".ogg",
    ".pdf",
    ".png",
    ".svg",
    ".txt",
    ".wasm",
    ".wav",
    ".webmanifest",
    ".webp",
    ".xml",
}
ALLOWED_SPECIAL_FILES = {".nojekyll", "CNAME", "assets/store/README.md"}
DENIED_PATH_PARTS = {
    ".git",
    ".github",
    ".idea",
    ".vscode",
    "node_modules",
    "scripts",
    "src",
    "tests",
}
DENIED_SUFFIXES = {
    ".astro",
    ".cs",
    ".csproj",
    ".env",
    ".key",
    ".map",
    ".mobileprovision",
    ".p12",
    ".pbxproj",
    ".pem",
    ".ps1",
    ".py",
    ".scss",
    ".sh",
    ".sln",
    ".slnx",
    ".swift",
    ".ts",
    ".tsx",
    ".xcconfig",
}
SECRET_PATTERNS = {
    "GitHub token": re.compile(rb"(?:gh[oprsu]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})"),
    "private key": re.compile(rb"-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----"),
    "Supabase service role key": re.compile(rb"(?:service_role|SUPABASE_SERVICE_ROLE_KEY)"),
}
REQUIRED_FILES = {
    ".nojekyll",
    "index.html",
    "en/index.html",
    "ja/index.html",
    "ko/index.html",
    "windows-latest.json",
    "windows/update.json",
}


def validate_repository(repository: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository) is None:
        raise ValueError(f"Invalid GitHub repository: {repository}")
    return repository


def validate_tree(root: Path, repository: str = DEFAULT_PUBLIC_REPOSITORY) -> list[str]:
    repository = validate_repository(repository)
    root = root.resolve(strict=True)
    if not root.is_dir():
        raise ValueError(f"Public tree is not a directory: {root}")

    errors: list[str] = []
    present: set[str] = set()
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            errors.append(f"symlink is not allowed: {relative}")
            continue
        if not path.is_file():
            continue
        present.add(relative)
        parts = set(Path(relative).parts[:-1])
        suffix = path.suffix.lower()
        if parts & DENIED_PATH_PARTS:
            errors.append(f"private path is not allowed: {relative}")
        if relative not in ALLOWED_SPECIAL_FILES and suffix not in ALLOWED_SUFFIXES:
            errors.append(f"file type is not allowlisted: {relative}")
        if suffix in DENIED_SUFFIXES:
            errors.append(f"source or credential file is not allowed: {relative}")

        if path.stat().st_size <= 10 * 1024 * 1024:
            content = path.read_bytes()
            for description, pattern in SECRET_PATTERNS.items():
                if pattern.search(content):
                    errors.append(f"{description} detected: {relative}")

    for relative in sorted(REQUIRED_FILES - present):
        errors.append(f"required public file is missing: {relative}")

    if errors:
        heading = f"Public tree validation failed for {repository}:"
        raise ValueError(heading + "\n" + "\n".join(f"- {error}" for error in errors))
    return sorted(present)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--repository", default=DEFAULT_PUBLIC_REPOSITORY)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    files = validate_tree(args.root, args.repository)
    print(f"PublicTreeValidated={args.repository}")
    print(f"PublicFileCount={len(files)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
