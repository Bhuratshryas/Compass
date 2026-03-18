//
//  ConversationStore.swift
//  Compass
//

import Foundation

final class ConversationStore: ObservableObject {
    static let shared = ConversationStore()

    @Published private(set) var conversations: [Conversation] = []

    private let key = "Compass.conversations"
    private let maxStored = 100

    init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Conversation].self, from: data) else {
            conversations = []
            return
        }
        conversations = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ conversation: Conversation) {
        var list = conversations.filter { $0.id != conversation.id }
        list.insert(conversation, at: 0)
        list = Array(list.prefix(maxStored))
        conversations = list.sorted { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func update(id: UUID, title: String? = nil, messages: [ChatMessage]? = nil) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        var conv = conversations[index]
        if let title = title { conv.title = title }
        if let messages = messages { conv.messages = messages }
        conv.updatedAt = Date()
        conversations[index] = conv
        conversations.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func delete(id: UUID) {
        conversations.removeAll { $0.id == id }
        persist()
    }

    func conversation(by id: UUID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
