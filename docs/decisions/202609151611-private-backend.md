# Backend 비공개 저장소 분리

Status: Accepted
Decided: 2026-09-15 16:11 KST
Evidence: [commit 67367a9](https://github.com/sidey-app/SIDEY-source/commit/67367a92f3fe8a71360ad64d81569cf70238556e)

## Context

Supabase schema·migration·RLS·Edge Functions, App Store verifier와 운영 도구가 public
client repository에 함께 있어 client contract와 server operation의 책임이 섞여 있었다.
이후 backend 개발과 배포를 조직의 비공개 경계에서 관리하기로 했다.

## Decision

Backend 구현과 운영 문서는 비공개 `sidey-app/sidey-backend` 저장소가 소유한다. Public
SIDEY 저장소에는 native Supabase client, public website, client-facing contract,
canonical commerce catalog와 asset manifest를 유지한다. Backend 상품 변경은 reviewed
public commit의 snapshot과 provenance를 사용한다.

## Consequences

Backend 작업은 해당 저장소의 current checkout, `AGENTS.md`와 CI에서 수행한다. Public
저장소의 과거 backend 사본을 수정하거나 배포 source로 사용하지 않는다. 이 분리는
운영 migration이나 deployment를 실행하지 않았고 이미 공개된 Git history를 비공개로
바꾸거나 rewrite하지 않는다.
