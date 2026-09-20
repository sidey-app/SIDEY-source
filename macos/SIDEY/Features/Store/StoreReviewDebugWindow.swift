#if DEBUG
import AppKit
import SpriteKit
import SwiftUI

/// Runs the real detail view with explicit review-only state. Never contacts commerce services.
@MainActor
final class StoreReviewDebugWindow: NSWindowController {
    private let review = StoreReviewSelection()
    private var exportTask: Task<Void, Never>?
    init() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 620, height: 800),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Sidey-dev · 상점 검토 · 실제 결제 없음"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: StoreReviewDebugView(review: review) { [weak window] size in
            guard let window, abs(window.contentLayoutRect.height - size.height) > 1 else { return }
            window.setContentSize(size)
        }.preferredColorScheme(.light))
        window.center()
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--store-review-output"), args.indices.contains(i + 1) {
            let directory = URL(fileURLWithPath: args[i + 1], isDirectory: true)
            exportTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    for product in CommerceCatalog.products where product.kind == .character || product.isKeepsake {
                        review.selectedID = product.id
                        try await Task.sleep(for: .seconds(1.5))
                        try capture(to: directory.appendingPathComponent(product.appStoreProductID + ".png"))
                    }
                    review.selectedID = CommerceProduct.pig.id
                } catch { window.title = "상점 검토 · 캡처 실패: \(error.localizedDescription)" }
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func capture(to url: URL) throws {
        guard let view = window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        // Metal-backed SpriteKit views need their own native renderer snapshot.
        let image = NSImage(size: view.bounds.size)
        image.lockFocus()
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        view.bounds.fill()
        rep.draw(in: view.bounds, from: .zero, operation: .sourceOver, fraction: 1,
                 respectFlipped: false, hints: nil)
        func drawScenes(_ child: NSView) {
            if let sk = child as? SKView, let scene = sk.scene,
               let texture = sk.texture(from: scene) {
                var frame = sk.convert(sk.bounds, to: view)
                if view.isFlipped { frame.origin.y = view.bounds.height - frame.maxY }
                NSImage(cgImage: texture.cgImage(), size: sk.bounds.size).draw(in: frame)
            }
            child.subviews.forEach(drawScenes)
        }
        drawScenes(view)
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try png.write(to: url, options: .atomic)
    }
    deinit { exportTask?.cancel() }
}

@MainActor
private final class StoreReviewSelection: ObservableObject {
    @Published var selectedID = CommerceProduct.pig.id
    @Published var ownership = 0
    @Published var notice = ""
    let audio = CharacterImpactAudio()
    func state(_ product: CommerceProduct) -> CommerceProductState {
        let owns = ownership == 3 || (ownership == 1 && product.kind == .character)
            || (ownership == 2 && product.isKeepsake)
        let price = CommerceCatalog.definition(id: product.id)?.appStorePrice ?? product.amountKRW
        return CommerceProductState(product: product, purchaseState: owns ? .owned : .available,
            isWorking: false, localizedPrice: "\(price.formatted())원")
    }
    var actions: SettingsActions {
        var actions = SettingsActions.empty
        actions.onPurchase = { [weak self] _ in self?.notice = "검토용 화면에서는 실제 결제를 진행하지 않아요." }
        actions.onCharacterImpact = { [weak self] id, time in self?.audio.play(objectID: id, at: time) }
        actions.onStopCharacterSounds = { [weak self] in self?.audio.stopAll() }
        return actions
    }
}

private struct StoreReviewDebugView: View {
    @ObservedObject var review: StoreReviewSelection
    let onContentSizeChanged: (CGSize) -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("상품", selection: $review.selectedID) {
                    ForEach(CommerceCatalog.products, id: \.id) { Text($0.displayName).tag($0.id) }
                }.frame(width: 270)
                Picker("보유", selection: $review.ownership) {
                    Text("미보유").tag(0); Text("캐릭터만").tag(1)
                    Text("물건만").tag(2); Text("둘 다").tag(3)
                }.frame(width: 150)
            }.padding(12)
            if !review.notice.isEmpty { Text(review.notice).font(.caption) }
            Divider()
            if let product = CommerceCatalog.product(id: review.selectedID) {
                StoreProductDetailSheet(productState: review.state(product),
                    relatedProductState: CommerceCatalog.keepsake(for: product.id).map { review.state($0) },
                    actions: review.actions, availability: .appStore,
                    onClose: { NSApp.keyWindow?.close() })
                    .id(product.id)
            }
        }
        .frame(width: 620)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onContentSizeChanged($0) }
    }
}
#endif
