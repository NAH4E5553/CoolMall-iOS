import Foundation
import MallCore

/// Deterministic fixture service over the bundled home.json (the H0-VALID
/// pure envelope). DEBUG previews/UI tests only; it runs the same envelope
/// decoding and mapping as the HTTP service and never replaces the Release
/// HTTP service.
public final class FixtureHomeService: HomeLoading, Sendable {
    private let payload: Data

    public init() {
        if let url = Bundle.module.url(forResource: "home", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        {
            payload = data
        } else {
            // The fixture ships with the module; a missing resource is a build
            // defect and surfaces as invalidResponse, never as fake success.
            payload = Data()
        }
    }

    public func loadHome() async throws -> HomeSnapshot {
        try HomeEnvelopeDecoder.snapshot(from: payload)
    }
}
