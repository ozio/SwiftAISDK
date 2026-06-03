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

public struct AINoOutputGeneratedError: Error, Equatable, CustomStringConvertible, Sendable {
    public var provider: String?
    public var outputKind: AIOutputKind?
    public var message: String

    public init(
        provider: String? = nil,
        outputKind: AIOutputKind? = nil,
        message: String = "No output was generated."
    ) {
        self.provider = provider
        self.outputKind = outputKind
        self.message = message
    }

    public var description: String {
        let providerPrefix = provider.map { "\($0) " } ?? ""
        let outputSuffix = outputKind.map { " for \($0.rawValue) output" } ?? ""
        return "\(providerPrefix)did not generate output\(outputSuffix): \(message)"
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

public extension AIError {
    var apiCallError: AIAPICallError? {
        switch self {
        case let .httpStatus(provider, statusCode, body):
            return AIAPICallError(
                provider: provider,
                statusCode: statusCode,
                responseBody: body
            )
        case let .httpStatusWithHeaders(provider, statusCode, body, headers):
            return AIAPICallError(
                provider: provider,
                statusCode: statusCode,
                responseHeaders: headers,
                responseBody: body
            )
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
