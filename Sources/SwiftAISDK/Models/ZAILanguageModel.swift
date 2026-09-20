import Foundation

/// Z.AI's provider-specific chat model. It layers the published GLM option and
/// finish-reason behavior over SwiftAISDK's audited OpenAI-compatible runtime.
public final class ZAILanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String

    public let supportedURLs: [String: [AISupportedURLPattern]] = [
        "image/*": [ZAILanguageModel.remoteURLPattern],
        "video/*": [ZAILanguageModel.remoteURLPattern]
    ]

    private let config: ModelHTTPConfig
    private let resolveAPIKey: @Sendable () -> String?

    init(
        modelID: String,
        config: ModelHTTPConfig,
        resolveAPIKey: @escaping @Sendable () -> String?
    ) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
        self.resolveAPIKey = resolveAPIKey
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = try zaiPreparedRequest(request)
        let capture = ZAIRequestBodyCapture()
        var requestConfig = try authorizedConfig()
        let transform = requestConfig.transformRequestBody
        requestConfig.transformRequestBody = { body in
            let transformed = transform?(body) ?? body
            capture.record(transformed)
            return transformed
        }
        let base = OpenAICompatibleChatModel(modelID: modelID, config: requestConfig)
        var result = try await base.generate(prepared.request)
        result.finishReason = zaiFinishReason(
            unified: result.finishReason,
            raw: result.rawValue["choices"]?[0]?["finish_reason"]?.stringValue
        )
        result.usage = zaiUsage(from: result.rawValue)
        result.providerMetadata["zai"] = result.providerMetadata["zai"] ?? .object([:])
        result.warnings = prepared.baseWarnings + result.warnings + prepared.zaiWarnings
        if let body = capture.value {
            result.requestMetadata = aiRequestMetadata(
                body: .object(body),
                headers: request.headers
            )
        }
        return result
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        let prepared: ZAIPreparedRequest
        do {
            prepared = try zaiPreparedRequest(request)
            let base = try authorizedBase()
            var rawRequest = prepared.request
            rawRequest.includeRawChunks = true
            return wrappedStream(
                base.stream(rawRequest),
                originalRequest: request,
                prepared: prepared
            )
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    private func wrappedStream(
        _ upstream: AsyncThrowingStream<LanguageStreamPart, Error>,
        originalRequest request: LanguageModelRequest,
        prepared: ZAIPreparedRequest
    ) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var rawFinishReason: String?
                    var latestUsage: TokenUsage?

                    for try await part in upstream {
                        switch part {
                        case let .streamStart(warnings):
                            continuation.yield(.streamStart(
                                warnings: prepared.baseWarnings + warnings + prepared.zaiWarnings
                            ))
                        case let .raw(raw):
                            if let reason = raw["choices"]?[0]?["finish_reason"]?.stringValue {
                                rawFinishReason = reason
                            }
                            if raw["usage"] != nil, raw["usage"] != .null {
                                latestUsage = zaiUsage(from: raw)
                            }
                            if request.includeRawChunks {
                                continuation.yield(.raw(raw))
                            }
                        case let .finishMetadata(reason, _, providerMetadata):
                            var providerMetadata = providerMetadata
                            providerMetadata["zai"] = providerMetadata["zai"] ?? .object([:])
                            continuation.yield(.finishMetadata(
                                reason: zaiFinishReason(unified: reason, raw: rawFinishReason),
                                usage: latestUsage ?? TokenUsage(),
                                providerMetadata: providerMetadata
                            ))
                        case let .finish(reason, _):
                            continuation.yield(.finish(
                                reason: zaiFinishReason(unified: reason, raw: rawFinishReason),
                                usage: latestUsage ?? TokenUsage()
                            ))
                        default:
                            continuation.yield(part)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func authorizedBase() throws -> OpenAICompatibleChatModel {
        OpenAICompatibleChatModel(modelID: modelID, config: try authorizedConfig())
    }

    private func authorizedConfig() throws -> ModelHTTPConfig {
        var authorizedConfig = config
        guard let apiKey = resolveAPIKey() else {
            throw AIError.missingAPIKey(
                provider: "zai",
                environmentVariables: ["ZAI_API_KEY"]
            )
        }
        if authorizedConfig.headers["authorization"] == nil {
            authorizedConfig.headers["authorization"] = "Bearer \(apiKey)"
        }
        return authorizedConfig
    }

    private static let remoteURLPattern = AISupportedURLPattern { value in
        let normalized = value.lowercased()
        return normalized.hasPrefix("https://") || normalized.hasPrefix("http://")
    }
}

private final class ZAIRequestBodyCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var body: [String: JSONValue]?

    var value: [String: JSONValue]? {
        lock.lock()
        defer { lock.unlock() }
        return body
    }

    func record(_ value: [String: JSONValue]) {
        lock.lock()
        body = value
        lock.unlock()
    }
}

private struct ZAIPreparedRequest {
    var request: LanguageModelRequest
    var baseWarnings: [AIWarning]
    var zaiWarnings: [AIWarning]
}

private func zaiPreparedRequest(_ request: LanguageModelRequest) throws -> ZAIPreparedRequest {
    var normalized = request
    var baseWarnings: [AIWarning] = []
    var zaiWarnings: [AIWarning] = []

    if request.topK != nil {
        baseWarnings.append(AIWarning(type: "unsupported", feature: "topK"))
    }
    if case let .json(schema, _, _)? = request.responseFormat, schema != nil {
        baseWarnings.append(AIWarning(
            type: "unsupported",
            feature: "responseFormat",
            message: "JSON response format schema is only supported with structuredOutputs"
        ))
    }
    if request.frequencyPenalty != nil {
        zaiWarnings.append(AIWarning(type: "unsupported", feature: "frequencyPenalty"))
        normalized.frequencyPenalty = nil
    }
    if request.presencePenalty != nil {
        zaiWarnings.append(AIWarning(type: "unsupported", feature: "presencePenalty"))
        normalized.presencePenalty = nil
    }
    if request.seed != nil {
        zaiWarnings.append(AIWarning(type: "unsupported", feature: "seed"))
        normalized.seed = nil
    }

    var providerOptions = request.providerOptions
    providerOptions.removeValue(forKey: "zai.chat")
    providerOptions.removeValue(forKey: "zaiChat")
    if let rawOptions = providerOptions["zai"] {
        if rawOptions == .null {
            providerOptions.removeValue(forKey: "zai")
        } else {
            guard let object = rawOptions.objectValue else {
                throw zaiInvalidProviderOptions()
            }
            providerOptions["zai"] = .object(try zaiValidatedProviderOptions(object))
        }
    }
    normalized.providerOptions = providerOptions

    if let toolChoiceType = zaiToolChoiceType(request.toolChoice) {
        if toolChoiceType == "none" {
            normalized.tools = [:]
            normalized.toolChoice = nil
        } else if toolChoiceType != "auto" {
            zaiWarnings.append(AIWarning(
                type: "unsupported",
                feature: "toolChoice \(toolChoiceType)",
                message: "Z.AI currently supports only automatic tool selection."
            ))
            normalized.toolChoice = nil
        }
    }

    return ZAIPreparedRequest(
        request: normalized,
        baseWarnings: baseWarnings,
        zaiWarnings: zaiWarnings
    )
}

private let zaiProviderOptionKeys: Set<String> = [
    "doSample", "thinking", "reasoningEffort", "toolStream", "requestId", "userId"
]

private func zaiValidatedProviderOptions(
    _ options: [String: JSONValue]
) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where zaiProviderOptionKeys.contains(key) {
        guard value != .null else { throw zaiInvalidProviderOptions() }
        switch key {
        case "doSample", "toolStream":
            guard value.boolValue != nil else { throw zaiInvalidProviderOptions() }
            output[key] = value
        case "thinking":
            guard let thinking = value.objectValue else { throw zaiInvalidProviderOptions() }
            var validated: [String: JSONValue] = [:]
            if let type = thinking["type"] {
                guard let typeValue = type.stringValue,
                      typeValue == "enabled" || typeValue == "disabled" else {
                    throw zaiInvalidProviderOptions()
                }
                validated["type"] = type
            }
            if let clearThinking = thinking["clearThinking"] {
                guard clearThinking.boolValue != nil else { throw zaiInvalidProviderOptions() }
                validated["clearThinking"] = clearThinking
            }
            output[key] = .object(validated)
        case "reasoningEffort":
            guard let effort = value.stringValue,
                  ["none", "minimal", "low", "medium", "high", "xhigh", "max"].contains(effort) else {
                throw zaiInvalidProviderOptions()
            }
            output[key] = value
        case "requestId":
            guard let identifier = value.stringValue,
                  (6...64).contains(identifier.count) else {
                throw zaiInvalidProviderOptions()
            }
            output[key] = value
        case "userId":
            guard let identifier = value.stringValue,
                  (6...128).contains(identifier.count) else {
                throw zaiInvalidProviderOptions()
            }
            output[key] = value
        default:
            break
        }
    }
    return output
}

private func zaiInvalidProviderOptions() -> AIError {
    .invalidArgument(
        argument: "providerOptions",
        message: "invalid zai provider options"
    )
}

private func zaiToolChoiceType(_ value: JSONValue?) -> String? {
    value?.stringValue ?? value?["type"]?.stringValue
}

func zaiTransformRequestBody(_ body: [String: JSONValue]) -> [String: JSONValue] {
    var output = body

    output.removeValue(forKey: "frequency_penalty")
    output.removeValue(forKey: "presence_penalty")
    output.removeValue(forKey: "seed")
    output.removeValue(forKey: "user")
    output.removeValue(forKey: "verbosity")

    if let value = output.removeValue(forKey: "doSample") {
        output["do_sample"] = value
    }
    if let thinkingValue = output.removeValue(forKey: "thinking") {
        let thinking = thinkingValue.objectValue ?? [:]
        var transformed: [String: JSONValue] = [:]
        if let type = thinking["type"] {
            transformed["type"] = type
        }
        if let clearThinking = thinking["clearThinking"] {
            transformed["clear_thinking"] = clearThinking
        }
        output["thinking"] = .object(transformed)
    }
    if let value = output.removeValue(forKey: "toolStream") {
        output["tool_stream"] = value
    }
    if let value = output.removeValue(forKey: "requestId") {
        output["request_id"] = value
    }
    if let value = output.removeValue(forKey: "userId") {
        output["user_id"] = value
    }

    return output
}

private func zaiFinishReason(unified: String?, raw: String?) -> String? {
    switch raw {
    case "sensitive":
        return "content-filter"
    case "model_context_window_exceeded":
        return "length"
    case "network_error":
        return "error"
    default:
        return unified
    }
}

private func zaiUsage(from raw: JSONValue) -> TokenUsage {
    guard let usage = raw["usage"], usage != .null else {
        return TokenUsage()
    }
    let inputTokens = usage["prompt_tokens"]?.intValue ?? 0
    let outputTokens = usage["completion_tokens"]?.intValue ?? 0
    let cacheReadTokens = usage["prompt_tokens_details"]?["cached_tokens"]?.intValue ?? 0
    let reasoningTokens = usage["completion_tokens_details"]?["reasoning_tokens"]?.intValue ?? 0
    return TokenUsage(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        totalTokens: usage["total_tokens"]?.intValue ?? inputTokens + outputTokens,
        inputTokensNoCache: inputTokens - cacheReadTokens,
        inputTokensCacheRead: cacheReadTokens,
        outputTextTokens: max(0, outputTokens - reasoningTokens),
        outputReasoningTokens: reasoningTokens,
        rawValue: usage
    )
}
