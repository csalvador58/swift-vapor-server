// File: SwiftVaporServer/Migrations/CreateUser.swift

import Fluent

struct CreateUser: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("users")
            .id()
            .field("username", .string, .required)
            .field("password_hash", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "username")
            .create()
    }
    
    func revert(on database: any Database) async throws {
        try await database.schema("users").delete()
    }
}
