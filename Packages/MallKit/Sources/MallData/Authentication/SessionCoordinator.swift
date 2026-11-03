import Foundation
import MallCore

/// App-owned single account writer. Tokens and cached profile commit atomically;
/// profile is required before selecting an account's shopping-cart partition.
public actor SessionCoordinator: AccountSession, LoginChallenges {
    public nonisolated let initialState: AccountState
    private let loader: any AuthenticationLoading
    private let storage: any AccountCredentialStoring
    private let environmentURL: URL?
    private var record: AccountCredentialRecord?
    private var state: AccountState
    private var generation: UInt64 = 0
    private var loginID: UUID?
    private var profileID: UUID?
    private var subscribers: [UUID: AsyncStream<AccountState>.Continuation] = [:]

    public init(environment: APIEnvironment) {
        let storage = KeychainCredentialStore(
            service: "CoolMall.Account.v1." + environment.baseURL.absoluteString)
        self.init(
            loader: HTTPAuthenticationService(environment: environment), storage: storage,
            environmentURL: environment.baseURL)
    }
    init(
        loader: any AuthenticationLoading, storage: any AccountCredentialStoring,
        environmentURL: URL? = nil
    ) {
        self.environmentURL = environmentURL
        self.loader = loader; self.storage = storage
        do {
            let value = try storage.read()
            record = value
            initialState = value.map { .signedIn($0.profile) } ?? .guest
        } catch { initialState = .guest }
        state = initialState
    }
    public func states() -> AsyncStream<AccountState> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<AccountState>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        subscribers[id] = continuation
        continuation.yield(state)
        continuation.onTermination = { [weak self] _ in Task { await self?.remove(id) } }
        return stream
    }
    private func remove(_ id: UUID) { subscribers[id] = nil }
    private func publish(_ value: AccountState) {
        state = value
        for observer in subscribers.values { observer.yield(value) }
    }
    public func login(_ credential: LoginCredential) async throws {
        guard loginID == nil else { throw AccountFailure.busy }
        generation &+= 1
        let epoch = generation
        let id = UUID(); loginID = id; profileID = nil
        defer { if loginID == id { loginID = nil } }
        let tokens = try await loader.authenticate(credential)
        try validate(epoch)
        let profile = try await loader.profile(token: tokens.token)
        try validate(epoch)
        let next = AccountCredentialRecord(tokens: tokens, profile: profile)
        try storage.save(next)
        record = next
        publish(.signedIn(profile))
    }
    public func logout() throws {
        try Task.checkCancellation()
        generation &+= 1; loginID = nil; profileID = nil
        try storage.delete()
        record = nil
        publish(.guest)
    }
    public func refreshProfile() async throws {
        guard let record else { return }
        guard loginID == nil, profileID == nil else { throw AccountFailure.busy }
        let epoch = generation
        let id = UUID(); profileID = id
        defer { if profileID == id { profileID = nil } }
        let profile = try await loader.profile(token: record.tokens.token)
        try validate(epoch)
        guard profile.id == record.profile.id else { throw AccountFailure.invalidPayload }
        let next = AccountCredentialRecord(tokens: record.tokens, profile: profile)
        try storage.save(next)
        self.record = next
        publish(.signedIn(profile))
    }
    private func validate(_ epoch: UInt64) throws {
        try Task.checkCancellation()
        guard generation == epoch else { throw CancellationError() }
    }
    func authorization(accountID: Int64, environmentURL: URL) throws -> AccountReadContext {
        try Task.checkCancellation()
        guard self.environmentURL == environmentURL else {
            throw PageReadFailure.invalidConfiguration
        }
        guard loginID == nil, let record, record.profile.id == accountID,
            state.profile?.id == accountID
        else { throw PageReadFailure.authenticationRequired }
        return AccountReadContext(
            accountID: accountID, generation: generation, token: record.tokens.token,
            environmentURL: environmentURL)
    }
    func validateAuthorization(_ context: AccountReadContext) throws {
        try Task.checkCancellation()
        guard loginID == nil, context.generation == generation,
            context.environmentURL == environmentURL, record?.profile.id == context.accountID,
            state.profile?.id == context.accountID
        else { throw CancellationError() }
    }
    public func captcha() async throws -> LoginCaptcha { try await loader.captcha() }
    public func requestCode(phone: String, captchaID: String, answer: String) async throws -> String
    {
        try await loader.requestCode(phone: phone, captchaID: captchaID, answer: answer)
    }
}
