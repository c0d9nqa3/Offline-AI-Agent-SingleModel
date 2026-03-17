import Foundation

public struct AppPaths: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public static func `default`() throws -> AppPaths {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = appSupport.appendingPathComponent("OfflineAgent", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return AppPaths(rootURL: root)
    }

    public var dbURL: URL { rootURL.appendingPathComponent("offline_agent.sqlite", isDirectory: false) }
    public var encryptedVectorIndexURL: URL { rootURL.appendingPathComponent("faiss_index.enc", isDirectory: false) }
    public var logURL: URL { rootURL.appendingPathComponent("logs.txt", isDirectory: false) }
}

