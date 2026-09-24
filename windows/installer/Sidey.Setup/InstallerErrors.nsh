; Category-based installer UI. Native codes are normalized by the compiled
; installer error helper;
; this file deliberately branches only on application-owned categories/statuses.

Var InstallerErrorStatus
Var InstallerErrorCategory
Var InstallerErrorSource
Var InstallerErrorNativeCode
Var InstallerErrorSideyCode
Var InstallerErrorStage
Var InstallerErrorSymbol
Var InstallerErrorDetail
Var InstallerErrorTarget
Var InstallerErrorCommand
Var InstallerErrorExitCode
Var InstallerErrorMessage
Var InstallerErrorResultPath
Var InstallerErrorLogPath
Var InstallerErrorResultLoaded

; SIDEY-owned support codes are intentionally outside the HRESULT/Win32 namespaces.
; Keep native Microsoft/Windows codes in the diagnostic data only.
!macro ResolveRecoveryErrorSymbol
  StrCpy $InstallerErrorSymbol "TRANSACTION_RECOVERY_FAILED"
  ${If} $InstallerErrorExitCode == 64
    StrCpy $InstallerErrorSymbol "RECOVERY_ARGUMENTS_INVALID"
  ${ElseIf} $InstallerErrorExitCode == 5
    StrCpy $InstallerErrorSymbol "RECOVERY_HELPER_LAUNCH_FAILED"
  ${ElseIf} $InstallerErrorExitCode == 70
    StrCpy $InstallerErrorSymbol "RECOVERY_PARENT_SECURITY_FAILED"
  ${ElseIf} $InstallerErrorExitCode == 71
    StrCpy $InstallerErrorSymbol "RECOVERY_STATE_CHECK_FAILED"
  ${ElseIf} $InstallerErrorExitCode == 72
    StrCpy $InstallerErrorSymbol "RECOVERY_ROLLBACK_FAILED"
  ${ElseIf} $InstallerErrorExitCode == 73
    StrCpy $InstallerErrorSymbol "RECOVERY_STAGING_CLEANUP_FAILED"
  ${ElseIf} $InstallerErrorExitCode == 74
    StrCpy $InstallerErrorSymbol "RECOVERY_COMMITTED_COMPLETION_FAILED"
  ${ElseIf} $InstallerErrorExitCode == 75
    StrCpy $InstallerErrorSymbol "RECOVERY_REGISTRY_CLEANUP_FAILED"
  ${ElseIf} $InstallerErrorExitCode == 76
    StrCpy $InstallerErrorSymbol "RECOVERY_ACCESS_DENIED"
  ${ElseIf} $InstallerErrorExitCode == 77
    StrCpy $InstallerErrorSymbol "RECOVERY_FILESYSTEM_IO_FAILED"
  ${ElseIf} $InstallerErrorExitCode == 78
    StrCpy $InstallerErrorSymbol "RECOVERY_INITIALIZATION_FAILED"
  ${EndIf}
!macroend

!macro ResolveSideyInstallerErrorCode
  StrCpy $InstallerErrorSideyCode "0x51DE10FF"
  ${If} $InstallerErrorSymbol == "TRANSACTION_RECOVERY_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE2001"
  ${ElseIf} $InstallerErrorSymbol == "RECOVERY_ARGUMENTS_INVALID"
    StrCpy $InstallerErrorSideyCode "0x51DE2201"
  ${ElseIf} $InstallerErrorSymbol == "RECOVERY_HELPER_LAUNCH_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE2202"
  ${ElseIf} $InstallerErrorSymbol == "RECOVERY_PARENT_SECURITY_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE2203"
  ${ElseIf} $InstallerErrorSymbol == "RECOVERY_STATE_CHECK_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE2204"
  ${ElseIf} $InstallerErrorSymbol == "RECOVERY_ROLLBACK_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE2205"
  ${ElseIf} $InstallerErrorSymbol == "RECOVERY_STAGING_CLEANUP_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE2206"
  ${ElseIf} $InstallerErrorSymbol == "RECOVERY_COMMITTED_COMPLETION_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE2207"
  ${ElseIf} $InstallerErrorSymbol == "RECOVERY_REGISTRY_CLEANUP_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE2208"
  ${ElseIf} $InstallerErrorSymbol == "RECOVERY_ACCESS_DENIED"
    StrCpy $InstallerErrorSideyCode "0x51DE2209"
  ${ElseIf} $InstallerErrorSymbol == "RECOVERY_FILESYSTEM_IO_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE220A"
  ${ElseIf} $InstallerErrorSymbol == "RECOVERY_INITIALIZATION_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE220B"
  ${ElseIf} $InstallerErrorSymbol == "EXISTING_REMOVAL_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE2002"
  ${ElseIf} $InstallerErrorSymbol == "TRANSACTION_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE2003"
  ${ElseIf} $InstallerErrorSymbol == "TRANSACTION_STATE_UNKNOWN"
    StrCpy $InstallerErrorSideyCode "0x51DE2004"
  ${ElseIf} $InstallerErrorSymbol == "LAUNCH_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE2005"
  ${ElseIf} $InstallerErrorSymbol == "CLEANUP_PENDING"
    StrCpy $InstallerErrorSideyCode "0x51DE2006"
  ${ElseIf} $InstallerErrorSymbol == "PAYLOAD_STAGE_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE2101"
  ${ElseIf} $InstallerErrorSymbol == "PROCESS_STOP_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE2102"
  ${ElseIf} $InstallerErrorSymbol == "PAYLOAD_ACTIVATION_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE2103"
  ${ElseIf} $InstallerErrorSymbol == "REGISTRATION_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE2104"
  ${ElseIf} $InstallerErrorSymbol == "UNINSTALL_PREFLIGHT_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE3001"
  ${ElseIf} $InstallerErrorSymbol == "UNINSTALL_STATE_UNKNOWN"
    StrCpy $InstallerErrorSideyCode "0x51DE3002"
  ${ElseIf} $InstallerErrorSymbol == "OPTIONAL_CLEANUP_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE3003"
  ${ElseIf} $InstallerErrorCategory == "NETWORK_ERROR"
    StrCpy $InstallerErrorSideyCode "0x51DE1001"
  ${ElseIf} $InstallerErrorCategory == "DOWNLOAD_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE1002"
  ${ElseIf} $InstallerErrorCategory == "DISK_FULL"
    StrCpy $InstallerErrorSideyCode "0x51DE1003"
  ${ElseIf} $InstallerErrorCategory == "PERMISSION_DENIED"
    StrCpy $InstallerErrorSideyCode "0x51DE1004"
  ${ElseIf} $InstallerErrorCategory == "BLOCKED_BY_POLICY"
    StrCpy $InstallerErrorSideyCode "0x51DE1005"
  ${ElseIf} $InstallerErrorCategory == "PACKAGE_CORRUPTED"
    StrCpy $InstallerErrorSideyCode "0x51DE1006"
  ${ElseIf} $InstallerErrorCategory == "SIGNATURE_ERROR"
    StrCpy $InstallerErrorSideyCode "0x51DE1007"
  ${ElseIf} $InstallerErrorCategory == "DEPENDENCY_MISSING"
    StrCpy $InstallerErrorSideyCode "0x51DE1008"
  ${ElseIf} $InstallerErrorCategory == "DEPENDENCY_CONFLICT"
    StrCpy $InstallerErrorSideyCode "0x51DE1009"
  ${ElseIf} $InstallerErrorCategory == "INCOMPATIBLE_SYSTEM"
    StrCpy $InstallerErrorSideyCode "0x51DE100A"
  ${ElseIf} $InstallerErrorCategory == "APP_IN_USE"
    StrCpy $InstallerErrorSideyCode "0x51DE100B"
  ${ElseIf} $InstallerErrorCategory == "ANOTHER_INSTALLATION_RUNNING"
    StrCpy $InstallerErrorSideyCode "0x51DE100C"
  ${ElseIf} $InstallerErrorCategory == "ALREADY_INSTALLED"
    StrCpy $InstallerErrorSideyCode "0x51DE100D"
  ${ElseIf} $InstallerErrorCategory == "REBOOT_REQUIRED"
    StrCpy $InstallerErrorSideyCode "0x51DE100E"
  ${ElseIf} $InstallerErrorCategory == "USER_CANCELLED"
    StrCpy $InstallerErrorSideyCode "0x51DE100F"
  ${ElseIf} $InstallerErrorCategory == "PACKAGE_REGISTRATION_FAILED"
    StrCpy $InstallerErrorSideyCode "0x51DE1010"
  ${ElseIf} $InstallerErrorCategory == "PACKAGE_REPOSITORY_CORRUPTED"
    StrCpy $InstallerErrorSideyCode "0x51DE1011"
  ${ElseIf} $InstallerErrorStage == "UNINSTALL"
    StrCpy $InstallerErrorSideyCode "0x51DE30FF"
  ${EndIf}
!macroend

LangString InstallerErrorNetwork ${LANG_ENGLISH} "SIDEY cannot be installed because the connection to Microsoft's download service was interrupted.$\r$\n$\r$\nCheck your internet connection and any proxy or VPN, then run Setup again."
LangString InstallerErrorDownload ${LANG_ENGLISH} "SIDEY cannot be installed because a required Microsoft component could not be downloaded.$\r$\n$\r$\nCheck your connection, then run Setup again so it can download the component."
LangString InstallerErrorDiskFull ${LANG_ENGLISH} "SIDEY cannot be installed because there is not enough storage space.$\r$\n$\r$\nFree space on both the Windows system drive and the selected SIDEY installation drive, then run Setup again."
LangString InstallerErrorPermission ${LANG_ENGLISH} "SIDEY cannot be installed because Windows blocked a required change.$\r$\n$\r$\nRestart Windows and run Setup again. If this PC is managed, contact your system administrator."
LangString InstallerErrorPolicy ${LANG_ENGLISH} "SIDEY cannot be installed because Windows policy does not allow this component.$\r$\n$\r$\nIf this PC is managed by a company or school, contact your system administrator. Do not bypass the policy."
LangString InstallerErrorPackage ${LANG_ENGLISH} "SIDEY cannot be installed because a required Microsoft component package could not be opened or is damaged.$\r$\n$\r$\nRun Setup again so it downloads a fresh copy from Microsoft. If the problem continues, install Windows updates and retry."
LangString InstallerErrorSignature ${LANG_ENGLISH} "SIDEY cannot be installed because Windows could not verify a required Microsoft component.$\r$\n$\r$\nCheck the Windows date and time, install Windows updates, then run Setup again.$\r$\n$\r$\nDo not disable signature verification."
LangString InstallerErrorDependency ${LANG_ENGLISH} "SIDEY cannot be installed because a required Microsoft runtime is unavailable.$\r$\n$\r$\nInstall Windows updates, restart Windows, and run Setup again.$\r$\n$\r$\nDo not manually remove shared Microsoft runtimes."
LangString InstallerErrorDependencyConflict ${LANG_ENGLISH} "SIDEY cannot be installed because a required Microsoft runtime is missing or conflicts with an installed package.$\r$\n$\r$\nInstall Windows updates, restart Windows, and run Setup again.$\r$\n$\r$\nDo not manually delete shared Microsoft runtimes."
LangString InstallerErrorIncompatible ${LANG_ENGLISH} "SIDEY cannot be installed because a required package is not compatible with this Windows version or architecture.$\r$\n$\r$\nCheck the SIDEY system requirements and install Windows updates.$\r$\n$\r$\nDo not install a package for a different architecture."
LangString InstallerErrorAppInUse ${LANG_ENGLISH} "SIDEY cannot be installed because a program or component that must be updated is in use.$\r$\n$\r$\nClose SIDEY and related installers, then run Setup again. If it remains in use, restart Windows and retry."
LangString InstallerErrorAnotherInstall ${LANG_ENGLISH} "SIDEY cannot be installed because another installation is running.$\r$\n$\r$\nFinish or cancel it, then run Setup again. If no installer is visible, restart Windows and retry."
LangString InstallerErrorAlreadyInstalled ${LANG_ENGLISH} "SIDEY cannot be installed because Windows found an existing version of a required component.$\r$\n$\r$\nRestart Windows, then run the latest SIDEY Setup again.$\r$\n$\r$\nDo not manually remove shared Microsoft runtimes."
LangString InstallerErrorRestart ${LANG_ENGLISH} "Windows must be restarted. The required component was installed, but this installation cannot continue yet.$\r$\n$\r$\nRestart Windows, then run Setup again."
LangString InstallerErrorCancelled ${LANG_ENGLISH} "Installation was cancelled. SIDEY application files were not replaced, but Microsoft components installed before cancellation may remain for other apps.$\r$\n$\r$\nRun Setup again when you are ready."
LangString InstallerErrorRegistration ${LANG_ENGLISH} "SIDEY cannot be installed. The required component was installed, but Windows could not make it available to the current desktop user.$\r$\n$\r$\nInstall Windows updates, restart Windows, and run Setup again.$\r$\n$\r$\nDo not edit Windows package folders manually."
LangString InstallerErrorRepository ${LANG_ENGLISH} "SIDEY cannot be installed because Windows reported a problem with its app package database.$\r$\n$\r$\nInstall Windows updates and restart Windows. If the problem continues, contact your system administrator.$\r$\n$\r$\nDo not edit WindowsApps or package data manually."
LangString InstallerErrorUnknown ${LANG_ENGLISH} "A problem occurred during installation. SIDEY could not be installed.$\r$\n$\r$\nRestart Windows, then run the latest SIDEY Setup again.$\r$\n$\r$\nIf the problem continues, open a GitHub issue and include a screenshot of this window and the diagnostic data.$\r$\nDo not manually remove shared runtimes or Windows package files."

LangString InstallerErrorNetwork ${LANG_KOREAN} "프로그램을 설치할 수 없습니다. Microsoft 다운로드 서비스와의 연결이 중단되었습니다.$\r$\n$\r$\n인터넷 연결과 프록시 또는 VPN을 확인한 뒤 설치 프로그램을 다시 실행하세요."
LangString InstallerErrorDownload ${LANG_KOREAN} "프로그램을 설치할 수 없습니다. 필수 Microsoft 구성 요소를 다운로드하지 못했습니다.$\r$\n$\r$\n인터넷 연결을 확인한 뒤 설치 프로그램을 다시 실행하여 구성 요소를 내려받아 주세요."
LangString InstallerErrorDiskFull ${LANG_KOREAN} "프로그램을 설치할 수 없습니다. 저장 공간이 부족합니다.$\r$\n$\r$\nWindows 시스템 드라이브와 선택한 설치 드라이브 모두에서 여유 공간을 확보한 뒤 설치 프로그램을 다시 실행하세요."
LangString InstallerErrorPermission ${LANG_KOREAN} "프로그램을 설치할 수 없습니다. Windows에서 필요한 변경을 차단했습니다.$\r$\n$\r$\nWindows를 다시 시작한 뒤 설치 프로그램을 다시 실행하세요. 관리되는 PC라면 시스템 관리자에게 문의하세요."
LangString InstallerErrorPolicy ${LANG_KOREAN} "프로그램을 설치할 수 없습니다. Windows 정책에서 이 구성 요소의 설치를 허용하지 않습니다.$\r$\n$\r$\n회사나 학교에서 관리하는 PC라면 시스템 관리자에게 문의하세요.$\r$\n$\r$\n정책을 우회하지 마세요."
LangString InstallerErrorPackage ${LANG_KOREAN} "프로그램을 설치할 수 없습니다. 필수 Microsoft 구성 요소 패키지를 열 수 없거나 패키지가 손상되었습니다.$\r$\n$\r$\n설치 프로그램을 다시 실행하여 Microsoft에서 새 사본을 다운로드하세요. 문제가 계속되면 Windows 업데이트를 설치한 뒤 다시 시도하세요."
LangString InstallerErrorSignature ${LANG_KOREAN} "프로그램을 설치할 수 없습니다. Windows에서 필수 Microsoft 구성 요소를 확인하지 못했습니다.$\r$\n$\r$\nWindows 날짜와 시간을 확인하고 Windows 업데이트를 설치한 뒤 설치 프로그램을 다시 실행하세요.$\r$\n$\r$\n서명 확인을 끄지 마세요."
LangString InstallerErrorDependency ${LANG_KOREAN} "프로그램을 설치할 수 없습니다. 필수 Microsoft 런타임을 사용할 수 없습니다.$\r$\n$\r$\nWindows 업데이트를 설치하고 Windows를 다시 시작한 뒤 설치 프로그램을 다시 실행하세요.$\r$\n$\r$\nMicrosoft 공유 런타임을 직접 제거하지 마세요."
LangString InstallerErrorDependencyConflict ${LANG_KOREAN} "프로그램을 설치할 수 없습니다. 필수 Microsoft 런타임이 없거나 설치된 패키지와 충돌합니다.$\r$\n$\r$\nWindows 업데이트를 설치하고 Windows를 다시 시작한 뒤 설치 프로그램을 다시 실행하세요.$\r$\n$\r$\nMicrosoft 공유 런타임을 직접 삭제하지 마세요."
LangString InstallerErrorIncompatible ${LANG_KOREAN} "프로그램을 설치할 수 없습니다. 필수 패키지가 현재 Windows 버전 또는 시스템 종류와 호환되지 않습니다.$\r$\n$\r$\n시스템 요구 사항을 확인하고 Windows 업데이트를 설치하세요.$\r$\n$\r$\n다른 시스템 종류용 패키지를 설치하지 마세요."
LangString InstallerErrorAppInUse ${LANG_KOREAN} "프로그램을 설치할 수 없습니다. 업데이트해야 할 프로그램이나 구성 요소를 사용 중입니다.$\r$\n$\r$\n프로그램과 관련 설치 프로그램을 종료한 뒤 다시 실행하세요. 계속 사용 중으로 표시되면 Windows를 다시 시작한 뒤 시도하세요."
LangString InstallerErrorAnotherInstall ${LANG_KOREAN} "프로그램을 설치할 수 없습니다. 다른 설치가 진행 중입니다.$\r$\n$\r$\n해당 설치를 완료하거나 취소한 뒤 설치 프로그램을 다시 실행하세요. 실행 중인 설치가 보이지 않으면 Windows를 다시 시작한 뒤 시도하세요."
LangString InstallerErrorAlreadyInstalled ${LANG_KOREAN} "프로그램을 설치할 수 없습니다. 필수 구성 요소의 기존 버전이 발견되었습니다.$\r$\n$\r$\nWindows를 다시 시작한 뒤 최신 설치 프로그램을 다시 실행하세요.$\r$\n$\r$\nMicrosoft 공유 런타임을 직접 제거하지 마세요."
LangString InstallerErrorRestart ${LANG_KOREAN} "Windows를 다시 시작해야 합니다. 필수 구성 요소는 설치되었지만 이번 설치를 아직 계속할 수 없습니다.$\r$\n$\r$\nWindows를 다시 시작한 뒤 설치 프로그램을 다시 실행하세요."
LangString InstallerErrorCancelled ${LANG_KOREAN} "설치가 취소되었습니다. SIDEY 앱 파일은 교체하지 않았지만 취소 전에 설치된 Microsoft 구성 요소는 다른 앱을 위해 남아 있을 수 있습니다.$\r$\n$\r$\n준비가 되면 설치 프로그램을 다시 실행하세요."
LangString InstallerErrorRegistration ${LANG_KOREAN} "프로그램을 설치할 수 없습니다. 필수 구성 요소는 설치되었지만 Windows에서 현재 데스크톱 사용자가 사용할 수 있도록 등록하지 못했습니다.$\r$\n$\r$\nWindows 업데이트를 설치하고 Windows를 다시 시작한 뒤 설치 프로그램을 다시 실행하세요.$\r$\n$\r$\nWindows 패키지 폴더를 직접 수정하지 마세요."
LangString InstallerErrorRepository ${LANG_KOREAN} "프로그램을 설치할 수 없습니다. Windows에서 앱 패키지 데이터베이스 문제를 보고했습니다.$\r$\n$\r$\nWindows 업데이트를 설치하고 Windows를 다시 시작하세요. 문제가 계속되면 시스템 관리자에게 문의하세요.$\r$\n$\r$\nWindowsApps 또는 패키지 데이터를 직접 수정하지 마세요."
LangString InstallerErrorUnknown ${LANG_KOREAN} "설치 중 문제가 발생했습니다. 프로그램 설치를 완료하지 못했습니다.$\r$\n$\r$\nWindows를 다시 시작한 뒤 최신 설치 프로그램을 다시 실행하세요.$\r$\n$\r$\n문제가 계속되면 이 창의 스크린샷과 진단 데이터를 첨부하여 GitHub 이슈를 남겨주세요.$\r$\n공유 런타임이나 Windows 패키지 파일을 직접 제거하지 마세요."

; The five additional installer languages retain the same category/action split.
LangString InstallerErrorNetwork ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\nMicrosoft のダウンロードサービスとの接続が切断されました。$\r$\n$\r$\nインターネット接続、プロキシ、VPN を確認してから、セットアップを再実行してください。"
LangString InstallerErrorDownload ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\n必要な Microsoft コンポーネントをダウンロードできませんでした。$\r$\n$\r$\n接続を確認し、セットアップを再実行してコンポーネントをダウンロードしてください。"
LangString InstallerErrorDiskFull ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\n空き容量が不足しています。$\r$\n$\r$\nWindows のシステムドライブと選択した SIDEY のインストール先ドライブの両方で空き容量を増やし、セットアップを再実行してください。"
LangString InstallerErrorPermission ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\nWindows が必要な変更をブロックしました。$\r$\n$\r$\nWindows を再起動してセットアップを再実行してください。管理対象の PC の場合は、システム管理者にお問い合わせください。"
LangString InstallerErrorPolicy ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\nWindows ポリシーにより、このコンポーネントをインストールできません。$\r$\n$\r$\n会社や学校が管理する PC の場合は、ポリシーを回避せず、システム管理者にお問い合わせください。"
LangString InstallerErrorPackage ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\n必要な Microsoft コンポーネントパッケージを開けないか、破損しています。$\r$\n$\r$\nセットアップを再実行して Microsoft から新しいコピーをダウンロードしてください。問題が続く場合は、Windows Update を適用して再試行してください。"
LangString InstallerErrorSignature ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\n必要な Microsoft コンポーネントを Windows で検証できませんでした。$\r$\n$\r$\nWindows の日付と時刻を確認し、Windows Update を適用してからセットアップを再実行してください。署名の検証を無効にしないでください。"
LangString InstallerErrorDependency ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\n必要な Microsoft ランタイムを利用できません。$\r$\n$\r$\nWindows Update を適用し、Windows を再起動してからセットアップを再実行してください。共有 Microsoft ランタイムを手動で削除しないでください。"
LangString InstallerErrorDependencyConflict ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\n必要な Microsoft ランタイムがないか、インストール済みパッケージと競合しています。$\r$\n$\r$\nWindows Update を適用し、Windows を再起動してからセットアップを再実行してください。共有ランタイムを手動で削除しないでください。"
LangString InstallerErrorIncompatible ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\n必要なパッケージは、この Windows バージョンまたはアーキテクチャに対応していません。$\r$\n$\r$\nSIDEY のシステム要件を確認して Windows Update を適用し、別のアーキテクチャ用パッケージをインストールしないでください。"
LangString InstallerErrorAppInUse ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\n更新が必要なプログラムまたはコンポーネントが使用中です。$\r$\n$\r$\nSIDEY と関連するインストーラーを終了してセットアップを再実行してください。使用中のままの場合は、Windows を再起動して再試行してください。"
LangString InstallerErrorAnotherInstall ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\n別のインストールが実行中です。$\r$\n$\r$\nそのインストールを完了またはキャンセルしてから、セットアップを再実行してください。インストーラーが見つからない場合は、Windows を再起動して再試行してください。"
LangString InstallerErrorAlreadyInstalled ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\n必要なコンポーネントの既存バージョンが見つかりました。$\r$\n$\r$\nWindows を再起動し、最新の SIDEY セットアップを再実行してください。共有 Microsoft ランタイムを手動で削除しないでください。"
LangString InstallerErrorRestart ${LANG_JAPANESE} "Windows の再起動が必要です。$\r$\n$\r$\n必要なコンポーネントはインストールされましたが、Windows を再起動するまで今回のインストールを続行できません。$\r$\n$\r$\nWindows を再起動してからセットアップを再実行してください。"
LangString InstallerErrorCancelled ${LANG_JAPANESE} "インストールはキャンセルされました。$\r$\n$\r$\nSIDEY のアプリファイルは置き換えられていません。キャンセル前にインストールされた Microsoft コンポーネントは残る場合があり、他のアプリでも共有されます。$\r$\n$\r$\n準備ができたらセットアップを再実行してください。"
LangString InstallerErrorRegistration ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\n必要なコンポーネントはインストールされましたが、現在のデスクトップユーザーが利用できるよう Windows で登録できませんでした。$\r$\n$\r$\nWindows Update を適用し、Windows を再起動してからセットアップを再実行してください。Windows のパッケージフォルダーを手動で変更しないでください。"
LangString InstallerErrorRepository ${LANG_JAPANESE} "SIDEY をインストールできません。$\r$\n$\r$\nWindows からアプリパッケージデータベースの問題が報告されました。$\r$\n$\r$\nWindows Update を適用して Windows を再起動してください。問題が続く場合は、システム管理者またはサポートに連絡し、WindowsApps やパッケージデータを手動で変更しないでください。"
LangString InstallerErrorUnknown ${LANG_JAPANESE} "インストール中に問題が発生し、プログラムをインストールできませんでした。$\r$\n$\r$\nWindows を再起動し、最新のセットアップをもう一度実行してください。$\r$\n$\r$\n問題が続く場合は、この画面のスクリーンショットと診断データを添えて GitHub Issue を作成してください。$\r$\n共有ランタイムや Windows パッケージファイルを手動で削除しないでください。"

LangString InstallerErrorNetwork ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n与 Microsoft 下载服务的连接已中断。$\r$\n$\r$\n请检查网络连接、代理或 VPN，然后重新运行安装程序。"
LangString InstallerErrorDownload ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n无法下载所需的 Microsoft 组件。$\r$\n$\r$\n请检查网络连接，然后重新运行安装程序以下载该组件。"
LangString InstallerErrorDiskFull ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n存储空间不足。$\r$\n$\r$\n请在 Windows 系统驱动器和所选 SIDEY 安装驱动器上都释放空间，然后重新运行安装程序。"
LangString InstallerErrorPermission ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\nWindows 阻止了所需更改。$\r$\n$\r$\n请重启 Windows 后重新运行安装程序。如果此电脑由组织管理，请联系系统管理员。"
LangString InstallerErrorPolicy ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\nWindows 策略不允许安装此组件。$\r$\n$\r$\n如果此电脑由公司或学校管理，请联系系统管理员，不要绕过该策略。"
LangString InstallerErrorPackage ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n无法打开所需的 Microsoft 组件包，或该包已损坏。$\r$\n$\r$\n请重新运行安装程序，以便从 Microsoft 下载新副本。如果问题仍然存在，请安装 Windows 更新后重试。"
LangString InstallerErrorSignature ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\nWindows 无法验证所需的 Microsoft 组件。$\r$\n$\r$\n请检查 Windows 日期和时间，安装 Windows 更新，然后重新运行安装程序。请勿禁用签名验证。"
LangString InstallerErrorDependency ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n所需的 Microsoft 运行时不可用。$\r$\n$\r$\n请安装 Windows 更新，重启 Windows，然后重新运行安装程序。请勿手动删除共享的 Microsoft 运行时。"
LangString InstallerErrorDependencyConflict ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n缺少所需的 Microsoft 运行时，或该运行时与已安装的软件包冲突。$\r$\n$\r$\n请安装 Windows 更新，重启 Windows，然后重新运行安装程序。请勿手动删除共享运行时。"
LangString InstallerErrorIncompatible ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n所需软件包与此 Windows 版本或系统架构不兼容。$\r$\n$\r$\n请检查 SIDEY 系统要求并安装 Windows 更新；不要安装用于其他架构的软件包。"
LangString InstallerErrorAppInUse ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n需要更新的程序或组件正在使用中。$\r$\n$\r$\n请关闭 SIDEY 和相关安装程序，然后重新运行安装程序。如果仍显示正在使用，请重启 Windows 后重试。"
LangString InstallerErrorAnotherInstall ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n另一个安装正在运行。$\r$\n$\r$\n请完成或取消该安装，然后重新运行 SIDEY 安装程序。如果没有可见的安装程序，请重启 Windows 后重试。"
LangString InstallerErrorAlreadyInstalled ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\nWindows 发现所需组件的现有版本。$\r$\n$\r$\n请重启 Windows，然后再次运行最新的 SIDEY 安装程序。请勿手动删除共享的 Microsoft 运行时。"
LangString InstallerErrorRestart ${LANG_SIMPCHINESE} "必须重启 Windows。$\r$\n$\r$\n所需组件已安装，但重启 Windows 前无法继续此次安装。$\r$\n$\r$\n请重启 Windows，然后重新运行安装程序。"
LangString InstallerErrorCancelled ${LANG_SIMPCHINESE} "安装已取消。$\r$\n$\r$\nSIDEY 应用文件未被替换。取消前安装的 Microsoft 组件可能会保留，并可能由其他应用共享。$\r$\n$\r$\n准备好后请重新运行安装程序。"
LangString InstallerErrorRegistration ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\n所需组件已安装，但 Windows 无法使当前桌面用户使用该组件。$\r$\n$\r$\n请安装 Windows 更新，重启 Windows，然后重新运行安装程序。请勿手动修改 Windows 软件包文件夹。"
LangString InstallerErrorRepository ${LANG_SIMPCHINESE} "无法安装 SIDEY。$\r$\n$\r$\nWindows 报告应用包数据库存在问题。$\r$\n$\r$\n请安装 Windows 更新并重启 Windows。如果问题仍然存在，请联系系统管理员；请勿手动修改 WindowsApps 或软件包数据。"
LangString InstallerErrorUnknown ${LANG_SIMPCHINESE} "安装过程中出现问题，无法安装程序。$\r$\n$\r$\n请重启 Windows 并再次运行最新的安装程序。$\r$\n$\r$\n如果问题仍然存在，请附上此窗口的截图和诊断数据提交 GitHub Issue。$\r$\n请勿手动删除共享运行时或 Windows 软件包文件。"

LangString InstallerErrorNetwork ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n與 Microsoft 下載服務的連線已中斷。$\r$\n$\r$\n請檢查網路連線、Proxy 或 VPN，然後重新執行安裝程式。"
LangString InstallerErrorDownload ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n無法下載必要的 Microsoft 元件。$\r$\n$\r$\n請檢查網路連線，然後重新執行安裝程式以下載該元件。"
LangString InstallerErrorDiskFull ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n儲存空間不足。$\r$\n$\r$\n請在 Windows 系統磁碟機和所選 SIDEY 安裝磁碟機上都釋放空間，然後重新執行安裝程式。"
LangString InstallerErrorPermission ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\nWindows 已阻擋必要變更。$\r$\n$\r$\n請重新啟動 Windows 後重新執行安裝程式。如果此電腦由組織管理，請聯絡系統管理員。"
LangString InstallerErrorPolicy ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\nWindows 原則不允許安裝此元件。$\r$\n$\r$\n如果此電腦由公司或學校管理，請聯絡系統管理員，不要規避該原則。"
LangString InstallerErrorPackage ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n無法開啟必要的 Microsoft 元件套件，或套件已損毀。$\r$\n$\r$\n請重新執行安裝程式，讓它從 Microsoft 下載新的副本。若問題持續，請安裝 Windows 更新後再試一次。"
LangString InstallerErrorSignature ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\nWindows 無法驗證必要的 Microsoft 元件。$\r$\n$\r$\n請檢查 Windows 日期與時間、安裝 Windows 更新，然後重新執行安裝程式。請勿停用簽章驗證。"
LangString InstallerErrorDependency ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n必要的 Microsoft 執行階段無法使用。$\r$\n$\r$\n請安裝 Windows 更新、重新啟動 Windows，然後重新執行安裝程式。請勿手動移除共用的 Microsoft 執行階段。"
LangString InstallerErrorDependencyConflict ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n缺少必要的 Microsoft 執行階段，或該執行階段與已安裝的套件衝突。$\r$\n$\r$\n請安裝 Windows 更新、重新啟動 Windows，然後重新執行安裝程式。請勿手動刪除共用執行階段。"
LangString InstallerErrorIncompatible ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n必要套件與此 Windows 版本或系統架構不相容。$\r$\n$\r$\n請查看 SIDEY 系統需求並安裝 Windows 更新；不要安裝其他架構的套件。"
LangString InstallerErrorAppInUse ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n需要更新的程式或元件正在使用中。$\r$\n$\r$\n請關閉 SIDEY 與相關安裝程式，然後重新執行安裝程式。若仍顯示使用中，請重新啟動 Windows 後再試一次。"
LangString InstallerErrorAnotherInstall ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n另一個安裝正在執行。$\r$\n$\r$\n請完成或取消該安裝，然後重新執行 SIDEY 安裝程式。若沒有看到安裝程式，請重新啟動 Windows 後再試一次。"
LangString InstallerErrorAlreadyInstalled ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\nWindows 找到必要元件的現有版本。$\r$\n$\r$\n請重新啟動 Windows，然後再次執行最新的 SIDEY 安裝程式。請勿手動移除共用的 Microsoft 執行階段。"
LangString InstallerErrorRestart ${LANG_TRADCHINESE} "必須重新啟動 Windows。$\r$\n$\r$\n必要元件已安裝，但重新啟動 Windows 前無法繼續此次安裝。$\r$\n$\r$\n請重新啟動 Windows，然後重新執行安裝程式。"
LangString InstallerErrorCancelled ${LANG_TRADCHINESE} "安裝已取消。$\r$\n$\r$\nSIDEY 應用程式檔案未被取代。取消前安裝的 Microsoft 元件可能會保留，並可能由其他應用程式共用。$\r$\n$\r$\n準備好後請重新執行安裝程式。"
LangString InstallerErrorRegistration ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\n必要元件已安裝，但 Windows 無法讓目前的桌面使用者使用該元件。$\r$\n$\r$\n請安裝 Windows 更新、重新啟動 Windows，然後重新執行安裝程式。請勿手動修改 Windows 套件資料夾。"
LangString InstallerErrorRepository ${LANG_TRADCHINESE} "無法安裝 SIDEY。$\r$\n$\r$\nWindows 回報應用程式套件資料庫有問題。$\r$\n$\r$\n請安裝 Windows 更新並重新啟動 Windows。若問題持續，請聯絡系統管理員；請勿手動修改 WindowsApps 或套件資料。"
LangString InstallerErrorUnknown ${LANG_TRADCHINESE} "安裝期間發生問題，無法安裝程式。$\r$\n$\r$\n請重新啟動 Windows，然後再次執行最新的安裝程式。$\r$\n$\r$\n如果問題持續，請附上此視窗的螢幕擷取畫面和診斷資料提交 GitHub Issue。$\r$\n請勿手動刪除共用執行階段或 Windows 套件檔案。"

LangString InstallerErrorNetwork ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nСоединение со службой загрузки Microsoft прервано.$\r$\n$\r$\n Проверьте подключение к Интернету, прокси-сервер или VPN и снова запустите установщик."
LangString InstallerErrorDownload ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nНе удалось загрузить необходимый компонент Microsoft.$\r$\n$\r$\n Проверьте подключение и снова запустите установщик для загрузки компонента."
LangString InstallerErrorDiskFull ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nНедостаточно места.$\r$\n$\r$\n Освободите место как на системном диске Windows, так и на выбранном диске установки SIDEY, затем снова запустите установщик."
LangString InstallerErrorPermission ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nWindows заблокировала необходимое изменение.$\r$\n$\r$\n Перезапустите Windows и снова запустите установщик. Если компьютер управляется организацией, обратитесь к системному администратору."
LangString InstallerErrorPolicy ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nПолитика Windows запрещает установку этого компонента.$\r$\n$\r$\n Если компьютер управляется организацией, обратитесь к системному администратору и не пытайтесь обходить политику."
LangString InstallerErrorPackage ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nНе удалось открыть пакет необходимого компонента Microsoft, либо он повреждён.$\r$\n$\r$\n Снова запустите установщик, чтобы загрузить новую копию с сайта Microsoft. Если проблема сохранится, установите обновления Windows и повторите попытку."
LangString InstallerErrorSignature ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nWindows не удалось проверить необходимый компонент Microsoft.$\r$\n$\r$\n Проверьте дату и время Windows, установите обновления Windows и снова запустите установщик. Не отключайте проверку подписи."
LangString InstallerErrorDependency ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nНеобходимая среда выполнения Microsoft недоступна.$\r$\n$\r$\n Установите обновления Windows, перезапустите Windows и снова запустите установщик. Не удаляйте общие среды выполнения Microsoft вручную."
LangString InstallerErrorDependencyConflict ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nНеобходимая среда выполнения Microsoft отсутствует или конфликтует с установленным пакетом.$\r$\n$\r$\n Установите обновления Windows, перезапустите Windows и снова запустите установщик. Не удаляйте общие среды выполнения вручную."
LangString InstallerErrorIncompatible ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nНеобходимый пакет несовместим с этой версией или архитектурой Windows.$\r$\n$\r$\n Проверьте системные требования SIDEY и установите обновления Windows; не устанавливайте пакет для другой архитектуры."
LangString InstallerErrorAppInUse ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nОбновляемая программа или компонент используется.$\r$\n$\r$\n Закройте SIDEY и связанные установщики, затем снова запустите установщик. Если компонент по-прежнему занят, перезапустите Windows и повторите попытку."
LangString InstallerErrorAnotherInstall ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nВыполняется другая установка.$\r$\n$\r$\n Завершите или отмените её, затем снова запустите установщик SIDEY. Если окно установщика не видно, перезапустите Windows и повторите попытку."
LangString InstallerErrorAlreadyInstalled ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nWindows обнаружила установленную версию необходимого компонента.$\r$\n$\r$\n Перезапустите Windows и снова запустите последнюю версию установщика SIDEY. Не удаляйте общие среды выполнения Microsoft вручную."
LangString InstallerErrorRestart ${LANG_RUSSIAN} "Необходимо перезапустить Windows.$\r$\n$\r$\nНеобходимый компонент установлен, но эту установку нельзя продолжить до перезапуска Windows.$\r$\n$\r$\n Перезапустите Windows и снова запустите установщик."
LangString InstallerErrorCancelled ${LANG_RUSSIAN} "Установка отменена.$\r$\n$\r$\nФайлы приложения SIDEY не заменены. Компоненты Microsoft, установленные до отмены, могут остаться и использоваться другими приложениями.$\r$\n$\r$\n Запустите установщик снова, когда будете готовы."
LangString InstallerErrorRegistration ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nНеобходимый компонент установлен, но Windows не смогла сделать его доступным текущему пользователю рабочего стола.$\r$\n$\r$\n Установите обновления Windows, перезапустите Windows и снова запустите установщик. Не изменяйте папки пакетов Windows вручную."
LangString InstallerErrorRepository ${LANG_RUSSIAN} "Не удалось установить SIDEY.$\r$\n$\r$\nWindows сообщила о проблеме с базой данных пакетов приложений.$\r$\n$\r$\n Установите обновления Windows и перезапустите Windows. Если проблема сохранится, обратитесь к системному администратору или в поддержку; не изменяйте WindowsApps или данные пакетов вручную."
LangString InstallerErrorUnknown ${LANG_RUSSIAN} "Во время установки возникла проблема. Программу установить не удалось.$\r$\n$\r$\nПерезапустите Windows и снова запустите последнюю версию установщика.$\r$\n$\r$\nЕсли проблема сохранится, создайте Issue на GitHub и приложите снимок этого окна и диагностические данные.$\r$\nНе удаляйте общие среды выполнения или файлы пакетов Windows вручную."

LangString InstallerErrorNetwork ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nЗ’єднання зі службою завантаження Microsoft перервано.$\r$\n$\r$\n Перевірте підключення до Інтернету, проксі-сервер або VPN і знову запустіть інсталятор."
LangString InstallerErrorDownload ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nНе вдалося завантажити потрібний компонент Microsoft.$\r$\n$\r$\n Перевірте підключення та знову запустіть інсталятор, щоб завантажити компонент."
LangString InstallerErrorDiskFull ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nНедостатньо місця.$\r$\n$\r$\n Звільніть місце як на системному диску Windows, так і на вибраному диску встановлення SIDEY, а потім знову запустіть інсталятор."
LangString InstallerErrorPermission ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nWindows заблокувала потрібну зміну.$\r$\n$\r$\n Перезапустіть Windows і знову запустіть інсталятор. Якщо комп’ютером керує організація, зверніться до системного адміністратора."
LangString InstallerErrorPolicy ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nПолітика Windows не дозволяє встановити цей компонент.$\r$\n$\r$\n Якщо комп’ютером керує організація, зверніться до системного адміністратора й не намагайтеся обійти політику."
LangString InstallerErrorPackage ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nНе вдалося відкрити пакет потрібного компонента Microsoft, або його пошкоджено.$\r$\n$\r$\n Знову запустіть інсталятор, щоб завантажити нову копію від Microsoft. Якщо проблема не зникне, установіть оновлення Windows і повторіть спробу."
LangString InstallerErrorSignature ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nWindows не вдалося перевірити потрібний компонент Microsoft.$\r$\n$\r$\n Перевірте дату й час Windows, установіть оновлення Windows і знову запустіть інсталятор. Не вимикайте перевірку підпису."
LangString InstallerErrorDependency ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nПотрібне середовище виконання Microsoft недоступне.$\r$\n$\r$\n Установіть оновлення Windows, перезапустіть Windows і знову запустіть інсталятор. Не видаляйте спільні середовища виконання Microsoft вручну."
LangString InstallerErrorDependencyConflict ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nПотрібне середовище виконання Microsoft відсутнє або конфліктує з установленим пакетом.$\r$\n$\r$\n Установіть оновлення Windows, перезапустіть Windows і знову запустіть інсталятор. Не видаляйте спільні середовища виконання вручну."
LangString InstallerErrorIncompatible ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nПотрібний пакет несумісний із цією версією або архітектурою Windows.$\r$\n$\r$\n Перевірте системні вимоги SIDEY та встановіть оновлення Windows; не встановлюйте пакет для іншої архітектури."
LangString InstallerErrorAppInUse ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nПрограма або компонент, який треба оновити, використовується.$\r$\n$\r$\n Закрийте SIDEY і пов’язані інсталятори, а потім знову запустіть інсталятор. Якщо компонент усе ще зайнятий, перезапустіть Windows і повторіть спробу."
LangString InstallerErrorAnotherInstall ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nВиконується інше встановлення.$\r$\n$\r$\n Завершіть або скасуйте його, а потім знову запустіть інсталятор SIDEY. Якщо вікно інсталятора не видно, перезапустіть Windows і повторіть спробу."
LangString InstallerErrorAlreadyInstalled ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nWindows виявила наявну версію потрібного компонента.$\r$\n$\r$\n Перезапустіть Windows і знову запустіть останню версію інсталятора SIDEY. Не видаляйте спільні середовища виконання Microsoft вручну."
LangString InstallerErrorRestart ${LANG_UKRAINIAN} "Потрібно перезапустити Windows.$\r$\n$\r$\nПотрібний компонент установлено, але це встановлення не можна продовжити до перезапуску Windows.$\r$\n$\r$\n Перезапустіть Windows і знову запустіть інсталятор."
LangString InstallerErrorCancelled ${LANG_UKRAINIAN} "Встановлення скасовано.$\r$\n$\r$\nФайли програми SIDEY не замінено. Компоненти Microsoft, установлені до скасування, можуть залишитися й використовуватися іншими програмами.$\r$\n$\r$\n Запустіть інсталятор знову, коли будете готові."
LangString InstallerErrorRegistration ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nПотрібний компонент установлено, але Windows не змогла зробити його доступним поточному користувачеві робочого стола.$\r$\n$\r$\n Установіть оновлення Windows, перезапустіть Windows і знову запустіть інсталятор. Не змінюйте папки пакетів Windows вручну."
LangString InstallerErrorRepository ${LANG_UKRAINIAN} "Не вдалося встановити SIDEY.$\r$\n$\r$\nWindows повідомила про проблему з базою даних пакетів програм.$\r$\n$\r$\n Установіть оновлення Windows і перезапустіть Windows. Якщо проблема не зникне, зверніться до системного адміністратора або служби підтримки; не змінюйте WindowsApps чи дані пакетів вручну."
LangString InstallerErrorUnknown ${LANG_UKRAINIAN} "Під час встановлення виникла проблема. Програму не вдалося встановити.$\r$\n$\r$\nПерезапустіть Windows і знову запустіть останню версію інсталятора.$\r$\n$\r$\nЯкщо проблема не зникне, створіть Issue на GitHub і додайте знімок цього вікна та діагностичні дані.$\r$\nНе видаляйте спільні середовища виконання або файли пакетів Windows вручну."

LangString InstallerErrorComponent ${LANG_ENGLISH} "Component: $InstallerErrorTarget"
LangString InstallerErrorCode ${LANG_ENGLISH} "SIDEY error code: $InstallerErrorSideyCode"
LangString InstallerErrorLog ${LANG_ENGLISH} "Diagnostic data: $InstallerErrorLogPath"
LangString InstallerErrorUnknownComponent ${LANG_ENGLISH} "Required Windows component"
LangString InstallerErrorComponent ${LANG_KOREAN} "구성 요소: $InstallerErrorTarget"
LangString InstallerErrorCode ${LANG_KOREAN} "오류 코드: $InstallerErrorSideyCode"
LangString InstallerErrorLog ${LANG_KOREAN} "진단 데이터: $InstallerErrorLogPath"
LangString InstallerErrorUnknownComponent ${LANG_KOREAN} "필수 Windows 구성 요소"
LangString InstallerErrorComponent ${LANG_JAPANESE} "コンポーネント: $InstallerErrorTarget"
LangString InstallerErrorCode ${LANG_JAPANESE} "SIDEY エラーコード: $InstallerErrorSideyCode"
LangString InstallerErrorLog ${LANG_JAPANESE} "診断データ: $InstallerErrorLogPath"
LangString InstallerErrorUnknownComponent ${LANG_JAPANESE} "必要な Windows コンポーネント"
LangString InstallerErrorComponent ${LANG_SIMPCHINESE} "组件: $InstallerErrorTarget"
LangString InstallerErrorCode ${LANG_SIMPCHINESE} "SIDEY 错误代码: $InstallerErrorSideyCode"
LangString InstallerErrorLog ${LANG_SIMPCHINESE} "诊断数据: $InstallerErrorLogPath"
LangString InstallerErrorUnknownComponent ${LANG_SIMPCHINESE} "所需 Windows 组件"
LangString InstallerErrorComponent ${LANG_TRADCHINESE} "元件: $InstallerErrorTarget"
LangString InstallerErrorCode ${LANG_TRADCHINESE} "SIDEY 錯誤代碼: $InstallerErrorSideyCode"
LangString InstallerErrorLog ${LANG_TRADCHINESE} "診斷資料: $InstallerErrorLogPath"
LangString InstallerErrorUnknownComponent ${LANG_TRADCHINESE} "必要的 Windows 元件"
LangString InstallerErrorComponent ${LANG_RUSSIAN} "Компонент: $InstallerErrorTarget"
LangString InstallerErrorCode ${LANG_RUSSIAN} "Код ошибки SIDEY: $InstallerErrorSideyCode"
LangString InstallerErrorLog ${LANG_RUSSIAN} "Диагностические данные: $InstallerErrorLogPath"
LangString InstallerErrorUnknownComponent ${LANG_RUSSIAN} "Необходимый компонент Windows"
LangString InstallerErrorComponent ${LANG_UKRAINIAN} "Компонент: $InstallerErrorTarget"
LangString InstallerErrorCode ${LANG_UKRAINIAN} "Код помилки SIDEY: $InstallerErrorSideyCode"
LangString InstallerErrorLog ${LANG_UKRAINIAN} "Діагностичні дані: $InstallerErrorLogPath"
LangString InstallerErrorUnknownComponent ${LANG_UKRAINIAN} "Потрібний компонент Windows"
LangString InstallerErrorOpenLog ${LANG_ENGLISH} "Open the diagnostic log now?"
LangString InstallerErrorOpenLog ${LANG_KOREAN} "지금 진단 로그를 여시겠습니까?"
LangString InstallerErrorOpenLog ${LANG_JAPANESE} "診断ログを今すぐ開きますか？"
LangString InstallerErrorOpenLog ${LANG_SIMPCHINESE} "是否立即打开诊断日志？"
LangString InstallerErrorOpenLog ${LANG_TRADCHINESE} "是否要立即開啟診斷記錄？"
LangString InstallerErrorOpenLog ${LANG_RUSSIAN} "Открыть журнал диагностики сейчас?"
LangString InstallerErrorOpenLog ${LANG_UKRAINIAN} "Відкрити журнал діагностики зараз?"

LangString InstallerComponentInstallation ${LANG_ENGLISH} "SIDEY installation"
LangString InstallerComponentInstallationState ${LANG_ENGLISH} "SIDEY installation state"
LangString InstallerComponentPayload ${LANG_ENGLISH} "SIDEY application files"
LangString InstallerComponentProcesses ${LANG_ENGLISH} "Running SIDEY processes"
LangString InstallerComponentRegistration ${LANG_ENGLISH} "SIDEY shortcuts and Windows registration"
LangString InstallerComponentRemoval ${LANG_ENGLISH} "SIDEY removal"
LangString InstallerComponentRemovalState ${LANG_ENGLISH} "SIDEY removal state"
LangString InstallerComponentCurrentUserData ${LANG_ENGLISH} "Current-user SIDEY data, credentials, or startup entry"
LangString InstallerComponentInstallation ${LANG_KOREAN} "SIDEY 설치"
LangString InstallerComponentInstallationState ${LANG_KOREAN} "SIDEY 설치 상태"
LangString InstallerComponentPayload ${LANG_KOREAN} "SIDEY 앱 파일"
LangString InstallerComponentProcesses ${LANG_KOREAN} "실행 중인 SIDEY 프로세스"
LangString InstallerComponentRegistration ${LANG_KOREAN} "SIDEY 바로가기 및 Windows 등록"
LangString InstallerComponentRemoval ${LANG_KOREAN} "SIDEY 제거"
LangString InstallerComponentRemovalState ${LANG_KOREAN} "SIDEY 제거 상태"
LangString InstallerComponentCurrentUserData ${LANG_KOREAN} "현재 사용자의 SIDEY 데이터, 자격 증명 또는 시작프로그램 항목"
LangString InstallerComponentInstallation ${LANG_JAPANESE} "SIDEY のインストール"
LangString InstallerComponentInstallationState ${LANG_JAPANESE} "SIDEY のインストール状態"
LangString InstallerComponentPayload ${LANG_JAPANESE} "SIDEY アプリのファイル"
LangString InstallerComponentProcesses ${LANG_JAPANESE} "実行中の SIDEY プロセス"
LangString InstallerComponentRegistration ${LANG_JAPANESE} "SIDEY のショートカットと Windows 登録"
LangString InstallerComponentRemoval ${LANG_JAPANESE} "SIDEY の削除"
LangString InstallerComponentRemovalState ${LANG_JAPANESE} "SIDEY の削除状態"
LangString InstallerComponentCurrentUserData ${LANG_JAPANESE} "現在のユーザーの SIDEY データ、資格情報、またはスタートアップ項目"
LangString InstallerComponentInstallation ${LANG_SIMPCHINESE} "SIDEY 安装"
LangString InstallerComponentInstallationState ${LANG_SIMPCHINESE} "SIDEY 安装状态"
LangString InstallerComponentPayload ${LANG_SIMPCHINESE} "SIDEY 应用文件"
LangString InstallerComponentProcesses ${LANG_SIMPCHINESE} "正在运行的 SIDEY 进程"
LangString InstallerComponentRegistration ${LANG_SIMPCHINESE} "SIDEY 快捷方式和 Windows 注册信息"
LangString InstallerComponentRemoval ${LANG_SIMPCHINESE} "SIDEY 卸载"
LangString InstallerComponentRemovalState ${LANG_SIMPCHINESE} "SIDEY 卸载状态"
LangString InstallerComponentCurrentUserData ${LANG_SIMPCHINESE} "当前用户的 SIDEY 数据、凭据或启动项"
LangString InstallerComponentInstallation ${LANG_TRADCHINESE} "SIDEY 安裝"
LangString InstallerComponentInstallationState ${LANG_TRADCHINESE} "SIDEY 安裝狀態"
LangString InstallerComponentPayload ${LANG_TRADCHINESE} "SIDEY 應用程式檔案"
LangString InstallerComponentProcesses ${LANG_TRADCHINESE} "執行中的 SIDEY 處理程序"
LangString InstallerComponentRegistration ${LANG_TRADCHINESE} "SIDEY 捷徑和 Windows 登錄資訊"
LangString InstallerComponentRemoval ${LANG_TRADCHINESE} "SIDEY 解除安裝"
LangString InstallerComponentRemovalState ${LANG_TRADCHINESE} "SIDEY 解除安裝狀態"
LangString InstallerComponentCurrentUserData ${LANG_TRADCHINESE} "目前使用者的 SIDEY 資料、認證或啟動項目"
LangString InstallerComponentInstallation ${LANG_RUSSIAN} "Установка SIDEY"
LangString InstallerComponentInstallationState ${LANG_RUSSIAN} "Состояние установки SIDEY"
LangString InstallerComponentPayload ${LANG_RUSSIAN} "Файлы приложения SIDEY"
LangString InstallerComponentProcesses ${LANG_RUSSIAN} "Запущенные процессы SIDEY"
LangString InstallerComponentRegistration ${LANG_RUSSIAN} "Ярлыки SIDEY и регистрация в Windows"
LangString InstallerComponentRemoval ${LANG_RUSSIAN} "Удаление SIDEY"
LangString InstallerComponentRemovalState ${LANG_RUSSIAN} "Состояние удаления SIDEY"
LangString InstallerComponentCurrentUserData ${LANG_RUSSIAN} "Данные, учётные данные или элемент автозапуска SIDEY текущего пользователя"
LangString InstallerComponentInstallation ${LANG_UKRAINIAN} "Встановлення SIDEY"
LangString InstallerComponentInstallationState ${LANG_UKRAINIAN} "Стан встановлення SIDEY"
LangString InstallerComponentPayload ${LANG_UKRAINIAN} "Файли програми SIDEY"
LangString InstallerComponentProcesses ${LANG_UKRAINIAN} "Запущені процеси SIDEY"
LangString InstallerComponentRegistration ${LANG_UKRAINIAN} "Ярлики SIDEY і реєстрація у Windows"
LangString InstallerComponentRemoval ${LANG_UKRAINIAN} "Видалення SIDEY"
LangString InstallerComponentRemovalState ${LANG_UKRAINIAN} "Стан видалення SIDEY"
LangString InstallerComponentCurrentUserData ${LANG_UKRAINIAN} "Дані, облікові дані або елемент автозапуску SIDEY поточного користувача"

Function InitializeInstallerErrorHandling
  InitPluginsDir
  ; Sidey.Setup.nsi uses SetShellVarContext all, so $APPDATA resolves to
  ; the machine-wide ProgramData folder even during over-the-shoulder elevation.
  CreateDirectory "$APPDATA\SIDEY\Installer\Logs"
  ${GetTime} "" "L" $0 $1 $2 $3 $4 $5 $6
  StrCpy $InstallerErrorLogPath "$APPDATA\SIDEY\Installer\Logs\SIDEY-Setup-$2$1$0-$4$5$6.log"
  StrCpy $InstallerErrorResultPath "$PLUGINSDIR\InstallerResult.ini"
FunctionEnd

Function ResetInstallerError
  StrCpy $InstallerErrorStatus "FAILED"
  StrCpy $InstallerErrorCategory "UNKNOWN_ERROR"
  StrCpy $InstallerErrorSource "UNKNOWN"
  StrCpy $InstallerErrorNativeCode "UNKNOWN"
  StrCpy $InstallerErrorSideyCode "0x51DE10FF"
  StrCpy $InstallerErrorStage "INSTALL"
  StrCpy $InstallerErrorSymbol ""
  StrCpy $InstallerErrorDetail ""
  StrCpy $InstallerErrorTarget ""
  StrCpy $InstallerErrorCommand ""
  StrCpy $InstallerErrorExitCode ""
  StrCpy $InstallerErrorResultLoaded "false"
  Delete "$InstallerErrorResultPath"
FunctionEnd

Function LoadInstallerResult
  ReadINIStr $R0 "$InstallerErrorResultPath" "InstallerResult" "status"
  ${If} $R0 != ""
    StrCpy $InstallerErrorStatus $R0
    StrCpy $InstallerErrorResultLoaded "true"
  ${EndIf}
  ReadINIStr $R0 "$InstallerErrorResultPath" "InstallerResult" "category"
  ${If} $R0 != ""
    StrCpy $InstallerErrorCategory $R0
  ${EndIf}
  ReadINIStr $R0 "$InstallerErrorResultPath" "InstallerResult" "source"
  ${If} $R0 != ""
    StrCpy $InstallerErrorSource $R0
  ${EndIf}
  ReadINIStr $R0 "$InstallerErrorResultPath" "InstallerResult" "nativeCode"
  ${If} $R0 != ""
    StrCpy $InstallerErrorNativeCode $R0
  ${EndIf}
  ReadINIStr $R0 "$InstallerErrorResultPath" "InstallerResult" "stage"
  ${If} $R0 != ""
    StrCpy $InstallerErrorStage $R0
  ${EndIf}
  ReadINIStr $R0 "$InstallerErrorResultPath" "InstallerResult" "symbol"
  ${If} $R0 != ""
    StrCpy $InstallerErrorSymbol $R0
  ${EndIf}
  ReadINIStr $R0 "$InstallerErrorResultPath" "InstallerResult" "detail"
  ${If} $R0 != ""
    StrCpy $InstallerErrorDetail $R0
  ${EndIf}
  ReadINIStr $R0 "$InstallerErrorResultPath" "InstallerResult" "target"
  ${If} $R0 != ""
    StrCpy $InstallerErrorTarget $R0
  ${EndIf}
  ReadINIStr $R0 "$InstallerErrorResultPath" "InstallerResult" "command"
  ${If} $R0 != ""
    StrCpy $InstallerErrorCommand $R0
  ${EndIf}
  ReadINIStr $R0 "$InstallerErrorResultPath" "InstallerResult" "exitCode"
  ${If} $R0 != ""
    StrCpy $InstallerErrorExitCode $R0
  ${EndIf}
FunctionEnd

Function NormalizeInstallerError
  Delete "$InstallerErrorResultPath"
  ClearErrors
  ExecWait '"$PLUGINSDIR\Sidey.InstallerErrorHelper.exe" --normalize-error --native-code "$InstallerErrorNativeCode" --source "$InstallerErrorSource" --stage "$InstallerErrorStage" --target "$InstallerErrorTarget" --command-description "$InstallerErrorCommand" --exit-code "$InstallerErrorExitCode" --result-path "$InstallerErrorResultPath" --log-path "$InstallerErrorLogPath" --installer-version "${APP_VERSION}"' $R0
  Call LoadInstallerResult
FunctionEnd

Function GetInstallerErrorMessage
  !insertmacro ResolveSideyInstallerErrorCode
  ${If} $InstallerErrorTarget == ""
    StrCpy $InstallerErrorTarget "$(InstallerErrorUnknownComponent)"
  ${EndIf}
  ${If} $InstallerErrorCategory == "NETWORK_ERROR"
    StrCpy $InstallerErrorMessage "$(InstallerErrorNetwork)"
  ${ElseIf} $InstallerErrorCategory == "DOWNLOAD_FAILED"
    StrCpy $InstallerErrorMessage "$(InstallerErrorDownload)"
  ${ElseIf} $InstallerErrorCategory == "DISK_FULL"
    StrCpy $InstallerErrorMessage "$(InstallerErrorDiskFull)"
  ${ElseIf} $InstallerErrorCategory == "PERMISSION_DENIED"
    StrCpy $InstallerErrorMessage "$(InstallerErrorPermission)"
  ${ElseIf} $InstallerErrorCategory == "BLOCKED_BY_POLICY"
    StrCpy $InstallerErrorMessage "$(InstallerErrorPolicy)"
  ${ElseIf} $InstallerErrorCategory == "PACKAGE_CORRUPTED"
    StrCpy $InstallerErrorMessage "$(InstallerErrorPackage)"
  ${ElseIf} $InstallerErrorCategory == "SIGNATURE_ERROR"
    StrCpy $InstallerErrorMessage "$(InstallerErrorSignature)"
  ${ElseIf} $InstallerErrorCategory == "DEPENDENCY_MISSING"
    StrCpy $InstallerErrorMessage "$(InstallerErrorDependency)"
  ${ElseIf} $InstallerErrorCategory == "DEPENDENCY_CONFLICT"
    StrCpy $InstallerErrorMessage "$(InstallerErrorDependencyConflict)"
  ${ElseIf} $InstallerErrorCategory == "INCOMPATIBLE_SYSTEM"
    StrCpy $InstallerErrorMessage "$(InstallerErrorIncompatible)"
  ${ElseIf} $InstallerErrorCategory == "APP_IN_USE"
    StrCpy $InstallerErrorMessage "$(InstallerErrorAppInUse)"
  ${ElseIf} $InstallerErrorCategory == "ANOTHER_INSTALLATION_RUNNING"
    StrCpy $InstallerErrorMessage "$(InstallerErrorAnotherInstall)"
  ${ElseIf} $InstallerErrorCategory == "ALREADY_INSTALLED"
    StrCpy $InstallerErrorMessage "$(InstallerErrorAlreadyInstalled)"
  ${ElseIf} $InstallerErrorCategory == "REBOOT_REQUIRED"
    StrCpy $InstallerErrorMessage "$(InstallerErrorRestart)"
  ${ElseIf} $InstallerErrorCategory == "USER_CANCELLED"
    StrCpy $InstallerErrorMessage "$(InstallerErrorCancelled)"
  ${ElseIf} $InstallerErrorCategory == "PACKAGE_REGISTRATION_FAILED"
    StrCpy $InstallerErrorMessage "$(InstallerErrorRegistration)"
  ${ElseIf} $InstallerErrorCategory == "PACKAGE_REPOSITORY_CORRUPTED"
    StrCpy $InstallerErrorMessage "$(InstallerErrorRepository)"
  ${Else}
    StrCpy $InstallerErrorMessage "$(InstallerErrorUnknown)"
  ${EndIf}
  StrCpy $InstallerErrorMessage "$InstallerErrorMessage$\r$\n$\r$\n$(InstallerErrorComponent)$\r$\n$(InstallerErrorLog)$\r$\n$\r$\n$(InstallerErrorCode)"
FunctionEnd

Function LogInstallerErrorFallback
  FileOpen $R0 "$InstallerErrorLogPath" a
  ${IfNot} ${Errors}
    ${GetTime} "" "L" $R1 $R2 $R3 $R4 $R5 $R6 $R7
    FileWrite $R0 "[InstallerError]$\r$\n"
    FileWrite $R0 "timestamp=$R3-$R2-$R1T$R5:$R6:$R7$\r$\n"
    FileWrite $R0 "status=$InstallerErrorStatus$\r$\n"
    FileWrite $R0 "category=$InstallerErrorCategory$\r$\n"
    FileWrite $R0 "source=$InstallerErrorSource$\r$\n"
    FileWrite $R0 "nativeCode=$InstallerErrorNativeCode$\r$\n"
    FileWrite $R0 "sideyCode=$InstallerErrorSideyCode$\r$\n"
    FileWrite $R0 "stage=$InstallerErrorStage$\r$\n"
    FileWrite $R0 "message=$InstallerErrorSymbol$\r$\n"
    FileWrite $R0 "detail=$InstallerErrorDetail$\r$\n"
    FileWrite $R0 "target=$InstallerErrorTarget$\r$\n"
    FileWrite $R0 "command=$InstallerErrorCommand$\r$\n"
    FileWrite $R0 "exitCode=$InstallerErrorExitCode$\r$\n"
    FileWrite $R0 "installerVersion=${APP_VERSION}$\r$\n$\r$\n"
    FileClose $R0
  ${EndIf}
FunctionEnd

Function LogInstallerDisplayCode
  FileOpen $R0 "$InstallerErrorLogPath" a
  ${IfNot} ${Errors}
    ${GetTime} "" "L" $R1 $R2 $R3 $R4 $R5 $R6 $R7
    FileWrite $R0 "[InstallerDisplay]$\r$\n"
    FileWrite $R0 "timestamp=$R3-$R2-$R1T$R5:$R6:$R7$\r$\n"
    FileWrite $R0 "sideyCode=$InstallerErrorSideyCode$\r$\n"
    FileWrite $R0 "message=$InstallerErrorSymbol$\r$\n$\r$\n"
    FileClose $R0
  ${EndIf}
FunctionEnd

Function ShowInstallerError
  !insertmacro ResolveSideyInstallerErrorCode
  ${If} $InstallerErrorResultLoaded == "true"
    Call LogInstallerDisplayCode
  ${Else}
    Call LogInstallerErrorFallback
  ${EndIf}
  Call GetInstallerErrorMessage
  DetailPrint "Installer result: status=$InstallerErrorStatus category=$InstallerErrorCategory source=$InstallerErrorSource nativeCode=$InstallerErrorNativeCode stage=$InstallerErrorStage"
  ${If} $InstallerErrorStatus == "SUCCESS_REBOOT_REQUIRED"
    MessageBox MB_OK|MB_ICONEXCLAMATION "$InstallerErrorMessage" /SD IDOK
  ${ElseIf} $InstallerErrorCategory == "USER_CANCELLED"
    MessageBox MB_OK|MB_ICONINFORMATION "$InstallerErrorMessage" /SD IDOK
  ${Else}
    MessageBox MB_OK|MB_ICONSTOP "$InstallerErrorMessage" /SD IDOK
  ${EndIf}
  IfFileExists "$InstallerErrorLogPath" 0 installer_error_done
  MessageBox MB_YESNO|MB_ICONQUESTION "$(InstallerErrorOpenLog)" /SD IDNO IDNO installer_error_done
  ClearErrors
  ExecShell "open" "$SYSDIR\notepad.exe" '"$InstallerErrorLogPath"'
  ${If} ${Errors}
    DetailPrint "The diagnostic log could not be opened: $InstallerErrorLogPath"
  ${EndIf}
  installer_error_done:
FunctionEnd

Function ShowLifecycleError
  !insertmacro ResolveSideyInstallerErrorCode
  Call LogInstallerErrorFallback
  ${If} $InstallerErrorTarget == ""
    StrCpy $InstallerErrorTarget "$(InstallerErrorUnknownComponent)"
  ${EndIf}
  StrCpy $InstallerErrorMessage "$InstallerErrorMessage$\r$\n$\r$\n$(InstallerErrorComponent)$\r$\n$(InstallerErrorLog)$\r$\n$\r$\n$(InstallerErrorCode)"
  DetailPrint "Installer lifecycle result: status=$InstallerErrorStatus category=$InstallerErrorCategory source=$InstallerErrorSource nativeCode=$InstallerErrorNativeCode stage=$InstallerErrorStage"
  ${If} $InstallerErrorStatus == "COMPLETED_WITH_WARNINGS"
    MessageBox MB_OK|MB_ICONEXCLAMATION "$InstallerErrorMessage" /SD IDOK
  ${Else}
    MessageBox MB_OK|MB_ICONSTOP "$InstallerErrorMessage" /SD IDOK
  ${EndIf}
  IfFileExists "$InstallerErrorLogPath" 0 lifecycle_error_done
  MessageBox MB_YESNO|MB_ICONQUESTION "$(InstallerErrorOpenLog)" /SD IDNO IDNO lifecycle_error_done
  ClearErrors
  ExecShell "open" "$SYSDIR\notepad.exe" '"$InstallerErrorLogPath"'
  ${If} ${Errors}
    DetailPrint "The diagnostic log could not be opened: $InstallerErrorLogPath"
  ${EndIf}
  lifecycle_error_done:
FunctionEnd

Function un.InitializeInstallerErrorHandling
  InitPluginsDir
  CreateDirectory "$APPDATA\SIDEY\Installer\Logs"
  ${GetTime} "" "L" $0 $1 $2 $3 $4 $5 $6
  StrCpy $InstallerErrorLogPath "$APPDATA\SIDEY\Installer\Logs\SIDEY-Uninstall-$2$1$0-$4$5$6.log"
  StrCpy $InstallerErrorResultPath "$PLUGINSDIR\InstallerResult.ini"
FunctionEnd

Function un.ResetInstallerError
  StrCpy $InstallerErrorStatus "FAILED"
  StrCpy $InstallerErrorCategory "UNKNOWN_ERROR"
  StrCpy $InstallerErrorSource "UNKNOWN"
  StrCpy $InstallerErrorNativeCode "UNKNOWN"
  StrCpy $InstallerErrorSideyCode "0x51DE30FF"
  StrCpy $InstallerErrorStage "UNINSTALL"
  StrCpy $InstallerErrorSymbol ""
  StrCpy $InstallerErrorDetail ""
  StrCpy $InstallerErrorTarget ""
  StrCpy $InstallerErrorCommand ""
  StrCpy $InstallerErrorExitCode ""
  StrCpy $InstallerErrorResultLoaded "false"
  Delete "$InstallerErrorResultPath"
FunctionEnd

Function un.LogInstallerErrorFallback
  FileOpen $R0 "$InstallerErrorLogPath" a
  ${IfNot} ${Errors}
    ${GetTime} "" "L" $R1 $R2 $R3 $R4 $R5 $R6 $R7
    FileWrite $R0 "[InstallerError]$\r$\n"
    FileWrite $R0 "timestamp=$R3-$R2-$R1T$R5:$R6:$R7$\r$\n"
    FileWrite $R0 "status=$InstallerErrorStatus$\r$\n"
    FileWrite $R0 "category=$InstallerErrorCategory$\r$\n"
    FileWrite $R0 "source=$InstallerErrorSource$\r$\n"
    FileWrite $R0 "nativeCode=$InstallerErrorNativeCode$\r$\n"
    FileWrite $R0 "sideyCode=$InstallerErrorSideyCode$\r$\n"
    FileWrite $R0 "stage=$InstallerErrorStage$\r$\n"
    FileWrite $R0 "message=$InstallerErrorSymbol$\r$\n"
    FileWrite $R0 "detail=$InstallerErrorDetail$\r$\n"
    FileWrite $R0 "target=$InstallerErrorTarget$\r$\n"
    FileWrite $R0 "command=$InstallerErrorCommand$\r$\n"
    FileWrite $R0 "exitCode=$InstallerErrorExitCode$\r$\n"
    FileWrite $R0 "installerVersion=${APP_VERSION}$\r$\n$\r$\n"
    FileClose $R0
  ${EndIf}
FunctionEnd

Function un.ShowLifecycleError
  !insertmacro ResolveSideyInstallerErrorCode
  Call un.LogInstallerErrorFallback
  ${If} $InstallerErrorTarget == ""
    StrCpy $InstallerErrorTarget "$(InstallerErrorUnknownComponent)"
  ${EndIf}
  StrCpy $InstallerErrorMessage "$InstallerErrorMessage$\r$\n$\r$\n$(InstallerErrorComponent)$\r$\n$(InstallerErrorLog)$\r$\n$\r$\n$(InstallerErrorCode)"
  DetailPrint "Uninstaller lifecycle result: status=$InstallerErrorStatus category=$InstallerErrorCategory source=$InstallerErrorSource nativeCode=$InstallerErrorNativeCode stage=$InstallerErrorStage"
  ${If} $InstallerErrorStatus == "COMPLETED_WITH_WARNINGS"
    MessageBox MB_OK|MB_ICONEXCLAMATION "$InstallerErrorMessage" /SD IDOK
  ${Else}
    MessageBox MB_OK|MB_ICONSTOP "$InstallerErrorMessage" /SD IDOK
  ${EndIf}
  IfFileExists "$InstallerErrorLogPath" 0 uninstall_lifecycle_error_done
  MessageBox MB_YESNO|MB_ICONQUESTION "$(InstallerErrorOpenLog)" /SD IDNO IDNO uninstall_lifecycle_error_done
  ClearErrors
  ExecShell "open" "$SYSDIR\notepad.exe" '"$InstallerErrorLogPath"'
  ${If} ${Errors}
    DetailPrint "The diagnostic log could not be opened: $InstallerErrorLogPath"
  ${EndIf}
  uninstall_lifecycle_error_done:
FunctionEnd
