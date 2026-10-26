import Foundation
import MallCore
import Testing
@testable import MallData

struct SessionCoordinatorTests {
    private let profile = AccountProfile(
        id: 123, nickname: "测试", phone: "13800000000", avatarURL: nil)
    private var input: LoginCredential { .password(phone: "13800000000", password: "test-only") }
    @Test func persistedSessionRoundTripRestoreAndLogout() async throws {
        let storage = SessionTestStorage()
        defer { try? storage.delete() }
        #expect(try storage.read() == nil)
        let loader = SessionLoader(profile: profile)
        let session = SessionCoordinator(loader: loader, storage: storage)
        try await session.login(input)
        #expect(await current(session) == .signedIn(profile))
        let restored = SessionCoordinator(loader: loader, storage: storage)
        #expect(restored.initialState == .signedIn(profile))
        try await restored.logout()
        #expect(try storage.read() == nil)
        #expect(await current(restored) == .guest)
    }
    @Test func credentialReadFailureIsGuestAndCanLogin() async throws {
        let session = SessionCoordinator(
            loader: SessionLoader(profile: profile), storage: ReadFailingStorage())
        #expect(session.initialState == .guest)
        #expect(await current(session) == .guest)
        try await session.login(input)
        #expect(await current(session) == .signedIn(profile))
    }
    @Test func credentialFailureCannotPublishLoginSuccess() async throws {
        let session = SessionCoordinator(
            loader: SessionLoader(profile: profile), storage: FailingStorage())
        await #expect(throws: AccountFailure.credentialWrite) { try await session.login(input) }
        #expect(await current(session) == .guest)
    }
    @Test func logoutDuringIgnoredCancellationRejectsLateLogin() async throws {
        let storage = SessionTestStorage()
        defer { try? storage.delete() }
        let loader = SessionLoader(profile: profile, hold: true)
        let session = SessionCoordinator(loader: loader, storage: storage)
        let attempt = Task { try await session.login(input) }
        await loader.waitForStart()
        try await session.logout()
        await loader.release()
        await #expect(throws: CancellationError.self) { try await attempt.value }
        #expect(await current(session) == .guest)
        #expect(try storage.read() == nil)
    }
    @Test func cancelAndDuplicateSubmissionCannotCommitCredentials() async throws {
        let storage = SessionTestStorage()
        defer { try? storage.delete() }
        let loader = SessionLoader(profile: profile, hold: true)
        let session = SessionCoordinator(loader: loader, storage: storage)
        let attempt = Task { try await session.login(input) }
        await loader.waitForStart()
        await #expect(throws: AccountFailure.busy) { try await session.login(input) }
        attempt.cancel(); await loader.release()
        await #expect(throws: CancellationError.self) { try await attempt.value }
        #expect(await loader.logins == 1)
        #expect(try storage.read() == nil)
    }
    @Test func refreshCannotOverwriteAnInFlightLogin() async throws {
        let storage = SessionTestStorage()
        defer { try? storage.delete() }
        let previous = AccountProfile(id: 1, nickname: "旧账号", phone: "13900000000", avatarURL: nil)
        try storage.save(
            AccountCredentialRecord(
                tokens: AuthenticationTokens(
                    token: "old", refreshToken: "old-r", expire: 1, refreshExpire: 2),
                profile: previous))
        let loader = SessionLoader(profile: profile, hold: true)
        let session = SessionCoordinator(loader: loader, storage: storage)
        let attempt = Task { try await session.login(input) }
        await loader.waitForStart()
        await #expect(throws: AccountFailure.busy) { try await session.refreshProfile() }
        await loader.release(); try await attempt.value
        #expect(try storage.read()?.profile == profile)
        #expect(await current(session) == .signedIn(profile))
    }
    @Test func failedLogoutPreservesPublishedAccount() async throws {
        let tokens = AuthenticationTokens(
            token: "a", refreshToken: "r", expire: 1, refreshExpire: 2)
        let session = SessionCoordinator(
            loader: SessionLoader(profile: profile),
            storage: FailingStorage(
                existing: AccountCredentialRecord(tokens: tokens, profile: profile)))
        await #expect(throws: AccountFailure.credentialDelete) { try await session.logout() }
        #expect(await current(session) == .signedIn(profile))
    }
    private func current(_ session: SessionCoordinator) async -> AccountState? {
        var iterator = await session.states().makeAsyncIterator()
        return await iterator.next()
    }
}

private struct FailingStorage: AccountCredentialStoring {
    var existing: AccountCredentialRecord? = nil
    func read() -> AccountCredentialRecord? { existing }
    func save(_ value: AccountCredentialRecord) throws { throw AccountFailure.credentialWrite }
    func delete() throws { if existing != nil { throw AccountFailure.credentialDelete } }
}

private actor SessionLoader: AuthenticationLoading {
    let user: AccountProfile; let hold: Bool
    var logins = 0
    var gate: CheckedContinuation<Void, Never>?
    var startWaiters: [CheckedContinuation<Void, Never>] = []
    init(profile: AccountProfile, hold: Bool = false) { user = profile; self.hold = hold }
    func authenticate(_ credential: LoginCredential) async -> AuthenticationTokens {
        logins += 1
        if hold {
            await withCheckedContinuation { continuation in
                gate = continuation; startWaiters.forEach { $0.resume() }; startWaiters = []
            }
        }
        return AuthenticationTokens(
            token: "synthetic-a", refreshToken: "synthetic-r", expire: 60, refreshExpire: 120)
    }
    func waitForStart() async {
        if gate != nil { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }
    func release() { gate?.resume(); gate = nil }
    func profile(token: String) -> AccountProfile { user }
    func captcha() -> LoginCaptcha { .init(id: "test", imageData: Data([1])) }
    func requestCode(phone: String, captchaID: String, answer: String) -> String { "2468" }
}

// The package runner has no keychain application entitlement. This store tests
// session transactions and restoration; the actual Keychain adapter is verified
// separately in the signed simulator integration harness (see acceptance evidence).
private struct SessionTestStorage: AccountCredentialStoring {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "account-test-" + UUID().uuidString)
    func read() throws -> AccountCredentialRecord? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(AccountCredentialRecord.self, from: Data(contentsOf: url))
    }
    func save(_ value: AccountCredentialRecord) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
    func delete() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

private struct ReadFailingStorage: AccountCredentialStoring {
    func read() throws -> AccountCredentialRecord? { throw AccountFailure.credentialRead }
    func save(_ value: AccountCredentialRecord) {}
    func delete() {}
}
