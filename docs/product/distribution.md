# 배포와 제공 채널

## 공개 상태의 source of truth

macOS의 App Store target version/build는 [`release/macos.json`](../../release/macos.json)과
[`macos/SIDEY.xcodeproj/project.pbxproj`](../../macos/SIDEY.xcodeproj/project.pbxproj)가
일치해야 한다. 이 metadata는 빌드 계약이며 App Store 심사·게시 완료를 뜻하지 않는다.
공개 설치와 업데이트 가능 여부는 App Store가 결정한다. 웹은 후보 version을 공개
version으로 표시하지 않고 App Store 제품 페이지로 연결한다.

Windows의 공개 version과 channel은 [`release/windows.json`](../../release/windows.json)이
소유한다. Release note, artifact name, website download metadata와 update manifest는
여기서 파생하거나 일치 여부를 검사한다. Windows target framework, minimum OS contract와
binary version은 [`windows/src/Sidey.App/Sidey.App.csproj`](../../windows/src/Sidey.App/Sidey.App.csproj)
및 관련 project files에 있다.

## macOS

macOS는 Mac App Store판만 개발·지원한다. 설치와 업데이트는 App Store가 담당하며
구매와 복원은 StoreKit 및 기존 서버 검증을 따른다. 직접 배포 DMG, Sparkle 업데이트와
Homebrew Cask는 지원하지 않는다. 기존 직접 배포판과 관련된 과거 release 기록, 사용자
계정·메시지·구매 원본은 보존한다. App Store 설치가 기존 직접 배포판의 Keychain 또는
sandbox storage를 자동으로 이전한다는 보장은 하지 않는다.

App Store archive 생성, submission, review와 게시 완료는 별도 단계다.

## Windows

Windows는 native app, launcher, assets, 필요한 installer helper와 .NET·Windows App SDK
runtime을 포함한 self-contained Setup EXE로 배포한다. 현재 설치 경로는 사용자 PC의
shared runtime을 prerequisite로 내려받거나 설치·등록하지 않는다. Installer는 포함된
payload를 검증하고 staging한 뒤 기존 설치를 보존할 수 있는 transaction boundary에서
교체한다. 실패하면 기존 설치를 유지하거나 복원하고 최종 상태를 확인할 수 없는 경우를
별도로 구분한다.

현재 self-contained 경로는 payload 준비, 실행 중인 process 종료, payload 적용과 Windows
등록 실패를 구분한다. Installer source에는 향후 framework-dependent 배포로 전환할 때
사용할 network·download·package·signature·shared-runtime dependency 오류 범주와 문구도
유지한다. 이 문구의 존재가 현재 설치 경로에서 shared runtime을 내려받는다는 뜻은 아니다.

설치·복구·제거 오류는 선택한 설치 언어로 무엇이 실패했는지와 기존 설치 상태를 먼저
설명하고, 빈 문단 뒤에 사용자가 취할 행동을 안내한다. 화면에는 Microsoft·Windows native
code와 구분되는 `0x51DE....` 형식의 8자리 hexadecimal 오류 코드와 진단 데이터 위치를
표시한다. Native code, 내부 예외, 실행 명령과 대상 경로는 진단 데이터에만 기록하며 진단
데이터는 메모장으로 열 수 있다. 문제가 계속되면 창의 screenshot과 진단 데이터를 첨부해
GitHub issue를 남기도록 안내한다. WindowsApps, SIDEY 설치 파일 또는 shared Microsoft
runtime의 수동 삭제를 해결책으로 안내하지 않으며, 특정 error code만 보고 별개의 runtime
제품이나 고정 patch version을 일반 해결책으로 제시하지 않는다.

Installer의 compiled helper가 payload transaction과 오류 정규화를 담당하며 사용자 PC에서
PowerShell script, `ExecutionPolicy Bypass` 또는 `taskkill.exe`를 호출하지 않는다. 새 공개
artifact, update metadata와 release note는 Windows release manifest와 같은 version을
사용한다.

## 공개 웹과 release note

공식 website는 macOS 설치를 App Store로 연결한다. Windows는 공개 release artifact를
확인하고 실제 hash에서 download metadata를 생성한다. `docs/releases/`는 사용자에게 보이는 각 platform release 결과를 기록하지만
현재 version의 source는 아니다. Store upload, public release, website deployment와
backend deployment는 서로 별도 작업이며 각각 명시적인 승인과 evidence가 필요하다.

반복 가능한 준비·검증·게시 순서는 [release operation](../operations/release.md)을 따른다.
