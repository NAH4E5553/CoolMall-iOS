import Foundation
import MallCore
import Testing
@testable import AccountFeature

@MainActor struct AddressViewModelTests {
    private var input: ShippingAddressInput {
        ShippingAddressInput(
            contact: "测试", phone: "13800000000", province: "河北省", city: "石家庄市", district: "桥西区",
            address: "测试街道", isDefault: false)
    }
    private func settle(_ predicate: () -> Bool) async {
        let limit = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate() && ContinuousClock.now < limit { await Task.yield() }
        #expect(predicate())
    }
    @Test func newDraftValidationSubmissionIsSingleFlightAndSuccessOnlyPublishesOnce() async {
        let service = AddressVMService();
        let vm = AddressEditorViewModel(
            accountID: 1, id: nil, loader: service, writer: service, regions: service)
        await vm.activate(true); #expect(!vm.canSave); #expect(vm.validationMessage == nil)
        vm.draft = input; vm.draft.phone = "1380000000"
        #expect(!vm.canSave); #expect(vm.validationMessage == "请填写11位有效手机号")
        vm.save {}; #expect(await service.writes == 0)
        vm.draft.phone += "0"; #expect(vm.canSave); #expect(vm.validationMessage == nil)
        var saved = 0; vm.save { saved += 1 }; vm.save { saved += 1 }
        await service.started(); #expect(await service.writes == 1); #expect(vm.saving)
        await service.finish(); await settle { saved == 1 }; #expect(!vm.canSave)
    }
    @Test func definiteRejectionKeepsDraftAndOnlyExplicitSaveRetriesUnknownNeverDoes() async {
        let service = AddressVMService();
        let vm = AddressEditorViewModel(
            accountID: 1, id: nil, loader: service, writer: service, regions: service)
        await vm.activate(true); vm.draft = input; vm.save {}
        await service.started(); await service.finish(.rejected(code: 500, message: "地址错误"));
        await settle { !vm.saving }
        #expect(vm.errorMessage == "地址错误"); #expect(vm.draft == input); #expect(vm.canSave)
        vm.save {}; await service.started(); await service.finish(.unconfirmed);
        await settle { !vm.saving }
        #expect(vm.unconfirmed); #expect(!vm.canSave)
        vm.draft.phone = "1380000000"; #expect(vm.validationMessage != nil)
        vm.draft.phone += "0"; #expect(vm.validationMessage == nil); #expect(!vm.canSave)
        vm.save {}; #expect(await service.writes == 2)
    }
    @Test func stoppedSaveAndIgnoredCancellationCannotPublishOldSuccessOrAutoResubmit() async {
        let service = AddressVMService();
        let vm = AddressEditorViewModel(
            accountID: 1, id: nil, loader: service, writer: service, regions: service)
        await vm.activate(true); vm.draft = input; var saved = false; vm.save { saved = true }
        await service.started(); vm.stop(); await service.finish(); await vm.activate(true)
        #expect(!saved); #expect(vm.unconfirmed); #expect(vm.draft == input); #expect(!vm.canSave);
        #expect(await service.writes == 1)
    }
    @Test func existingUnknownRegionIsPreservedAndRegionDuplicatesAreRejected() async {
        let service = AddressVMService();
        let vm = AddressEditorViewModel(
            accountID: 1, id: 7, loader: service, writer: service, regions: service)
        await vm.activate(true); #expect(vm.draft.province == "旧省名称"); await vm.loadRegions()
        #expect(vm.regions.isEmpty); #expect(vm.regionError != nil);
        #expect(vm.draft.province == "旧省名称")
        vm.draft.contact = "正在编辑"; vm.stop(); await vm.activate(true);
        #expect(vm.draft.contact == "正在编辑")
    }
    @Test func unknownDeleteNeedsFreshReadThenAnotherExplicitConfirmation() async {
        let service = AddressVMService();
        let vm = AddressListViewModel(accountID: 1, loader: service, writer: service)
        await vm.activate(true); vm.deleteCandidate = vm.state.items[0]; vm.confirmDelete();
        await service.started()
        await service.finish(.unconfirmed); await settle { vm.deleting == nil }
        vm.deleteCandidate = vm.state.items[0]; vm.confirmDelete();
        #expect(await service.writes == 1)
        await vm.refresh(); #expect(await service.writes == 1)
        vm.deleteCandidate = vm.state.items[0]; vm.confirmDelete(); await service.started();
        #expect(await service.writes == 2)
        await service.finish(); await settle { vm.state.items.first?.id == 2 }; vm.stop()
    }
    @Test func appendFailureKeepsRowsAndExplicitRefreshRestoresNextPage() async {
        let service = AddressVMService(appendFailure: true);
        let vm = AddressListViewModel(accountID: 1, loader: service, writer: service)
        await vm.activate(true); vm.more(); await settle { vm.state.appendFailure != nil }
        #expect(vm.state.items.count == 10); #expect(vm.state.operation == nil)
        await vm.refresh(); vm.more(); await settle { vm.state.items.count == 12 }; vm.stop()
    }
    @Test func listPaginationAndDeleteKeepCommittedSnapshotUntilAcknowledgedThenRefresh() async {
        let service = AddressVMService();
        let vm = AddressListViewModel(accountID: 1, loader: service, writer: service)
        await vm.activate(true); #expect(vm.state.items.count == 10); vm.more();
        await settle { vm.state.items.count == 12 }
        vm.deleteCandidate = vm.state.items[0]; vm.confirmDelete(); await service.started()
        #expect(vm.state.items.count == 12); #expect(vm.deleting == 1)
        await service.finish(); await settle { vm.deleting == nil && vm.state.items.first?.id == 2 }
        #expect(vm.state.total == 11); vm.stop()
    }
}
private actor AddressVMService: AddressLoading, AddressWriting, AddressRegionsLoading {
    var writes = 0
    private var failAppend: Bool
    init(appendFailure: Bool = false) { failAppend = appendFailure }
    private var deleted: Set<Int64> = []
    private var gate: CheckedContinuation<Void, any Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func loadAddresses(accountID: Int64, page: Int, pageSize: Int) throws -> NumberedPage<
        ShippingAddress
    > {
        if page == 2 && failAppend { failAppend = false; throw PageReadFailure.timeout }
        let all = (1...12).filter { !deleted.contains(Int64($0)) }.map {
            ShippingAddress(id: Int64($0), value: .init(contact: "测试"))
        }
        return NumberedPage(
            items: Array(all.dropFirst((page - 1) * pageSize).prefix(pageSize)), page: page,
            size: pageSize, total: Int64(all.count))
    }
    func loadAddress(accountID: Int64, id: Int64) -> ShippingAddress {
        ShippingAddress(
            id: id,
            value: .init(
                contact: "测试", phone: "13800000000", province: "旧省名称", city: "旧市", district: "旧区",
                address: "旧地址"))
    }
    func loadRegions() -> [AddressRegion] {
        [AddressRegion(id: "same", name: "测试", children: [AddressRegion(id: "same", name: "重复")])]
    }
    func saveAddress(accountID: Int64, id: Int64?, input: ShippingAddressInput) async throws {
        try await hold()
    }
    func deleteAddress(accountID: Int64, id: Int64) async throws {
        try await hold(); deleted.insert(id)
    }
    private func hold() async throws {
        writes += 1
        try await withCheckedThrowingContinuation {
            gate = $0; waiters.forEach { $0.resume() }; waiters = []
        }
    }
    func started() async {
        if gate != nil { return }; await withCheckedContinuation { waiters.append($0) }
    }
    func finish(_ failure: AddressWriteFailure? = nil) {
        if let failure { gate?.resume(throwing: failure) } else { gate?.resume() }; gate = nil
    }
}
