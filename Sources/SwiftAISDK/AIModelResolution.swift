import Foundation

public extension AI {
    static func resolveLanguageModel(_ modelID: String, provider: (any AIProvider)? = nil) throws -> any LanguageModel {
        try (provider ?? AIDefaultProvider.resolved()).languageModel(modelID)
    }

    static func resolveEmbeddingModel(_ modelID: String, provider: (any AIProvider)? = nil) throws -> any EmbeddingModel {
        try (provider ?? AIDefaultProvider.resolved()).embeddingModel(modelID)
    }

    static func resolveImageModel(_ modelID: String, provider: (any AIProvider)? = nil) throws -> any ImageModel {
        try (provider ?? AIDefaultProvider.resolved()).imageModel(modelID)
    }

    static func resolveTranscriptionModel(_ modelID: String, provider: (any AIProvider)? = nil) throws -> any TranscriptionModel {
        try (provider ?? AIDefaultProvider.resolved()).transcriptionModel(modelID)
    }

    static func resolveSpeechModel(_ modelID: String, provider: (any AIProvider)? = nil) throws -> any SpeechModel {
        try (provider ?? AIDefaultProvider.resolved()).speechModel(modelID)
    }

    static func resolveVideoModel(_ modelID: String, provider: (any AIProvider)? = nil) throws -> any VideoModel {
        try (provider ?? AIDefaultProvider.resolved()).videoModel(modelID)
    }

    static func resolveRerankingModel(_ modelID: String, provider: (any AIProvider)? = nil) throws -> any RerankingModel {
        try (provider ?? AIDefaultProvider.resolved()).rerankingModel(modelID)
    }

    static func generateText(
        model modelID: String,
        provider: (any AIProvider)? = nil,
        request: LanguageModelRequest,
        retryPolicy: AIRetryPolicy = .default
    ) async throws -> TextGenerationResult {
        try await generateText(
            model: resolveLanguageModel(modelID, provider: provider),
            request: request,
            retryPolicy: retryPolicy
        )
    }

    static func generateText(
        model modelID: String,
        provider: (any AIProvider)? = nil,
        request: LanguageModelRequest,
        executableTools: [AITool],
        maxSteps: Int = 5,
        stopWhen: [AIStopCondition] = [],
        prepareStep: AIPrepareStep? = nil,
        toolApproval: AIToolApproval? = nil,
        retryPolicy: AIRetryPolicy = .default
    ) async throws -> TextGenerationResult {
        try await generateText(
            model: resolveLanguageModel(modelID, provider: provider),
            request: request,
            executableTools: executableTools,
            maxSteps: maxSteps,
            stopWhen: stopWhen,
            prepareStep: prepareStep,
            toolApproval: toolApproval,
            retryPolicy: retryPolicy
        )
    }

    static func generateText(
        model modelID: String,
        provider: (any AIProvider)? = nil,
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
        executableTools: [AITool] = [],
        maxSteps: Int = 5,
        stopWhen: [AIStopCondition] = [],
        prepareStep: AIPrepareStep? = nil,
        toolApproval: AIToolApproval? = nil,
        retryPolicy: AIRetryPolicy = .default,
        toolChoice: JSONValue? = nil,
        includeRawChunks: Bool = false,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:]
    ) async throws -> TextGenerationResult {
        try await generateText(
            model: resolveLanguageModel(modelID, provider: provider),
            prompt: prompt,
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
            executableTools: executableTools,
            maxSteps: maxSteps,
            stopWhen: stopWhen,
            prepareStep: prepareStep,
            toolApproval: toolApproval,
            retryPolicy: retryPolicy,
            toolChoice: toolChoice,
            includeRawChunks: includeRawChunks,
            providerOptions: providerOptions,
            extraBody: extraBody,
            headers: headers
        )
    }

    static func streamText(
        model modelID: String,
        provider: (any AIProvider)? = nil,
        request: LanguageModelRequest,
        timeoutNanoseconds: UInt64? = nil
    ) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        do {
            return streamText(
                model: try resolveLanguageModel(modelID, provider: provider),
                request: request,
                timeoutNanoseconds: timeoutNanoseconds
            )
        } catch {
            return failingStream(error)
        }
    }

    static func streamText(
        model modelID: String,
        provider: (any AIProvider)? = nil,
        request: LanguageModelRequest,
        executableTools: [AITool],
        maxSteps: Int = 5,
        stopWhen: [AIStopCondition] = [],
        prepareStep: AIPrepareStep? = nil,
        toolApproval: AIToolApproval? = nil,
        timeoutNanoseconds: UInt64? = nil
    ) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        do {
            return streamText(
                model: try resolveLanguageModel(modelID, provider: provider),
                request: request,
                executableTools: executableTools,
                maxSteps: maxSteps,
                stopWhen: stopWhen,
                prepareStep: prepareStep,
                toolApproval: toolApproval,
                timeoutNanoseconds: timeoutNanoseconds
            )
        } catch {
            return failingStream(error)
        }
    }

    static func streamText(
        model modelID: String,
        provider: (any AIProvider)? = nil,
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
        executableTools: [AITool] = [],
        maxSteps: Int = 5,
        stopWhen: [AIStopCondition] = [],
        prepareStep: AIPrepareStep? = nil,
        toolApproval: AIToolApproval? = nil,
        toolChoice: JSONValue? = nil,
        includeRawChunks: Bool = false,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        timeoutNanoseconds: UInt64? = nil
    ) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        do {
            return streamText(
                model: try resolveLanguageModel(modelID, provider: provider),
                prompt: prompt,
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
                executableTools: executableTools,
                maxSteps: maxSteps,
                stopWhen: stopWhen,
                prepareStep: prepareStep,
                toolApproval: toolApproval,
                toolChoice: toolChoice,
                includeRawChunks: includeRawChunks,
                providerOptions: providerOptions,
                extraBody: extraBody,
                headers: headers,
                timeoutNanoseconds: timeoutNanoseconds
            )
        } catch {
            return failingStream(error)
        }
    }

    static func generateObject<Object: Decodable & Sendable>(
        model modelID: String,
        provider: (any AIProvider)? = nil,
        request: LanguageModelRequest,
        as type: Object.Type = Object.self,
        schema: JSONValue? = nil,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        retryPolicy: AIRetryPolicy = .default,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) async throws -> ObjectGenerationResult<Object> {
        try await generateObject(
            model: resolveLanguageModel(modelID, provider: provider),
            request: request,
            as: type,
            schema: schema,
            schemaName: schemaName,
            schemaDescription: schemaDescription,
            retryPolicy: retryPolicy,
            repairText: repairText
        )
    }

    static func generateObjectArray<Element: Decodable & Sendable>(
        model modelID: String,
        provider: (any AIProvider)? = nil,
        request: LanguageModelRequest,
        as type: Element.Type = Element.self,
        elementSchema: JSONValue,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        retryPolicy: AIRetryPolicy = .default,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) async throws -> ObjectGenerationResult<[Element]> {
        try await generateObjectArray(
            model: resolveLanguageModel(modelID, provider: provider),
            request: request,
            as: type,
            elementSchema: elementSchema,
            schemaName: schemaName,
            schemaDescription: schemaDescription,
            retryPolicy: retryPolicy,
            repairText: repairText
        )
    }

    static func generateEnum(
        model modelID: String,
        provider: (any AIProvider)? = nil,
        request: LanguageModelRequest,
        values: [String],
        retryPolicy: AIRetryPolicy = .default,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) async throws -> ObjectGenerationResult<String> {
        try await generateEnum(
            model: resolveLanguageModel(modelID, provider: provider),
            request: request,
            values: values,
            retryPolicy: retryPolicy,
            repairText: repairText
        )
    }

    static func generateJSON(
        model modelID: String,
        provider: (any AIProvider)? = nil,
        request: LanguageModelRequest,
        retryPolicy: AIRetryPolicy = .default,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) async throws -> ObjectGenerationResult<JSONValue> {
        try await generateJSON(
            model: resolveLanguageModel(modelID, provider: provider),
            request: request,
            retryPolicy: retryPolicy,
            repairText: repairText
        )
    }

    static func streamObject<Object: Decodable & Sendable>(
        model modelID: String,
        provider: (any AIProvider)? = nil,
        request: LanguageModelRequest,
        as type: Object.Type = Object.self,
        schema: JSONValue? = nil,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        timeoutNanoseconds: UInt64? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) -> AsyncThrowingStream<ObjectStreamPart<Object>, Error> {
        do {
            return streamObject(
                model: try resolveLanguageModel(modelID, provider: provider),
                request: request,
                as: type,
                schema: schema,
                schemaName: schemaName,
                schemaDescription: schemaDescription,
                timeoutNanoseconds: timeoutNanoseconds,
                repairText: repairText
            )
        } catch {
            return failingObjectStream(error)
        }
    }

    static func embed(
        model modelID: String,
        provider: (any AIProvider)? = nil,
        value: String,
        dimensions: Int? = nil,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        retryPolicy: AIRetryPolicy = .default
    ) async throws -> EmbeddingResult {
        try await embed(
            model: resolveEmbeddingModel(modelID, provider: provider),
            value: value,
            dimensions: dimensions,
            providerOptions: providerOptions,
            extraBody: extraBody,
            headers: headers,
            retryPolicy: retryPolicy
        )
    }

    static func embed(
        model modelID: String,
        provider: (any AIProvider)? = nil,
        request: EmbeddingRequest,
        retryPolicy: AIRetryPolicy = .default
    ) async throws -> EmbeddingResult {
        try await embed(model: resolveEmbeddingModel(modelID, provider: provider), request: request, retryPolicy: retryPolicy)
    }

    static func embedMany(
        model modelID: String,
        provider: (any AIProvider)? = nil,
        values: [String],
        dimensions: Int? = nil,
        chunkSize: Int? = nil,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        retryPolicy: AIRetryPolicy = .default
    ) async throws -> EmbeddingResult {
        try await embedMany(
            model: resolveEmbeddingModel(modelID, provider: provider),
            values: values,
            dimensions: dimensions,
            chunkSize: chunkSize,
            providerOptions: providerOptions,
            extraBody: extraBody,
            headers: headers,
            retryPolicy: retryPolicy
        )
    }

    static func generateImage(
        model modelID: String,
        provider: (any AIProvider)? = nil,
        request: ImageGenerationRequest,
        retryPolicy: AIRetryPolicy = .default
    ) async throws -> ImageGenerationResult {
        try await generateImage(model: resolveImageModel(modelID, provider: provider), request: request, retryPolicy: retryPolicy)
    }

    static func generateImage(
        model modelID: String,
        provider: (any AIProvider)? = nil,
        prompt: String,
        size: String? = nil,
        aspectRatio: String? = nil,
        seed: Int? = nil,
        count: Int? = nil,
        files: [ImageInputFile] = [],
        mask: ImageInputFile? = nil,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        retryPolicy: AIRetryPolicy = .default
    ) async throws -> ImageGenerationResult {
        try await generateImage(
            model: resolveImageModel(modelID, provider: provider),
            prompt: prompt,
            size: size,
            aspectRatio: aspectRatio,
            seed: seed,
            count: count,
            files: files,
            mask: mask,
            providerOptions: providerOptions,
            extraBody: extraBody,
            headers: headers,
            retryPolicy: retryPolicy
        )
    }

    static func transcribe(
        model modelID: String,
        provider: (any AIProvider)? = nil,
        request: AudioTranscriptionRequest,
        retryPolicy: AIRetryPolicy = .default
    ) async throws -> TranscriptionResult {
        try await transcribe(model: resolveTranscriptionModel(modelID, provider: provider), request: request, retryPolicy: retryPolicy)
    }

    static func generateSpeech(
        model modelID: String,
        provider: (any AIProvider)? = nil,
        request: SpeechRequest,
        retryPolicy: AIRetryPolicy = .default
    ) async throws -> SpeechResult {
        try await generateSpeech(model: resolveSpeechModel(modelID, provider: provider), request: request, retryPolicy: retryPolicy)
    }

    static func generateVideo(
        model modelID: String,
        provider: (any AIProvider)? = nil,
        request: VideoGenerationRequest,
        retryPolicy: AIRetryPolicy = .default
    ) async throws -> VideoGenerationResult {
        try await generateVideo(model: resolveVideoModel(modelID, provider: provider), request: request, retryPolicy: retryPolicy)
    }

    static func rerank(
        model modelID: String,
        provider: (any AIProvider)? = nil,
        request: RerankingRequest,
        retryPolicy: AIRetryPolicy = .default
    ) async throws -> RerankingResult {
        try await rerank(model: resolveRerankingModel(modelID, provider: provider), request: request, retryPolicy: retryPolicy)
    }
}

private func failingStream(_ error: Error) -> AsyncThrowingStream<LanguageStreamPart, Error> {
    AsyncThrowingStream { continuation in
        continuation.finish(throwing: error)
    }
}

private func failingObjectStream<Object: Sendable>(_ error: Error) -> AsyncThrowingStream<ObjectStreamPart<Object>, Error> {
    AsyncThrowingStream { continuation in
        continuation.finish(throwing: error)
    }
}
