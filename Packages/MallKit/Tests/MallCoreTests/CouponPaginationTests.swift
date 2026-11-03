import Foundation
import MallCore
import Testing

@MainActor struct CouponPaginationTests {
    private func item(_ id: Int64, _ title: String = "券") -> UserCoupon {
        UserCoupon(
            id: id, title: title, description: "说明", amountYuan: 30, minimumSpendYuan: 299,
            startTime: "2020-01-01T00:00:00", endTime: "2030-01-01T00:00:00", type: 0, status: 1,
            useStatus: 0)
    }
    private func finish(_ coordinator: NumberedPageCoordinator<UserCoupon>) async {
        for _ in 0..<10000 {
            if coordinator.snapshot.operation == nil { return }; await Task.yield()
        }
        Issue.record("coordinator did not settle")
    }
    @Test func firstEmptyAndRefreshWaitForActualRead() async {
        let reader = CouponPageGate()
        let pages = NumberedPageCoordinator<UserCoupon>(pageSize: 2) {
            try await reader.read($0, $1)
        }
        pages.setActive(true)
        let initial = Task { await pages.loadInitial() }; await reader.started(1)
        #expect(!pages.snapshot.hasLoaded); #expect(pages.snapshot.operation == .initial)
        await reader.resolve(1, .success(NumberedPage(items: [], page: 1, size: 2, total: 0)))
        await initial.value; #expect(pages.snapshot.hasLoaded);
        #expect(pages.snapshot.nextPage == nil)
        let refresh = Task { await pages.refresh() }; await reader.started(2)
        #expect(pages.snapshot.operation == .refresh)
        await reader.resolve(2, .failure(.networkUnavailable)); await refresh.value
        #expect(pages.snapshot.hasLoaded); #expect(pages.snapshot.failure == .networkUnavailable)
    }
    @Test func appendFailureRetrySamePageDeduplicatesAndRejectsNoProgress() async {
        let reader = CouponPageGate()
        let pages = NumberedPageCoordinator<UserCoupon>(pageSize: 2) {
            try await reader.read($0, $1)
        }
        pages.setActive(true); let first = Task { await pages.loadInitial() };
        await reader.started(1)
        await reader.resolve(
            1, .success(NumberedPage(items: [item(1), item(2)], page: 1, size: 2, total: 5)));
        await first.value
        pages.loadMore(automatic: true); await reader.started(2); pages.loadMore()
        #expect(await reader.count == 2)
        await reader.resolve(2, .failure(.timeout)); await finish(pages)
        #expect(pages.snapshot.items.map(\.id) == [1, 2]); #expect(pages.snapshot.nextPage == 2)
        pages.loadMore(automatic: true); #expect(await reader.count == 2)
        pages.loadMore(); await reader.started(3)
        #expect(await reader.requests.last?.0 == 2)
        await reader.resolve(
            3, .success(NumberedPage(items: [item(2, "更新"), item(3)], page: 2, size: 2, total: 5)));
        await finish(pages)
        #expect(pages.snapshot.items.map(\.id) == [1, 2, 3]);
        #expect(pages.snapshot.items[1].title == "更新")
        pages.loadMore(); await reader.started(4)
        await reader.resolve(
            4, .success(NumberedPage(items: [item(3)], page: 3, size: 2, total: 5)));
        await finish(pages)
        #expect(pages.snapshot.appendFailure == .noProgress); #expect(pages.snapshot.nextPage == 3)
        #expect(pages.snapshot.items.map(\.id) == [1, 2, 3])
    }
    @Test func refreshSupersedesIgnoringCancellationAppendAndStopRejectsLateError() async {
        let reader = CouponPageGate()
        let pages = NumberedPageCoordinator<UserCoupon>(pageSize: 2) {
            try await reader.read($0, $1)
        }
        pages.setActive(true); let first = Task { await pages.loadInitial() };
        await reader.started(1)
        await reader.resolve(
            1, .success(NumberedPage(items: [item(1), item(2)], page: 1, size: 2, total: 4)));
        await first.value
        pages.loadMore(); await reader.started(2)
        let refresh = Task { await pages.refresh() }; await reader.started(3)
        await reader.resolve(
            2, .success(NumberedPage(items: [item(3), item(4)], page: 2, size: 2, total: 4)))
        #expect(pages.snapshot.operation == .refresh)
        await reader.resolve(
            3, .success(NumberedPage(items: [item(8)], page: 1, size: 2, total: 1)));
        await refresh.value
        #expect(pages.snapshot.items.map(\.id) == [8])
        let late = Task { await pages.refresh() }; await reader.started(4); pages.setActive(false)
        await reader.resolve(4, .failure(.timeout)); await late.value
        #expect(pages.snapshot.failure == nil); #expect(pages.snapshot.items.map(\.id) == [8])
    }
    @Test func invalidMetadataDoesNotCommitAndAutomaticTailIsBounded() async {
        let reader = CouponPageGate()
        let pages = NumberedPageCoordinator<UserCoupon>(pageSize: 2) {
            try await reader.read($0, $1)
        }
        pages.setActive(true); let first = Task { await pages.loadInitial() };
        await reader.started(1)
        await reader.resolve(
            1, .success(NumberedPage(items: [item(1)], page: 1, size: 2, total: 4)));
        await first.value
        #expect(!pages.snapshot.hasLoaded); #expect(pages.snapshot.failure == .invalidResponse)
        pages.retry(); await reader.started(2)
        await reader.resolve(
            2, .success(NumberedPage(items: [item(1), item(2)], page: 1, size: 2, total: 6)));
        await finish(pages)
        pages.loadMore(automatic: true); await reader.started(3)
        await reader.resolve(
            3, .success(NumberedPage(items: [item(3), item(4)], page: 2, size: 2, total: 6)));
        await finish(pages)
        pages.loadMore(automatic: true); #expect(await reader.count == 3)
        pages.tailExited(); pages.loadMore(automatic: true); await reader.started(4)
        await reader.resolve(
            4, .success(NumberedPage(items: [item(5), item(6)], page: 3, size: 2, total: 6)));
        await finish(pages)
        #expect(pages.snapshot.nextPage == nil); #expect(pages.snapshot.items.count == 6)
    }
    @Test func cancelledRefreshCallerAndDuplicateRefreshHaveSingleOwner() async {
        let reader = CouponPageGate()
        let pages = NumberedPageCoordinator<UserCoupon>(pageSize: 2) {
            try await reader.read($0, $1)
        }
        pages.setActive(true)
        let first = Task { await pages.refresh() }; await reader.started(1)
        let duplicate = Task { await pages.refresh() }; await Task.yield()
        #expect(await reader.count == 1)
        first.cancel();
        await reader.resolve(
            1, .success(NumberedPage(items: [item(1)], page: 1, size: 2, total: 1)))
        await first.value; await duplicate.value
        #expect(!pages.snapshot.hasLoaded); #expect(pages.snapshot.failure == nil)
        #expect(pages.snapshot.operation == nil)
    }
    @Test func availabilityUsesExactBoundaryAndUnknownStatesAreConservative() throws {
        let zone = try #require(TimeZone(secondsFromGMT: 0));
        let now = Date(timeIntervalSince1970: 1893456000)
        #expect(item(1).availability(at: now, timeZone: zone) == .expired)
        #expect(item(1).availability(at: now.addingTimeInterval(-1), timeZone: zone) == .available)
        for value in ["bad", "2030-02-31T00:00:00"] {
            let coupon = UserCoupon(
                id: 1, title: "券", description: "", amountYuan: 1, minimumSpendYuan: nil,
                startTime: nil, endTime: value, type: 0, status: 1, useStatus: 0)
            #expect(coupon.availability(at: now, timeZone: zone) == .unverified)
        }
        for bounds: (String?, String?) in [
            (nil, nil), (nil, "2030-01-01T00:00:00"), ("2020-01-01T00:00:00", nil), ("", ""),
        ] {
            let coupon = UserCoupon(
                id: 1, title: "券", description: "", amountYuan: 1, minimumSpendYuan: nil,
                startTime: bounds.0, endTime: bounds.1, type: 0, status: 1, useStatus: 0)
            #expect(
                coupon.availability(at: now.addingTimeInterval(-1), timeZone: zone) == .unverified)
        }
        let unknown = UserCoupon(
            id: 1, title: "券", description: "", amountYuan: 1, minimumSpendYuan: nil,
            startTime: nil, endTime: nil, type: 7, status: 1, useStatus: 0)
        #expect(unknown.availability(at: now, timeZone: zone) == .unverified)
    }
}
private actor CouponPageGate {
    var count: Int { requests.count }
    var requests: [(Int, Int)] = []
    private var gates: [Int: CheckedContinuation<NumberedPage<UserCoupon>, any Error>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func read(_ page: Int, _ size: Int) async throws -> NumberedPage<UserCoupon> {
        requests.append((page, size)); let id = requests.count
        return try await withCheckedThrowingContinuation { c in
            gates[id] = c
            let ready = waiters.filter { $0.0 <= id }; waiters.removeAll { $0.0 <= id }
            ready.forEach { $0.1.resume() }
        }
    }
    func started(_ count: Int) async {
        if gates[count] != nil { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func resolve(_ id: Int, _ result: Result<NumberedPage<UserCoupon>, PageReadFailure>) {
        guard let c = gates.removeValue(forKey: id) else { Issue.record("missing gate"); return }
        switch result {
        case .success(let value): c.resume(returning: value);
        case .failure(let failure): c.resume(throwing: failure)
        }
    }
}
