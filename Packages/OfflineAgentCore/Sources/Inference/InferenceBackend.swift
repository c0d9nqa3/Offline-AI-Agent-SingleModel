import Foundation

public protocol InferenceBackend: Sendable {
    func stream(
        request: InferenceRequest,
        onDelta: @Sendable @escaping (String) -> Void,
        cancellation: CancellationToken
    ) async throws
}

public final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled
    }

    public func cancel() {
        lock.lock()
        _isCancelled = true
        lock.unlock()
    }
}

