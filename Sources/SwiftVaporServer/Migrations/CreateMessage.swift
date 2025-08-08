// File: SwiftVaporServer/Migrations/CreateMessage.swift

import Fluent

struct CreateMessage: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("messages")
            .id()
            .field("sender_id", .uuid, .required, .references("users", "id"))
            .field("text_content", .string)
            .field("participant_hash", .string)
            .field("sent_at", .datetime)
            .create()
    }
    
    func revert(on database: any Database) async throws {
        try await database.schema("messages").delete()
    }
}
