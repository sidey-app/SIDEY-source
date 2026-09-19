# 개발 후보 직접 검증

`dev-mac`은 Mac App Store판, `dev-window`는 Windows 설치 후보를 검증하는 원격 브랜치다.
플랫폼별 구현 커밋을 모으는 검증용 브랜치이며, main 통합·공개 릴리스·운영 배포를 뜻하지 않는다.

## macOS

`dev-mac`을 별도 worktree에 체크아웃하고 `macos/SIDEY.xcodeproj`의 `SIDEYAppStore`
scheme으로 빌드·실행한다. Direct scheme과 DMG/Sparkle 경로는 사용하지 않는다.
Sign in with Apple과 Keychain을 포함한 실제 로그인 검증에는 해당 App Store 앱의
개발 서명·프로비저닝이 필요하다. ad-hoc 테스트 빌드를 로그인 검증 완료로 간주하지 않는다.
자동 검사는 `./scripts/macos/tests/test_native.sh`로 수행한다.

## Windows

GitHub Actions의 `SIDEY CI (Windows build and tests)`에서 `dev-window`를 선택해 실행한다.
전체 검사·게시 앱 smoke·설치기 검사를 통과하면 해당 run의
`sidey-windows-candidate-<commit SHA>` artifact에서 Setup EXE를 받는다.
실패한 run이나 다른 SHA의 설치기를 해당 브랜치 검증 결과로 사용하지 않는다.
후보의 source version은 공개 manifest보다 앞설 수 있으며 공개 업데이트는 자동 게시하지 않는다.

새 설치와 기존 버전 업데이트, 시작 프로그램 OFF 보존, 일반/최대화 창, 다중 모니터와
작업 표시줄, 한글 조합·붙여넣기, 빠른 방 전환을 직접 확인한다.
두 기기로 500ms 미만 입력 취소·연속 입력·5초 무입력 typing 종료도 확인한다.
보안 화면·DRM·관리자 권한 창·모든 독점 전체화면 게임 위 표시를 보장하지 않는다.

## 결제 검증의 선행 조건

Windows 후보는 기존 24개 상품을 운영 Supabase와 PortOne으로 구매한다. 신규 상품은
추가하지 않는다. 후보 코드를 받는 것만으로 운영 서버·공개 checkout이 업데이트되지는 않는다.
비공개 backend의 Windows PortOne migration과 functions, 이 후보의 checkout 웹 코드가
함께 배포되어야 한다. 판매 활성화와 실제 결제·전액 환불 검증은 별도 운영 작업이다.
시크릿은 Supabase에만 보관하며 앱 빌드·소스·테스트 자료에 복사하지 않는다.
