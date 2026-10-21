import MallCore
import MallImages
import SwiftUI

/// Local display selection only; the snapshot remains HomeViewModel's read-only input.
/// Every read and write is checked against the CURRENT IDs, including delayed pager callbacks.
struct HomeBannerSelection {
    private(set) var selectedID: Int64?
    private var validIDs: [Int64] = []

    func currentID(in ids: [Int64]) -> Int64? {
        if let selectedID, ids.contains(selectedID) { return selectedID }
        return ids.first
    }

    mutating func reconcile(with ids: [Int64]) {
        selectedID = currentID(in: ids)
        validIDs = ids
    }

    mutating func select(_ id: Int64) {
        guard validIDs.contains(id) else { return }
        selectedID = id
    }

    func adjacentID(offset: Int, in ids: [Int64]) -> Int64? {
        guard let current = currentID(in: ids), let index = ids.firstIndex(of: current) else {
            return nil
        }
        let next = index + offset
        guard ids.indices.contains(next) else { return nil }
        return ids[next]
    }
}

/// The complete autoplay gate as pure inputs. The view supplies its own state
/// plus the scene and assistive environments, so every pause reason stays
/// enumerable and unit-testable without a live scene or real system settings.
struct HomeBannerAutoplayGate {
    var bannerCount: Int
    var allowsAutoplay = true
    var isHomeActive = true
    var isSceneActive = true
    var reducesMotion = false
    var isVoiceOverRunning = false
    var isDragging = false
    var bannerFrame: CGRect = .zero
    var viewport: CGRect = .zero

    var isEligible: Bool {
        let intersection = bannerFrame.intersection(viewport)
        return bannerCount > 1 && allowsAutoplay && isHomeActive && isSceneActive
            && !reducesMotion && !isVoiceOverRunning && !isDragging
            && !intersection.isNull && intersection.width > 0 && intersection.height > 0
    }
}

/// Deadline bookkeeping for the single autoplay task. Generation tokens reject
/// stale wakes, including any wake surviving a pause/resume cycle; consuming
/// the deadline clears it, so a repeated wake can never advance twice.
struct HomeBannerAutoplay {
    private(set) var generation: UInt64 = 0
    private(set) var deadline: ContinuousClock.Instant?

    mutating func restart(at now: ContinuousClock.Instant, eligible: Bool) -> UInt64 {
        generation &+= 1
        deadline = eligible ? now.advanced(by: .seconds(5)) : nil
        return generation
    }

    mutating func consume(_ token: UInt64, at now: ContinuousClock.Instant) -> Bool {
        guard token == generation, let deadline, now >= deadline else { return false }
        self.deadline = nil
        return true
    }
}

@MainActor
struct HomeBannerCarouselView: View {
    let banners: [HomeBanner]
    let imagePipeline: MallImagePipeline?
    let isActive: Bool
    var allowsAutoplay = true
    var visibleViewport = CGRect.zero
    /// Any ACTIVE user drag on the home scroll (the entry's existing
    /// scroll-wide gesture) pauses playback — including banner swipes that
    /// do not change the page and system-cancelled drags. A local pager
    /// gesture is deliberately NOT used: it breaks pull-to-refresh.
    var isUserDragging = false
    var onUnavailableAction: () -> Void = {}
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var selection = HomeBannerSelection()
    @State private var autoplay = HomeBannerAutoplay()
    @State private var bannerFrame = CGRect.zero
    @State private var interaction: UInt64 = 0

    private var ids: [Int64] { banners.map(\.id) }
    private var currentID: Int64? { selection.currentID(in: ids) }
    private var currentIndex: Int { ids.firstIndex(of: currentID ?? 0) ?? 0 }
    private var canAutoplay: Bool {
        HomeBannerAutoplayGate(
            bannerCount: banners.count, allowsAutoplay: allowsAutoplay,
            isHomeActive: isActive, isSceneActive: scenePhase == .active,
            reducesMotion: reduceMotion, isVoiceOverRunning: voiceOver,
            isDragging: isUserDragging, bannerFrame: bannerFrame, viewport: visibleViewport
        ).isEligible
    }
    private struct PlaybackKey: Equatable {
        let ids: [Int64]
        let currentID: Int64?
        let eligible: Bool
        let interaction: UInt64
    }
    private var playbackKey: PlaybackKey {
        PlaybackKey(ids: ids, currentID: currentID, eligible: canAutoplay, interaction: interaction)
    }

    var body: some View {
        if !banners.isEmpty {
            Color.clear.aspectRatio(2, contentMode: .fit)
                .overlay {
                    GeometryReader { geometry in
                        TabView(selection: pagerSelection) {
                            ForEach(banners, id: \.id) { banner in
                                bannerPage(banner, size: geometry.size).tag(banner.id)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .overlay(alignment: .bottom) { paginationDots }
                    }
                }
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    bannerFrame = $0
                }
                .onChange(of: ids, initial: true) { _, newIDs in
                    selection.reconcile(with: newIDs)
                }
                .task(id: playbackKey) { @MainActor in
                    let clock = ContinuousClock()
                    let token = autoplay.restart(at: clock.now, eligible: canAutoplay)
                    guard let deadline = autoplay.deadline else { return }
                    do { try await clock.sleep(until: deadline) } catch { return }
                    guard !Task.isCancelled, canAutoplay,
                        autoplay.consume(token, at: clock.now), !ids.isEmpty
                    else { return }
                    // No copied sentinel pages; the last-to-first wrap may visibly reverse.
                    let next = ids[(currentIndex + 1) % ids.count]
                    withAnimation { selection.select(next) }
                }
        }
    }

    /// In-image pagination dots replace the removed below-image controls row.
    /// Hit-test transparent; only the page summary is exposed semantically.
    @ViewBuilder private var paginationDots: some View {
        if ids.count > 1 {
            HStack(spacing: 6) {
                ForEach(ids, id: \.self) { id in
                    Circle().fill(.white.opacity(id == currentID ? 1 : 0.45))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(6)
            .background(.black.opacity(0.25), in: Capsule())
            .padding(.bottom, 8)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("轮播分页")
            .accessibilityValue("第\(currentIndex + 1)页，共\(ids.count)页")
            .accessibilityIdentifier("home.banner.indicators")
        }
    }

    private var pagerSelection: Binding<Int64> {
        Binding(
            get: { currentID ?? 0 },
            set: { selection.select($0) })
    }

    private func move(offset: Int) {
        guard let id = selection.adjacentID(offset: offset, in: ids) else { return }
        selection.select(id)
    }

    private func bannerPage(_ banner: HomeBanner, size: CGSize) -> some View {
        ZStack {
            if banner.id != currentID {
                Rectangle().fill(.quaternary).accessibilityHidden(true)
            } else if let imagePipeline {
                RemoteImage(
                    url: banner.imageURL, targetSize: size, pipeline: imagePipeline,
                    isEnabled: isActive && banner.id == currentID)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                    .accessibilityIdentifier("home.image.unavailable")
                    .accessibilityHidden(true)
            }
            // A separate leaf preserves RemoteImage's state identifiers for testing.
            Color.clear.accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    banner.description.isEmpty
                        ? "轮播图，第\(currentIndex + 1)张，共\(banners.count)张" : banner.description
                )
                .accessibilityValue("第\(currentIndex + 1)张，共\(banners.count)张")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: move(offset: 1)
                    case .decrement: move(offset: -1)
                    @unknown default: break
                    }
                    interaction &+= 1
                }
                .accessibilityIdentifier("home.banner.current.\(banner.id)")
                .accessibilityHidden(banner.id != currentID)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onUnavailableAction)
        .accessibilityAction { onUnavailableAction() }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

#if DEBUG
    #Preview("轮播 · 深色特大字体") {
        ScrollView {
            HomeBannerCarouselView(
                banners: (1...3).map {
                    HomeBanner(id: Int64($0), description: "预览轮播\($0)", imageURL: nil)
                }, imagePipeline: nil, isActive: true
            )
            .padding(16)
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
    }
#endif
