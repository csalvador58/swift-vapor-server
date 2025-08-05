// File: SwiftVaporServer/Utils/Utils.swift

import Vapor

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
