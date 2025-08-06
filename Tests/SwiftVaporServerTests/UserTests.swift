// File: Tests/SwiftVaporServerTests/UserTests.swift

@testable import SwiftVaporServer
import VaporTesting
import Testing
import Fluent

@Suite("User Tests with DB", .serialized)
struct UserTests {
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
    
    private func createTestUser(username: String, password: String, on app: Application) async throws -> User {
        let user = User(
            username: username,
            passwordHash: try await app.password.async.hash(password))
        try await user.save(on: app.db)
        return user
    }
    
    private func loginUser(username: String, password: String, on app: Application) async throws -> String {
        let loginDTO = LoginUserDTO(username: username, password: password)
        var token = ""
        
        try await app.testing().test(
            .POST, "users/login",
            beforeRequest: { req in
                try req.content.encode(loginDTO)
            },
            afterResponse: { res in
                let response = try res.content.decode(UserTokenDTO.self)
                token = response.token
            })
        
        return token
    }
    
    private func createUserAndLogin(username: String, password: String, on app: Application) async throws -> TestUser {
        let user = try await createTestUser(username: username, password: password, on: app)
        let token = try await loginUser(username: username, password: password, on: app)
        return TestUser(user: user, password: password, token: token)
    }
    
    @Test("Register a new user")
    func createUserDTO() async throws {
        let createUserDTO = CreateUserDTO(username: "testuser", password: "password123")
        
        try await withApp { app in
            try await app.testing().test(
                .POST, "users/register",
                beforeRequest: { req in
                    try req.content.encode(createUserDTO)
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    
                    let response = try res.content.decode(UserTokenDTO.self)
                    #expect(response.user.username == createUserDTO.username)
                    #expect(!response.token.isEmpty)
                    
                    // Verify user was created in database
                    let user = try await User.query(on: app.db)
                        .filter(\.$username == createUserDTO.username)
                        .first()
                    #expect(user != nil)
                    #expect(user?.username == createUserDTO.username)
                })
        }
    }
    
    @Test("Login with valid credentials")
    func loginUser() async throws {
        let username = "testuser"
        let password = "password123"
        
        try await withApp { app in
            let user = try await createTestUser(username: username, password: password, on: app)
            
            let loginUserDTO = LoginUserDTO(username: username, password: password)
            
            try await app.testing().test(
                .POST, "users/login",
                beforeRequest: { req in
                    try req.content.encode(loginUserDTO)
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    
                    let response = try res.content.decode(UserTokenDTO.self)
                    #expect(response.user.username == username)
                    #expect(response.user.id == user.id)
                    #expect(!response.token.isEmpty)
                })
        }
    }
    
    @Test("Login with invalid password")
    func loginWithInvalidCredentials() async throws {
        let username = "testuser"
        let password = "password123"
        
        try await withApp { app in
            _ = try await createTestUser(username: username, password: password, on: app)
            
            let loginUserDTO = LoginUserDTO(username: username, password: "invalid")
            
            try await app.testing().test(
                .POST, "users/login",
                beforeRequest: { req in
                    try req.content.encode(loginUserDTO)
                },
                afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
        }
    }
    
    @Test("Delete user with authentication")
    func deleteUser() async throws {
        let username = "testuser"
        let password = "password123"
        
        try await withApp { app in
            let testUser = try await createUserAndLogin(username: username, password: password, on: app)
            
            guard let token = testUser.token else {
                Issue.record("Token is missing")
                return
            }
            
            // Delete user
            try await app.testing().test(
                .DELETE, "users",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: token)
                },
                afterResponse: { res async throws in
                    #expect(res.status == .noContent)
                    
                    let user = try await User.find(testUser.user.id, on: app.db)
                    #expect(user == nil)
                })
        }
    }
    
    @Test("Delete user attempt with invalid authentication")
    func deleteUserAttemptWithInvalidToken() async throws {
        let username = "testuser"
        let password = "password123"
        
        try await withApp { app in
            let testUser = try await createUserAndLogin(username: username, password: password, on: app)
            
            let invalidToken = "invalidToken"
            
            try await app.testing().test(
                .DELETE, "users",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: invalidToken)
                },
                afterResponse: { res async throws in
                    #expect(res.status == .unauthorized)
                    
                    let user = try await User.find(testUser.user.id, on: app.db)
                    #expect(user != nil)
                })
        }
    }
    
    @Test("Update password with authentication")
    func updatePassword() async throws {
        let username = "testuser"
        let currentPassword = "password123"
        let newPassword = "newpassword123"
        
        try await withApp { app in
            let testUser = try await createUserAndLogin(username: username, password: currentPassword, on: app)
            
            guard let token = testUser.token else {
                Issue.record("Token is missing")
                return
            }
            
            let updateUserPasswordDTO = UpdateUserPasswordDTO(currentPassword: currentPassword, newPassword: newPassword)
            
            try await app.testing().test(
                .PATCH, "users/password",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: token)
                    try req.content.encode(updateUserPasswordDTO)
                },
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    
                    let userDTO = try res.content.decode(UserDTO.self)
                    #expect(userDTO.id == testUser.user.id)
                    #expect(userDTO.username == username)
                })
            
            // Verify password was changed by trying to login with new password
            let newToken = try await loginUser(username: username, password: newPassword, on: app)
            #expect(!newToken.isEmpty)
        }
    }
    
    @Test("Register with existing username")
    func registerWithExistingUsername() async throws {
        let username = "testuser"
        let password = "password123"
        
        try await withApp { app in
            _ = try await createTestUser(username: username, password: password, on: app)
            
            let createUserDTO = CreateUserDTO(username: username, password: password)
            
            try await app.testing().test(
                .POST, "users/register",
                beforeRequest: { req in
                    try req.content.encode(createUserDTO)
                },
                afterResponse: { res async in
                    #expect(res.status == .badRequest)
                })
        }
    }
    
    @Test("Register with short password")
    func registerWithShortPassword() async throws {
        let createUserDTO = CreateUserDTO(username: "testuser", password: "short")
        
        try await withApp { app in
            try await app.testing().test(
                .POST, "users/register",
                beforeRequest: { req in
                    try req.content.encode(createUserDTO)
                },
                afterResponse: { res async in
                    #expect(res.status == .badRequest)
                })
        }
    }
    
    @Test("Update password with wrong current password")
    func updatePasswordWithWrongCurrentPassword() async throws {
        let username = "testuser"
        let password = "password123"
        
        try await withApp { app in
            let testUser = try await createUserAndLogin(username: username, password: password, on: app)
            
            guard let token = testUser.token else {
                Issue.record("Token is missing")
                return
            }
            
            let updateUserPasswordDTO = UpdateUserPasswordDTO(currentPassword: "wrongpassword", newPassword: "newpassword123")
            
            try await app.testing().test(
                .PATCH, "users/password",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: token)
                    try req.content.encode(updateUserPasswordDTO)
                },
                afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
        }
    }
    
    @Test("Access protected route without authentication")
    func accessProtectedRouteWithoutAuth() async throws {
        try await withApp { app in
            try await app.testing().test(
                .DELETE, "users",
                afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
            
            let updateUserPasswordDTO = UpdateUserPasswordDTO(currentPassword: "password", newPassword: "newpassword")
            
            try await app.testing().test(
                .PATCH, "users/password",
                beforeRequest: { req in
                    try req.content.encode(updateUserPasswordDTO)
                },
                afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
        }
    }
    
    @Test("Login with non-existent user")
    func loginWithNonExistentUser() async throws {
        let loginUserDTO = LoginUserDTO(username: "nonexistent", password: "password123")
        
        try await withApp { app in
            try await app.testing().test(
                .POST, "users/login",
                beforeRequest: { req in
                    try req.content.encode(loginUserDTO)
                },
                afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                })
        }
    }
    
    @Test("Update password with short new password")
    func updatePasswordWithShortNewPassword() async throws {
        let username = "testuser"
        let password = "password123"
        
        try await withApp { app in
            let testUser = try await createUserAndLogin(username: username, password: password, on: app)
            
            guard let token = testUser.token else {
                Issue.record("Token is missing")
                return
            }
            
            let updateUserPasswordDTO = UpdateUserPasswordDTO(currentPassword: password, newPassword: "short")
            
            try await app.testing().test(
                .PATCH, "users/password",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: token)
                    try req.content.encode(updateUserPasswordDTO)
                },
                afterResponse: { res async in
                    #expect(res.status == .badRequest)
                })
        }
    }
    
    
}
