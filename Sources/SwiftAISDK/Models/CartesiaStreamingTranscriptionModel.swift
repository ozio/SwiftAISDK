import Foundation

public final class CartesiaStreamingTranscriptionModel:
    StreamingTranscriptionModel,
    @unchecked Sendable {
    public let providerID = "cartesia.transcription"
    public let modelID: String

    private let config: ModelHTTPConfig
    private let version: String
    private let webSocketTransport: any AIDuplexWebSocketTransport
    private let currentDate: @Sendable () -> Date

    init(
        modelID: String,
        config: ModelHTTPConfig,
        version: String,
        webSocketTransport: any AIDuplexWebSocketTransport,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.modelID = modelID
        self.config = config
        self.version = version
        self.webSocketTransport = webSocketTransport
        self.currentDate = currentDate
    }

    public func stream(
        _ request: StreamingTranscriptionRequest
    ) async throws -> StreamingTranscriptionResult {
        guard isCartesiaInk2Model(modelID) else {
            throw AIError.invalidArgument(
                argument: "modelID",
                message: "Cartesia \(modelID) does not support streaming transcription."
            )
        }

        let options = try parseCartesiaStreamingOptions(
            request.providerOptions
        )
        if let language = options.language, language != "en" {
            throw AIError.invalidArgument(
                argument: "providerOptions",
                message: "Cartesia Ink 2 currently supports English only."
            )
        }

        var warnings: [AIWarning] = []
        if options.hasTimestampGranularities {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "providerOptions.cartesia.timestampGranularities",
                message: "Cartesia streaming transcription does not support timestamp granularities."
            ))
        }

        let inferredEncoding = try cartesiaEncoding(
            for: request.inputAudioFormat.mediaType
        )
        let encoding = options.encoding ?? inferredEncoding
        if encoding != inferredEncoding,
           !(inferredEncoding == "pcm_s16le"
             && cartesiaLinearPCMEncodings.contains(encoding)) {
            warnings.append(AIWarning(
                type: "other",
                message: "providerOptions.cartesia.streaming.encoding '\(encoding)' contradicts inputAudioFormat.type '\(request.inputAudioFormat.mediaType)' (inferred '\(inferredEncoding)'); sending '\(encoding)'."
            ))
        }

        let token = try await createAccessToken(request: request)
        let useTurnDetection = options.turnDetection != false
        let urls = try cartesiaStreamingURLs(
            config: config,
            modelID: modelID,
            version: version,
            encoding: encoding,
            format: request.inputAudioFormat,
            language: options.language,
            token: token,
            useTurnDetection: useTurnDetection
        )

        let connection: any AIDuplexWebSocketConnection
        do {
            connection = try await webSocketTransport.connect(
                AIDuplexWebSocketRequest(
                    url: urls.authenticated,
                    abortSignal: request.abortSignal
                )
            )
        } catch {
            request.audio.cancelFromConsumer()
            throw error
        }

        let session = CartesiaStreamingTranscriptionSession(
            connection: connection,
            audio: request.audio,
            abortSignal: request.abortSignal,
            warnings: warnings,
            language: options.language ?? "en",
            useTurnDetection: useTurnDetection,
            includeRawChunks: request.includeRawChunks
        )

        return StreamingTranscriptionResult(
            stream: session.makeStream(),
            requestMetadata: AIRequestMetadata(
                body: .string(urls.redacted.absoluteString),
                headers: request.headers
            ),
            responseMetadata: AIResponseMetadata(
                timestamp: currentDate(),
                modelID: modelID
            ),
            cancel: { session.cancel() }
        )
    }

    private func createAccessToken(
        request: StreamingTranscriptionRequest
    ) async throws -> String {
        let httpRequest = try config.request(
            path: "/access-token",
            modelID: modelID,
            body: .object([
                "grants": .object(["stt": .bool(true)])
            ]),
            headers: request.headers,
            abortSignal: request.abortSignal
        )
        let response = try await config.transport.send(httpRequest)
        guard (200..<300).contains(response.statusCode) else {
            throw cartesiaHTTPStatusError(
                provider: providerID,
                response: response
            )
        }

        let raw = try response.jsonValue()
        guard let token = raw["token"]?.stringValue, !token.isEmpty else {
            throw AIError.invalidResponse(
                provider: providerID,
                message: "Cartesia access-token response did not contain a non-empty token."
            )
        }
        return token
    }
}

private struct ParsedCartesiaStreamingOptions {
    var language: String?
    var hasTimestampGranularities = false
    var encoding: String?
    var turnDetection: Bool?
}

private let cartesiaStreamingEncodings: Set<String> = [
    "pcm_alaw",
    "pcm_f16le",
    "pcm_f32le",
    "pcm_mulaw",
    "pcm_s16le",
    "pcm_s32le"
]

private let cartesiaLinearPCMEncodings: Set<String> = [
    "pcm_f16le",
    "pcm_f32le",
    "pcm_s16le",
    "pcm_s32le"
]

private func parseCartesiaStreamingOptions(
    _ providerOptions: [String: JSONValue]
) throws -> ParsedCartesiaStreamingOptions {
    guard let namespace = providerOptions["cartesia"], namespace != .null else {
        return ParsedCartesiaStreamingOptions()
    }
    guard let values = namespace.objectValue else {
        throw AIError.invalidArgument(
            argument: "providerOptions.cartesia",
            message: "Cartesia provider options must be an object."
        )
    }

    var options = ParsedCartesiaStreamingOptions()
    if let language = values["language"], language != .null {
        guard let language = language.stringValue else {
            throw AIError.invalidArgument(
                argument: "providerOptions.cartesia.language",
                message: "Cartesia language must be a string."
            )
        }
        options.language = language
    }

    if let granularities = values["timestampGranularities"],
       granularities != .null {
        guard let items = granularities.arrayValue,
              items.allSatisfy({ $0.stringValue == "word" }) else {
            throw AIError.invalidArgument(
                argument: "providerOptions.cartesia.timestampGranularities",
                message: "Cartesia timestampGranularities only supports word."
            )
        }
        options.hasTimestampGranularities = true
    }

    if let streaming = values["streaming"] {
        guard let streaming = streaming.objectValue else {
            throw AIError.invalidArgument(
                argument: "providerOptions.cartesia.streaming",
                message: "Cartesia streaming options must be an object."
            )
        }

        if let encoding = streaming["encoding"] {
            guard let encoding = encoding.stringValue,
                  cartesiaStreamingEncodings.contains(encoding) else {
                throw AIError.invalidArgument(
                    argument: "providerOptions.cartesia.streaming.encoding",
                    message: "Cartesia encoding must be one of pcm_alaw, pcm_f16le, pcm_f32le, pcm_mulaw, pcm_s16le, pcm_s32le."
                )
            }
            options.encoding = encoding
        }

        if let turnDetection = streaming["turnDetection"] {
            guard let turnDetection = turnDetection.boolValue else {
                throw AIError.invalidArgument(
                    argument: "providerOptions.cartesia.streaming.turnDetection",
                    message: "Cartesia turnDetection must be a boolean."
                )
            }
            options.turnDetection = turnDetection
        }
    }

    return options
}

private func cartesiaEncoding(for mediaType: String) throws -> String {
    switch mediaType {
    case "audio/pcm":
        return "pcm_s16le"
    case "audio/pcmu":
        return "pcm_mulaw"
    case "audio/pcma":
        return "pcm_alaw"
    default:
        throw AIError.invalidArgument(
            argument: "inputAudioFormat",
            message: "Unsupported Cartesia streaming audio format: \(mediaType)"
        )
    }
}

private func isCartesiaInk2Model(_ modelID: String) -> Bool {
    modelID == "ink-2" || modelID.hasPrefix("ink-2-")
}

private func cartesiaStreamingURLs(
    config: ModelHTTPConfig,
    modelID: String,
    version: String,
    encoding: String,
    format: AIStreamingAudioFormat,
    language: String?,
    token: String,
    useTurnDetection: Bool
) throws -> (authenticated: URL, redacted: URL) {
    let path = useTurnDetection
        ? "/stt/turns/websocket"
        : "/stt/websocket"
    let baseURL = try config.url(modelID, path)
    guard var components = URLComponents(
        url: baseURL,
        resolvingAgainstBaseURL: false
    ) else {
        throw AIError.invalidURL(baseURL.absoluteString)
    }
    switch components.scheme?.lowercased() {
    case "https":
        components.scheme = "wss"
    case "http":
        components.scheme = "ws"
    case "ws", "wss":
        break
    default:
        throw AIError.invalidURL(baseURL.absoluteString)
    }

    var queryItems = components.queryItems ?? []
    queryItems.append(contentsOf: [
        URLQueryItem(name: "model", value: modelID),
        URLQueryItem(name: "encoding", value: encoding),
        URLQueryItem(
            name: "sample_rate",
            value: String(format.sampleRate ?? 24_000)
        ),
        URLQueryItem(name: "cartesia_version", value: version),
        URLQueryItem(name: "access_token", value: token)
    ])
    if !useTurnDetection, let language {
        queryItems.append(URLQueryItem(name: "language", value: language))
    }
    components.queryItems = queryItems
    guard let authenticated = components.url else {
        throw AIError.invalidURL(baseURL.absoluteString)
    }

    components.queryItems = queryItems.filter {
        $0.name != "access_token"
    }
    guard let redacted = components.url else {
        throw AIError.invalidURL(baseURL.absoluteString)
    }
    return (authenticated, redacted)
}

private final class CartesiaStreamingTranscriptionSession:
    @unchecked Sendable {
    private typealias Continuation =
        AsyncThrowingStream<StreamingTranscriptionPart, Error>.Continuation

    private let connection: any AIDuplexWebSocketConnection
    private let audio: AIStreamingAudioInput
    private let abortSignal: AIAbortSignal?
    private let warnings: [AIWarning]
    private let language: String
    private let useTurnDetection: Bool
    private let includeRawChunks: Bool

    private let lock = NSLock()
    private var continuation: Continuation?
    private var eventTask: Task<Void, Never>?
    private var audioTask: Task<Void, Never>?
    private var abortRegistration: AIAbortHandlerRegistration?
    private var started = false
    private var completed = false

    init(
        connection: any AIDuplexWebSocketConnection,
        audio: AIStreamingAudioInput,
        abortSignal: AIAbortSignal?,
        warnings: [AIWarning],
        language: String,
        useTurnDetection: Bool,
        includeRawChunks: Bool
    ) {
        self.connection = connection
        self.audio = audio
        self.abortSignal = abortSignal
        self.warnings = warnings
        self.language = language
        self.useTurnDetection = useTurnDetection
        self.includeRawChunks = includeRawChunks
    }

    func makeStream()
        -> AsyncThrowingStream<StreamingTranscriptionPart, Error> {
        AsyncThrowingStream { continuation in
            start(continuation: continuation)
            continuation.onTermination = { [weak self] termination in
                if case .cancelled = termination {
                    self?.cancel()
                }
            }
        }
    }

    func cancel() {
        complete(throwing: nil, finish: nil)
    }

    private func start(continuation: Continuation) {
        lock.lock()
        guard !started else {
            lock.unlock()
            continuation.finish(throwing: AIError.invalidArgument(
                argument: "stream",
                message: "A streaming transcription result can only be consumed once."
            ))
            return
        }
        started = true
        self.continuation = continuation
        lock.unlock()

        let registration = abortSignal?.addAbortHandler {
            [weak self, weak signal = abortSignal] reason in
            self?.complete(
                throwing: AIAbortError(
                    reason: reason,
                    reasonName: signal?.reasonName
                ),
                finish: nil
            )
        }
        setAbortRegistration(registration)

        let eventTask = Task { [weak self] in
            guard let self else { return }
            await self.consumeEvents()
        }
        setEventTask(eventTask)
    }

    private func consumeEvents() async {
        var finalTexts: [String] = []
        var durationInSeconds = 0.0
        var audioStarted = false

        do {
            for try await event in connection.events {
                if isCompleted { return }
                switch event {
                case .opened:
                    yield(.streamStart(warnings: warnings))
                    if !audioStarted {
                        audioStarted = true
                        startSendingAudio()
                    }

                case let .message(.text(text)):
                    guard let raw = parseJSONText(text) else { continue }
                    if includeRawChunks {
                        yield(.raw(raw))
                    }
                    let shouldContinue = await handle(
                        raw: raw,
                        finalTexts: &finalTexts,
                        durationInSeconds: &durationInSeconds
                    )
                    if !shouldContinue { return }

                case .message(.binary):
                    continue

                case let .closed(metadata):
                    finish(
                        finalTexts: finalTexts,
                        durationInSeconds: durationInSeconds,
                        closeMetadata: metadata
                    )
                    return
                }
            }

            if !isCompleted {
                finish(
                    finalTexts: finalTexts,
                    durationInSeconds: durationInSeconds,
                    closeMetadata: nil
                )
            }
        } catch {
            if let abortSignal, abortSignal.isAborted {
                complete(
                    throwing: AIAbortError(
                        reason: abortSignal.reason,
                        reasonName: abortSignal.reasonName
                    ),
                    finish: nil
                )
            } else if !(error is CancellationError) {
                complete(
                    throwing: AIStreamingTranscriptionError(
                        provider: "cartesia.transcription",
                        message: "Cartesia streaming transcription error"
                    ),
                    finish: nil
                )
            }
        }
    }

    private func handle(
        raw: JSONValue,
        finalTexts: inout [String],
        durationInSeconds: inout Double
    ) async -> Bool {
        let type = raw["type"]?.stringValue
        let id = raw["request_id"]?.stringValue
        switch type {
        case "turn.update", "turn.eager_end":
            yield(.transcriptPartial(
                id: id,
                text: raw["transcript"]?.stringValue ?? ""
            ))

        case "turn.end":
            let text = raw["transcript"]?.stringValue ?? ""
            finalTexts.append(text)
            yield(.transcriptFinal(id: id, text: text))

        case "transcript":
            let text = raw["text"]?.stringValue ?? ""
            let duration = raw["duration"]?.doubleValue
            if raw["is_final"]?.boolValue == true {
                finalTexts.append(text)
                durationInSeconds += duration ?? 0
                yield(.transcriptFinal(id: id, text: text))
            } else {
                yield(.transcriptPartial(
                    id: id,
                    text: text,
                    durationInSeconds: duration
                ))
            }

        case "flush_done":
            do {
                try await connection.send(text: "close")
            } catch {
                complete(
                    throwing: AIStreamingTranscriptionError(
                        provider: "cartesia.transcription",
                        message: "Cartesia streaming transcription error"
                    ),
                    finish: nil
                )
                return false
            }

        case "done":
            finish(
                finalTexts: finalTexts,
                durationInSeconds: durationInSeconds,
                closeMetadata: .normalClosure
            )
            return false

        case "error":
            let code = raw["error_code"]?.stringValue
            let message = raw["message"]?.stringValue
                ?? code
                ?? "Cartesia streaming transcription error"
            complete(
                throwing: AIStreamingTranscriptionError(
                    provider: "cartesia.transcription",
                    code: code,
                    message: message,
                    rawValue: raw
                ),
                finish: nil
            )
            return false

        default:
            break
        }
        return true
    }

    private func startSendingAudio() {
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await chunk in audio {
                    if isCompleted { return }
                    try await connection.send(binary: chunk)
                }
                if !isCompleted {
                    try await connection.send(text: useTurnDetection
                        ? #"{"type":"close"}"#
                        : "finalize")
                }
            } catch {
                if error is CancellationError, isCompleted {
                    return
                }
                complete(
                    throwing: error,
                    finish: nil
                )
            }
        }
        setAudioTask(task)
    }

    private func finish(
        finalTexts: [String],
        durationInSeconds: Double,
        closeMetadata: AIDuplexWebSocketCloseMetadata?
    ) {
        complete(
            throwing: nil,
            finish: StreamingTranscriptionFinish(
                text: finalTexts.joined(separator: useTurnDetection ? " " : ""),
                language: language,
                durationInSeconds: durationInSeconds > 0
                    ? durationInSeconds
                    : nil,
                closeMetadata: closeMetadata
            )
        )
    }

    private func complete(
        throwing error: Error?,
        finish: StreamingTranscriptionFinish?
    ) {
        let resources = takeResources()
        guard resources.didComplete else { return }

        if let finish {
            resources.continuation?.yield(.finish(finish))
        }
        if let error {
            resources.continuation?.finish(throwing: error)
        } else {
            resources.continuation?.finish()
        }

        resources.registration?.cancel()
        resources.eventTask?.cancel()
        resources.audioTask?.cancel()
        audio.cancelFromConsumer()
        Task { [connection] in
            await connection.close(
                code: AIDuplexWebSocketCloseMetadata.normalClosure.code,
                reason: nil
            )
        }
    }

    private var isCompleted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    private func yield(_ part: StreamingTranscriptionPart) {
        lock.lock()
        guard !completed, let continuation else {
            lock.unlock()
            return
        }
        continuation.yield(part)
        lock.unlock()
    }

    private func setAbortRegistration(
        _ registration: AIAbortHandlerRegistration?
    ) {
        guard let registration else { return }
        lock.lock()
        if completed {
            lock.unlock()
            registration.cancel()
            return
        }
        abortRegistration = registration
        lock.unlock()
    }

    private func setEventTask(_ task: Task<Void, Never>) {
        lock.lock()
        if completed {
            lock.unlock()
            task.cancel()
            return
        }
        eventTask = task
        lock.unlock()
    }

    private func setAudioTask(_ task: Task<Void, Never>) {
        lock.lock()
        if completed {
            lock.unlock()
            task.cancel()
            return
        }
        audioTask = task
        lock.unlock()
    }

    private func takeResources() -> (
        didComplete: Bool,
        continuation: Continuation?,
        registration: AIAbortHandlerRegistration?,
        eventTask: Task<Void, Never>?,
        audioTask: Task<Void, Never>?
    ) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return (false, nil, nil, nil, nil)
        }
        completed = true
        let resources = (
            true,
            continuation,
            abortRegistration,
            eventTask,
            audioTask
        )
        continuation = nil
        abortRegistration = nil
        eventTask = nil
        audioTask = nil
        lock.unlock()
        return resources
    }
}

private func parseJSONText(_ text: String) -> JSONValue? {
    try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}
