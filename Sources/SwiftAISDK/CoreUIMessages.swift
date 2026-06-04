import Foundation

public struct AIUITextPart: Equatable, Hashable, Sendable {
    public var id: String?
    public var text: String
    public var providerMetadata: [String: JSONValue]

    public init(
        id: String? = nil,
        text: String,
        providerMetadata: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.text = text
        self.providerMetadata = providerMetadata
    }
}

public struct AIUIReasoningPart: Equatable, Hashable, Sendable {
    public var id: String?
    public var text: String
    public var providerMetadata: [String: JSONValue]

    public init(
        id: String? = nil,
        text: String,
        providerMetadata: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.text = text
        self.providerMetadata = providerMetadata
    }
}

public struct AIUIDataPart: Equatable, Hashable, Sendable {
    public var id: String?
    public var value: JSONValue
    public var providerMetadata: [String: JSONValue]

    public init(
        id: String? = nil,
        value: JSONValue,
        providerMetadata: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.value = value
        self.providerMetadata = providerMetadata
    }
}

public enum AIUIMessagePart: Equatable, Hashable, Sendable {
    case text(AIUITextPart)
    case reasoning(AIUIReasoningPart)
    case source(AISource)
    case file(AIStreamFile)
    case reasoningFile(AIStreamFile)
    case toolCall(AIToolCall)
    case toolResult(AIToolResult)
    case toolApprovalRequest(AIToolApprovalRequest)
    case toolApprovalResponse(AIToolApprovalResponse)
    case data(AIUIDataPart)
    case metadata([String: JSONValue])
    case error(message: String, rawValue: JSONValue?)
    case custom(JSONValue, providerMetadata: [String: JSONValue] = [:])
    case raw(JSONValue)
}

public struct AIUIMessage: Equatable, Hashable, Sendable {
    public var id: String
    public var role: MessageRole
    public var parts: [AIUIMessagePart]
    public var metadata: [String: JSONValue]

    public init(
        id: String = UUID().uuidString,
        role: MessageRole,
        parts: [AIUIMessagePart] = [],
        metadata: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.role = role
        self.parts = parts
        self.metadata = metadata
    }

    public static func system(
        _ text: String,
        id: String = UUID().uuidString,
        metadata: [String: JSONValue] = [:]
    ) -> AIUIMessage {
        AIUIMessage(
            id: id,
            role: .system,
            parts: [.text(AIUITextPart(text: text))],
            metadata: metadata
        )
    }

    public static func user(
        _ text: String,
        id: String = UUID().uuidString,
        metadata: [String: JSONValue] = [:]
    ) -> AIUIMessage {
        AIUIMessage(
            id: id,
            role: .user,
            parts: [.text(AIUITextPart(text: text))],
            metadata: metadata
        )
    }

    public static func assistant(
        id: String = UUID().uuidString,
        parts: [AIUIMessagePart] = [],
        metadata: [String: JSONValue] = [:]
    ) -> AIUIMessage {
        AIUIMessage(id: id, role: .assistant, parts: parts, metadata: metadata)
    }

    public var text: String {
        parts.compactMap { part in
            if case let .text(textPart) = part {
                return textPart.text
            }
            return nil
        }.joined()
    }

    public var reasoning: String {
        parts.compactMap { part in
            if case let .reasoning(reasoningPart) = part {
                return reasoningPart.text
            }
            return nil
        }.joined()
    }
}
