#!/usr/bin/env python3
"""Reject empty SIDEY pull request descriptions without enforcing a layout."""

from __future__ import annotations

from pathlib import Path
import re

GENERAL_TEMPLATE = Path(".github/PULL_REQUEST_TEMPLATE/general.md")
GENERAL_MARKER = "<!-- SIDEY_GENERAL_PR_TEMPLATE: keep -->"


class PullRequestValidationError(ValueError):
    """Raised when a pull request body has no visible description."""


def validate_pr_body(
    root: Path,
    body: str,
    paths: list[str],
    *,
    label: str = "PR body",
) -> str:
    """Accept a nonempty description in any format."""

    visible_text = re.sub(r"<!--.*?-->", "", body, flags=re.DOTALL).strip()
    if not visible_text:
        raise PullRequestValidationError(f"{label} must include a description")
    return "general"
