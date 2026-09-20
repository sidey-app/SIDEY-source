#!/usr/bin/env python3
"""Validate SIDEY's canonical Korean release-note body format."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
from typing import Sequence

CHANGES_HEADING = "## 변경사항"
LOGIN_PATTERN = r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?"
BULLET_PATTERN = re.compile(
    rf"^- (?P<description>.+) \( "
    rf"(?P<reference>PR \d+|commit [0-9a-f]{{7}}), "
    rf"@(?P<author>{LOGIN_PATTERN}) \)$"
)


class NoteError(RuntimeError):
    """Raised when a release note violates the canonical format."""


def evidence_attributions(evidence: object) -> dict[str, str]:
    """Return resolved release-note references and their authors."""

    if not isinstance(evidence, dict):
        raise NoteError("Release evidence must be a JSON object")
    integrations = evidence.get("integrations")
    if not isinstance(integrations, list):
        raise NoteError("Release evidence has no integrations list")
    attributions: dict[str, str] = {}
    for record in integrations:
        if not isinstance(record, dict):
            raise NoteError("Release evidence contains an invalid integration")
        reference = record.get("reference")
        author = record.get("author")
        if isinstance(reference, str) and isinstance(author, str):
            display_reference = (
                f"PR {reference[1:]}"
                if re.fullmatch(r"#\d+", reference)
                else f"commit {reference}"
            )
            attributions[display_reference] = author
    return attributions


def validate_note(
    source: str,
    baseline: str,
    target: str,
    evidence: object | None = None,
) -> None:
    """Validate one release-note body against exact source-range tags."""

    normalized = source.replace("\r\n", "\n").replace("\r", "\n")
    lines = normalized.splitlines()
    heading_indexes = [
        index for index, line in enumerate(lines) if line == CHANGES_HEADING
    ]
    if len(heading_indexes) != 1:
        raise NoteError(
            f"Release note must contain one exact {CHANGES_HEADING!r}"
        )
    heading = heading_indexes[0]
    introduction = [line for line in lines[:heading] if line.strip()]
    prose = [
        line
        for line in introduction
        if line != "---" and not line.startswith("#")
    ]
    if not prose:
        raise NoteError(
            "Release note needs a final-user summary before 변경사항"
        )

    nonblank = [index for index, line in enumerate(lines) if line.strip()]
    if not nonblank:
        raise NoteError("Release note must not be empty")
    casefolded = normalized.casefold()
    if "github.com/sidey-app/sidey/compare/" in casefolded:
        raise NoteError(
            "Public release notes must not claim a source comparison URL"
        )
    if "github.com/sidey-app/sidey-source" in casefolded:
        raise NoteError(
            "Public release notes must not link the private source repository"
        )
    note_end = nonblank[-1] + 1
    following_heading = next(
        (
            index
            for index in range(heading + 1, note_end)
            if lines[index].startswith("## ")
        ),
        note_end,
    )
    bullets = [
        line for line in lines[heading + 1:following_heading] if line.strip()
    ]
    if not bullets:
        raise NoteError("변경사항 must contain at least one attributed bullet")
    matches = [BULLET_PATTERN.fullmatch(line) for line in bullets]
    invalid = [line for line, match in zip(bullets, matches) if match is None]
    if invalid:
        raise NoteError(
            "Every change must be one attributed bullet in the form "
            "'- 변경 사항 ( PR 123, @author )' or "
            "'- 변경 사항 ( commit 1a2b3c4, @author )': "
            + repr(invalid[0])
        )
    if evidence is not None:
        if not isinstance(evidence, dict):
            raise NoteError("Release evidence must be a JSON object")
        baseline_data = evidence.get("baseline")
        target_data = evidence.get("target")
        if not isinstance(baseline_data, dict) or not isinstance(
            target_data, dict
        ):
            raise NoteError("Release evidence is missing range endpoints")
        if baseline_data.get("reference") != baseline:
            raise NoteError("Release evidence baseline does not match --base")
        if target_data.get("reference") != target:
            raise NoteError("Release evidence target does not match --target")
        attributions = evidence_attributions(evidence)
        for match in matches:
            if match is None:
                continue
            reference = match.group("reference")
            author = match.group("author")
            if attributions.get(reference) != author:
                raise NoteError(
                    "Release-note attribution is absent from exact evidence: "
                    f"{reference}, @{author}"
                )


def parser() -> argparse.ArgumentParser:
    """Build the command-line parser."""

    command = argparse.ArgumentParser(description=__doc__)
    command.add_argument("path", type=Path, help="Canonical release-note file")
    command.add_argument("--base", required=True, help="Previous platform tag")
    command.add_argument("--target", required=True, help="Target platform tag")
    command.add_argument(
        "--evidence",
        type=Path,
        help="Collector JSON used to verify references and authors",
    )
    return command


def main(arguments: Sequence[str] | None = None) -> int:
    """Run the validator CLI."""

    options = parser().parse_args(arguments)
    try:
        source = options.path.read_text(encoding="utf-8")
        evidence = None
        if options.evidence:
            evidence = json.loads(options.evidence.read_text(encoding="utf-8"))
        validate_note(source, options.base, options.target, evidence)
    except (OSError, UnicodeError, json.JSONDecodeError, NoteError) as error:
        print(f"release note error: {error}", file=sys.stderr)
        return 1
    print(f"Release note format is valid: {options.path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
