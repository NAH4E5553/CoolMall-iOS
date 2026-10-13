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

@MainActor
struct HomeBannerCarouselView: View {
    let banners: [HomeBanner]
    let imagePipeline: MallImagePipeline?
    let isActive: Bool
    @State private var selection = HomeBannerSelection()

    private var ids: [Int64] { banners.map(\.id) }
    private var currentID: Int64? { selection.currentID(in: ids) }
    private var currentIndex: Int { ids.firstIndex(of: currentID ?? 0) ?? 0 }

    var body: some View {
        if !banners.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("轮播").font(.headline)
                    .accessibilityIdentifier("home.section.banner.title")
                Color.clear.aspectRatio(2, contentMode: .fit)
                    .overlay {
                        GeometryReader { geometry in
                            TabView(selection: pagerSelection) {
                                ForEach(banners, id: \.id) { banner in
                                    bannerPage(banner, size: geometry.size)
                                        .tag(banner.id)
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: .never))
                        }
                    }
                if banners.count > 1 {
                    Text("第\(currentIndex + 1)张，共\(banners.count)张")
                        .font(.body)
                        .accessibilityIdentifier("home.banner.page")
                    HStack {
                        Button("上一张") { move(offset: -1) }
                            .disabled(selection.adjacentID(offset: -1, in: ids) == nil)
                            .accessibilityIdentifier("home.banner.previous")
                        Spacer(minLength: 8)
                        Button("下一张") { move(offset: 1) }
                            .disabled(selection.adjacentID(offset: 1, in: ids) == nil)
                            .accessibilityIdentifier("home.banner.next")
                    }
                    .buttonStyle(.bordered)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: ids, initial: true) { _, newIDs in
                selection.reconcile(with: newIDs)
            }
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
                .accessibilityIdentifier("home.banner.current.\(banner.id)")
                .accessibilityHidden(banner.id != currentID)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

#if DEBUG
    #Preview("手动轮播 · 深色特大字体") {
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
