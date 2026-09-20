# SIDEY licensing

## Current source code

The SIDEY software in the first Git revision containing the current
proprietary [`LICENSE`](LICENSE) notice and in later revisions is proprietary,
unless a file or component carries a separate license notice. Copyright
remains with the respective copyright holders. No source-code license is
granted merely because a file, build, or public artifact can be viewed or
downloaded.

The repository containing current application and website source is private.
The public `sidey-app/SIDEY` repository is a distribution surface for the
official website, public policy documents, release metadata, and released
binaries. Public availability of those artifacts does not make the current
SIDEY source code open source.

## Historical AGPL revisions

SIDEY software revisions distributed before the first Git revision containing
the current proprietary `LICENSE` notice retain the license stated in each
revision. This includes revisions that were distributed under the **GNU Affero
General Public License, version 3 only** (`AGPL-3.0-only`). Previously granted
permissions are not withdrawn, narrowed, or made conditional by the current
license change or by making the source repository private.

Use, modification, or redistribution of a historical revision must be assessed
against that revision's own license text, source, dependencies, notices, and
asset terms. The public distribution repository is not a promise to publish
source for later proprietary revisions.

When an official binary built from an AGPL-covered historical revision remains
available for download, its exact Corresponding Source and AGPL notice must
remain available by a method that satisfies that release's license obligations.
The public distribution repository may therefore include versioned source
archives for historical AGPL releases. Those archives cover only their recorded
historical revisions and do not expose or license later proprietary source.

## Assets and third-party material

The current proprietary software notice and historical AGPL grants do **not**
by themselves license SIDEY artwork, character sprites, bubbles, throwables,
animations, audio, fonts, logos, or other non-code assets. They also do not
replace existing third-party licenses or attribution notices.

- Paid assets identified by [`assets/v1/manifest.json`](assets/v1/manifest.json)
  remain subject to the [SIDEY Paid Asset License 1.0](assets/PAID_ASSET_LICENSE.md),
  including the copies and derivatives covered by that license.
- Review assets with their own scope notice retain that notice, including
  [`docs/reviews/character-five/LICENSE.md`](docs/reviews/character-five/LICENSE.md).
- Third-party components and other materials retain their separately stated
  terms. If no permission is stated for a non-code asset, its visibility is not
  a grant to reuse or redistribute it.

Permission to use software does not by itself authorize bundling restricted
assets. A redistributed historical build must independently satisfy the terms
of the assets and dependencies it includes, or replace or omit them.

## Brand, service, and repository boundaries

No trademark license to use the SIDEY name or logo as the branding of another
product is granted here. Lawful references to the product remain unaffected.
Official service access and paid-asset entitlements are separate from rights
granted for any historical software revision.

The separately maintained backend and administration repositories are outside
the scope of this notice. Public website output, release metadata, and binaries
do not grant access to or rights in those repositories or the private SIDEY
source repository.

## Contributions and reports

SIDEY no longer accepts external code, documentation, translation, or asset
contributions. The public repository accepts bug reports through GitHub Issues;
see [CONTRIBUTING.md](CONTRIBUTING.md). Existing contributor copyright,
attribution, agreements, and license grants remain unchanged.
