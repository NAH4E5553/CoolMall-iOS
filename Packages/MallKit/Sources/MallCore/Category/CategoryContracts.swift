import Foundation

/// CATEGORY-01 read contract: one cancellable read of the flat category list
/// (A-GOODS-01 `POST goods/type/list`). No paging, credentials, cache, retry or
/// tree construction behind this protocol; the page model owns tree/selection.
public protocol CategoryLoading: Sendable {
    func loadCategories() async throws -> [CategoryNode]
}

/// One read-only category node projected from the flat response. `sortNum` is
/// the reference ordering value (absent in the home `HomeCategory` type);
/// `parentID == nil` marks a root. Display uses roots and their DIRECT children
/// only; deeper/unknown-parent nodes stay in the payload but are not rendered.
public struct CategoryNode: Equatable, Sendable {
    public let id: Int64
    public let name: String
    public let parentID: Int64?
    public let sortNum: Int
    public let imageURL: URL?

    public init(id: Int64, name: String, parentID: Int64?, sortNum: Int, imageURL: URL?) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.sortNum = sortNum
        self.imageURL = imageURL
    }
}

/// Recoverable category read failures surfaced to the page model. Mirrors the
/// H0 failure vocabulary without reusing `HomeLoadFailure` (separate endpoint
/// and page); carries no raw body, URL, token or backend message.
public enum CategoryLoadFailure: Error, Equatable, Sendable {
    case networkUnavailable
    case timeout
    case httpStatus(Int)
    case businessCode(Int)
    case invalidConfiguration
    case invalidResponse
    case invalidPayload
}
