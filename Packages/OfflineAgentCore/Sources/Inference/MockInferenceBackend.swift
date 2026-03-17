import Foundation

/// A deterministic backend used for the initial iOS inference spike.
/// Replace with CoreML / llama.cpp backend once model artifacts are available.
public struct MockInferenceBackend: InferenceBackend {
    public init() {}

    public func stream(
        request: InferenceRequest,
        onDelta: @Sendable @escaping (String) -> Void,
        cancellation: CancellationToken
    ) async throws {
        let prefix: String = {
            switch request.mode {
            case .work:
                return "（工作模式）"
            case .companion:
                return "（陪伴模式）"
            }
        }()

        let actionHint = " 动作：\(request.action.rawValue)。"

        let content = """
        \(prefix)\(actionHint)
        System: \(request.systemPrompt)

        你刚才说：\(request.userText)

        下一步：我会在离线推理链路接入后，替换此mock为真实Gemma流式输出。
        """

        // Stream by grapheme clusters so中文也逐字输出
        var idx = content.startIndex
        while idx < content.endIndex {
            if cancellation.isCancelled || Task.isCancelled {
                throw InferenceError.cancelled
            }
            let next = content.index(after: idx)
            let chunk = String(content[idx..<next])
            onDelta(chunk)
            idx = next
            try await Task.sleep(nanoseconds: 22_000_000) // ~22ms
        }
    }

}

