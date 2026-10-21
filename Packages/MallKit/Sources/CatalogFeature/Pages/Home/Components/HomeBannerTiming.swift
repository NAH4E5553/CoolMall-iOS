import Foundation
import SwiftUI

/// Narrow dependency of the view-owned structured task. Live behavior retains
/// ContinuousClock and its default sleep tolerance; tests replace only time.
struct BannerTiming: Sendable {
    var now: @MainActor @Sendable () -> ContinuousClock.Instant
    var sleepUntil: @Sendable (ContinuousClock.Instant) async throws -> Void
    var monotonicTime: @MainActor @Sendable () -> Double

    static let live = BannerTiming(
        now: { ContinuousClock().now },
        sleepUntil: { try await ContinuousClock().sleep(until: $0) },
        monotonicTime: { ProcessInfo.processInfo.systemUptime })
}

private struct BannerTimingKey: EnvironmentKey {
    static let defaultValue = BannerTiming.live
}

extension EnvironmentValues {
    var bannerTiming: BannerTiming {
        get { self[BannerTimingKey.self] }
        set { self[BannerTimingKey.self] = newValue }
    }
}

#if DEBUG
    struct BannerGateSnapshot: Codable, Equatable, Sendable {
        let homeActive: Bool
        let sceneActive: Bool
        let drag: Bool
        let visible: Bool
        let allowed: Bool
        let reduceMotion: Bool
        let voiceOver: Bool
        let count: Int
        let frame: [Double]
        let viewport: [Double]
    }

    struct BannerAuditEvent: Codable, Sendable {
        var schemaVersion = 1
        let runID: String
        var origin = "carousel"
        let processID: Int32
        let instanceID: String
        let eventSequence: UInt64
        let monotonicTime: Double
        let inputRevision: UInt64
        let taskID: String?
        let generation: UInt64
        let event: String
        let selectedID: Int64?
        let selectionRevision: UInt64
        let advanceSequence: UInt64
        /// Monotonic measurement bounds around the real restart clock sample.
        /// The production ContinuousClock deadline is never derived from these.
        let deadline: Double?
        let deadlineUpper: Double?
        let gate: BannerGateSnapshot
        let previousGate: BannerGateSnapshot?
        let oldSelectedID: Int64?
        let cause: String?
    }

    struct BannerAuditSink: Sendable {
        let runID: String
        var receive: @MainActor @Sendable (BannerAuditEvent) -> Void

        static var launchConfigured: BannerAuditSink? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "--ui-banner-audit-run-id"),
                arguments.indices.contains(index + 1), !arguments[index + 1].isEmpty
            else { return nil }
            return BannerAuditSink(runID: arguments[index + 1]) { event in
                do {
                    let data = try JSONEncoder().encode(event)
                    guard let line = String(data: data, encoding: .utf8) else {
                        NSLog("BANNERAUDIT_ERROR invalid-utf8")
                        return
                    }
                    NSLog("BANNERAUDIT %@", line)
                } catch { NSLog("BANNERAUDIT_ERROR %@", String(describing: error)) }
            }
        }
    }

    private struct BannerAuditSinkKey: EnvironmentKey {
        static let defaultValue: BannerAuditSink? = .launchConfigured
    }

    extension EnvironmentValues {
        var bannerAuditSink: BannerAuditSink? {
            get { self[BannerAuditSinkKey.self] }
            set { self[BannerAuditSinkKey.self] = newValue }
        }
    }

    /// Diagnostic ledger only. It never supplies an autoplay business guard.
    @MainActor
    final class BannerAuditLedger {
        let instanceID = UUID().uuidString
        var sequence: UInt64 = 0
        private var inputs: [BannerGateSnapshot] = []
        var rawGate: BannerGateSnapshot?
        private var latestTaskID: String?
        private var deadlines: [String: (lower: Double, upper: Double)] = [:]

        func recordDeadline(taskID: String, lower: Double?, upper: Double?) {
            latestTaskID = taskID
            if let lower, let upper {
                deadlines[taskID] = (lower, upper)
            } else {
                deadlines[taskID] = nil
            }
        }

        func deadline(for taskID: String?) -> (lower: Double, upper: Double)? {
            guard let id = taskID ?? latestTaskID else { return nil }
            return deadlines[id]
        }

        func revision(for gate: BannerGateSnapshot) -> UInt64 {
            // Consecutive equal observations share a revision. A return to an
            // earlier gate is a new input, preserving the pause/resume transcript.
            if inputs.last != gate { inputs.append(gate) }
            return UInt64(inputs.count)
        }
    }
#endif
