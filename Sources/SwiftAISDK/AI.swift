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
        stopWhen: [AIStopCondition] = [],
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
            let step = AIToolStep(
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
            steps.append(step)

            result.toolResults = allToolResults
            result.steps = steps
            lastResult = result
            if try await isStopConditionMet(stopWhen, steps: steps) {
                return result
            }
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
        stopWhen: [AIStopCondition] = [],
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
            stopWhen: stopWhen,
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
        request: LanguageModelRequest,
        executableTools: [AITool],
        maxSteps: Int = 5,
        stopWhen: [AIStopCondition] = []
    ) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !executableTools.isEmpty else {
                        for try await part in streamText(model: model, request: request) {
                            continuation.yield(part)
                        }
                        continuation.finish()
                        return
                    }
                    guard maxSteps > 0 else {
                        throw AIError.invalidArgument(argument: "maxSteps", message: "maxSteps must be greater than zero.")
                    }

                    let toolsByName = try toolsByName(from: executableTools)
                    var currentRequest = request
                    currentRequest.tools.merge(toolsDictionary(from: executableTools)) { _, typed in typed }
                    var steps: [AIToolStep] = []

                    for index in 0..<maxSteps {
                        let step = try await forwardLanguageStream(
                            streamText(model: model, request: currentRequest),
                            to: continuation
                        )
                        let executableCalls = step.toolCalls.filter { !$0.providerExecuted && toolsByName[$0.name] != nil }

                        guard !executableCalls.isEmpty else {
                            continuation.finish()
                            return
                        }

                        let toolResults = try await executeToolCalls(executableCalls, toolsByName: toolsByName)
                        for toolResult in toolResults {
                            continuation.yield(.toolResult(toolResult))
                        }

                        let completedStep = step.toolStep(index: index, toolResults: toolResults)
                        steps.append(completedStep)
                        if try await isStopConditionMet(stopWhen, steps: steps) {
                            continuation.finish()
                            return
                        }
                        currentRequest.messages.append(.assistant(text: step.text, toolCalls: step.toolCalls))
                        currentRequest.messages.append(contentsOf: toolResults.map(AIMessage.toolResult))
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
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
        executableTools: [AITool] = [],
        maxSteps: Int = 5,
        stopWhen: [AIStopCondition] = [],
        toolChoice: JSONValue? = nil,
        includeRawChunks: Bool = false,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:]
    ) -> AsyncThrowingStream<LanguageStreamPart, Error> {
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
            return streamText(model: model, request: request)
        }

        return streamText(model: model, request: request, executableTools: executableTools, maxSteps: maxSteps, stopWhen: stopWhen)
    }

    public static func streamObject<Object: Decodable & Sendable>(
        model: any LanguageModel,
        request: LanguageModelRequest,
        as type: Object.Type = Object.self,
        schema: JSONValue? = nil,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) -> AsyncThrowingStream<ObjectStreamPart<Object>, Error> {
        var objectRequest = request
        let responseFormat = AIResponseFormat.json(schema: schema, name: schemaName, description: schemaDescription)
        objectRequest.responseFormat = objectRequest.responseFormat ?? responseFormat
        if objectRequest.extraBody["responseFormat"] == nil {
            objectRequest.extraBody["responseFormat"] = responseFormatJSON(schema: schema, name: schemaName, description: schemaDescription)
        }
        let streamRequest = objectRequest

        return AsyncThrowingStream { continuation in
            let task = Task {
                var text = ""
                var reasoning = ""
                var finishReason: String?
                var usage: TokenUsage?
                var warnings: [AIWarning] = []
                var sources: [AISource] = []
                var providerMetadata: [String: JSONValue] = [:]
                var responseMetadata = AIResponseMetadata()
                var rawValues: [JSONValue] = []
                var lastPartialObject: JSONValue?

                do {
                    for try await part in streamText(model: model, request: streamRequest) {
                        try Task.checkCancellation()
                        switch part {
                        case let .streamStart(partWarnings):
                            warnings.append(contentsOf: partWarnings)
                            for warning in partWarnings {
                                continuation.yield(.warning(warning))
                            }
                        case let .textDelta(delta):
                            text += delta
                            continuation.yield(.textDelta(delta))
                            if let partial = partialObject(from: text), partial != lastPartialObject {
                                lastPartialObject = partial
                                continuation.yield(.partialObject(partial))
                            }
                        case let .textDeltaPart(_, delta, _):
                            text += delta
                            continuation.yield(.textDelta(delta))
                            if let partial = partialObject(from: text), partial != lastPartialObject {
                                lastPartialObject = partial
                                continuation.yield(.partialObject(partial))
                            }
                        case let .reasoningDelta(delta):
                            reasoning += delta
                            continuation.yield(.raw(part))
                        case let .reasoningDeltaPart(_, delta, _):
                            reasoning += delta
                            continuation.yield(.raw(part))
                        case let .source(source):
                            sources.append(source)
                            continuation.yield(.source(source))
                        case let .metadata(metadata):
                            continuation.yield(.metadata(metadata))
                        case let .responseMetadata(metadata):
                            responseMetadata = metadata
                            continuation.yield(.responseMetadata(metadata))
                        case let .raw(raw):
                            rawValues.append(raw)
                            continuation.yield(.raw(part))
                        case let .finish(reason, partUsage):
                            finishReason = reason
                            usage = partUsage
                        case let .finishMetadata(reason, partUsage, metadata):
                            finishReason = reason
                            usage = partUsage
                            providerMetadata.merge(metadata) { _, new in new }
                        default:
                            continuation.yield(.raw(part))
                        }
                    }

                    let parsed = try await parseObject(
                        Object.self,
                        from: text,
                        repairText: repairText,
                        providerID: model.providerID
                    )
                    let textResult = TextGenerationResult(
                        text: parsed.text,
                        reasoning: reasoning,
                        finishReason: finishReason,
                        usage: usage,
                        sources: sources,
                        providerMetadata: providerMetadata,
                        rawValue: rawValues.isEmpty ? parsed.rawObject : .array(rawValues),
                        warnings: warnings,
                        responseMetadata: responseMetadata
                    )
                    let objectResult = ObjectGenerationResult(
                        object: parsed.object,
                        text: parsed.text,
                        rawObject: parsed.rawObject,
                        reasoning: reasoning,
                        finishReason: finishReason,
                        usage: usage,
                        warnings: warnings,
                        providerMetadata: providerMetadata,
                        responseMetadata: responseMetadata,
                        textResult: textResult
                    )
                    continuation.yield(.object(objectResult))
                    continuation.yield(.finish(reason: finishReason, usage: usage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public static func streamObject<Object: Decodable & Sendable>(
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
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) -> AsyncThrowingStream<ObjectStreamPart<Object>, Error> {
        streamObject(
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
            repairText: repairText
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

private struct LanguageStreamToolStep {
    var text = ""
    var reasoning = ""
    var finishReason: String?
    var usage: TokenUsage?
    var toolCalls: [AIToolCall] = []
    var providerMetadata: [String: JSONValue] = [:]
    var responseMetadata = AIResponseMetadata()

    mutating func record(_ part: LanguageStreamPart) {
        switch part {
        case let .textDelta(delta):
            text += delta
        case let .textDeltaPart(_, delta, _):
            text += delta
        case let .reasoningDelta(delta):
            reasoning += delta
        case let .reasoningDeltaPart(_, delta, _):
            reasoning += delta
        case let .toolCall(toolCall):
            toolCalls.append(toolCall)
        case let .metadata(metadata):
            providerMetadata.merge(metadata) { _, new in new }
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .finish(reason, partUsage):
            finishReason = reason
            usage = partUsage
        case let .finishMetadata(reason, partUsage, metadata):
            finishReason = reason
            usage = partUsage
            providerMetadata.merge(metadata) { _, new in new }
        default:
            break
        }
    }

    func toolStep(index: Int, toolResults: [AIToolResult]) -> AIToolStep {
        AIToolStep(
            index: index,
            text: text,
            reasoning: reasoning,
            finishReason: finishReason,
            usage: usage,
            toolCalls: toolCalls,
            toolResults: toolResults,
            providerMetadata: providerMetadata,
            responseMetadata: responseMetadata
        )
    }
}

private func forwardLanguageStream(
    _ stream: AsyncThrowingStream<LanguageStreamPart, Error>,
    to continuation: AsyncThrowingStream<LanguageStreamPart, Error>.Continuation
) async throws -> LanguageStreamToolStep {
    var step = LanguageStreamToolStep()
    for try await part in stream {
        try Task.checkCancellation()
        step.record(part)
        continuation.yield(part)
    }
    return step
}

private func isStopConditionMet(_ stopConditions: [AIStopCondition], steps: [AIToolStep]) async throws -> Bool {
    let context = AIStopConditionContext(steps: steps)
    for condition in stopConditions {
        if try await condition.evaluate(context) {
            return true
        }
    }
    return false
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

private func partialObject(from text: String) -> JSONValue? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let value = try? decodeJSONBody(Data(trimmed.utf8)) {
        return value
    }
    let repaired = fixPartialJSON(trimmed)
    guard repaired != trimmed, !repaired.isEmpty else { return nil }
    return try? decodeJSONBody(Data(repaired.utf8))
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

private enum PartialJSONState {
    case root
    case finish
    case insideString
    case insideStringEscape
    case insideLiteral
    case insideNumber
    case insideObjectStart
    case insideObjectKey
    case insideObjectAfterKey
    case insideObjectBeforeValue
    case insideObjectAfterValue
    case insideObjectAfterComma
    case insideArrayStart
    case insideArrayAfterValue
    case insideArrayAfterComma
}

private func fixPartialJSON(_ input: String) -> String {
    let characters = Array(input)
    var stack: [PartialJSONState] = [.root]
    var lastValidIndex: Int?
    var literalStart: Int?

    func replaceTop(with states: PartialJSONState...) {
        _ = stack.popLast()
        stack.append(contentsOf: states)
    }

    func processValueStart(_ character: Character, index: Int, swapState: PartialJSONState) {
        switch character {
        case "\"":
            lastValidIndex = index
            replaceTop(with: swapState, .insideString)
        case "f", "t", "n":
            lastValidIndex = index
            literalStart = index
            replaceTop(with: swapState, .insideLiteral)
        case "-":
            replaceTop(with: swapState, .insideNumber)
        case "0"..."9":
            lastValidIndex = index
            replaceTop(with: swapState, .insideNumber)
        case "{":
            lastValidIndex = index
            replaceTop(with: swapState, .insideObjectStart)
        case "[":
            lastValidIndex = index
            replaceTop(with: swapState, .insideArrayStart)
        default:
            break
        }
    }

    func processAfterObjectValue(_ character: Character, index: Int) {
        switch character {
        case ",":
            _ = stack.popLast()
            stack.append(.insideObjectAfterComma)
        case "}":
            lastValidIndex = index
            _ = stack.popLast()
        default:
            break
        }
    }

    func processAfterArrayValue(_ character: Character, index: Int) {
        switch character {
        case ",":
            _ = stack.popLast()
            stack.append(.insideArrayAfterComma)
        case "]":
            lastValidIndex = index
            _ = stack.popLast()
        default:
            break
        }
    }

    for (index, character) in characters.enumerated() {
        guard let currentState = stack.last else { break }
        switch currentState {
        case .root:
            processValueStart(character, index: index, swapState: .finish)

        case .insideObjectStart:
            switch character {
            case "\"":
                _ = stack.popLast()
                stack.append(.insideObjectKey)
            case "}":
                lastValidIndex = index
                _ = stack.popLast()
            default:
                break
            }

        case .insideObjectAfterComma:
            if character == "\"" {
                _ = stack.popLast()
                stack.append(.insideObjectKey)
            }

        case .insideObjectKey:
            if character == "\"" {
                _ = stack.popLast()
                stack.append(.insideObjectAfterKey)
            }

        case .insideObjectAfterKey:
            if character == ":" {
                _ = stack.popLast()
                stack.append(.insideObjectBeforeValue)
            }

        case .insideObjectBeforeValue:
            processValueStart(character, index: index, swapState: .insideObjectAfterValue)

        case .insideObjectAfterValue:
            processAfterObjectValue(character, index: index)

        case .insideString:
            switch character {
            case "\"":
                _ = stack.popLast()
                lastValidIndex = index
            case "\\":
                stack.append(.insideStringEscape)
            default:
                lastValidIndex = index
            }

        case .insideArrayStart:
            if character == "]" {
                lastValidIndex = index
                _ = stack.popLast()
            } else {
                lastValidIndex = index
                processValueStart(character, index: index, swapState: .insideArrayAfterValue)
            }

        case .insideArrayAfterValue:
            switch character {
            case ",":
                _ = stack.popLast()
                stack.append(.insideArrayAfterComma)
            case "]":
                lastValidIndex = index
                _ = stack.popLast()
            default:
                lastValidIndex = index
            }

        case .insideArrayAfterComma:
            processValueStart(character, index: index, swapState: .insideArrayAfterValue)

        case .insideStringEscape:
            _ = stack.popLast()
            lastValidIndex = index

        case .insideNumber:
            switch character {
            case "0"..."9":
                lastValidIndex = index
            case "e", "E", "-", ".":
                break
            case ",":
                _ = stack.popLast()
                if stack.last == .insideArrayAfterValue {
                    processAfterArrayValue(character, index: index)
                }
                if stack.last == .insideObjectAfterValue {
                    processAfterObjectValue(character, index: index)
                }
            case "}":
                _ = stack.popLast()
                if stack.last == .insideObjectAfterValue {
                    processAfterObjectValue(character, index: index)
                }
            case "]":
                _ = stack.popLast()
                if stack.last == .insideArrayAfterValue {
                    processAfterArrayValue(character, index: index)
                }
            default:
                _ = stack.popLast()
            }

        case .insideLiteral:
            let start = literalStart ?? index
            let partialLiteral = String(characters[start...index])
            if !"false".hasPrefix(partialLiteral),
               !"true".hasPrefix(partialLiteral),
               !"null".hasPrefix(partialLiteral) {
                _ = stack.popLast()
                if stack.last == .insideObjectAfterValue {
                    processAfterObjectValue(character, index: index)
                } else if stack.last == .insideArrayAfterValue {
                    processAfterArrayValue(character, index: index)
                }
            } else {
                lastValidIndex = index
            }

        case .finish:
            break
        }
    }

    guard let lastValidIndex else { return "" }
    var result = String(characters[0...lastValidIndex])

    for state in stack.reversed() {
        switch state {
        case .insideString:
            result += "\""
        case .insideObjectKey,
             .insideObjectAfterKey,
             .insideObjectAfterComma,
             .insideObjectStart,
             .insideObjectBeforeValue,
             .insideObjectAfterValue:
            result += "}"
        case .insideArrayStart,
             .insideArrayAfterComma,
             .insideArrayAfterValue:
            result += "]"
        case .insideLiteral:
            let start = literalStart ?? characters.count
            let partialLiteral = start < characters.count ? String(characters[start..<characters.count]) : ""
            if "true".hasPrefix(partialLiteral) {
                result += String("true".dropFirst(partialLiteral.count))
            } else if "false".hasPrefix(partialLiteral) {
                result += String("false".dropFirst(partialLiteral.count))
            } else if "null".hasPrefix(partialLiteral) {
                result += String("null".dropFirst(partialLiteral.count))
            }
        case .root, .finish, .insideStringEscape, .insideNumber:
            break
        }
    }

    return result
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
