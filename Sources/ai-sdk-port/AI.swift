import Foundation

public enum AI {
    public static func generateText(
        model: any LanguageModel,
        request: LanguageModelRequest,
        retryPolicy: AIRetryPolicy = .default
    ) async throws -> TextGenerationResult {
        try await withRetry(policy: retryPolicy) {
            try await model.generate(request)
        }
    }

    public static func generateText(
        model: any LanguageModel,
        request: LanguageModelRequest,
        executableTools: [AITool],
        maxSteps: Int = 5,
        retryPolicy: AIRetryPolicy = .default
    ) async throws -> TextGenerationResult {
        guard !executableTools.isEmpty else {
            return try await generateText(model: model, request: request, retryPolicy: retryPolicy)
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
            var result = try await generateText(model: model, request: currentRequest, retryPolicy: retryPolicy)
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
            return try await generateText(model: model, request: currentRequest, retryPolicy: retryPolicy)
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
        retryPolicy: AIRetryPolicy = .default,
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
            return try await generateText(model: model, request: request, retryPolicy: retryPolicy)
        }

        return try await generateText(
            model: model,
            request: request,
            executableTools: executableTools,
            maxSteps: maxSteps,
            retryPolicy: retryPolicy
        )
    }

    public static func generateObject<Object: Decodable & Sendable>(
        model: any LanguageModel,
        request: LanguageModelRequest,
        as type: Object.Type = Object.self,
        schema: JSONValue? = nil,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        retryPolicy: AIRetryPolicy = .default,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) async throws -> ObjectGenerationResult<Object> {
        var objectRequest = request
        let responseFormat = AIResponseFormat.json(schema: schema, name: schemaName, description: schemaDescription)
        objectRequest.responseFormat = objectRequest.responseFormat ?? responseFormat
        if objectRequest.extraBody["responseFormat"] == nil {
            objectRequest.extraBody["responseFormat"] = responseFormatJSON(schema: schema, name: schemaName, description: schemaDescription)
        }

        let textResult = try await generateText(model: model, request: objectRequest, retryPolicy: retryPolicy)
        let parsed = try await parseObject(
            Object.self,
            from: textResult.text,
            repairText: repairText,
            providerID: model.providerID
        )

        return ObjectGenerationResult(
            object: parsed.object,
            text: parsed.text,
            rawObject: parsed.rawObject,
            reasoning: textResult.reasoning,
            finishReason: textResult.finishReason,
            usage: textResult.usage,
            warnings: textResult.warnings,
            providerMetadata: textResult.providerMetadata,
            responseMetadata: textResult.responseMetadata,
            textResult: textResult
        )
    }

    public static func generateObject<Object: Decodable & Sendable>(
        model: any LanguageModel,
        prompt: String,
        as type: Object.Type = Object.self,
        schema: JSONValue? = nil,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        seed: Int? = nil,
        maxOutputTokens: Int? = nil,
        stopSequences: [String] = [],
        reasoning: String? = nil,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        retryPolicy: AIRetryPolicy = .default,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) async throws -> ObjectGenerationResult<Object> {
        try await generateObject(
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
                responseFormat: .json(schema: schema, name: schemaName, description: schemaDescription),
                reasoning: reasoning,
                providerOptions: providerOptions,
                extraBody: extraBody,
                headers: headers
            ),
            as: Object.self,
            schema: schema,
            schemaName: schemaName,
            schemaDescription: schemaDescription,
            retryPolicy: retryPolicy,
            repairText: repairText
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

    public static func embed(model: any EmbeddingModel, value: String, dimensions: Int? = nil, providerOptions: [String: JSONValue] = [:], extraBody: [String: JSONValue] = [:], headers: [String: String] = [:], retryPolicy: AIRetryPolicy = .default) async throws -> EmbeddingResult {
        try await embed(model: model, request: EmbeddingRequest(values: [value], dimensions: dimensions, providerOptions: providerOptions, extraBody: extraBody, headers: headers), retryPolicy: retryPolicy)
    }

    public static func embed(model: any EmbeddingModel, request: EmbeddingRequest, retryPolicy: AIRetryPolicy = .default) async throws -> EmbeddingResult {
        try await withRetry(policy: retryPolicy) {
            try await model.embed(request)
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
        retryPolicy: AIRetryPolicy = .default
    ) async throws -> EmbeddingResult {
        guard let chunkSize, chunkSize > 0, values.count > chunkSize else {
            return try await embed(model: model, request: EmbeddingRequest(values: values, dimensions: dimensions, providerOptions: providerOptions, extraBody: extraBody, headers: headers), retryPolicy: retryPolicy)
        }

        var embeddings: [[Double]] = []
        var usage: TokenUsage?
        var rawValues: [JSONValue] = []
        var warnings: [AIWarning] = []
        var providerMetadata: [String: JSONValue] = [:]
        var responseMetadata = AIResponseMetadata()

        for chunk in values.chunked(size: chunkSize) {
            let result = try await embed(model: model, request: EmbeddingRequest(values: chunk, dimensions: dimensions, providerOptions: providerOptions, extraBody: extraBody, headers: headers), retryPolicy: retryPolicy)
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

    public static func generateImage(model: any ImageModel, request: ImageGenerationRequest, retryPolicy: AIRetryPolicy = .default) async throws -> ImageGenerationResult {
        try await withRetry(policy: retryPolicy) {
            try await model.generateImage(request)
        }
    }

    public static func generateImage(model: any ImageModel, prompt: String, size: String? = nil, aspectRatio: String? = nil, seed: Int? = nil, count: Int? = nil, files: [ImageInputFile] = [], mask: ImageInputFile? = nil, providerOptions: [String: JSONValue] = [:], extraBody: [String: JSONValue] = [:], headers: [String: String] = [:], retryPolicy: AIRetryPolicy = .default) async throws -> ImageGenerationResult {
        try await generateImage(model: model, request: ImageGenerationRequest(prompt: prompt, size: size, aspectRatio: aspectRatio, seed: seed, count: count, files: files, mask: mask, providerOptions: providerOptions, extraBody: extraBody, headers: headers), retryPolicy: retryPolicy)
    }

    public static func transcribe(model: any TranscriptionModel, request: AudioTranscriptionRequest, retryPolicy: AIRetryPolicy = .default) async throws -> TranscriptionResult {
        try await withRetry(policy: retryPolicy) {
            try await model.transcribe(request)
        }
    }

    public static func generateSpeech(model: any SpeechModel, request: SpeechRequest, retryPolicy: AIRetryPolicy = .default) async throws -> SpeechResult {
        try await withRetry(policy: retryPolicy) {
            try await model.speak(request)
        }
    }

    public static func generateVideo(model: any VideoModel, request: VideoGenerationRequest, retryPolicy: AIRetryPolicy = .default) async throws -> VideoGenerationResult {
        try await withRetry(policy: retryPolicy) {
            try await model.generateVideo(request)
        }
    }

    public static func rerank(model: any RerankingModel, request: RerankingRequest, retryPolicy: AIRetryPolicy = .default) async throws -> RerankingResult {
        try await withRetry(policy: retryPolicy) {
            try await model.rerank(request)
        }
    }

    public static func uploadFile(client: any AIFileClient, request: FileUploadRequest, retryPolicy: AIRetryPolicy = .default) async throws -> FileUploadResult {
        try await withRetry(policy: retryPolicy) {
            try await client.uploadFile(request)
        }
    }

    public static func uploadSkill(client: any AISkillsClient, request: SkillUploadRequest, retryPolicy: AIRetryPolicy = .default) async throws -> SkillUploadResult {
        try await withRetry(policy: retryPolicy) {
            try await client.uploadSkill(request)
        }
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

private func withRetry<Output: Sendable>(
    policy: AIRetryPolicy,
    operation: @Sendable () async throws -> Output
) async throws -> Output {
    guard policy.maxRetries >= 0 else {
        throw AIError.invalidArgument(argument: "maxRetries", message: "maxRetries must be >= 0.")
    }
    guard policy.backoffFactor >= 1 else {
        throw AIError.invalidArgument(argument: "backoffFactor", message: "backoffFactor must be >= 1.")
    }

    var errors: [String] = []
    var delay = policy.initialDelayNanoseconds

    while true {
        try Task.checkCancellation()
        do {
            return try await operation()
        } catch is CancellationError {
            throw AIRetryError(reason: .cancelled, attempts: errors.count + 1, errors: errors)
        } catch {
            errors.append(String(describing: error))
            let attempts = errors.count
            guard policy.maxRetries > 0 else { throw error }
            guard isRetryable(error) else {
                if attempts == 1 { throw error }
                throw AIRetryError(reason: .errorNotRetryable, attempts: attempts, errors: errors)
            }
            guard attempts <= policy.maxRetries else {
                throw AIRetryError(reason: .maxRetriesExceeded, attempts: attempts, errors: errors)
            }
            if delay > 0 {
                try await Task.sleep(nanoseconds: delay)
            }
            delay = nextDelay(current: delay, policy: policy)
        }
    }
}

private func isRetryable(_ error: Error) -> Bool {
    if let error = error as? AIError {
        if case let .httpStatus(_, statusCode, _) = error {
            return statusCode == 408 || statusCode == 409 || statusCode == 429 || statusCode >= 500
        }
        return false
    }
    if let error = error as? URLError {
        switch error.code {
        case .cancelled, .userCancelledAuthentication:
            return false
        default:
            return true
        }
    }
    return false
}

private func nextDelay(current: UInt64, policy: AIRetryPolicy) -> UInt64 {
    guard current > 0 else { return 0 }
    let next = Double(current) * policy.backoffFactor
    guard next.isFinite, next < Double(UInt64.max) else {
        return policy.maxDelayNanoseconds
    }
    return Swift.min(UInt64(next), policy.maxDelayNanoseconds)
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

private func responseFormatJSON(schema: JSONValue?, name: String?, description: String?) -> JSONValue {
    .object([
        "type": .string("json"),
        "schema": schema,
        "name": name.map(JSONValue.string),
        "description": description.map(JSONValue.string)
    ])
}

private func parseObject<Object: Decodable>(
    _ type: Object.Type,
    from text: String,
    repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)?,
    providerID: String
) async throws -> (object: Object, rawObject: JSONValue, text: String) {
    do {
        return try decodeObject(Object.self, from: text)
    } catch {
        guard let repairText else {
            throw AIError.invalidResponse(provider: providerID, message: "No object generated: \(error.localizedDescription)")
        }
        guard let repaired = try await repairText(AIObjectRepairContext(text: text, errorMessage: error.localizedDescription)) else {
            throw AIError.invalidResponse(provider: providerID, message: "No object generated: \(error.localizedDescription)")
        }
        do {
            return try decodeObject(Object.self, from: repaired)
        } catch {
            throw AIError.invalidResponse(provider: providerID, message: "No object generated after repair: \(error.localizedDescription)")
        }
    }
}

private func decodeObject<Object: Decodable>(_ type: Object.Type, from text: String) throws -> (object: Object, rawObject: JSONValue, text: String) {
    let jsonText = try extractJSONObjectText(from: text)
    let rawObject = try decodeJSONBody(Data(jsonText.utf8))
    let data = try encodeJSONBody(rawObject)
    return (try JSONDecoder().decode(Object.self, from: data), rawObject, jsonText)
}

private func extractJSONObjectText(from text: String) throws -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if (try? decodeJSONBody(Data(trimmed.utf8))) != nil {
        return trimmed
    }

    if let fenced = fencedJSONText(from: trimmed), (try? decodeJSONBody(Data(fenced.utf8))) != nil {
        return fenced
    }

    if let balanced = balancedJSONText(from: trimmed), (try? decodeJSONBody(Data(balanced.utf8))) != nil {
        return balanced
    }

    throw AIError.invalidArgument(argument: "text", message: "Expected JSON object or array text.")
}

private func fencedJSONText(from text: String) -> String? {
    guard let opening = text.range(of: "```") else { return nil }
    let afterOpening = text[opening.upperBound...]
    let contentStart = afterOpening.firstIndex(of: "\n").map { text.index(after: $0) } ?? afterOpening.startIndex
    guard let closing = text[contentStart...].range(of: "```") else { return nil }
    return String(text[contentStart..<closing.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func balancedJSONText(from text: String) -> String? {
    guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
    let opening = text[start]
    let closing: Character = opening == "{" ? "}" : "]"
    var depth = 0
    var inString = false
    var escaped = false
    var index = start

    while index < text.endIndex {
        let character = text[index]
        if inString {
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString = false
            }
        } else if character == "\"" {
            inString = true
        } else if character == opening {
            depth += 1
        } else if character == closing {
            depth -= 1
            if depth == 0 {
                return String(text[start...index])
            }
        }
        index = text.index(after: index)
    }

    return nil
}

private extension Array {
    func chunked(size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}
