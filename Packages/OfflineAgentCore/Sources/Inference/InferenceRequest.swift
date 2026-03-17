import Foundation

public enum RoutedAction: String, Sendable, Equatable, Codable {
    case chat
    case translate
    case photoRepair
    case textEnhance
    case settings
    case wipeMemory
}

public struct InferenceRequest: Sendable, Equatable {
    public var userText: String
    public var mode: ChatMode
    public var action: RoutedAction
    public var systemPrompt: String
    public var conversation: [ChatMessage]

    public init(
        userText: String,
        mode: ChatMode,
        action: RoutedAction,
        systemPrompt: String,
        conversation: [ChatMessage]
    ) {
        self.userText = userText
        self.mode = mode
        self.action = action
        self.systemPrompt = systemPrompt
        self.conversation = conversation
    }
}

