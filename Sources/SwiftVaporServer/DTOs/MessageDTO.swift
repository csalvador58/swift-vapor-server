// File: SwiftVaporServer/DTOs/MessageDTO.swift

import Fluent
import Vapor

struct MessageDTO: Content {
    let id: UUID
    let sender: UserDTO
    let recipients: [String]
    let textContent: String?
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
