import Foundation

public struct FileUploadRequest: Sendable {
    public var data: Data
    public var mediaType: String
    public var filename: String?
    public var purpose: String?
    public var displayName: String?
    public var pollIntervalNanoseconds: UInt64
    public var pollTimeoutNanoseconds: UInt64
    public var providerOptions: [String: JSONValue]
    public var extraBody: [String: JSONValue]
    public var headers: [String: String]
    public var abortSignal: AIAbortSignal?

    public init(
        data: Data,
        mediaType: String,
        filename: String? = nil,
        purpose: String? = nil,
        displayName: String? = nil,
        pollIntervalNanoseconds: UInt64 = 2_000_000_000,
        pollTimeoutNanoseconds: UInt64 = 300_000_000_000,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil
    ) {
        self.data = data
        self.mediaType = mediaType
        self.filename = filename
        self.purpose = purpose
        self.displayName = displayName
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.pollTimeoutNanoseconds = pollTimeoutNanoseconds
        self.providerOptions = providerOptions
        self.extraBody = extraBody
        self.headers = headers
        self.abortSignal = abortSignal
    }
}

public struct FileUploadResult: Sendable {
    public var providerReference: [String: String]
    public var filename: String?
    public var mediaType: String?
    public var metadata: [String: JSONValue]
    public var rawValue: JSONValue
    public var warnings: [AIWarning]
    public var providerMetadata: [String: JSONValue]
    public var requestMetadata: AIRequestMetadata
    public var responseMetadata: AIResponseMetadata

    public init(
        providerReference: [String: String],
        filename: String? = nil,
        mediaType: String? = nil,
        metadata: [String: JSONValue] = [:],
        rawValue: JSONValue,
        warnings: [AIWarning] = [],
        providerMetadata: [String: JSONValue] = [:],
        requestMetadata: AIRequestMetadata = AIRequestMetadata(),
        responseMetadata: AIResponseMetadata = AIResponseMetadata()
    ) {
        self.providerReference = providerReference
        self.filename = filename
        self.mediaType = mediaType
        self.metadata = metadata
        self.rawValue = rawValue
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.requestMetadata = requestMetadata
        self.responseMetadata = responseMetadata
    }
}

public struct SkillUploadFile: Equatable, Sendable {
    public var path: String
    public var data: Data
    public var mediaType: String

    public init(path: String, data: Data, mediaType: String = "application/octet-stream") {
        self.path = path
        self.data = data
        self.mediaType = mediaType
    }
}

public struct SkillUploadRequest: Sendable {
    public var files: [SkillUploadFile]
    public var displayTitle: String?
    public var headers: [String: String]
    public var abortSignal: AIAbortSignal?

    public init(files: [SkillUploadFile], displayTitle: String? = nil, headers: [String: String] = [:], abortSignal: AIAbortSignal? = nil) {
        self.files = files
        self.displayTitle = displayTitle
        self.headers = headers
        self.abortSignal = abortSignal
    }
}

public struct AIWarning: Equatable, Sendable {
    public var type: String
    public var feature: String?
    public var setting: String?
    public var message: String?

    public init(type: String, feature: String? = nil, setting: String? = nil, message: String? = nil) {
        self.type = type
        self.feature = feature
        self.setting = setting
        self.message = message
    }
}

public struct SkillUploadResult: Sendable {
    public var providerReference: [String: String]
    public var displayTitle: String?
    public var name: String?
    public var description: String?
    public var latestVersion: String?
    public var providerMetadata: [String: JSONValue]
    public var requestMetadata: AIRequestMetadata
    public var responseMetadata: AIResponseMetadata
    public var warnings: [AIWarning]
    public var rawValue: JSONValue

    public init(
        providerReference: [String: String],
        displayTitle: String? = nil,
        name: String? = nil,
        description: String? = nil,
        latestVersion: String? = nil,
        providerMetadata: [String: JSONValue] = [:],
        requestMetadata: AIRequestMetadata = AIRequestMetadata(),
        responseMetadata: AIResponseMetadata = AIResponseMetadata(),
        warnings: [AIWarning] = [],
        rawValue: JSONValue
    ) {
        self.providerReference = providerReference
        self.displayTitle = displayTitle
        self.name = name
        self.description = description
        self.latestVersion = latestVersion
        self.providerMetadata = providerMetadata
        self.requestMetadata = requestMetadata
        self.responseMetadata = responseMetadata
        self.warnings = warnings
        self.rawValue = rawValue
    }
}

public struct TokenUsage: Equatable, Codable, Sendable {
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var totalTokens: Int?
    public var inputTokensNoCache: Int?
    public var inputTokensCacheRead: Int?
    public var inputTokensCacheWrite: Int?
    public var outputTextTokens: Int?
    public var outputReasoningTokens: Int?
    public var rawValue: JSONValue?

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        inputTokensNoCache: Int? = nil,
        inputTokensCacheRead: Int? = nil,
        inputTokensCacheWrite: Int? = nil,
        outputTextTokens: Int? = nil,
        outputReasoningTokens: Int? = nil,
        rawValue: JSONValue? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.inputTokensNoCache = inputTokensNoCache
        self.inputTokensCacheRead = inputTokensCacheRead
        self.inputTokensCacheWrite = inputTokensCacheWrite
        self.outputTextTokens = outputTextTokens
        self.outputReasoningTokens = outputReasoningTokens
        self.rawValue = rawValue
    }
}
