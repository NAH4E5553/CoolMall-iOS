import Foundation
import MallCore
import Observation

@MainActor @Observable final class AddressListViewModel {
    private let pages: NumberedPageCoordinator<ShippingAddress>
    private let writer: any AddressWriting
    private let accountID: Int64
    private var active = false
    private var revision: UInt64 = 0
    private var deletion: Task<Void, Never>?
    private var uncertain: Set<Int64> = []
    private(set) var state: NumberedPageSnapshot<ShippingAddress>
    private(set) var deleting: Int64?
    private(set) var notice: String?
    var deleteCandidate: ShippingAddress?
    init(accountID: Int64, loader: any AddressLoading, writer: any AddressWriting) {
        self.accountID = accountID; self.writer = writer
        let pages = NumberedPageCoordinator<ShippingAddress>(pageSize: 10) { page, size in
            try await loader.loadAddresses(accountID: accountID, page: page, pageSize: size)
        }
        self.pages = pages; state = pages.snapshot
        pages.onChange = { [weak self] in self?.state = $0 }
    }
    func activate(_ value: Bool) async {
        if !value { stop(); return }
        active = true; pages.setActive(true); await refresh()
    }
    func refresh() async {
        let token = revision
        await pages.refresh()
        if active, revision == token, pages.snapshot.failure == nil, pages.snapshot.hasLoaded {
            // A fresh explicit read allows a subsequent explicit confirmation, never a replay.
            uncertain.removeAll()
        }
    }
    func more() { pages.loadMore(automatic: true) }
    func tailExited() { pages.tailExited() }
    func stop() {
        active = false; revision &+= 1; pages.setActive(false)
        if let deleting { uncertain.insert(deleting) }
        deletion?.cancel(); deletion = nil; deleting = nil; deleteCandidate = nil
    }
    func dismissNotice() { notice = nil }
    func confirmDelete() {
        guard active, deleting == nil, let candidate = deleteCandidate else { return }
        deleteCandidate = nil
        guard !uncertain.contains(candidate.id) else { notice = "删除结果尚未确认，请下拉刷新核对"; return }
        deleting = candidate.id; revision &+= 1; let token = revision
        let accountID = accountID; let writer = writer
        deletion = Task { [weak self] in
            do {
                try await writer.deleteAddress(accountID: accountID, id: candidate.id)
                guard let self, self.active, self.revision == token, !Task.isCancelled else {
                    return
                }
                self.deleting = nil; self.notice = "删除成功"; self.deletion = nil
                await self.pages.refresh()
            } catch {
                guard let self, self.active, self.revision == token else { return }
                self.deleting = nil; self.deletion = nil
                if error is CancellationError || error as? AddressWriteFailure == .unconfirmed {
                    self.uncertain.insert(candidate.id)
                }
                self.notice =
                    self.uncertain.contains(candidate.id)
                    ? "删除结果尚未确认，请下拉刷新核对" : addressWriteMessage(error)
            }
        }
    }
}
@MainActor @Observable final class AddressEditorViewModel {
    let id: Int64?
    private let accountID: Int64
    private let loader: any AddressLoading
    private let regionLoader: any AddressRegionsLoading
    private(set) var regions: [AddressRegion] = []
    private(set) var regionError: String?
    private let writer: any AddressWriting
    private var active = false
    private var loaded: Bool
    private var revision: UInt64 = 0
    private var submission: Task<Void, Never>?
    var draft = ShippingAddressInput()
    private(set) var loading = false
    private(set) var saving = false
    private(set) var unconfirmed = false
    private(set) var errorMessage: String?
    var canSave: Bool { active && loaded && !loading && !saving && !unconfirmed && draft.isValid }
    var validationMessage: String? {
        let value = draft.normalized
        guard !value.contact.isEmpty, !value.phone.isEmpty, !value.province.isEmpty,
            !value.city.isEmpty, !value.district.isEmpty, !value.address.isEmpty, !value.isValid
        else { return nil }
        return "请填写11位有效手机号"
    }
    init(
        accountID: Int64, id: Int64?, loader: any AddressLoading, writer: any AddressWriting,
        regions: any AddressRegionsLoading
    ) {
        self.accountID = accountID; self.id = id; self.loader = loader; self.writer = writer;
        self.regionLoader = regions
        loaded = id == nil
    }
    func activate(_ value: Bool) async {
        if !value { stop(); return }
        active = true
        guard !loaded, !loading, let id else { return }
        revision &+= 1; let token = revision; loading = true; errorMessage = nil
        do {
            let value = try await loader.loadAddress(accountID: accountID, id: id)
            guard active, revision == token, !Task.isCancelled else { return }
            draft = value.value; loaded = true; loading = false
        } catch {
            guard active, revision == token else { return }
            loading = false
            if !(error is CancellationError) { errorMessage = "地址读取失败，请返回后重试" }
        }
    }
    func stop() {
        active = false; revision &+= 1; loading = false
        if saving { unconfirmed = true; errorMessage = "保存结果尚未确认，请返回地址列表核对" }
        submission?.cancel(); submission = nil; saving = false
    }
    func loadRegions() async {
        guard active, regions.isEmpty else { return }
        let token = revision; regionError = nil
        do {
            let values = try await regionLoader.loadRegions()
            try Task.checkCancellation()
            guard active, revision == token else { return }
            var ids = Set<String>()
            func valid(_ nodes: [AddressRegion], depth: Int) -> Bool {
                !nodes.isEmpty
                    && nodes.allSatisfy { node in
                        !node.id.isEmpty && !node.name.isEmpty && ids.insert(node.id).inserted
                            && (depth == 3
                                ? node.children.isEmpty : valid(node.children, depth: depth + 1))
                    }
            }
            guard valid(values, depth: 1) else { throw PageReadFailure.invalidResponse }
            regions = values
        } catch {
            guard active, revision == token, !(error is CancellationError) else { return }
            regionError = "地区数据读取失败，请收起后重试"
        }
    }
    func save(onSaved: @escaping @MainActor () -> Void) {
        guard canSave else { return }
        saving = true; errorMessage = nil; revision &+= 1; let token = revision
        let input = draft.normalized; let writer = writer; let accountID = accountID; let id = id
        submission = Task { [weak self] in
            do {
                try await writer.saveAddress(accountID: accountID, id: id, input: input)
                guard let self, self.active, self.revision == token, !Task.isCancelled else {
                    return
                }
                self.saving = false; self.submission = nil
                // Disable this exact draft before routing, even if the callback does not pop immediately.
                self.loaded = false
                onSaved()
            } catch {
                guard let self, self.active, self.revision == token else { return }
                self.saving = false; self.submission = nil
                self.unconfirmed =
                    error is CancellationError || error as? AddressWriteFailure == .unconfirmed
                self.errorMessage = addressWriteMessage(error)
            }
        }
    }
}
func addressWriteMessage(_ error: any Error) -> String {
    switch error as? AddressWriteFailure {
    case .rejected(_, let message): return message ?? "操作失败，请重试"
    case .authenticationRequired: return "登录已失效，请返回后重新登录"
    case .invalidConfiguration: return "地址服务暂时不可用，请稍后重试"
    case .invalidInput: return "请检查地址信息"
    case .busy: return "正在处理地址，请稍后重试"
    default: return "操作结果尚未确认，请返回地址列表核对"
    }
}
