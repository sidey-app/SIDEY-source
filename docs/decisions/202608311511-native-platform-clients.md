# 플랫폼별 네이티브 클라이언트

Status: Accepted
Decided: 2026-08-31 15:11 KST
Evidence: [commit cc36880](https://github.com/sidey-app/SIDEY-source/commit/cc368804943a8d6833696e4fcd4985bd77a497e6)

## Context

이미 동작하는 macOS 네이티브 앱을 유지하면서 Windows의 창, DPI, 전원, 입력과 overlay
제약을 검증해야 했다. 두 platform을 하나의 Godot runtime으로 다시 묶으면 기존
macOS session·설정 호환과 platform-native 창 동작을 함께 위험하게 만들었다.

## Decision

macOS는 SwiftUI·AppKit·SpriteKit, Windows는 C#/.NET·WinUI 3·Win32로 각각 네이티브
구현한다. Platform 사이에서는 UI runtime을 공유하지 않고 Postgres, Realtime payload,
product behavior와 asset contract를 공유한다. Godot과 3D runtime은 재도입하지 않는다.

## Consequences

각 platform은 고유 lifecycle과 resource 위험을 자체적으로 다룬다. 동등성은 공통
server/asset contract와 자동 검증으로 유지해야 하며, 한 platform 구현을 다른 쪽에
그대로 복사하지 않는다.
