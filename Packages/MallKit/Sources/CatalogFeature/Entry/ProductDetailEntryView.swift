import Foundation
import MallCore
import MallImages
import SwiftUI

/// A detail instance owns its read state and SKU draft; App owns navigation.
@MainActor
public struct ProductDetailEntryView: View {
    private let productID: Int64
    private let loader: any ProductDetailLoading
    private let imagePipeline: MallImagePipeline?
    private let isActive: Bool
    private let onShowAllReviews: (Int64) -> Void
    private let footprintRecorder: (any FootprintRecording)?
    private let shoppingCart: (any ShoppingCart)?
    private let cartVerifier: (any CartProductChecking)?
    private let onReceiveCoupon: (CouponClaimOffer) -> Void
    private let onOpenCart: () -> Void
    private let onBuyNow: (BuyNowIntent) -> Void

    public init(
        productID: Int64, loader: any ProductDetailLoading,
        imagePipeline: MallImagePipeline? = nil, isActive: Bool,
        onShowAllReviews: @escaping (Int64) -> Void = { _ in },
        footprintRecorder: (any FootprintRecording)? = nil,
        shoppingCart: (any ShoppingCart)? = nil, cartVerifier: (any CartProductChecking)? = nil,
        onOpenCart: @escaping () -> Void = {},
        onReceiveCoupon: @escaping (CouponClaimOffer) -> Void = { _ in },
        onBuyNow: @escaping (BuyNowIntent) -> Void = { _ in }
    ) {
        self.productID = productID
        self.loader = loader
        self.imagePipeline = imagePipeline
        self.isActive = isActive
        self.onShowAllReviews = onShowAllReviews
        self.footprintRecorder = footprintRecorder
        self.shoppingCart = shoppingCart; self.cartVerifier = cartVerifier;
        self.onOpenCart = onOpenCart
        self.onReceiveCoupon = onReceiveCoupon; self.onBuyNow = onBuyNow
    }

    public var body: some View {
        ProductDetailScreen(
            productID: productID, loader: loader,
            pipeline: imagePipeline, isActive: isActive, onShowAllReviews: onShowAllReviews,
            footprintRecorder: footprintRecorder, shoppingCart: shoppingCart,
            cartVerifier: cartVerifier, onOpenCart: onOpenCart, onReceiveCoupon: onReceiveCoupon,
            onBuyNow: onBuyNow
        )
        .tint(ProductDetailStyle.accent)
        .id(productID)
    }
}

@MainActor
private struct ProductDetailScreen: View {
    @State private var model: ProductDetailViewModel
    @State private var cartModel: ProductCartViewModel?
    @State private var showsSpecifications = false
    @State private var showsCoupons = false
    @State private var requestedBack = false
    @State private var heroOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var imageIndex = 0
    @State private var windowHeight: CGFloat = 800
    @Environment(\.scenePhase) private var scenePhase
    let pipeline: MallImagePipeline?
    let isActive: Bool
    let onShowAllReviews: (Int64) -> Void
    let onOpenCart: () -> Void
    let onReceiveCoupon: (CouponClaimOffer) -> Void
    let onBuyNow: (BuyNowIntent) -> Void
    let shoppingCart: (any ShoppingCart)?
    let cartVerifier: (any CartProductChecking)?
    let footprintRecorder: (any FootprintRecording)?
    @State private var boundCartScope: CartScope?
    @State private var purchaseNotice: String?

    init(
        productID: Int64, loader: any ProductDetailLoading,
        pipeline: MallImagePipeline?, isActive: Bool, onShowAllReviews: @escaping (Int64) -> Void,
        footprintRecorder: (any FootprintRecording)?, shoppingCart: (any ShoppingCart)?,
        cartVerifier: (any CartProductChecking)?,
        onOpenCart: @escaping () -> Void, onReceiveCoupon: @escaping (CouponClaimOffer) -> Void,
        onBuyNow: @escaping (BuyNowIntent) -> Void
    ) {
        _model = State(
            initialValue: ProductDetailViewModel(
                productID: productID, loader: loader, footprintRecorder: footprintRecorder))
        self.pipeline = pipeline; self.isActive = isActive; self.onShowAllReviews = onShowAllReviews
        self.onBuyNow = onBuyNow; self.shoppingCart = shoppingCart; self.cartVerifier = cartVerifier
        self.footprintRecorder = footprintRecorder;
        _boundCartScope = State(initialValue: shoppingCart?.scope)
        self.onOpenCart = onOpenCart; self.onReceiveCoupon = onReceiveCoupon
        _cartModel = State(
            initialValue: shoppingCart.flatMap { store in
                cartVerifier.map { ProductCartViewModel(store: store, verifier: $0) }
            })
    }

    private var active: Bool { isActive && scenePhase == .active }
    private func buyNow() {
        guard active, cartModel?.busy != true else { return }
        guard let selected = model.selected, let product = model.detail else {
            showsSpecifications = true; return
        }
        do {
            let intent = try BuyNowIntent(
                product: product, specification: selected, quantity: model.quantity)
            purchaseNotice = nil; showsSpecifications = false; onBuyNow(intent)
        } catch { purchaseNotice = "所选商品、规格或数量无效，请重新选择" }
    }
    private struct ReadKey: Equatable { let active: Bool; let attempt: Int; let scope: CartScope? }

    var body: some View {
        Group {
            switch model.detailState {
            case .idle, .loading:
                ProgressView("正在加载商品").accessibilityIdentifier("detail.loading")
            case .failed(let failure):
                VStack(spacing: 16) {
                    Text("商品加载失败").font(.headline).accessibilityIdentifier("detail.error")
                    Text(detailFailureDescription(failure)).foregroundStyle(.secondary)
                    Button("重试") { model.retryDetail() }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("detail.retry")
                }.padding()
            case .ready(let detail):
                content(detail)
            }
        }
        .accessibilityHidden(showsCoupons || showsSpecifications)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height + $0.safeAreaInsets.top + $0.safeAreaInsets.bottom
        } action: {
            windowHeight = $0
        }
        .background(ProductDetailStyle.background(scheme))
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            topBar.accessibilityHidden(showsCoupons || showsSpecifications)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.detail != nil {
                ProductDetailBottomBar(
                    onAdd: {
                        if let selected = model.selected {
                            guard model.canAddToCart, boundCartScope == shoppingCart?.scope else {
                                return
                            }
                            cartModel?.add(specification: selected, quantity: model.quantity)
                        } else {
                            showsSpecifications = true
                        }
                    }, onBuy: buyNow, onOpenCart: onOpenCart, isAdding: cartModel?.busy == true,
                    canAdd: model.selected == nil || model.canAddToCart
                )
                .accessibilityHidden(showsCoupons || showsSpecifications)
            }
        }
        .overlay(alignment: .top) {
            if model.footprintSaveFailed {
                Button("浏览记录未保存，点击重试") { model.retryFootprint() }
                    .font(.footnote).padding(8).background(.regularMaterial, in: Capsule())
                    .accessibilityIdentifier("detail.footprint.retry")
            }
        }
        .overlay(alignment: .leading) {
            // A narrow edge fallback preserves back navigation while the system
            // bar is hidden. It never attaches a drag recognizer to the pager.
            Color.clear.frame(width: 20).contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 20).onEnded { value in
                        guard !showsCoupons, !showsSpecifications,
                            value.translation.width > 80,
                            abs(value.translation.height) < value.translation.width / 2
                        else { return }
                        goBack()
                    }
                )
                .accessibilityHidden(true)
        }
        .overlay {
            if showsCoupons, let detail = model.detail {
                ProductDetailCouponSheet(
                    coupons: detail.coupons,
                    height: min(windowHeight * 0.70, max(280, windowHeight - 100)),
                    dismiss: { showsCoupons = false },
                    onReceive: { coupon in
                        showsCoupons = false
                        onReceiveCoupon(
                            CouponClaimOffer(
                                id: coupon.id, title: coupon.title, description: coupon.description,
                                amountYuan: coupon.amountYuan,
                                minimumSpendYuan: coupon.minimumSpendYuan, endTime: coupon.endTime))
                    })
            }
        }
        .task(id: ReadKey(active: active, attempt: model.detailAttempt, scope: shoppingCart?.scope))
        {
            guard !Task.isCancelled else { return }
            // One task entry owns scope rebinding and read restart; no onChange/task ordering assumption.
            if boundCartScope != shoppingCart?.scope {
                cartModel?.setActive(false)
                model.replaceFootprintRecorder(footprintRecorder)
                cartModel = shoppingCart.flatMap { store in
                    cartVerifier.map { ProductCartViewModel(store: store, verifier: $0) }
                }
                boundCartScope = shoppingCart?.scope
            }
            model.setActive(active); cartModel?.setActive(active)
            guard active else { return }
            await model.loadDetail()
        }
        .onChange(of: active) { _, value in
            model.setActive(value)
            cartModel?.setActive(value)
            if !isActive { showsSpecifications = false; showsCoupons = false }
        }
        .onDisappear {
            model.setActive(false)
            cartModel?.setActive(false)
            showsSpecifications = false; showsCoupons = false
        }
        .overlay {
            if showsSpecifications {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.32).ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showsSpecifications = false; cartModel?.cancel()
                        }
                        .accessibilityLabel("关闭规格弹框").accessibilityAddTraits(.isButton)
                    ProductSpecificationSheet(
                        model: model, pipeline: pipeline, isActive: active,
                        maxContentHeight: windowHeight * 0.8,
                        dismiss: {
                            showsSpecifications = false; cartModel?.cancel()
                        },
                        onAdd: {
                            if let selected = model.selected {
                                cartModel?.add(specification: selected, quantity: model.quantity)
                            }
                        },
                        onBuy: buyNow, isAdding: cartModel?.busy == true)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let message = purchaseNotice ?? cartModel?.message {
                Text(message).font(.footnote).padding(12).background(
                    .regularMaterial, in: Capsule()
                )
                .padding(.bottom, 76).accessibilityIdentifier("detail.cart.message")
            }
        }
        .alert(
            "商品价格变化",
            isPresented: Binding(
                get: { cartModel?.confirmation != nil },
                set: { if !$0, cartModel?.confirmation != nil { cartModel?.cancel() } })
        ) {
            Button("取消", role: .cancel) { cartModel?.cancel() }
            Button("确认新价格") { cartModel?.confirmPrice() }.accessibilityIdentifier(
                "detail.cart.confirmPrice")
        } message: {
            Text(cartModel?.confirmation?.text ?? "")
        }
        .onChange(of: cartModel?.success) { _, value in
            if let value, value > 0 { model.didAddToCart(); showsSpecifications = false }
        }
        .onChange(of: showsSpecifications) { old, value in
            if old && !value { cartModel?.cancel() }
        }
        .foregroundStyle(ProductDetailStyle.onSurface(scheme))
    }

    private func goBack() {
        guard isActive, !requestedBack else { return }
        requestedBack = true
        dismiss()
    }

    private var topBar: some View {
        HStack {
            Button {
                goBack()
            } label: {
                Image("detail-back", bundle: .module).resizable().frame(width: 28, height: 28)
            }
            .accessibilityLabel("返回").accessibilityIdentifier("detail.back")
            Spacer()
            Button {
            } label: {
                Image("detail-share", bundle: .module).resizable().frame(width: 20, height: 20)
            }
            .accessibilityLabel("分享").accessibilityHint("功能暂未实现")
        }
        .buttonStyle(DetailCircleButtonStyle())
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(ProductDetailStyle.surface(scheme).opacity(min(1, max(0, -heroOffset / 140))))
    }

    private func content(_ detail: ProductDetailSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                hero(detail)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.frame(in: .global).minY
                    } action: {
                        heroOffset = $0
                    }
                ProductDetailInfoCard(
                    detail: detail, selected: model.selected,
                    showCoupons: { showsCoupons = true },
                    showSpecifications: { showsSpecifications = true }
                )
                .padding(.horizontal, 12)
                ProductDetailDeliveryCard().padding(.horizontal, 12)
                if !detail.reviews.isEmpty {
                    ProductDetailReviewsCard(
                        reviews: detail.reviews, pipeline: pipeline, isActive: active,
                        showAll: { onShowAllReviews(detail.id) }
                    )
                    .padding(.horizontal, 12)
                }
                VStack(spacing: 0) {
                    ProductDetailSectionTitle(title: "商品详情").padding(12)
                        .background(ProductDetailStyle.surface(scheme))
                    // A separate zero-spacing stack prevents outer card spacing from
                    // leaking between slices of one continuous product illustration.
                    VStack(spacing: 0) {
                        ForEach(Array(detail.contentImageURLs.enumerated()), id: \.offset) {
                            index, url in
                            ProductContentImage(url: url, pipeline: pipeline, isActive: active)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Text(verbatim: "商品详情图片 \(index + 1)"))
                                .accessibilityIdentifier("detail.contentImage.\(index)")
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 12)
            }.padding(.bottom, 12)
        }
        .ignoresSafeArea(edges: .top)
        .accessibilityIdentifier("detail.scroll")
        // Identity remains testable without exposing debug copy in the product UI.
        .accessibilityValue(Text(verbatim: "商品ID：\(detail.id)"))
    }

    private func hero(_ detail: ProductDetailSnapshot) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                if detail.imageURLs.isEmpty {
                    detailImage(nil, width: proxy.size.width)
                } else {
                    TabView(selection: $imageIndex) {
                        ForEach(Array(detail.imageURLs.enumerated()), id: \.offset) { index, url in
                            detailImage(url, width: proxy.size.width).tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .accessibilityIdentifier("detail.images")
                    HStack(spacing: 0) {
                        ForEach(detail.imageURLs.indices, id: \.self) { index in
                            Rectangle().fill(
                                ProductDetailStyle.accent.opacity(index == imageIndex ? 0.6 : 0.2)
                            )
                            .frame(width: 16, height: 3)
                        }
                    }
                    .clipShape(Capsule()).padding(.bottom, 10)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("商品图片")
                    .accessibilityValue("\(imageIndex + 1) / \(detail.imageURLs.count)")
                    .accessibilityIdentifier("detail.image.position")
                }
            }
        }.aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func detailImage(_ url: URL?, width: CGFloat, natural: Bool = false) -> some View {
        if let pipeline {
            RemoteImage(
                url: url, targetSize: CGSize(width: width, height: width),
                contentMode: .fill, pipeline: pipeline, isEnabled: active,
                preservesIntrinsicAspectRatio: natural)
        } else {
            Rectangle().fill(.quaternary)
                .overlay { Image(systemName: "photo").accessibilityHidden(true) }
                .frame(width: width, height: width).accessibilityLabel("暂无图片")
        }
    }
}

/// Width is measured without imposing a height on the natural-size image.
private struct ProductContentImage: View {
    let url: URL
    let pipeline: MallImagePipeline?
    let isActive: Bool
    @State private var width: CGFloat = 1
    var body: some View {
        Group {
            if let pipeline {
                RemoteImage(
                    url: url, targetSize: CGSize(width: width, height: width),
                    contentMode: .fit, pipeline: pipeline, isEnabled: isActive,
                    preservesIntrinsicAspectRatio: true)
            } else {
                Rectangle().fill(.quaternary).aspectRatio(1, contentMode: .fit)
                    .overlay { Image(systemName: "photo").accessibilityHidden(true) }
                    .accessibilityLabel("暂无图片")
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = max(1, $0)
        }
    }
}

func detailFailureDescription(_ failure: ProductDetailLoadFailure) -> String {
    switch failure {
    case .invalidProductID: "商品编号无效"
    case .invalidConfiguration: "服务配置无效"
    case .networkUnavailable: "网络不可用"
    case .timeout: "请求超时"
    case .httpStatus(let code): "服务错误（\(code)）"
    case .businessCode(let code): "读取失败（\(code)）"
    case .invalidResponse: "商品数据无效"
    }
}

private struct DetailCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.white).frame(width: 38, height: 38)
            .background(.black.opacity(configuration.isPressed ? 0.45 : 0.3), in: Circle())
            .contentShape(Circle())
    }
}
