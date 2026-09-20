# macOS Review Reference

Read this reference only when the review includes macOS-owned changes. Apply `macos/AGENTS.md` first.

## Risk map

- Trace Swift structured-concurrency ownership, actor isolation, detached or unstructured tasks, cancellation handlers and callbacks that may outlive their owner.
- Check NotificationCenter, workspace, display, network-path and application observers for symmetric teardown and duplicate registration across reinitialization.
- Follow AppKit window and panel lifetime, activation, focus, click-through and interaction-mode transitions. Check monitor, scale and visible-frame changes and partial window-controller construction.
- Inspect SpriteKit update loops for per-frame allocation, node or action leaks, stale coordinate spaces, nondeterministic frame selection and work that continues while hidden or locked.
- Preserve Keychain denial and caching behavior, StoreKit transaction and entitlement ownership, Supabase session boundaries and the App Store sandbox identity. Retired Direct credentials and customer records must not be silently migrated or deleted.
- Review signing, entitlements, package resolution, resource membership, login-item behavior, App Store archive inputs, and Release-only configuration when the diff touches distribution.

## Validation

Use the narrowest affected XCTest, Python asset/provenance test or structural inspection first. When broader evidence is warranted, use `./scripts/macos/tests/test_native.sh` as defined by `macos/AGENTS.md`. Signing, packaging, app launch, Keychain prompts, StoreKit, network-backed integration and release operations require matching authorization and must not be inferred from unit-test success.
