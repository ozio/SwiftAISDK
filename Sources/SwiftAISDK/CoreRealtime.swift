import Foundation

/// Audio format configuration shared by realtime V4 model implementations.
public struct AIRealtimeAudioFormat: Equatable, Hashable, Sendable {
    public var type: String
    public var rate: Int?

    public init(type: String, rate: Int? = nil) {
        self.type = type
        self.rate = rate
    }

    public init(_ format: AIStreamingAudioFormat) {
        self.init(type: format.mediaType, rate: format.sampleRate)
    }
}

public enum AIRealtimeOutputModality: String, Equatable, Hashable, Sendable {
    case text
    case audio
}

public struct AIRealtimeAudioTranscriptionConfiguration:
    Equatable,
    Sendable {
    public var model: String?
    public var language: String?
    public var prompt: String?

    public init(
        model: String? = nil,
        language: String? = nil,
        prompt: String? = nil
    ) {
        self.model = model
        self.language = language
        self.prompt = prompt
    }
}

public enum AIRealtimeTurnDetectionType:
    String,
    Equatable,
    Hashable,
    Sendable {
    case serverVAD = "server-vad"
    case semanticVAD = "semantic-vad"
    case disabled
}

public struct AIRealtimeTurnDetectionConfiguration: Equatable, Sendable {
    public var type: AIRealtimeTurnDetectionType
    public var threshold: Double?
    public var silenceDurationMilliseconds: Int?
    public var prefixPaddingMilliseconds: Int?

    public init(
        type: AIRealtimeTurnDetectionType,
        threshold: Double? = nil,
        silenceDurationMilliseconds: Int? = nil,
        prefixPaddingMilliseconds: Int? = nil
    ) {
        self.type = type
        self.threshold = threshold
        self.silenceDurationMilliseconds = silenceDurationMilliseconds
        self.prefixPaddingMilliseconds = prefixPaddingMilliseconds
    }
}

public struct AIRealtimeToolDefinition: Equatable, Sendable {
    public var type: String
    public var name: String
    public var description: String?
    public var parameters: JSONValue

    public init(
        type: String = "function",
        name: String,
        description: String? = nil,
        parameters: JSONValue
    ) {
        self.type = type
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// Provider-neutral configuration for a realtime V4 session.
public struct AIRealtimeSessionConfiguration: Equatable, Sendable {
    public var instructions: String?
    public var voice: String?
    public var outputModalities: [AIRealtimeOutputModality]?
    public var inputAudioFormat: AIRealtimeAudioFormat?
    public var inputAudioTranscription:
        AIRealtimeAudioTranscriptionConfiguration?
    public var outputAudioTranscription:
        AIRealtimeAudioTranscriptionConfiguration?
    public var outputAudioFormat: AIRealtimeAudioFormat?
    public var turnDetection: AIRealtimeTurnDetectionConfiguration?
    public var tools: [AIRealtimeToolDefinition]?
    public var providerOptions: [String: JSONValue]?

    public init(
        instructions: String? = nil,
        voice: String? = nil,
        outputModalities: [AIRealtimeOutputModality]? = nil,
        inputAudioFormat: AIRealtimeAudioFormat? = nil,
        inputAudioTranscription:
            AIRealtimeAudioTranscriptionConfiguration? = nil,
        outputAudioTranscription:
            AIRealtimeAudioTranscriptionConfiguration? = nil,
        outputAudioFormat: AIRealtimeAudioFormat? = nil,
        turnDetection: AIRealtimeTurnDetectionConfiguration? = nil,
        tools: [AIRealtimeToolDefinition]? = nil,
        providerOptions: [String: JSONValue]? = nil
    ) {
        self.instructions = instructions
        self.voice = voice
        self.outputModalities = outputModalities
        self.inputAudioFormat = inputAudioFormat
        self.inputAudioTranscription = inputAudioTranscription
        self.outputAudioTranscription = outputAudioTranscription
        self.outputAudioFormat = outputAudioFormat
        self.turnDetection = turnDetection
        self.tools = tools
        self.providerOptions = providerOptions
    }
}

public struct AIRealtimeClientSecretOptions: Equatable, Sendable {
    public var expiresAfterSeconds: Int?
    public var sessionConfig: AIRealtimeSessionConfiguration?
    public var abortSignal: AIAbortSignal?

    public init(
        expiresAfterSeconds: Int? = nil,
        sessionConfig: AIRealtimeSessionConfiguration? = nil,
        abortSignal: AIAbortSignal? = nil
    ) {
        self.expiresAfterSeconds = expiresAfterSeconds
        self.sessionConfig = sessionConfig
        self.abortSignal = abortSignal
    }

    public static func == (
        lhs: AIRealtimeClientSecretOptions,
        rhs: AIRealtimeClientSecretOptions
    ) -> Bool {
        lhs.expiresAfterSeconds == rhs.expiresAfterSeconds
            && lhs.sessionConfig == rhs.sessionConfig
            && lhs.abortSignal === rhs.abortSignal
    }
}

public struct AIRealtimeClientSecretResult: Equatable, Sendable {
    public var token: String
    public var url: String
    public var expiresAt: Int?

    public init(token: String, url: String, expiresAt: Int? = nil) {
        self.token = token
        self.url = url
        self.expiresAt = expiresAt
    }
}

public struct AIRealtimeWebSocketConfiguration: Equatable, Sendable {
    public var url: String
    public var protocols: [String]
    public var headers: [String: String]

    public init(
        url: String,
        protocols: [String] = [],
        headers: [String: String] = [:]
    ) {
        self.url = url
        self.protocols = protocols
        self.headers = headers
    }
}

public enum AIRealtimeConversationItem: Equatable, Sendable {
    case textMessage(text: String)
    case audioMessage(audio: String)
    case functionCallOutput(callID: String, name: String?, output: String)
}

public struct AIRealtimeResponseOptions: Equatable, Sendable {
    public var modalities: [String]?
    public var instructions: String?
    public var metadata: [String: JSONValue]?

    public init(
        modalities: [String]? = nil,
        instructions: String? = nil,
        metadata: [String: JSONValue]? = nil
    ) {
        self.modalities = modalities
        self.instructions = instructions
        self.metadata = metadata
    }
}

/// Provider-neutral events sent from a realtime client to a V4 model.
public enum AIRealtimeClientEvent: Equatable, Sendable {
    case sessionUpdate(AIRealtimeSessionConfiguration)
    case inputAudioAppend(audio: String)
    case inputAudioCommit
    case inputAudioClear
    case conversationItemCreate(AIRealtimeConversationItem)
    case conversationItemTruncate(
        itemID: String,
        contentIndex: Int,
        audioEndMilliseconds: Int
    )
    case responseCreate(options: AIRealtimeResponseOptions? = nil)
    case responseCancel
}

/// A serialized provider message ready for a duplex WebSocket connection.
public enum AIRealtimeWireMessage: Equatable, Sendable {
    case json(JSONValue)
    case text(String)
    case binary(Data)
}

/// Normalized events emitted by a realtime V4 model.
public enum AIRealtimeServerEvent: Equatable, Sendable {
    case sessionCreated(sessionID: String?, raw: JSONValue)
    case sessionUpdated(raw: JSONValue)
    case speechStarted(itemID: String?, raw: JSONValue)
    case speechStopped(itemID: String?, raw: JSONValue)
    case audioCommitted(
        itemID: String?,
        previousItemID: String?,
        raw: JSONValue
    )
    case conversationItemAdded(
        itemID: String,
        item: JSONValue,
        raw: JSONValue
    )
    case inputTranscriptionCompleted(
        itemID: String,
        transcript: String,
        raw: JSONValue
    )
    case responseCreated(responseID: String, raw: JSONValue)
    case responseDone(responseID: String, status: String, raw: JSONValue)
    case outputItemAdded(
        responseID: String,
        itemID: String,
        raw: JSONValue
    )
    case outputItemDone(
        responseID: String,
        itemID: String,
        raw: JSONValue
    )
    case contentPartAdded(
        responseID: String,
        itemID: String,
        raw: JSONValue
    )
    case contentPartDone(
        responseID: String,
        itemID: String,
        raw: JSONValue
    )
    case audioDelta(
        responseID: String,
        itemID: String,
        delta: String,
        raw: JSONValue
    )
    case audioDone(responseID: String, itemID: String, raw: JSONValue)
    case audioTranscriptDelta(
        responseID: String,
        itemID: String,
        delta: String,
        raw: JSONValue
    )
    case audioTranscriptDone(
        responseID: String,
        itemID: String,
        transcript: String?,
        raw: JSONValue
    )
    case textDelta(
        responseID: String,
        itemID: String,
        delta: String,
        raw: JSONValue
    )
    case textDone(
        responseID: String,
        itemID: String,
        text: String?,
        raw: JSONValue
    )
    case functionCallArgumentsDelta(
        responseID: String,
        itemID: String,
        callID: String,
        delta: String,
        raw: JSONValue
    )
    case functionCallArgumentsDone(
        responseID: String,
        itemID: String,
        callID: String,
        name: String,
        arguments: String,
        raw: JSONValue
    )
    case error(message: String, code: String?, raw: JSONValue)
    case custom(rawType: String, raw: JSONValue)
}

/// Provider V4 contract for bidirectional audio/text realtime models.
public protocol AIRealtimeModelV4: Sendable {
    var specificationVersion: String { get }
    var providerID: String { get }
    var modelID: String { get }

    func doCreateClientSecret(
        _ options: AIRealtimeClientSecretOptions
    ) async throws -> AIRealtimeClientSecretResult

    func getWebSocketConfig(
        token: String,
        url: String
    ) -> AIRealtimeWebSocketConfiguration

    func parseServerEvent(_ raw: JSONValue) -> [AIRealtimeServerEvent]

    func serializeClientEvent(
        _ event: AIRealtimeClientEvent
    ) async throws -> AIRealtimeWireMessage?

    func buildSessionConfig(
        _ config: AIRealtimeSessionConfiguration
    ) -> JSONValue

    func getHealthCheckResponse(
        _ raw: JSONValue
    ) async throws -> AIRealtimeWireMessage?
}

public extension AIRealtimeModelV4 {
    var specificationVersion: String { "v4" }
    var provider: String { providerID }

    func createClientSecret(
        _ options: AIRealtimeClientSecretOptions = .init()
    ) async throws -> AIRealtimeClientSecretResult {
        try await doCreateClientSecret(options)
    }

    func parseServerEvent(_ raw: JSONValue) -> [AIRealtimeServerEvent] {
        [.custom(rawType: raw["type"]?.stringValue ?? "", raw: raw)]
    }

    func getHealthCheckResponse(
        _ raw: JSONValue
    ) async throws -> AIRealtimeWireMessage? {
        nil
    }
}

/// Mirrors the experimental naming of `@ai-sdk/provider` V4.
public typealias Experimental_RealtimeModelV4 = AIRealtimeModelV4
public typealias Experimental_RealtimeModelV4ClientEvent =
    AIRealtimeClientEvent
public typealias Experimental_RealtimeModelV4ServerEvent =
    AIRealtimeServerEvent
public typealias Experimental_RealtimeModelV4SessionConfig =
    AIRealtimeSessionConfiguration
public typealias Experimental_RealtimeModelV4ClientSecretOptions =
    AIRealtimeClientSecretOptions
public typealias Experimental_RealtimeModelV4ClientSecretResult =
    AIRealtimeClientSecretResult
