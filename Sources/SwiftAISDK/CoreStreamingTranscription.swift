import Foundation

/// The raw audio format supplied to a streaming transcription model.
public struct AIStreamingAudioFormat: Equatable, Hashable, Sendable {
    public var mediaType: String
    public var sampleRate: Int?

    public init(mediaType: String, sampleRate: Int? = nil) {
        self.mediaType = mediaType
        self.sampleRate = sampleRate
    }
}

/// The result of attempting to enqueue an audio chunk.
public enum AIStreamingAudioSendResult: Equatable, Sendable {
    case enqueued
    case dropped
    case terminated
}

/// The producer side of an ``AIStreamingAudioInput`` pipe.
///
/// Send raw audio chunks with ``send(_:)`` and call ``finish()`` when no more
/// audio will be produced. Calling ``cancel(reason:reasonName:)`` terminates the
/// consumer with an ``AIAbortError``.
public final class AIStreamingAudioWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?

    fileprivate init(
        continuation: AsyncThrowingStream<Data, Error>.Continuation
    ) {
        self.continuation = continuation
    }

    @discardableResult
    public func send(_ audio: Data) -> AIStreamingAudioSendResult {
        lock.lock()
        let continuation = self.continuation
        lock.unlock()

        guard let continuation else {
            return .terminated
        }

        switch continuation.yield(audio) {
        case .enqueued:
            return .enqueued
        case .dropped:
            return .dropped
        case .terminated:
            terminate()
            return .terminated
        @unknown default:
            terminate()
            return .terminated
        }
    }

    public func finish() {
        takeContinuation()?.finish()
    }

    public func cancel(
        reason: String? = nil,
        reasonName: String? = nil
    ) {
        takeContinuation()?.finish(throwing: AIAbortError(
            reason: reason,
            reasonName: reasonName
        ))
    }

    fileprivate func cancelFromConsumer() {
        cancel(
            reason: "Streaming audio input was cancelled.",
            reasonName: "AbortError"
        )
    }

    private func terminate() {
        _ = takeContinuation()
    }

    private func takeContinuation()
        -> AsyncThrowingStream<Data, Error>.Continuation? {
        lock.lock()
        defer { lock.unlock() }
        let continuation = self.continuation
        self.continuation = nil
        return continuation
    }
}

/// An asynchronous stream of raw audio chunks.
public struct AIStreamingAudioInput: AsyncSequence, Sendable {
    public typealias Element = Data
    public typealias AsyncIterator = AsyncThrowingStream<Data, Error>.Iterator

    private let stream: AsyncThrowingStream<Data, Error>
    private let onConsumerCancel: @Sendable () -> Void

    public init(
        _ stream: AsyncThrowingStream<Data, Error>,
        onConsumerCancel: @escaping @Sendable () -> Void = {}
    ) {
        self.stream = stream
        self.onConsumerCancel = onConsumerCancel
    }

    public func makeAsyncIterator() -> AsyncIterator {
        stream.makeAsyncIterator()
    }

    /// Creates an unbounded audio pipe suitable for microphones and other
    /// incremental audio producers.
    public static func makeStream()
        -> (input: AIStreamingAudioInput, writer: AIStreamingAudioWriter) {
        let pair = AsyncThrowingStream<Data, Error>.makeStream()
        let writer = AIStreamingAudioWriter(continuation: pair.continuation)
        let input = AIStreamingAudioInput(pair.stream) {
            writer.cancelFromConsumer()
        }
        return (input, writer)
    }

    /// Creates a finite audio input from already available chunks.
    public static func chunks(_ chunks: [Data]) -> AIStreamingAudioInput {
        let pair = makeStream()
        for chunk in chunks {
            _ = pair.writer.send(chunk)
        }
        pair.writer.finish()
        return pair.input
    }

    func cancelFromConsumer() {
        onConsumerCancel()
    }
}

public struct StreamingTranscriptionRequest: Sendable {
    public var audio: AIStreamingAudioInput
    public var inputAudioFormat: AIStreamingAudioFormat
    public var providerOptions: [String: JSONValue]
    public var headers: [String: String]
    public var includeRawChunks: Bool
    public var abortSignal: AIAbortSignal?

    public init(
        audio: AIStreamingAudioInput,
        inputAudioFormat: AIStreamingAudioFormat,
        providerOptions: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        includeRawChunks: Bool = false,
        abortSignal: AIAbortSignal? = nil
    ) {
        self.audio = audio
        self.inputAudioFormat = inputAudioFormat
        self.providerOptions = providerOptions
        self.headers = headers
        self.includeRawChunks = includeRawChunks
        self.abortSignal = abortSignal
    }
}

public struct StreamingTranscriptionFinish: Equatable, Sendable {
    public var text: String
    public var segments: [TranscriptionSegment]
    public var language: String?
    public var durationInSeconds: Double?
    public var providerMetadata: [String: JSONValue]
    public var closeMetadata: AIDuplexWebSocketCloseMetadata?

    public init(
        text: String,
        segments: [TranscriptionSegment] = [],
        language: String? = nil,
        durationInSeconds: Double? = nil,
        providerMetadata: [String: JSONValue] = [:],
        closeMetadata: AIDuplexWebSocketCloseMetadata? = nil
    ) {
        self.text = text
        self.segments = segments
        self.language = language
        self.durationInSeconds = durationInSeconds
        self.providerMetadata = providerMetadata
        self.closeMetadata = closeMetadata
    }
}

/// Provider-independent streaming transcription lifecycle events.
public enum StreamingTranscriptionPart: Equatable, Sendable {
    case streamStart(warnings: [AIWarning])
    case transcriptDelta(
        id: String?,
        delta: String,
        providerMetadata: [String: JSONValue] = [:]
    )
    case transcriptPartial(
        id: String?,
        text: String,
        startSecond: Double? = nil,
        durationInSeconds: Double? = nil,
        channelIndex: Int? = nil,
        providerMetadata: [String: JSONValue] = [:]
    )
    case transcriptFinal(
        id: String?,
        text: String,
        startSecond: Double? = nil,
        endSecond: Double? = nil,
        channelIndex: Int? = nil,
        providerMetadata: [String: JSONValue] = [:]
    )
    case responseMetadata(AIResponseMetadata)
    case finish(StreamingTranscriptionFinish)
    case raw(JSONValue)
    case error(message: String, rawValue: JSONValue? = nil)
}

/// A provider error emitted while a streaming transcription session is open.
public struct AIStreamingTranscriptionError:
    Error,
    Equatable,
    Sendable,
    CustomStringConvertible {
    public var provider: String
    public var code: String?
    public var message: String
    public var rawValue: JSONValue?
    public var closeMetadata: AIDuplexWebSocketCloseMetadata?

    public init(
        provider: String,
        code: String? = nil,
        message: String,
        rawValue: JSONValue? = nil,
        closeMetadata: AIDuplexWebSocketCloseMetadata? = nil
    ) {
        self.provider = provider
        self.code = code
        self.message = message
        self.rawValue = rawValue
        self.closeMetadata = closeMetadata
    }

    public var description: String {
        if let code, !code.isEmpty {
            return "\(provider) streaming transcription failed (\(code)): \(message)"
        }
        return "\(provider) streaming transcription failed: \(message)"
    }
}

public struct StreamingTranscriptionResult: Sendable {
    public var stream: AsyncThrowingStream<StreamingTranscriptionPart, Error>
    public var requestMetadata: AIRequestMetadata
    public var responseMetadata: AIResponseMetadata

    private let cancelOperation: @Sendable () -> Void

    public init(
        stream: AsyncThrowingStream<StreamingTranscriptionPart, Error>,
        requestMetadata: AIRequestMetadata = AIRequestMetadata(),
        responseMetadata: AIResponseMetadata = AIResponseMetadata(),
        cancel: @escaping @Sendable () -> Void = {}
    ) {
        self.stream = stream
        self.requestMetadata = requestMetadata
        self.responseMetadata = responseMetadata
        self.cancelOperation = cancel
    }

    /// Stops the session, cancels input consumption, and closes its duplex
    /// transport. The output stream then terminates without a finish event.
    public func cancel() {
        cancelOperation()
    }
}

public protocol StreamingTranscriptionModel: Sendable {
    var providerID: String { get }
    var modelID: String { get }

    func stream(
        _ request: StreamingTranscriptionRequest
    ) async throws -> StreamingTranscriptionResult
}
