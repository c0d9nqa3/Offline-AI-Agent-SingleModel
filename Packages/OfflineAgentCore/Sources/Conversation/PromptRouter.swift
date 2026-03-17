import Foundation

public struct RouteResult: Sendable, Equatable {
    public var mode: ChatMode
    public var action: RoutedAction
    public var cleanedUserText: String

    public init(mode: ChatMode, action: RoutedAction, cleanedUserText: String) {
        self.mode = mode
        self.action = action
        self.cleanedUserText = cleanedUserText
    }
}

public struct PromptRouter: Sendable {
    public init() {}

    public func route(userText: String, currentMode: ChatMode) -> RouteResult {
        let raw = userText.trimmingCharacters(in: .whitespacesAndNewlines)

        if raw.hasPrefix("/") {
            return routeSlash(raw, currentMode: currentMode)
        }

        // Keyword-based mode switch (strict, deterministic).
        if raw.contains("翻译") || raw.contains("修图") {
            return RouteResult(mode: .work, action: raw.contains("翻译") ? .translate : .photoRepair, cleanedUserText: raw)
        }
        if raw.contains("聊天") || raw.contains("心情不好") {
            return RouteResult(mode: .companion, action: .chat, cleanedUserText: raw)
        }
        if raw.contains("文字增强") {
            return RouteResult(mode: .work, action: .textEnhance, cleanedUserText: raw)
        }
        if raw.contains("设置") {
            return RouteResult(mode: currentMode, action: .settings, cleanedUserText: raw)
        }
        if raw.contains("记忆清空") {
            return RouteResult(mode: currentMode, action: .wipeMemory, cleanedUserText: raw)
        }

        return RouteResult(mode: currentMode, action: .chat, cleanedUserText: raw)
    }

    private func routeSlash(_ raw: String, currentMode: ChatMode) -> RouteResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed == "/translate" || trimmed.hasPrefix("/translate ") {
            return RouteResult(mode: .work, action: .translate, cleanedUserText: trimmed.replacingOccurrences(of: "/translate", with: "").trimmingCharacters(in: .whitespaces))
        }
        if trimmed == "/photo" || trimmed.hasPrefix("/photo ") {
            return RouteResult(mode: .work, action: .photoRepair, cleanedUserText: trimmed.replacingOccurrences(of: "/photo", with: "").trimmingCharacters(in: .whitespaces))
        }
        if trimmed == "/enhance" || trimmed.hasPrefix("/enhance ") {
            return RouteResult(mode: .work, action: .textEnhance, cleanedUserText: trimmed.replacingOccurrences(of: "/enhance", with: "").trimmingCharacters(in: .whitespaces))
        }
        if trimmed == "/settings" {
            return RouteResult(mode: currentMode, action: .settings, cleanedUserText: "")
        }
        if trimmed == "/wipe" {
            return RouteResult(mode: currentMode, action: .wipeMemory, cleanedUserText: "")
        }

        return RouteResult(mode: currentMode, action: .chat, cleanedUserText: trimmed)
    }
}

