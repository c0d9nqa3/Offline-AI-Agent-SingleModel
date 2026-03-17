import XCTest
@testable import OfflineAgentCore

final class OfflineAgentCoreTests: XCTestCase {
    actor StringCollector {
        private(set) var value: String = ""
        func append(_ delta: String) { value.append(delta) }
    }

    func testMockInferenceStreamsNonEmpty() async throws {
        let service = InferenceService(backend: MockInferenceBackend())
        let req = InferenceRequest(
            userText: "你好",
            mode: .work,
            action: .chat,
            systemPrompt: "test",
            conversation: []
        )

        let collector = StringCollector()
        try await service.stream(request: req) { delta in
            Task { await collector.append(delta) }
        }
        let out = await collector.value
        XCTAssertFalse(out.isEmpty)
    }
}

