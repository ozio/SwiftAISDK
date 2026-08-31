import Foundation

extension AI {
    public static func embed(model: any EmbeddingModel, value: String, dimensions: Int? = nil, providerOptions: [String: JSONValue] = [:], extraBody: [String: JSONValue] = [:], headers: [String: String] = [:], abortSignal: AIAbortSignal? = nil, retryPolicy: AIRetryPolicy = .default, telemetry: Telemetry.Options? = nil) async throws -> EmbeddingResult {
        try await embed(model: model, request: EmbeddingRequest(values: [value], dimensions: dimensions, providerOptions: providerOptions, extraBody: extraBody, headers: headers, abortSignal: abortSignal), retryPolicy: retryPolicy, telemetry: telemetry)
    }

    public static func embed(model: any EmbeddingModel, request: EmbeddingRequest, retryPolicy: AIRetryPolicy = .default, telemetry: Telemetry.Options? = nil) async throws -> EmbeddingResult {
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
        telemetry: Telemetry.Options? = nil
    ) async throws -> EmbeddingResult {
        let effectiveMaxEmbeddingsPerCall: Int?
        switch (chunkSize, model.maxEmbeddingsPerCall) {
        case let (requested?, providerMaximum?):
            effectiveMaxEmbeddingsPerCall = min(requested, providerMaximum)
        case let (requested?, nil):
            effectiveMaxEmbeddingsPerCall = requested
        case let (nil, providerMaximum?):
            effectiveMaxEmbeddingsPerCall = providerMaximum
        case (nil, nil):
            effectiveMaxEmbeddingsPerCall = nil
        }
        let chunks = try embeddingValueChunks(
            values,
            maxEmbeddingsPerCall: effectiveMaxEmbeddingsPerCall,
            maxInputBytesPerCall: model.maxInputBytesPerCall
        )
        let request = EmbeddingRequest(values: values, dimensions: dimensions, providerOptions: providerOptions, extraBody: extraBody, headers: headers, abortSignal: abortSignal)
        if chunks.isEmpty {
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
                EmbeddingResult(
                    embeddings: [],
                    usage: TokenUsage(inputTokens: 0, totalTokens: 0),
                    rawValue: .array([JSONValue]()),
                    requestMetadata: AIRequestMetadata(body: embeddingRequestMetadataBody(request), headers: headers)
                )
            }
        }
        guard chunks.count > 1 else {
            return try await embed(model: model, request: EmbeddingRequest(values: values, dimensions: dimensions, providerOptions: providerOptions, extraBody: extraBody, headers: headers, abortSignal: abortSignal), retryPolicy: retryPolicy, telemetry: telemetry)
        }

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

            for chunk in chunks {
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

    public static func generateImage(model: any ImageModel, request: ImageGenerationRequest, retryPolicy: AIRetryPolicy = .default, telemetry: Telemetry.Options? = nil) async throws -> ImageGenerationResult {
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
            if result.calls.isEmpty {
                result.calls = [ImageGenerationCall(
                    urls: result.urls,
                    base64Images: result.base64Images,
                    warnings: result.warnings,
                    usage: result.usage,
                    providerMetadata: result.providerMetadata,
                    responseMetadata: result.responseMetadata
                )]
            }
            guard !result.urls.isEmpty || !result.base64Images.isEmpty else {
                throw AINoOutputError(kind: .image, responses: [result.responseMetadata])
            }
            return result
        }
    }

    public static func generateImage(model: any ImageModel, prompt: String, size: String? = nil, aspectRatio: String? = nil, seed: Int? = nil, count: Int? = nil, files: [ImageInputFile] = [], mask: ImageInputFile? = nil, providerOptions: [String: JSONValue] = [:], extraBody: [String: JSONValue] = [:], headers: [String: String] = [:], abortSignal: AIAbortSignal? = nil, retryPolicy: AIRetryPolicy = .default, telemetry: Telemetry.Options? = nil) async throws -> ImageGenerationResult {
        try await generateImage(model: model, request: ImageGenerationRequest(prompt: prompt, size: size, aspectRatio: aspectRatio, seed: seed, count: count, files: files, mask: mask, providerOptions: providerOptions, extraBody: extraBody, headers: headers, abortSignal: abortSignal), retryPolicy: retryPolicy, telemetry: telemetry)
    }

    public static func transcribe(model: any TranscriptionModel, request: AudioTranscriptionRequest, retryPolicy: AIRetryPolicy = .default, telemetry: Telemetry.Options? = nil) async throws -> TranscriptionResult {
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
            guard !result.text.isEmpty else {
                throw AINoOutputError(kind: .transcript, responses: [result.responseMetadata])
            }
            return result
        }
    }

    public static func generateSpeech(model: any SpeechModel, request: SpeechRequest, retryPolicy: AIRetryPolicy = .default, telemetry: Telemetry.Options? = nil) async throws -> SpeechResult {
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
            guard !result.audio.isEmpty else {
                throw AINoOutputError(kind: .speech, responses: [result.responseMetadata])
            }
            return result
        }
    }

    public static func generateAudio(model: any AudioGenerationModel, request: AudioGenerationRequest, retryPolicy: AIRetryPolicy = .default, telemetry: Telemetry.Options? = nil) async throws -> AudioGenerationResult {
        try await withTelemetry(
            operationID: "ai.generateAudio",
            providerID: model.providerID,
            modelID: model.modelID,
            input: audioGenerationRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            abortSignal: request.abortSignal,
            output: audioGenerationTelemetryOutput,
            usage: { _ in nil },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata }
        ) {
            var result = try await model.generateAudio(request)
            if result.requestMetadata == AIRequestMetadata() {
                result.requestMetadata = AIRequestMetadata(body: audioGenerationRequestMetadataBody(request), headers: request.headers)
            }
            guard !result.audio.isEmpty else {
                throw AINoOutputError(kind: .audio, responses: [result.responseMetadata])
            }
            return result
        }
    }

    public static func transformAudio(model: any AudioTransformationModel, request: AudioTransformationRequest, retryPolicy: AIRetryPolicy = .default, telemetry: Telemetry.Options? = nil) async throws -> AudioTransformationResult {
        try await withTelemetry(
            operationID: "ai.transformAudio",
            providerID: model.providerID,
            modelID: model.modelID,
            input: audioTransformationRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            abortSignal: request.abortSignal,
            output: audioTransformationTelemetryOutput,
            usage: { _ in nil },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata }
        ) {
            var result = try await model.transformAudio(request)
            if result.requestMetadata == AIRequestMetadata() {
                result.requestMetadata = AIRequestMetadata(body: audioTransformationRequestMetadataBody(request), headers: request.headers)
            }
            guard !result.audio.isEmpty else {
                throw AINoOutputError(kind: .audio, responses: [result.responseMetadata])
            }
            return result
        }
    }

    public static func generateVideo(
        model: any VideoModel,
        request: VideoGenerationRequest,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: Telemetry.Options? = nil,
        poll: VideoGenerationPollOptions? = nil,
        webhook: VideoGenerationWebhookFactory? = nil
    ) async throws -> VideoGenerationResult {
        let normalized = normalizeVideoGenerationRequest(request)
        let operationOptionsRequested = poll != nil || webhook != nil
        let availableOperationModel = model as? any AsyncVideoModel
        let operationModel = availableOperationModel.flatMap { candidate in
            operationOptionsRequested || !model.supportsUnaryVideoGeneration ? candidate : nil
        }
        if !model.supportsUnaryVideoGeneration, availableOperationModel == nil {
            throw AIError.invalidArgument(
                argument: "model",
                message: "Video model \(model.modelID) does not implement unary generation or start/status operations."
            )
        }
        return try await withTelemetry(
            operationID: "ai.generateVideo",
            providerID: model.providerID,
            modelID: model.modelID,
            input: videoRequestTelemetryInput(normalized.request),
            telemetry: telemetry,
            // Start/status calls own their retry boundaries. Retrying this outer
            // closure after a successful billable start could create a second job.
            retryPolicy: operationModel == nil ? retryPolicy : .none,
            abortSignal: normalized.request.abortSignal,
            output: videoTelemetryOutput,
            usage: { _ in nil },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata },
            logEmptyWarnings: false
        ) {
            var result: VideoGenerationResult
            if let operationModel {
                result = try await generateVideoUsingOperations(
                    model: operationModel,
                    request: normalized.request,
                    poll: poll,
                    webhook: webhook,
                    retryPolicy: retryPolicy
                )
            } else {
                result = try await model.generateVideo(normalized.request)
                if operationOptionsRequested {
                    result.warnings.insert(AIWarning(
                        type: "other",
                        message: "poll/webhook options were provided but the model does not support start/status operations. Falling back to unary generateVideo."
                    ), at: 0)
                }
            }
            result.warnings = normalized.warnings + result.warnings
            if result.requestMetadata == AIRequestMetadata() {
                result.requestMetadata = videoGenerationRequestMetadata(normalized.request)
            }
            guard !result.urls.isEmpty || !result.base64Videos.isEmpty else {
                throw AINoOutputError(kind: .video, responses: [result.responseMetadata])
            }
            return result
        }
    }

    public static func rerank(model: any RerankingModel, request: RerankingRequest, retryPolicy: AIRetryPolicy = .default, telemetry: Telemetry.Options? = nil) async throws -> RerankingResult {
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

    public static func uploadFile(client: any AIFileClient, request: FileUploadRequest, retryPolicy: AIRetryPolicy = .default, telemetry: Telemetry.Options? = nil) async throws -> FileUploadResult {
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

    public static func uploadSkill(client: any AISkillsClient, request: SkillUploadRequest, retryPolicy: AIRetryPolicy = .default, telemetry: Telemetry.Options? = nil) async throws -> SkillUploadResult {
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

private func embeddingValueChunks(
    _ values: [String],
    maxEmbeddingsPerCall: Int?,
    maxInputBytesPerCall: Int?
) throws -> [[String]] {
    if let maxEmbeddingsPerCall, maxEmbeddingsPerCall <= 0 {
        throw AIError.invalidArgument(
            argument: "maxEmbeddingsPerCall",
            message: "maxEmbeddingsPerCall must be greater than zero."
        )
    }
    if let maxInputBytesPerCall, maxInputBytesPerCall <= 0 {
        throw AIError.invalidArgument(
            argument: "maxInputBytesPerCall",
            message: "maxInputBytesPerCall must be greater than zero."
        )
    }
    guard !values.isEmpty else { return [] }
    guard maxEmbeddingsPerCall != nil || maxInputBytesPerCall != nil else { return [values] }

    var chunks: [[String]] = []
    var current: [String] = []
    var currentInputBytes = 0

    for value in values {
        let inputBytes = value.utf8.count
        let exceedsCount = maxEmbeddingsPerCall.map { current.count >= $0 } ?? false
        let exceedsBytes = maxInputBytesPerCall.map { currentInputBytes + inputBytes > $0 } ?? false
        if !current.isEmpty, exceedsCount || exceedsBytes {
            chunks.append(current)
            current = []
            currentInputBytes = 0
        }
        current.append(value)
        currentInputBytes += inputBytes
    }

    chunks.append(current)
    return chunks
}

func normalizeVideoGenerationRequest(_ request: VideoGenerationRequest) -> (request: VideoGenerationRequest, warnings: [AIWarning]) {
    var normalized = request
    var warnings: [AIWarning] = []

    if !normalized.frameImages.isEmpty, !normalized.inputReferences.isEmpty {
        normalized.inputReferences = []
        warnings.append(AIWarning(
            type: "other",
            message: "inputReferences were ignored because frameImages were provided; frameImages and inputReferences cannot be combined."
        ))
    }

    if let firstFrame = normalized.frameImages.first(where: { $0.frameType == .firstFrame }) {
        if normalized.image != nil, normalized.image != firstFrame.image {
            warnings.append(AIWarning(
                type: "other",
                message: "prompt.image was ignored because a first_frame frameImage was provided; the first_frame frameImage takes precedence as the start image."
            ))
        }
        normalized.image = firstFrame.image
    }

    return (normalized, warnings)
}
