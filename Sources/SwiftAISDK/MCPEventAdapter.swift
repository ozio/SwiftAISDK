import Foundation

public struct MCPManagedSubscription: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case pending, active, needsAuth = "needs_auth", stopped, expired, failed
    }
    public enum CleanupStatus: String, Codable, Sendable { case pending, complete, exhausted }
    public var id: String
    public var name: String
    public var arguments: [String: JSONValue]
    public var status: Status
    public var expiresAt: String?
    public var cleanupStatus: CleanupStatus?

    public init(id: String, name: String, arguments: [String: JSONValue] = [:], status: Status, expiresAt: String?, cleanupStatus: CleanupStatus? = nil) {
        self.id = id; self.name = name; self.arguments = arguments; self.status = status
        self.expiresAt = expiresAt; self.cleanupStatus = cleanupStatus
    }
}

public struct MCPManagedSubscribeInput: Sendable {
    public enum Lifetime: Sendable { case milliseconds(Int), expiresAt(String?) }
    public var name: String
    public var arguments: [String: JSONValue]
    public var context: [String: JSONValue]?
    public var idempotencyKey: String
    public var lifetime: Lifetime
    public var options: MCPRequestOptions?

    public init(name: String, arguments: [String: JSONValue] = [:], context: [String: JSONValue]? = nil, idempotencyKey: String, lifetime: Lifetime, options: MCPRequestOptions? = nil) {
        self.name = name; self.arguments = arguments; self.context = context
        self.idempotencyKey = idempotencyKey; self.lifetime = lifetime; self.options = options
    }
}

public struct MCPManagedSubscriptionPage: Equatable, Sendable {
    public var subscriptions: [MCPManagedSubscription]
    public var nextCursor: String?
    public init(subscriptions: [MCPManagedSubscription], nextCursor: String? = nil) {
        self.subscriptions = subscriptions; self.nextCursor = nextCursor
    }
}

/// The application binds these operations to an authorized account and
/// destination. Its backend owns verification, renewal, storage and cleanup.
/// Cancelling a request does not undo an accepted remote subscription.
public protocol MCPEventOperations: Sendable {
    func subscribe(_ input: MCPManagedSubscribeInput) async throws -> MCPManagedSubscription
    func getSubscription(id: String, options: MCPRequestOptions?) async throws -> MCPManagedSubscription
    func listSubscriptions(cursor: String?, limit: Int?, status: MCPManagedSubscription.Status?, options: MCPRequestOptions?) async throws -> MCPManagedSubscriptionPage
    func unsubscribe(id: String, options: MCPRequestOptions?) async throws -> MCPManagedSubscription
}

public enum MCPEventTransportMetadata: Equatable, Sendable {
    case http(url: URL)
    case custom
}

/// A synchronous factory called once, before the MCP transport starts. It
/// receives configured endpoint metadata, never credentials or the transport.
public protocol MCPEventAdapter: Sendable {
    func createAdapter(transport: MCPEventTransportMetadata) throws -> any MCPEventOperations
}
