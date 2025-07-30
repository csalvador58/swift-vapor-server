// File: SwiftVaporServer/configure.swift

import NIOSSL
import Fluent
import FluentSQLiteDriver
import Vapor
import JWT

// configures your application
public func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    
    // Configure JWT with HMAC SHA-256
    let jwtSecret = Environment.get("JWT_SECRET") ?? "your-secret-key"
    let hmacKey = HMACKey(from: Data(jwtSecret.utf8))
    await app.jwt.keys.add(hmac: hmacKey, digestAlgorithm: .sha256)
    
    // Configure password hasher
    app.passwords.use(.bcrypt)

    let databaseFile = Environment.get("DATABASE_FILE") ?? "db.sqlite"
    app.databases.use(DatabaseConfigurationFactory.sqlite(.file(databaseFile)), as: .sqlite)

    app.migrations.add(CreateUser())

    // register routes
    try routes(app)
}
