// File: SwiftVaporServer/Models/User.swift

import Fluent
import Foundation
import Vapor

final class User: Model, @unchecked Sendable {
    static let schema = "users"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "username")
    var username: String
    
    @Field(key: "password_hash")
    var passwordHash: String
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?
    
    init() { }
    
    init(id: UUID? = nil, username: String, passwordHash: String) {
        self.id = id
        self.username = username
        self.passwordHash = passwordHash
    }
    
    func toUserDTO() throws -> UserDTO {
        guard let id = self.id else {
            throw Abort(.internalServerError, reason: "User ID is missing")
        }
        
        return UserDTO(
            id: id,
            username: self.username,
            createdAt: self.createdAt,
            updatedAt: self.updatedAt
        )
    }
}
