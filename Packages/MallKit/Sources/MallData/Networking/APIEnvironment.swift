import Foundation

/// Fixed endpoint configuration for H0 v0.2. The App owns the only instance;
/// there is no user-facing environment switch and no fallback service.
/// The service validates scheme/host/trailing-slash and finite positive
/// timeouts before any request (see Endpoint).
public struct APIEnvironment: Equatable, Sendable {
    public let baseURL: URL
    public let requestTimeout: TimeInterval
    public let resourceTimeout: TimeInterval

    public init(baseURL: URL, requestTimeout: TimeInterval = 10, resourceTimeout: TimeInterval = 30)
    {
        self.baseURL = baseURL
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
    }
}
