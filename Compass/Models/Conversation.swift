//
//  Conversation.swift
//  Compass
//

import Foundation

struct Conversation: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, messages: [ChatMessage] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func title(from firstUserMessage: String) -> String {
        let trimmed = firstUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "New chat" }
        let words = trimmed.split(separator: " ").prefix(6)
        let title = words.joined(separator: " ")
        return title.count > 50 ? String(title.prefix(47)) + "…" : title
    }
}
