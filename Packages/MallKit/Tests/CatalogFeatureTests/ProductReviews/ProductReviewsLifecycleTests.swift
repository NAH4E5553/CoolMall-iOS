import Foundation
import MallCore
@testable import CatalogFeature
import SwiftUI
import Testing

@MainActor
struct ProductReviewsLifecycleTests {
    @Test func realEntryRemovalCancelsItsActualRead() async throws {
        let service = ProductReviewsViewModelTests.Service([.gate(cooperative: true)])
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let host = UIHostingController(
            rootView:
                ProductReviewsEntryView(productID: 830001, loader: service, isActive: true)
                .environment(\.scenePhase, .active))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.rootViewController = nil; window.isHidden = true }
        let started = try await wait { service.gates[0] != nil }
        try #require(started, "the actual mounted Entry must reach the service")
        #expect(service.calls.count == 1); #expect(service.cancellations.isEmpty)
        // Remove the real Entry. No test-side task.cancel or VM visibility call.
        window.rootViewController = nil; host.view.removeFromSuperview(); window.isHidden = true
        let cancelled = try await wait { service.cancellations.contains(0) }
        #expect(cancelled); #expect(service.cancellations == [0]); #expect(service.gates.isEmpty)
        // Explicit active Scene injection only: this tests removal, not OS background delivery.
    }
    @Test func realEntryRemovalCancelsAppendAfterInitialReadCommits() async throws {
        let service = ProductReviewsViewModelTests.Service([
            .value(ProductReviewsViewModelTests.page([1], next: 2)), .gate(cooperative: true),
        ])
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let host = UIHostingController(
            rootView:
                ProductReviewsEntryView(productID: 830001, loader: service, isActive: true)
                .environment(\.scenePhase, .active))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.rootViewController = nil; window.isHidden = true }
        // Short real content makes the actual footer visible. Its production
        // callback starts a distinct append generation after the initial read commits.
        // The stale initial caller cannot cancel this newer generation.
        let appended = try await wait { service.gates[1] != nil }
        try #require(appended, "actual visible tail must start page2")
        #expect(service.calls.map(\.page) == [1, 2]); #expect(service.cancellations.isEmpty)
        window.rootViewController = nil; host.view.removeFromSuperview(); window.isHidden = true
        let cancelled = try await wait { service.cancellations.contains(1) }
        #expect(cancelled); #expect(service.cancellations == [1]); #expect(service.gates.isEmpty)
        #expect(service.calls.count == 2)
    }
    private func wait(_ condition: () -> Bool) async throws -> Bool {
        let clock = ContinuousClock(); let end = clock.now.advanced(by: .seconds(2))
        while !condition(), clock.now < end { try await Task.sleep(for: .milliseconds(1)) }
        return condition()
    }
}
