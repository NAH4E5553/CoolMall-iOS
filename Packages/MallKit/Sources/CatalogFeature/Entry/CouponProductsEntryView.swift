import Foundation
import MallCore
import MallImages
import SwiftUI

@MainActor public struct CouponProductsEntryView: View {
    @State private var model: CouponProductsViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    private let minimum: Decimal?
    private let pipeline: MallImagePipeline?
    private let isActive: Bool
    private let onOpenProduct: (Int64) -> Void
    public init(
        minimumPriceYuan: Decimal?, loader: any CouponProductsLoading,
        imagePipeline: MallImagePipeline?, isActive: Bool, onOpenProduct: @escaping (Int64) -> Void
    ) {
        _model = State(
            initialValue: CouponProductsViewModel(minimum: minimumPriceYuan, loader: loader))
        minimum = minimumPriceYuan; pipeline = imagePipeline; self.isActive = isActive;
        self.onOpenProduct = onOpenProduct
    }
    private var active: Bool { isActive && scenePhase == .active }
    public var body: some View {
        VStack(spacing: 0) {
            if model.state.failure != nil {
                VStack(spacing: 8) {
                    Text("商品读取失败，请重试").foregroundStyle(.red)
                    Button("重试") { model.retry() }.accessibilityIdentifier("couponProducts.retry")
                }.padding(12).frame(maxWidth: .infinity).background(.background)
            }
            ScrollView {
                LazyVStack(spacing: 12) {
                    Text(
                        minimum.map {
                            "价格从 "
                                + $0.formatted(
                                    .currency(code: "CNY").locale(Locale(identifier: "zh_CN")))
                                + " 起"
                        } ?? "全部价格"
                    )
                    .font(.subheadline).accessibilityIdentifier("couponProducts.minimum")
                    Text("优惠券具体使用范围以使用说明为准").font(.caption).foregroundStyle(.secondary)
                    if !model.state.hasLoaded && model.state.operation != nil {
                        ProgressView("正在读取商品")
                    }
                    if model.state.hasLoaded && model.state.items.isEmpty {
                        ContentUnavailableView(
                            "暂无商品", systemImage: "shippingbox", description: Text("试试重新加载"))
                        Button("重新加载") { model.retry() }.accessibilityIdentifier(
                            "couponProducts.reload")
                    }
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), alignment: .top),
                            count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12
                    ) {
                        ForEach(model.state.items) { item in card(item) }
                    }
                    if model.state.nextPage != nil {
                        VStack(spacing: 8) {
                            if model.state.appendFailure != nil {
                                Text("加载失败，请重试").foregroundStyle(.red).font(.footnote)
                            }
                            if model.state.operation == .append { ProgressView("正在加载") }
                            Button(model.state.appendFailure == nil ? "加载更多" : "重试加载") {
                                model.more()
                            }
                            .disabled(model.state.operation != nil).accessibilityIdentifier(
                                "couponProducts.more")
                        }.padding().task { model.more(automatic: true) }.onDisappear {
                            model.tailExited()
                        }
                    } else if model.state.hasLoaded && !model.state.items.isEmpty {
                        Text("没有更多商品了").font(.footnote).foregroundStyle(.secondary).padding()
                            .accessibilityIdentifier("couponProducts.end")
                    }
                }.padding(12).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.scrollBounceBehavior(.always, axes: .vertical).refreshable { await model.refresh() }
                .accessibilityIdentifier("couponProducts.page")
        }.background(.quinary).navigationTitle("商品列表").navigationBarTitleDisplayMode(.inline)
            .task(id: active) { await model.activate(active) }.onDisappear { model.stop() }
    }
    private func card(_ item: CouponProductSummary) -> some View {
        Button {
            onOpenProduct(item.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { proxy in
                    if let pipeline {
                        RemoteImage(
                            url: item.imageURL, targetSize: proxy.size, contentMode: .fit,
                            pipeline: pipeline, isEnabled: active)
                    } else {
                        Color.clear.overlay {
                            Image(systemName: "photo").foregroundStyle(.tertiary)
                        }
                    }
                }.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
                Text(item.title).font(.body).foregroundStyle(.primary).lineLimit(2)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(
                    item.priceYuan.formatted(
                        .currency(code: "CNY").locale(Locale(identifier: "zh_CN")))
                )
                .font(.headline).foregroundStyle(.red)
                Text("已售\(item.sold)件").font(.caption).foregroundStyle(.secondary)
            }.padding(12).background(.background, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityIdentifier("couponProducts.item.\(item.id)")
    }
}
