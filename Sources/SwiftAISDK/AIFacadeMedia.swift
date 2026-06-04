import Foundation

extension AI {
    public static func embed(model: any EmbeddingModel, value: String, dimensions: Int? = nil, providerOptions: [String: JSONValue] = [:], extraBody: [String: JSONValue] = [:], headers: [String: String] = [:], abortSignal: AIAbortSignal? = nil, retryPolicy: AIRetryPolicy = .default, telemetry: AITelemetryOptions? = nil) async throws -> EmbeddingResult {
        try await embed(model: model, request: EmbeddingRequest(values: [value], dimensions: dimensions, providerOptions: providerOptions, extraBody: extraBody, headers: headers, abortSignal: abortSignal), retryPolicy: retryPolicy, telemetry: telemetry)
    }

    public static func embed(model: any EmbeddingModel, request: EmbeddingRequest, retryPolicy: AIRetryPolicy = .default, telemetry: AITelemetryOptions? = nil) async throws -> EmbeddingResult {
        try await withTelemetry(
            operationID: request.values.count == 1 ? "ai.embed" : "ai.embedMany",
            providerID: model.providerID,
            modelID: model.modelID,
            input: embeddingRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            abortSignal: request.abortSignal,
            output: embeddingTelemetryOutput,
            usage: { $0.usage },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata }
        ) {
            var result = try await model.embed(request)
            if result.requestMetadata == AIRequestMetadata() {
                result.requestMetadata = AIRequestMetadata(body: embeddingRequestMetadataBody(request), headers: request.headers)
            }
            return result
        }
    }

    public static func embedMany(
        model: any EmbeddingModel,
        values: [String],
        dimensions: Int? = nil,
        chunkSize: Int? = nil,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil
    ) async throws -> EmbeddingResult {
        guard let chunkSize, chunkSize > 0, values.count > chunkSize else {
            return try await embed(model: model, request: EmbeddingRequest(values: values, dimensions: dimensions, providerOptions: providerOptions, extraBody: extraBody, headers: headers, abortSignal: abortSignal), retryPolicy: retryPolicy, telemetry: telemetry)
        }

        let request = EmbeddingRequest(values: values, dimensions: dimensions, providerOptions: providerOptions, extraBody: extraBody, headers: headers, abortSignal: abortSignal)
        return try await withTelemetry(
            operationID: "ai.embedMany",
            providerID: model.providerID,
            modelID: model.modelID,
            input: embeddingRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            abortSignal: request.abortSignal,
            output: embeddingTelemetryOutput,
            usage: { $0.usage },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata }
        ) {
            var embeddings: [[Double]] = []
            var usage: TokenUsage?
            var rawValues: [JSONValue] = []
            var warnings: [AIWarning] = []
            var providerMetadata: [String: JSONValue] = [:]
            var requestMetadata = AIRequestMetadata(body: embeddingRequestMetadataBody(request), headers: request.headers)
            var responseMetadata = AIResponseMetadata()

            for chunk in values.chunked(size: chunkSize) {
                let result = try await withRetry(policy: retryPolicy) {
                    try await model.embed(EmbeddingRequest(values: chunk, dimensions: dimensions, providerOptions: providerOptions, extraBody: extraBody, headers: headers, abortSignal: abortSignal))
                }
                embeddings.append(contentsOf: result.embeddings)
                usage = sumTokenUsage(usage, result.usage)
                rawValues.append(result.rawValue)
                warnings.append(contentsOf: result.warnings)
                providerMetadata.merge(result.providerMetadata) { _, new in new }
                if requestMetadata.body == nil, result.requestMetadata.body != nil {
                    requestMetadata = result.requestMetadata
                }
                if responseMetadata == AIResponseMetadata() {
                    responseMetadata = result.responseMetadata
                }
            }

            return EmbeddingResult(
                embeddings: embeddings,
                usage: usage,
                rawValue: .array(rawValues),
                warnings: warnings,
                providerMetadata: providerMetadata,
                requestMetadata: requestMetadata,
                responseMetadata: responseMetadata
            )
        }
    }

    public static func generateImage(model: any ImageModel, request: ImageGenerationRequest, retryPolicy: AIRetryPolicy = .default, telemetry: AITelemetryOptions? = nil) async throws -> ImageGenerationResult {
        try await withTelemetry(
            operationID: "ai.generateImage",
            providerID: model.providerID,
            modelID: model.modelID,
            input: imageRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            abortSignal: request.abortSignal,
            output: imageTelemetryOutput,
            usage: { $0.usage },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata }
        ) {
            var result = try await model.generateImage(request)
            if result.requestMetadata == AIRequestMetadata() {
                result.requestMetadata = imageGenerationRequestMetadata(request)
            }
            return result
        }
    }

    public static func generateImage(model: any ImageModel, prompt: String, size: String? = nil, aspectRatio: String? = nil, seed: Int? = nil, count: Int? = nil, files: [ImageInputFile] = [], mask: ImageInputFile? = nil, providerOptions: [String: JSONValue] = [:], extraBody: [String: JSONValue] = [:], headers: [String: String] = [:], abortSignal: AIAbortSignal? = nil, retryPolicy: AIRetryPolicy = .default, telemetry: AITelemetryOptions? = nil) async throws -> ImageGenerationResult {
        try await generateImage(model: model, request: ImageGenerationRequest(prompt: prompt, size: size, aspectRatio: aspectRatio, seed: seed, count: count, files: files, mask: mask, providerOptions: providerOptions, extraBody: extraBody, headers: headers, abortSignal: abortSignal), retryPolicy: retryPolicy, telemetry: telemetry)
    }

    public static func transcribe(model: any TranscriptionModel, request: AudioTranscriptionRequest, retryPolicy: AIRetryPolicy = .default, telemetry: AITelemetryOptions? = nil) async throws -> TranscriptionResult {
        try await withTelemetry(
            operationID: "ai.transcribe",
            providerID: model.providerID,
            modelID: model.modelID,
            input: transcriptionRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            abortSignal: request.abortSignal,
            output: transcriptionTelemetryOutput,
            usage: { _ in nil },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata }
        ) {
            var result = try await model.transcribe(request)
            if result.requestMetadata == AIRequestMetadata() {
                result.requestMetadata = AIRequestMetadata(body: transcriptionRequestMetadataBody(request), headers: request.headers)
            }
            return result
        }
    }

    public static func generateSpeech(model: any SpeechModel, request: SpeechRequest, retryPolicy: AIRetryPolicy = .default, telemetry: AITelemetryOptions? = nil) async throws -> SpeechResult {
        try await withTelemetry(
            operationID: "ai.generateSpeech",
            providerID: model.providerID,
            modelID: model.modelID,
            input: speechRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            abortSignal: request.abortSignal,
            output: speechTelemetryOutput,
            usage: { _ in nil },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata }
        ) {
            var result = try await model.speak(request)
            if result.requestMetadata == AIRequestMetadata() {
                result.requestMetadata = AIRequestMetadata(body: speechRequestMetadataBody(request), headers: request.headers)
            }
            return result
        }
    }

    public static func generateVideo(model: any VideoModel, request: VideoGenerationRequest, retryPolicy: AIRetryPolicy = .default, telemetry: AITelemetryOptions? = nil) async throws -> VideoGenerationResult {
        try await withTelemetry(
            operationID: "ai.generateVideo",
            providerID: model.providerID,
            modelID: model.modelID,
            input: videoRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            abortSignal: request.abortSignal,
            output: videoTelemetryOutput,
            usage: { _ in nil },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata }
        ) {
            var result = try await model.generateVideo(request)
            if result.requestMetadata == AIRequestMetadata() {
                result.requestMetadata = videoGenerationRequestMetadata(request)
            }
            return result
        }
    }

    public static func rerank(model: any RerankingModel, request: RerankingRequest, retryPolicy: AIRetryPolicy = .default, telemetry: AITelemetryOptions? = nil) async throws -> RerankingResult {
        try await withTelemetry(
            operationID: "ai.rerank",
            providerID: model.providerID,
            modelID: model.modelID,
            input: rerankingRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            abortSignal: request.abortSignal,
            output: rerankingTelemetryOutput,
            usage: { _ in nil },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata }
        ) {
            var result = try await model.rerank(request)
            if result.requestMetadata == AIRequestMetadata() {
                result.requestMetadata = AIRequestMetadata(body: rerankingRequestMetadataBody(request), headers: request.headers)
            }
            return result
        }
    }

    public static func uploadFile(client: any AIFileClient, request: FileUploadRequest, retryPolicy: AIRetryPolicy = .default, telemetry: AITelemetryOptions? = nil) async throws -> FileUploadResult {
        try await withTelemetry(
            operationID: "ai.uploadFile",
            providerID: client.providerID,
            modelID: nil,
            input: fileUploadRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            abortSignal: request.abortSignal,
            output: fileUploadTelemetryOutput,
            usage: { _ in nil },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata }
        ) {
            var result = try await client.uploadFile(request)
            if result.requestMetadata == AIRequestMetadata() {
                result.requestMetadata = AIRequestMetadata(body: fileUploadRequestMetadataBody(request), headers: request.headers)
            }
            return result
        }
    }

    public static func uploadSkill(client: any AISkillsClient, request: SkillUploadRequest, retryPolicy: AIRetryPolicy = .default, telemetry: AITelemetryOptions? = nil) async throws -> SkillUploadResult {
        try await withTelemetry(
            operationID: "ai.uploadSkill",
            providerID: client.providerID,
            modelID: nil,
            input: skillUploadRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            abortSignal: request.abortSignal,
            output: skillUploadTelemetryOutput,
            usage: { _ in nil },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata }
        ) {
            var result = try await client.uploadSkill(request)
            if result.requestMetadata == AIRequestMetadata() {
                result.requestMetadata = AIRequestMetadata(body: skillUploadRequestMetadataBody(request), headers: request.headers)
            }
            return result
        }
    }
}
