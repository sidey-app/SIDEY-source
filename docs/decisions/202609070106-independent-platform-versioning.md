# Platform별 독립 versioning

Status: Accepted
Decided: 2026-09-07 01:06 KST
Evidence: [commit 43425d6](https://github.com/sidey-app/SIDEY/commit/43425d61e340c4185bf4c6e94775cef678448010)

## Context

한 platform의 release 때문에 다른 platform version까지 올리거나, user-visible feature를
기존 patch line에 계속 누적하면 실제 배포 이력과 호환성 의미가 흐려졌다.

## Decision

macOS와 Windows version을 독립적으로 관리하고 각 platform의 shipped diff와 호환성에
따라 version을 정한다. 기능이 같은 macOS direct/App Store target은 marketing version을
공유하되 이미 사용한 upload build를 재사용하지 않는다.

## Consequences

Website나 backend만 바뀌었다는 이유로 app version을 올리지 않는다. 기존 tag와 build에
다른 artifact를 덮어쓰지 않는다. 정확한 현재 값은 release manifest와 native project
setting이 소유한다.

macOS 배포 채널은 이후 [App Store 단일화 결정](20260918-macos-app-store-only.md)으로
변경되었다. 플랫폼별 독립 versioning과 사용한 upload build 재사용 금지는 유지한다.
