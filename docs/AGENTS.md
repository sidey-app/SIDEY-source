# SIDEY Documentation and Release Instructions

These instructions apply to `docs/**`.

## Document boundaries

- `product/**` describes current product behavior, `architecture.md` describes current
  system boundaries, `decisions/**` preserves only long-lived rationale, and `operations/**`
  contains repeatable procedures. Do not put plans, completed checklists or ordinary change
  history into current-state documents.
- Machine-readable source and code own exact prices, IDs, versions, build numbers, asset
  hashes and platform settings. Link to those sources instead of copying their values into
  Markdown. Use Git/PR history for ordinary implementation history.
- Public release writing is for users. Internal architecture, review evidence, operational history and contributor procedures may retain the technical detail needed for their audience; do not force public marketing style onto them.
- Windows contributor documentation under `windows/docs/**` follows `windows/docs/AGENTS.md`, not this directory's location and language layout.

## Release documentation contract

- `release/macos.json` records the App Store target version/build, not public review or publication status. `release/windows.json` owns the public Windows version. Native project settings and Windows update metadata are validated mirrors.
- Existing `docs/releases/v<version>.md` files are private historical copies of deleted direct-distribution GitHub Release bodies. Do not revise, republish or recreate those releases, and do not rewrite one as an App Store note merely because the marketing version matches. App Store release notes require the exact submitted build and App Store Connect evidence. `docs/releases/windows-v<version>.md` remains the canonical Windows release body.
- Release notes lead with a short verified user outcome, use the exact `## 변경사항` section, and attribute every change bullet to its private-source pull request or direct commit and GitHub author without linking private source from the public body. Do not add a public repository comparison URL: the public distribution repository does not contain current source history. Follow the format and evidence rules in the release-notes skill rather than copying a historical note whose layout may be obsolete.
- Add installation steps, required warnings or limitations only when the user requests a separate section or verified user action or risk makes the information necessary. Keep implementation details only when users must act on them.
- Use the official website and GitHub Releases URLs. Do not claim signing, testing, compatibility, availability or release completion without evidence from the exact target commit and artifact.

Use [release notes](../.agents/skills/release-notes/SKILL.md) when researching or drafting the canonical note or GitHub Release body for a specific platform release. Use [version audit](../.agents/skills/version-audit/SKILL.md) when the release needs an evidence-based version or build decision. Validate versions and links with `scripts/skills/verify_release_consistency.py` and run `git diff --check`. Drafting documentation does not authorize tags, uploads, publication or deployment.
