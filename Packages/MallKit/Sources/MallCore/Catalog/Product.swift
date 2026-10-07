import Foundation

/// F0's minimal business value, independent of HTTP and persistence schemas.
public struct Product: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let title: String
    public init(id: Int64, title: String) { self.id = id; self.title = title }
}

/// Reads one product. Missing products and failures throw; cancellation propagates.
public protocol ProductLoading: Sendable {
    func product(id: Int64) async throws -> Product
}
