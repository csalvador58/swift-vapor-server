// File: SwiftVaporServer/Controllers/MessageController.swift

import Fluent
import Vapor

struct MessageController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let messages = routes.grouped("messages")
        
        let protected = messages.grouped(UserAuthenticator())
        protected.get(use: self.getMessages)
    }
    
    @Sendable
    func getMessages(req: Request) async throws -> [MessageDTO] {
        let payload = try req.auth.require(AuthPayload.self)
        
        return try await req.messageService.getAllMessages(for: payload.userId, req: req)
    }
}
