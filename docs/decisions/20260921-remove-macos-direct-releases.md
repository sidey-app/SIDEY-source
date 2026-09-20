# macOS Direct 공개 배포물 삭제

- Status: Accepted
- Decided: 2026-09-21
- Refines: [macOS 배포를 Mac App Store로 단일화](20260918-macos-app-store-only.md)

## 결정

지원이 종료된 macOS Direct 채널의 공개 GitHub Releases, DMG·ZIP·checksum 자산과
연결된 `v*` 태그를 삭제한다. 공개 배포 저장소의 release history에서도 해당 macOS
항목을 제공하지 않는다. macOS 설치와 업데이트는 Mac App Store만 제공한다.

Windows Releases와 update URL, App Store metadata, 사용자 계정·메시지·구매 원본,
과거 공개 revision에 이미 부여된 라이선스 및 비공개 source의 Git 이력은 보존한다.
삭제한 태그가 가리키던 commit은 private source `main` 이력에 남는다.

## 이유와 영향

종료한 배포 채널을 공식 공개 다운로드 surface에 계속 노출하면 사용자가 지원되지 않는
앱을 새로 설치하거나 현재 배포판으로 오인할 수 있다. 공개 설치 경로를 실제 지원 채널과
일치시키기 위해 Direct binary와 태그를 제거한다.

기존 Direct 설치본의 Sparkle feed가 가리키던 ZIP과 과거 DMG 재다운로드 URL은 더 이상
동작하지 않는다. 이는 지원 종료에 따른 의도된 결과다. 서명된 appcast는 비공개 source에
과거 기록으로만 남기며 다시 게시하거나 새 Direct release를 만드는 근거로 사용하지 않는다.
