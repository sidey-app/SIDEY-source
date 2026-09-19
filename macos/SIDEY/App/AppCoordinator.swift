import AppKit

@MainActor
final class AppCoordinator {
    let model: AppModel

    lazy var typingActivity = makeTypingActivity()

    private func makeTypingActivity() -> TypingActivityController {
        TypingActivityController(
            now: { ProcessInfo.processInfo.systemUptime },
            automaticallySchedule: true,
            publish: { [weak self] roomID, event in
                try await self?.backend?.broadcastTyping(roomID: roomID, event: event)
            },
            localTyping: { [weak self] roomID, active in
                guard let self, let userID = model.currentUserID else { return }
                model.updateTyping(roomID: roomID, userID: userID, active: active)
            }
        )
    }

    let preferencesStore: PreferencesStore
    private let legacyMigrator: LegacySettingsMigrator
    let releaseChannel: AppReleaseChannel
    var backend: SideyBackend?
    private let runtimeConfiguration: RuntimeConfiguration?
    let configurationError: Error?
    let keychainAccessSession: KeychainAccessSession
    let launchReason: LaunchReason
    private let onLandingFirstFrame: () -> Void
    private let launchAtLoginController: LaunchAtLoginController
    lazy var overlayWindows = OverlayWindowGroup(
        model: model,
        onSend: { [weak self] body in self?.sendMessage(body) },
        onTypingChanged: { [weak self] active in self?.typingChanged(active) },
        onCharacterDoubleClick: { [weak self] in self?.characterDoubleClicked() },
        onTargetCharacterClick: { [weak self] userID in self?.characterThrowRequested(targetUserID: userID) },
        onRegionChanged: { [weak self] in self?.persistPreferences() },
        onTreeMovementToggle: { [weak self] in self?.toggleTreeMovement() }
    )
    private lazy var historyWindow = makeHistoryWindow()
    lazy var settingsWindow = SettingsWindowController(
        model: model,
        actions: SettingsActions(
            onOverlayVisibilityChanged: { [weak self] visible in self?.setOverlayVisible(visible) },
            onOverlayRegionChanged: { [weak self] preference in self?.setOverlayRegion(preference) },
            onShowOfflineMembersChanged: { [weak self] visible in self?.setShowOfflineMembers(visible) },
            onRequiresRightClickToThrowChanged: { [weak self] required in
                self?.setRequiresRightClickToThrow(required)
            },
            onQuietModeChanged: { [weak self] enabled in self?.setQuietMode(enabled) },
            onLaunchAtLoginChanged: { [weak self] enabled in self?.setLaunchAtLogin(enabled) },
            onPurchase: { [weak self] productID in self?.purchase(productID: productID) },
            onRefreshCommerceState: { [weak self] productID in
                self?.refreshCommerceState(productID: productID)
            },
            onSetEquippedCosmetic: { [weak self] kind, catalogItemID in
                self?.setEquippedCosmetic(kind: kind, catalogItemID: catalogItemID)
            },
            onRestorePurchases: { [weak self] in self?.restoreAppStorePurchases() },
            onSignInWithApple: { [weak self] payload in self?.signInWithApple(payload) },
            onDeleteAccount: { [weak self] payload in self?.deleteAccount(payload) },
            onSaveProfile: { [weak self] in self?.saveProfile() },
            onSetCharacter: { [weak self] characterID in self?.setCharacter(characterID) },
            onCreateRoom: { [weak self] in self?.createRoom() },
            onJoinRoom: { [weak self] in self?.joinRoom() },
            onSelectRoom: { [weak self] roomID in self?.selectRoom(roomID) },
            onCopyInviteCode: { [weak self] roomID in
                await self?.copyInviteCode(roomID: roomID) ?? false
            },
            onRotateInviteCode: { [weak self] roomID in self?.rotateInviteCode(roomID: roomID) },
            onRenameRoom: { [weak self] roomID, name in self?.renameRoom(roomID, name: name) },
            onRemoveRoomMember: { [weak self] roomID, userID in self?.removeRoomMember(roomID, userID: userID) },
            onLeaveRoom: { [weak self] roomID in self?.leaveRoom(roomID) },
            onDeleteRoom: { [weak self] roomID in self?.deleteRoom(roomID) },
            onCharacterSoundEffectsChanged: { [weak self] enabled in
                guard let self else { return }
                self.model.preferences.characterSoundEffectsEnabled = enabled
                self.model.characterImpactAudio.isEnabled = enabled
                self.persistPreferences()
            },
            onCharacterImpact: { [weak self] id, time in
                guard let self else { return }
                self.model.characterImpactAudio.isEnabled = self.model.preferences.characterSoundEffectsEnabled
                self.model.characterImpactAudio.play(objectID: id, at: time)
            },
            onStopCharacterSounds: { [weak self] in
                self?.model.characterImpactAudio.stopAll()
            }
        ),
        onClose: { [weak self] in self?.settingsDidClose() }
    )
    private lazy var landingWindow = LandingWindowController(
        onSkip: { [weak self] in self?.finishLanding() },
        onFirstFrame: onLandingFirstFrame
    )
    private lazy var statusItemController = StatusItemController(
        onToggleOverlay: { [weak self] in self?.toggleOverlay() },
        onFocusMessage: { [weak self] in self?.focusMessageField() },
        onSelectRoom: { [weak self] roomID in self?.selectRoom(roomID) },
        onToggleQuietMode: { [weak self] in self?.setQuietMode(!(self?.model.preferences.quietModeEnabled ?? false)) },
        onOpenHistory: { [weak self] in self?.showHistory() },
        onOpenStore: { [weak self] in self?.showStore() },
        onToggleLaunchAtLogin: { [weak self] in self?.setLaunchAtLogin(!(self?.model.launchAtLogin ?? false)) },
        onOpenGroupSettings: { [weak self] in self?.showGroupSettings() },
        onOpenSettings: { [weak self] in self?.showSettings() },
        onQuit: { NSApplication.shared.terminate(nil) }
    )
    let commerceSession = CommerceSession()
    let roomSession = RoomSessionLifetime()
    var treeMovementTask: Task<Void, Never>?
    private var landingTask: Task<Void, Never>?
    private var landingDidComplete = false
    private var didCompleteFirstRunTransition = false
    var backendBootstrapState: BackendBootstrapState = .pending
    var backendConnectionStatus: BackendConnectionStatus?
    private lazy var activityMonitor = SystemActivityMonitor { [weak self] state in
        self?.localPresenceChanged(state)
    }
    private let mainThreadProbe = MainThreadPerformanceProbe()

    init(
        preferencesStore: PreferencesStore = .live,
        legacyMigrator: LegacySettingsMigrator = .live,
        keychainAccessSession: KeychainAccessSession = .shared,
        releaseChannel: AppReleaseChannel = .resolve(),
        arguments: [String] = ProcessInfo.processInfo.arguments,
        onLandingFirstFrame: @escaping () -> Void = {}
    ) {
        self.releaseChannel = releaseChannel
        self.launchAtLoginController = LaunchAtLoginController(mode: releaseChannel.loginItemMode)
        self.preferencesStore = preferencesStore
        self.legacyMigrator = legacyMigrator
        self.keychainAccessSession = keychainAccessSession
        self.onLandingFirstFrame = onLandingFirstFrame
        let preferences = legacyMigrator.migrateIfNeeded(preferencesStore)
        self.launchReason = LaunchRouter.reason(
            hasShownNativeLanding: preferences.hasShownNativeLanding,
            arguments: arguments
        )
        self.model = AppModel(preferences: preferences)
        do {
            let configuration = try RuntimeConfiguration.resolve(releaseChannel: releaseChannel)
            self.runtimeConfiguration = configuration
            self.configurationError = nil
        } catch {
            self.runtimeConfiguration = nil
            self.configurationError = error
        }
        self.roomSession.switchPipeline = RoomSwitchPipeline(
            debounce: .milliseconds(150),
            performSwitch: { [weak self] roomID in
                guard let self, let backend = self.backend else {
                    throw SideyBackendError.realtimeUnavailable
                }
                try await backend.setActiveRoom(roomID)
                return try await backend.recentMessages(roomID: roomID)
            },
            restoreCommittedRoom: { [weak self] in
                guard let self, let backend = self.backend else {
                    throw SideyBackendError.realtimeUnavailable
                }
                try await backend.setActiveRoom(self.model.activeRoom?.id)
            },
            operationChanged: { [weak self] operation in
                self?.model.groupOperation = operation
            },
            committed: { [weak self] roomID, messages in
                self?.commitRoomSwitch(roomID: roomID, messages: messages)
            },
            failed: { [weak self] _, error, restoreError in
                self?.handleRoomSwitchFailure(error, restoreError: restoreError)
            }
        )
    }

    func start() {
        keychainAccessSession.setAccessDeniedHandler { _ in
            Task { @MainActor in
                NSApplication.shared.terminate(nil)
            }
        }
        if !model.preferences.keychainTransitionComplete,
           !KeychainTransitionNotice.present() {
            keychainAccessSession.denyFurtherAccess()
            return
        }
        if let runtimeConfiguration {
            backend = SideyBackend(
                configuration: runtimeConfiguration,
                keychain: KeychainStore(
                    service: releaseChannel.keychainService,
                    session: keychainAccessSession
                )
            )
        }

        mainThreadProbe.start()
        statusItemController.install()
        overlayWindows.restore(preference: model.preferences.overlayRegion)
        model.launchAtLogin = launchAtLoginController.isEnabled
        model.preferences.launchAtLogin = model.launchAtLogin

        // Overlay rendering is gated on both completed onboarding and a restored
        // backend session. Keep the user's persisted visibility request intact
        // while the runtime windows remain hidden during bootstrap.
        applyRequestedOverlayVisibility()

        switch launchReason {
        case .firstRun:
            refreshStatusItem()
            showLanding()
        case .manual:
            refreshStatusItem()
            showSettings()
        case .loginItem:
            refreshStatusItem()
            NSApplication.shared.setActivationPolicy(.accessory)
        }
        activityMonitor.start()
        startBackend()
    }

    func handleManualReopen(originatesFromOverlayInteraction: Bool = false) {
        guard ManualReopenPolicy.shouldOpenSettings(
            hasShownNativeLanding: model.preferences.hasShownNativeLanding,
            composerVisible: overlayWindows.composerVisible,
            originatesFromOverlayInteraction: originatesFromOverlayInteraction
        ) else { return }
        showSettings()
    }

    private var shutdownTask: Task<Void, Never>?

    @discardableResult
    func shutdown() -> Task<Void, Never>? {
        if let shutdownTask { return shutdownTask }
        cancelTreeMovementRequests()
        model.treeMovement.reset()
        landingTask?.cancel()
        typingActivity.stop()
        roomSession.cancel()
        commerceSession.cancel(model: model)
        activityMonitor.stop()
        mainThreadProbe.stop()
        let typingActivity = typingActivity
        let backend = backend
        shutdownTask = Task {
            await typingActivity.shutdown()
            await backend?.shutdown()
        }
        keychainAccessSession.setAccessDeniedHandler(nil)
        persistPreferences()
        return shutdownTask
    }

    private func showLanding() {
        NSApplication.shared.setActivationPolicy(.regular)
        landingWindow.show()
        NSApplication.shared.activate(ignoringOtherApps: true)
        landingTask?.cancel()
        landingTask = Task { [weak self] in
            let configured = ProcessInfo.processInfo.environment["SIDEY_LANDING_DURATION_SECONDS"]
                .flatMap(Double.init) ?? 2
            try? await Task.sleep(for: .seconds(max(0.1, configured)))
            guard !Task.isCancelled else { return }
            self?.finishLanding()
        }
    }

    private func finishLanding() {
        guard launchReason == .firstRun, !landingDidComplete else { return }
        landingDidComplete = true
        landingTask?.cancel()
        landingTask = nil
        model.preferences.hasShownNativeLanding = true
        persistPreferences()
        advanceFirstRunTransition()
    }

    func advanceFirstRunTransition() {
        guard launchReason == .firstRun, !didCompleteFirstRunTransition else { return }
        let destination = FirstRunTransition.destination(
            landingCompleted: landingDidComplete,
            onboardingComplete: model.preferences.onboardingComplete,
            backendState: backendBootstrapState
        )
        switch destination {
        case .waiting:
            if landingDidComplete, model.preferences.onboardingComplete {
                landingWindow.setRestoringSession(true)
            }
        case .onboarding:
            didCompleteFirstRunTransition = true
            landingWindow.close()
            showSettings()
        case .overlay:
            didCompleteFirstRunTransition = true
            landingWindow.close()
            NSApplication.shared.setActivationPolicy(.accessory)
            applyRequestedOverlayVisibility()
        case .recovery:
            didCompleteFirstRunTransition = true
            landingWindow.close()
            showSettings()
        }
    }

    func showSettings() {
        NSApplication.shared.setActivationPolicy(.regular)
        settingsWindow.show()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func showGroupSettings() {
        model.activeSettingsPage = .groups
        showSettings()
    }

    private func showStore() {
        model.activeSettingsPage = .store
        showSettings()
    }

    func handleOpenURL(_ url: URL) -> Bool {
        return false
    }

    private func settingsDidClose() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    private func toggleOverlay() {
        setOverlayVisible(!model.overlayVisible)
    }

    private func focusMessageField() {
        if !model.overlayVisible { setOverlayVisible(true) }
        overlayWindows.focusMessageField()
    }

    private func markActiveRoomRead() {
        guard let roomID = model.activeRoom?.id else { return }
        model.markRoomRead(roomID)
        refreshStatusItem()
    }

    private func setOverlayVisible(_ visible: Bool) {
        model.setOverlayVisibility(OverlayVisibility(isVisible: visible))
        applyRequestedOverlayVisibility()
        refreshStatusItem()
        persistPreferences()
    }

    func applyRequestedOverlayVisibility() {
        overlayWindows.setVisible(OverlayRevealPolicy.isVisible(
            requested: model.preferences.overlayVisible,
            onboardingComplete: model.preferences.onboardingComplete,
            backendState: backendBootstrapState
        ))
    }

    private func setOverlayRegion(_ preference: OverlayRegionPreference) {
        overlayWindows.setRegionPreference(preference)
        persistPreferences()
    }

    private func setShowOfflineMembers(_ visible: Bool) {
        model.preferences.showOfflineMembers = visible
        overlayWindows.refreshThrowHotspots()
        persistPreferences()
    }

    private func setRequiresRightClickToThrow(_ required: Bool) {
        model.preferences.requiresRightClickToThrow = required
        overlayWindows.throwInteractionPreferenceChanged()
        persistPreferences()
    }

    private func setQuietMode(_ enabled: Bool) {
        model.preferences.quietModeEnabled = enabled
        if enabled { model.clearBubbles() }
        refreshStatusItem()
        persistPreferences()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(enabled)
            model.launchAtLogin = launchAtLoginController.isEnabled
            model.preferences.launchAtLogin = model.launchAtLogin
            model.errorMessage = nil
            refreshStatusItem()
            persistPreferences()
        } catch {
            model.launchAtLogin = launchAtLoginController.isEnabled
            model.errorMessage = "로그인 자동 실행을 변경하지 못했습니다: \(error.localizedDescription)"
            refreshStatusItem()
        }
    }

    private func copyInviteCode(roomID: UUID) async -> Bool {
        guard model.rooms.first(where: { $0.id == roomID })?.inviteCodeReady == true else {
            model.dismissSuccess()
            model.errorMessage = "이 그룹의 이전 초대 코드는 폐기됐습니다. 방장이 새 코드를 발급해야 합니다."
            return false
        }
        guard let backend else {
            model.dismissSuccess()
            model.errorMessage = "초대 코드를 읽을 서버 구성이 없습니다."
            return false
        }
        do {
            guard let inviteCode = try await backend.storedInviteCode(roomID: roomID),
                  !inviteCode.isEmpty
            else {
                model.dismissSuccess()
                model.errorMessage = "이 기기에 이 그룹의 초대 코드 원문이 없습니다. 보안상 데이터베이스의 해시에서는 복구할 수 없습니다."
                return false
            }
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(inviteCode, forType: .string) else {
                model.dismissSuccess()
                model.errorMessage = "초대 코드를 클립보드에 복사하지 못했습니다."
                return false
            }
            model.errorMessage = nil
            model.dismissSuccess()
            return true
        } catch {
            model.dismissSuccess()
            model.errorMessage = "초대 코드를 읽지 못했습니다: \(error.localizedDescription)"
            return false
        }
    }

    private func rotateInviteCode(roomID: UUID) {
        guard let backend else { return }
        runMutation(successMessage: "새 초대 코드를 발급했습니다.") {
            let created = try await backend.rotateInviteCode(roomID: roomID)
            self.model.lastCreatedInviteCode = created.inviteCode
            if !created.storedInKeychain {
                self.model.errorMessage = "새 코드는 발급됐지만 키체인에 저장하지 못했습니다. 지금 표시된 코드를 따로 보관해 주세요."
            }
        }
    }

    func refreshStatusItem() {
        statusItemController.update(
            overlayVisible: model.overlayVisible,
            rooms: model.rooms,
            activeRoomID: model.activeRoom?.id,
            unreadCounts: model.unreadCounts,
            quietModeEnabled: model.preferences.quietModeEnabled,
            launchAtLogin: model.launchAtLogin
        )
    }

    func persistPreferences() {
        preferencesStore.save(model.preferences)
    }

    private func makeHistoryWindow() -> HistoryWindowController {
        HistoryWindowController(
            model: model,
            loadPage: { [weak self] roomID, cursor, pageSize in
                guard let backend = self?.backend else {
                    throw SideyBackendError.realtimeUnavailable
                }
                return try await backend.historyPage(
                    roomID: roomID,
                    before: cursor,
                    pageSize: pageSize
                )
            }
        )
    }

    private func showHistory() {
        markActiveRoomRead()
        NSApplication.shared.setActivationPolicy(.regular)
        historyWindow.show()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

}
