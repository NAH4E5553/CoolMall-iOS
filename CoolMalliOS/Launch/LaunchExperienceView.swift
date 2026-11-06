import SwiftUI

/// Scene-local presentation only; RootView keeps its identity and loads underneath.
/// The structured task ends on completion, interruption, or removal. No launch flag is persisted.
@MainActor
struct LaunchExperienceView: View {
    private enum Phase { case waiting, lifted, settled, finished }

    let dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = Phase.waiting

    var body: some View {
        ZStack {
            RootView(dependencies: dependencies, isLaunching: phase != .finished)
                .allowsHitTesting(phase == .finished)
                .accessibilityHidden(phase != .finished)

            if phase != .finished {
                LaunchArtworkView(
                    isRevealed: phase != .waiting, isLifted: phase == .lifted,
                    reduceMotion: reduceMotion
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, phase == .waiting else { return }
            do {
                try Task.checkCancellation()
                withAnimation(
                    reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.42)
                ) {
                    phase = .lifted
                }
                try await Task.sleep(for: .milliseconds(420))
                try Task.checkCancellation()
                guard phase == .lifted else { return }
                withAnimation(
                    reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.95, bounce: 0.38)
                ) {
                    phase = .settled
                }
                try await Task.sleep(for: .milliseconds(1_100))
                try Task.checkCancellation()
                guard phase == .settled else { return }
                finish(animated: true)
            } catch is CancellationError {
                finish(animated: false)
            } catch {
                // Presentation must never prevent entry to the app.
                finish(animated: false)
            }
        }
        .onChange(of: scenePhase) { _, value in
            if value == .background { finish(animated: false) }
        }
    }

    private func finish(animated: Bool) {
        guard phase != .finished else { return }
        withAnimation(animated ? .easeOut(duration: 0.3) : nil) {
            phase = .finished
        }
    }
}

/// Local artwork and typography stay separate so the finished composition can be previewed.
@MainActor
private struct LaunchArtworkView: View {
    let isRevealed: Bool
    let isLifted: Bool
    let reduceMotion: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { Color(red: 0.39, green: 0.38, blue: 1) }
    private var background: Color { Color("LaunchBackground") }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                background.ignoresSafeArea()

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [accent.opacity(0.3), accent.opacity(0.09), .clear],
                                center: .center, startRadius: 0, endRadius: 145
                            )
                        )
                        .frame(width: 300, height: 300)
                        .scaleEffect(!reduceMotion && isLifted ? 1.35 : 1)
                        .opacity(isRevealed ? 1 : 0.75)

                    if !reduceMotion {
                        Circle()
                            .stroke(accent.opacity(0.24), lineWidth: 1.5)
                            .frame(width: 210, height: 210)
                            .scaleEffect(isRevealed ? 1.6 : 0.65)
                            .opacity(isLifted ? 0.65 : 0)
                            .animation(.easeOut(duration: 0.8), value: isRevealed)
                    }

                    Ellipse()
                        .fill(accent.opacity(colorScheme == .dark ? 0.2 : 0.13))
                        .frame(width: 92, height: 16)
                        .scaleEffect(x: !reduceMotion && isLifted ? 0.62 : 1, y: 1)
                        .blur(radius: 11)
                        .offset(y: 83)
                        .opacity(isLifted ? 0.35 : 0.75)

                    Image("LaunchBag")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 176, height: 176)
                        .scaleEffect(!reduceMotion && isLifted ? 1.26 : 1)
                        .rotationEffect(.degrees(!reduceMotion && isLifted ? -14 : 0))
                        .rotation3DEffect(
                            .degrees(!reduceMotion && isLifted ? 16 : 0),
                            axis: (x: 0, y: 1, z: 0), perspective: 0.35
                        )
                        .offset(y: !reduceMotion && isLifted ? -58 : 0)
                }
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.43)
                .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("青商城")
                        .font(.title2.weight(.semibold))
                        .tracking(4)
                        .foregroundStyle(.primary)
                        .opacity(isRevealed ? 1 : 0)
                        .offset(y: !reduceMotion && !isRevealed ? 16 : 0)
                        .animation(
                            .easeOut(duration: 0.45).delay(0.14), value: isRevealed)
                    Text("COOLMALL")
                        .font(.caption2.weight(.medium))
                        .tracking(3.5)
                        .foregroundStyle(.secondary)
                        .opacity(isRevealed ? 1 : 0)
                        .offset(y: !reduceMotion && !isRevealed ? 12 : 0)
                        .animation(
                            .easeOut(duration: 0.45).delay(0.28), value: isRevealed)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("青商城，正在启动")
        .accessibilityIdentifier("launch.brand")
    }
}

#Preview("启动页 · 浅色") {
    LaunchArtworkView(isRevealed: true, isLifted: false, reduceMotion: false)
}

#Preview("启动页 · 深色 / 减少动态效果") {
    LaunchArtworkView(isRevealed: true, isLifted: false, reduceMotion: true)
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("首帧立即显示品牌") {
    LaunchArtworkView(isRevealed: false, isLifted: false, reduceMotion: false)
}
