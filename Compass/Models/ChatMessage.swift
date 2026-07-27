//
//  ChatMessage.swift
//  Compass
//

import Foundation
import SwiftUI

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let role: Role
    var content: String
    var attachedImage: ImageAttachment?
    /// Sources the assistant used to ground this answer (Perplexity-style citations).
    /// Empty for on-device-only answers that used no external retrieval.
    var sources: [WebSource]
    let date: Date

    enum Role: String, Equatable, Codable {
        case user
        case assistant
    }

    struct ImageAttachment: Equatable, Codable {
        let data: Data
        let id: UUID
    }

    init(id: UUID = UUID(), role: Role, content: String, attachedImage: ImageAttachment? = nil, sources: [WebSource] = [], date: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.attachedImage = attachedImage
        self.sources = sources
        self.date = date
    }

    // Backwards-compatible decoding: older stored conversations have no `sources`.
    enum CodingKeys: String, CodingKey {
        case id, role, content, attachedImage, sources, date
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        role = try c.decode(Role.self, forKey: .role)
        content = try c.decode(String.self, forKey: .content)
        attachedImage = try c.decodeIfPresent(ImageAttachment.self, forKey: .attachedImage)
        sources = try c.decodeIfPresent([WebSource].self, forKey: .sources) ?? []
        date = try c.decode(Date.self, forKey: .date)
    }
}
