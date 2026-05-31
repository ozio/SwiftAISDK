import Foundation

public enum AI {
    public static func generateText(model: any LanguageModel, request: LanguageModelRequest) async throws -> TextGenerationResult {
        try await model.generate(request)
    }

    public static func generateText(
        model: any LanguageModel,
        prompt: String,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        seed: Int? = nil,
        maxOutputTokens: Int? = nil,
        stopSequences: [String] = [],
        responseFormat: AIResponseFormat? = nil,
        reasoning: String? = nil,
        tools: [String: JSONValue] = [:],
        toolChoice: JSONValue? = nil,
        includeRawChunks: Bool = false,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:]
    ) async throws -> TextGenerationResult {
        try await generateText(
            model: model,
            request: LanguageModelRequest(
                messages: [.user(prompt)],
                temperature: temperature,
                topP: topP,
                topK: topK,
                presencePenalty: presencePenalty,
                frequencyPenalty: frequencyPenalty,
                seed: seed,
                maxOutputTokens: maxOutputTokens,
                stopSequences: stopSequences,
                responseFormat: responseFormat,
                reasoning: reasoning,
                tools: tools,
                toolChoice: toolChoice,
                includeRawChunks: includeRawChunks,
                providerOptions: providerOptions,
                extraBody: extraBody,
                headers: headers
            )
        )
    }

    public static func streamText(model: any LanguageModel, request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        model.stream(request)
    }

    public static func streamText(
        model: any LanguageModel,
        prompt: String,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        seed: Int? = nil,
        maxOutputTokens: Int? = nil,
        stopSequences: [String] = [],
        responseFormat: AIResponseFormat? = nil,
        reasoning: String? = nil,
        tools: [String: JSONValue] = [:],
        toolChoice: JSONValue? = nil,
        includeRawChunks: Bool = false,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:]
    ) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamText(
            model: model,
            request: LanguageModelRequest(
                messages: [.user(prompt)],
                temperature: temperature,
                topP: topP,
                topK: topK,
                presencePenalty: presencePenalty,
                frequencyPenalty: frequencyPenalty,
                seed: seed,
                maxOutputTokens: maxOutputTokens,
                stopSequences: stopSequences,
                responseFormat: responseFormat,
                reasoning: reasoning,
                tools: tools,
                toolChoice: toolChoice,
                includeRawChunks: includeRawChunks,
                providerOptions: providerOptions,
                extraBody: extraBody,
                headers: headers
            )
        )
    }

    public static func embed(model: any EmbeddingModel, value: String, dimensions: Int? = nil, providerOptions: [String: JSONValue] = [:], extraBody: [String: JSONValue] = [:], headers: [String: String] = [:]) async throws -> EmbeddingResult {
        try await model.embed(EmbeddingRequest(values: [value], dimensions: dimensions, providerOptions: providerOptions, extraBody: extraBody, headers: headers))
    }

    public static func embed(model: any EmbeddingModel, request: EmbeddingRequest) async throws -> EmbeddingResult {
        try await model.embed(request)
    }

    public static func embedMany(
        model: any EmbeddingModel,
        values: [String],
        dimensions: Int? = nil,
        chunkSize: Int? = nil,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:]
    ) async throws -> EmbeddingResult {
        guard let chunkSize, chunkSize > 0, values.count > chunkSize else {
            return try await model.embed(EmbeddingRequest(values: values, dimensions: dimensions, providerOptions: providerOptions, extraBody: extraBody, headers: headers))
        }

        var embeddings: [[Double]] = []
        var usage: TokenUsage?
        var rawValues: [JSONValue] = []
        var warnings: [AIWarning] = []
        var providerMetadata: [String: JSONValue] = [:]
        var responseMetadata = AIResponseMetadata()

        for chunk in values.chunked(size: chunkSize) {
            let result = try await model.embed(EmbeddingRequest(values: chunk, dimensions: dimensions, providerOptions: providerOptions, extraBody: extraBody, headers: headers))
            embeddings.append(contentsOf: result.embeddings)
            usage = sumTokenUsage(usage, result.usage)
            rawValues.append(result.rawValue)
            warnings.append(contentsOf: result.warnings)
            providerMetadata.merge(result.providerMetadata) { _, new in new }
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
            responseMetadata: responseMetadata
        )
    }

    public static func generateImage(model: any ImageModel, request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        try await model.generateImage(request)
    }

    public static func generateImage(model: any ImageModel, prompt: String, size: String? = nil, aspectRatio: String? = nil, seed: Int? = nil, count: Int? = nil, files: [ImageInputFile] = [], mask: ImageInputFile? = nil, providerOptions: [String: JSONValue] = [:], extraBody: [String: JSONValue] = [:], headers: [String: String] = [:]) async throws -> ImageGenerationResult {
        try await generateImage(model: model, request: ImageGenerationRequest(prompt: prompt, size: size, aspectRatio: aspectRatio, seed: seed, count: count, files: files, mask: mask, providerOptions: providerOptions, extraBody: extraBody, headers: headers))
    }

    public static func transcribe(model: any TranscriptionModel, request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        try await model.transcribe(request)
    }

    public static func generateSpeech(model: any SpeechModel, request: SpeechRequest) async throws -> SpeechResult {
        try await model.speak(request)
    }

    public static func generateVideo(model: any VideoModel, request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        try await model.generateVideo(request)
    }

    public static func rerank(model: any RerankingModel, request: RerankingRequest) async throws -> RerankingResult {
        try await model.rerank(request)
    }

    public static func uploadFile(client: any AIFileClient, request: FileUploadRequest) async throws -> FileUploadResult {
        try await client.uploadFile(request)
    }

    public static func uploadSkill(client: any AISkillsClient, request: SkillUploadRequest) async throws -> SkillUploadResult {
        try await client.uploadSkill(request)
    }
}

private func sumTokenUsage(_ lhs: TokenUsage?, _ rhs: TokenUsage?) -> TokenUsage? {
    guard lhs != nil || rhs != nil else { return nil }
    return TokenUsage(
        inputTokens: optionalSum(lhs?.inputTokens, rhs?.inputTokens),
        outputTokens: optionalSum(lhs?.outputTokens, rhs?.outputTokens),
        totalTokens: optionalSum(lhs?.totalTokens, rhs?.totalTokens)
    )
}

private func optionalSum(_ lhs: Int?, _ rhs: Int?) -> Int? {
    switch (lhs, rhs) {
    case let (lhs?, rhs?):
        return lhs + rhs
    case let (lhs?, nil):
        return lhs
    case let (nil, rhs?):
        return rhs
    case (nil, nil):
        return nil
    }
}

private extension Array {
    func chunked(size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}
