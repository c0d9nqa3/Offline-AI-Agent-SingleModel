import Foundation

public final class LocalLogger: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()

    public init(url: URL) {
        self.url = url
    }

    public func log(_ event: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(event)\n"
        lock.lock()
        defer { lock.unlock() }

        do {
            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: [.atomic])
            }
        } catch {
            // best-effort: never crash
        }
    }

    public func readAll(maxBytes: Int = 100 * 1024 * 1024) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if let data = try? Data(contentsOf: url), data.count <= maxBytes {
            return data
        }
        return nil
    }

    public func delete() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url)
    }

    public var fileURL: URL { url }
}

