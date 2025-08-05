// File: SwiftVaporServer/Services/MessageService.swift

import Fluent
import Vapor

struct MessageService {
    func getAllMessages(for userId: UUID, req: Request) async throws -> [MessageDTO] {
        async let sentMessages = getSentMessages(for: userId, req: req)
        async let receivedMessages = getReceivedMessages(for: userId, req: req)
        
        let allMessages = try await sentMessages + receivedMessages
        
        return allMessages.sorted {
            ($0.sentAt ?? Date.distantPast) > ($1.sentAt ?? Date.distantPast) }
        
    }
    
    func markNewMessagesAsReceived(for userId: UUID, req: Request) async throws {
        try await MessageRecipient.query(on: req.db)
            .filter(\.$user.$id == userId)
            .filter(\.$receivedAt == nil)
            .set(\.$receivedAt, to: Date())
            .update()
    }
    
    func sendMessage(from userId: UUID, dto: CreateMessageDTO, req: Request) async throws -> UUID {
        
        // Validate recipients
        try await validateRecipients(dto.recipientIDs, req: req)
        
        return try await req.db.transaction { db in
            // Create message
            let message = Message(senderID: userId, textContent: dto.textContent)
            try await message.save(on: db)
            
            guard let messageId = message.id else {
                throw Abort(.internalServerError, reason: "Failed to create message")
            }
            
            // Create entries for message recipients
            let recipients = dto.recipientIDs.map { recipientID in
                MessageRecipient(messageID: messageId, userID: recipientID)
            }
            
            try await recipients.create(on: db)
            
            return messageId
        }
        
    }
}

// MARK: - Private helpers
private extension MessageService {
    func getSentMessages(for userId: UUID, req: Request) async throws -> [MessageDTO] {
        let messages = try await Message.query(on: req.db)
            .with(\.$sender)
            .with(\.$recipients)
            .filter(\.$sender.$id == userId)
            .sort(\.$sentAt, .descending)
            .all()
        
        return try messages.map { try $0.toMessageDTO() }
    }
    
    func getReceivedMessages(for userId: UUID, req: Request) async throws -> [MessageDTO] {
        let messages = try await Message.query(on: req.db)
            .with(\.$sender)
            .with(\.$recipients)
            .join(MessageRecipient.self, on: \Message.$id == \MessageRecipient.$message.$id)
            .filter(MessageRecipient.self, \.$user.$id == userId)
            .sort(\.$sentAt, .descending)
            .all()
        
        // Mark any new messages as read
        try await markNewMessagesAsReceived(for: userId, req: req)
        
        return try messages.map { try $0.toMessageDTO() }
    }
    
    func validateRecipients(_ recipientIDs: [UUID], req: Request) async throws {
        guard !recipientIDs.isEmpty else {
            throw Abort(.badRequest, reason: "At least one valid recipient is required")
        }
        
        let existingUsers = try await User.query(on: req.db)
            .filter(\.$id ~~ recipientIDs)
            .count()
        
        guard existingUsers == recipientIDs.count else {
            throw Abort(.badRequest, reason: "One or more recipient IDs are invalid")
        }
    }
}

extension Request {
    var messageService: MessageService {
        MessageService()
    }
}
