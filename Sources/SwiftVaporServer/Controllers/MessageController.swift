// File: SwiftVaporServer/Controllers/MessageController.swift

import Fluent
import Vapor

struct MessageController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let messages = routes.grouped("messages")
        
        let protected = messages.grouped(UserAuthenticator())
        protected.get(use: self.getMessages)
        protected.post("new", use: self.sendMessage)
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
}
