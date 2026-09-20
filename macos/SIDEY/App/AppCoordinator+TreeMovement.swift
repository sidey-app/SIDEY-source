import Foundation

extension AppCoordinator {
    @discardableResult
    func cancelTreeMovementRequests() -> Task<Void, Never>? {
        let previous = treeMovementTask
        previous?.cancel()
        treeMovementTask = nil
        model.treeMovement.cancelPending()
        return previous
    }

    func toggleTreeMovement() {
        guard !model.accountOperationInProgress,
              model.selectedCharacterID == PixelCharacterCatalog.pixelTreeID,
              let userID = model.currentUserID,
              let value = model.treeMovement.confirmed[userID] else { return }
        guard value.revision != nil else {
            // Older servers have no profile field/RPC. Keep the existing local control until deployment.
            model.preferences.treeMovementPaused.toggle()
            persistPreferences()
            return
        }
        saveTreeMovement(userID: userID, paused: !model.treeMovement.effectivePaused(
            userID: userID, currentUserID: model.currentUserID,
            legacyPaused: model.preferences.treeMovementPaused))
    }

    func migrateTreeMovementIfNeeded() {
        guard model.hasProfile, let userID = model.currentUserID else { return }
        saveTreeMovement(userID: userID, paused: model.preferences.treeMovementPaused, migrating: true)
    }

    private func saveTreeMovement(userID: UUID, paused: Bool, migrating: Bool = false) {
        guard !model.accountOperationInProgress,
              let backend,
              let request = model.treeMovement.begin(userID: userID, paused: paused, migrating: migrating)
        else { return }
        treeMovementTask?.cancel()
        treeMovementTask = Task { [weak self] in
            guard let self, !Task.isCancelled, model.currentUserID == request.userID,
                  model.treeMovement.pending == request else { return }
            do {
                let profile = try await backend.setTreeMovementPaused(
                    request.paused, expectedRevision: request.expectedRevision, expectedUserID: request.userID)
                guard !Task.isCancelled, model.currentUserID == request.userID,
                      model.treeMovement.finish(request) else { return }
                // Only this field was mutated; a delayed response must not overwrite nickname/equipment.
                guard profile.id == request.userID else { return }
                model.applyTreeMovement(profile: profile)
            } catch {
                guard !Task.isCancelled, model.currentUserID == request.userID,
                      model.treeMovement.finish(request) else { return }
                if !migrating { model.errorMessage = "나무 움직임을 저장하지 못했습니다. 다시 시도해 주세요." }
            }
        }
    }
}
