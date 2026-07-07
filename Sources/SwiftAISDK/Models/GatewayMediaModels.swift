import Foundation

public final class GatewayEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        var body: [String: JSONValue] = ["values": .array(request.values)]
        if !request.providerOptions.isEmpty { body["providerOptions"] = .object(request.providerOptions) }
        body.merge(request.extraBody) { _, new in new }
        let response = try await config.sendJSONResponse(path: "/embedding-model", modelID: modelID, body: .object(body), headers: request.headers.mergingHeaders([
            "ai-embedding-model-specification-version": "4",
            "ai-model-id": modelID
        ]), abortSignal: request.abortSignal)
        let raw = response.json
        guard let embeddings = raw["embeddings"]?.arrayValue?.map({ item in item.arrayValue?.compactMap(\.doubleValue) ?? [] }) else {
            throw AIError.invalidResponse(provider: providerID, message: "No embeddings found in Gateway response.")
        }
        return EmbeddingResult(
            embeddings: embeddings,
            usage: gatewayEmbeddingUsage(from: raw),
            rawValue: raw,
            warnings: gatewayWarnings(from: raw["warnings"]),
            providerMetadata: gatewayProviderMetadata(raw["providerMetadata"] ?? raw["provider_metadata"]),
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

func gatewayEmbeddingUsage(from raw: JSONValue) -> TokenUsage? {
    if let tokens = raw["usage"]?["tokens"]?.intValue {
        return TokenUsage(totalTokens: tokens)
    }
    return tokenUsage(from: raw)
}

public final class GatewayImageModel: ImageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        var body: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if let count = request.count { body["n"] = .number(Double(count)) }
        if let size = request.size { body["size"] = .string(size) }
        if let aspectRatio = request.aspectRatio { body["aspectRatio"] = .string(aspectRatio) }
        if let seed = request.seed { body["seed"] = .number(Double(seed)) }
        if !request.providerOptions.isEmpty { body["providerOptions"] = .object(request.providerOptions) }
        body.merge(request.extraBody) { _, new in new }
        if !request.files.isEmpty {
            body["files"] = .array(request.files.map(gatewayImageFile))
        }
        if let mask = request.mask {
            body["mask"] = gatewayImageFile(mask)
        }
        let response = try await config.sendJSONResponse(path: "/image-model", modelID: modelID, body: .object(body), headers: request.headers.mergingHeaders([
            "ai-image-model-specification-version": "4",
            "ai-model-id": modelID
        ]))
        let raw = response.json
        let images = raw["images"]?.arrayValue ?? raw["data"]?.arrayValue ?? []
        return ImageGenerationResult(
            urls: images.compactMap { $0["url"]?.stringValue },
            base64Images: images.compactMap { $0["data"]?.stringValue ?? $0.stringValue ?? $0["b64_json"]?.stringValue },
            rawValue: raw,
            warnings: gatewayWarnings(from: raw["warnings"]),
            providerMetadata: gatewayProviderMetadata(raw["providerMetadata"] ?? raw["provider_metadata"]),
            requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

func gatewayImageFile(_ file: ImageInputFile) -> JSONValue {
    if let url = file.url {
        return .object([
            "type": .string("url"),
            "url": .string(url)
        ])
    }
    return .object([
        "type": .string("file"),
        "mediaType": .string(file.mediaType ?? "application/octet-stream"),
        "data": .string((file.data ?? Data()).base64EncodedString())
    ])
}

public final class GatewayVideoModel: VideoModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        var body: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if let aspectRatio = request.aspectRatio { body["aspectRatio"] = .string(aspectRatio) }
        if let durationSeconds = request.durationSeconds { body["duration"] = .number(durationSeconds) }
        if let count = request.count { body["n"] = .number(Double(count)) }
        if let resolution = request.resolution { body["resolution"] = .string(resolution) }
        if let fps = request.fps { body["fps"] = .number(fps) }
        if let seed = request.seed { body["seed"] = .number(Double(seed)) }
        if let generateAudio = request.generateAudio { body["generateAudio"] = .bool(generateAudio) }
        if !request.providerOptions.isEmpty { body["providerOptions"] = .object(request.providerOptions) }
        if let image = request.image { body["image"] = gatewayVideoFile(image) }
        if !request.frameImages.isEmpty {
            body["frameImages"] = .array(request.frameImages.map(gatewayVideoFrameImage))
        }
        if !request.inputReferences.isEmpty {
            body["inputReferences"] = .array(request.inputReferences.map(gatewayVideoFile))
        }
        body.merge(request.extraBody) { _, new in new }
        let httpRequest = try config.request(path: "/video-model", modelID: modelID, body: .object(body), headers: request.headers.mergingHeaders([
            "ai-video-model-specification-version": "4",
            "ai-model-id": modelID,
            "accept": "text/event-stream"
        ]))
        let response = try await config.transport.send(httpRequest)
        guard (200..<300).contains(response.statusCode) else {
            throw apiCallError(provider: providerID, response: response)
        }
        let raw: JSONValue
        if let event = parseServerSentEvents(response.body).first(where: { $0.data != "[DONE]" }) {
            raw = try decodeJSONBody(Data(event.data.utf8))
        } else {
            raw = try response.jsonValue()
        }
        if raw["type"]?.stringValue == "error" {
            let errorBody = JSONValue.object([
                "error": .object([
                    "message": raw["message"] ?? .string("Gateway request failed"),
                    "type": raw["errorType"] ?? .string("internal_server_error"),
                    "param": raw["param"] ?? .null
                ])
            ])
            throw apiCallError(
                provider: providerID,
                statusCode: raw["statusCode"]?.intValue ?? response.statusCode,
                body: String(data: try encodeJSONBody(errorBody), encoding: .utf8) ?? raw["message"]?.stringValue ?? String(describing: raw),
                headers: response.headers
            )
        }
        let videos = raw["videos"]?.arrayValue ?? raw["data"]?.arrayValue ?? []
        return VideoGenerationResult(
            urls: videos.compactMap { $0["url"]?.stringValue ?? $0.stringValue },
            base64Videos: videos.compactMap { $0["base64"]?.stringValue ?? $0["data"]?.stringValue },
            operationID: raw["id"]?.stringValue,
            mediaType: videos.first?["mediaType"]?.stringValue,
            rawValue: raw,
            warnings: gatewayWarnings(from: raw["warnings"]),
            providerMetadata: gatewayProviderMetadata(raw["providerMetadata"] ?? raw["provider_metadata"]),
            requestMetadata: videoGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: response, modelID: modelID)
        )
    }
}

func gatewayVideoFile(_ file: ImageInputFile) -> JSONValue {
    gatewayImageFile(file)
}

private func gatewayVideoFrameImage(_ frameImage: VideoFrameImage) -> JSONValue {
    .object([
        "frameType": .string(frameImage.frameType.rawValue),
        "image": gatewayVideoFile(frameImage.image)
    ])
}

public final class GatewayRerankingModel: RerankingModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func rerank(_ request: RerankingRequest) async throws -> RerankingResult {
        var body: [String: JSONValue] = [
            "query": .string(request.query),
            "documents": .array(request.documents)
        ]
        if let topK = request.topK { body["topN"] = .number(Double(topK)) }
        if !request.providerOptions.isEmpty { body["providerOptions"] = .object(request.providerOptions) }
        body.merge(request.extraBody) { _, new in new }
        let response = try await config.sendJSONResponse(path: "/reranking-model", modelID: modelID, body: .object(body), headers: request.headers.mergingHeaders([
            "ai-reranking-model-specification-version": "4",
            "ai-model-id": modelID
        ]), abortSignal: request.abortSignal)
        let raw = response.json
        let ranking = raw["ranking"]?.arrayValue ?? raw["results"]?.arrayValue ?? []
        return RerankingResult(results: ranking.compactMap { item in
            guard let index = item["index"]?.intValue,
                  let score = item["relevanceScore"]?.doubleValue ?? item["relevance_score"]?.doubleValue ?? item["score"]?.doubleValue else {
                return nil
            }
            return RerankedDocument(index: index, score: score)
        }, rawValue: raw, warnings: gatewayWarnings(from: raw["warnings"]), providerMetadata: gatewayProviderMetadata(raw["providerMetadata"] ?? raw["provider_metadata"]), requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers), responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID))
    }
}

public final class GatewaySpeechModel: SpeechModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func speak(_ request: SpeechRequest) async throws -> SpeechResult {
        var body: [String: JSONValue] = ["text": .string(request.text)]
        if let voice = request.voice { body["voice"] = .string(voice) }
        if let format = request.format { body["outputFormat"] = .string(format) }
        if let instructions = request.instructions { body["instructions"] = .string(instructions) }
        if let speed = request.speed { body["speed"] = .number(speed) }
        if let language = request.language { body["language"] = .string(language) }
        if !request.providerOptions.isEmpty { body["providerOptions"] = .object(request.providerOptions) }
        body.merge(request.extraBody) { _, new in new }
        let response = try await config.sendJSONResponse(path: "/speech-model", modelID: modelID, body: .object(body), headers: request.headers.mergingHeaders([
            "ai-speech-model-specification-version": "4",
            "ai-model-id": modelID
        ]))
        let raw = response.json
        guard let audio = raw["audio"]?.stringValue, let data = Data(base64Encoded: audio) else {
            throw AIError.invalidResponse(provider: providerID, message: "No base64 audio found in Gateway speech response.")
        }
        return SpeechResult(
            audio: data,
            warnings: gatewayWarnings(from: raw["warnings"]),
            providerMetadata: gatewayProviderMetadata(raw["providerMetadata"] ?? raw["provider_metadata"]),
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

public final class GatewayTranscriptionModel: TranscriptionModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        var body: [String: JSONValue] = [
            "audio": .string(request.audio.base64EncodedString()),
            "mediaType": .string(request.mimeType)
        ]
        if !request.providerOptions.isEmpty { body["providerOptions"] = .object(request.providerOptions) }
        body.merge(request.extraBody) { _, new in new }
        let response = try await config.sendJSONResponse(path: "/transcription-model", modelID: modelID, body: .object(body), headers: request.headers.mergingHeaders([
            "ai-transcription-model-specification-version": "4",
            "ai-model-id": modelID
        ]))
        let raw = response.json
        guard let text = raw["text"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "No text found in Gateway transcription response.")
        }
        let segments = standardTranscriptionSegments(from: raw)
        return TranscriptionResult(
            text: text,
            rawValue: raw,
            segments: segments,
            language: raw["language"]?.stringValue,
            durationInSeconds: raw["durationInSeconds"]?.doubleValue ?? raw["duration"]?.doubleValue ?? transcriptionDuration(from: segments),
            warnings: gatewayWarnings(from: raw["warnings"]),
            providerMetadata: gatewayProviderMetadata(raw["providerMetadata"] ?? raw["provider_metadata"]),
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

private func gatewayWarnings(from value: JSONValue?) -> [AIWarning] {
    value?.arrayValue?.map { warning in
        AIWarning(
            type: warning["type"]?.stringValue ?? "other",
            feature: warning["feature"]?.stringValue,
            setting: warning["setting"]?.stringValue,
            message: warning["message"]?.stringValue ?? warning["details"]?.stringValue
        )
    } ?? []
}
