import Foundation

/// One ordered page; nil nextPage means the server pagination is exhausted.
public struct ProductReviewPage: Equatable, Sendable {
    public let items: [ProductDetailReview]
    public let nextPage: Int?
    public init(items: [ProductDetailReview], nextPage: Int?) {
        self.items = items; self.nextPage = nextPage
    }
}

/// Anonymous, uncached numbered review reads. Throws ProductDetailLoadFailure;
/// invalid product IDs/configuration fail before I/O, cancellation stays CancellationError.
public protocol ProductReviewsLoading: Sendable {
    func loadReviews(productID: Int64, page: Int, pageSize: Int) async throws -> ProductReviewPage
}
