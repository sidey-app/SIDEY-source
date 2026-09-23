import SwiftUI

struct LandingView: View {
    let isRestoringSession: Bool
    let onSkip: () -> Void
    @State private var appeared = false
    @State private var orbit = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.82, green: 0.98, blue: 0.93), .white, Color(red: 0.82, green: 0.90, blue: 1.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(.mint.opacity(0.26))
                .frame(width: 310, height: 310)
                .blur(radius: 18)
                .offset(x: orbit ? 150 : -150, y: orbit ? -80 : 80)
                .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: orbit)

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.58))
                        .frame(width: 124, height: 124)
                        .sideyGlassSurface(in: Capsule())
                    Circle()
                        .stroke(.black.opacity(0.08), lineWidth: 1)
                        .frame(width: 96, height: 96)
                    Text(verbatim: "S")
                        .font(.system(size: 58, weight: .black, design: .rounded))
                        .foregroundStyle(.black.opacity(0.86))
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(index == 1 ? .cyan : .mint)
                            .frame(width: index == 1 ? 10 : 8, height: index == 1 ? 10 : 8)
                            .offset(y: -76)
                            .rotationEffect(.degrees(Double(index * 120) + (orbit ? 360 : 0)))
                    }
                }
                .scaleEffect(appeared ? 1 : 0.72)
                .opacity(appeared ? 1 : 0)
                .animation(.linear(duration: 2.4).repeatForever(autoreverses: false), value: orbit)

                Text(verbatim: "SIDEY")
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .tracking(5)
                    .foregroundStyle(.black.opacity(0.88))
                Text("landing.tagline")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.black.opacity(0.58))
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.black.opacity(0.38))
            }
            .offset(y: appeared ? 0 : 14)
            .animation(.spring(duration: 0.72, bounce: 0.24), value: appeared)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isRestoringSession { onSkip() }
        }
        .onAppear {
            appeared = true
            orbit = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(.isButton)
    }

    private var statusText: LocalizedStringResource {
        isRestoringSession ? "landing.status.restoring" : "landing.status.ready"
    }

    private var accessibilityLabel: LocalizedStringResource {
        isRestoringSession ? "landing.accessibility.restoring" : "landing.accessibility.ready"
    }
}
