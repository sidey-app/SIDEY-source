# SIDEY Documentation and Release Instructions

These instructions apply to `docs/**`. They also govern the root `README.md` when the repository-root routing sends a task here.

## Document boundaries

- `product/**` describes current product behavior, `architecture.md` describes current
  system boundaries, `decisions/**` preserves only long-lived rationale, and `operations/**`
  contains repeatable procedures. Do not put plans, completed checklists or ordinary change
  history into current-state documents.
- Machine-readable source and code own exact prices, IDs, versions, build numbers, asset
  hashes and platform settings. Link to those sources instead of copying their values into
  Markdown. Use Git/PR history for ordinary implementation history.
- Public README and release writing is for users. Internal architecture, review evidence, operational history and contributor procedures may retain the technical detail needed for their audience; do not force public marketing style onto them.
- Windows contributor documentation under `windows/docs/**` follows `windows/docs/AGENTS.md`, not this directory's location and language layout.

## Public README contract

- Keep `README.md` as the Korean entry point in its established polite conversational style. Keep English, Japanese, Simplified Chinese, Traditional Chinese, Russian and Ukrainian translations at `docs/readme/README.<locale>.md`, with valid links among all seven editions.
- Preserve the durable introduction, official website, preview, separate macOS and Windows installation sections, contribution guidance, credits and policy links.
- macOS installation links only to the Mac App Store; Windows installation links to the official GitHub Releases page. Do not duplicate version numbers, build numbers, versioned artifact filenames, update histories or roadmaps in README files.
- Store badges use the repository's official SVG assets. A store badge or availability statement must match a confirmed public product URL and shipped state.
- Keep development setup, backend architecture, build instructions and internal rollout language out of the public README.

## Release documentation contract

- `release/macos.json` records the App Store target version/build, not public review or publication status. `release/windows.json` owns the public Windows version. Native project settings and Windows update metadata are validated mirrors.
- `docs/releases/v<version>.md` is the canonical macOS release body and `docs/releases/windows-v<version>.md` is the canonical Windows release body. Keep platform releases independent and do not copy an unverified change between them.
- Release notes lead with a short verified user outcome, use the exact `## 변경사항` section, attribute every change bullet to its pull request or direct commit and GitHub author, and end with the exact platform comparison URL. Follow the format and evidence rules in the release-notes skill rather than copying a historical note whose layout may be obsolete.
- Add installation steps, required warnings or limitations only when the user requests a separate section or verified user action or risk makes the information necessary. Keep implementation details only when users must act on them.
- Use the official website and GitHub Releases URLs. Do not claim signing, testing, compatibility, availability or release completion without evidence from the exact target commit and artifact.

Use [release notes](../.agents/skills/release-notes/SKILL.md) when researching or drafting the canonical note or GitHub Release body for a specific platform release. Use [version audit](../.agents/skills/version-audit/SKILL.md) when the release needs an evidence-based version or build decision. General README work is governed by this file without a separate Skill. Validate versions and links with `scripts/skills/verify_release_consistency.py`, resolve changed relative Markdown links, inspect translations affected by the change and run `git diff --check`. Drafting documentation does not authorize tags, uploads, publication or deployment.
