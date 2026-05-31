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

public func wrapProvider(
    _ provider: any AIProvider,
    languageModelMiddleware: AILanguageModelMiddleware
) -> any AIProvider {
    wrapProvider(provider, languageModelMiddleware: [languageModelMiddleware])
}

public func wrapProvider(
    _ provider: any AIProvider,
    languageModelMiddleware: [AILanguageModelMiddleware]
) -> any AIProvider {
    AIWrappedProvider(provider: provider, languageModelMiddleware: languageModelMiddleware)
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

private final class AIWrappedProvider: AIFileProvider, AISkillsProvider, @unchecked Sendable {
    private let provider: any AIProvider
    private let languageModelMiddleware: [AILanguageModelMiddleware]

    let providerID: String
    let supportedCapabilities: Set<ModelCapability>

    init(provider: any AIProvider, languageModelMiddleware: [AILanguageModelMiddleware]) {
        self.provider = provider
        self.languageModelMiddleware = languageModelMiddleware
        self.providerID = provider.providerID
        self.supportedCapabilities = provider.supportedCapabilities
    }

    func languageModel(_ modelID: String) throws -> any LanguageModel {
        wrapLanguageModel(try provider.languageModel(modelID), middleware: languageModelMiddleware)
    }

    func embeddingModel(_ modelID: String) throws -> any EmbeddingModel {
        try provider.embeddingModel(modelID)
    }

    func imageModel(_ modelID: String) throws -> any ImageModel {
        try provider.imageModel(modelID)
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
