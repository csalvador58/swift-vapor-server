// File: SwiftVaporServer/Controllers/UserController.swift

import Fluent
import Vapor
import JWT

struct UserController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let users = routes.grouped("users")
        
        users.post("register", use: self.createUser)
        users.post("login", use: self.loginUser)
        
        let protected = users.grouped(UserAuthenticator())
        protected.delete(use: self.deleteUser)
        protected.patch("password", use: self.updateUserPassword)
    }
    
    @Sendable
    func createUser(req: Request) async throws -> UserTokenDTO {
        let createUserDTO = try req.content.decode(CreateUserDTO.self)
        
        let user = try await req.userService.createUser(dto: createUserDTO, req: req)
        let token = try await req.userService.generateToken(for: user, req: req)
        
        return UserTokenDTO(token: token, user: try user.toUserDTO())
    }
    
    @Sendable
    func loginUser(req: Request) async throws -> UserTokenDTO {
        let loginUserDTO = try req.content.decode(LoginUserDTO.self)
        
        let user = try await req.userService.authenticateUser(dto: loginUserDTO, req: req)
        let token = try await req.userService.generateToken(for: user, req: req)
        
        return UserTokenDTO(token: token, user: try user.toUserDTO())
    }
    
    @Sendable
    func deleteUser(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(AuthPayload.self)
        
        try await req.userService.deleteUser(userId: payload.userId, req: req)
        return .noContent
    }
    
    @Sendable
    func updateUserPassword(req: Request) async throws -> UserDTO {
        let updateDTO = try req.content.decode(UpdateUserPasswordDTO.self)
        let payload = try req.auth.require(AuthPayload.self)
        
        let user = try await req.userService.updatePassword(
            userId: payload.userId,
            dto: updateDTO,
            req: req
        )
        
        return try user.toUserDTO()
    }
}

struct UserAuthenticator: AsyncBearerAuthenticator {
    func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
        do {
            let payload = try await request.jwt.verify(bearer.token, as: AuthPayload.self)
            request.auth.login(payload)
        } catch {
            request.logger.debug("JWT authentication failed: \(error)")
        }
    }
}

