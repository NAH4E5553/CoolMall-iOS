import Foundation
import MallCore

/// Pinned, licensed local data. No key, runtime HTTP or location permission.
public struct BundledAddressRegions: AddressRegionsLoading {
    public init() {}
    public func loadRegions() async throws -> [AddressRegion] {
        try Task.checkCancellation()
        guard let url = Bundle.module.url(forResource: "AddressRegions", withExtension: "json")
        else { throw PageReadFailure.invalidResponse }
        return try await Task.detached(priority: .userInitiated) {
            let bytes = try Data(contentsOf: url)
            let nodes = try JSONDecoder().decode([RegionDTO].self, from: bytes)
            var ids = Set<String>()
            func map(_ values: [RegionDTO], depth: Int) throws -> [AddressRegion] {
                guard !values.isEmpty, depth <= 3 else { throw PageReadFailure.invalidResponse }
                return try values.map { node in
                    guard node.code.count == 6, !node.name.isEmpty, ids.insert(node.code).inserted,
                        depth == 3
                            ? node.children?.isEmpty ?? true : node.children?.isEmpty == false
                    else { throw PageReadFailure.invalidResponse }
                    return AddressRegion(
                        id: node.code, name: node.name,
                        children: depth == 3 ? [] : try map(node.children ?? [], depth: depth + 1))
                }
            }
            return try map(nodes, depth: 1)
        }.value
    }
}
private struct RegionDTO: Decodable {
    let code: String; let name: String; let children: [RegionDTO]?
}
