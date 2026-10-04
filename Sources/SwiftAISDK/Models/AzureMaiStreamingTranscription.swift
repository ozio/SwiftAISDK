import Foundation

extension AzureTranscriptionModel {
    public func stream(_ request: StreamingTranscriptionRequest) async throws -> StreamingTranscriptionResult {
        let options = try azureAudioOptions(request.providerOptions, transcription: true)
        guard api(for: options) == "mai" else {
            throw AIError.invalidArgument(argument: "model", message: "Azure streaming transcription requires the MAI realtime API (providerOptions.azure.api = mai).")
        }
        let rate = request.inputAudioFormat.sampleRate ?? 24_000
        guard request.inputAudioFormat.mediaType == "audio/pcm", [16_000, 24_000].contains(rate) else {
            throw AIError.invalidArgument(argument: "inputAudioFormat", message: "MAI streaming transcription requires 16-bit mono PCM (audio/pcm) at 16000 or 24000 Hz.")
        }
        try request.abortSignal?.throwIfAborted()
        var transcription: [String: JSONValue] = ["model": .string(modelID)]
        if let language = options["language"] { transcription["language"] = language }
        let update: JSONValue = .object([
            "type": "session.update", "session": .object([
                "type": "transcription", "audio": .object(["input": .object([
                    "format": .object(["type": "audio/pcm", "rate": .number(Double(rate))]),
                    "transcription": .object(transcription), "turn_detection": .null, "noise_reduction": .null
                ])])
            ])
        ])
        var components = URLComponents(string: try config.baseURL(api: "mai") + "/realtime?intent=transcription")
        let scheme = components?.scheme == "http" ? "ws" : "wss"
        components?.scheme = scheme
        guard let url = components?.url else { throw AIError.invalidURL("Invalid Azure MAI realtime URL.") }
        var headers = config.requestHeaders(api: "mai")
        if let tokenProvider = config.tokenProvider { headers = headers.mergingHeaders(["Authorization": "Bearer \(try await tokenProvider())"]) }
        headers = headers.mergingHeaders(request.headers)
        let connection: any AIDuplexWebSocketConnection
        do {
            connection = try await config.settings.webSocketTransport.connect(AIDuplexWebSocketRequest(url: url, headers: headers, abortSignal: request.abortSignal))
        } catch {
            request.audio.cancelFromConsumer()
            throw error
        }
        let warnings = azureAudioUnusedOptions(options.filter { !["api", "language"].contains($0.key) }, api: "Speech")
        let session = AzureMaiTranscriptionSession(connection: connection, request: request, update: update, rate: rate,
                                                   language: options["language"]?.stringValue, warnings: warnings)
        let stream = await session.start()
        return StreamingTranscriptionResult(stream: stream, requestMetadata: AIRequestMetadata(body: update, headers: request.headers),
                                            responseMetadata: AIResponseMetadata(timestamp: Date(), modelID: modelID),
                                            cancel: { Task { await session.cancel() } })
    }
}

private actor AzureMaiTranscriptionSession {
    let connection: any AIDuplexWebSocketConnection
    let request: StreamingTranscriptionRequest
    let update: JSONValue
    let rate: Int
    let language: String?
    let warnings: [AIWarning]
    var continuation: AsyncThrowingStream<StreamingTranscriptionPart, Error>.Continuation?
    var eventTask: Task<Void, Never>?
    var audioTask: Task<Void, Never>?
    var abortRegistration: AIAbortHandlerRegistration?
    var completed = false
    var audioStarted = false
    var committed = false
    var audioBytes = 0
    var deltas = ""

    init(connection: any AIDuplexWebSocketConnection, request: StreamingTranscriptionRequest,
         update: JSONValue, rate: Int, language: String?, warnings: [AIWarning]) {
        self.connection = connection; self.request = request; self.update = update
        self.rate = rate; self.language = language; self.warnings = warnings
    }

    func start() -> AsyncThrowingStream<StreamingTranscriptionPart, Error> {
        let pair = AsyncThrowingStream<StreamingTranscriptionPart, Error>.makeStream()
        continuation = pair.continuation
        continuation?.onTermination = { termination in
            if case .cancelled = termination { Task { await self.cancel() } }
        }
        abortRegistration = request.abortSignal?.addAbortHandler { [weak signal = request.abortSignal] reason in
            let error = AIAbortError(reason: reason, reasonName: signal?.reasonName)
            Task { await self.fail(error) }
        }
        eventTask = Task { await consumeEvents() }
        return pair.stream
    }

    func cancel() async { await complete(error: nil, finish: nil) }
    func fail(_ error: Error) async { await complete(error: error, finish: nil) }

    private func consumeEvents() async {
        do {
            for try await event in connection.events {
                guard !completed else { return }
                switch event {
                case .opened:
                    continuation?.yield(.streamStart(warnings: warnings))
                case let .message(message):
                    let data: Data
                    switch message { case let .text(text): data = Data(text.utf8); case let .binary(bytes): data = bytes }
                    guard let raw = try? decodeJSONBody(data) else { continue }
                    if request.includeRawChunks { continuation?.yield(.raw(raw)) }
                    try await process(raw)
                case let .closed(close):
                    await fail(AIStreamingTranscriptionError(provider: "azure.transcription", message: "Azure MAI transcription connection closed before the transcript completed (code \(close.code)\(close.reason.map { ": " + $0 } ?? "")).", closeMetadata: close))
                }
            }
            if !completed { await fail(AIStreamingTranscriptionError(provider: "azure.transcription", message: "Azure MAI transcription connection closed before the transcript completed.")) }
        } catch { await fail(error) }
    }

    private func process(_ event: JSONValue) async throws {
        let id = event["item_id"]?.stringValue
        switch event["type"]?.stringValue {
        case "session.created":
            try await send(update)
        case "session.updated":
            guard !audioStarted else { return }
            audioStarted = true
            audioTask = Task { await sendAudio() }
        case "conversation.item.input_audio_transcription.delta":
            let delta = event["delta"]?.stringValue ?? ""
            deltas += delta
            continuation?.yield(.transcriptDelta(id: id, delta: delta))
        case "conversation.item.input_audio_transcription.intermediate":
            continuation?.yield(.transcriptPartial(id: id, text: event["intermediate"]?.stringValue ?? ""))
        case "conversation.item.input_audio_transcription.completed":
            let text = event["transcript"]?.stringValue ?? deltas
            continuation?.yield(.transcriptFinal(id: id, text: text))
            if committed { await complete(error: nil, finish: StreamingTranscriptionFinish(text: text, language: language, durationInSeconds: audioBytes > 0 ? Double(audioBytes) / Double(rate * 2) : nil)) }
        case "conversation.item.input_audio_transcription.failed", "error":
            await fail(AIStreamingTranscriptionError(provider: "azure.transcription", code: event["error"]?["code"]?.stringValue,
                                                     message: "Azure MAI transcription error: \(event["error"]?["message"]?.stringValue ?? "unknown error")", rawValue: event))
        default: break
        }
    }

    private func sendAudio() async {
        do {
            for try await chunk in request.audio {
                guard !completed else { return }
                try Task.checkCancellation()
                guard !chunk.isEmpty else { continue }
                audioBytes += chunk.count
                try await send(.object(["type": "input_audio_buffer.append", "audio": .string(chunk.base64EncodedString())]))
            }
            guard !completed else { return }
            if audioBytes == 0 {
                await complete(error: nil, finish: StreamingTranscriptionFinish(text: "", language: language))
            } else {
                committed = true
                try await send(["type": "input_audio_buffer.commit"])
            }
        } catch { await fail(error) }
    }

    private func send(_ json: JSONValue) async throws {
        guard !completed else { return }
        try await connection.send(text: String(decoding: try encodeJSONBody(json), as: UTF8.self))
    }

    private func complete(error: Error?, finish: StreamingTranscriptionFinish?) async {
        guard !completed else { return }
        completed = true
        eventTask?.cancel(); audioTask?.cancel(); abortRegistration?.cancel()
        eventTask = nil; audioTask = nil; abortRegistration = nil
        request.audio.cancelFromConsumer()
        if let finish { continuation?.yield(.finish(finish)) }
        if let error { continuation?.finish(throwing: error) } else { continuation?.finish() }
        continuation = nil
        await connection.close(code: finish == nil ? 1001 : 1000)
    }
}
