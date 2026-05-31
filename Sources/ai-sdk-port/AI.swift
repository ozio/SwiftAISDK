import Foundation

public enum AI {
    public static func generateText(model: any LanguageModel, request: LanguageModelRequest) async throws -> TextGenerationResult {
        try await model.generate(request)
    }

    public static func generateText(
        model: any LanguageModel,
        request: LanguageModelRequest,
        executableTools: [AITool],
        maxSteps: Int = 5
    ) async throws -> TextGenerationResult {
        guard !executableTools.isEmpty else {
            return try await model.generate(request)
        }
        guard maxSteps > 0 else {
            throw AIError.invalidArgument(argument: "maxSteps", message: "maxSteps must be greater than zero.")
        }

        let toolsByName = try toolsByName(from: executableTools)
        var currentRequest = request
        currentRequest.tools.merge(toolsDictionary(from: executableTools)) { _, typed in typed }

        var steps: [AIToolStep] = []
        var allToolResults: [AIToolResult] = []
        var lastResult: TextGenerationResult?

        for index in 0..<maxSteps {
            var result = try await model.generate(currentRequest)
            let executableCalls = result.toolCalls.filter { !$0.providerExecuted && toolsByName[$0.name] != nil }

            if executableCalls.isEmpty {
                result.toolResults = allToolResults
                result.steps = steps + [
                    AIToolStep(
                        index: index,
                        text: result.text,
                        reasoning: result.reasoning,
                        finishReason: result.finishReason,
                        usage: result.usage,
                        toolCalls: result.toolCalls,
                        providerMetadata: result.providerMetadata,
                        responseMetadata: result.responseMetadata
                    )
                ]
                return result
            }

            let toolResults = try await executeToolCalls(executableCalls, toolsByName: toolsByName)
            allToolResults.append(contentsOf: toolResults)
            steps.append(
                AIToolStep(
                    index: index,
                    text: result.text,
                    reasoning: result.reasoning,
                    finishReason: result.finishReason,
                    usage: result.usage,
                    toolCalls: result.toolCalls,
                    toolResults: toolResults,
                    providerMetadata: result.providerMetadata,
                    responseMetadata: result.responseMetadata
                )
            )

            result.toolResults = allToolResults
            result.steps = steps
            lastResult = result
            currentRequest.messages.append(.assistant(text: result.text, toolCalls: result.toolCalls))
            currentRequest.messages.append(contentsOf: toolResults.map(AIMessage.toolResult))
        }

        guard var result = lastResult else {
            return try await model.generate(currentRequest)
        }
        result.toolResults = allToolResults
        result.steps = steps
        return result
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
        executableTools: [AITool] = [],
        maxSteps: Int = 5,
        toolChoice: JSONValue? = nil,
        includeRawChunks: Bool = false,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:]
    ) async throws -> TextGenerationResult {
        let request = LanguageModelRequest(
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

        if executableTools.isEmpty {
            return try await generateText(model: model, request: request)
        }

        return try await generateText(
            model: model,
            request: request,
            executableTools: executableTools,
            maxSteps: maxSteps
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

private func toolsDictionary(from tools: [AITool]) -> [String: JSONValue] {
    Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0.schema) })
}

private func toolsByName(from tools: [AITool]) throws -> [String: AITool] {
    var output: [String: AITool] = [:]
    for tool in tools {
        guard output[tool.name] == nil else {
            throw AIError.invalidArgument(argument: "executableTools", message: "Duplicate tool name '\(tool.name)'.")
        }
        output[tool.name] = tool
    }
    return output
}

private func executeToolCalls(_ calls: [AIToolCall], toolsByName: [String: AITool]) async throws -> [AIToolResult] {
    var results: [AIToolResult] = []
    for call in calls {
        guard let tool = toolsByName[call.name] else { continue }
        let arguments = try toolArguments(from: call)
        let result = try await tool.execute(arguments)
        results.append(AIToolResult(
            toolCallID: call.id,
            toolName: call.name,
            result: result,
            dynamic: call.dynamic,
            providerMetadata: call.providerMetadata
        ))
    }
    return results
}

private func toolArguments(from call: AIToolCall) throws -> JSONValue {
    let trimmed = call.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .object([:]) }
    do {
        return try decodeJSONBody(Data(trimmed.utf8))
    } catch {
        throw AIError.invalidArgument(argument: "toolCalls.\(call.name).arguments", message: "Tool call arguments must be valid JSON.")
    }
}

private extension Array {
    func chunked(size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}
