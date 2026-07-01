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

    private var toolCalls: [Int: TrackedStreamingToolCall] = [:]

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
        let index = delta.index ?? toolCalls.count
        if toolCalls[index] == nil {
            return try processNewToolCall(index: index, delta: delta)
        }
        return processExistingToolCall(index: index, delta: delta)
    }

    public mutating func flush() -> [LanguageStreamPart] {
        var parts: [LanguageStreamPart] = []
        for index in toolCalls.keys.sorted() {
            guard let toolCall = toolCalls[index], !toolCall.hasFinished else { continue }
            parts.append(contentsOf: finishToolCall(index: index, toolCall: toolCall))
        }
        return parts
    }

    private mutating func processNewToolCall(index: Int, delta: AIStreamingToolCallDelta) throws -> [LanguageStreamPart] {
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
        toolCalls[index] = toolCall

        var parts: [LanguageStreamPart] = [
            .toolInputStart(id: id, name: name)
        ]
        if !arguments.isEmpty {
            parts.append(.toolInputDelta(id: id, delta: arguments))
        }
        if isParsableJSON(arguments) {
            parts.append(contentsOf: finishToolCall(index: index, toolCall: toolCall))
        }
        return parts
    }

    private mutating func processExistingToolCall(index: Int, delta: AIStreamingToolCallDelta) -> [LanguageStreamPart] {
        guard var toolCall = toolCalls[index], !toolCall.hasFinished else {
            return []
        }

        var parts: [LanguageStreamPart] = []
        if let arguments = delta.arguments {
            toolCall.arguments += arguments
            toolCall.rawValue = delta.rawValue ?? toolCall.rawValue
            toolCalls[index] = toolCall
            parts.append(.toolInputDelta(id: toolCall.id, delta: arguments))
        }

        if isParsableJSON(toolCall.arguments) {
            parts.append(contentsOf: finishToolCall(index: index, toolCall: toolCall))
        }
        return parts
    }

    private mutating func finishToolCall(index: Int, toolCall: TrackedStreamingToolCall) -> [LanguageStreamPart] {
        var finished = toolCall
        finished.hasFinished = true
        toolCalls[index] = finished

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
