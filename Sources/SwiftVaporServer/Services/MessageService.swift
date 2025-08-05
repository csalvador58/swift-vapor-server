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
    
    private func getSentMessages(for userId: UUID, req: Request) async throws -> [MessageDTO] {
        let messages = try await Message.query(on: req.db)
            .with(\.$sender)
            .with(\.$recipients)
            .filter(\.$sender.$id == userId)
            .sort(\.$sentAt, .descending)
            .all()
        
        return try messages.map { try $0.toMessageDTO() }
    }
    
    private func getReceivedMessages(for userId: UUID, req: Request) async throws -> [MessageDTO] {
        let messages = try await Message.query(on: req.db)
            .with(\.$sender)
            .with(\.$recipients)
            .join(MessageRecipient.self, on: \Message.$id == \MessageRecipient.$message.$id)
            .filter(MessageRecipient.self, \.$user.$id == userId)
            .sort(\.$sentAt, .descending)
            .all()
        
        return try messages.map { try $0.toMessageDTO() }
    }
}

extension Request {
    var messageService: MessageService {
        MessageService()
    }
}
