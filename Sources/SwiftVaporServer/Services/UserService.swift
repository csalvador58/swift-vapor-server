// File: SwiftVaporServer/Services/UserService.swift

import Fluent
import JWT
import Vapor

struct UserService {
    func createUser(dto: CreateUserDTO, req: Request) async throws -> User {
        
        // Validate user inputs
        try validateUsername(dto.username)
        try validatePassword(dto.password)
        
        // Validate username is unique
        try await validateUsernameDoesNotExist(dto.username.lowercased(), req: req)
        
        let passwordHash = try await req.password.async.hash(dto.password)
        let user = User(username: dto.username, passwordHash: passwordHash)
        
        try await user.save(on: req.db)
        
        return user
    }
    
    func authenticateUser(dto: LoginUserDTO, req: Request) async throws -> User {
        guard let user = try await User.query(on: req.db)
            .filter(\.$username == dto.username)
            .first()
        else {
            throw Abort(.unauthorized, reason: "Invalid credentials")
        }
        
        let passwordValidationResult = try await req.password.async.verify(dto.password, created: user.passwordHash)
        guard passwordValidationResult else {
            throw Abort(.unauthorized, reason: "Invalid credentials")
        }
        req.logger.info("User logged in", metadata: ["username": .string(user.username)])
        return user
    }
    
    func updatePassword(userId: UUID, dto: UpdateUserPasswordDTO, req: Request) async throws -> User {
        // Validate new password input
        try validatePassword(dto.newPassword)
        
        // Validate user exists
        guard let user = try await User.find(userId, on: req.db) else {
            throw Abort(.notFound)
        }
        
        let passwordValidationResult = try await req.password.async.verify(dto.currentPassword, created: user.passwordHash)
        guard passwordValidationResult else {
            throw Abort(.unauthorized, reason: "Invalid current password")
        }
        
        user.passwordHash = try await req.password.async.hash(dto.newPassword)
        try await user.save(on: req.db)
        
        return user
    }
    
    func deleteUser(userId: UUID, req: Request) async throws {
        guard let user = try await User.find(userId, on: req.db) else {
            throw Abort(.notFound)
        }
        
        try await user.delete(on: req.db)
    }
    
    func generateToken(for user: User, req: Request) async throws -> String {
        let userDTO = try user.toUserDTO()
        
        let payload = AuthPayload(
            subject: SubjectClaim(value: userDTO.id.uuidString),
            expiration: ExpirationClaim(value: .init(timeIntervalSinceNow: 60 * 60 * 24)),
            username: userDTO.username
        )
        
        return try await req.jwt.sign(payload)
    }
}

// MARK: - Private helpers
private extension UserService {
    func validateUsername(_ username: String) throws {
        guard !username.isEmpty else {
            throw Abort(.badRequest, reason: "Username is required")
        }
    }
    
    func validatePassword(_ password: String) throws {
        guard password.count >= 8 else {
            throw Abort(.badRequest, reason: "Password must be at least 8 characters long")
        }
    }
    
    func validateUsernameDoesNotExist(_ username: String, req: Request) async throws {
        let existingUser = try await User.query(on: req.db)
            .filter(\.$username == username.lowercased())
            .first()
        
        if existingUser != nil {
            throw Abort(.badRequest, reason: "Username already exists")
        }
    }
}

extension Request {
    var userService: UserService {
        UserService()
    }
}
