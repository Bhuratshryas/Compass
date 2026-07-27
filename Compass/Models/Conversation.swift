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

    /// Rolling long-term memory: a compact summary of messages older than the
    /// recent buffer, so long sessions retain earlier facts.
    var summary: String
    /// Number of leading messages already folded into `summary`.
    var memoryWatermark: Int

    init(id: UUID = UUID(), title: String, messages: [ChatMessage] = [], createdAt: Date = Date(), updatedAt: Date = Date(), summary: String = "", memoryWatermark: Int = 0) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.summary = summary
        self.memoryWatermark = memoryWatermark
    }

    // Backwards-compatible decoding: older stored conversations lack memory fields.
    enum CodingKeys: String, CodingKey {
        case id, title, messages, createdAt, updatedAt, summary, memoryWatermark
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        messages = try c.decode([ChatMessage].self, forKey: .messages)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        memoryWatermark = try c.decodeIfPresent(Int.self, forKey: .memoryWatermark) ?? 0
    }

    static func title(from firstUserMessage: String) -> String {
        let trimmed = firstUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "New chat" }
        let words = trimmed.split(separator: " ").prefix(6)
        let title = words.joined(separator: " ")
        return title.count > 50 ? String(title.prefix(47)) + "…" : title
    }
}
