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
}
