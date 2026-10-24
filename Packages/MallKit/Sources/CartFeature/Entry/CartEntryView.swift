import MallCore
import MallImages
import SwiftUI

@MainActor
public struct CartEntryView: View {
    private let fixture: (any CartObserving)?
    private let store: (any ShoppingCart)?
    private let verifier: (any CartProductChecking)?
    private let pipeline: MallImagePipeline?
    private let isActive: Bool
    private let onOpenProduct: (Int64) -> Void
    public init(cart: any CartObserving) {
        fixture = cart; store = nil; verifier = nil; pipeline = nil; isActive = true;
        onOpenProduct = { _ in }
    }
    public init(
        store: any ShoppingCart, verifier: any CartProductChecking,
        imagePipeline: MallImagePipeline? = nil, isActive: Bool,
        onOpenProduct: @escaping (Int64) -> Void
    ) {
        fixture = nil; self.store = store; self.verifier = verifier
        pipeline = imagePipeline; self.isActive = isActive; self.onOpenProduct = onOpenProduct
    }
    public var body: some View {
        if let fixture {
            CartFixtureEntry(cart: fixture)
        } else if let store, let verifier {
            ShoppingCartScreen(
                store: store, verifier: verifier, pipeline: pipeline,
                isActive: isActive, onOpenProduct: onOpenProduct
            )
            .id(store.scope)
        }
    }
}

@MainActor
private struct ShoppingCartScreen: View {
    @State private var model: CartViewModel
    @State private var retry = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    let pipeline: MallImagePipeline?
    let isActive: Bool
    let onOpenProduct: (Int64) -> Void
    init(
        store: any ShoppingCart, verifier: any CartProductChecking, pipeline: MallImagePipeline?,
        isActive: Bool, onOpenProduct: @escaping (Int64) -> Void
    ) {
        _model = State(initialValue: CartViewModel(store: store, verifier: verifier))
        self.pipeline = pipeline; self.isActive = isActive; self.onOpenProduct = onOpenProduct
    }
    private var active: Bool { isActive && scenePhase == .active }
    private struct ReadKey: Equatable { let active: Bool; let retry: Int }
    private var accent: Color { Color(red: 0.31, green: 0.32, blue: 1) }
    private var surface: Color { scheme == .dark ? Color(white: 0.12) : .white }
    var body: some View {
        Group {
            switch model.status {
            case .loading: ProgressView("正在读取购物车").accessibilityIdentifier("cart.loading")
            case .failed:
                VStack(spacing: 16) {
                    Text("购物车读取失败，原数据保留").accessibilityIdentifier("cart.error")
                    Button("重试") { retry += 1 }.accessibilityIdentifier("cart.retry")
                }
            case .ready:
                if model.snapshot?.lines.isEmpty != false {
                    ContentUnavailableView("购物车空空如也", systemImage: "cart")
                        .accessibilityIdentifier("cart.empty")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(model.groups, id: \.self) { group in productGroup(group) }
                        }.padding(12)
                    }
                    .accessibilityIdentifier("cart.scroll")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(scheme == .dark ? Color.black : Color(red: 0.945, green: 0.953, blue: 0.98))
        .navigationTitle("购物车").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(model.editing ? "完成" : "编辑") { model.toggleEditing() }
                    .disabled(model.isRemoving || model.snapshot?.lines.isEmpty != false)
                    .accessibilityIdentifier("cart.edit")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let message = model.message {
                    Text(message).font(.footnote).foregroundStyle(.red).padding(8)
                        .accessibilityIdentifier("cart.message")
                }
                bottomBar
            }.background(surface)
        }
        .tint(accent)
        .alert(
            "商品价格变化",
            isPresented: Binding(
                get: { model.confirmation != nil }, set: { if !$0 { model.cancelPrice() } })
        ) {
            Button("取消", role: .cancel) { model.cancelPrice() }
            Button("确认新价格") { model.confirmPrice() }.accessibilityIdentifier("cart.confirmPrice")
        } message: {
            Text(model.confirmation?.text ?? "")
        }
        .task(id: ReadKey(active: active, retry: retry)) {
            if active { await model.observe() } else { model.stop() }
        }
        .onDisappear { model.stop() }
    }
    private func productGroup(_ id: Int64) -> some View {
        VStack(spacing: 0) {
            Button {
                onOpenProduct(id)
            } label: {
                HStack {
                    Text(model.lines(for: id).first?.title ?? "").font(.body)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
                }.padding(12).frame(minHeight: 44)
            }.buttonStyle(.plain).accessibilityIdentifier("cart.product.\(id)")
            Divider()
            ForEach(model.lines(for: id)) { line in row(line) }
        }.background(surface, in: RoundedRectangle(cornerRadius: 16))
    }
    private func row(_ line: CartLine) -> some View {
        HStack(alignment: .center, spacing: 12) {
            selectionButton(line.id).disabled(!model.selectable.contains(line.id))
            VStack(alignment: .leading, spacing: 10) {
                if typeSize.isAccessibilitySize {
                    HStack(alignment: .top) {
                        thumbnail(line); specification(line)
                    }
                    priceAndQuantity(line, stacked: true)
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        thumbnail(line)
                        VStack(alignment: .leading, spacing: 12) {
                            specification(line)
                            priceAndQuantity(line, stacked: false)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let note = model.note(for: line) {
                    Button {
                        model.retryChecks()
                    } label: {
                        Text(note).font(.caption).multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(.secondary).buttonStyle(.plain)
                    .accessibilityIdentifier(
                        "cart.status.\(line.productID).\(line.specificationID)")
                }
            }
        }.padding(12).accessibilityElement(children: .contain).accessibilityIdentifier(
            "cart.line.\(line.productID).\(line.specificationID)")
    }
    private func thumbnail(_ line: CartLine) -> some View {
        Group {
            if let pipeline {
                RemoteImage(
                    url: line.imageURL, targetSize: .init(width: 90, height: 90), contentMode: .fit,
                    pipeline: pipeline, isEnabled: active)
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }.frame(width: 90, height: 90)
            .background(.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
    private func specification(_ line: CartLine) -> some View {
        Text(line.specification).font(.caption).foregroundStyle(.secondary).fixedSize(
            horizontal: false, vertical: true
        )
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
    }
    @ViewBuilder private func priceAndQuantity(_ line: CartLine, stacked: Bool) -> some View {
        if stacked {
            VStack(alignment: .leading, spacing: 8) {
                price(line); stepper(line)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack {
                    price(line); Spacer(minLength: 4); stepper(line)
                }
                VStack(alignment: .leading, spacing: 8) {
                    price(line); stepper(line)
                }
            }
        }
    }
    private func price(_ line: CartLine) -> some View {
        let whole = line.unitPrice.cents / 100
        let fraction = String(format: "%02lld", line.unitPrice.cents % 100)
        return
            (Text("¥").font(.caption) + Text(verbatim: String(whole)).font(.title3.bold())
            + Text(".\(fraction)").font(.caption))
            .foregroundStyle(.red).accessibilityLabel(line.unitPrice.formatted)
            .accessibilityIdentifier("cart.price.\(line.productID).\(line.specificationID)")
    }
    private func stepper(_ line: CartLine) -> some View {
        HStack(spacing: 4) {
            Button {
                model.decrease(line.id)
            } label: {
                Image(systemName: "minus").font(.system(size: 16)).frame(width: 26, height: 26)
                    .background(.secondary.opacity(0.06), in: Circle())
            }.frame(width: 44, height: 44).disabled(line.quantity <= 1 || model.isRemoving)
                .foregroundStyle(.secondary)
                .accessibilityLabel("减少\(line.specification)数量").accessibilityIdentifier(
                    "cart.minus.\(line.productID).\(line.specificationID)")
            Text("\(line.quantity)").monospacedDigit().frame(minWidth: 22)
                .accessibilityIdentifier(
                    "cart.quantity.\(line.productID).\(line.specificationID)")
            Button {
                model.increase(line.id)
            } label: {
                Image(systemName: "plus").font(.system(size: 16)).foregroundStyle(.white).frame(
                    width: 26, height: 26
                )
                .background(accent, in: Circle())
            }.frame(width: 44, height: 44).disabled(model.isRemoving || !model.canIncrease(line))
                .accessibilityLabel("增加\(line.specification)数量")
                .accessibilityIdentifier("cart.plus.\(line.productID).\(line.specificationID)")
        }
        // Pending quantity writes are guarded by the model without changing
        // the controls' appearance. Stock and quantity limits still disable them.
        .frame(minHeight: 44).buttonStyle(.plain).controlSize(.small)
    }
    private func selectionButton(_ id: CartItemID) -> some View {
        Button {
            model.toggle(id)
        } label: {
            Image(systemName: model.selection.contains(id) ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24)).foregroundStyle(
                    model.selection.contains(id) ? accent : .secondary
                )
                .frame(width: 28, height: 44)
        }.buttonStyle(.plain).accessibilityLabel(model.selection.contains(id) ? "取消选择" : "选择")
            .accessibilityAddTraits(model.selection.contains(id) ? .isSelected : [])
            .accessibilityIdentifier("cart.select.\(id.productID).\(id.specificationID)")
    }
    private var bottomBar: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    allButton
                    if !model.editing {
                        Text("合计：").font(.body)
                        Text(model.total?.formatted ?? "金额异常").font(.body).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("cart.total")
                    }
                    actionButton.frame(maxWidth: .infinity, alignment: .trailing)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        allButton; Spacer(minLength: 0); summary; actionButton
                    }
                    VStack(spacing: 12) {
                        HStack {
                            allButton; Spacer(); summary
                        }
                        actionButton.frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }.padding(12)
    }
    private var allButton: some View {
        Button {
            model.toggleAll()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: model.allSelected ? "checkmark.circle.fill" : "circle").font(
                    .system(size: 24))
                Text("全选")
            }
        }.buttonStyle(.plain).accessibilityIdentifier("cart.selectAll").frame(minHeight: 44)
    }
    private var summary: some View {
        Group {
            if !model.editing {
                HStack(spacing: 4) {
                    Text("合计:"); Text(model.total?.formatted ?? "金额异常").foregroundStyle(.red)
                }
                .accessibilityElement(children: .combine).accessibilityIdentifier("cart.total")
            }
        }
    }
    private var actionButton: some View {
        Button {
            if model.editing { model.removeSelected() }
        } label: {
            Text(
                model.editing
                    ? "删除(\(model.selection.count))"
                    : (model.selection.isEmpty ? "结算" : "结算(\(model.selection.count))")
            )
            .bold().foregroundStyle(.white).padding(.horizontal, 24).padding(.vertical, 12)
            .background(model.editing ? .red : accent, in: Capsule())
            .opacity(model.selection.isEmpty ? 0.5 : 1)
        }.disabled(model.selection.isEmpty || model.isRemoving || model.total == nil)
            .buttonStyle(.plain).accessibilityIdentifier(
                model.editing ? "cart.delete" : "cart.checkout"
            )
            .accessibilityHint(model.editing ? "删除所选规格" : "结算功能暂缓实现")
    }
}
