import Foundation

public final class GoogleVertexLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: GoogleVertexConfig

    init(modelID: String, config: GoogleVertexConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = try googleGenerateContentBody(request, modelID: modelID, providerID: providerID)
        let response = try await config.sendJSONResponse(path: "/models/\(modelID):generateContent", body: prepared.body, headers: request.headers.mergingHeaders(prepared.headers), abortSignal: request.abortSignal)
        let raw = response.json
        let text = googleGenerateContentText(from: raw)
        let toolCalls = googleGenerateContentToolCalls(from: raw)
        let toolResults = googleGenerateContentToolResults(from: raw)
        guard text != nil || !toolCalls.isEmpty || !toolResults.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No candidate text found in Vertex response.")
        }
        return TextGenerationResult(
            text: text ?? "",
            finishReason: googleGenerateContentFinishReason(raw["candidates"]?[0]?["finishReason"]?.stringValue, hasToolCalls: !toolCalls.isEmpty),
            usage: googleGenerateContentUsage(from: raw),
            toolCalls: toolCalls,
            toolResults: toolResults,
            sources: googleGenerateContentSources(from: raw),
            providerMetadata: googleGenerateContentProviderMetadata(from: raw),
            rawValue: raw,
            warnings: prepared.warnings,
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = try googleGenerateContentBody(request, modelID: modelID, providerID: providerID, isStreaming: true)
                    let httpRequest = try await config.request(
                        path: "/models/\(modelID):streamGenerateContent?alt=sse",
                        body: prepared.body,
                        headers: request.headers.mergingHeaders(prepared.headers),
                        abortSignal: request.abortSignal
                    )
                    let response = try await config.transport.send(httpRequest)
                    let parts = try streamFromGoogleGenerateContent(
                        providerID: providerID,
                        response: response,
                        includeRawChunks: request.includeRawChunks,
                        modelID: modelID,
                        warnings: prepared.warnings
                    )
                    for part in parts {
                        continuation.yield(part)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

public final class GoogleVertexEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: GoogleVertexConfig

    init(modelID: String, config: GoogleVertexConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        let maxEmbeddingsPerCall = googleVertexUsesEmbedContentEndpoint(modelID) ? 1 : 2048
        guard request.values.count <= maxEmbeddingsPerCall else {
            throw AITooManyEmbeddingValuesForCallError(
                provider: providerID,
                modelID: modelID,
                maxEmbeddingsPerCall: maxEmbeddingsPerCall,
                values: request.values
            )
        }
        let options = googleVertexEmbeddingProviderOptions(from: request)
        var parameters: [String: JSONValue] = [:]
        if let dimensions = request.dimensions {
            parameters["outputDimensionality"] = .number(Double(dimensions))
        }
        if let outputDimensionality = options["outputDimensionality"] {
            parameters["outputDimensionality"] = outputDimensionality
        }
        if let autoTruncate = options["autoTruncate"] {
            parameters["autoTruncate"] = autoTruncate
        }
        let taskType = options["taskType"]
        let title = options["title"]
        if googleVertexUsesEmbedContentEndpoint(modelID) {
            var embedContentConfig = parameters
            if let taskType { embedContentConfig["taskType"] = taskType }
            if let title { embedContentConfig["title"] = title }
            let body: [String: JSONValue] = [
                "content": .object([
                    "parts": .array([.object(["text": .string(request.values.first ?? "")])])
                ]),
                "embedContentConfig": .object(embedContentConfig)
            ]
            let response = try await config.sendJSONResponse(path: "/models/\(modelID):embedContent", body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
            let raw = response.json
            guard let embedding = raw["embedding"]?["values"]?.arrayValue?.compactMap(\.doubleValue), !embedding.isEmpty else {
                throw AIError.invalidResponse(provider: providerID, message: "No embedding returned from Vertex embedContent response.")
            }
            return EmbeddingResult(
                embeddings: [embedding],
                usage: raw["usageMetadata"]?["promptTokenCount"]?.intValue.map { TokenUsage(inputTokens: $0, totalTokens: $0, rawValue: raw["usageMetadata"]) },
                rawValue: raw,
                requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
                responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
            )
        }
        var body: [String: JSONValue] = [
            "instances": .array(request.values.map { value in
                var instance: [String: JSONValue] = ["content": .string(value)]
                if let taskType { instance["task_type"] = taskType }
                if let title { instance["title"] = title }
                return .object(instance)
            })
        ]
        if !parameters.isEmpty { body["parameters"] = .object(parameters) }
        body.merge(request.extraBody) { _, new in new }
        let response = try await config.sendJSONResponse(path: "/models/\(modelID):predict", body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let embeddings = raw["predictions"]?.arrayValue?.compactMap { prediction in
            prediction["embeddings"]?["values"]?.arrayValue?.compactMap(\.doubleValue)
        } ?? []
        let totalTokens = raw["predictions"]?.arrayValue?.reduce(0) { partial, prediction in
            partial + (prediction["embeddings"]?["statistics"]?["token_count"]?.intValue ?? 0)
        }
        return EmbeddingResult(
            embeddings: embeddings,
            usage: totalTokens.map { TokenUsage(totalTokens: $0) },
            rawValue: raw,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

public final class GoogleVertexTranscriptionModel: TranscriptionModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: GoogleVertexConfig

    init(modelID: String, config: GoogleVertexConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        let options = try googleVertexTranscriptionProviderOptions(from: request)
        guard let project = config.project, !project.isEmpty else {
            throw AIError.invalidURL("Google Vertex transcription requires project in settings or GOOGLE_VERTEX_PROJECT.")
        }
        let region = options["region"]?.stringValue ?? config.location ?? "global"
        let languageCodes = options["languageCodes"]?.arrayValue?.compactMap(\.stringValue)
            ?? request.language.map { [$0] }
            ?? ["auto"]
        var features: [String: JSONValue] = [
            "enableWordTimeOffsets": options["enableWordTimeOffsets"] ?? .bool(true),
            "enableAutomaticPunctuation": options["enableAutomaticPunctuation"] ?? .bool(true)
        ]
        features.merge(request.extraBody["features"]?.objectValue ?? [:]) { _, new in new }
        var configBody: [String: JSONValue] = [
            "model": .string(modelID),
            "languageCodes": .array(languageCodes.map(JSONValue.string)),
            "autoDecodingConfig": .object([:]),
            "features": .object(features)
        ]
        if let explicitConfig = request.extraBody["config"]?.objectValue {
            configBody.merge(explicitConfig) { _, new in new }
        }
        var body: [String: JSONValue] = [
            "config": .object(configBody),
            "content": .string(request.audio.base64EncodedString())
        ]
        body.merge(request.extraBody.filter { key, _ in
            !["config", "features", "region", "languageCodes", "enableAutomaticPunctuation", "enableWordTimeOffsets"].contains(key)
        }) { _, new in new }

        let host = region == "global" ? "speech.googleapis.com" : "\(region)-speech.googleapis.com"
        let url = "https://\(host)/v2/projects/\(project)/locations/\(region)/recognizers/_:recognize"
        let response = try await config.sendJSONResponse(url: url, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let results = raw["results"]?.arrayValue ?? []
        let text = results.compactMap { result in
            result["alternatives"]?[0]?["transcript"]?.stringValue
        }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = googleVertexTranscriptionSegments(from: results)
        return TranscriptionResult(
            text: text,
            rawValue: raw,
            segments: segments,
            language: googleVertexISO639Language(from: results.first?["languageCode"]?.stringValue),
            durationInSeconds: googleVertexDurationSeconds(raw["metadata"]?["totalBilledDuration"]?.stringValue),
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

public final class GoogleVertexSpeechModel: SpeechModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: GoogleVertexConfig

    init(modelID: String, config: GoogleVertexConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func speak(_ request: SpeechRequest) async throws -> SpeechResult {
        let options = googleVertexSpeechProviderOptions(from: request)
        let multiSpeakerVoiceConfig = options["multiSpeakerVoiceConfig"]
        var warnings: [AIWarning] = []
        if request.speed != nil {
            warnings.append(AIWarning(type: "unsupported", feature: "speed", message: "Google Vertex speech models do not support the `speed` option."))
        }
        if request.language != nil {
            warnings.append(AIWarning(type: "unsupported", feature: "language", message: "Google Vertex speech models do not support the `language` option."))
        }

        let text: String
        if let instructions = request.instructions, !instructions.isEmpty {
            if multiSpeakerVoiceConfig != nil {
                warnings.append(AIWarning(type: "unsupported", feature: "instructions", message: "Google Vertex speech models ignore `instructions` when `multiSpeakerVoiceConfig` is set."))
                text = request.text
            } else {
                text = "\(instructions): \(request.text)"
            }
        } else {
            text = request.text
        }

        let outputFormat: GoogleVertexSpeechOutputFormat
        switch request.format?.lowercased() {
        case nil, "wav":
            outputFormat = .wav
        case "pcm":
            outputFormat = .pcm
            warnings.append(AIWarning(type: "unsupported", feature: "outputFormat", message: "Google Vertex speech returns raw PCM only when `format` is `pcm`; WAV is the default wrapped output."))
        case let format?:
            outputFormat = .wav
            warnings.append(AIWarning(type: "unsupported", feature: "outputFormat", message: "Google Vertex speech does not support `\(format)`. Falling back to WAV."))
        }

        var speechConfig: [String: JSONValue] = [:]
        if let multiSpeakerVoiceConfig {
            speechConfig["multiSpeakerVoiceConfig"] = multiSpeakerVoiceConfig
        } else {
            speechConfig["voiceConfig"] = .object([
                "prebuiltVoiceConfig": .object([
                    "voiceName": .string(request.voice ?? "Kore")
                ])
            ])
        }

        let body = JSONValue.object([
            "contents": .array([
                .object([
                    "role": .string("user"),
                    "parts": .array([.object(["text": .string(text)])])
                ])
            ]),
            "generationConfig": .object([
                "responseModalities": .array([.string("AUDIO")]),
                "speechConfig": .object(speechConfig)
            ])
        ])
        let response = try await config.sendJSONResponse(
            path: "/models/\(modelID):generateContent",
            body: body,
            headers: request.headers,
            abortSignal: request.abortSignal
        )
        let raw = response.json
        let inlineData = googleVertexSpeechInlineData(from: raw)
        let mimeType = inlineData.mimeType
        let sampleRate = googleVertexSpeechSampleRate(from: mimeType) ?? 24_000
        let pcm = inlineData.data.flatMap { Data(base64Encoded: $0) } ?? Data()
        let audio: Data
        let contentType: String
        switch outputFormat {
        case .wav:
            audio = pcm.isEmpty ? pcm : googleVertexSpeechWAVData(fromPCM: pcm, sampleRate: sampleRate)
            contentType = "audio/wav"
        case .pcm:
            audio = pcm
            contentType = mimeType ?? "audio/L16;rate=\(sampleRate)"
        }

        return SpeechResult(
            audio: audio,
            contentType: contentType,
            warnings: warnings,
            providerMetadata: ["googleVertex": .object([
                "sampleRate": .number(Double(sampleRate)),
                "mimeType": mimeType.map(JSONValue.string) ?? .null
            ])],
            requestMetadata: AIRequestMetadata(body: body, headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

public final class GoogleVertexInteractionsLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let agent: String?
    private let config: GoogleVertexConfig

    init(modelID: String, agent: String?, config: GoogleVertexConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.agent = agent
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = try googleInteractionsPreparedCall(for: request, modelID: modelID, agent: agent, stream: false)
        let raw = try await sendInteractions(body: .object(prepared.body), headers: request.headers, abortSignal: request.abortSignal)
        let final = try await resolvedInteraction(raw, requestHeaders: request.headers, abortSignal: request.abortSignal)
        let text = googleInteractionsText(from: final)
        let toolCalls = googleInteractionsToolCalls(from: final)
        guard !text.isEmpty || !toolCalls.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No model_output text found in Google Vertex Interactions response.")
        }
        return TextGenerationResult(
            text: text,
            finishReason: googleInteractionsFinishReason(status: final["status"]?.stringValue, hasFunctionCall: googleInteractionsHasFunctionCall(final)),
            usage: googleInteractionsUsage(from: final),
            toolCalls: toolCalls,
            sources: googleInteractionsSources(from: final),
            providerMetadata: googleInteractionsProviderMetadata(from: final),
            rawValue: final,
            warnings: prepared.warnings
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = try googleInteractionsPreparedCall(for: request, modelID: modelID, agent: agent, stream: true)
                    let httpRequest = try await config.request(
                        path: "/interactions",
                        body: .object(prepared.body),
                        headers: googleInteractionsHeaders(request.headers),
                        abortSignal: request.abortSignal
                    )
                    let response = try await config.transport.send(httpRequest)
                    guard (200..<300).contains(response.statusCode) else {
                        throw apiCallError(provider: providerID, response: response)
                    }
                    if !prepared.warnings.isEmpty {
                        continuation.yield(.streamStart(warnings: prepared.warnings))
                    }
                    var toolCalls = GoogleInteractionsStreamingToolCalls()
                    var hasFunctionCall = false
                    var sourceCounter = 0
                    var emittedSourceKeys: Set<String> = []
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        for source in googleInteractionsSources(from: raw, sourceCounter: &sourceCounter, emittedKeys: &emittedSourceKeys) {
                            continuation.yield(.source(source))
                        }
                        if let interaction = raw["interaction"] {
                            let metadata = googleInteractionsProviderMetadata(from: interaction)
                            if !metadata.isEmpty {
                                continuation.yield(.metadata(metadata))
                            }
                        }
                        let eventType = raw["event_type"]?.stringValue
                        if eventType == "step.start", raw["step"]?["type"]?.stringValue == "function_call" {
                            hasFunctionCall = true
                            for part in toolCalls.start(step: raw["step"], index: raw["index"]?.intValue) {
                                continuation.yield(part)
                            }
                        }
                        if eventType == "step.delta", let delta = raw["delta"] {
                            if let text = delta["text"]?.stringValue, !text.isEmpty {
                                continuation.yield(.textDelta(text))
                            }
                            if let summary = delta["summary"]?.stringValue, !summary.isEmpty {
                                continuation.yield(.reasoningDelta(summary))
                            }
                            if delta["type"]?.stringValue == "arguments_delta" {
                                hasFunctionCall = true
                                for part in toolCalls.delta(delta, index: raw["index"]?.intValue) {
                                    continuation.yield(part)
                                }
                            }
                        }
                        if eventType == "step.stop" {
                            for part in toolCalls.stop(index: raw["index"]?.intValue) {
                                continuation.yield(part)
                            }
                        }
                        if eventType == "interaction.completed" || eventType == "interaction.failed" || eventType == "interaction.incomplete" || eventType == "interaction.cancelled" {
                            let interaction = raw["interaction"] ?? raw
                            continuation.yield(.finish(
                                reason: googleInteractionsFinishReason(status: interaction["status"]?.stringValue, hasFunctionCall: hasFunctionCall),
                                usage: googleInteractionsUsage(from: interaction)
                            ))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func sendInteractions(body: JSONValue, headers: [String: String], abortSignal: AIAbortSignal?) async throws -> JSONValue {
        let response = try await config.transport.send(try await config.request(path: "/interactions", body: body, headers: googleInteractionsHeaders(headers), abortSignal: abortSignal))
        guard (200..<300).contains(response.statusCode) else {
            throw apiCallError(provider: providerID, response: response)
        }
        return try response.jsonValue()
    }

    private func resolvedInteraction(_ raw: JSONValue, requestHeaders: [String: String], abortSignal: AIAbortSignal?) async throws -> JSONValue {
        guard agent != nil,
              !googleInteractionsIsTerminal(raw["status"]?.stringValue),
              let id = raw["id"]?.stringValue else {
            return raw
        }
        return try await pollInteraction(id: id, requestHeaders: requestHeaders, timeoutNanoseconds: googleInteractionsPollTimeout(raw: raw), abortSignal: abortSignal)
    }

    private func pollInteraction(id: String, requestHeaders: [String: String], timeoutNanoseconds: UInt64, abortSignal: AIAbortSignal?) async throws -> JSONValue {
        let started = DispatchTime.now().uptimeNanoseconds
        repeat {
            let response = try await config.transport.send(AIHTTPRequest(
                method: "GET",
                url: try requireURL("\(config.baseURL)/interactions/\(id)"),
                headers: try await config.authenticatedHeaders(googleInteractionsHeaders(requestHeaders)),
                abortSignal: abortSignal
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw apiCallError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            if googleInteractionsIsTerminal(raw["status"]?.stringValue) {
                return raw
            }
            try await sleepWithAbortSignal(nanoseconds: 10_000_000, abortSignal: abortSignal)
        } while DispatchTime.now().uptimeNanoseconds - started < timeoutNanoseconds

        throw AIError.invalidResponse(provider: providerID, message: "Google Vertex Interactions polling timed out.")
    }
}

public final class GoogleVertexImageModel: ImageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: GoogleVertexConfig

    init(modelID: String, config: GoogleVertexConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        if modelID.starts(with: "gemini-") {
            let languageResult = try await GoogleVertexLanguageModel(modelID: modelID, config: config).generate(LanguageModelRequest(messages: [.user(request.prompt)], extraBody: request.extraBody, headers: request.headers, abortSignal: request.abortSignal))
            let images = languageResult.rawValue["candidates"]?[0]?["content"]?["parts"]?.arrayValue?.compactMap { part in
                part["inlineData"]?["data"]?.stringValue
            } ?? []
            return ImageGenerationResult(
                urls: [],
                base64Images: images,
                rawValue: languageResult.rawValue,
                requestMetadata: imageGenerationRequestMetadata(request),
                responseMetadata: languageResult.responseMetadata
            )
        }

        let body = try googleVertexImageBody(for: request)
        let response = try await config.sendJSONResponse(path: "/models/\(modelID):predict", body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let images = raw["predictions"]?.arrayValue?.compactMap { prediction in
            prediction["bytesBase64Encoded"]?.stringValue
        } ?? []
        return ImageGenerationResult(
            urls: [],
            base64Images: images,
            rawValue: raw,
            requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

public final class GoogleVertexVideoModel: VideoModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: GoogleVertexConfig

    init(modelID: String, config: GoogleVertexConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        let options = googleVertexVideoProviderOptions(from: request)
        var warnings: [AIWarning] = []
        var instance: [String: JSONValue] = [:]
        if !request.prompt.isEmpty {
            instance["prompt"] = .string(request.prompt)
        }
        if let firstFrame = request.frameImages.first(where: { $0.frameType == .firstFrame }) {
            if let image = googleVertexVideoImage(firstFrame.image) {
                instance["image"] = image
            } else if firstFrame.image.url != nil {
                warnings.append(AIWarning(
                    type: "unsupported",
                    feature: "URL-based image input",
                    message: "Vertex AI video models require base64-encoded images or GCS URIs. URL will be ignored."
                ))
            }
        } else if let image = request.image {
            if image.url != nil {
                warnings.append(AIWarning(
                    type: "unsupported",
                    feature: "URL-based image input",
                    message: "Vertex AI video models require base64-encoded images or GCS URIs. URL will be ignored."
                ))
            } else if let image = googleVertexVideoImage(image) {
                instance["image"] = image
            }
        }
        if let lastFrame = request.frameImages.first(where: { $0.frameType == .lastFrame }), let image = googleVertexVideoImage(lastFrame.image) {
            instance["lastFrame"] = image
        }
        if !request.inputReferences.isEmpty {
            let referenceImages = request.inputReferences.compactMap(googleVertexVideoReferenceImage)
            if !referenceImages.isEmpty {
                instance["referenceImages"] = .array(referenceImages)
            }
        } else if let referenceImages = options["referenceImages"] {
            instance["referenceImages"] = referenceImages
        }

        var parameters: [String: JSONValue] = [:]
        if let count = request.count { parameters["sampleCount"] = .number(Double(count)) }
        if let aspectRatio = request.aspectRatio { parameters["aspectRatio"] = .string(aspectRatio) }
        if let resolution = request.resolution { parameters["resolution"] = .string(googleVertexVideoResolution(resolution)) }
        if let duration = request.durationSeconds { parameters["durationSeconds"] = .number(duration) }
        if let seed = request.seed { parameters["seed"] = .number(Double(seed)) }
        if let generateAudio = request.generateAudio ?? options["generateAudio"]?.boolValue {
            parameters["generateAudio"] = .bool(generateAudio)
        }
        parameters.merge(options.filter { key, value in
            !googleVertexVideoInternalOptionKeys.contains(key) && value != .null
        }) { _, new in new }
        var body: [String: JSONValue] = [
            "instances": .array([.object(instance)])
        ]
        if !parameters.isEmpty { body["parameters"] = .object(parameters) }
        let initialResponse = try await config.sendJSONResponse(path: "/models/\(modelID):predictLongRunning", body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let operationName = try googleVertexVideoOperationName(from: initialResponse.json, providerID: providerID)
        let finalResponse = try await googleVertexPollVideoOperation(
            initial: initialResponse,
            operationName: operationName,
            config: config,
            modelID: modelID,
            headers: request.headers,
            options: options,
            abortSignal: request.abortSignal
        )
        let raw = finalResponse.json
        let videos = raw["response"]?["videos"]?.arrayValue ?? raw["videos"]?.arrayValue ?? []
        guard !videos.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No videos in Vertex video response.")
        }
        let urls = videos.compactMap { $0["gcsUri"]?.stringValue ?? $0["url"]?.stringValue }
        let base64Videos = videos.compactMap { $0["bytesBase64Encoded"]?.stringValue }
        guard !urls.isEmpty || !base64Videos.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No valid videos in Vertex video response.")
        }
        let videoMetadata = JSONValue.object([
            "videos": .array(videos.map { video in
                .object([
                    "gcsUri": video["gcsUri"] ?? .null,
                    "mimeType": video["mimeType"] ?? .null
                ])
            })
        ])
        return VideoGenerationResult(
            urls: urls,
            base64Videos: base64Videos,
            operationID: operationName,
            rawValue: raw,
            warnings: warnings,
            providerMetadata: [
                "googleVertex": videoMetadata,
                "google-vertex": videoMetadata,
                "vertex": videoMetadata
            ],
            requestMetadata: videoGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: finalResponse.response, modelID: modelID)
        )
    }
}

private func googleVertexUsesEmbedContentEndpoint(_ modelID: String) -> Bool {
    modelID == "gemini-embedding-2" || modelID == "gemini-embedding-2-preview"
}

private struct GoogleVertexGenerateContentPreparedCall {
    var body: JSONValue
    var warnings: [AIWarning]
    var headers: [String: String]
}

private func googleGenerateContentBody(_ request: LanguageModelRequest, modelID: String, providerID: String, isStreaming: Bool = false) throws -> GoogleVertexGenerateContentPreparedCall {
    let preparedOptions = googlePrepareGenerateContentOptions(
        from: request,
        modelID: modelID,
        providerID: providerID,
        isVertexProvider: true
    )
    var options = preparedOptions.options
    let responseFormat = googleResolvedResponseFormat(request: request, options: &options)
    var warnings = preparedOptions.warnings
    let systemText = request.messages.filter { $0.role == .system }.map(\.combinedText).joined(separator: "\n")
    let rawContents = try request.messages.filter { $0.role != .system }.map { message in
        try googleGenerateContentMessageJSON(message, modelID: modelID, warnings: &warnings)
    }
    let preparedMessages = googleContentsWithSystemInstruction(systemText: systemText, contents: rawContents, modelID: modelID)
    var body: [String: JSONValue] = ["contents": .array(preparedMessages.contents)]
    if let systemInstruction = preparedMessages.systemInstruction {
        body["systemInstruction"] = systemInstruction
    }
    var generationConfig: [String: JSONValue] = [:]
    googleApplyStandardGenerationSettings(request, to: &generationConfig)
    googleApplyResponseFormat(responseFormat, options: options, to: &generationConfig)
    googleApplyProviderGenerationOptions(options, to: &generationConfig)
    if !generationConfig.isEmpty { body["generationConfig"] = .object(generationConfig) }
    if let preparedTools = googlePrepareTools(from: request.tools, toolChoice: options["toolChoice"], modelID: modelID, isVertexProvider: true) {
        warnings.append(contentsOf: preparedTools.warnings)
        if !preparedTools.tools.isEmpty {
            body["tools"] = .array(preparedTools.tools)
        }
        if let toolConfig = googleToolConfigWithProviderOptions(preparedTools.toolConfig, options: options, isStreaming: isStreaming, isVertexProvider: true) {
            body["toolConfig"] = toolConfig
        }
    } else if let toolConfig = googleToolConfigWithProviderOptions(nil, options: options, isStreaming: isStreaming, isVertexProvider: true) {
        body["toolConfig"] = toolConfig
    }
    body.merge(googleTopLevelGenerateContentOptions(options)) { _, new in new }
    body.merge(googleExtraBodyWithoutToolChoice(options)) { _, new in new }
    return GoogleVertexGenerateContentPreparedCall(body: .object(body), warnings: warnings, headers: preparedOptions.headers)
}

private func googleVertexImageBody(for request: ImageGenerationRequest) throws -> [String: JSONValue] {
    let options = googleVertexImageProviderOptions(from: request.extraBody)
    if request.files.isEmpty {
        var body: [String: JSONValue] = [
            "instances": .array([.object(["prompt": .string(request.prompt)])])
        ]
        let parameters = googleVertexImagenParameters(for: request, options: options)
        if !parameters.isEmpty {
            body["parameters"] = .object(parameters)
        }
        return body
    }

    let edit = options["edit"]?.objectValue ?? [:]
    var referenceImages: [JSONValue] = []
    for (index, file) in request.files.enumerated() {
        referenceImages.append(.object([
            "referenceType": .string("REFERENCE_TYPE_RAW"),
            "referenceId": .number(Double(index + 1)),
            "referenceImage": .object([
                "bytesBase64Encoded": .string(try googleVertexImageEditBase64(file))
            ])
        ]))
    }
    if let mask = request.mask {
        var maskImageConfig: [String: JSONValue] = [
            "maskMode": edit["maskMode"] ?? .string("MASK_MODE_USER_PROVIDED")
        ]
        if let dilation = edit["maskDilation"] {
            maskImageConfig["dilation"] = dilation
        }
        referenceImages.append(.object([
            "referenceType": .string("REFERENCE_TYPE_MASK"),
            "referenceId": .number(Double(request.files.count + 1)),
            "referenceImage": .object([
                "bytesBase64Encoded": .string(try googleVertexImageEditBase64(mask))
            ]),
            "maskImageConfig": .object(maskImageConfig)
        ]))
    }

    var parameters = googleVertexImagenParameters(for: request, options: options)
    parameters["editMode"] = edit["mode"] ?? .string("EDIT_MODE_INPAINT_INSERTION")
    if let baseSteps = edit["baseSteps"] {
        parameters["editConfig"] = .object(["baseSteps": baseSteps])
    }

    return [
        "instances": .array([.object([
            "prompt": .string(request.prompt),
            "referenceImages": .array(referenceImages)
        ])]),
        "parameters": .object(parameters)
    ]
}

private func googleVertexImagenParameters(for request: ImageGenerationRequest, options: [String: JSONValue]) -> [String: JSONValue] {
    var parameters: [String: JSONValue] = ["sampleCount": .number(Double(request.count ?? 1))]
    if let aspectRatio = googleVertexImageAspectRatio(from: request) {
        parameters["aspectRatio"] = .string(aspectRatio)
    }
    parameters.merge(options.filter { key, _ in key != "edit" && key != "googleSearch" }) { _, new in new }
    if let seed = request.extraBody["seed"] {
        parameters["seed"] = seed
    }
    return parameters
}

private func googleVertexImageProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    if let googleVertex = extraBody["googleVertex"]?.objectValue {
        return googleVertex
    }
    if let vertex = extraBody["vertex"]?.objectValue {
        return vertex
    }
    return extraBody.filter { $0.key != "googleVertex" && $0.key != "vertex" }
}

private func googleVertexEmbeddingProviderOptions(from request: EmbeddingRequest) -> [String: JSONValue] {
    if let googleVertex = request.providerOptions["googleVertex"]?.objectValue {
        return googleVertex
    }
    if let vertex = request.providerOptions["vertex"]?.objectValue {
        return vertex
    }
    if let google = request.providerOptions["google"]?.objectValue {
        return google
    }
    return [:]
}

private func googleVertexTranscriptionProviderOptions(from request: AudioTranscriptionRequest) throws -> [String: JSONValue] {
    var options = request.extraBody
    if let googleVertex = request.providerOptions["googleVertex"] {
        guard let object = googleVertex.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.googleVertex", message: "Google Vertex transcription provider options must be an object.")
        }
        options.merge(object) { _, new in new }
    } else if let vertex = request.providerOptions["vertex"] {
        guard let object = vertex.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.vertex", message: "Google Vertex transcription provider options must be an object.")
        }
        options.merge(object) { _, new in new }
    } else if let google = request.providerOptions["google"] {
        guard let object = google.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.google", message: "Google Vertex transcription provider options must be an object.")
        }
        options.merge(object) { _, new in new }
    }
    if let languageCodes = options["languageCodes"],
       languageCodes.arrayValue?.allSatisfy({ $0.stringValue != nil }) != true {
        throw AIError.invalidArgument(argument: "providerOptions.googleVertex.languageCodes", message: "Google Vertex languageCodes must be an array of strings.")
    }
    for key in ["enableAutomaticPunctuation", "enableWordTimeOffsets"] where options[key] != nil && options[key]?.boolValue == nil {
        throw AIError.invalidArgument(argument: "providerOptions.googleVertex.\(key)", message: "Google Vertex \(key) must be a boolean.")
    }
    if options["region"] != nil && options["region"]?.stringValue == nil {
        throw AIError.invalidArgument(argument: "providerOptions.googleVertex.region", message: "Google Vertex region must be a string.")
    }
    return options
}

private func googleVertexTranscriptionSegments(from results: [JSONValue]) -> [TranscriptionSegment] {
    results.flatMap { result in
        result["alternatives"]?[0]?["words"]?.arrayValue?.compactMap { word in
            guard let text = word["word"]?.stringValue,
                  let start = googleVertexDurationSeconds(word["startOffset"]?.stringValue),
                  let end = googleVertexDurationSeconds(word["endOffset"]?.stringValue) else {
                return nil
            }
            return TranscriptionSegment(text: text, startSecond: start, endSecond: end)
        } ?? []
    }
}

private func googleVertexDurationSeconds(_ value: String?) -> Double? {
    guard let value else { return nil }
    let trimmed = value.hasSuffix("s") ? String(value.dropLast()) : value
    return Double(trimmed)
}

private func googleVertexISO639Language(from value: String?) -> String? {
    guard let value else { return nil }
    let language = value.split(separator: "-").first.map(String.init) ?? value
    return language.count == 2 ? language : nil
}

private func googleVertexVideoProviderOptions(from request: VideoGenerationRequest) -> [String: JSONValue] {
    var options = request.extraBody
    if let googleVertex = request.providerOptions["googleVertex"]?.objectValue {
        options.merge(googleVertex) { _, new in new }
    } else if let vertex = request.providerOptions["vertex"]?.objectValue {
        options.merge(vertex) { _, new in new }
    }
    return options
}

private let googleVertexVideoInternalOptionKeys: Set<String> = [
    "generateAudio",
    "pollIntervalMs",
    "pollTimeoutMs",
    "referenceImages"
]

private enum GoogleVertexSpeechOutputFormat {
    case wav
    case pcm
}

private func googleVertexSpeechProviderOptions(from request: SpeechRequest) -> [String: JSONValue] {
    var options = request.extraBody
    if let googleVertex = request.extraBody["googleVertex"]?.objectValue {
        options = googleVertex
    } else if let vertex = request.extraBody["vertex"]?.objectValue {
        options = vertex
    }
    if let googleVertex = request.providerOptions["googleVertex"]?.objectValue {
        options.merge(googleVertex) { _, new in new }
    } else if let vertex = request.providerOptions["vertex"]?.objectValue {
        options.merge(vertex) { _, new in new }
    } else if let google = request.providerOptions["google"]?.objectValue {
        options.merge(google) { _, new in new }
    }
    return options.filter { $0.key != "google" && $0.key != "googleVertex" && $0.key != "vertex" }
}

private func googleVertexSpeechInlineData(from raw: JSONValue) -> (mimeType: String?, data: String?) {
    let parts = raw["candidates"]?[0]?["content"]?["parts"]?.arrayValue ?? []
    for part in parts {
        if let inlineData = part["inlineData"]?.objectValue {
            return (inlineData["mimeType"]?.stringValue, inlineData["data"]?.stringValue)
        }
    }
    return (nil, nil)
}

private func googleVertexSpeechSampleRate(from mimeType: String?) -> Int? {
    guard let mimeType else { return nil }
    for component in mimeType.split(separator: ";") {
        let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("rate=") else { continue }
        return Int(trimmed.dropFirst("rate=".count))
    }
    return nil
}

private func googleVertexSpeechWAVData(fromPCM pcm: Data, sampleRate: Int) -> Data {
    let channelCount = 1
    let bitsPerSample = 16
    let byteRate = sampleRate * channelCount * bitsPerSample / 8
    let blockAlign = channelCount * bitsPerSample / 8
    var data = Data()
    data.append(Data("RIFF".utf8))
    googleVertexSpeechAppendUInt32LE(UInt32(36 + pcm.count), to: &data)
    data.append(Data("WAVE".utf8))
    data.append(Data("fmt ".utf8))
    googleVertexSpeechAppendUInt32LE(16, to: &data)
    googleVertexSpeechAppendUInt16LE(1, to: &data)
    googleVertexSpeechAppendUInt16LE(UInt16(channelCount), to: &data)
    googleVertexSpeechAppendUInt32LE(UInt32(sampleRate), to: &data)
    googleVertexSpeechAppendUInt32LE(UInt32(byteRate), to: &data)
    googleVertexSpeechAppendUInt16LE(UInt16(blockAlign), to: &data)
    googleVertexSpeechAppendUInt16LE(UInt16(bitsPerSample), to: &data)
    data.append(Data("data".utf8))
    googleVertexSpeechAppendUInt32LE(UInt32(pcm.count), to: &data)
    data.append(pcm)
    return data
}

private func googleVertexSpeechAppendUInt16LE(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
}

private func googleVertexSpeechAppendUInt32LE(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8((value >> 24) & 0xff))
}

private func googleVertexVideoImage(_ image: ImageInputFile) -> JSONValue? {
    if let data = image.data {
        return .object([
            "bytesBase64Encoded": .string(data.base64EncodedString()),
            "mimeType": .string(image.mediaType ?? "image/png")
        ])
    }
    if let url = image.url, url.hasPrefix("gs://") {
        return .object([
            "gcsUri": .string(url),
            "mimeType": .string(image.mediaType ?? googleVertexVideoMimeType(for: url))
        ])
    }
    return nil
}

private func googleVertexVideoReferenceImage(_ image: ImageInputFile) -> JSONValue? {
    guard let prepared = googleVertexVideoImage(image) else { return nil }
    return .object([
        "image": prepared,
        "referenceType": .string("asset")
    ])
}

private func googleVertexVideoMimeType(for url: String) -> String {
    let path = URL(string: url)?.path.lowercased() ?? url.lowercased()
    if path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") {
        return "image/jpeg"
    }
    if path.hasSuffix(".webp") {
        return "image/webp"
    }
    return "image/png"
}

private func googleVertexVideoResolution(_ resolution: String) -> String {
    switch resolution {
    case "1280x720":
        return "720p"
    case "1920x1080":
        return "1080p"
    case "3840x2160":
        return "4k"
    default:
        return resolution
    }
}

private func googleVertexPollVideoOperation(
    initial: (json: JSONValue, response: AIHTTPResponse),
    operationName: String,
    config: GoogleVertexConfig,
    modelID: String,
    headers: [String: String],
    options: [String: JSONValue],
    abortSignal: AIAbortSignal?
) async throws -> (json: JSONValue, response: AIHTTPResponse) {
    var current = initial
    let pollIntervalNanoseconds = googleVertexVideoPollInterval(options)
    let pollTimeoutNanoseconds = googleVertexVideoPollTimeout(options)
    let started = DispatchTime.now().uptimeNanoseconds
    while current.json["done"]?.boolValue != true {
        if DispatchTime.now().uptimeNanoseconds - started > pollTimeoutNanoseconds {
            throw AIError.invalidResponse(provider: config.providerID, message: "Video generation timed out after \(pollTimeoutNanoseconds / 1_000_000)ms.")
        }
        try await sleepWithAbortSignal(nanoseconds: pollIntervalNanoseconds, abortSignal: abortSignal)
        current = try await config.sendJSONResponse(
            path: "/models/\(modelID):fetchPredictOperation",
            body: .object(["operationName": .string(operationName)]),
            headers: headers,
            abortSignal: abortSignal
        )
    }
    if let message = current.json["error"]?["message"]?.stringValue {
        throw AIError.invalidResponse(provider: config.providerID, message: "Video generation failed: \(message)")
    }
    return current
}

private func googleVertexVideoOperationName(from operation: JSONValue, providerID: String) throws -> String {
    guard let operationName = operation["name"]?.stringValue, !operationName.isEmpty else {
        throw AIError.invalidResponse(provider: providerID, message: "No operation name returned from Vertex video response.")
    }
    return operationName
}

private func googleVertexVideoPollInterval(_ options: [String: JSONValue]) -> UInt64 {
    let milliseconds = options["pollIntervalMs"]?.intValue ?? 10_000
    return UInt64(milliseconds) * 1_000_000
}

private func googleVertexVideoPollTimeout(_ options: [String: JSONValue]) -> UInt64 {
    let milliseconds = options["pollTimeoutMs"]?.intValue ?? 600_000
    return UInt64(milliseconds) * 1_000_000
}

private func googleVertexImageAspectRatio(from request: ImageGenerationRequest) -> String? {
    if let aspectRatio = request.extraBody["aspectRatio"]?.stringValue {
        return aspectRatio
    }
    if let size = request.size, size.contains(":") {
        return size
    }
    return nil
}

private func googleVertexImageEditBase64(_ file: ImageInputFile) throws -> String {
    if file.url != nil {
        throw AIError.invalidArgument(argument: "files", message: "URL-based images are not supported for Google Vertex image editing. Provide image data directly.")
    }
    guard let data = file.data else {
        throw AIError.invalidArgument(argument: "files", message: "Image file must contain data for Google Vertex image editing.")
    }
    return data.base64EncodedString()
}
