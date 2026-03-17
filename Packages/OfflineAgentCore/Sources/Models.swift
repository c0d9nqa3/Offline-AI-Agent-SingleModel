import Foundation

public enum ChatMode: Sendable, Equatable {
    case work
    case companion
}

public enum ChatRole: String, Sendable, Codable {
    case user
    case assistant
    case system
}

public struct ChatMessage: Identifiable, Sendable, Equatable, Codable {
    public var id: UUID
    public var role: ChatRole
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), role: ChatRole, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

