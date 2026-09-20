# Platform release manifest

Status: Accepted
Decided: 2026-09-04 20:56 KST
Evidence: [commit 38a8d6c](https://github.com/sidey-app/SIDEY-source/commit/38a8d6c2cdee47bd644a6402094dd3cb669032a2)

## Context

Tag, artifact name, website update metadata와 release 절차가 여러 prose 및 script 입력에서
중복되면 공개 version과 실제 artifact가 어긋날 수 있었다. Platform release도 서로
다른 시점과 검증 경로를 사용한다.

## Decision

macOS와 Windows의 공개 version은 각각의 `release/*.json` manifest가 소유한다.
Platform release pipeline은 독립적으로 운영하고 website/update metadata는 manifest와
검증된 공개 artifact에서 파생한다.

## Consequences

README와 일반 Markdown은 현재 version, build, artifact name 또는 hash를 소유하지 않는다.
Native project의 공개 version은 release manifest와 일치해야 하며, target별 build 값은
project setting이 소유한다. Public release 전에 candidate artifact를 다시 내려받아
동일성을 확인한다.
