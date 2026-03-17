import Foundation

public struct ConversationService: Sendable {
    public init() {}

    public func systemPrompt(for mode: ChatMode, action: RoutedAction) -> String {
        let base = """
        你是一个纯离线本地运行的AI Agent。你必须遵守：
        - 不要提及任何云端、联网、上传。
        - 只给出必要、可执行的回答，避免冗余。
        - 如果用户请求“记忆清空”，必须先二次确认。
        """

        let modePrompt: String = {
            switch mode {
            case .work:
                return "当前为工作模式：专业、严谨、效率优先。"
            case .companion:
                return "当前为陪伴模式：温柔、共情、安抚情绪。"
            }
        }()

        let actionPrompt: String = {
            switch action {
            case .chat:
                return "任务：对话回复。"
            case .translate:
                return "任务：离线翻译（按用户要求语言对），输出自然流畅。"
            case .photoRepair:
                return "任务：2K划痕修复（仅划痕修复）。如无法处理图片输入，给出下一步需要的操作。"
            case .textEnhance:
                return "任务：文字增强（去阴影/折痕/锐化），如无法处理图片输入，给出下一步需要的操作。"
            case .settings:
                return "任务：打开设置说明（由应用侧处理），模型只需简短说明。"
            case .wipeMemory:
                return "任务：记忆清空（必须二次确认后才能执行）。"
            }
        }()

        return [base, modePrompt, actionPrompt].joined(separator: "\n")
    }
}

