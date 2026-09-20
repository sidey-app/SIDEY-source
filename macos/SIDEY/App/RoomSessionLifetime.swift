import Foundation

@MainActor
final class RoomSessionLifetime {
    var switchPipeline: RoomSwitchPipeline!
    var bootstrapTask: Task<Void, Never>?
    var eventTask: Task<Void, Never>?
    var bubbleExpiryTask: Task<Void, Never>?
    var pulseCooldown = CharacterPulseCooldown()
    var throwCooldown = CharacterThrowCooldown()

    func cancel() {
        bootstrapTask?.cancel()
        eventTask?.cancel()
        bubbleExpiryTask?.cancel()
        bootstrapTask = nil
        // The stream consumer clears eventTask only after cancellation has drained.
        bubbleExpiryTask = nil
        switchPipeline?.cancel()
        pulseCooldown = CharacterPulseCooldown()
        throwCooldown = CharacterThrowCooldown()
    }
}
