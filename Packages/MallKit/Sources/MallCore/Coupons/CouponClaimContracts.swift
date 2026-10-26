import Foundation

/// Display intent only; it is not an owned coupon or proof of claimability.
public struct CouponClaimOffer: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let title: String
    public let description: String
    public let amountYuan: Decimal?
    public let minimumSpendYuan: Decimal?
    public let endTime: String?
    public init(
        id: Int64, title: String, description: String = "", amountYuan: Decimal? = nil,
        minimumSpendYuan: Decimal? = nil, endTime: String? = nil
    ) {
        self.id = id; self.title = title; self.description = description
        self.amountYuan = amountYuan; self.minimumSpendYuan = minimumSpendYuan
        self.endTime = endTime
    }
}
public enum CouponClaimFailure: Error, Equatable, Sendable {
    case invalidConfiguration, authenticationRequired, busy, unconfirmed
    case rejected(Int)
    case rejectedMessage(Int, String)
}
/// One explicit write attempt. No automatic retry/replay or locally invented owned coupon.
/// Success returns the optional server message. Rejections retain their code and message.
/// Cancellation after dispatch cannot establish whether the server committed.
public protocol CouponReceiving: Sendable {
    @discardableResult func receiveCoupon(accountID: Int64, couponID: Int64) async throws -> String?
}
