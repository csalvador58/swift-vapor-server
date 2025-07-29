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
    await app.jwt.keys.add(hmac: "your-secret-key", digestAlgorithm: .sha256)
    
    // Configure password hasher
    app.passwords.use(.bcrypt)

    app.databases.use(DatabaseConfigurationFactory.sqlite(.file("db.sqlite")), as: .sqlite)

    app.migrations.add(CreateUser())

    // register routes
    try routes(app)
}
