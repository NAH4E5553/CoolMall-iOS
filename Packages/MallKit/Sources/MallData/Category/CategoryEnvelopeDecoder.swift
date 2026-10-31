import Foundation
import MallCore

/// Shared envelope interpretation for the category list, reusing the H0 header
/// contract: a required integer `code`; non-1000 fails before body decoding;
/// only code 1000 decodes `data`, which must be a present array.
enum CategoryEnvelopeDecoder {
    static func categories(from data: Data) throws -> [CategoryNode] {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(EnvelopeHeader.self, from: data) else {
            throw CategoryLoadFailure.invalidResponse
        }
        guard header.code == 1000 else {
            throw CategoryLoadFailure.businessCode(header.code)
        }
        do {
            let envelope = try decoder.decode(Envelope<[CategoryDTO]>.self, from: data)
            guard let body = envelope.data else { throw CategoryLoadFailure.invalidPayload }
            return try CategoryMapper.categories(from: body)
        } catch let failure as CategoryLoadFailure {
            throw failure
        } catch {
            throw CategoryLoadFailure.invalidPayload
        }
    }
}
