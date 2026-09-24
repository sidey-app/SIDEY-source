# SIDEY release metadata

`version.json` is the only manually edited source for SIDEY's shared Product Version,
Windows revision and macOS build number. `python3 scripts/sidey_version.py --write macos`
and `--write windows` update the platform release and native build mirrors. The matching
`--check` commands fail when a mirror is stale or a value violates its platform constraints.

`macos.json` is the generated Mac App Store target version/build mirror with the `appstore`
channel. It does not claim that a candidate has passed review or been published. The App
Store owns public availability and updates; the website links to its product page without
advertising a candidate version. `app-store-localizations.json` also resolves its release
identity from `version.json` instead of duplicating those values.

`windows.json` is the generated public Windows release mirror. It separates the Product
Version, three-component Windows update version, unique release artifact version and
four-component MSIX version. A Product Version's revision-zero release keeps the legacy
`windows-v<ProductVersion>` identity so installed clients can cross the versioning migration;
later revisions retain that bridge in the public update manifest while new clients consume
the independent update fields.

Windows remains an unpackaged self-contained app distributed by NSIS. The version resolver
also calculates `{Major}.{Minor}.{Patch * 1000 + windowsRevision}.0`, validates Microsoft
Store's MSIX component limits and exposes that value as Windows `FileVersion` and
`SideyMsixVersion`. Its first three components are the Windows update comparison version.
This does not create or publish an MSIX package.
The repeatable process is documented in
[`docs/operations/release.md`](../docs/operations/release.md).

Windows releases are published only by the manually dispatched `Windows Release` workflow
on `main`. It builds a draft, verifies its downloaded Setup EXE, publishes it and calls the
reusable Pages workflow. Pages verifies only the Windows installer artifact; macOS downloads
use the Mac App Store.

macOS supports only the App Store target. Archive creation, App Store Connect upload,
submission and publication are separate actions. Developer ID DMG releases, Sparkle feeds
and Homebrew Cask updates are retired. Historical Direct GitHub Releases, assets and tags were
removed and must not be republished. Purchase records and private source history remain intact.
Backend tests and deployment run in the private backend repository.
