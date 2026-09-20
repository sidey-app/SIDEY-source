import SwiftUI

struct StoreProductDetailSheet: View {
    let productState: CommerceProductState
    var relatedProductState: CommerceProductState? = nil
    var isPurchaseInProgress = false
    let actions: SettingsActions
    var availability: StoreAvailability = .appStore
    let onClose: () -> Void
    @State private var playsPreviewSound = true
    @State private var contentHeight: CGFloat = 640

    var displaysCommerceAction: Bool { availability.unavailableDetailMessage == nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(productState.product.displayName).font(.title2.bold())
                if productState.product.kind != .character {
                    Text(productState.product.description)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                StorePreviewStage(product: productState.product,
                    onCharacterImpact: { object, time in
                        if playsPreviewSound { actions.onCharacterImpact(object, time) }
                    }, onStopCharacterSounds: actions.onStopCharacterSounds)
                    .overlay(alignment: .topLeading) {
                        if productState.product.characterID == PixelCharacterCatalog.pixelTreeID {
                            Text("나무를 우클릭하면 멈추고, 다시 우클릭하면 걸어요.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.trailing, 60).padding(12)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if productState.product.kind != .bubble {
                            Button(playsPreviewSound ? "미리보기 소리 끄기" : "미리보기 소리 켜기",
                                   systemImage: playsPreviewSound ? "speaker.wave.2.fill" : "speaker.slash.fill") {
                                playsPreviewSound.toggle()
                                if !playsPreviewSound { actions.onStopCharacterSounds() }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.bordered)
                            .help(playsPreviewSound ? "미리보기 소리 끄기" : "미리보기 소리 켜기")
                            .padding(12)
                        }
                    }
                HStack(alignment: .top, spacing: 12) {
                    StoreDetailPurchaseCard(state: productState, actions: actions,
                        availability: availability, purchaseInProgress: isPurchaseInProgress,
                        showsDescription: productState.product.kind == .character)
                    if let relatedProductState {
                        StoreDetailPurchaseCard(state: relatedProductState, actions: actions,
                            availability: availability, purchaseInProgress: isPurchaseInProgress,
                            showsDescription: true)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 24)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if height > 0 { contentHeight = height }
            }
        }
        .frame(width: 600, height: min(contentHeight, 720))
        .overlay(alignment: .topTrailing) {
            Button("닫기", systemImage: "xmark", action: onClose)
                .labelStyle(.iconOnly).buttonStyle(.plain).padding(12)
                .accessibilityLabel("상품 상세 닫기")
        }
        .onDisappear { actions.onStopCharacterSounds() }
    }
}

private struct StoreDetailPurchaseCard: View {
    let state: CommerceProductState
    let actions: SettingsActions
    let availability: StoreAvailability
    let purchaseInProgress: Bool
    var showsDescription = false

    private var kindLabel: String {
        state.product.isKeepsake ? "애착 물건" : state.product.kind.title
    }
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(kindLabel).font(.caption.weight(.medium))
                Spacer(minLength: 2)
                if state.product.isKeepsake {
                    Text("별도 판매").font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                }
            }
            .frame(height: 22)
            StoreProductPreview(product: state.product, pointSize: 64).frame(height: 64)
            Text(state.product.displayName).font(.callout.weight(.semibold))
                .lineLimit(2, reservesSpace: true).multilineTextAlignment(.center)
            if showsDescription {
                Text(state.product.storeDescription)
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            purchaseAction
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.09)))
    }
    @ViewBuilder private var purchaseAction: some View {
        if let message = availability.unavailableDetailMessage {
            Text(message).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 30)
        } else if state.isWorking {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 30)
                .accessibilityLabel("\(state.product.displayName) 처리 중")
        } else if state.purchaseState == .owned {
            Text(state.isEquipped ? "사용 중" : "보유 중")
                .font(.callout.weight(.medium)).frame(maxWidth: .infinity, minHeight: 30)
        } else if case .error = state.purchaseState {
            Button("상태 다시 확인") { actions.onRefreshCommerceState(state.id) }
                .disabled(purchaseInProgress)
        } else if state.purchaseState == .unavailable {
            VStack(spacing: 6) {
                Text("이 상품은 아직 구매할 수 없어요.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("상태 다시 확인") { actions.onRefreshCommerceState(state.id) }
                    .disabled(purchaseInProgress)
            }
            .frame(maxWidth: .infinity, minHeight: 30)
        } else if availability.usesAppStore && state.localizedPrice == nil {
            VStack(spacing: 6) {
                Text(state.priceLoadState == .loading
                     ? "가격을 불러오는 중이에요" : "App Store 가격을 확인할 수 없어요")
                    .font(.caption).foregroundStyle(.secondary)
                if state.priceLoadState != .loading {
                    Button("가격 다시 확인") { actions.onRefreshCommerceState(state.id) }
                        .disabled(purchaseInProgress)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 30)
        } else {
            Button {
                actions.onPurchase(state.id)
            } label: {
                Text("\(kindLabel) · \(state.formattedPrice) 구매")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(purchaseInProgress || (availability.usesAppStore && state.localizedPrice == nil))
            .accessibilityLabel("\(state.product.displayName), \(state.formattedPrice) 구매")
        }
    }
}
