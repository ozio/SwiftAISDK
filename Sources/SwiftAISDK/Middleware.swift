import Foundation

public enum AILanguageModelCallType: String, Sendable {
    case generate
    case stream
}

public struct AILanguageModelTransformContext: Sendable {
    public var type: AILanguageModelCallType
    public var request: LanguageModelRequest
    public var model: any LanguageModel

    public init(type: AILanguageModelCallType, request: LanguageModelRequest, model: any LanguageModel) {
        self.type = type
        self.request = request
        self.model = model
    }
}

public struct AILanguageModelGenerateContext: Sendable {
    public var doGenerate: @Sendable () async throws -> TextGenerationResult
    public var doStream: @Sendable () -> AsyncThrowingStream<LanguageStreamPart, Error>
    public var request: LanguageModelRequest
    public var model: any LanguageModel

    public init(
        doGenerate: @escaping @Sendable () async throws -> TextGenerationResult,
        doStream: @escaping @Sendable () -> AsyncThrowingStream<LanguageStreamPart, Error>,
        request: LanguageModelRequest,
        model: any LanguageModel
    ) {
        self.doGenerate = doGenerate
        self.doStream = doStream
        self.request = request
        self.model = model
    }
}

public struct AILanguageModelStreamContext: Sendable {
    public var doGenerate: @Sendable () async throws -> TextGenerationResult
    public var doStream: @Sendable () -> AsyncThrowingStream<LanguageStreamPart, Error>
    public var request: LanguageModelRequest
    public var model: any LanguageModel

    public init(
        doGenerate: @escaping @Sendable () async throws -> TextGenerationResult,
        doStream: @escaping @Sendable () -> AsyncThrowingStream<LanguageStreamPart, Error>,
        request: LanguageModelRequest,
        model: any LanguageModel
    ) {
        self.doGenerate = doGenerate
        self.doStream = doStream
        self.request = request
        self.model = model
    }
}

public struct AILanguageModelMiddleware: Sendable {
    public var overrideProviderID: (@Sendable (_ model: any LanguageModel) -> String)?
    public var overrideModelID: (@Sendable (_ model: any LanguageModel) -> String)?
    public var transformRequest: (@Sendable (AILanguageModelTransformContext) async throws -> LanguageModelRequest)?
    public var wrapGenerate: (@Sendable (AILanguageModelGenerateContext) async throws -> TextGenerationResult)?
    public var wrapStream: (@Sendable (AILanguageModelStreamContext) -> AsyncThrowingStream<LanguageStreamPart, Error>)?

    public init(
        overrideProviderID: (@Sendable (_ model: any LanguageModel) -> String)? = nil,
        overrideModelID: (@Sendable (_ model: any LanguageModel) -> String)? = nil,
        transformRequest: (@Sendable (AILanguageModelTransformContext) async throws -> LanguageModelRequest)? = nil,
        wrapGenerate: (@Sendable (AILanguageModelGenerateContext) async throws -> TextGenerationResult)? = nil,
        wrapStream: (@Sendable (AILanguageModelStreamContext) -> AsyncThrowingStream<LanguageStreamPart, Error>)? = nil
    ) {
        self.overrideProviderID = overrideProviderID
        self.overrideModelID = overrideModelID
        self.transformRequest = transformRequest
        self.wrapGenerate = wrapGenerate
        self.wrapStream = wrapStream
    }
}

public struct AIImageModelTransformContext: Sendable {
    public var request: ImageGenerationRequest
    public var model: any ImageModel

    public init(request: ImageGenerationRequest, model: any ImageModel) {
        self.request = request
        self.model = model
    }
}

public struct AIImageModelGenerateContext: Sendable {
    public var doGenerate: @Sendable () async throws -> ImageGenerationResult
    public var request: ImageGenerationRequest
    public var model: any ImageModel

    public init(
        doGenerate: @escaping @Sendable () async throws -> ImageGenerationResult,
        request: ImageGenerationRequest,
        model: any ImageModel
    ) {
        self.doGenerate = doGenerate
        self.request = request
        self.model = model
    }
}

public struct AIImageModelMiddleware: Sendable {
    public var overrideProviderID: (@Sendable (_ model: any ImageModel) -> String)?
    public var overrideModelID: (@Sendable (_ model: any ImageModel) -> String)?
    public var transformRequest: (@Sendable (AIImageModelTransformContext) async throws -> ImageGenerationRequest)?
    public var wrapGenerate: (@Sendable (AIImageModelGenerateContext) async throws -> ImageGenerationResult)?

    public init(
        overrideProviderID: (@Sendable (_ model: any ImageModel) -> String)? = nil,
        overrideModelID: (@Sendable (_ model: any ImageModel) -> String)? = nil,
        transformRequest: (@Sendable (AIImageModelTransformContext) async throws -> ImageGenerationRequest)? = nil,
        wrapGenerate: (@Sendable (AIImageModelGenerateContext) async throws -> ImageGenerationResult)? = nil
    ) {
        self.overrideProviderID = overrideProviderID
        self.overrideModelID = overrideModelID
        self.transformRequest = transformRequest
        self.wrapGenerate = wrapGenerate
    }
}

public struct AIEmbeddingModelTransformContext: Sendable {
    public var request: EmbeddingRequest
    public var model: any EmbeddingModel

    public init(request: EmbeddingRequest, model: any EmbeddingModel) {
        self.request = request
        self.model = model
    }
}

public struct AIEmbeddingModelEmbedContext: Sendable {
    public var doEmbed: @Sendable () async throws -> EmbeddingResult
    public var request: EmbeddingRequest
    public var model: any EmbeddingModel

    public init(
        doEmbed: @escaping @Sendable () async throws -> EmbeddingResult,
        request: EmbeddingRequest,
        model: any EmbeddingModel
    ) {
        self.doEmbed = doEmbed
        self.request = request
        self.model = model
    }
}

public struct AIEmbeddingModelMiddleware: Sendable {
    public var overrideProviderID: (@Sendable (_ model: any EmbeddingModel) -> String)?
    public var overrideModelID: (@Sendable (_ model: any EmbeddingModel) -> String)?
    public var transformRequest: (@Sendable (AIEmbeddingModelTransformContext) async throws -> EmbeddingRequest)?
    public var wrapEmbed: (@Sendable (AIEmbeddingModelEmbedContext) async throws -> EmbeddingResult)?

    public init(
        overrideProviderID: (@Sendable (_ model: any EmbeddingModel) -> String)? = nil,
        overrideModelID: (@Sendable (_ model: any EmbeddingModel) -> String)? = nil,
        transformRequest: (@Sendable (AIEmbeddingModelTransformContext) async throws -> EmbeddingRequest)? = nil,
        wrapEmbed: (@Sendable (AIEmbeddingModelEmbedContext) async throws -> EmbeddingResult)? = nil
    ) {
        self.overrideProviderID = overrideProviderID
        self.overrideModelID = overrideModelID
        self.transformRequest = transformRequest
        self.wrapEmbed = wrapEmbed
    }
}

public func wrapLanguageModel(
    _ model: any LanguageModel,
    middleware: AILanguageModelMiddleware,
    modelID: String? = nil,
    providerID: String? = nil
) -> any LanguageModel {
    wrapLanguageModel(model, middleware: [middleware], modelID: modelID, providerID: providerID)
}

public func wrapLanguageModel(
    _ model: any LanguageModel,
    middleware: [AILanguageModelMiddleware],
    modelID: String? = nil,
    providerID: String? = nil
) -> any LanguageModel {
    middleware.reversed().reduce(model) { wrappedModel, nextMiddleware in
        AIWrappedLanguageModel(
            model: wrappedModel,
            middleware: nextMiddleware,
            modelID: modelID,
            providerID: providerID
        )
    }
}

public func wrapImageModel(
    _ model: any ImageModel,
    middleware: AIImageModelMiddleware,
    modelID: String? = nil,
    providerID: String? = nil
) -> any ImageModel {
    wrapImageModel(model, middleware: [middleware], modelID: modelID, providerID: providerID)
}

public func wrapImageModel(
    _ model: any ImageModel,
    middleware: [AIImageModelMiddleware],
    modelID: String? = nil,
    providerID: String? = nil
) -> any ImageModel {
    middleware.reversed().reduce(model) { wrappedModel, nextMiddleware in
        AIWrappedImageModel(
            model: wrappedModel,
            middleware: nextMiddleware,
            modelID: modelID,
            providerID: providerID
        )
    }
}

public func wrapEmbeddingModel(
    _ model: any EmbeddingModel,
    middleware: AIEmbeddingModelMiddleware,
    modelID: String? = nil,
    providerID: String? = nil
) -> any EmbeddingModel {
    wrapEmbeddingModel(model, middleware: [middleware], modelID: modelID, providerID: providerID)
}

public func wrapEmbeddingModel(
    _ model: any EmbeddingModel,
    middleware: [AIEmbeddingModelMiddleware],
    modelID: String? = nil,
    providerID: String? = nil
) -> any EmbeddingModel {
    middleware.reversed().reduce(model) { wrappedModel, nextMiddleware in
        AIWrappedEmbeddingModel(
            model: wrappedModel,
            middleware: nextMiddleware,
            modelID: modelID,
            providerID: providerID
        )
    }
}

public struct AIDefaultLanguageModelSettings: Sendable {
    public var temperature: Double?
    public var topP: Double?
    public var topK: Int?
    public var presencePenalty: Double?
    public var frequencyPenalty: Double?
    public var seed: Int?
    public var maxOutputTokens: Int?
    public var stopSequences: [String]?
    public var responseFormat: AIResponseFormat?
    public var reasoning: String?
    public var tools: [String: JSONValue]
    public var toolChoice: JSONValue?
    public var providerOptions: [String: JSONValue]
    public var extraBody: [String: JSONValue]
    public var headers: [String: String]

    public init(
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        seed: Int? = nil,
        maxOutputTokens: Int? = nil,
        stopSequences: [String]? = nil,
        responseFormat: AIResponseFormat? = nil,
        reasoning: String? = nil,
        tools: [String: JSONValue] = [:],
        toolChoice: JSONValue? = nil,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:]
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.seed = seed
        self.maxOutputTokens = maxOutputTokens
        self.stopSequences = stopSequences
        self.responseFormat = responseFormat
        self.reasoning = reasoning
        self.tools = tools
        self.toolChoice = toolChoice
        self.providerOptions = providerOptions
        self.extraBody = extraBody
        self.headers = headers
    }
}

public func defaultSettingsMiddleware(settings: AIDefaultLanguageModelSettings) -> AILanguageModelMiddleware {
    AILanguageModelMiddleware(transformRequest: { context in
        applyingDefaultSettings(settings, to: context.request)
    })
}

public struct AIDefaultEmbeddingModelSettings: Sendable {
    public var providerOptions: [String: JSONValue]
    public var headers: [String: String]

    public init(
        providerOptions: [String: JSONValue] = [:],
        headers: [String: String] = [:]
    ) {
        self.providerOptions = providerOptions
        self.headers = headers
    }
}

public func defaultEmbeddingSettingsMiddleware(settings: AIDefaultEmbeddingModelSettings) -> AIEmbeddingModelMiddleware {
    AIEmbeddingModelMiddleware(transformRequest: { context in
        applyingDefaultEmbeddingSettings(settings, to: context.request)
    })
}

public func extractJsonMiddleware(
    transform: (@Sendable (_ text: String) -> String)? = nil
) -> AILanguageModelMiddleware {
    let transformText = transform ?? defaultExtractJSONTransform
    return AILanguageModelMiddleware(
        wrapGenerate: { context in
            var result = try await context.doGenerate()
            result.text = transformText(result.text)
            return result
        },
        wrapStream: { context in
            transformTextStream(context.doStream(), transform: transformText)
        }
    )
}

public func extractJSONMiddleware(
    transform: (@Sendable (_ text: String) -> String)? = nil
) -> AILanguageModelMiddleware {
    extractJsonMiddleware(transform: transform)
}

public func extractReasoningMiddleware(
    tagName: String,
    separator: String = "\n",
    startWithReasoning: Bool = false
) -> AILanguageModelMiddleware {
    AILanguageModelMiddleware(
        wrapGenerate: { context in
            var result = try await context.doGenerate()
            let input = startWithReasoning ? "<\(tagName)>" + result.text : result.text
            guard let extracted = extractTaggedSections(text: input, tagName: tagName, separator: separator) else {
                return result
            }
            result.text = extracted.text
            result.reasoning = appendSeparated(result.reasoning, extracted.reasoning, separator: separator)
            return result
        },
        wrapStream: { context in
            extractReasoningStream(
                context.doStream(),
                tagName: tagName,
                separator: separator,
                startWithReasoning: startWithReasoning
            )
        }
    )
}

public func simulateStreamingMiddleware() -> AILanguageModelMiddleware {
    AILanguageModelMiddleware(wrapStream: { context in
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await context.doGenerate()
                    var id = 0

                    continuation.yield(.streamStart(warnings: result.warnings))
                    if result.responseMetadata != AIResponseMetadata() {
                        continuation.yield(.responseMetadata(result.responseMetadata))
                    }

                    if !result.reasoning.isEmpty {
                        let partID = String(id)
                        continuation.yield(.reasoningStart(id: partID))
                        continuation.yield(.reasoningDeltaPart(id: partID, delta: result.reasoning))
                        continuation.yield(.reasoningEnd(id: partID))
                        id += 1
                    }

                    if !result.text.isEmpty {
                        let partID = String(id)
                        continuation.yield(.textStart(id: partID))
                        continuation.yield(.textDeltaPart(id: partID, delta: result.text))
                        continuation.yield(.textEnd(id: partID))
                        id += 1
                    }

                    for source in result.sources {
                        continuation.yield(.source(source))
                    }
                    for toolCall in result.toolCalls {
                        continuation.yield(.toolCall(toolCall))
                    }
                    for approvalRequest in result.toolApprovalRequests {
                        continuation.yield(.toolApprovalRequest(approvalRequest))
                    }
                    for approvalResponse in result.toolApprovalResponses {
                        continuation.yield(.toolApprovalResponse(approvalResponse))
                    }
                    for toolResult in result.toolResults {
                        continuation.yield(.toolResult(toolResult))
                    }

                    continuation.yield(.finish(reason: result.finishReason, usage: result.usage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    })
}

public struct AIToolInputExampleFormatContext: Sendable {
    public var example: JSONValue
    public var index: Int

    public init(example: JSONValue, index: Int) {
        self.example = example
        self.index = index
    }
}

public func addToolInputExamplesMiddleware(
    prefix: String = "Input Examples:",
    remove: Bool = true,
    format: (@Sendable (AIToolInputExampleFormatContext) -> String)? = nil
) -> AILanguageModelMiddleware {
    AILanguageModelMiddleware(transformRequest: { context in
        var request = context.request
        request.tools = request.tools.mapValues { tool in
            toolWithInputExamplesInDescription(
                tool,
                prefix: prefix,
                remove: remove,
                format: format ?? defaultFormatToolInputExample
            )
        }
        return request
    })
}

public func wrapProvider(
    _ provider: any AIProvider,
    languageModelMiddleware: AILanguageModelMiddleware,
    imageModelMiddleware: [AIImageModelMiddleware] = [],
    embeddingModelMiddleware: [AIEmbeddingModelMiddleware] = []
) -> any AIProvider {
    wrapProvider(
        provider,
        languageModelMiddleware: [languageModelMiddleware],
        imageModelMiddleware: imageModelMiddleware,
        embeddingModelMiddleware: embeddingModelMiddleware
    )
}

public func wrapProvider(
    _ provider: any AIProvider,
    languageModelMiddleware: [AILanguageModelMiddleware],
    imageModelMiddleware: [AIImageModelMiddleware] = [],
    embeddingModelMiddleware: [AIEmbeddingModelMiddleware] = []
) -> any AIProvider {
    AIWrappedProvider(
        provider: provider,
        languageModelMiddleware: languageModelMiddleware,
        imageModelMiddleware: imageModelMiddleware,
        embeddingModelMiddleware: embeddingModelMiddleware
    )
}

public func wrapProvider(
    _ provider: any AIProvider,
    languageModelMiddleware: [AILanguageModelMiddleware] = [],
    imageModelMiddleware: AIImageModelMiddleware,
    embeddingModelMiddleware: [AIEmbeddingModelMiddleware] = []
) -> any AIProvider {
    wrapProvider(
        provider,
        languageModelMiddleware: languageModelMiddleware,
        imageModelMiddleware: [imageModelMiddleware],
        embeddingModelMiddleware: embeddingModelMiddleware
    )
}

public func wrapProvider(
    _ provider: any AIProvider,
    languageModelMiddleware: [AILanguageModelMiddleware] = [],
    imageModelMiddleware: [AIImageModelMiddleware] = [],
    embeddingModelMiddleware: AIEmbeddingModelMiddleware
) -> any AIProvider {
    wrapProvider(
        provider,
        languageModelMiddleware: languageModelMiddleware,
        imageModelMiddleware: imageModelMiddleware,
        embeddingModelMiddleware: [embeddingModelMiddleware]
    )
}

private final class AIWrappedLanguageModel: LanguageModel, @unchecked Sendable {
    private let model: any LanguageModel
    private let middleware: AILanguageModelMiddleware
    let providerID: String
    let modelID: String

    init(
        model: any LanguageModel,
        middleware: AILanguageModelMiddleware,
        modelID: String?,
        providerID: String?
    ) {
        self.model = model
        self.middleware = middleware
        self.providerID = providerID ?? middleware.overrideProviderID?(model) ?? model.providerID
        self.modelID = modelID ?? middleware.overrideModelID?(model) ?? model.modelID
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let transformed = try await transform(request, type: .generate)
        let doGenerate: @Sendable () async throws -> TextGenerationResult = { [model] in
            try await model.generate(transformed)
        }
        let doStream: @Sendable () -> AsyncThrowingStream<LanguageStreamPart, Error> = { [model] in
            model.stream(transformed)
        }

        guard let wrapGenerate = middleware.wrapGenerate else {
            return try await doGenerate()
        }
        return try await wrapGenerate(AILanguageModelGenerateContext(
            doGenerate: doGenerate,
            doStream: doStream,
            request: transformed,
            model: model
        ))
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let transformed = try await transform(request, type: .stream)
                    let doGenerate: @Sendable () async throws -> TextGenerationResult = { [model] in
                        try await model.generate(transformed)
                    }
                    let doStream: @Sendable () -> AsyncThrowingStream<LanguageStreamPart, Error> = { [model] in
                        model.stream(transformed)
                    }
                    let stream = middleware.wrapStream?(AILanguageModelStreamContext(
                        doGenerate: doGenerate,
                        doStream: doStream,
                        request: transformed,
                        model: model
                    )) ?? doStream()

                    for try await part in stream {
                        continuation.yield(part)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func transform(_ request: LanguageModelRequest, type: AILanguageModelCallType) async throws -> LanguageModelRequest {
        guard let transformRequest = middleware.transformRequest else {
            return request
        }
        return try await transformRequest(AILanguageModelTransformContext(
            type: type,
            request: request,
            model: model
        ))
    }
}

private final class AIWrappedImageModel: ImageModel, @unchecked Sendable {
    private let model: any ImageModel
    private let middleware: AIImageModelMiddleware
    let providerID: String
    let modelID: String

    init(
        model: any ImageModel,
        middleware: AIImageModelMiddleware,
        modelID: String?,
        providerID: String?
    ) {
        self.model = model
        self.middleware = middleware
        self.providerID = providerID ?? middleware.overrideProviderID?(model) ?? model.providerID
        self.modelID = modelID ?? middleware.overrideModelID?(model) ?? model.modelID
    }

    func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        let transformed = try await transform(request)
        let doGenerate: @Sendable () async throws -> ImageGenerationResult = { [model] in
            try await model.generateImage(transformed)
        }
        guard let wrapGenerate = middleware.wrapGenerate else {
            return try await doGenerate()
        }
        return try await wrapGenerate(AIImageModelGenerateContext(
            doGenerate: doGenerate,
            request: transformed,
            model: model
        ))
    }

    private func transform(_ request: ImageGenerationRequest) async throws -> ImageGenerationRequest {
        guard let transformRequest = middleware.transformRequest else {
            return request
        }
        return try await transformRequest(AIImageModelTransformContext(request: request, model: model))
    }
}

private final class AIWrappedEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    private let model: any EmbeddingModel
    private let middleware: AIEmbeddingModelMiddleware
    let providerID: String
    let modelID: String

    init(
        model: any EmbeddingModel,
        middleware: AIEmbeddingModelMiddleware,
        modelID: String?,
        providerID: String?
    ) {
        self.model = model
        self.middleware = middleware
        self.providerID = providerID ?? middleware.overrideProviderID?(model) ?? model.providerID
        self.modelID = modelID ?? middleware.overrideModelID?(model) ?? model.modelID
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        let transformed = try await transform(request)
        let doEmbed: @Sendable () async throws -> EmbeddingResult = { [model] in
            try await model.embed(transformed)
        }
        guard let wrapEmbed = middleware.wrapEmbed else {
            return try await doEmbed()
        }
        return try await wrapEmbed(AIEmbeddingModelEmbedContext(
            doEmbed: doEmbed,
            request: transformed,
            model: model
        ))
    }

    private func transform(_ request: EmbeddingRequest) async throws -> EmbeddingRequest {
        guard let transformRequest = middleware.transformRequest else {
            return request
        }
        return try await transformRequest(AIEmbeddingModelTransformContext(request: request, model: model))
    }
}

private final class AIWrappedProvider: AIFileProvider, AISkillsProvider, @unchecked Sendable {
    private let provider: any AIProvider
    private let languageModelMiddleware: [AILanguageModelMiddleware]
    private let imageModelMiddleware: [AIImageModelMiddleware]
    private let embeddingModelMiddleware: [AIEmbeddingModelMiddleware]

    let providerID: String
    let supportedCapabilities: Set<ModelCapability>

    init(
        provider: any AIProvider,
        languageModelMiddleware: [AILanguageModelMiddleware],
        imageModelMiddleware: [AIImageModelMiddleware],
        embeddingModelMiddleware: [AIEmbeddingModelMiddleware]
    ) {
        self.provider = provider
        self.languageModelMiddleware = languageModelMiddleware
        self.imageModelMiddleware = imageModelMiddleware
        self.embeddingModelMiddleware = embeddingModelMiddleware
        self.providerID = provider.providerID
        self.supportedCapabilities = provider.supportedCapabilities
    }

    func languageModel(_ modelID: String) throws -> any LanguageModel {
        wrapLanguageModel(try provider.languageModel(modelID), middleware: languageModelMiddleware)
    }

    func embeddingModel(_ modelID: String) throws -> any EmbeddingModel {
        let model = try provider.embeddingModel(modelID)
        guard !embeddingModelMiddleware.isEmpty else {
            return model
        }
        return wrapEmbeddingModel(model, middleware: embeddingModelMiddleware)
    }

    func imageModel(_ modelID: String) throws -> any ImageModel {
        let model = try provider.imageModel(modelID)
        guard !imageModelMiddleware.isEmpty else {
            return model
        }
        return wrapImageModel(model, middleware: imageModelMiddleware)
    }

    func transcriptionModel(_ modelID: String) throws -> any TranscriptionModel {
        try provider.transcriptionModel(modelID)
    }

    func speechModel(_ modelID: String) throws -> any SpeechModel {
        try provider.speechModel(modelID)
    }

    func videoModel(_ modelID: String) throws -> any VideoModel {
        try provider.videoModel(modelID)
    }

    func rerankingModel(_ modelID: String) throws -> any RerankingModel {
        try provider.rerankingModel(modelID)
    }

    func files() throws -> any AIFileClient {
        guard let fileProvider = provider as? any AIFileProvider else {
            throw AIProviderRegistryError.unsupportedFiles(providerID: provider.providerID)
        }
        return try fileProvider.files()
    }

    func skills() throws -> any AISkillsClient {
        guard let skillsProvider = provider as? any AISkillsProvider else {
            throw AIProviderRegistryError.unsupportedSkills(providerID: provider.providerID)
        }
        return try skillsProvider.skills()
    }
}

private func applyingDefaultSettings(_ settings: AIDefaultLanguageModelSettings, to request: LanguageModelRequest) -> LanguageModelRequest {
    var output = request
    output.temperature = output.temperature ?? settings.temperature
    output.topP = output.topP ?? settings.topP
    output.topK = output.topK ?? settings.topK
    output.presencePenalty = output.presencePenalty ?? settings.presencePenalty
    output.frequencyPenalty = output.frequencyPenalty ?? settings.frequencyPenalty
    output.seed = output.seed ?? settings.seed
    output.maxOutputTokens = output.maxOutputTokens ?? settings.maxOutputTokens
    if output.stopSequences.isEmpty, let stopSequences = settings.stopSequences {
        output.stopSequences = stopSequences
    }
    output.responseFormat = output.responseFormat ?? settings.responseFormat
    output.reasoning = output.reasoning ?? settings.reasoning
    output.tools = mergeJSONDictionaries(settings.tools, output.tools)
    output.toolChoice = output.toolChoice ?? settings.toolChoice
    output.providerOptions = mergeJSONDictionaries(settings.providerOptions, output.providerOptions)
    output.extraBody = mergeJSONDictionaries(settings.extraBody, output.extraBody)
    output.headers = settings.headers.merging(output.headers) { _, request in request }
    return output
}

private func applyingDefaultEmbeddingSettings(
    _ settings: AIDefaultEmbeddingModelSettings,
    to request: EmbeddingRequest
) -> EmbeddingRequest {
    var output = request
    output.providerOptions = mergeJSONDictionaries(settings.providerOptions, output.providerOptions)
    output.headers = settings.headers.merging(output.headers) { _, request in request }
    return output
}

private func mergeJSONDictionaries(_ defaults: [String: JSONValue], _ overrides: [String: JSONValue]) -> [String: JSONValue] {
    defaults.merging(overrides) { defaultValue, overrideValue in
        mergeJSONValues(defaultValue, overrideValue)
    }
}

private func mergeJSONValues(_ defaultValue: JSONValue, _ overrideValue: JSONValue) -> JSONValue {
    guard case let .object(defaultObject) = defaultValue,
          case let .object(overrideObject) = overrideValue else {
        return overrideValue
    }
    return .object(mergeJSONDictionaries(defaultObject, overrideObject))
}

private func defaultExtractJSONTransform(_ text: String) -> String {
    text
        .replacingOccurrences(of: #"^```(?:json)?\s*\n?"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\n?```\s*$"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func transformTextStream(
    _ stream: AsyncThrowingStream<LanguageStreamPart, Error>,
    transform: @escaping @Sendable (String) -> String
) -> AsyncThrowingStream<LanguageStreamPart, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                var simpleBuffer = ""
                var blockBuffers: [String: String] = [:]
                var blockStarts: [String: LanguageStreamPart] = [:]

                func flushSimpleBuffer() {
                    guard !simpleBuffer.isEmpty else { return }
                    let transformed = transform(simpleBuffer)
                    simpleBuffer = ""
                    guard !transformed.isEmpty else { return }
                    continuation.yield(.textDelta(transformed))
                }

                for try await part in stream {
                    switch part {
                    case let .textStart(id, providerMetadata):
                        blockStarts[id] = .textStart(id: id, providerMetadata: providerMetadata)
                    case let .textDelta(delta):
                        simpleBuffer += delta
                    case let .textDeltaPart(id, delta, _):
                        blockBuffers[id, default: ""] += delta
                    case let .textEnd(id, providerMetadata):
                        let transformed = transform(blockBuffers[id] ?? "")
                        if let start = blockStarts[id] {
                            continuation.yield(start)
                        }
                        if !transformed.isEmpty {
                            continuation.yield(.textDeltaPart(id: id, delta: transformed))
                        }
                        continuation.yield(.textEnd(id: id, providerMetadata: providerMetadata))
                        blockBuffers[id] = nil
                        blockStarts[id] = nil
                    case .finish:
                        for id in blockBuffers.keys.sorted() {
                            let transformed = transform(blockBuffers[id] ?? "")
                            if let start = blockStarts[id] {
                                continuation.yield(start)
                            }
                            if !transformed.isEmpty {
                                continuation.yield(.textDeltaPart(id: id, delta: transformed))
                            }
                            continuation.yield(.textEnd(id: id))
                        }
                        blockBuffers.removeAll()
                        blockStarts.removeAll()
                        flushSimpleBuffer()
                        continuation.yield(part)
                    default:
                        continuation.yield(part)
                    }
                }
                flushSimpleBuffer()
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

private func extractTaggedSections(
    text: String,
    tagName: String,
    separator: String
) -> (reasoning: String, text: String)? {
    let openingTag = "<\(tagName)>"
    let closingTag = "</\(tagName)>"
    let pattern = NSRegularExpression.escapedPattern(for: openingTag)
        + "(.*?)"
        + NSRegularExpression.escapedPattern(for: closingTag)
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
        return nil
    }

    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let matches = regex.matches(in: text, range: range)
    guard !matches.isEmpty else {
        return nil
    }

    let reasoning = matches.compactMap { match -> String? in
        guard let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }.joined(separator: separator)

    var textWithoutReasoning = text
    for match in matches.reversed() {
        guard let matchRange = Range(match.range, in: textWithoutReasoning) else { continue }
        let before = String(textWithoutReasoning[..<matchRange.lowerBound])
        let after = String(textWithoutReasoning[matchRange.upperBound...])
        let joiner = (!before.isEmpty && !after.isEmpty) ? separator : ""
        textWithoutReasoning = before + joiner + after
    }

    return (reasoning: reasoning, text: textWithoutReasoning)
}

private func appendSeparated(_ existing: String, _ next: String, separator: String) -> String {
    guard !existing.isEmpty else { return next }
    guard !next.isEmpty else { return existing }
    return existing + separator + next
}

private func extractReasoningStream(
    _ stream: AsyncThrowingStream<LanguageStreamPart, Error>,
    tagName: String,
    separator: String,
    startWithReasoning: Bool
) -> AsyncThrowingStream<LanguageStreamPart, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                var textBuffer = ""
                var textID = "0"
                var sawTextPart = false

                func flushExtractedText() {
                    guard sawTextPart else { return }
                    let input = startWithReasoning ? "<\(tagName)>" + textBuffer : textBuffer
                    if let extracted = extractTaggedSections(text: input, tagName: tagName, separator: separator) {
                        if !extracted.reasoning.isEmpty {
                            continuation.yield(.reasoningStart(id: "reasoning-0"))
                            continuation.yield(.reasoningDeltaPart(id: "reasoning-0", delta: extracted.reasoning))
                            continuation.yield(.reasoningEnd(id: "reasoning-0"))
                        }
                        if !extracted.text.isEmpty {
                            continuation.yield(.textStart(id: textID))
                            continuation.yield(.textDeltaPart(id: textID, delta: extracted.text))
                            continuation.yield(.textEnd(id: textID))
                        }
                    } else if !textBuffer.isEmpty {
                        continuation.yield(.textStart(id: textID))
                        continuation.yield(.textDeltaPart(id: textID, delta: textBuffer))
                        continuation.yield(.textEnd(id: textID))
                    }
                    textBuffer = ""
                    sawTextPart = false
                }

                for try await part in stream {
                    switch part {
                    case let .textStart(id, _):
                        textID = id
                        sawTextPart = true
                    case let .textDelta(delta):
                        textBuffer += delta
                        sawTextPart = true
                    case let .textDeltaPart(id, delta, _):
                        textID = id
                        textBuffer += delta
                        sawTextPart = true
                    case .textEnd:
                        break
                    case .finish:
                        flushExtractedText()
                        continuation.yield(part)
                    default:
                        continuation.yield(part)
                    }
                }
                flushExtractedText()
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

private func toolWithInputExamplesInDescription(
    _ tool: JSONValue,
    prefix: String,
    remove: Bool,
    format: @Sendable (AIToolInputExampleFormatContext) -> String
) -> JSONValue {
    guard var object = tool.objectValue,
          let examples = object["inputExamples"]?.arrayValue,
          !examples.isEmpty else {
        return tool
    }

    let formattedExamples = examples.enumerated()
        .map { index, example in format(AIToolInputExampleFormatContext(example: example, index: index)) }
        .joined(separator: "\n")
    let examplesSection = prefix + "\n" + formattedExamples
    if let description = object["description"]?.stringValue, !description.isEmpty {
        object["description"] = .string(description + "\n\n" + examplesSection)
    } else {
        object["description"] = .string(examplesSection)
    }
    if remove {
        object.removeValue(forKey: "inputExamples")
    }
    return .object(object)
}

private func defaultFormatToolInputExample(_ context: AIToolInputExampleFormatContext) -> String {
    if let input = context.example["input"] {
        return compactJSONString(input)
    }
    return compactJSONString(context.example)
}

private func compactJSONString(_ value: JSONValue) -> String {
    guard let data = try? JSONEncoder().encode(value),
          let string = String(data: data, encoding: .utf8) else {
        return String(describing: value)
    }
    return string
}
