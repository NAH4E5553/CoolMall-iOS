import Foundation
import MallCore
import SwiftUI
@testable import CatalogFeature
import Testing

/// Executes the real view-owned .task and selection mutator. Only the clock
/// is virtual; no test computes or selects the next carousel page.
@MainActor
@Suite(.serialized)
struct HomeBannerProductionTimingTests {
    actor Sleeper {
        struct Wait: Sendable {
            let id: Int
            let taskIdentity: Int?
            let deadline: ContinuousClock.Instant
            var cancelled = false
        }
        private var nextID = 0
        private var waits: [Int: (Wait, CheckedContinuation<Void, any Error>)] = [:]
        private(set) var registered: [Wait] = []
        private(set) var cancellations: [Int] = []
        var ignoresCancellation: Bool
        private var time: ContinuousClock.Instant

        init(now: ContinuousClock.Instant, ignoresCancellation: Bool) {
            time = now
            self.ignoresCancellation = ignoresCancellation
        }

        func sleep(until deadline: ContinuousClock.Instant) async throws {
            nextID += 1
            let id = nextID
            let taskIdentity = withUnsafeCurrentTask { $0?.hashValue }
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let wait = Wait(id: id, taskIdentity: taskIdentity, deadline: deadline)
                    registered.append(wait)
                    waits[id] = (wait, continuation)
                    if Task.isCancelled { cancel(id) } else if deadline <= time { release(id) }
                }
            } onCancel: {
                Task { await self.cancel(id) }
            }
        }

        private func cancel(_ id: Int) {
            guard !cancellations.contains(id) else { return }
            cancellations.append(id)
            guard var value = waits[id] else { return }
            value.0.cancelled = true
            waits[id] = value
            if !ignoresCancellation {
                waits.removeValue(forKey: id)?.1.resume(throwing: CancellationError())
            }
        }

        func advance(to now: ContinuousClock.Instant) {
            time = now
            for id in waits.keys.sorted() where waits[id]!.0.deadline <= time { release(id) }
        }

        func release(_ id: Int) { waits.removeValue(forKey: id)?.1.resume() }
        func pending() -> [Wait] { waits.values.map(\.0).sorted { $0.id < $1.id } }
        func finish() {
            for id in waits.keys.sorted() {
                waits.removeValue(forKey: id)?.1.resume(throwing: CancellationError())
            }
        }
    }

    @MainActor
    final class ClockDriver {
        let epoch = ContinuousClock().now
        var elapsed = Duration.zero
        var now: ContinuousClock.Instant { epoch.advanced(by: elapsed) }
        let sleeper: Sleeper
        var events: [BannerAuditEvent] = []
        let runID = "host-production-" + UUID().uuidString
        init(ignoresCancellation: Bool = false) {
            sleeper = Sleeper(now: epoch, ignoresCancellation: ignoresCancellation)
        }
        var timing: BannerTiming {
            BannerTiming(
                now: { self.now }, sleepUntil: { [sleeper] in try await sleeper.sleep(until: $0) },
                monotonicTime: {
                    1000 + Double(self.elapsed.components.seconds)
                        + Double(self.elapsed.components.attoseconds) / 1e18
                })
        }
        var sink: BannerAuditSink {
            BannerAuditSink(runID: runID) {
                self.events.append($0)
                if let data = try? JSONEncoder().encode($0),
                    let line = String(data: data, encoding: .utf8)
                {
                    NSLog("BANNERHOST %@", line)
                }
            }
        }
        func advance(_ duration: Duration) async {
            elapsed += duration
            await sleeper.advance(to: now)
        }
        var commits: [BannerAuditEvent] { events.filter { $0.event == "advanceCommit" } }
    }

    private struct Shell: View {
        let driver: ClockDriver
        var active = true
        var scene = ScenePhase.active
        var dragging = false
        var viewport = CGRect(x: 0, y: 0, width: 390, height: 844)
        var body: some View {
            HomeBannerCarouselView(
                banners: (1...3).map {
                    HomeBanner(id: Int64($0), description: "B\($0)", imageURL: nil)
                },
                imagePipeline: nil, isActive: active,
                visibleViewport: viewport, isUserDragging: dragging
            )
            .environment(\.scenePhase, scene)
            .environment(\.bannerTiming, driver.timing)
            .environment(\.bannerAuditSink, driver.sink)
        }
    }

    private func mount(_ driver: ClockDriver) -> (UIHostingController<Shell>, UIWindow) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let host = UIHostingController(rootView: Shell(driver: driver))
        window.rootViewController = host
        window.makeKeyAndVisible()
        return (host, window)
    }

    private func remove(_ host: UIHostingController<Shell>, _ window: UIWindow) {
        window.rootViewController = nil
        host.view.removeFromSuperview()
        window.isHidden = true
    }

    /// Cleanup runs only after the scenario's assertions, including a thrown
    /// requirement. Finishing ignored waiters is resource disposal, never the
    /// evidence for the production cancellation assertion above it.
    private func withHost(
        _ driver: ClockDriver,
        operation: (UIHostingController<Shell>, UIWindow) async throws -> Void
    ) async throws {
        let (host, window) = mount(driver)
        do {
            try await operation(host, window)
        } catch {
            remove(host, window)
            await driver.sleeper.finish()
            throw error
        }
        remove(host, window)
        await driver.sleeper.finish()
    }

    /// Polls a concrete acknowledgement with a bounded host budget. Product
    /// time never advances during this wait and no fixed settle is inserted.
    private func acknowledged(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock().now.advanced(by: .seconds(2))
        while !(await condition()), ContinuousClock().now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(await condition(), "production host acknowledgement missing")
    }

    private func armed(_ driver: ClockDriver) async throws -> Sleeper.Wait {
        try await acknowledged { await driver.sleeper.pending().contains { !$0.cancelled } }
        let wait = try #require(await driver.sleeper.pending().last { !$0.cancelled })
        try #require(
            wait.taskIdentity != nil, "the actual production Swift task must register its identity")
        return wait
    }

    private enum PauseReason: CaseIterable {
        case home, scene, drag, offscreen
        func matches(_ gate: BannerGateSnapshot) -> Bool {
            switch self {
            case .home: !gate.homeActive
            case .scene: !gate.sceneActive
            case .drag: gate.drag
            case .offscreen: !gate.visible
            }
        }
        func shell(_ driver: ClockDriver) -> Shell {
            switch self {
            case .home: Shell(driver: driver, active: false)
            case .scene: Shell(driver: driver, scene: .background)
            case .drag: Shell(driver: driver, dragging: true)
            case .offscreen:
                Shell(driver: driver, viewport: CGRect(x: 0, y: 2000, width: 390, height: 844))
            }
        }
    }

    private func pause(
        _ driver: ClockDriver, _ host: UIHostingController<Shell>, original: Int,
        reason: PauseReason = .home
    ) async throws {
        host.rootView = reason.shell(driver)
        try await acknowledged {
            driver.events.contains { $0.event == "rawInput" && reason.matches($0.gate) }
        }
        // N01 must reach this cancellation assertion using raw input delivery,
        // never wait for a replacement task that its fault intentionally blocks.
        let deadline = ContinuousClock().now.advanced(by: .seconds(2))
        while !(await driver.sleeper.cancellations.contains(original)),
            ContinuousClock().now < deadline
        {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(
            await driver.sleeper.cancellations.contains(original),
            "P02 missing original sleeper cancellation after raw inactive input")
    }

    @Test func P01DeadlineBeforeAndAtAdvanceActualSelection() async throws {
        let driver = ClockDriver()
        try await withHost(driver) { host, window in
            let wait = try await armed(driver)
            #expect(wait.deadline == driver.epoch.advanced(by: .seconds(5)))
            await driver.advance(.nanoseconds(4_999_999_999))
            #expect(driver.commits.isEmpty)
            #expect(driver.events.last?.selectedID == 1)
            await driver.advance(.nanoseconds(1))
            try await acknowledged { driver.commits.count == 1 }
            #expect(driver.commits[0].selectedID == 2)
            #expect(driver.commits[0].advanceSequence == 1)
            #expect(driver.commits[0].selectionRevision == 2)
            _ = try await armed(driver)
            #expect(driver.commits.count == 1)
            let committedTask = driver.commits[0].taskID
            #expect(
                driver.events.filter { $0.taskID == committedTask }.allSatisfy {
                    $0.event == "taskEntry" || $0.deadline == 1005 && $0.deadlineUpper == 1005
                })
        }
    }

    @Test func P02PauseCancelsProductionWaitAndRejectsLateWake() async throws {
        for ignoresCancellation in [false, true] {
            let driver = ClockDriver(ignoresCancellation: ignoresCancellation)
            try await withHost(driver) { host, window in
                let wait = try await armed(driver)
                try await pause(driver, host, original: wait.id)
                await driver.advance(.seconds(60))
                if ignoresCancellation {
                    try await acknowledged { driver.events.contains { $0.event == "reject" } }
                } else {
                    try await acknowledged { driver.events.contains { $0.event == "cancel" } }
                }
                #expect(driver.commits.isEmpty)
                #expect(driver.events.last?.selectedID == 1)
            }
        }
    }

    @Test func P03ReturnArmsNewFullPeriodWithoutCatchup() async throws {
        for reason in PauseReason.allCases {
            let driver = ClockDriver(ignoresCancellation: true)
            try await withHost(driver) { host, window in
                let old = try await armed(driver)
                try await pause(driver, host, original: old.id, reason: reason)
                await driver.advance(.seconds(60))
                try await acknowledged { driver.events.contains { $0.event == "reject" } }
                host.rootView = Shell(driver: driver)
                let resumed = try await armed(driver)
                #expect(resumed.id != old.id)
                #expect(resumed.deadline == driver.now.advanced(by: .seconds(5)))
                #expect(driver.commits.isEmpty, "P03 resume must not commit immediately")
                await driver.advance(.nanoseconds(4_999_999_999))
                #expect(driver.commits.isEmpty, "P03 predeadline actual selection changed")
                await driver.advance(.nanoseconds(1))
                try await acknowledged { driver.commits.count == 1 }
                #expect(driver.commits[0].selectedID == 2)
                #expect(driver.commits[0].advanceSequence == 1)
            }
        }
    }

    @Test func P04RapidPauseReturnHasOneCurrentTaskAndNoDuplicateCommit() async throws {
        let driver = ClockDriver(ignoresCancellation: true)
        try await withHost(driver) { host, window in
            let old = try await armed(driver)
            await driver.advance(.seconds(1))
            try await pause(driver, host, original: old.id)
            // Resume is queued while the cancelled old sleep deliberately remains
            // unresolved. No yield is inserted to turn an undelivered edge into one.
            host.rootView = Shell(driver: driver)
            let resumed = try await armed(driver)
            let pending = await driver.sleeper.pending()
            #expect(pending.filter { !$0.cancelled }.count == 1)
            #expect(Set(pending.filter { !$0.cancelled }.compactMap(\.taskIdentity)).count == 1)
            #expect(old.taskIdentity != resumed.taskIdentity)
            #expect(pending.contains { $0.id == old.id && $0.cancelled })
            #expect(resumed.id != old.id)
            await driver.advance(.seconds(4))
            try await acknowledged { driver.events.contains { $0.event == "reject" } }
            #expect(driver.commits.isEmpty)
            await driver.advance(.seconds(1))
            try await acknowledged { !driver.commits.isEmpty }
            let next = try await armed(driver)
            #expect(driver.commits.count == 1, "P04 duplicate actual production deadline commit")
            #expect(driver.commits.last?.advanceSequence == 1)
            #expect(driver.commits.last?.selectedID == 2)
            #expect(next.deadline == driver.now.advanced(by: .seconds(5)))
            let entries = driver.events.filter { $0.event == "taskEntry" }
            #expect(Set(entries.compactMap(\.taskID)).count == entries.count)
            #expect(driver.events.contains { $0.event == "rawInput" && !$0.gate.homeActive })
            #expect(driver.events.contains { $0.event == "taskEntry" && !$0.gate.homeActive })
            #expect(
                driver.events.contains {
                    $0.event == "taskEntry" && $0.gate.homeActive && $0.inputRevision > 1
                })
        }
    }

    @Test func P05RealHostRemovalCancelsAutoplayWait() async throws {
        let driver = ClockDriver(ignoresCancellation: true)
        try await withHost(driver) { host, window in
            let wait = try await armed(driver)
            remove(host, window)
            try await acknowledged { await driver.sleeper.cancellations.contains(wait.id) }
            await driver.advance(.seconds(30))
            try await acknowledged { driver.events.contains { $0.event == "reject" } }
            #expect(driver.commits.isEmpty)
        }
    }

    @Test func P06HiddenFullCycleStillFailsAudit() async throws {
        let driver = ClockDriver()
        try await withHost(driver) { host, window in
            _ = try await armed(driver)
            host.rootView = Shell(driver: driver, active: false, scene: .background)
            try await acknowledged {
                driver.events.contains {
                    $0.event == "rawInput" && !$0.gate.homeActive && !$0.gate.sceneActive
                }
            }
            let baseline = try #require(
                driver.events.last {
                    $0.event == "rawInput" && !$0.gate.homeActive && !$0.gate.sceneActive
                })
            for _ in 0..<3 {
                await driver.advance(.seconds(5))
                // A production negative which ignores lifecycle gates must run its
                // real commit and next structured wait before the next clock step.
                // The positive path instead acknowledges the ineligible task entry.
                try await acknowledged {
                    let waits = await driver.sleeper.pending()
                    let paused = driver.events.contains {
                        $0.event == "arm" && !$0.gate.homeActive && $0.deadline == nil
                    }
                    let advancedAndRearmed =
                        driver.commits.last?.monotonicTime
                        == 1000 + Double(driver.elapsed.components.seconds)
                        && waits.contains {
                            !$0.cancelled && $0.deadline == driver.now.advanced(by: .seconds(5))
                        }
                    return paused && waits.isEmpty || advancedAndRearmed
                }
            }
            if !driver.commits.isEmpty { #expect(driver.commits.count == 3) }
            #expect(
                driver.events.last?.selectedID == baseline.selectedID, "old initial/final ID check")
            let hiddenCommits = driver.events.filter {
                $0.event == "advanceCommit" && $0.eventSequence > baseline.eventSequence
            }
            #expect(
                hiddenCommits.isEmpty,
                "P06 lifecycle audit rejects actual hidden production commits including full wrap")
            #expect(
                driver.events.last?.advanceSequence == baseline.advanceSequence,
                "P06 hidden advance counter delta")
        }
    }
}
