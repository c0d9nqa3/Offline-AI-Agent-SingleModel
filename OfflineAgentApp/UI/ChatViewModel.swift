import Foundation
import Combine
import OfflineAgentCore

struct CommandPaletteItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let command: String
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var mode: ChatMode = .work
    @Published var isSpeakerOn: Bool = true
    @Published var isBellOn: Bool = true
    @Published var inputText: String = ""
    @Published private(set) var messages: [ChatMessage] = []
    @Published var isSettingsPresented: Bool = false

    var activeFrequency: String { "中" }
    var selectedQuantization: String { "INT8（默认）" }

    private let inference: InferenceService
    private let logger: LocalLogger
    private let wiper: DataWiper
    private let router = PromptRouter()
    private let conversationService = ConversationService()
    private var currentTask: Task<Void, Never>?

    init(inference: InferenceService, logger: LocalLogger, wiper: DataWiper) {
        self.inference = inference
        self.logger = logger
        self.wiper = wiper
        self.messages = [
            ChatMessage(role: .assistant, text: "你好，我是离线助手。你可以直接聊天，或输入“翻译/修图/设置/记忆清空”。")
        ]
        logger.log("app_start")
    }

    func toggleMode() {
        mode = (mode == .work) ? .companion : .work
    }

    var isCommandPaletteVisible: Bool {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines) == "/"
    }

    var commandPaletteItems: [CommandPaletteItem] {
        [
            CommandPaletteItem(title: "翻译", command: "/translate"),
            CommandPaletteItem(title: "修图", command: "/photo"),
            CommandPaletteItem(title: "文字增强", command: "/enhance"),
            CommandPaletteItem(title: "设置", command: "/settings"),
            CommandPaletteItem(title: "记忆清空", command: "/wipe"),
        ]
    }

    func applyCommandPaletteItem(_ item: CommandPaletteItem) {
        switch item.command {
        case "/settings":
            inputText = ""
            isSettingsPresented = true
        default:
            inputText = item.command + " "
        }
    }

    func sendCurrentText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""

        cancelGeneration()

        logger.log("user_input len=\(text.count)")

        if text == "确认清空" {
            do {
                try wiper.wipeAll()
                messages.append(ChatMessage(role: .assistant, text: "已清空所有本地数据（不可恢复）。"))
                logger.log("wipe_all success")
            } catch {
                messages.append(ChatMessage(role: .assistant, text: "清空失败：\(error.localizedDescription)"))
                logger.log("wipe_all failed")
            }
            return
        }
        if text == "取消" {
            messages.append(ChatMessage(role: .assistant, text: "已取消。"))
            return
        }

        let route = router.route(userText: text, currentMode: mode)
        mode = route.mode

        if route.action == .settings {
            isSettingsPresented = true
            return
        }

        if route.action == .wipeMemory {
            messages.append(ChatMessage(role: .assistant, text: "将清空所有本地记忆且不可恢复。请回复“确认清空”以继续，或回复“取消”。"))
            return
        }

        messages.append(ChatMessage(role: .user, text: text))
        let assistantId = UUID()
        messages.append(ChatMessage(id: assistantId, role: .assistant, text: ""))

        currentTask = Task { [weak self] in
            guard let self else { return }

            let systemPrompt = self.conversationService.systemPrompt(for: self.mode, action: route.action)
            let request = InferenceRequest(
                userText: route.cleanedUserText.isEmpty ? text : route.cleanedUserText,
                mode: self.mode,
                action: route.action,
                systemPrompt: systemPrompt,
                conversation: self.messages
            )

            do {
                try await self.inference.stream(request: request) { [weak self] delta in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let idx = self.messages.firstIndex(where: { $0.id == assistantId }) {
                            self.messages[idx].text.append(delta)
                        }
                    }
                }
                self.logger.log("assistant_done action=\(route.action.rawValue)")
            } catch {
                if let idx = self.messages.firstIndex(where: { $0.id == assistantId }) {
                    self.messages[idx].text = "（生成失败）\(error.localizedDescription)"
                }
                self.logger.log("assistant_failed action=\(route.action.rawValue)")
            }
        }
    }

    func cancelGeneration() {
        currentTask?.cancel()
        currentTask = nil
        inference.cancelCurrentGeneration()
    }
}

