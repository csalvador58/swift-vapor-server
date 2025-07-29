// File: SwiftVaporServer/DTOs/AuthPayload.swift

import Foundation
import JWT
import Vapor

struct AuthPayload: JWTPayload {
    enum CodingKeys: String, CodingKey {
        case subject = "sub"
        case expiration = "exp"
        case userId = "userId"
        case username = "username"
    }
    
    var subject: SubjectClaim
    var expiration: ExpirationClaim
    var userId: UUID
    var username: String
    
    func verify(using algorithm: some JWTAlgorithm) async throws {
        try self.expiration.verifyNotExpired()
    }
}
