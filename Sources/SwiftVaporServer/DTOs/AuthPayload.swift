// File: SwiftVaporServer/DTOs/AuthPayload.swift

import Foundation
import JWT
import Vapor

struct AuthPayload: JWTPayload, Authenticatable {
    enum CodingKeys: String, CodingKey {
        case subject = "sub"
        case expiration = "exp"
        case username = "user"
    }
    
    var subject: SubjectClaim
    var expiration: ExpirationClaim
    var username: String
    
    var userId: UUID {
        UUID(uuidString: subject.value)!
    }
    
    func verify(using algorithm: some JWTAlgorithm) async throws {
        try self.expiration.verifyNotExpired()
    }
}
