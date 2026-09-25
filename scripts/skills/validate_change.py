#!/usr/bin/env python3
"""Validate change policy and resolve its required checks."""

import json
import os
import sys
from pathlib import Path

from sidey_tools import WorkflowError
from sidey_tools.policy import (
    PullRequestValidationError,
    validate_message,
    validate_pr_body,
    validate_subject,
)
from sidey_tools.repository import (
    changed_paths,
    git,
    root_at,
    validate_paths,
)
from validation_scope import required_scopes


def verify_gate(scopes, needs):
    required = set(scopes) | {"scope"}
    failures = {
        name: needs.get(name, {}).get("result", "missing")
        for name in required
        if needs.get(name, {}).get("result") != "success"
    }
    if failures:
        raise WorkflowError(f"Required checks did not succeed: {failures}")


def verify_commit_contract(messages, pr_title=None):
    failures = []
    if pr_title is not None:
        violations = validate_subject(pr_title)
        if violations:
            failures.append(
                f"PR title {pr_title!r}: {'; '.join(violations)}"
            )
    for message in messages:
        violations = validate_message(message)
        if violations:
            subject = message.splitlines()[0] if message.splitlines() else ""
            failures.append(
                f"commit message {subject!r}: {'; '.join(violations)}"
            )
    if failures:
        details = " | ".join(failures)
        raise WorkflowError(f"Commit policy validation failed: {details}")


def verify_pr_contract(root, body, paths):
    try:
        return validate_pr_body(root, body or "", paths)
    except PullRequestValidationError as error:
        message = f"Pull request validation failed: {error}"
        raise WorkflowError(message) from error


def validate_pr_paths(branch, paths, *, root=None, base=None, revision="HEAD"):
    return validate_paths(
        branch, paths, root=root, base=base, revision=revision,
    )


def commit_messages(root, base, revision):
    return [
        message.strip("\r\n")
        for message in git(
            root,
            "log",
            "--format=%B%x00",
            f"{base}..{revision}",
        ).split("\0")
        if message.strip("\r\n")
    ]


def resolve_change(root, event):
    """Validate an event and return its diff and required scopes."""

    pr = event.get("pull_request")
    base = pr["base"]["sha"] if pr else event["before"]
    revision = pr["head"]["sha"] if pr else event["after"]
    paths = changed_paths(root, base, revision)
    if pr:
        verify_commit_contract(
            commit_messages(root, base, revision),
            pr.get("title"),
        )
        verify_pr_contract(root, pr.get("body"), paths)
        validate_pr_paths(
            pr["head"]["ref"], paths, root=root, base=base, revision=revision,
        )
    else:
        verify_commit_contract(commit_messages(root, base, revision))
    # Revalidate edited PR metadata without repeating expensive source
    # validation when the head is unchanged.
    edited_pull_request = pr and event.get("action") == "edited"
    scopes = [] if edited_pull_request else required_scopes(paths)
    return {
        "base": base,
        "head": revision,
        "paths": paths,
        "scopes": scopes,
    }


def main():
    if sys.argv[1:] == ["gate"]:
        needs = json.loads(os.environ["SIDEY_NEEDS"])
        scope_outputs = needs.get("scope", {}).get("outputs", {})
        scopes = json.loads(scope_outputs.get("scopes", "[]"))
        verify_gate(scopes, needs)
        print("All applicable checks succeeded")
        return
    event_path = Path(os.environ["GITHUB_EVENT_PATH"])
    event = json.loads(event_path.read_text())
    root = root_at(".")
    change = resolve_change(root, event)
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        serialized_scopes = json.dumps(change["scopes"])
        output.write(f"scopes={serialized_scopes}\n")
    print(json.dumps(change, indent=2))


if __name__ == "__main__":
    main()
