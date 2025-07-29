// File: SwiftVaporServer/DTOs/UserDTO.swift

import Fluent
import Vapor

struct UserDTO: Content {
    let id: UUID
    let username: String
    let createdAt: Date?
    let updatedAt: Date?
}

struct CreateUserDTO: Content {
    let username: String
    let password: String
}

struct LoginUserDTO: Content {
    let username: String
    let password: String
}

struct UpdateUserPasswordDTO: Content {
    let currentPassword: String
    let newPassword: String
}

struct UserTokenDTO: Content {
    let token: String
    let user: UserDTO
}
