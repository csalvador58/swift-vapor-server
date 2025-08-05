// File: SwiftVaporServer/Models/Message.swift

import Fluent
import Foundation
import Vapor

final class Message: Model, @unchecked Sendable {
    static let schema = "messages"
    
    @ID(key: .id)
    var id: UUID?
    
    @Parent(key: "sender_id")
    var sender: User
    
    @Siblings(through: MessageRecipient.self, from: \.$message, to: \.$user)
    var recipients: [User]
    
    @OptionalField(key: "text_content")
    var textContent: String?
    
    @Timestamp(key: "sent_at", on: .create)
    var sentAt: Date?
    
    init() { }
    
    init(id: UUID? = nil, senderID: UUID, textContent: String? = nil) {
        self.id = id
        self.$sender.id = senderID
        self.textContent = textContent
    }
    
    func toMessageDTO() throws -> MessageDTO {
        guard let id = self.id else {
            throw Abort(.internalServerError, reason: "Message ID is missing")
        }
        
        let senderDTO = try self.sender.toUserDTO()
        
        let recipientUsernames = self.recipients.map { $0.username }
        
        return MessageDTO(
            id: id,
            sender: senderDTO,
            recipients: recipientUsernames,
            textContent: self.textContent,
            sentAt: self.sentAt
        )
    }
}
