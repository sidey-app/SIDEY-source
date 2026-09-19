import SwiftUI
import AuthenticationServices

struct AppSettingsView: View {
    @Bindable var model: AppModel
    let actions: SettingsActions
    let storeAvailability: StoreAvailability
    @State private var showsDeletionControls = false
    @State private var deletionPhrase = ""

    init(
        model: AppModel,
        actions: SettingsActions,
        storeAvailability: StoreAvailability = AppReleaseChannel.resolve().storeAvailability
    ) {
        self.model = model
        self.actions = actions
        self.storeAvailability = storeAvailability
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            #if DEBUG
            Text("\(SideyBuildStamp.target) · \(SideyBuildStamp.commit.prefix(8))\(SideyBuildStamp.dirty ? " · 미커밋 변경" : "")")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            #endif
            SettingsSection(
                title: "일반",
                subtitle: "SIDEY의 기본 표시와 실행 방식을 설정할 수 있습니다.",
                systemImage: "gearshape"
            ) {
                SettingsToggleRow(
                    title: "픽셀 월드 표시",
                    description: "선택한 화면 가장자리에 친구들의 픽셀 월드를 표시합니다.",
                    isOn: Binding(
                        get: { model.overlayVisible },
                        set: { actions.onOverlayVisibilityChanged($0) }
                    )
                )
                Divider()
                SettingsToggleRow(
                    title: "로그인 시 자동 실행",
                    description: "Mac에 로그인하면 SIDEY를 자동으로 시작합니다.",
                    isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { actions.onLaunchAtLoginChanged($0) }
                    )
                )
            }

            SettingsSection(
                title: "표시",
                subtitle: "친구 상태와 메시지가 화면에 나타나는 방식을 조절할 수 있습니다.",
                systemImage: "eye"
            ) {
                SettingsToggleRow(
                    title: "조용히 모드",
                    description: "메시지 본문 말풍선은 숨기고 타이핑 상태와 미확인 수는 유지합니다.",
                    isOn: Binding(
                        get: { model.preferences.quietModeEnabled },
                        set: { actions.onQuietModeChanged($0) }
                    )
                )
                Divider()
                SettingsToggleRow(
                    title: "오프라인 멤버 표시",
                    description: "접속하지 않은 친구도 잠든 캐릭터와 빨간 상태 점으로 표시합니다.",
                    isOn: Binding(
                        get: { model.preferences.showOfflineMembers },
                        set: { actions.onShowOfflineMembersChanged($0) }
                    )
                )
                Divider()
                SettingsToggleRow(
                    title: "더블 우클릭 후 던지기",
                    description: "끄면 친구 캐릭터를 바로 클릭할 수 있고, 켜면 내 캐릭터를 더블 우클릭한 뒤 10초 동안만 클릭할 수 있습니다.",
                    isOn: Binding(
                        get: { model.preferences.requiresRightClickToThrow },
                        set: { actions.onRequiresRightClickToThrowChanged($0) }
                    )
                )
            }

            SettingsSection(title: "소리", subtitle: "캐릭터 효과음 재생을 설정합니다.", systemImage: "speaker.wave.2") {
                SettingsToggleRow(
                    title: "캐릭터 효과음",
                    description: "현재 그룹에서 캐릭터가 맞을 때 효과음을 재생합니다.",
                    isOn: Binding(get: { model.preferences.characterSoundEffectsEnabled },
                                  set: { actions.onCharacterSoundEffectsChanged($0) })
                )
            }

            SettingsSection(
                title: "월드 배치",
                subtitle: "픽셀 캐릭터를 표시할 화면과 위치를 선택할 수 있습니다.",
                systemImage: "rectangle.inset.filled"
            ) {
                SettingsControlRow(
                    title: "가장자리",
                    description: "캐릭터가 걸어 다닐 화면 방향을 선택합니다."
                ) {
                    Picker("가장자리", selection: regionEdgeBinding) {
                        ForEach(OverlayEdge.allCases) { edge in
                            Text(edge.title).tag(edge)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180, alignment: .trailing)
                }
                Divider()
                SettingsControlRow(
                    title: "영역 길이",
                    description: "선택한 가장자리에서 월드가 차지할 범위를 선택합니다."
                ) {
                    Picker("길이", selection: regionSpanBinding) {
                        ForEach(OverlaySpan.allCases) { span in
                            Text(span.title).tag(span)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180, alignment: .trailing)
                }
                Divider()
                SettingsControlRow(
                    title: "모니터",
                    description: "픽셀 월드와 메시지 입력창을 표시할 화면을 선택합니다."
                ) {
                    Picker("모니터", selection: regionScreenBinding) {
                        ForEach(model.availableScreens) { screen in
                            Text(screen.name).tag(Optional(screen.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240, alignment: .trailing)
                }
            }

            if storeAvailability.usesAppStore {
                accountSection
            }

        }
    }

    private var accountSection: some View {
        SettingsSection(
            title: "계정 및 개인정보",
            subtitle: "계정 데이터와 App Store 구매 연결을 관리합니다.",
            systemImage: "person.crop.circle"
        ) {
            HStack(spacing: 18) {
                Link(
                    "개인정보 처리방침",
                    destination: URL(string: "https://sidey-app.github.io/SIDEY/privacy.html")!
                )
                Link(
                    "이용약관",
                    destination: URL(string: "https://sidey-app.github.io/SIDEY/terms.html")!
                )
                Spacer()
                Button("구매 복원", action: actions.onRestorePurchases)
                    .disabled(model.accountOperationInProgress)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("계정 탈퇴")
                    .font(.body.weight(.semibold))
                Text("프로필, 메시지, 그룹 멤버십을 삭제합니다. 구매 기록은 회계·부정 사용 방지에 필요한 범위에서 계정과 분리해 보관될 수 있습니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if showsDeletionControls {
                    TextField("확인을 위해 ‘탈퇴’ 입력", text: $deletionPhrase)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                    SignInWithAppleButton(.continue) { request in
                        let nonce = AppleAuthorization.makeNonce()
                        AppleAuthorization.prepare(request, nonce: nonce)
                    } onCompletion: { result in
                        do {
                            let payload = try AppleAuthorization.payload(from: result)
                            actions.onDeleteAccount(payload)
                        } catch {
                            model.errorMessage = error.localizedDescription
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(width: 280, height: 40)
                    .disabled(deletionPhrase != "탈퇴" || model.accountOperationInProgress)
                    Text("‘탈퇴’를 입력한 뒤 Apple로 다시 인증하면 즉시 삭제됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("계정 탈퇴…", role: .destructive) {
                        showsDeletionControls = true
                    }
                }
            }
        }
    }

    private var regionEdgeBinding: Binding<OverlayEdge> {
        Binding(
            get: { model.preferences.overlayRegion.edge },
            set: { edge in
                var preference = model.preferences.overlayRegion
                preference.edge = edge
                actions.onOverlayRegionChanged(preference)
            }
        )
    }

    private var regionSpanBinding: Binding<OverlaySpan> {
        Binding(
            get: { model.preferences.overlayRegion.span },
            set: { span in
                var preference = model.preferences.overlayRegion
                preference.span = span
                actions.onOverlayRegionChanged(preference)
            }
        )
    }

    private var regionScreenBinding: Binding<String?> {
        Binding(
            get: { model.preferences.overlayRegion.screenIdentifier },
            set: { screenIdentifier in
                var preference = model.preferences.overlayRegion
                preference.screenIdentifier = screenIdentifier
                actions.onOverlayRegionChanged(preference)
            }
        )
    }
}
