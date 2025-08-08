// File: Tests/SwiftVaporServerTests/MessageTests.swift

@testable import SwiftVaporServer
import VaporTesting
import Testing
import Fluent

@Suite("Message Test with DB", .serialized)
struct MessagesTest {
    struct TestUser {
        let user: User
        let password: String
        let token: String?
    }
    
    private func withApp(_ test: (Application) async throws -> ()) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await app.autoMigrate()
            try await test(app)
            try await app.autoRevert()
        } catch {
            try? await app.autoRevert()
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
    
    private func createTestUsersWithLoginTokens(on app: Application) async throws -> [TestUser] {
        // Create test users
        let userData = [
            (username: "testUser1", password: "password123"),
            (username: "testUser2", password: "password456"),
            (username: "testUser3", password: "password789"),
        ]

        var testUsers: [TestUser] = []
        
        // Create and save users
        for (index, data) in userData.enumerated() {
            let user = User(
                username: data.username,
                passwordHash: try await app.password.async.hash(data.password)
            )
            try await user.save(on: app.db)
            
            // Login testUser1 & testUser2, keep testUser3 logged out
            if index < 2 {
                let loginUserDTO = LoginUserDTO(
                    username: data.username,
                    password: data.password
                )
                
                var token: String?
                
                try await app.testing().test(
                    .POST, "users/login",
                    beforeRequest: { req in
                        try req.content.encode(loginUserDTO)
                    },
                    afterResponse: { res in
                        let response = try res.content.decode(UserTokenDTO.self)
                        token = response.token
                    })
                
                testUsers.append(TestUser(user: user, password: data.password, token: token))
            } else {
                testUsers.append(TestUser(user: user, password: data.password, token: nil))
            }
        }
        
        return testUsers
    }
    
    @Test("Send a new message")
    func sendANewMessage() async throws {
        try await withApp { app in
            // Create test users
            let testUsers = try await createTestUsersWithLoginTokens(on: app)
            let sender = testUsers[0] // test user 1
            let recipients = [testUsers[1].user, testUsers[2].user]
                              
            guard let senderToken = sender.token else {
                Issue.record("Sender token is missing")
                return
            }
            
            // Create message
            let recipientIDs = recipients.compactMap { $0.id }
            let createMessageDTO = CreateMessageDTO(
                recipientIDs: recipientIDs,
                textContent: "Test message from testUser1")
            
            // Send message
            try await app.testing().test(
                .POST, "messages/new",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: senderToken)
                    try req.content.encode(createMessageDTO)
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    
                    let messageId = try res.content.decode(String.self)
                    guard let messageUUID = UUID(uuidString: messageId) else {
                        Issue.record("Invalid message UUID")
                        return
                    }
                    
                    // Verify in message was stored in db
                    let message = try await Message.find(messageUUID, on: app.db)
                    
                    #expect(message != nil)
                    #expect(message?.$sender.id == sender.user.id)
                    #expect(message?.textContent == "Test message from testUser1")
                    
                    // Verify recipients received message
                    let messageRecipients = try await MessageRecipient.query(on: app.db)
                        .filter(\.$message.$id == messageUUID)
                        .all()
                    #expect(messageRecipients.count == 2)
                    
                    let recipientUserIDs = messageRecipients.map { $0.$user.id }
                    guard let user2Id = testUsers[1].user.id,
                          let user3Id = testUsers[2].user.id else {
                        Issue.record("Test user IDs are missing")
                        return
                    }
                    
                    #expect(recipientUserIDs.contains(user2Id))
                    #expect(recipientUserIDs.contains(user3Id))
                    
                })
        }
    }
    
    @Test("Get all messages for a user - Sent and Received")
    func getAllMessages() async throws {
        try await withApp { app in
            let testUsers = try await createTestUsersWithLoginTokens(on: app)
            let user1 = testUsers[0]
            let user2 = testUsers[1]
            let user3 = testUsers[2]
            
            guard let user1Token = user1.token,
                  let user2Token = user2.token,
                  let user1Id = user1.user.id,
                  let user2Id = user2.user.id,
                  let user3Id = user3.user.id else {
                Issue.record("Required test data is missing")
                return
            }
            
            let messageFromUser1ToUser2And3DTO = CreateMessageDTO(
                recipientIDs: [user2Id, user3Id],
                textContent: "Test message from user1 to user2 and user3"
            )
            
            var messageFromUser1ToUser2AndUser3Id: UUID?
            try await app.testing().test(
                .POST, "messages/new",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: user1Token)
                    try req.content.encode(messageFromUser1ToUser2And3DTO)
                },
                afterResponse: { res in
                    let messageId = try res.content.decode(String.self)
                    messageFromUser1ToUser2AndUser3Id = UUID(uuidString: messageId)
                })
            
            let messageFromUser2ToUser1DTO = CreateMessageDTO(
                recipientIDs: [user1Id],
                textContent: "Test message from user2 to user1"
            )
            
            var messageFromUser2ToUser1Id: UUID?
            try await app.testing().test(
                .POST, "messages/new",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: user2Token)
                    try req.content.encode(messageFromUser2ToUser1DTO)
                },
                afterResponse: { res in
                    let messageId = try res.content.decode(String.self)
                    messageFromUser2ToUser1Id = UUID(uuidString: messageId)
                })
            
            // Get all messages for user1
            try await app.testing().test(
                .GET, "messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: user1Token)
                },
                afterResponse: { res in
                    #expect(res.status == .ok)
                    
                    let messages = try res.content.decode([MessageDTO].self)
                    #expect(messages.count == 2)
                    
                    let messageIds = messages.map { $0.id }
                    #expect(messageIds.contains(messageFromUser1ToUser2AndUser3Id!))
                    #expect(messageIds.contains(messageFromUser2ToUser1Id!))
                    
                    // Check the sent message
                    if let sentMessage = messages.first(where: { $0.id == messageFromUser1ToUser2AndUser3Id }) {
                        #expect(sentMessage.sender.id == user1Id)
                        #expect(sentMessage.textContent == "Test message from user1 to user2 and user3")
                        #expect(sentMessage.recipients.contains("testUser2"))
                        #expect(sentMessage.recipients.contains("testUser3"))
                    }
                    
                    // Check the received message
                    if let receivedMessage = messages.first(where: { $0.id == messageFromUser2ToUser1Id }) {
                        #expect(receivedMessage.sender.id == user2Id)
                        #expect(receivedMessage.textContent == "Test message from user2 to user1")
                        #expect(receivedMessage.recipients.contains("testUser1"))
                    }
                })
            
            // Get all messages for user2
            try await app.testing().test(
                .GET, "messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: user2Token)
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    
                    let messages = try res.content.decode([MessageDTO].self)
                    #expect(messages.count == 2)
                    
                    let messageIds = messages.map { $0.id }
                    #expect(messageIds.contains(messageFromUser1ToUser2AndUser3Id!))
                    #expect(messageIds.contains(messageFromUser2ToUser1Id!))
                })
            
        }
    }
    
    @Test("Delete message as sender")
    func deleteMessageAsSender() async throws {
        try await withApp { app in
            let testUsers = try await createTestUsersWithLoginTokens(on: app)
            let sender = testUsers[0]
            let recipient = testUsers[1]
            
            guard let senderToken = sender.token,
                  let recipientToken = recipient.token,
                  let recipientId = recipient.user.id else {
                Issue.record("Required test data is missing")
                return
            }
            
            // Send a message
            let messageFromSenderToRecipientDTO = CreateMessageDTO(
                recipientIDs: [recipientId],
                textContent: "Test message from sender to recipient - to be deleted by sender"
            )
            
            var messageFromSenderToRecipientId: UUID?
            try await app.testing().test(
                .POST, "messages/new",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: senderToken)
                    try req.content.encode(messageFromSenderToRecipientDTO)
                },
                afterResponse: { res in
                    let messageIdString = try res.content.decode(String.self)
                    messageFromSenderToRecipientId = UUID(uuidString: messageIdString)
                })
            
            guard let messageFromSenderToRecipientId = messageFromSenderToRecipientId else {
                Issue.record("Message ID is missing")
                return
            }
            
            // Delete message as sender
            let deleteMessagesDTO = DeleteMessagesDTO(messageIDs: [messageFromSenderToRecipientId])
            
            try await app.testing().test(
                .DELETE, "messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: senderToken)
                    try req.content.encode(deleteMessagesDTO)
                },
                afterResponse: { res async throws in
                    #expect(res.status == .noContent)
                    
                    // Verify message is completely deleted from database
                    let message = try await Message.find(messageFromSenderToRecipientId, on: app.db)
                    #expect(message == nil)
                    
                    // Verify message recipients are also deleted
                    let recipients = try await MessageRecipient.query(on: app.db)
                        .filter(\.$message.$id == messageFromSenderToRecipientId)
                        .all()
                    #expect(recipients.isEmpty)
                })
            
            // Verify recipient no longer sees the message
            try await app.testing().test(
                .GET, "messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: recipientToken)
                },
                afterResponse: { res async throws in
                    let messages = try res.content.decode([MessageDTO].self)
                    let messageIds = messages.map { $0.id }
                    #expect(!messageIds.contains(messageFromSenderToRecipientId))
                })
        }
    }
    
    @Test("Delete message as recipient")
    func deleteMessageAsRecipient() async throws {
        try await withApp { app in
            let testUsers = try await createTestUsersWithLoginTokens(on: app)
            let sender = testUsers[0]
            let recipient = testUsers[1]
            
            guard let senderToken = sender.token,
                  let recipientToken = recipient.token,
                  let recipientId = recipient.user.id else {
                Issue.record("Required test data is missing")
                return
            }
            
            // Send a message
            let messageFromSenderToRecipientDTO = CreateMessageDTO(
                recipientIDs: [recipientId],
                textContent: "Test message from sender to recipient - to be deleted by recipient"
            )
            
            var messageIdString: UUID?
            try await app.testing().test(
                .POST, "messages/new",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: senderToken)
                    try req.content.encode(messageFromSenderToRecipientDTO)
                },
                afterResponse: { res in
                    let messageId = try res.content.decode(String.self)
                    messageIdString = UUID(uuidString: messageId)
                })
            
            guard let messageFromSenderToRecipientId = messageIdString else {
                Issue.record("Message ID is missing")
                return
            }
            
            // Delete message as recipient
            let deleteMessagesDTO = DeleteMessagesDTO(messageIDs: [messageFromSenderToRecipientId])
            
            try await app.testing().test(
                .DELETE, "messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: recipientToken)
                    try req.content.encode(deleteMessagesDTO)
                },
                afterResponse: { res async throws in
                    #expect(res.status == .noContent)
                    
                    // Verify message still exists in database
                    let message = try await Message.find(messageFromSenderToRecipientId, on: app.db)
                    #expect(message != nil)
                    
                    // Verify recipient entry is soft deleted
                    let recipientEntry = try await MessageRecipient.query(on: app.db)
                        .filter(\.$message.$id == messageFromSenderToRecipientId)
                        .filter(\.$user.$id == recipientId)
                        .first()
                    #expect(recipientEntry?.deletedAt != nil)
                })
            
            // Verify recipient no longer sees the message
            try await app.testing().test(
                .GET, "messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: recipientToken)
                },
                afterResponse: { res async throws in
                    let messages = try res.content.decode([MessageDTO].self)
                    let messageIds = messages.map { $0.id }
                    #expect(!messageIds.contains(messageFromSenderToRecipientId))
                })
            
            // Verify sender still sees the message
            try await app.testing().test(
                .GET, "messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: senderToken)
                },
                afterResponse: { res async throws in
                    let messages = try res.content.decode([MessageDTO].self)
                    let messageIds = messages.map { $0.id }
                    #expect(messageIds.contains(messageFromSenderToRecipientId))
                })
        }
    }
    
    @Test("Send message with invalid recipient IDs")
    func sendMessageWithInvalidRecipients() async throws {
        try await withApp { app in
            let testUsers = try await createTestUsersWithLoginTokens(on: app)
            let sender = testUsers[0]
            
            guard let senderToken = sender.token else {
                Issue.record("Sender token is missing")
                return
            }
            
            // Create message with non-existent recipient IDs
            let nonExistentRecipientId = UUID()
            let messageWithInvalidRecipientDTO = CreateMessageDTO(
                recipientIDs: [nonExistentRecipientId],
                textContent: "Test message with invalid recipient"
            )
            
            // Attempt to send message
            try await app.testing().test(
                .POST, "messages/new",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: senderToken)
                    try req.content.encode(messageWithInvalidRecipientDTO)
                },
                afterResponse: { res async in
                    #expect(res.status == .badRequest)
                })
        }
    }
    
    @Test("Send message with empty recipient list")
    func sendMessageWithEmptyRecipients() async throws {
        try await withApp { app in
            let testUsers = try await createTestUsersWithLoginTokens(on: app)
            let sender = testUsers[0]
            
            guard let senderToken = sender.token else {
                Issue.record("Sender token is missing")
                return
            }
            
            // Create message with empty recipient list
            let messageWithNoRecipientsDTO = CreateMessageDTO(
                recipientIDs: [],
                textContent: "Test message with no recipients"
            )
            
            // Attempt to send message
            try await app.testing().test(
                .POST, "messages/new",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: senderToken)
                    try req.content.encode(messageWithNoRecipientsDTO)
                },
                afterResponse: { res async in
                    #expect(res.status == .badRequest)
                })
        }
    }
    
    @Test("Message recipient marking as received")
    func messageRecipientMarkingAsReceived() async throws {
        try await withApp { app in
            let testUsers = try await createTestUsersWithLoginTokens(on: app)
            let sender = testUsers[0]
            let recipient = testUsers[1]
            
            guard let senderToken = sender.token,
                  let recipientToken = recipient.token,
                  let recipientId = recipient.user.id else {
                Issue.record("Required test data is missing")
                return
            }
            
            // Send a message
            let messageFromSenderToRecipientDTO = CreateMessageDTO(
                recipientIDs: [recipientId],
                textContent: "Test message from sender to recipient - to test received marking"
            )
            
            var messageIdString: UUID?
            try await app.testing().test(
                .POST, "messages/new",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: senderToken)
                    try req.content.encode(messageFromSenderToRecipientDTO)
                },
                afterResponse: { res in
                    let messageId = try res.content.decode(String.self)
                    messageIdString = UUID(uuidString: messageId)
                })
            
            guard let messageFromSenderToRecipientId = messageIdString else {
                Issue.record("Message ID is missing")
                return
            }
            
            // Check that receivedAt is initially nil
            let initialRecipientEntry = try await MessageRecipient.query(on: app.db)
                .filter(\.$message.$id == messageFromSenderToRecipientId)
                .filter(\.$user.$id == recipientId)
                .first()
            #expect(initialRecipientEntry?.receivedAt == nil)
            
            // Recipient fetches messages
            try await app.testing().test(
                .GET, "messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: recipientToken)
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    
                    // Verify receivedAt is now set
                    let updatedRecipientEntry = try await MessageRecipient.query(on: app.db)
                        .filter(\.$message.$id == messageFromSenderToRecipientId)
                        .filter(\.$user.$id == recipientId)
                        .first()
                    #expect(updatedRecipientEntry?.receivedAt != nil)
                })
        }
    }
    
    @Test("Delete multiple messages at once")
    func deleteMultipleMessages() async throws {
        try await withApp { app in
            let testUsers = try await createTestUsersWithLoginTokens(on: app)
            let sender = testUsers[0]
            let recipient = testUsers[1]
            
            guard let senderToken = sender.token,
                  let recipientId = recipient.user.id else {
                Issue.record("Required test data is missing")
                return
            }
            
            var messageIdsFromSenderToRecipient: [UUID] = []
            
            // Send multiple messages
            for i in 1...3 {
                let messageFromSenderToRecipientDTO = CreateMessageDTO(
                    recipientIDs: [recipientId],
                    textContent: "Test message \(i) from sender to recipient - to be deleted"
                )
                
                try await app.testing().test(
                    .POST, "messages/new",
                    beforeRequest: { req in
                        req.headers.bearerAuthorization = BearerAuthorization(token: senderToken)
                        try req.content.encode(messageFromSenderToRecipientDTO)
                    },
                    afterResponse: { res in
                        let messageIdString = try res.content.decode(String.self)
                        if let messageId = UUID(uuidString: messageIdString) {
                            messageIdsFromSenderToRecipient.append(messageId)
                        }
                    })
            }
            
            #expect(messageIdsFromSenderToRecipient.count == 3)
            
            // Delete all messages at once
            let deleteMultipleMessagesDTO = DeleteMessagesDTO(messageIDs: messageIdsFromSenderToRecipient)
            
            try await app.testing().test(
                .DELETE, "messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: senderToken)
                    try req.content.encode(deleteMultipleMessagesDTO)
                },
                afterResponse: { res async throws in
                    #expect(res.status == .noContent)
                    
                    // Verify all messages are deleted
                    for messageId in messageIdsFromSenderToRecipient {
                        let message = try await Message.find(messageId, on: app.db)
                        #expect(message == nil)
                    }
                })
        }
    }
    
    @Test("Delete with empty message ID list")
    func deleteWithEmptyMessageIds() async throws {
        try await withApp { app in
            let testUsers = try await createTestUsersWithLoginTokens(on: app)
            let user = testUsers[0]
            
            guard let userToken = user.token else {
                Issue.record("User token is missing")
                return
            }
            
            // Attempt to delete with empty list
            let deleteEmptyMessagesDTO = DeleteMessagesDTO(messageIDs: [])
            
            try await app.testing().test(
                .DELETE, "messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: userToken)
                    try req.content.encode(deleteEmptyMessagesDTO)
                },
                afterResponse: { res async in
                    #expect(res.status == .badRequest)
                })
        }
    }
    
    @Test("Messages are sorted by sentAt in descending order")
    func messagesAreSortedBySentAt() async throws {
        try await withApp { app in
            let testUsers = try await createTestUsersWithLoginTokens(on: app)
            let user1 = testUsers[0]
            let user2 = testUsers[1]
            
            guard let user1Token = user1.token,
                  let user2Id = user2.user.id else {
                Issue.record("Required test data is missing")
                return
            }
            
            var messagesToUser2: [String] = []
            
            // Send multiple messages
            for i in 1...3 {
                let messageText = "Test message \(i) from user1 to user2"
                messagesToUser2.append(messageText)
                
                let messageFromUser1ToUser2DTO = CreateMessageDTO(
                    recipientIDs: [user2Id],
                    textContent: messageText
                )
                
                try await app.testing().test(
                    .POST, "messages/new",
                    beforeRequest: { req in
                        req.headers.bearerAuthorization = BearerAuthorization(token: user1Token)
                        try req.content.encode(messageFromUser1ToUser2DTO)
                    },
                    afterResponse: { res in
                        #expect(res.status == .ok)
                    })
                
                // Small delay to ensure different timestamps
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            
            // Get messages and verify order
            try await app.testing().test(
                .GET, "messages",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: user1Token)
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    
                    let messages = try res.content.decode([MessageDTO].self)
                    #expect(messages.count == 3)
                    
                    // Messages should be in descending order (newest first)
                    #expect(messages[0].textContent == "Test message 3 from user1 to user2")
                    #expect(messages[1].textContent == "Test message 2 from user1 to user2")
                    #expect(messages[2].textContent == "Test message 1 from user1 to user2")
                })
        }
    }
}
