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
    let date: Date

    enum Role: String, Equatable, Codable {
        case user
        case assistant
    }

    struct ImageAttachment: Equatable, Codable {
        let data: Data
        let id: UUID
    }

    init(id: UUID = UUID(), role: Role, content: String, attachedImage: ImageAttachment? = nil, date: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.attachedImage = attachedImage
        self.date = date
    }
}
