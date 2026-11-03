import Foundation
import MallCore
import SwiftUI

@MainActor public struct AddressEditorEntryView: View {
    private let accountID: Int64
    private let id: Int64?
    private let loader: any AddressLoading
    private let writer: any AddressWriting
    private let regions: any AddressRegionsLoading
    private let isActive: Bool
    private let onSaved: () -> Void
    public init(
        accountID: Int64, id: Int64?, loader: any AddressLoading, writer: any AddressWriting,
        regions: any AddressRegionsLoading, isActive: Bool, onSaved: @escaping () -> Void
    ) {
        self.accountID = accountID; self.id = id; self.loader = loader; self.writer = writer
        self.regions = regions; self.isActive = isActive; self.onSaved = onSaved
    }
    public var body: some View {
        AddressEditorScreen(
            accountID: accountID, id: id, loader: loader, writer: writer, regions: regions,
            isActive: isActive, onSaved: onSaved
        )
        .id("\(accountID):\(id.map(String.init) ?? "new")")
    }
}
@MainActor private struct AddressEditorScreen: View {
    enum Field: Hashable { case contact, phone, detail }
    @State private var model: AddressEditorViewModel
    @FocusState private var focus: Field?
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectingRegion = false
    @State private var regionBottom: CGFloat = 0
    @ScaledMetric(relativeTo: .caption) private var fieldTopPadding: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var labelLift: CGFloat = 8
    let isActive: Bool
    let onSaved: () -> Void
    init(
        accountID: Int64, id: Int64?, loader: any AddressLoading, writer: any AddressWriting,
        regions: any AddressRegionsLoading, isActive: Bool, onSaved: @escaping () -> Void
    ) {
        _model = State(
            initialValue: AddressEditorViewModel(
                accountID: accountID, id: id, loader: loader, writer: writer, regions: regions))
        self.isActive = isActive; self.onSaved = onSaved
    }
    private var active: Bool { isActive && scenePhase == .active }
    var body: some View {
        @Bindable var model = model
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 22) {
                            field(
                                "联系人", filled: !model.draft.contact.isEmpty,
                                focused: focus == .contact
                            ) {
                                TextField(
                                    "", text: $model.draft.contact,
                                    prompt: Text(focus == .contact ? "请填写联系人" : "联系人")
                                )
                                .textContentType(.name).focused($focus, equals: .contact)
                                .submitLabel(.next)
                                .onSubmit { focus = .phone }.accessibilityLabel("联系人")
                                .accessibilityIdentifier("address.contact")
                            }
                            field(
                                "手机号", filled: !model.draft.phone.isEmpty, focused: focus == .phone
                            ) {
                                TextField(
                                    "", text: $model.draft.phone,
                                    prompt: Text(focus == .phone ? "请填写手机号" : "手机号")
                                )
                                .keyboardType(.phonePad).textContentType(.telephoneNumber).focused(
                                    $focus, equals: .phone
                                )
                                .accessibilityLabel("手机号").accessibilityIdentifier("address.phone")
                            }
                            Button {
                                focus = nil; selectingRegion = true
                            } label: {
                                field(
                                    "省市区", filled: !model.draft.province.isEmpty,
                                    focused: selectingRegion
                                ) {
                                    HStack {
                                        Text(
                                            model.draft.province.isEmpty
                                                ? "省市区"
                                                : [
                                                    model.draft.province, model.draft.city,
                                                    model.draft.district,
                                                ].joined(separator: " ")
                                        )
                                        .foregroundStyle(
                                            model.draft.province.isEmpty ? .secondary : .primary)
                                        Spacer(minLength: 4);
                                        Image(systemName: "chevron.right").foregroundStyle(
                                            .tertiary)
                                    }
                                }
                            }.buttonStyle(.plain).accessibilityIdentifier("address.region")
                                .onGeometryChange(for: CGFloat.self) {
                                    $0.frame(in: .named("address.editor")).maxY
                                } action: {
                                    regionBottom = $0
                                }
                            field(
                                "详细地址", filled: !model.draft.address.isEmpty,
                                focused: focus == .detail, tall: true
                            ) {
                                TextField(
                                    "", text: $model.draft.address,
                                    prompt: Text(focus == .detail ? "请填写街道、楼牌号等" : "详细地址"),
                                    axis: .vertical
                                )
                                .lineLimit(3...6).textContentType(.fullStreetAddress).focused(
                                    $focus, equals: .detail
                                )
                                .accessibilityLabel("详细地址").accessibilityIdentifier(
                                    "address.detail")
                            }
                        }.padding(18).padding(.top, 6).background(
                            .background, in: RoundedRectangle(cornerRadius: 18))
                        Toggle(isOn: $model.draft.isDefault) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("设置默认地址")
                                Text("下单会优先使用该地址").font(.footnote).foregroundStyle(.secondary)
                            }
                        }.toggleStyle(.switch).tint(accountAccent).padding(18).background(
                            .background, in: RoundedRectangle(cornerRadius: 18)
                        ).accessibilityIdentifier("address.default")
                        if model.loading { ProgressView("正在读取地址") }
                        if let message = model.validationMessage {
                            Text(message).font(.footnote).foregroundStyle(.red)
                                .accessibilityIdentifier("address.validation")
                        }
                        if let error = model.errorMessage {
                            Text(error).foregroundStyle(.red).accessibilityIdentifier(
                                "address.error")
                        }
                    }.padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .disabled(model.loading || model.saving)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if selectingRegion { saveButton.hidden() } else { saveButton }
                }
                .allowsHitTesting(!selectingRegion).accessibilityHidden(selectingRegion)
                if selectingRegion {
                    Color.black.opacity(0.3).ignoresSafeArea().onTapGesture {
                        selectingRegion = false
                    }.accessibilityLabel("收起地区选择").accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("address.region.backdrop")
                    // Same viewport/field geometry fixes the height across all levels;
                    // row counts never determine it. It cannot cover the region field.
                    AddressRegionPicker(
                        regions: model.regions, initial: model.draft, error: model.regionError,
                        onDismiss: { selectingRegion = false }
                    ) { path in
                        model.draft.province = path[0].name; model.draft.city = path[1].name;
                        model.draft.district = path[2].name
                        selectingRegion = false
                    }
                    .frame(height: max(0, min(480, geometry.size.height - regionBottom)))
                    .task { await model.loadRegions() }
                }
            }
            .coordinateSpace(name: "address.editor")
            .background(Color.primary.opacity(0.035))
        }
        .navigationTitle(model.id == nil ? "添加地址" : "编辑地址")
        .navigationBarTitleDisplayMode(.large)
        .task(id: active) {
            if !active { selectingRegion = false }; await model.activate(active)
        }
        .onDisappear {
            selectingRegion = false; model.stop()
        }
    }
    private var saveButton: some View {
        Button {
            focus = nil; model.save { onSaved() }
        } label: {
            HStack(spacing: 10) {
                if model.saving { ProgressView().tint(.white) }
                Text("保存")
            }
        }
        .buttonStyle(AddressSaveButtonStyle())
        .disabled(!model.canSave || selectingRegion)
        .padding(16).background(.background)
        .accessibilityHidden(selectingRegion).accessibilityIdentifier("address.save")
    }
    private func field<Content: View>(
        _ label: String, filled: Bool, focused: Bool, tall: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content().tint(accountAccent).frame(
            maxWidth: .infinity, minHeight: tall ? 86 : 30, alignment: .topLeading
        )
        .padding(.horizontal, 14).padding(.top, fieldTopPadding).padding(.bottom, 14)
        .contentShape(Rectangle())
        .overlay {
            RoundedRectangle(cornerRadius: 13).strokeBorder(
                focused ? accountAccent : Color.primary.opacity(0.09),
                lineWidth: focused ? 2 : 1)
        }
        .overlay(alignment: .topLeading) {
            if filled || focused {
                Text(label).font(.caption).foregroundStyle(
                    focused ? accountAccent : .secondary
                ).padding(.horizontal, 5).background(.background).offset(x: 12, y: -labelLift)
            }
        }
    }
}
private struct AddressSaveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(.white)
            .background(accountAccent.opacity(isEnabled ? 1 : 0.45), in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
@MainActor private struct AddressRegionPicker: View {
    let regions: [AddressRegion]
    let initial: ShippingAddressInput
    let error: String?
    let onDismiss: () -> Void
    let onSelect: ([AddressRegion]) -> Void
    @State private var path: [AddressRegion] = []
    @State private var level = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState(
        resetTransaction: Transaction(animation: .spring(response: 0.3, dampingFraction: 1)))
    private var dragOffset: CGFloat = 0
    private var rows: [AddressRegion] { level == 0 ? regions : path[level - 1].children }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Capsule().fill(.tertiary).frame(width: 42, height: 4).padding(.top, 10)
                Text("请选择所在地区").font(.headline)
            }.frame(maxWidth: .infinity).padding(.bottom, 16).contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .global)
                        .updating($dragOffset) { value, offset, transaction in
                            transaction.animation = nil
                            if value.translation.height > abs(value.translation.width) {
                                offset = max(0, value.translation.height)
                            }
                        }.onEnded { value in
                            if value.translation.height >= 64
                                && abs(value.translation.width) < value.translation.height
                            {
                                onDismiss()
                            }
                        }
                ).accessibilityElement(children: .contain).accessibilityIdentifier(
                    "address.region.header")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(path.prefix(level).enumerated()), id: \.offset) { index, node in
                        Button(node.name) {
                            level = index; path = Array(path.prefix(index))
                        }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule)
                        .accessibilityIdentifier("address.region.step.\(index)")
                    }
                    Text("请选择").padding(.horizontal, 14).padding(.vertical, 9).foregroundStyle(
                        .white
                    ).background(.tint, in: Capsule())
                }.padding(.horizontal, 16)
            }.padding(.bottom, 12)
            Divider()
            if let error {
                Text(error).foregroundStyle(.secondary).padding()
            } else if regions.isEmpty {
                ProgressView("正在读取地区").padding()
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { node in
                        Button {
                            path = Array(path.prefix(level)) + [node]
                            if level == 2 { onSelect(path) } else { level += 1 }
                        } label: {
                            Text(node.name).frame(
                                maxWidth: .infinity, minHeight: 54, alignment: .leading
                            ).padding(.horizontal, 24).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier(
                            "address.region.row.\(node.id)")
                        Divider().padding(.horizontal, 16)
                    }
                }
            }.clipped().id(level).accessibilityIdentifier("address.region.rows")
        }.background {
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                .fill(.background).ignoresSafeArea(.container, edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("address.region.panel")
        .offset(y: dragOffset)
        .transaction { if reduceMotion { $0.animation = nil } }
        .accessibilityAction(.escape, onDismiss)
        .onAppear { restore() }.onChange(of: regions) { restore() }
    }
    private func restore() {
        path = []; level = 0
        guard let province = regions.first(where: { $0.name == initial.province }),
            let city = province.children.first(where: { $0.name == initial.city }),
            let district = city.children.first(where: { $0.name == initial.district })
        else { return }
        path = [province, city, district]; level = 2
    }
}
