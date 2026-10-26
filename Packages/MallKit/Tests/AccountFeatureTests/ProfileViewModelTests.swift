import MallCore
import Testing
@testable import AccountFeature

@MainActor struct ProfileViewModelTests {
    @Test func duplicateRefreshIsRejectedAndFailureCanRetry() async {
        let session = ProfileFake()
        let model = ProfileViewModel(session: session)
        model.refresh(); model.refresh(); await session.waitForRefresh()
        let firstCount = await session.refreshes
        #expect(model.busy && firstCount == 1)
        await session.release(failed: true); await settle(model)
        #expect(model.error != nil && !model.busy)
        model.refresh(); await session.waitForRefresh()
        await session.release(failed: false); await settle(model)
        let retryCount = await session.refreshes
        #expect(model.error == nil && retryCount == 2)
    }
    @Test func leavingRejectsAnUncooperativeLateRefreshError() async {
        let session = ProfileFake()
        let model = ProfileViewModel(session: session)
        model.refresh(); await session.waitForRefresh(); model.stop()
        model.logout(); await settle(model)
        await session.release(failed: true)
        for _ in 0..<100 { await Task.yield() }
        #expect(!model.busy && model.error == nil)
        #expect(await session.logouts == 1)
    }
    @Test func logoutFailureRemainsVisibleAndRetryable() async {
        let session = ProfileFake(failsLogout: true)
        let model = ProfileViewModel(session: session)
        model.logout(); await settle(model)
        #expect(model.error?.contains("退出失败") == true && !model.busy)
        model.logout(); await settle(model)
        #expect(await session.logouts == 2)
    }
    private func settle(_ model: ProfileViewModel) async {
        for _ in 0..<2000 { if !model.busy { return }; await Task.yield() }
        Issue.record("Profile operation did not settle")
    }
}

private actor ProfileFake: AccountSession {
    nonisolated let initialState: AccountState = .guest
    let failsLogout: Bool
    var refreshes = 0; var logouts = 0
    private var gate: CheckedContinuation<Bool, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(failsLogout: Bool = false) { self.failsLogout = failsLogout }
    func states() -> AsyncStream<AccountState> { AsyncStream { $0.finish() } }
    func login(_ credential: LoginCredential) {}
    func logout() throws {
        logouts += 1
        if failsLogout { throw AccountFailure.credentialDelete }
    }
    func refreshProfile() async throws {
        refreshes += 1
        let failed = await withCheckedContinuation { continuation in
            gate = continuation; waiters.forEach { $0.resume() }; waiters = []
        }
        if failed { throw AccountFailure.networkUnavailable }
    }
    func waitForRefresh() async {
        if gate != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release(failed: Bool) { gate?.resume(returning: failed); gate = nil }
}
