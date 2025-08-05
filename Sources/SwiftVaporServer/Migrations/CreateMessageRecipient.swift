// File: SwiftVaporServer/Migrations/CreateMessageRecipient.swift

import Fluent

struct CreateMessageRecipient: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("message_recipients")
            .id()
            .field("message_id", .uuid, .required, .references("messages", "id", onDelete: .cascade))
            .field("user_id", .uuid, .required, .references("users", "id"))
            .field("received_at", .datetime)
            .field("deleted_at", .datetime)
            .create()
    }
    
    func revert(on database: any Database) async throws {
        try await database.schema("message_recipients").delete()
    }
}
