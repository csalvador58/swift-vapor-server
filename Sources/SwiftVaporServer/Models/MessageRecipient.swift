// File: SwiftVaporServer/Models/MessageRecipient.swift

import Fluent
import Vapor

final class MessageRecipient: Model, @unchecked Sendable {
    static let schema = "message_recipients"
    
    @ID(key: .id)
    var id: UUID?
    
    @Parent(key: "message_id")
    var message: Message
    
    @Parent(key: "user_id")
    var user: User
    
    @Timestamp(key: "read_at", on: .none)
    var readAt: Date?
    
    init() { }
    
    init(id: UUID? = nil, messageID: UUID, userID: UUID) {
        self.id = id
        self.$message.id = messageID
        self.$user.id = userID
    }
}
