import Foundation

public struct AudioTranscriptionRequest: Sendable {
    public var audio: Data
    public var fileName: String
    public var mimeType: String
    public var language: String?
    public var prompt: String?
    public var providerOptions: [String: JSONValue]
    public var extraBody: [String: JSONValue]
    public var headers: [String: String]
    public var abortSignal: AIAbortSignal?

    public init(
        audio: Data,
        fileName: String = "audio.wav",
        mimeType: String = "audio/wav",
        language: String? = nil,
        prompt: String? = nil,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil
    ) {
        self.audio = audio
        self.fileName = fileName
        self.mimeType = mimeType
        self.language = language
        self.prompt = prompt
        self.providerOptions = providerOptions
        self.extraBody = extraBody
        self.headers = headers
        self.abortSignal = abortSignal
    }
}

public struct TranscriptionResult: Sendable {
    public var text: String
    public var rawValue: JSONValue
    public var segments: [TranscriptionSegment]
    public var language: String?
    public var durationInSeconds: Double?
    public var warnings: [AIWarning]
    public var providerMetadata: [String: JSONValue]
    public var requestMetadata: AIRequestMetadata
    public var responseMetadata: AIResponseMetadata

    public init(
        text: String,
        rawValue: JSONValue,
        segments: [TranscriptionSegment] = [],
        language: String? = nil,
        durationInSeconds: Double? = nil,
        warnings: [AIWarning] = [],
        providerMetadata: [String: JSONValue] = [:],
        requestMetadata: AIRequestMetadata = AIRequestMetadata(),
        responseMetadata: AIResponseMetadata = AIResponseMetadata()
    ) {
        self.text = text
        self.rawValue = rawValue
        self.segments = segments
        self.language = language
        self.durationInSeconds = durationInSeconds
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.requestMetadata = requestMetadata
        self.responseMetadata = responseMetadata
    }
}

public struct TranscriptionSegment: Equatable, Sendable {
    public var text: String
    public var startSecond: Double
    public var endSecond: Double

    public init(text: String, startSecond: Double, endSecond: Double) {
        self.text = text
        self.startSecond = startSecond
        self.endSecond = endSecond
    }
}

public struct SpeechRequest: Sendable {
    public var text: String
    public var voice: String?
    public var format: String?
    public var speed: Double?
    public var language: String?
    public var instructions: String?
    public var providerOptions: [String: JSONValue]
    public var extraBody: [String: JSONValue]
    public var headers: [String: String]
    public var abortSignal: AIAbortSignal?

    public init(
        text: String,
        voice: String? = nil,
        format: String? = nil,
        speed: Double? = nil,
        language: String? = nil,
        instructions: String? = nil,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil
    ) {
        self.text = text
        self.voice = voice
        self.format = format
        self.speed = speed
        self.language = language
        self.instructions = instructions
        self.providerOptions = providerOptions
        self.extraBody = extraBody
        self.headers = headers
        self.abortSignal = abortSignal
    }
}

public struct SpeechResult: Sendable {
    public var audio: Data
    public var contentType: String?
    public var warnings: [AIWarning]
    public var providerMetadata: [String: JSONValue]
    public var requestMetadata: AIRequestMetadata
    public var responseMetadata: AIResponseMetadata

    public init(
        audio: Data,
        contentType: String? = nil,
        warnings: [AIWarning] = [],
        providerMetadata: [String: JSONValue] = [:],
        requestMetadata: AIRequestMetadata = AIRequestMetadata(),
        responseMetadata: AIResponseMetadata = AIResponseMetadata()
    ) {
        self.audio = audio
        self.contentType = contentType
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.requestMetadata = requestMetadata
        self.responseMetadata = responseMetadata
    }
}
