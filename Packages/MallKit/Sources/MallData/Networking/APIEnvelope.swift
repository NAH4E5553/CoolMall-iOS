import Foundation
import MallCore

/// Envelope header consumed before any body decoding: `code` is a required
/// Int; missing/null/wrong-type code, empty body, bad JSON or a non-object
/// body are all invalidResponse. `message` is never consumed.
struct EnvelopeHeader: Decodable {
    let code: Int
}

/// Success envelope; `data` carries the payload (absent/null → invalidPayload
/// at the H0 layer, never a silent empty home).
struct Envelope<Body: Decodable>: Decodable {
    let data: Body?
}

/// Shared H0 envelope interpretation used by both the HTTP service and the
/// bundled fixture service, so both run through the exact same decoding and
/// mapping path.
enum HomeEnvelopeDecoder {
    /// Full pass: HTTP-layer header check, then body decode + field mapping.
    static func snapshot(from data: Data) throws -> HomeSnapshot {
        let body = try body(from: data)
        return try HomeMapper.snapshot(from: body)
    }

    /// Header first: required integer code; non-1000 → businessCode without
    /// touching data. Only code==1000 decodes the body; data must be present
    /// and object-shaped.
    static func body(from data: Data) throws -> HomeDTO {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(EnvelopeHeader.self, from: data) else {
            throw HomeLoadFailure.invalidResponse
        }
        guard header.code == 1000 else { throw HomeLoadFailure.businessCode(header.code) }
        do {
            let envelope = try decoder.decode(Envelope<HomeDTO>.self, from: data)
            guard let body = envelope.data else { throw HomeLoadFailure.invalidPayload }
            return body
        } catch let failure as HomeLoadFailure {
            throw failure
        } catch {
            throw HomeLoadFailure.invalidPayload
        }
    }
}
