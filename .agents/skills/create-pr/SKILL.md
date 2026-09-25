---
name: create-pr
description: Prepare or create a SIDEY pull request from the exact reviewed and validated task head using the repository template and workflow. Use for pull request titles, bodies, previews or publication; do not use for code review, merging, releases or deployments.
---

# Create Pull Request

Read the root `AGENTS.md` and the internal validation and pull request section
of [CONTRIBUTING.md](../../../CONTRIBUTING.md#validation-and-pull-requests),
then inspect the complete changed-path set. Start from
`.github/PULL_REQUEST_TEMPLATE/general.md` when useful and include concrete
change and validation evidence in any format. External asset contributions
are not accepted. This applies equally to agent-created and manual pull requests.

Separate local preparation from remote publication. Drafting a title, body or
preview does not authorize a push or pull request creation. Immediately before
the first remote mutation, confirm that the current user request explicitly
authorizes publishing the branch and creating the pull request. If it does
not, return the prepared title and body without changing remote state.

## Prepare

1. Confirm the task-owned worktree, branch prefix, integration base and current
   HEAD. Require a clean worktree and a committed task head.
2. Review the full diff and commit range against the current base. Reject
   unrelated paths, prohibited platform mixing and unreviewed changes.
3. Confirm that required checks passed for this exact HEAD. A failed, skipped,
   unavailable or stale check blocks publication.
4. Write a title that passes
   `scripts/skills/commit/validate_commit_message.py --subject`.
   Do not add a pull request number to the title.
5. Describe the change and validation evidence. The general template is a
   starting point, not a required layout. Do not mark a failed or inapplicable
   check as passed.
6. Validate the body with the repository pull request validator and present
   the base, head, title, body and exact commit for review.

## Publish

Use `scripts/skills/workflow.py` for freshness, ownership, push and pull request
creation. Do not replace it with an ad hoc `git push` or `gh pr create` path.
After publication, read the pull request back and confirm its number, URL,
base, head commit, title and body.

Stop after the pull request exists. Do not merge it, wait indefinitely for CI,
release, upload or deploy. Those operations require separate instructions.
GitHub owns the squash commit title and body through the repository's merge
message settings; do not pass custom squash subject or body overrides.

If the branch already has a pull request, update or reuse it only when it
targets the same task branch and exact reviewed head. Otherwise stop and report
the conflict.
