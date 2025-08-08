// File: SwiftVaporServer/DTOs/MessageDTO.swift

import Fluent
import Vapor

struct MessageDTO: Content {
    let id: UUID
    let sender: UserDTO
    let recipients: [String]
    let textContent: String?
    let participantHash: String?
    let sentAt: Date?
}

struct MessageRecipientDTO: Content {
    let user: UserDTO
    let readAt: Date?
}

struct CreateMessageDTO: Content {
    let recipientIDs: [UUID]
    let textContent: String?
}

struct DeleteMessagesDTO: Content {
    let messageIDs: [UUID]
}

struct GetConversationMessagesDTO: Content {
    let participantHash: String
    let limit: Int
    let offset: Int
    
    init(participantHash: String, limit: Int = 20, offset: Int = 0) {
        self.participantHash = participantHash
        self.limit = min(limit, 100)
        self.offset = max(offset, 0)
    }
}
