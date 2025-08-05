// File: SwiftVaporServer/Controllers/MessageController.swift

import Fluent
import Vapor

struct MessageController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let messages = routes.grouped("messages")
        
        let protected = messages.grouped(UserAuthenticator())
        protected.get(use: self.getMessages)
        protected.post("new", use: self.sendMessage)
        protected.delete(use: self.deleteMessages)
    }
    
    @Sendable
    func getMessages(req: Request) async throws -> [MessageDTO] {
        let payload = try req.auth.require(AuthPayload.self)
        
        return try await req.messageService.getAllMessages(for: payload.userId, req: req)
    }
    
    @Sendable
    func sendMessage(req: Request) async throws -> String {
        let createMessageDTO = try req.content.decode(CreateMessageDTO.self)
        
        let payload = try req.auth.require(AuthPayload.self)
        
        let messageId = try await req.messageService.sendMessage(
            from: payload.userId,
            dto: createMessageDTO,
            req: req
        )
        
        return messageId.uuidString
    }
    
    @Sendable
    func deleteMessages(req: Request) async throws -> HTTPStatus {
        let deleteMessagesDTO = try req.content.decode(DeleteMessagesDTO.self)
        
        let payload = try req.auth.require(AuthPayload.self)
        
        try await req.messageService.deleteMessages(
            for: payload.userId,
            messageIDs: deleteMessagesDTO.messageIDs,
            req: req
        )
        
        return .noContent
    }
}
