import Foundation

public struct AIAPICallError: Error, Equatable, CustomStringConvertible, Sendable {
    public var provider: String
    public var url: String?
    public var requestBody: JSONValue?
    public var statusCode: Int
    public var responseHeaders: [String: String]
    public var responseBody: String
    public var isRetryable: Bool

    public init(
        provider: String,
        url: String? = nil,
        requestBody: JSONValue? = nil,
        statusCode: Int,
        responseHeaders: [String: String] = [:],
        responseBody: String,
        isRetryable: Bool? = nil
    ) {
        self.provider = provider
        self.url = url
        self.requestBody = requestBody
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.isRetryable = isRetryable ?? Self.defaultRetryableStatus(statusCode)
    }

    public var description: String {
        "\(provider) request failed with HTTP \(statusCode): \(responseBody)"
    }

    private static func defaultRetryableStatus(_ statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 409 || statusCode == 429 || statusCode >= 500
    }
}

public struct AITypeValidationError: Error, Equatable, CustomStringConvertible, Sendable {
    public var value: JSONValue?
    public var schema: JSONValue?
    public var path: String
    public var message: String

    public init(
        value: JSONValue? = nil,
        schema: JSONValue? = nil,
        path: String,
        message: String
    ) {
        self.value = value
        self.schema = schema
        self.path = path
        self.message = message
    }

    public var description: String {
        "\(path): \(message)"
    }
}

public enum AINoOutputKind: String, Equatable, Sendable {
    case output
    case content
    case image
    case video
    case audio
    case speech
    case transcript
}

public struct AINoOutputError: Error, Equatable, CustomStringConvertible, Sendable {
    public var provider: String?
    public var kind: AINoOutputKind
    public var structuredOutputKind: AIOutputKind?
    public var responses: [AIResponseMetadata]
    public var message: String

    public init(
        provider: String? = nil,
        kind: AINoOutputKind = .output,
        structuredOutputKind: AIOutputKind? = nil,
        responses: [AIResponseMetadata] = [],
        message: String? = nil
    ) {
        self.provider = provider
        self.kind = kind
        self.structuredOutputKind = structuredOutputKind
        self.responses = responses
        self.message = message ?? Self.defaultMessage(kind: kind, structuredOutputKind: structuredOutputKind)
    }

    public var description: String {
        let providerPrefix = provider.map { "\($0) " } ?? ""
        return "\(providerPrefix)\(message)"
    }

    private static func defaultMessage(kind: AINoOutputKind, structuredOutputKind: AIOutputKind?) -> String {
        switch kind {
        case .output:
            if let structuredOutputKind {
                return "No \(structuredOutputKind.rawValue) output was generated."
            }
            return "No output was generated."
        case .content:
            return "No content was generated."
        case .image:
            return "No image was generated."
        case .video:
            return "No video was generated."
        case .audio:
            return "No audio was generated."
        case .speech:
            return "No speech audio was generated."
        case .transcript:
            return "No transcript was generated."
        }
    }
}

public struct AITooManyEmbeddingValuesForCallError: Error, Equatable, CustomStringConvertible, Sendable {
    public var provider: String
    public var modelID: String
    public var maxEmbeddingsPerCall: Int
    public var values: [String]

    public init(
        provider: String,
        modelID: String,
        maxEmbeddingsPerCall: Int,
        values: [String]
    ) {
        self.provider = provider
        self.modelID = modelID
        self.maxEmbeddingsPerCall = maxEmbeddingsPerCall
        self.values = values
    }

    public var description: String {
        "Too many values for a single embedding call. The \(provider) model \"\(modelID)\" can only embed up to \(maxEmbeddingsPerCall) values per call, but \(values.count) values were provided."
    }
}

public struct AINoSuchToolError: Error, Equatable, CustomStringConvertible, Sendable {
    public var toolName: String
    public var availableToolNames: [String]

    public init(toolName: String, availableToolNames: [String] = []) {
        self.toolName = toolName
        self.availableToolNames = availableToolNames.sorted()
    }

    public var description: String {
        guard !availableToolNames.isEmpty else {
            return "No such tool: \(toolName)."
        }
        return "No such tool: \(toolName). Available tools: \(availableToolNames.joined(separator: ", "))."
    }
}

public struct AIInvalidToolApprovalError: Error, Equatable, CustomStringConvertible, Sendable {
    public var approvalID: String

    public init(approvalID: String) {
        self.approvalID = approvalID
    }

    public var description: String {
        "Tool approval response references unknown approvalId: \"\(approvalID)\". No matching tool-approval-request found in message history."
    }
}

public struct AIToolCallNotFoundForApprovalError: Error, Equatable, CustomStringConvertible, Sendable {
    public var toolCallID: String
    public var approvalID: String

    public init(toolCallID: String, approvalID: String) {
        self.toolCallID = toolCallID
        self.approvalID = approvalID
    }

    public var description: String {
        "Tool call \"\(toolCallID)\" not found for approval request \"\(approvalID)\"."
    }
}

public struct AIInvalidToolInputError: Error, Equatable, CustomStringConvertible, Sendable {
    public var toolName: String
    public var toolCallID: String?
    public var input: JSONValue?
    public var message: String
    public var validationError: AITypeValidationError?

    public init(
        toolName: String,
        toolCallID: String? = nil,
        input: JSONValue? = nil,
        message: String,
        validationError: AITypeValidationError? = nil
    ) {
        self.toolName = toolName
        self.toolCallID = toolCallID
        self.input = input
        self.message = message
        self.validationError = validationError
    }

    public var description: String {
        let idSuffix = toolCallID.map { " call \($0)" } ?? ""
        return "Invalid input for tool \(toolName)\(idSuffix): \(message)"
    }
}

public struct AIToolCallRepairError: Error, Equatable, CustomStringConvertible, Sendable {
    public var toolName: String
    public var toolCallID: String?
    public var originalError: String
    public var repairedInput: JSONValue?

    public init(
        toolName: String,
        toolCallID: String? = nil,
        originalError: String,
        repairedInput: JSONValue? = nil
    ) {
        self.toolName = toolName
        self.toolCallID = toolCallID
        self.originalError = originalError
        self.repairedInput = repairedInput
    }

    public var description: String {
        let idSuffix = toolCallID.map { " call \($0)" } ?? ""
        return "Tool input repair failed for \(toolName)\(idSuffix): \(originalError)"
    }
}

public struct AIUIMessageStreamError: Error, Equatable, CustomStringConvertible, Sendable {
    public var message: String
    public var chunkType: String?
    public var chunkID: String?
    public var rawValue: JSONValue?
    public var validationIssues: [AIUIMessageValidationIssue]

    public init(
        message: String,
        chunkType: String? = nil,
        chunkID: String? = nil,
        rawValue: JSONValue? = nil,
        validationIssues: [AIUIMessageValidationIssue] = []
    ) {
        self.message = message
        self.chunkType = chunkType
        self.chunkID = chunkID
        self.rawValue = rawValue
        self.validationIssues = validationIssues
    }

    public var description: String {
        guard !validationIssues.isEmpty else { return message }
        return "\(message): \(validationIssues.map(\.description).joined(separator: "; "))"
    }
}

public extension AIError {
    static func apiCall(
        provider: String,
        statusCode: Int,
        body: String,
        headers: [String: String] = [:]
    ) -> AIError {
        .apiCall(AIAPICallError(
            provider: provider,
            statusCode: statusCode,
            responseHeaders: headers,
            responseBody: body
        ))
    }

    var apiCallError: AIAPICallError? {
        switch self {
        case let .apiCall(error):
            return error
        case let .gateway(error):
            return AIAPICallError(
                provider: "gateway",
                statusCode: error.statusCode,
                responseHeaders: error.headers,
                responseBody: error.message,
                isRetryable: error.isRetryable
            )
        default:
            return nil
        }
    }
}
