import Foundation

public enum InferenceError: Error, LocalizedError {
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "已取消"
        }
    }
}

public final class InferenceService: @unchecked Sendable {
    private let backend: InferenceBackend
    private let token = CancellationToken()

    public init(backend: InferenceBackend) {
        self.backend = backend
    }

    public func cancelCurrentGeneration() {
        token.cancel()
    }

    /// Streams assistant output incrementally via `onDelta`.
    public func stream(
        request: InferenceRequest,
        onDelta: @Sendable @escaping (String) -> Void
    ) async throws {
        if Task.isCancelled { throw InferenceError.cancelled }
        try await backend.stream(request: request, onDelta: onDelta, cancellation: token)
    }
}

