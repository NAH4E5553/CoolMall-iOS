import Foundation
import MallCore

/// App-owned write adapter. Shared by all Scenes and both catalog entry points.
/// In-flight ownership prevents concurrent duplicate claims; no request is replayed.
public actor HTTPCouponReceiver: CouponReceiving {
    private struct Key: Hashable { let accountID: Int64; let couponID: Int64 }
    private let environment: APIEnvironment
    private let session: any AccountReadAuthorizing
    private let transport: any ProductDetailTransport
    private var inFlight: Set<Key> = []
    public init(environment: APIEnvironment, session: SessionCoordinator) {
        self.init(
            environment: environment, session: session,
            transport: URLSessionTransport(resourceTimeout: environment.resourceTimeout))
    }
    init(
        environment: APIEnvironment, session: any AccountReadAuthorizing,
        transport: any ProductDetailTransport
    ) {
        self.environment = environment; self.session = session; self.transport = transport
    }
    @discardableResult public func receiveCoupon(accountID: Int64, couponID: Int64) async throws
        -> String?
    {
        try Task.checkCancellation()
        guard accountID > 0 else { throw CouponClaimFailure.authenticationRequired }
        guard couponID > 0 else { throw CouponClaimFailure.invalidConfiguration }
        var request: URLRequest
        let context: AccountReadContext
        do {
            request = try CouponHTTP.request(environment, path: "market/coupon/user/receive")
            context = try await session.authorization(
                accountID: accountID, environmentURL: environment.baseURL)
        } catch is CancellationError { throw CancellationError() } catch PageReadFailure
            .authenticationRequired
        { throw CouponClaimFailure.authenticationRequired } catch {
            throw CouponClaimFailure.invalidConfiguration
        }
        try Task.checkCancellation()
        let key = Key(accountID: accountID, couponID: couponID)
        guard inFlight.insert(key).inserted else { throw CouponClaimFailure.busy }
        defer { inFlight.remove(key) }
        struct Command: Encodable { let couponId: Int64 }
        request.httpBody = try JSONEncoder().encode(Command(couponId: couponID))
        request.setValue(context.token, forHTTPHeaderField: "Authorization")
        do {
            let bytes = try await CouponHTTP.body(request, transport: transport)
            #if DEBUG
                diagnose(bytes, couponID: couponID)
            #endif
            guard let header = try? JSONDecoder().decode(EnvelopeHeader.self, from: bytes) else {
                throw CouponClaimFailure.unconfirmed
            }
            struct Message: Decodable { let message: String? }
            let rawMessage = (try? JSONDecoder().decode(Message.self, from: bytes))?.message
            let message = rawMessage.flatMap { value -> String? in
                let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }
            guard header.code == 1000 else {
                if let message { throw CouponClaimFailure.rejectedMessage(header.code, message) }
                throw CouponClaimFailure.rejected(header.code)
            }
            guard let envelope = try? JSONDecoder().decode(Envelope<String>.self, from: bytes),
                envelope.data != nil
            else { throw CouponClaimFailure.unconfirmed }
            try await session.validateAuthorization(context)
            return message
        } catch {
            #if DEBUG
                NSLog(
                    "CouponReceiveDiagnostics coupon=%lld error=%@", couponID,
                    diagnosticError(error))
            #endif
            try await session.validateAuthorization(context)
            if error is CancellationError { throw CancellationError() }
            if let failure = error as? CouponClaimFailure { throw failure }
            if error as? PageReadFailure == .authenticationRequired {
                throw CouponClaimFailure.authenticationRequired
            }
            throw CouponClaimFailure.unconfirmed
        }
    }
    #if DEBUG
        private func diagnosticError(_ error: any Error) -> String {
            if error is CancellationError { return "cancelled" }
            if let failure = error as? CouponClaimFailure {
                switch failure {
                case .rejected(let code), .rejectedMessage(let code, _):
                    return "business-" + String(code)
                case .unconfirmed: return "unconfirmed"
                default: return "claim-preflight"
                }
            }
            if let failure = error as? PageReadFailure {
                switch failure {
                case .httpStatus(let code): return "http-" + String(code)
                case .timeout: return "timeout"
                case .networkUnavailable: return "network-unavailable"
                case .authenticationRequired: return "authentication-required"
                default: return "invalid-response"
                }
            }
            return "other"
        }
        private func diagnose(_ data: Data, couponID: Int64) {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let code = (json?["code"] as? NSNumber)?.stringValue ?? "missing"
            let value = json?["data"]
            let kind: String
            switch value {
            case nil: kind = "missing"
            case is NSNull: kind = "null"
            case is String: kind = "string"
            case is [String: Any]: kind = "object"
            case is [Any]: kind = "array"
            default: kind = "scalar"
            }
            let message = json?["message"] as? String ?? ""
            let category: String
            if message.contains("已领取") || message.contains("重复领取") {
                category = "already-received"
            } else if message.contains("上限") {
                category = "limit"
            } else if message.contains("领完") || message.contains("不足") {
                category = "exhausted"
            } else if message.contains("登录") || message.contains("token") {
                category = "authentication"
            } else if message.contains("过期") {
                category = "expired"
            } else {
                category = "unclassified"
            }
            NSLog(
                "CouponReceiveDiagnostics coupon=%lld code=%@ data=%@ reason=%@", couponID, code,
                kind, category)
            if category == "already-received", message.count <= 48,
                message.unicodeScalars.allSatisfy({
                    (0x4E00...0x9FFF).contains($0.value) || "，。！、： ".unicodeScalars.contains($0)
                })
            {
                NSLog("CouponReceiveDiagnostics coupon=%lld duplicate-reason=%@", couponID, message)
            }
        }
    #endif

}
