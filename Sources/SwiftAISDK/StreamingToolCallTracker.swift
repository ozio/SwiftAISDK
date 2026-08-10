import Foundation

public enum AIStreamingToolCallTypeValidation: Sendable {
    case none
    case ifPresent
    case required
}

public struct AIStreamingToolCallDelta: Equatable, Sendable {
    public var index: Int?
    public var id: String?
    public var type: String?
    public var functionName: String?
    public var arguments: String?
    public var rawValue: JSONValue?

    public init(
        index: Int? = nil,
        id: String? = nil,
        type: String? = nil,
        functionName: String? = nil,
        arguments: String? = nil,
        rawValue: JSONValue? = nil
    ) {
        self.index = index
        self.id = id
        self.type = type
        self.functionName = functionName
        self.arguments = arguments
        self.rawValue = rawValue
    }
}

public struct AIStreamingToolCallTracker: Sendable {
    public var generateID: @Sendable () -> String
    public var typeValidation: AIStreamingToolCallTypeValidation
    public var extractMetadata: (@Sendable (AIStreamingToolCallDelta) -> [String: JSONValue]?)?
    public var buildToolCallProviderMetadata: (@Sendable ([String: JSONValue]?) -> [String: JSONValue]?)?

    private var toolCalls: [TrackedStreamingToolCall] = []
    private var toolCallPositionsByID: [String: Int] = [:]
    private var toolCallPositionsByIndex: [Int: Int] = [:]
    private var latestToolCallPosition: Int?

    public init(
        generateID: @escaping @Sendable () -> String = { UUID().uuidString },
        typeValidation: AIStreamingToolCallTypeValidation = .none,
        extractMetadata: (@Sendable (AIStreamingToolCallDelta) -> [String: JSONValue]?)? = nil,
        buildToolCallProviderMetadata: (@Sendable ([String: JSONValue]?) -> [String: JSONValue]?)? = nil
    ) {
        self.generateID = generateID
        self.typeValidation = typeValidation
        self.extractMetadata = extractMetadata
        self.buildToolCallProviderMetadata = buildToolCallProviderMetadata
    }

    public mutating func processDelta(_ delta: AIStreamingToolCallDelta) throws -> [LanguageStreamPart] {
        let position: Int?
        if let id = delta.id, !id.isEmpty {
            position = toolCallPositionsByID[id]
        } else if let index = delta.index {
            position = toolCallPositionsByIndex[index]
        } else {
            position = latestToolCallPosition
        }

        let resolvedPosition: Int
        let parts: [LanguageStreamPart]
        if let position {
            resolvedPosition = position
            parts = processExistingToolCall(position: position, delta: delta)
        } else {
            let created = try processNewToolCall(delta: delta)
            resolvedPosition = created.position
            parts = created.parts
        }

        if let index = delta.index {
            toolCallPositionsByIndex[index] = resolvedPosition
        }
        latestToolCallPosition = resolvedPosition
        return parts
    }

    public mutating func flush() -> [LanguageStreamPart] {
        var parts: [LanguageStreamPart] = []
        for position in toolCalls.indices where !toolCalls[position].hasFinished {
            parts.append(contentsOf: finishToolCall(position: position))
        }
        return parts
    }

    private mutating func processNewToolCall(delta: AIStreamingToolCallDelta) throws -> (position: Int, parts: [LanguageStreamPart]) {
        switch typeValidation {
        case .required:
            guard delta.type == "function" else {
                throw AIError.invalidResponse(provider: "provider-utils", message: "Expected 'function' type.")
            }
        case .ifPresent:
            guard delta.type == nil || delta.type == "function" else {
                throw AIError.invalidResponse(provider: "provider-utils", message: "Expected 'function' type.")
            }
        case .none:
            break
        }

        guard let id = delta.id else {
            throw AIError.invalidResponse(provider: "provider-utils", message: "Expected 'id' to be a string.")
        }
        guard let name = delta.functionName else {
            throw AIError.invalidResponse(provider: "provider-utils", message: "Expected 'function.name' to be a string.")
        }

        let arguments = delta.arguments ?? ""
        let metadata = extractMetadata?(delta)
        let toolCall = TrackedStreamingToolCall(
            id: id,
            name: name,
            arguments: arguments,
            hasFinished: false,
            metadata: metadata,
            rawValue: delta.rawValue
        )
        let position = toolCalls.endIndex
        toolCalls.append(toolCall)
        if !id.isEmpty {
            toolCallPositionsByID[id] = position
        }

        var parts: [LanguageStreamPart] = [
            .toolInputStart(id: id, name: name)
        ]
        if !arguments.isEmpty {
            parts.append(.toolInputDelta(id: id, delta: arguments))
        }
        return (position, parts)
    }

    private mutating func processExistingToolCall(position: Int, delta: AIStreamingToolCallDelta) -> [LanguageStreamPart] {
        guard toolCalls.indices.contains(position), !toolCalls[position].hasFinished else {
            return []
        }

        guard let arguments = delta.arguments else {
            return []
        }
        toolCalls[position].arguments += arguments
        toolCalls[position].rawValue = delta.rawValue ?? toolCalls[position].rawValue
        return [.toolInputDelta(id: toolCalls[position].id, delta: arguments)]
    }

    private mutating func finishToolCall(position: Int) -> [LanguageStreamPart] {
        let toolCall = toolCalls[position]
        toolCalls[position].hasFinished = true

        let providerMetadata = buildToolCallProviderMetadata?(toolCall.metadata) ?? [:]
        return [
            .toolInputEnd(id: toolCall.id),
            .toolCall(AIToolCall(
                id: toolCall.id,
                name: toolCall.name,
                arguments: toolCall.arguments,
                providerMetadata: providerMetadata,
                rawValue: toolCall.rawValue
            ))
        ]
    }
}

private struct TrackedStreamingToolCall: Sendable {
    var id: String
    var name: String
    var arguments: String
    var hasFinished: Bool
    var metadata: [String: JSONValue]?
    var rawValue: JSONValue?
}
