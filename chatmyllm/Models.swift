//
//  Models.swift
//  chatmyllm
//
//  Created by Egor Glukhov on 15. 3. 2026.
//

import Foundation
import SwiftData

@Model
final class Chat {
    var id: UUID
    var title: String
    var createdAt: Date
    var modelId: String
    var draft: String

    @Relationship(deleteRule: .cascade, inverse: \Message.chat)
    var messages: [Message]

    init(title: String? = nil, modelId: String = "anthropic/claude-3.5-sonnet") {
        self.id = UUID()
        self.title = title ?? String(localized: "New Chat", comment: "Default chat title")
        self.createdAt = Date()
        self.modelId = modelId
        self.draft = ""
        self.messages = []
    }
}

@Model
final class Message {
    var id: UUID
    var content: String
    var isFromUser: Bool
    var timestamp: Date

    var chat: Chat?

    init(content: String, isFromUser: Bool, chat: Chat? = nil) {
        self.id = UUID()
        self.content = content
        self.isFromUser = isFromUser
        self.timestamp = Date()
        self.chat = chat
    }
}
