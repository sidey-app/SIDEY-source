#!/usr/bin/env python3
"""Collect read-only pull-request evidence for a SIDEY release range."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import Callable, Sequence

SOURCE_REPOSITORY = "sidey-app/SIDEY-source"
PUBLIC_REPOSITORY = "sidey-app/SIDEY"
CommandRunner = Callable[[Sequence[str], Path], str]


class CollectionError(RuntimeError):
    """Raised when immutable release evidence cannot be collected."""


def run_command(command: Sequence[str], cwd: Path) -> str:
    """Run one read-only command and return normalized standard output."""

    result = subprocess.run(
        command,
        cwd=cwd,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise CollectionError(f"{' '.join(command[:4])} failed: {detail}")
    return result.stdout.replace("\r\n", "\n").rstrip("\n")


def git(
    root: Path,
    *arguments: str,
    runner: CommandRunner = run_command,
) -> str:
    """Run a read-only Git command."""

    return runner(("git", *arguments), root)


def resolve_commit(
    root: Path,
    reference: str,
    runner: CommandRunner,
) -> str:
    """Resolve a reference to one full commit ID."""

    commit = git(
        root,
        "rev-parse",
        "--verify",
        f"{reference}^{{commit}}",
        runner=runner,
    ).strip()
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise CollectionError(
            f"Reference did not resolve to a commit: {reference}"
        )
    return commit


def require_ancestor(
    root: Path,
    baseline: str,
    target: str,
    runner: CommandRunner,
) -> None:
    """Require the baseline to be in the target's history."""

    runner(("git", "merge-base", "--is-ancestor", baseline, target), root)


def parse_commit_details(source: str) -> dict[str, str]:
    """Parse the NUL-delimited commit fields emitted by Git."""

    fields = source.split("\0")
    if len(fields) != 5:
        raise CollectionError("Git returned malformed commit metadata")
    return {
        "commit": fields[0],
        "subject": fields[1],
        "git_author_name": fields[2],
        "git_author_email": fields[3],
        "authored_at": fields[4],
    }


def github_json(
    root: Path,
    endpoint: str,
    runner: CommandRunner,
) -> object:
    """Read one GitHub API endpoint and decode its JSON response."""

    source = runner(
        (
            "gh",
            "api",
            "-H",
            "Accept: application/vnd.github+json",
            endpoint,
        ),
        root,
    )
    try:
        return json.loads(source)
    except json.JSONDecodeError as error:
        raise CollectionError(
            f"GitHub returned malformed JSON for {endpoint}"
        ) from error


def exact_pull_requests(
    pulls: object,
    commit: str,
) -> list[dict[str, object]]:
    """Return merged PRs whose recorded merge commit is exact."""

    if not isinstance(pulls, list):
        raise CollectionError("GitHub commit-to-pulls response was not a list")
    return [
        pull
        for pull in pulls
        if isinstance(pull, dict)
        and pull.get("merged_at")
        and str(pull.get("merge_commit_sha", "")).lower() == commit
    ]


def pull_record(
    details: dict[str, str],
    paths: list[str],
    pull: dict[str, object],
) -> dict[str, object]:
    """Create a normalized pull-request integration record."""

    user = pull.get("user")
    author = user.get("login") if isinstance(user, dict) else None
    if not author:
        raise CollectionError(
            f"Pull request author is unresolved for commit {details['commit']}"
        )
    return {
        **details,
        "kind": "pull_request",
        "reference": f"#{pull['number']}",
        "pull_request": pull["number"],
        "author": author,
        "url": pull.get("html_url"),
        "changed_paths": paths,
    }


def direct_commit_record(
    root: Path,
    repository: str,
    details: dict[str, str],
    paths: list[str],
    runner: CommandRunner,
) -> dict[str, object]:
    """Create an attributed direct-commit integration record."""

    commit = details["commit"]
    metadata = github_json(
        root,
        f"repos/{repository}/commits/{commit}",
        runner,
    )
    if not isinstance(metadata, dict):
        raise CollectionError(
            f"GitHub commit response was invalid for {commit}"
        )
    user = metadata.get("author")
    author = user.get("login") if isinstance(user, dict) else None
    return {
        **details,
        "kind": "direct_commit",
        "reference": commit[:7],
        "author": author,
        "url": metadata.get("html_url"),
        "changed_paths": paths,
        "attribution_status": "resolved" if author else "action_required",
    }


def collect_evidence(
    root: Path,
    baseline_reference: str,
    target_reference: str,
    repository: str = SOURCE_REPOSITORY,
    target_tag: str | None = None,
    public_repository: str = PUBLIC_REPOSITORY,
    runner: CommandRunner = run_command,
) -> dict[str, object]:
    """Collect normalized first-parent integrations for one release range."""

    baseline = resolve_commit(root, baseline_reference, runner)
    target = resolve_commit(root, target_reference, runner)
    release_target = target_tag or target_reference
    require_ancestor(root, baseline, target, runner)
    commit_source = git(
        root,
        "rev-list",
        "--first-parent",
        "--reverse",
        f"{baseline}..{target}",
        runner=runner,
    )
    commits = [line for line in commit_source.splitlines() if line]
    if not commits:
        raise CollectionError(
            "Release range contains no first-parent integrations"
        )
    integrations: list[dict[str, object]] = []

    for commit in commits:
        detail_source = git(
            root,
            "show",
            "-s",
            "--format=%H%x00%s%x00%aN%x00%aE%x00%aI",
            commit,
            runner=runner,
        )
        details = parse_commit_details(detail_source)
        path_source = git(
            root,
            "diff-tree",
            "--root",
            "--no-commit-id",
            "--name-only",
            "-r",
            "-z",
            commit,
            runner=runner,
        )
        paths = sorted(path for path in path_source.split("\0") if path)
        pulls = github_json(
            root,
            f"repos/{repository}/commits/{commit}/pulls",
            runner,
        )
        exact = exact_pull_requests(pulls, commit)
        if len(exact) > 1:
            numbers = sorted(str(pull.get("number")) for pull in exact)
            raise CollectionError(
                f"Commit {commit} maps to multiple exact PRs: "
                f"{', '.join(numbers)}"
            )
        if exact:
            integrations.append(pull_record(details, paths, exact[0]))
        else:
            integrations.append(
                direct_commit_record(
                    root,
                    repository,
                    details,
                    paths,
                    runner,
                )
            )

    gaps = [
        record["reference"]
        for record in integrations
        if record.get("attribution_status") == "action_required"
    ]
    net_path_source = git(
        root,
        "diff",
        "--name-only",
        "-z",
        baseline,
        target,
        runner=runner,
    )
    return {
        "schema_version": 2,
        "source_repository": repository,
        "public_repository": public_repository,
        "baseline": {
            "reference": baseline_reference,
            "commit": baseline,
        },
        "target": {
            "reference": release_target,
            "source_reference": target_reference,
            "commit": target,
        },
        "public_release_url": (
            f"https://github.com/{public_repository}/releases/tag/{target_tag}"
            if target_tag
            else None
        ),
        "net_changed_paths": sorted(
            path for path in net_path_source.split("\0") if path
        ),
        "integrations": integrations,
        "action_required": gaps,
    }


def parser() -> argparse.ArgumentParser:
    """Build the command-line parser."""

    command = argparse.ArgumentParser(description=__doc__)
    command.add_argument("--base", required=True, help="Previous platform tag")
    command.add_argument(
        "--target",
        required=True,
        help="Target tag or commit",
    )
    command.add_argument(
        "--target-tag",
        help="Expected release tag used in the public release URL",
    )
    command.add_argument(
        "--repo-root",
        type=Path,
        default=Path.cwd(),
        help="SIDEY checkout root (defaults to the working directory)",
    )
    command.add_argument(
        "--repository",
        default=SOURCE_REPOSITORY,
        help=(
            "Private source GitHub owner/repository "
            f"(default: {SOURCE_REPOSITORY})"
        ),
    )
    command.add_argument(
        "--public-repository",
        default=PUBLIC_REPOSITORY,
        help=(
            "Public release GitHub owner/repository "
            f"(default: {PUBLIC_REPOSITORY})"
        ),
    )
    command.add_argument(
        "--output",
        type=Path,
        help="Optional UTF-8 JSON output path; stdout is always written",
    )
    return command


def main(arguments: Sequence[str] | None = None) -> int:
    """Run the collector CLI."""

    options = parser().parse_args(arguments)
    root = options.repo_root.resolve()
    try:
        evidence = collect_evidence(
            root,
            options.base,
            options.target,
            options.repository,
            options.target_tag,
            options.public_repository,
        )
    except CollectionError as error:
        print(f"release evidence error: {error}", file=sys.stderr)
        return 1

    source = json.dumps(evidence, ensure_ascii=False, indent=2) + "\n"
    if options.output:
        options.output.parent.mkdir(parents=True, exist_ok=True)
        options.output.write_text(source, encoding="utf-8")
    print(source, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
