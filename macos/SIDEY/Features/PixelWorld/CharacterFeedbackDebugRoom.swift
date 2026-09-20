#if DEBUG
import AppKit
import SpriteKit

/// A local room using the production scene and audio paths, without a backend or user preferences.
@MainActor
final class CharacterFeedbackDebugRoom: NSWindowController, NSWindowDelegate {
    static let launchArgument = "--character-feedback-room"
    private let actorID = UUID()
    private let friendID = UUID()
    private let roomID = UUID()
    private let audio = CharacterImpactAudio()
    private let spriteView = CharacterFeedbackDebugView(frame: CGRect(x: 20, y: 105, width: 860, height: 290))
    private let throwablePicker = NSPopUpButton(frame: CGRect(x: 90, y: 428, width: 215, height: 30))
    private let characterPicker = NSPopUpButton(frame: CGRect(x: 400, y: 428, width: 185, height: 30))
    private let status = NSTextField(labelWithString: "")
    private var ticker: Timer?
    private var cooldown = CharacterThrowCooldown()
    private var requiresDoubleRightClick = false
    private var throwArmedUntil: TimeInterval = 0
    private lazy var rightClicks = CharacterRightClickCoordinator(
        onSingle: { [weak self] in
            guard let self else { return }
            _ = self.world.toggleTreeMovement(for: self.actorID)
        },
        onDouble: { [weak self] in self?.throwArmedUntil = ProcessInfo.processInfo.systemUptime + 10 }
    )
    private var actorCharacterID: String { PixelCharacterCatalog.all[characterPicker.indexOfSelectedItem].id }
    private let choices = [
        ("기본 말랑공", ""),
        ("조개 · 수달", "clam"), ("돼지고기 · 촵", "pork"), ("작은 나무", "timber"),
        ("눈송이", "throwable_snowflake"), ("야구공", "throwable_baseball"),
        ("왁뿌볼 A", "throwable_wakkuball"), ("두쫀쿠", "throwable_dujjonku"),
        ("테니스공", "tennis_ball"), ("휴지 뭉치", "tissue_ball"),
        ("어묵꼬치", "fish_cake_skewer"), ("잎사귀", "leaf"),
        ("말랑공 A", "patch_soft_ball"), ("파프리카 C", "mini_paprika"),
        ("바나나 B", "banana"), ("모래주머니 C", "dust_bath_pouch"),
        ("별빛 구슬 B", "starlight_orb"), ("하트 B · 팝 한 번", "throwable_bouncy_heart"),
        ("오리 B · 꽥 한 번", "throwable_squeaky_duck"), ("대포 C", "throwable_toy_cannon")
    ]
    private(set) var world: PixelWorldScene!

    init() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 510),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Sidey-dev · 새 캐릭터·투척물 테스트"
        window.isReleasedWhenClosed = false
        window.delegate = self
        let content = window.contentView!
        addLabel("로컬 테스트 방 · 수달·돼지·나무와 투척물", frame: CGRect(x: 24, y: 471, width: 500, height: 25), size: 20, to: content)
        addLabel("투척물", frame: CGRect(x: 24, y: 431, width: 65, height: 22), to: content)
        throwablePicker.addItems(withTitles: choices.map(\.0))
        content.addSubview(throwablePicker)
        addLabel("내 캐릭터", frame: CGRect(x: 315, y: 431, width: 90, height: 22), to: content)
        characterPicker.addItems(withTitles: PixelCharacterCatalog.all.map(\.displayName))
        characterPicker.selectItem(at: PixelCharacterCatalog.all.firstIndex { $0.id == PixelCharacterCatalog.pixelOtterID } ?? 0)
        characterPicker.target = self; characterPicker.action = #selector(changeCharacter)
        content.addSubview(characterPicker)
        let sound = NSButton(checkboxWithTitle: "효과음 ON", target: self, action: #selector(toggleSound(_:)))
        sound.state = .on; sound.frame = CGRect(x: 635, y: 428, width: 150, height: 26)
        content.addSubview(sound)
        let arming = NSButton(checkboxWithTitle: "더블 우클릭 후 던지기", target: self, action: #selector(toggleArming(_:)))
        arming.frame = CGRect(x: 635, y: 399, width: 220, height: 26)
        content.addSubview(arming)
        PixelWorldRendererPolicy.apply(to: spriteView)
        world = PixelWorldScene(size: spriteView.bounds.size, renderingConfiguration: .storePreview(
            initialTrackFractions: [actorID: 0.27], fixedTrackFractions: [friendID: 0.73]))
        world.backgroundColor = NSColor.controlBackgroundColor
        let floor = SKSpriteNode(color: .separatorColor, size: CGSize(width: 860, height: 3))
        floor.position = CGPoint(x: 430, y: 32); floor.zPosition = -10
        world.addChild(floor)
        world.onCharacterImpact = { [weak self] id, time in self?.audio.play(objectID: id, at: time) }
        world.onStopCharacterSounds = { [weak self] in self?.audio.stopAll() }
        spriteView.presentScene(world)
        spriteView.onClick = { [weak self] point in
            guard let self, self.world.memberID(at: point) == self.friendID else { return }
            self.hitFriend()
        }
        spriteView.onRightClick = { [weak self] point, count in
            guard let self, self.world.memberID(at: point) == self.actorID else { return }
            self.rightClicks.handle(clickCount: count)
        }
        content.addSubview(spriteView)
        let hit = NSButton(title: "친구 때리기 (Space)", target: self, action: #selector(hitFriend))
        hit.keyEquivalent = " "; hit.frame = CGRect(x: 22, y: 65, width: 190, height: 30); hit.bezelStyle = .rounded
        content.addSubview(hit)
        let returnHit = NSButton(title: "나도 맞아보기", target: self, action: #selector(hitMe))
        returnHit.frame = CGRect(x: 220, y: 65, width: 150, height: 30); returnHit.bezelStyle = .rounded
        content.addSubview(returnHit)
        let reset = NSButton(title: "초기화", target: self, action: #selector(resetRoom))
        reset.frame = CGRect(x: 380, y: 65, width: 95, height: 30); reset.bezelStyle = .rounded
        content.addSubview(reset)
        status.frame = CGRect(x: 490, y: 69, width: 390, height: 25)
        status.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        content.addSubview(status)
        addLabel("내 나무 우클릭: 정지/걷기 · 더블 우클릭: 던지기 준비 · 콩이 클릭/Space: 던지기 · 실제 방/소유권 변경 없음",
                 frame: CGRect(x: 24, y: 22, width: 860, height: 28), size: 12, to: content)
        applyMembers()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
        refreshStatus()
        window.center()
    }

    isolated deinit { ticker?.invalidate() }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func addLabel(_ value: String, frame: CGRect, size: CGFloat = 13, to view: NSView) {
        let label = NSTextField(labelWithString: value)
        label.frame = frame; label.font = .systemFont(ofSize: size, weight: .medium)
        view.addSubview(label)
    }

    private func applyMembers() {
        world.apply(roomID: roomID, members: [
            PixelWorldMember(id: actorID, nickname: "토리", characterID: actorCharacterID, presence: .online, isTyping: false, isCurrentUser: true),
            PixelWorldMember(id: friendID, nickname: "콩이", characterID: "pixel_hamster",
                             presence: .online, isTyping: false, isCurrentUser: false)
        ], bubbles: [], edge: .bottom, activityFrame: CGRect(x: 0, y: 32, width: 860, height: 258), installationSeed: 77)
    }

    private func throwObject(from actor: UUID, to target: UUID) {
        let now = ProcessInfo.processInfo.systemUptime
        guard (!requiresDoubleRightClick || now < throwArmedUntil),
              !world.stunState.isStunned(actor, at: now), cooldown.accept(actorUserID: actor, uptime: now) else { return }
        world.playLocalPreviewThrow(CharacterThrowEvent(id: UUID(), roomID: roomID, actorUserID: actor,
            targetUserID: target, sourceCharacterID: actor == actorID ? actorCharacterID : "pixel_hamster",
            throwableID: choices[throwablePicker.indexOfSelectedItem].1.isEmpty ? nil : choices[throwablePicker.indexOfSelectedItem].1))
    }

    @objc private func hitFriend() { throwObject(from: actorID, to: friendID) }
    @objc private func hitMe() { throwObject(from: friendID, to: actorID) }
    @objc private func changeCharacter() {
        rightClicks.cancel(); throwArmedUntil = 0
        world.cancelLocalPreviewPlayback()
        throwablePicker.selectItem(at: 0)
        applyMembers()
    }
    @objc private func toggleArming(_ button: NSButton) {
        requiresDoubleRightClick = button.state == .on; throwArmedUntil = 0
    }
    @objc private func toggleSound(_ button: NSButton) {
        audio.isEnabled = button.state == .on
        button.title = audio.isEnabled ? "효과음 ON" : "효과음 OFF"
    }
    @objc private func resetRoom() {
        world.cancelLocalPreviewPlayback(); cooldown = CharacterThrowCooldown(); applyMembers(); refreshStatus()
    }

    private func refreshStatus() {
        let now = ProcessInfo.processInfo.systemUptime
        func state(_ id: UUID) -> String {
            if let start = world.stunState.startedAt[id], now < start + 6 {
                return String(format: "기절 %.1f초", start + 6 - now)
            }
            return "\(world.stunState.recentHitCount(id, at: now))/10"
        }
        status.stringValue = audio.resourceErrors.isEmpty
            ? "콩이 \(state(friendID))  ·  나 \(state(actorID))"
            : "효과음 로드 실패: \(audio.resourceErrors.count)개"
    }

    func windowWillClose(_ notification: Notification) {
        rightClicks.cancel()
        ticker?.invalidate(); ticker = nil
        world.cancelLocalPreviewPlayback(); audio.stopAll()
        spriteView.isPaused = true; spriteView.presentScene(nil)
    }
}

@MainActor
private final class CharacterFeedbackDebugView: SKView {
    var onClick: ((CGPoint) -> Void)?
    var onRightClick: ((CGPoint, Int) -> Void)?
    override func rightMouseDown(with event: NSEvent) {
        guard let scene else { return }
        onRightClick?(scene.convertPoint(fromView: convert(event.locationInWindow, from: nil)), event.clickCount)
    }
    override func mouseDown(with event: NSEvent) {
        guard let scene else { return }
        onClick?(scene.convertPoint(fromView: convert(event.locationInWindow, from: nil)))
    }
}
#endif
