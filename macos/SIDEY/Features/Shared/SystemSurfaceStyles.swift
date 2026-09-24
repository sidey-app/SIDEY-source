import SwiftUI

extension View {
    /// Keep Liquid Glass on macOS 26 and a readable material surface on macOS 15.
    @ViewBuilder
    func sideyGlassSurface<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay {
                    shape.stroke(.primary.opacity(0.12), lineWidth: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        }
    }

    @ViewBuilder
    func sideyProminentButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}
