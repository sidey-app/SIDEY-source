# Release-note Evidence

Use this reference while researching the exact release range.

## Establish immutable endpoints

Resolve the previous published regular platform tag and the target commit. For macOS tags use `v<version>`; for Windows use `windows-v<version>`. Confirm that the baseline is an ancestor of the target and record both full commit IDs. Do not treat a staged manifest, draft release or branch name as proof of a shipped endpoint.

Run the skill-local collector from the repository root:

```text
python3 scripts/skills/release-notes/collect_release_evidence.py --base <previous-tag> --target <target-commit> --target-tag <release-tag> --output <temporary-json-path>
```

The collector is read-only. It follows the target's first-parent history so a traditional merge is represented once and SIDEY's squash integrations remain one record each. It resolves pull requests through GitHub's commit-to-pulls API because SIDEY squash subjects intentionally contain the Korean PR title without a `(#number)` suffix.

Source commit and pull-request evidence comes from the private `sidey-app/SIDEY-source` repository. The public `sidey-app/SIDEY` repository owns release artifacts and URLs but not current source history. Do not substitute public artifact tags for the source comparison range.

If GitHub authentication or commit metadata is unavailable, report `BLOCKED`. Do not fall back to guessing PR numbers from commit messages. More than one exact PR association for one integration is `ACTION REQUIRED`.

## Inspect and classify

For every collected integration:

1. Inspect the changed paths and relevant hunks, not only the title or PR body.
2. Confirm whether the selected platform artifact consumes the change.
3. Identify a concrete user-visible outcome or exclude the integration with a reason.
4. Verify claims with tests, manifests, artifact evidence or current behavior as appropriate.

Normally exclude release-note-only, version bookkeeping, CI-only and internal refactoring changes unless they produce a user-visible result for the artifact. A pull request may justify multiple bullets when it contains distinct user outcomes. Several pull requests may share one bullet when they implement one coherent outcome.

## Attribution

Use the pull-request opener returned by GitHub for a PR bullet. In the public body, write `PR 108` without `#` so GitHub does not link it to an unrelated public issue or pull request. Do not link the private source repository, and do not credit the merging account or `Co-authored-by: codex` as the PR author.

For a direct commit with no associated pull request, use its seven-character commit ID and GitHub commit-author login:

```text
- 변경 사항을 설명해요. ( commit 3a25b84, @author )
```

If GitHub cannot resolve the direct commit to an account, return `ACTION REQUIRED`; do not invent a username. Keep the direct commit in the included or excluded ledger even when no bullet is ultimately needed.
