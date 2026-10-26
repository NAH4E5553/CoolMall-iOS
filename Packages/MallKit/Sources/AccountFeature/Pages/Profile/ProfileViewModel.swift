import MallCore
import Observation

/// Owned by one profile-page identity. App remains the owner of account snapshots.
@MainActor @Observable
final class ProfileViewModel {
    private(set) var busy = false
    private(set) var error: String?
    private let session: any AccountSession
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0

    init(session: any AccountSession) { self.session = session }
    func refresh() { perform { [session] in try await session.refreshProfile() } }
    func logout() { perform { [session] in try await session.logout() } }
    func stop() {
        generation &+= 1
        task?.cancel(); task = nil; busy = false
    }
    private func perform(_ operation: @escaping @Sendable () async throws -> Void) {
        guard !busy else { return }
        generation &+= 1
        let epoch = generation
        busy = true; error = nil
        task = Task {
            do { try await operation() } catch {
                guard generation == epoch, !Task.isCancelled else { return }
                if !(error is CancellationError) { self.error = accountMessage(error) }
            }
            guard generation == epoch, !Task.isCancelled else { return }
            busy = false
        }
    }
}
