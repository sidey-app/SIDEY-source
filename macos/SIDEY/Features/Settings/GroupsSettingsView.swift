import SwiftUI

struct GroupsSettingsView: View {
    @Bindable var model: AppModel
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            SettingsSection(
                title: "groups.current.title",
                verbatimSubtitle: L10n.format(
                    "groups.current.subtitle",
                    ProductLimits.maximumRoomMembers
                ),
                systemImage: "person.2"
            ) {
                if model.rooms.isEmpty {
                    ContentUnavailableView(
                        "groups.current.empty.title",
                        systemImage: "person.2",
                        description: Text("groups.current.empty.description")
                    )
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    ForEach(model.rooms) { room in
                        RoomRow(
                            room: room,
                            currentUserID: model.currentUserID,
                            isActive: room.id == model.activeRoom?.id,
                            mutationsDisabled: model.groupMutationsDisabled,
                            selectionDisabled: model.isWorking || !model.groupOperation.allowsRoomSelection,
                            isSwitchingTarget: model.groupOperation.isSwitching(to: room.id),
                            onSelect: { actions.onSelectRoom(room.id) },
                            onCopyInviteCode: { await actions.onCopyInviteCode(room.id) },
                            onRotateInviteCode: { actions.onRotateInviteCode(room.id) },
                            onRename: { name in actions.onRenameRoom(room.id, name) },
                            onRemoveMember: { userID in
                                actions.onRemoveRoomMember(room.id, userID)
                            },
                            onLeave: { actions.onLeaveRoom(room.id) },
                            onDelete: { actions.onDeleteRoom(room.id) }
                        )
                        if room.id != model.rooms.last?.id { Divider() }
                    }
                }
            }

            SettingsSection(
                title: "groups.create.title",
                subtitle: "groups.create.subtitle",
                systemImage: "plus.circle"
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("groups.create.name.title")
                        .font(.headline)
                    Text("groups.create.name.description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    TextField("groups.create.name.placeholder", text: $model.newRoomName)
                        .textFieldStyle(.roundedBorder)
                    Button(action: actions.onCreateRoom) {
                        OperationButtonLabel(
                            title: model.groupOperation.localizedCreateButtonTitle,
                            showsProgress: model.groupOperation == .creating
                        )
                    }
                        .buttonStyle(.glassProminent)
                        .disabled(model.groupMutationsDisabled || !validRoomName || !validNickname)
                }

                if let invite = model.lastCreatedInviteCode {
                    Divider()
                    SettingsControlRow(
                        title: "groups.create.invite_code.title",
                        description: "groups.create.invite_code.description"
                    ) {
                        Text(verbatim: invite)
                            .font(.system(.body, design: .monospaced).bold())
                            .textSelection(.enabled)
                    }
                }
            }

            SettingsSection(
                title: "groups.join.title",
                subtitle: "groups.join.subtitle",
                systemImage: "ticket"
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("groups.join.invite_code.title")
                        .font(.headline)
                    Text("groups.join.invite_code.description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    TextField("groups.join.invite_code.placeholder", text: $model.inviteCode)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: model.inviteCode) { _, value in
                            let uppercased = value.uppercased()
                            if value != uppercased { model.inviteCode = uppercased }
                        }
                    Button(action: actions.onJoinRoom) {
                        OperationButtonLabel(
                            title: model.groupOperation.localizedJoinButtonTitle,
                            showsProgress: model.groupOperation == .joining
                        )
                    }
                        .buttonStyle(.glassProminent)
                        .disabled(model.groupMutationsDisabled || model.inviteCode.trimmingCharacters(in: .whitespaces).isEmpty || !validNickname)
                }
            }
        }
    }

    private var validNickname: Bool {
        model.confirmedNickname.map(ProfileValidator.isValidNickname)
            ?? ProfileValidator.isValidNickname(model.nickname)
    }

    private var validRoomName: Bool {
        RoomNameValidator.isValid(model.newRoomName)
    }
}
struct RoomRow: View {
    let room: Room
    let currentUserID: UUID?
    let isActive: Bool
    let mutationsDisabled: Bool
    let selectionDisabled: Bool
    let isSwitchingTarget: Bool
    let onSelect: () -> Void
    let onCopyInviteCode: () async -> Bool
    let onRotateInviteCode: () -> Void
    let onRename: (String) -> Void
    let onRemoveMember: (UUID) -> Void
    let onLeave: () -> Void
    let onDelete: () -> Void

    @State private var isExpanded = false
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @State private var removalCandidate: RoomMember?
    @State private var showsDeleteConfirmation = false
    @State private var showsLeaveConfirmation = false
    @State private var inviteCopyFeedback = InviteCopyFeedbackState()
    @State private var inviteCopyTask: Task<Void, Never>?
    @State private var inviteCopyResetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            roomHeader
            VStack(alignment: .leading, spacing: 0) {
                if isExpanded {
                    expandedContent
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .clipped()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            isSwitchingTarget ? Color.accentColor.opacity(0.10) : .clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isSwitchingTarget ? Color.accentColor.opacity(0.55) : .clear,
                    lineWidth: 1
                )
        }
        .onChange(of: room.name) { _, newName in
            if !isRenaming { renameDraft = newName }
        }
        .onDisappear {
            inviteCopyTask?.cancel()
            inviteCopyResetTask?.cancel()
            inviteCopyFeedback.cancel()
        }
        .alert(
            removalCandidate.map {
                L10n.format("groups.member.remove.confirmation_title", $0.nickname)
            } ?? L10n.text("groups.member.remove.title"),
            isPresented: Binding(
                get: { removalCandidate != nil },
                set: { if !$0 { removalCandidate = nil } }
            )
        ) {
            Button("common.cancel", role: .cancel) { removalCandidate = nil }
            Button("groups.member.remove.action", role: .destructive) {
                guard let candidate = removalCandidate else { return }
                removalCandidate = nil
                onRemoveMember(candidate.userID)
            }
        } message: {
            Text("groups.member.remove.message")
        }
        .alert(L10n.format("groups.delete.confirmation_title", room.name), isPresented: $showsDeleteConfirmation) {
            Button("common.cancel", role: .cancel) {}
            Button("groups.delete.action", role: .destructive, action: onDelete)
        } message: {
            Text("groups.delete.message")
        }
        .alert(L10n.format("groups.leave.confirmation_title", room.name), isPresented: $showsLeaveConfirmation) {
            Button("common.cancel", role: .cancel) {}
            Button("groups.leave.action", role: .destructive, action: onLeave)
        } message: {
            Text(RoomLeaveConfirmation.resolve(
                room: room,
                currentUserID: currentUserID
            ).localizedMessage)
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if room.members.isEmpty {
                Text("groups.members.empty")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 48)
            } else {
                ForEach(room.members) { member in
                    memberRow(member)
                }
            }

            if RoomManagementPolicy.canManage(room, currentUserID: currentUserID) {
                Divider()
                    .padding(.leading, 48)
                if isRenaming {
                    renameEditor
                } else {
                    managementButtons
                }
            }
            Divider()
                .padding(.leading, 48)
            Button("groups.leave.action", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                showsLeaveConfirmation = true
            }
            .disabled(mutationsDisabled)
            .padding(.leading, 48)
        }
        .padding(.top, 12)
        .padding(.leading, 8)
    }

    private var roomHeader: some View {
        HStack(spacing: 10) {
            Button(action: toggleExpansion) {
                HStack(spacing: 14) {
                    Image(systemName: isActive ? "person.2.fill" : "person.2")
                        .font(.title2)
                        .foregroundStyle(isActive ? .mint : .secondary)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: room.name).font(.headline)
                        Text(verbatim: roomSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isActive {
                        Label("groups.active", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.mint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isActive || isSwitchingTarget {
                Button(action: onSelect) {
                    OperationButtonLabel(
                        title: isSwitchingTarget
                            ? "groups.operation.switching"
                            : "groups.operation.select",
                        showsProgress: isSwitchingTarget
                    )
                }
                .disabled(selectionDisabled || isSwitchingTarget)
            }
            if !room.inviteCodeReady,
               RoomManagementPolicy.canManage(room, currentUserID: currentUserID) {
                Button("groups.invite_code.rotate", systemImage: "arrow.clockwise", action: onRotateInviteCode)
                    .disabled(mutationsDisabled)
                    .help("groups.invite_code.rotate.help")
            } else {
                Button(action: copyInviteCode) {
                    Label {
                        Text(copyButtonTitle)
                    } icon: {
                        Image(systemName: inviteCopyFeedback.showsConfirmation
                              ? "checkmark.circle.fill"
                              : "doc.on.doc")
                    }
                    .foregroundStyle(inviteCopyFeedback.showsConfirmation ? .green : .primary)
                }
                .disabled(mutationsDisabled || !room.inviteCodeReady)
                .help("groups.invite_code.copy.help")
            }

            Button(action: toggleExpansion) {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text(expansionLabel))
            .accessibilityLabel(Text(expansionLabel))
        }
    }

    private var managementButtons: some View {
        HStack(spacing: 8) {
            Button("groups.rename.action", systemImage: "pencil") {
                renameDraft = room.name
                isRenaming = true
            }
            .disabled(mutationsDisabled)
            Button("groups.delete.action", systemImage: "trash", role: .destructive) {
                showsDeleteConfirmation = true
            }
            .disabled(mutationsDisabled)
        }
        .padding(.leading, 48)
    }

    private var roomSummary: String {
        if room.inviteCodeReady {
            return L10n.format(
                "groups.room.summary.invite_ready",
                room.members.count,
                ProductLimits.maximumRoomMembers,
                room.inviteCodeHint
            )
        }
        return L10n.format(
            "groups.room.summary.invite_rotation_required",
            room.members.count,
            ProductLimits.maximumRoomMembers
        )
    }

    private var copyButtonTitle: LocalizedStringResource {
        inviteCopyFeedback.showsConfirmation
            ? "groups.invite_code.copy.complete"
            : "groups.invite_code.copy.action"
    }

    private var expansionLabel: LocalizedStringResource {
        isExpanded ? "groups.collapse" : "groups.expand"
    }

    private func toggleExpansion() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isExpanded.toggle()
        }
    }

    private func copyInviteCode() {
        inviteCopyTask?.cancel()
        inviteCopyTask = Task {
            let succeeded = await onCopyInviteCode()
            guard !Task.isCancelled,
                  let generation = inviteCopyFeedback.recordResult(succeeded)
            else { return }

            inviteCopyResetTask?.cancel()
            inviteCopyResetTask = Task {
                do {
                    try await Task.sleep(for: InviteCopyFeedbackState.confirmationDuration)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                inviteCopyFeedback.clear(generation: generation)
            }
        }
    }

    private var renameEditor: some View {
        HStack(spacing: 8) {
            TextField("groups.rename.placeholder", text: $renameDraft)
                .textFieldStyle(.roundedBorder)
                .onChange(of: renameDraft) { _, value in
                    let limited = RoomNameValidator.limitedDraft(value)
                    if value != limited { renameDraft = limited }
                }
            Button("common.save") {
                let value = renameDraft
                isRenaming = false
                onRename(value)
            }
            .buttonStyle(.borderedProminent)
            .disabled(mutationsDisabled || !RoomNameValidator.isValid(renameDraft))
            Button("common.cancel") {
                renameDraft = room.name
                isRenaming = false
            }
            .disabled(mutationsDisabled)
        }
        .padding(.leading, 48)
    }

    @ViewBuilder
    private func memberRow(_ member: RoomMember) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: PixelCharacterPreviewImage.image(
                for: PixelCharacterCatalog.definition(for: member.characterID)
            ))
            .interpolation(.none)
            .resizable()
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            HStack(spacing: 6) {
                if RoomManagementPolicy.isOwner(member, in: room) {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(Color(red: 0.95, green: 0.68, blue: 0.12))
                        .accessibilityLabel("groups.member.owner")
                }
                Text(verbatim: member.nickname)
                if member.userID == currentUserID {
                    Text("groups.member.me")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            Spacer()
            if RoomManagementPolicy.canRemove(
                member,
                from: room,
                currentUserID: currentUserID
            ) {
                Button("groups.member.remove.action", role: .destructive) {
                    removalCandidate = member
                }
                .disabled(mutationsDisabled)
            }
        }
        .padding(.leading, 48)
    }
}

private extension RoomLeaveConfirmation {
    var localizedMessage: LocalizedStringResource {
        switch self {
        case .member: "groups.leave.message.member"
        case .ownerWithRemainingMembers: "groups.leave.message.owner_transfer"
        case .lastOwner: "groups.leave.message.last_owner"
        }
    }
}

struct OperationButtonLabel: View {
    let title: LocalizedStringResource
    let showsProgress: Bool

    var body: some View {
        HStack(spacing: 7) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            }
            Text(title)
        }
    }
}
