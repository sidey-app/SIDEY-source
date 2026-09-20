---
name: release-notes
description: Research, draft and validate a user-facing SIDEY release note from its exact shipped commit and pull-request range, with author attribution and inclusion or exclusion evidence. Use for Windows GitHub Release bodies, historical direct-distribution macOS notes, or an explicitly identified App Store Connect note; do not use for README, developer documentation, version selection or release publication.
---

# Release Notes

Produce the canonical release body for one platform artifact. General documentation rules remain in `docs/AGENTS.md`; this skill owns the release-specific investigation, attribution, copy and format validation.

## Inputs

Establish the platform, target version and commit, intended artifact, distribution channel, and previous published regular release for that channel. Use the matching `release/*.json` as release metadata. A staged target manifest is not evidence that its tag or App Store build has shipped. Stop with `BLOCKED` if the target, artifact, channel or comparison baseline is ambiguous.

When `release/macos.json` uses the `appstore` channel, existing `docs/releases/v<version>.md` files remain historical Direct GitHub Release bodies. Never overwrite or reinterpret one as an App Store note merely because its marketing version matches. An App Store note requires the exact submitted build, the prior published App Store build, App Store Connect evidence and an explicit destination/localization request. If any of those are missing, report `BLOCKED`; the manifest alone does not authorize or identify a canonical note file.

## Collect and classify evidence

Read [references/evidence.md](references/evidence.md), then use the read-only
[collector](../../../scripts/skills/release-notes/collect_release_evidence.py)
to inventory first-parent integrations, associated pull requests, direct
commits, authors and changed paths in the exact baseline-to-target range. The
inventory is a routing aid, not sufficient evidence for release copy: inspect
the relevant hunks, pull-request context and tests or artifact evidence.

Include only changes consumed by the target platform artifact. Keep macOS and Windows independent. Exclude other-platform work, future work, release-note preparation itself, and internal-only changes without a meaningful user outcome. Record every integration as included or excluded with a reason; unresolved PR association or author attribution is `ACTION REQUIRED`, not a value to invent.

## Draft and verify

Read [references/format.md](references/format.md) before drafting. Translate implementation evidence into a short final-user summary followed by one-sentence change bullets. Preserve installation actions, compatibility limits, data-risk warnings, signing status and known limitations only when users need them or the user requests a separate section. Do not claim unverified functionality, security, signing, testing, availability or release completion.

Write or revise `docs/releases/windows-v<version>.md` for Windows. Revise `docs/releases/v<version>.md` for macOS only when the exact target is a historical Direct GitHub Release. These repository files are the corresponding public GitHub Release bodies. For an explicitly evidenced App Store submission, do not touch a historical Direct note; prepare only the requested App Store Connect destination and localization. Unless the user explicitly requests another section, use only the requested preamble when present, the summary, `## 변경사항`, attributed bullets and the final comparison link for GitHub Release bodies; do not add a release title, date, installation or limitations section by habit.

Save the collector output outside tracked source, then run the
[format validator](../../../scripts/skills/release-notes/validate_release_note.py)
with that evidence and the exact baseline and target tags. Then run the
relevant `scripts/skills/verify_release_consistency.py` mode and validate
changed links. Recheck every bullet's PR or direct-commit reference and author
against the collected evidence.

## Evidence

```text
Platform / version / target commit / artifact
Baseline tag and commit / exact comparison range
Included: PR or commit, author, source evidence -> user-facing outcome
Excluded: PR or commit, author, source evidence -> exclusion reason
Canonical release-note path
Validation: note format, attribution, comparison URL, manifest, links, deterministic checks
Verdict: READY / ACTION REQUIRED / BLOCKED
Unverified claims or missing evidence
```

Do not change milestones or pull requests, create or push a tag, upload an artifact, create or edit a public GitHub Release, submit to a store, or deploy. Publication remains a separate explicitly authorized release operation.
