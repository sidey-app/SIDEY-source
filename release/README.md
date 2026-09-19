# SIDEY release metadata

`macos.json` records the Mac App Store target version/build with the `appstore` channel.
It must match the native project, but does not claim that a candidate has passed review or
been published. The App Store owns public availability and updates; the website links to
its product page without advertising a candidate version.

`windows.json` is the authoritative public Windows release metadata. Tags, installer names,
release-note paths, website update manifests and workflow outputs derive from this file.
The release consistency check validates the corresponding source and public release note.
The repeatable process is documented in
[`docs/operations/release.md`](../docs/operations/release.md).

Windows releases are published only by the manually dispatched `Windows Release` workflow
on `main`. It builds a draft, verifies its downloaded Setup EXE, publishes it and calls the
reusable Pages workflow. Pages verifies only the Windows installer artifact; macOS downloads
use the Mac App Store.

macOS supports only the App Store target. Archive creation, App Store Connect upload,
submission and publication are separate actions. Developer ID DMG releases, Sparkle feeds
and Homebrew Cask updates are retired. Historical releases and purchase records remain intact.
Backend tests and deployment run in the private backend repository.
