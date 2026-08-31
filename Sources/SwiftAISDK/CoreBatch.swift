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

// JSON numbers use IEEE-754 doubles throughout the provider adapters. Keep
// batch counters within JavaScript's exact integer range so converting them to
// `Int` cannot silently round a provider value or trap on overflow.
let aiBatchMaximumSafeInteger = 9_007_199_254_740_991

func normalizedBatchJSONInteger(_ value: JSONValue?) -> Int? {
    guard case let .number(number)? = value,
          number.isFinite,
          number >= 0,
          number <= Double(aiBatchMaximumSafeInteger),
          number.rounded(.towardZero) == number else {
        return nil
    }
    return Int(number)
}

func checkedBatchSafeIntegerSum(_ values: [Int]) -> Int? {
    var sum = 0
    for value in values {
        guard (0...aiBatchMaximumSafeInteger).contains(value) else { return nil }
        let addition = sum.addingReportingOverflow(value)
        guard !addition.overflow,
              addition.partialValue <= aiBatchMaximumSafeInteger else {
            return nil
        }
        sum = addition.partialValue
    }
    return sum
}

func normalizedBatchRequestCounts(
    total: Int?,
    pending: Int?,
    completed: Int?,
    failed: Int?
) -> AIBatchRequestCounts? {
    guard let total,
          let pending,
          let completed,
          let failed,
          (0...aiBatchMaximumSafeInteger).contains(total),
          let itemTotal = checkedBatchSafeIntegerSum([pending, completed, failed]),
          itemTotal == total else {
        return nil
    }
    return AIBatchRequestCounts(
        total: total,
        pending: pending,
        completed: completed,
        failed: failed
    )
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
    /// Optional callback URL for providers that support per-batch completion webhooks.
    public var webhookURL: String?

    public init(
        requests: [Request],
        providerOptions: [String: JSONValue] = [:],
        abortSignal: AIAbortSignal? = nil,
        headers: [String: String] = [:],
        idempotencyKey: String? = nil,
        webhookURL: String? = nil
    ) {
        self.requests = requests
        self.providerOptions = providerOptions
        self.abortSignal = abortSignal
        self.headers = headers
        self.idempotencyKey = idempotencyKey
        self.webhookURL = webhookURL
    }

    /// Source-compatible initializer retained for clients built against Batch V4
    /// before completion webhooks were added.
    public init(
        requests: [Request],
        providerOptions: [String: JSONValue] = [:],
        abortSignal: AIAbortSignal? = nil,
        headers: [String: String] = [:],
        idempotencyKey: String? = nil
    ) {
        self.init(
            requests: requests,
            providerOptions: providerOptions,
            abortSignal: abortSignal,
            headers: headers,
            idempotencyKey: idempotencyKey,
            webhookURL: nil
        )
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
    public var content: [AIResultContentPart]
    public var finishReason: String?
    public var rawFinishReason: String?
    public var usage: TokenUsage
    public var response: AIResponseMetadata?
    public var providerMetadata: [String: JSONValue]

    public init(
        text: String,
        content: [AIResultContentPart] = [],
        finishReason: String? = nil,
        rawFinishReason: String? = nil,
        usage: TokenUsage = TokenUsage(),
        response: AIResponseMetadata? = nil,
        providerMetadata: [String: JSONValue] = [:]
    ) {
        self.text = text
        self.content = content
        self.finishReason = finishReason
        self.rawFinishReason = rawFinishReason
        self.usage = usage
        self.response = response
        self.providerMetadata = providerMetadata
    }

    /// Source-compatible initializer retained from the text-only batch result.
    public init(
        text: String,
        finishReason: String? = nil,
        rawFinishReason: String? = nil,
        usage: TokenUsage = TokenUsage(),
        response: AIResponseMetadata? = nil,
        providerMetadata: [String: JSONValue] = [:]
    ) {
        self.init(
            text: text,
            content: [],
            finishReason: finishReason,
            rawFinishReason: rawFinishReason,
            usage: usage,
            response: response,
            providerMetadata: providerMetadata
        )
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
