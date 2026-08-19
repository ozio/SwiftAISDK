import Foundation

/// Serializable error information for a durable batch or one of its items.
public struct AIBatchError: Error, Equatable, Codable, Sendable, CustomStringConvertible {
    public var message: String
    public var type: String?
    public var code: String?
    public var statusCode: Int?

    public init(message: String, type: String? = nil, code: String? = nil, statusCode: Int? = nil) {
        self.message = message
        self.type = type
        self.code = code
        self.statusCode = statusCode
    }

    public var description: String { message }
}

public enum AIBatchLifecycleStatus: String, Equatable, Hashable, Codable, Sendable {
    case pending
    case completed
    case failed
}

public struct AIBatchRequestCounts: Equatable, Codable, Sendable {
    public var total: Int
    public var pending: Int
    public var completed: Int
    public var failed: Int

    public init(total: Int, pending: Int, completed: Int, failed: Int) {
        self.total = total
        self.pending = pending
        self.completed = completed
        self.failed = failed
    }
}

/// Normalized, provider-independent lifecycle status for a durable batch.
public struct AIBatchStatus: Equatable, Codable, Sendable {
    public var status: AIBatchLifecycleStatus
    public var rawStatus: String?
    public var requestCounts: AIBatchRequestCounts?
    public var error: AIBatchError?
    public var createdAt: String?
    public var expiresAt: String?
    public var providerMetadata: [String: JSONValue]

    public init(
        status: AIBatchLifecycleStatus,
        rawStatus: String? = nil,
        requestCounts: AIBatchRequestCounts? = nil,
        error: AIBatchError? = nil,
        createdAt: String? = nil,
        expiresAt: String? = nil,
        providerMetadata: [String: JSONValue] = [:]
    ) {
        self.status = status
        self.rawStatus = rawStatus
        self.requestCounts = requestCounts
        self.error = error
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.providerMetadata = providerMetadata
    }
}

public struct AIBatchWarning: Equatable, Sendable {
    public var requestID: String?
    public var warning: AIWarning

    public init(requestID: String? = nil, warning: AIWarning) {
        self.requestID = requestID
        self.warning = warning
    }
}

public struct AIBatchStartOptions<Request: Sendable>: Sendable {
    public var requests: [Request]
    public var providerOptions: [String: JSONValue]
    public var abortSignal: AIAbortSignal?
    public var headers: [String: String]
    /// Optional stable key forwarded to providers that implement idempotent batch creation.
    public var idempotencyKey: String?

    public init(
        requests: [Request],
        providerOptions: [String: JSONValue] = [:],
        abortSignal: AIAbortSignal? = nil,
        headers: [String: String] = [:],
        idempotencyKey: String? = nil
    ) {
        self.requests = requests
        self.providerOptions = providerOptions
        self.abortSignal = abortSignal
        self.headers = headers
        self.idempotencyKey = idempotencyKey
    }
}

public struct AIBatchStartResult: Equatable, Sendable {
    public var batchID: String
    public var status: AIBatchStatus
    public var warnings: [AIBatchWarning]

    public init(batchID: String, status: AIBatchStatus, warnings: [AIBatchWarning] = []) {
        self.batchID = batchID
        self.status = status
        self.warnings = warnings
    }
}

public struct AIBatchOperationOptions: Sendable {
    public var batchID: String
    public var providerOptions: [String: JSONValue]
    public var abortSignal: AIAbortSignal?
    public var headers: [String: String]

    public init(
        batchID: String,
        providerOptions: [String: JSONValue] = [:],
        abortSignal: AIAbortSignal? = nil,
        headers: [String: String] = [:]
    ) {
        self.batchID = batchID
        self.providerOptions = providerOptions
        self.abortSignal = abortSignal
        self.headers = headers
    }
}

/// One terminal provider result. Individual failures do not terminate the result stream.
public enum AIBatchItemResult<Result: Sendable>: Sendable {
    case succeeded(id: String, result: Result)
    case failed(id: String, error: AIBatchError, providerMetadata: [String: JSONValue] = [:])
    case cancelled(id: String, error: AIBatchError? = nil, providerMetadata: [String: JSONValue] = [:])
    case expired(id: String, error: AIBatchError? = nil, providerMetadata: [String: JSONValue] = [:])

    public var id: String {
        switch self {
        case let .succeeded(id, _),
             let .failed(id, _, _),
             let .cancelled(id, _, _),
             let .expired(id, _, _):
            return id
        }
    }
}

public struct AILanguageModelBatchRequest: Sendable {
    public var id: String
    public var request: LanguageModelRequest

    public init(id: String, request: LanguageModelRequest) {
        self.id = id
        self.request = request
    }
}

/// Durable Batch V4 capability for language models.
public protocol BatchLanguageModel: LanguageModel {
    func startBatch(_ options: AIBatchStartOptions<AILanguageModelBatchRequest>) async throws -> AIBatchStartResult
    func getBatchStatus(_ options: AIBatchOperationOptions) async throws -> AIBatchStatus
    func getBatchResults(
        _ options: AIBatchOperationOptions
    ) async throws -> AsyncThrowingStream<AIBatchItemResult<TextGenerationResult>, Error>
}

public enum AIBatchReferenceType: String, Equatable, Hashable, Codable, Sendable {
    case text
}

/// Persistable identity of a durable text batch.
public struct TextBatchReference: Equatable, Hashable, Codable, Sendable {
    public let version: Int
    public let type: AIBatchReferenceType
    public var id: String
    public var providerID: String
    public var modelID: String

    public init(
        version: Int = 1,
        type: AIBatchReferenceType = .text,
        id: String,
        providerID: String,
        modelID: String
    ) {
        self.version = version
        self.type = type
        self.id = id
        self.providerID = providerID
        self.modelID = modelID
    }
}

public struct TextBatch: Equatable, Codable, Sendable {
    public var reference: TextBatchReference
    public var status: AIBatchStatus

    public init(reference: TextBatchReference, status: AIBatchStatus) {
        self.reference = reference
        self.status = status
    }
}

public struct TextBatchRequest: Sendable {
    public var id: String
    public var request: LanguageModelRequest

    public init(id: String, request: LanguageModelRequest) {
        self.id = id
        self.request = request
    }
}

public struct StartTextBatchResult: Equatable, Sendable {
    public var batch: TextBatch
    public var warnings: [AIBatchWarning]

    public init(batch: TextBatch, warnings: [AIBatchWarning] = []) {
        self.batch = batch
        self.warnings = warnings
    }
}

public struct TextBatchGenerationResult: Sendable {
    public var text: String
    public var finishReason: String?
    public var rawFinishReason: String?
    public var usage: TokenUsage
    public var response: AIResponseMetadata?
    public var providerMetadata: [String: JSONValue]

    public init(
        text: String,
        finishReason: String? = nil,
        rawFinishReason: String? = nil,
        usage: TokenUsage = TokenUsage(),
        response: AIResponseMetadata? = nil,
        providerMetadata: [String: JSONValue] = [:]
    ) {
        self.text = text
        self.finishReason = finishReason
        self.rawFinishReason = rawFinishReason
        self.usage = usage
        self.response = response
        self.providerMetadata = providerMetadata
    }
}

public enum TextBatchItemResult: Sendable {
    case succeeded(id: String, result: TextBatchGenerationResult)
    case failed(id: String, error: AIBatchError, providerMetadata: [String: JSONValue] = [:])
    case cancelled(id: String, error: AIBatchError? = nil, providerMetadata: [String: JSONValue] = [:])
    case expired(id: String, error: AIBatchError? = nil, providerMetadata: [String: JSONValue] = [:])

    public var id: String {
        switch self {
        case let .succeeded(id, _),
             let .failed(id, _, _),
             let .cancelled(id, _, _),
             let .expired(id, _, _):
            return id
        }
    }
}
