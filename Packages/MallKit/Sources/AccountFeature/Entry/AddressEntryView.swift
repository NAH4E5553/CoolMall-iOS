import Foundation
import MallCore
import SwiftUI

@MainActor public struct AddressEntryView: View {
    private let accountID: Int64
    private let loader: any AddressLoading
    private let writer: any AddressWriting
    private let isActive: Bool
    private let onEdit: (Int64?) -> Void
    public init(
        accountID: Int64, loader: any AddressLoading, writer: any AddressWriting, isActive: Bool,
        onEdit: @escaping (Int64?) -> Void
    ) {
        self.accountID = accountID; self.loader = loader; self.writer = writer
        self.isActive = isActive; self.onEdit = onEdit
    }
    public var body: some View {
        AddressListScreen(
            accountID: accountID, loader: loader, writer: writer, isActive: isActive, onEdit: onEdit
        ).id(accountID)
    }
}
@MainActor private struct AddressListScreen: View {
    @State private var model: AddressListViewModel
    @Environment(\.scenePhase) private var scenePhase
    let isActive: Bool
    let onEdit: (Int64?) -> Void
    init(
        accountID: Int64, loader: any AddressLoading, writer: any AddressWriting, isActive: Bool,
        onEdit: @escaping (Int64?) -> Void
    ) {
        _model = State(
            initialValue: AddressListViewModel(accountID: accountID, loader: loader, writer: writer)
        )
        self.isActive = isActive; self.onEdit = onEdit
    }
    private var active: Bool { isActive && scenePhase == .active }
    var body: some View {
        @Bindable var model = model
        ScrollView {
            LazyVStack(spacing: 14) {
                if model.state.operation == .initial { ProgressView("正在读取地址") }
                if let failure = model.state.failure ?? model.state.appendFailure {
                    Text(failure == .authenticationRequired ? "登录已失效，请返回后重新登录" : "地址读取失败，请下拉刷新重试")
                        .foregroundStyle(.secondary).accessibilityIdentifier("addresses.readError")
                }
                if model.state.hasLoaded && model.state.items.isEmpty {
                    ContentUnavailableView("暂无收货地址", systemImage: "mappin.slash")
                        .accessibilityIdentifier("addresses.empty")
                }
                ForEach(model.state.items) { address in card(address) }
                if model.state.nextPage != nil && model.state.appendFailure == nil {
                    ProgressView().frame(height: 44).onAppear { model.more() }.onDisappear {
                        model.tailExited()
                    }
                }
            }.padding(16)
        }
        .accessibilityIdentifier("addresses.list")
        .background(Color.primary.opacity(0.035))
        .refreshable { await model.refresh() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                onEdit(nil)
            } label: {
                Text("新增地址").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            .controlSize(.large).tint(accountAccent).padding(16).background(.background)
            .accessibilityIdentifier(
                "addresses.add")
        }
        .navigationTitle("收货地址").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "确定删除该地址？",
            isPresented: Binding(
                get: { model.deleteCandidate != nil },
                set: { if !$0 { model.deleteCandidate = nil } }), titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { model.confirmDelete() }
        }
        .overlay(alignment: .bottom) {
            if let message = model.notice {
                Text(message).font(.callout).padding(14).background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12).accessibilityIdentifier("addresses.toast")
            }
        }
        .task(id: active) { await model.activate(active) }
        .task(id: model.notice) {
            guard model.notice != nil else { return }
            do { try await Task.sleep(for: .seconds(3)); model.dismissNotice() } catch {}
        }
        .onDisappear { model.stop() }
    }
    private func card(_ item: ShippingAddress) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    onEdit(item.id)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.value.province + item.value.city + item.value.district).font(
                            .headline
                        ).foregroundStyle(.primary)
                        Text(item.value.address).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("addresses.card.\(item.id)")
                Button {
                    onEdit(item.id)
                } label: {
                    Image(systemName: "square.and.pencil").frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("编辑地址")
                .accessibilityIdentifier("addresses.edit.\(item.id)")
                Button {
                    model.deleteCandidate = item
                } label: {
                    if model.deleting == item.id {
                        ProgressView().frame(width: 44, height: 44).contentShape(Rectangle())
                    } else {
                        Image(systemName: "trash").frame(width: 44, height: 44).contentShape(
                            Rectangle())
                    }
                }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(model.deleting != nil)
                    .accessibilityLabel("删除地址").accessibilityIdentifier(
                        "addresses.delete.\(item.id)")
            }.padding(16)
            Divider()
            HStack {
                Text(item.value.contact); Text(item.value.phone); Spacer(minLength: 4)
                if item.value.isDefault {
                    Text("默认").font(.caption).foregroundStyle(.white).padding(6).background(
                        accountAccent, in: Capsule())
                }
            }.foregroundStyle(.secondary).padding(16)
        }.background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}
