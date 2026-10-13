import Foundation

/// Limits are bytes; a zero disk limit explicitly selects memory-only caching.
public struct MallImageConfiguration: Sendable {
    public let memoryLimitBytes: Int
    public let diskLimitBytes: Int
    public let cacheNamespace: String

    public init(
        memoryLimitBytes: Int = 33_554_432, diskLimitBytes: Int = 134_217_728,
        cacheNamespace: String
    ) {
        self.memoryLimitBytes = memoryLimitBytes
        self.diskLimitBytes = diskLimitBytes
        self.cacheNamespace = cacheNamespace
    }

    enum Invalid: Error { case limits, namespace }

    func validate() throws {
        guard memoryLimitBytes > 0, diskLimitBytes >= 0 else { throw Invalid.limits }
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard (1...64).contains(cacheNamespace.utf8.count),
            cacheNamespace.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else { throw Invalid.namespace }
    }

    static func allows(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
            url.user == nil, url.password == nil
        else { return false }
        return true
    }
}
