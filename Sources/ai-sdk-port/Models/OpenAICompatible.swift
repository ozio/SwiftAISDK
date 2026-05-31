import Foundation

public enum OpenAITools {
    public static func applyPatch() -> JSONValue {
        providerTool(id: "openai.apply_patch", name: "apply_patch")
    }

    public static func customTool(name: String, description: String? = nil, format: JSONValue? = nil) -> JSONValue {
        providerTool(id: "openai.custom", name: name, args: JSONValue.object([
            "description": description.map(JSONValue.string),
            "format": format
        ]).objectValue ?? [:])
    }

    public static func codeInterpreter(container: JSONValue? = nil) -> JSONValue {
        providerTool(id: "openai.code_interpreter", name: "code_interpreter", args: JSONValue.object([
            "container": container
        ]).objectValue ?? [:])
    }

    public static func fileSearch(vectorStoreIDs: [String], maxNumResults: Int? = nil, ranking: JSONValue? = nil, filters: JSONValue? = nil) -> JSONValue {
        providerTool(id: "openai.file_search", name: "file_search", args: JSONValue.object([
            "vectorStoreIds": .array(vectorStoreIDs),
            "maxNumResults": maxNumResults.map { .number(Double($0)) },
            "ranking": ranking,
            "filters": filters
        ]).objectValue ?? [:])
    }

    public static func imageGeneration(
        background: String? = nil,
        inputFidelity: String? = nil,
        inputImageMask: JSONValue? = nil,
        model: String? = nil,
        moderation: String? = nil,
        outputCompression: Int? = nil,
        outputFormat: String? = nil,
        partialImages: Int? = nil,
        quality: String? = nil,
        size: String? = nil
    ) -> JSONValue {
        providerTool(id: "openai.image_generation", name: "image_generation", args: JSONValue.object([
            "background": background.map(JSONValue.string),
            "inputFidelity": inputFidelity.map(JSONValue.string),
            "inputImageMask": inputImageMask,
            "model": model.map(JSONValue.string),
            "moderation": moderation.map(JSONValue.string),
            "outputCompression": outputCompression.map { .number(Double($0)) },
            "outputFormat": outputFormat.map(JSONValue.string),
            "partialImages": partialImages.map { .number(Double($0)) },
            "quality": quality.map(JSONValue.string),
            "size": size.map(JSONValue.string)
        ]).objectValue ?? [:])
    }

    public static func localShell() -> JSONValue {
        providerTool(id: "openai.local_shell", name: "local_shell")
    }

    public static func shell(environment: JSONValue? = nil) -> JSONValue {
        providerTool(id: "openai.shell", name: "shell", args: JSONValue.object([
            "environment": environment
        ]).objectValue ?? [:])
    }

    public static func webSearchPreview(searchContextSize: String? = nil, userLocation: JSONValue? = nil) -> JSONValue {
        providerTool(id: "openai.web_search_preview", name: "web_search_preview", args: JSONValue.object([
            "searchContextSize": searchContextSize.map(JSONValue.string),
            "userLocation": userLocation
        ]).objectValue ?? [:])
    }

    public static func webSearch(
        filters: JSONValue? = nil,
        externalWebAccess: Bool? = nil,
        searchContextSize: String? = nil,
        userLocation: JSONValue? = nil
    ) -> JSONValue {
        providerTool(id: "openai.web_search", name: "web_search", args: JSONValue.object([
            "filters": filters,
            "externalWebAccess": externalWebAccess.map(JSONValue.bool),
            "searchContextSize": searchContextSize.map(JSONValue.string),
            "userLocation": userLocation
        ]).objectValue ?? [:])
    }

    public static func mcp(
        serverLabel: String,
        allowedTools: JSONValue? = nil,
        authorization: String? = nil,
        connectorID: String? = nil,
        headers: JSONValue? = nil,
        requireApproval: JSONValue? = nil,
        serverDescription: String? = nil,
        serverURL: String? = nil
    ) -> JSONValue {
        providerTool(id: "openai.mcp", name: "mcp", args: JSONValue.object([
            "serverLabel": .string(serverLabel),
            "allowedTools": allowedTools,
            "authorization": authorization.map(JSONValue.string),
            "connectorId": connectorID.map(JSONValue.string),
            "headers": headers,
            "requireApproval": requireApproval,
            "serverDescription": serverDescription.map(JSONValue.string),
            "serverUrl": serverURL.map(JSONValue.string)
        ]).objectValue ?? [:])
    }

    public static func toolSearch(execution: JSONValue? = nil, description: String? = nil, parameters: JSONValue? = nil) -> JSONValue {
        providerTool(id: "openai.tool_search", name: "tool_search", args: JSONValue.object([
            "execution": execution,
            "description": description.map(JSONValue.string),
            "parameters": parameters
        ]).objectValue ?? [:])
    }

    static func providerTool(id: String, name: String, args: [String: JSONValue] = [:]) -> JSONValue {
        .object([
            "type": .string("provider"),
            "id": .string(id),
            "name": .string(name),
            "args": .object(args)
        ])
    }
}

public enum AzureOpenAITools {
    public static func codeInterpreter(container: JSONValue? = nil) -> JSONValue {
        OpenAITools.codeInterpreter(container: container)
    }

    public static func fileSearch(vectorStoreIDs: [String], maxNumResults: Int? = nil, ranking: JSONValue? = nil, filters: JSONValue? = nil) -> JSONValue {
        OpenAITools.fileSearch(vectorStoreIDs: vectorStoreIDs, maxNumResults: maxNumResults, ranking: ranking, filters: filters)
    }

    public static func imageGeneration(
        background: String? = nil,
        inputFidelity: String? = nil,
        inputImageMask: JSONValue? = nil,
        model: String? = nil,
        moderation: String? = nil,
        outputCompression: Int? = nil,
        outputFormat: String? = nil,
        partialImages: Int? = nil,
        quality: String? = nil,
        size: String? = nil
    ) -> JSONValue {
        OpenAITools.imageGeneration(
            background: background,
            inputFidelity: inputFidelity,
            inputImageMask: inputImageMask,
            model: model,
            moderation: moderation,
            outputCompression: outputCompression,
            outputFormat: outputFormat,
            partialImages: partialImages,
            quality: quality,
            size: size
        )
    }

    public static func webSearch(filters: JSONValue? = nil, externalWebAccess: Bool? = nil, searchContextSize: String? = nil, userLocation: JSONValue? = nil) -> JSONValue {
        OpenAITools.webSearch(filters: filters, externalWebAccess: externalWebAccess, searchContextSize: searchContextSize, userLocation: userLocation)
    }

    public static func webSearchPreview(searchContextSize: String? = nil, userLocation: JSONValue? = nil) -> JSONValue {
        OpenAITools.webSearchPreview(searchContextSize: searchContextSize, userLocation: userLocation)
    }
}

public enum AuthorizationStyle: Equatable, Hashable, Sendable {
    case bearer(environmentVariables: [String])
    case token(environmentVariables: [String])
    case apiKeyHeader(name: String, prefix: String? = nil, environmentVariables: [String])
    case none
}

public struct ProviderSettings: Sendable {
    public var apiKey: String?
    public var baseURL: String?
    public var organization: String?
    public var project: String?
    public var headers: [String: String]
    public var queryParams: [String: String]
    public var transport: any AITransport
    public var includeUsage: Bool
    public var supportsStructuredOutputs: Bool
    public var maxEmbeddingsPerCall: Int?
    public var transformRequestBody: (@Sendable ([String: JSONValue]) -> [String: JSONValue])?

    public init(
        apiKey: String? = nil,
        baseURL: String? = nil,
        organization: String? = nil,
        project: String? = nil,
        headers: [String: String] = [:],
        queryParams: [String: String] = [:],
        transport: any AITransport = URLSessionTransport.shared,
        includeUsage: Bool = false,
        supportsStructuredOutputs: Bool = false,
        maxEmbeddingsPerCall: Int? = nil,
        transformRequestBody: (@Sendable ([String: JSONValue]) -> [String: JSONValue])? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.organization = organization
        self.project = project
        self.headers = headers
        self.queryParams = queryParams
        self.transport = transport
        self.includeUsage = includeUsage
        self.supportsStructuredOutputs = supportsStructuredOutputs
        self.maxEmbeddingsPerCall = maxEmbeddingsPerCall
        self.transformRequestBody = transformRequestBody
    }
}

struct ModelHTTPConfig: @unchecked Sendable {
    var providerID: String
    var baseURL: String
    var headers: [String: String]
    var transport: any AITransport
    var includeUsage: Bool
    var queryParams: [String: String]
    var supportsStructuredOutputs: Bool
    var maxEmbeddingsPerCall: Int?
    var transformRequestBody: (@Sendable ([String: JSONValue]) -> [String: JSONValue])?
    var url: @Sendable (String, String) throws -> URL

    init(
        providerID: String,
        baseURL: String,
        headers: [String: String],
        transport: any AITransport,
        includeUsage: Bool = false,
        queryParams: [String: String] = [:],
        supportsStructuredOutputs: Bool = false,
        maxEmbeddingsPerCall: Int? = nil,
        transformRequestBody: (@Sendable ([String: JSONValue]) -> [String: JSONValue])? = nil,
        url: (@Sendable (String, String) throws -> URL)? = nil
    ) {
        self.providerID = providerID
        let normalizedBaseURL = withoutTrailingSlash(baseURL)
        self.baseURL = normalizedBaseURL
        self.headers = headers
        self.transport = transport
        self.includeUsage = includeUsage
        self.queryParams = queryParams
        self.supportsStructuredOutputs = supportsStructuredOutputs
        self.maxEmbeddingsPerCall = maxEmbeddingsPerCall
        self.transformRequestBody = transformRequestBody
        self.url = url ?? { _, path in
            try openAICompatibleURL("\(normalizedBaseURL)\(path)", queryParams: queryParams)
        }
    }

    func request(path: String, modelID: String, body: JSONValue, headers requestHeaders: [String: String] = [:]) throws -> AIHTTPRequest {
        try rawRequest(
            path: path,
            modelID: modelID,
            body: try encodeJSONBody(body),
            contentType: "application/json",
            headers: requestHeaders
        )
    }

    func rawRequest(path: String, modelID: String, body: Data, contentType: String?, headers requestHeaders: [String: String] = [:]) throws -> AIHTTPRequest {
        var headers = self.headers.mergingHeaders(requestHeaders)
        if let contentType {
            headers["content-type"] = headers["content-type"] ?? contentType
        }
        headers["user-agent"] = headers["user-agent"] ?? userAgent(providerID)
        return AIHTTPRequest(
            method: "POST",
            url: try url(modelID, path),
            headers: headers,
            body: body
        )
    }

    func sendJSON(path: String, modelID: String, body: JSONValue, headers: [String: String] = [:]) async throws -> JSONValue {
        let response = try await transport.send(request(path: path, modelID: modelID, body: body, headers: headers))
        guard (200..<300).contains(response.statusCode) else {
            throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
        }
        return try response.jsonValue()
    }

    func withProviderID(_ providerID: String) -> ModelHTTPConfig {
        ModelHTTPConfig(
            providerID: providerID,
            baseURL: baseURL,
            headers: headers,
            transport: transport,
            includeUsage: includeUsage,
            queryParams: queryParams,
            supportsStructuredOutputs: supportsStructuredOutputs,
            maxEmbeddingsPerCall: maxEmbeddingsPerCall,
            transformRequestBody: transformRequestBody,
            url: url
        )
    }
}

private func openAICompatibleURL(_ string: String, queryParams: [String: String]) throws -> URL {
    guard !queryParams.isEmpty else { return try requireURL(string) }
    guard var components = URLComponents(string: string) else { throw AIError.invalidURL(string) }
    var items = components.queryItems ?? []
    for key in queryParams.keys.sorted() {
        items.append(URLQueryItem(name: key, value: queryParams[key]))
    }
    components.queryItems = items
    guard let url = components.url else { throw AIError.invalidURL(string) }
    return url
}

public final class OpenAICompatibleChatModel: LanguageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let warnings = isOpenAIBackedProvider(providerID)
            ? []
            : openAICompatibleProviderOptionWarnings(from: request.extraBody, providerID: providerID, includeCompatibilityNamespace: true)
        let raw = try await config.sendJSON(path: "/chat/completions", modelID: modelID, body: .object(body(for: request, stream: false)), headers: request.headers)
        let choice = raw["choices"]?[0]
        let toolCalls = openAICompatibleChatToolCalls(from: choice?["message"]?["tool_calls"])
        let text = choice?["message"]?["content"]?.stringValue
            ?? choice?["text"]?.stringValue
            ?? raw["output_text"]?.stringValue
            ?? raw["text"]?.stringValue
        guard let text = text ?? (toolCalls.isEmpty ? nil : "") else {
            throw AIError.invalidResponse(provider: providerID, message: "No text content found in chat completion response.")
        }
        return TextGenerationResult(
            text: text,
            finishReason: openAICompatibleFinishReason(choice?["finish_reason"]?.stringValue),
            usage: usage(from: raw),
            toolCalls: toolCalls,
            rawValue: raw,
            warnings: warnings
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let body = JSONValue.object(body(for: request, stream: true))
                    let httpRequest = try config.request(path: "/chat/completions", modelID: modelID, body: body, headers: request.headers)
                    let response = try await config.transport.send(httpRequest)
                    guard (200..<300).contains(response.statusCode) else {
                        throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
                    }
                    var toolCalls = OpenAICompatibleStreamingToolCalls()
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        continuation.yield(.raw(raw))
                        let choice = raw["choices"]?[0]
                        let delta = choice?["delta"]
                        if let reasoning = delta?["reasoning_content"]?.stringValue ?? delta?["reasoning"]?.stringValue {
                            continuation.yield(.reasoningDelta(reasoning))
                        }
                        if let delta = delta?["content"]?.stringValue {
                            continuation.yield(.textDelta(delta))
                        }
                        if let toolCallDeltas = delta?["tool_calls"]?.arrayValue {
                            for toolCallDelta in toolCallDeltas {
                                let update = toolCalls.apply(delta: toolCallDelta)
                                continuation.yield(.toolCallDelta(
                                    id: update.id,
                                    name: update.name,
                                    argumentsDelta: update.argumentsDelta,
                                    index: update.index
                                ))
                            }
                        }
                        if let reason = choice?["finish_reason"]?.stringValue {
                            for toolCall in toolCalls.finishedCalls() {
                                continuation.yield(.toolCall(toolCall))
                            }
                            continuation.yield(.finish(reason: openAICompatibleFinishReason(reason), usage: usage(from: raw)))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func body(for request: LanguageModelRequest, stream: Bool) -> [String: JSONValue] {
        var body = Self.body(
            for: request,
            modelID: modelID,
            providerID: providerID,
            stream: stream,
            unwrapOpenAIProviderOptions: isOpenAIBackedProvider(providerID),
            supportsStructuredOutputs: config.supportsStructuredOutputs
        )
        if stream, config.includeUsage {
            body["stream_options"] = .object(["include_usage": .bool(true)])
        }
        if openAICompatibleProviderRoot(providerID) == "fireworks" {
            body = fireworksChatBody(from: body)
        }
        if openAICompatibleProviderRoot(providerID) == "moonshotai" {
            body = moonshotChatBody(from: body)
        }
        if providerID == "googleVertex.xai" {
            body.removeValue(forKey: "reasoning_effort")
        }
        if providerID.hasPrefix("xai.") {
            if let topLogprobs = body.removeValue(forKey: "topLogprobs") {
                body["top_logprobs"] = topLogprobs
            }
        }
        return config.transformRequestBody?(body) ?? body
    }

    private func usage(from raw: JSONValue) -> TokenUsage? {
        openAICompatibleProviderRoot(providerID) == "moonshotai" ? moonshotChatUsage(from: raw) : tokenUsage(from: raw)
    }

    private static func body(
        for request: LanguageModelRequest,
        modelID: String,
        providerID: String,
        stream: Bool,
        unwrapOpenAIProviderOptions: Bool,
        supportsStructuredOutputs: Bool
    ) -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "messages": .array(request.messages.map(Self.messageJSON))
        ]
        if stream { body["stream"] = true }
        if let temperature = request.temperature { body["temperature"] = .number(temperature) }
        if let topP = request.topP { body["top_p"] = .number(topP) }
        if let maxOutputTokens = request.maxOutputTokens { body["max_tokens"] = .number(Double(maxOutputTokens)) }
        if !request.stopSequences.isEmpty { body["stop"] = .array(request.stopSequences) }
        let tools = openAICompatibleChatTools(from: request.tools)
        if !tools.isEmpty {
            body["tools"] = .array(tools)
            if let toolChoice = openAICompatibleChatToolChoice(from: request.extraBody["toolChoice"]) {
                body["tool_choice"] = toolChoice
            }
        }
        let extraBody = unwrapOpenAIProviderOptions
            ? openAIProviderOptions(from: request.extraBody, providerID: providerID)
            : openAICompatibleProviderOptions(from: request.extraBody, providerID: providerID, includeCompatibilityNamespace: true)
        body.merge(openAICompatibleChatOptions(from: extraBody, supportsStructuredOutputs: supportsStructuredOutputs)) { _, new in new }
        return body
    }

    static func messageJSON(_ message: AIMessage) -> JSONValue {
        let textOnly = message.content.allSatisfy {
            if case .text = $0 { true } else { false }
        }

        if textOnly {
            return .object([
                "role": .string(message.role.rawValue),
                "content": .string(message.combinedText)
            ])
        }

        let parts: [JSONValue] = message.content.map { part in
            switch part {
            case let .text(text):
                return .object(["type": .string("text"), "text": .string(text)])
            case let .imageURL(url):
                return .object(["type": .string("image_url"), "image_url": .object(["url": .string(url)])])
            case let .data(mimeType, data), let .file(mimeType, data, _):
                return .object([
                    "type": .string("image_url"),
                    "image_url": .object(["url": .string("data:\(mimeType);base64,\(data.base64EncodedString())")])
                ])
            }
        }

        return .object([
            "role": .string(message.role.rawValue),
            "content": .array(parts)
        ])
    }
}

private func fireworksChatBody(from input: [String: JSONValue]) -> [String: JSONValue] {
    var body = input

    if let value = body.removeValue(forKey: "reasoningEffort") {
        body["reasoning_effort"] = value
    }

    if let effort = body["reasoning_effort"]?.stringValue {
        body["reasoning_effort"] = .string(fireworksReasoningEffort(effort))
    }

    if let thinking = body.removeValue(forKey: "thinking")?.objectValue {
        var converted: [String: JSONValue] = [:]
        if let type = thinking["type"] { converted["type"] = type }
        if let budgetTokens = thinking["budgetTokens"] {
            converted["budget_tokens"] = budgetTokens
        } else if let budgetTokens = thinking["budget_tokens"] {
            converted["budget_tokens"] = budgetTokens
        }
        body["thinking"] = .object(converted)
    }

    if let reasoningHistory = body.removeValue(forKey: "reasoningHistory") {
        body["reasoning_history"] = reasoningHistory
    }

    return body
}

private func fireworksReasoningEffort(_ value: String) -> String {
    switch value {
    case "minimal":
        return "low"
    case "xhigh":
        return "high"
    default:
        return value
    }
}

private func moonshotChatBody(from input: [String: JSONValue]) -> [String: JSONValue] {
    var body = input
    if let nested = body.removeValue(forKey: "moonshotai")?.objectValue {
        body.merge(nested) { _, nested in nested }
    }
    if let nested = body.removeValue(forKey: "moonshotAI")?.objectValue {
        body.merge(nested) { _, nested in nested }
    }

    if let thinking = body.removeValue(forKey: "thinking")?.objectValue {
        var converted: [String: JSONValue] = [:]
        if let type = thinking["type"] { converted["type"] = type }
        if let budgetTokens = thinking["budgetTokens"] {
            converted["budget_tokens"] = budgetTokens
        } else if let budgetTokens = thinking["budget_tokens"] {
            converted["budget_tokens"] = budgetTokens
        }
        body["thinking"] = .object(converted)
    }

    if let reasoningHistory = body.removeValue(forKey: "reasoningHistory") {
        body["reasoning_history"] = reasoningHistory
    }

    return body
}

private func moonshotChatUsage(from raw: JSONValue) -> TokenUsage? {
    guard let usage = raw["usage"] else { return nil }
    let inputTokens = usage["prompt_tokens"]?.intValue ?? usage["input_tokens"]?.intValue
    let outputTokens = usage["completion_tokens"]?.intValue ?? usage["output_tokens"]?.intValue
    let totalTokens = usage["total_tokens"]?.intValue ?? {
        guard let inputTokens, let outputTokens else { return nil }
        return inputTokens + outputTokens
    }()
    return TokenUsage(inputTokens: inputTokens, outputTokens: outputTokens, totalTokens: totalTokens)
}

private func openAICompatibleChatTools(from tools: [String: JSONValue]) -> [JSONValue] {
    tools.compactMap { name, schema in
        let object = schema.objectValue
        if object?["type"]?.stringValue == "provider" || object?["id"]?.stringValue != nil {
            return nil
        }
        var parameters = schema
        var function: [String: JSONValue] = [
            "name": .string(name),
            "parameters": parameters
        ]
        if var parameterObject = parameters.objectValue {
            if let description = parameterObject["description"]?.stringValue {
                function["description"] = .string(description)
            }
            if let strict = parameterObject.removeValue(forKey: "strict") {
                function["strict"] = strict
                parameters = .object(parameterObject)
                function["parameters"] = parameters
            }
        }
        return .object([
            "type": .string("function"),
            "function": .object(function)
        ])
    }
}

private func openAICompatibleChatToolChoice(from value: JSONValue?) -> JSONValue? {
    if let string = value?.stringValue {
        switch string {
        case "auto", "none", "required":
            return .string(string)
        default:
            return nil
        }
    }
    guard let object = value?.objectValue else { return nil }
    switch object["type"]?.stringValue {
    case "auto", "none", "required":
        return object["type"]
    case "tool":
        guard let toolName = object["toolName"]?.stringValue ?? object["tool_name"]?.stringValue else {
            return nil
        }
        return .object([
            "type": .string("function"),
            "function": .object(["name": .string(toolName)])
        ])
    default:
        return nil
    }
}

private func openAICompatibleChatOptions(from extraBody: [String: JSONValue], supportsStructuredOutputs: Bool) -> [String: JSONValue] {
    var output = extraBody
    output.removeValue(forKey: "toolChoice")
    if let reasoningEffort = output.removeValue(forKey: "reasoningEffort") {
        output["reasoning_effort"] = reasoningEffort
    }
    if let textVerbosity = output.removeValue(forKey: "textVerbosity") {
        output["verbosity"] = textVerbosity
    }
    if let responseFormat = output.removeValue(forKey: "responseFormat") {
        if let mapped = openAICompatibleResponseFormat(from: responseFormat, supportsStructuredOutputs: supportsStructuredOutputs, strictJsonSchema: output.removeValue(forKey: "strictJsonSchema")) {
            output["response_format"] = mapped
        }
    } else {
        output.removeValue(forKey: "strictJsonSchema")
    }
    return output
}

private func openAICompatibleResponseFormat(from value: JSONValue, supportsStructuredOutputs: Bool, strictJsonSchema: JSONValue?) -> JSONValue? {
    guard let object = value.objectValue else {
        return value
    }
    guard object["type"]?.stringValue == "json" else {
        return value
    }
    guard supportsStructuredOutputs, let schema = object["schema"] else {
        return .object(["type": .string("json_object")])
    }
    var jsonSchema: [String: JSONValue] = [
        "schema": schema,
        "strict": strictJsonSchema ?? .bool(true),
        "name": object["name"] ?? .string("response")
    ]
    if let description = object["description"] {
        jsonSchema["description"] = description
    }
    return .object([
        "type": .string("json_schema"),
        "json_schema": .object(jsonSchema)
    ])
}

private struct OpenAICompatibleToolCallBuffer {
    var id: String?
    var name: String?
    var arguments: String = ""
    var rawValue: JSONValue?
}

private struct OpenAICompatibleStreamingToolCalls {
    private var buffers: [Int: OpenAICompatibleToolCallBuffer] = [:]

    mutating func apply(delta: JSONValue) -> (id: String?, name: String?, argumentsDelta: String, index: Int?) {
        let index = delta["index"]?.intValue ?? 0
        var buffer = buffers[index] ?? OpenAICompatibleToolCallBuffer()
        if let id = delta["id"]?.stringValue {
            buffer.id = id
        }
        if let name = delta["function"]?["name"]?.stringValue {
            buffer.name = name
        }
        let argumentsDelta = delta["function"]?["arguments"]?.stringValue ?? ""
        if !argumentsDelta.isEmpty {
            buffer.arguments += argumentsDelta
        }
        buffer.rawValue = delta
        buffers[index] = buffer
        return (buffer.id, buffer.name, argumentsDelta, index)
    }

    func finishedCalls() -> [AIToolCall] {
        buffers.keys.sorted().compactMap { index in
            guard let buffer = buffers[index], let name = buffer.name else { return nil }
            return AIToolCall(
                id: buffer.id ?? "tool-call-\(index)",
                name: name,
                arguments: buffer.arguments,
                rawValue: buffer.rawValue
            )
        }
    }
}

private func openAICompatibleChatToolCalls(from value: JSONValue?) -> [AIToolCall] {
    value?.arrayValue?.enumerated().compactMap { index, item in
        guard let name = item["function"]?["name"]?.stringValue else { return nil }
        return AIToolCall(
            id: item["id"]?.stringValue ?? "tool-call-\(index)",
            name: name,
            arguments: item["function"]?["arguments"]?.stringValue ?? "",
            rawValue: item
        )
    } ?? []
}

private func openAICompatibleFinishReason(_ reason: String?) -> String? {
    switch reason {
    case "stop":
        return "stop"
    case "length":
        return "length"
    case "content_filter":
        return "content-filter"
    case "tool_calls", "function_call":
        return "tool-calls"
    case nil:
        return nil
    default:
        return "other"
    }
}

public final class OpenAICompatibleCompletionModel: LanguageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let warnings = isOpenAIBackedProvider(providerID)
            ? []
            : openAICompatibleProviderOptionWarnings(from: request.extraBody, providerID: providerID, includeCompatibilityNamespace: false)
        let body = body(for: request, stream: false)
        let raw = try await config.sendJSON(path: "/completions", modelID: modelID, body: .object(body), headers: request.headers)
        guard let text = raw["choices"]?[0]?["text"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "No text found in completion response.")
        }
        return TextGenerationResult(text: text, finishReason: raw["choices"]?[0]?["finish_reason"]?.stringValue, usage: tokenUsage(from: raw), rawValue: raw, warnings: warnings)
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let body = JSONValue.object(body(for: request, stream: true))
                    let httpRequest = try config.request(path: "/completions", modelID: modelID, body: body, headers: request.headers)
                    let response = try await config.transport.send(httpRequest)
                    guard (200..<300).contains(response.statusCode) else {
                        throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
                    }
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        continuation.yield(.raw(raw))
                        let choice = raw["choices"]?[0]
                        if let delta = choice?["text"]?.stringValue {
                            continuation.yield(.textDelta(delta))
                        }
                        if let reason = choice?["finish_reason"]?.stringValue {
                            continuation.yield(.finish(reason: openAICompatibleFinishReason(reason), usage: tokenUsage(from: raw)))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func body(for request: LanguageModelRequest, stream: Bool) -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "prompt": .string(request.messages.map(\.combinedText).joined(separator: "\n"))
        ]
        if stream { body["stream"] = .bool(true) }
        if stream, config.includeUsage { body["stream_options"] = .object(["include_usage": .bool(true)]) }
        if let temperature = request.temperature { body["temperature"] = .number(temperature) }
        if let maxOutputTokens = request.maxOutputTokens { body["max_tokens"] = .number(Double(maxOutputTokens)) }
        let extraBody = isOpenAIBackedProvider(providerID)
            ? openAICompletionProviderOptions(from: request.extraBody, providerID: providerID)
            : openAICompatibleProviderOptions(from: request.extraBody, providerID: providerID, includeCompatibilityNamespace: false)
        body.merge(extraBody) { _, new in new }
        return body
    }
}

public final class OpenAICompatibleResponsesModel: LanguageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let raw = try await config.sendJSON(path: "/responses", modelID: modelID, body: .object(body(for: request, stream: false)), headers: request.headers)
        let toolCalls = openAIResponsesToolCalls(from: raw)
        let text = raw["output_text"]?.stringValue
            ?? raw["output"]?[0]?["content"]?[0]?["text"]?.stringValue
            ?? raw["choices"]?[0]?["message"]?["content"]?.stringValue
        guard let text = text ?? (toolCalls.isEmpty ? nil : "") else {
            throw AIError.invalidResponse(provider: providerID, message: "No output text found in responses API response.")
        }
        return TextGenerationResult(
            text: text,
            finishReason: openAIResponsesFinishReason(
                status: raw["status"]?.stringValue,
                incompleteReason: raw["incomplete_details"]?["reason"]?.stringValue
            ),
            usage: tokenUsage(from: raw),
            toolCalls: toolCalls,
            rawValue: raw
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let body = body(for: request, stream: true)
                    let response = try await config.transport.send(config.request(path: "/responses", modelID: modelID, body: .object(body), headers: request.headers))
                    guard (200..<300).contains(response.statusCode) else {
                        throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
                    }
                    var toolCallBuffers = OpenAIResponsesStreamingToolCalls()
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        continuation.yield(.raw(raw))
                        if let delta = raw["delta"]?.stringValue ?? raw["output_text_delta"]?.stringValue, openAIResponsesIsTextDelta(raw) {
                            continuation.yield(.textDelta(delta))
                        }
                        if let delta = raw["delta"]?.stringValue, raw["type"]?.stringValue == "response.reasoning_summary_text.delta" {
                            continuation.yield(.reasoningDelta(delta))
                        }
                        for eventPart in toolCallBuffers.apply(event: raw) {
                            continuation.yield(eventPart)
                        }
                        if raw["type"]?.stringValue == "response.completed" {
                            let response = raw["response"] ?? raw
                            continuation.yield(.finish(
                                reason: openAIResponsesFinishReason(
                                    status: response["status"]?.stringValue,
                                    incompleteReason: response["incomplete_details"]?["reason"]?.stringValue
                                ),
                                usage: tokenUsage(from: response)
                            ))
                        } else if raw["type"]?.stringValue == "response.incomplete" {
                            let response = raw["response"] ?? raw
                            continuation.yield(.finish(
                                reason: openAIResponsesFinishReason(
                                    status: response["status"]?.stringValue ?? "incomplete",
                                    incompleteReason: response["incomplete_details"]?["reason"]?.stringValue
                                ),
                                usage: tokenUsage(from: response)
                            ))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func body(for request: LanguageModelRequest, stream: Bool) -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "input": .array(request.messages.map(openAIResponsesInputMessageJSON))
        ]
        if stream { body["stream"] = true }
        if let temperature = request.temperature { body["temperature"] = .number(temperature) }
        if let topP = request.topP { body["top_p"] = .number(topP) }
        if let maxOutputTokens = request.maxOutputTokens { body["max_output_tokens"] = .number(Double(maxOutputTokens)) }
        let extraBody: [String: JSONValue]
        if isOpenAIBackedProvider(providerID) {
            extraBody = openAIResponsesProviderOptions(from: request.extraBody, providerID: providerID)
        } else if providerID.hasPrefix("xai.") {
            extraBody = openAICompatibleProviderOptions(from: request.extraBody, providerID: providerID, includeCompatibilityNamespace: false)
        } else {
            extraBody = request.extraBody
        }
        var options = openAIResponsesOptions(from: extraBody)
        if providerID.hasPrefix("xai.") {
            options = xaiResponsesOptions(from: options)
        }
        body.merge(options) { _, new in new }
        let preparedTools = openAIResponsesTools(from: request.tools)
        if !preparedTools.tools.isEmpty {
            body["tools"] = .array(preparedTools.tools)
            if let toolChoice = openAIResponsesToolChoice(from: request.extraBody["toolChoice"], customToolNames: preparedTools.customToolNames) {
                body["tool_choice"] = toolChoice
            }
        }
        return body
    }
}

private func openAIResponsesInputMessageJSON(_ message: AIMessage) -> JSONValue {
    if message.role == .user {
        return .object([
            "role": .string("user"),
            "content": .array(message.content.enumerated().compactMap(openAIResponsesInputContentPart))
        ])
    }

    if message.role == .assistant {
        return .object([
            "role": .string("assistant"),
            "content": .array(message.combinedText.isEmpty ? [] : [.object(["type": .string("output_text"), "text": .string(message.combinedText)])])
        ])
    }

    return .object([
        "role": .string(message.role.rawValue),
        "content": .string(message.combinedText)
    ])
}

private func openAIResponsesInputContentPart(_ indexAndPart: EnumeratedSequence<[AIContentPart]>.Element) -> JSONValue? {
    let (index, part) = indexAndPart
    switch part {
    case let .text(text):
        return .object(["type": .string("input_text"), "text": .string(text)])
    case let .imageURL(url):
        return .object(["type": .string("input_image"), "image_url": .string(url)])
    case let .data(mimeType, data), let .file(mimeType, data, _):
        let dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
        if mimeType.lowercased().hasPrefix("image/") {
            return .object(["type": .string("input_image"), "image_url": .string(dataURL)])
        }
        return .object([
            "type": .string("input_file"),
            "filename": .string(openAIResponsesFileName(for: mimeType, index: index)),
            "file_data": .string(dataURL)
        ])
    }
}

private func openAIResponsesFileName(for mimeType: String, index: Int) -> String {
    mimeType.lowercased() == "application/pdf" ? "part-\(index).pdf" : "part-\(index)"
}

private func openAIResponsesOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    openAIResponsesMoveKey("previousResponseId", to: "previous_response_id", in: &output)
    openAIResponsesMoveKey("parallelToolCalls", to: "parallel_tool_calls", in: &output)
    openAIResponsesMoveKey("serviceTier", to: "service_tier", in: &output)
    openAIResponsesMoveKey("maxToolCalls", to: "max_tool_calls", in: &output)
    output.removeValue(forKey: "toolChoice")
    output.removeValue(forKey: "allowedTools")

    var reasoning = output["reasoning"]?.objectValue ?? [:]
    if let effort = output.removeValue(forKey: "reasoningEffort") {
        reasoning["effort"] = effort
    }
    if let summary = output.removeValue(forKey: "reasoningSummary") {
        reasoning["summary"] = summary
    }
    if !reasoning.isEmpty {
        output["reasoning"] = .object(reasoning)
    }

    return output
}

private func xaiResponsesOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let topLogprobs = output.removeValue(forKey: "topLogprobs") {
        output["top_logprobs"] = topLogprobs
        output["logprobs"] = output["logprobs"] ?? .bool(true)
    }
    if output["store"]?.boolValue == true {
        output.removeValue(forKey: "store")
    } else if output["store"]?.boolValue == false {
        var include = output["include"]?.arrayValue ?? []
        if !include.contains(.string("reasoning.encrypted_content")) {
            include.append(.string("reasoning.encrypted_content"))
        }
        output["include"] = .array(include)
    }
    return output
}

private func openAIResponsesTools(from tools: [String: JSONValue]) -> (tools: [JSONValue], customToolNames: Set<String>) {
    var customToolNames: Set<String> = []
    let mapped = tools.compactMap { name, schema -> JSONValue? in
        let object = schema.objectValue
        let providerToolID = object?["id"]?.stringValue
        if object?["type"]?.stringValue == "provider" || providerToolID?.hasPrefix("openai.") == true {
            return openAIResponsesProviderTool(name: object?["name"]?.stringValue ?? name, id: providerToolID ?? name, args: object?["args"]?.objectValue ?? [:], customToolNames: &customToolNames)
        }

        var parameters = schema
        var function: [String: JSONValue] = [
            "type": .string("function"),
            "name": .string(name),
            "parameters": parameters
        ]
        if var parameterObject = parameters.objectValue {
            if let description = parameterObject["description"]?.stringValue {
                function["description"] = .string(description)
            }
            if let strict = parameterObject.removeValue(forKey: "strict") {
                function["strict"] = strict
                parameters = .object(parameterObject)
                function["parameters"] = parameters
            }
            if let deferLoading = parameterObject.removeValue(forKey: "deferLoading") ?? parameterObject.removeValue(forKey: "defer_loading") {
                function["defer_loading"] = deferLoading
                parameters = .object(parameterObject)
                function["parameters"] = parameters
            }
        }
        return .object(function)
    }
    return (mapped, customToolNames)
}

private func openAIResponsesProviderTool(name: String, id: String, args: [String: JSONValue], customToolNames: inout Set<String>) -> JSONValue? {
    switch id {
    case "openai.file_search":
        var tool: [String: JSONValue] = ["type": .string("file_search")]
        if let vectorStoreIds = args["vectorStoreIds"] ?? args["vector_store_ids"] { tool["vector_store_ids"] = vectorStoreIds }
        if let maxNumResults = args["maxNumResults"] ?? args["max_num_results"] { tool["max_num_results"] = maxNumResults }
        if let ranking = (args["ranking"] ?? args["ranking_options"])?.objectValue {
            tool["ranking_options"] = .object([
                "ranker": ranking["ranker"],
                "score_threshold": ranking["scoreThreshold"] ?? ranking["score_threshold"]
            ])
        }
        if let filters = args["filters"] { tool["filters"] = filters }
        return .object(tool)
    case "openai.local_shell":
        return .object(["type": .string("local_shell")])
    case "openai.shell":
        var tool: [String: JSONValue] = ["type": .string("shell")]
        if let environment = args["environment"]?.objectValue {
            tool["environment"] = openAIResponsesShellEnvironment(environment)
        }
        return .object(tool)
    case "openai.apply_patch":
        return .object(["type": .string("apply_patch")])
    case "openai.web_search_preview":
        var tool: [String: JSONValue] = ["type": .string("web_search_preview")]
        if let searchContextSize = args["searchContextSize"] ?? args["search_context_size"] { tool["search_context_size"] = searchContextSize }
        if let userLocation = args["userLocation"] ?? args["user_location"] { tool["user_location"] = userLocation }
        return .object(tool)
    case "openai.web_search":
        var tool: [String: JSONValue] = ["type": .string("web_search")]
        if let filters = args["filters"]?.objectValue {
            var mappedFilters = filters
            if let allowedDomains = mappedFilters.removeValue(forKey: "allowedDomains") {
                mappedFilters["allowed_domains"] = allowedDomains
            }
            tool["filters"] = .object(mappedFilters)
        }
        if let externalWebAccess = args["externalWebAccess"] ?? args["external_web_access"] { tool["external_web_access"] = externalWebAccess }
        if let searchContextSize = args["searchContextSize"] ?? args["search_context_size"] { tool["search_context_size"] = searchContextSize }
        if let userLocation = args["userLocation"] ?? args["user_location"] { tool["user_location"] = userLocation }
        return .object(tool)
    case "openai.code_interpreter":
        var tool: [String: JSONValue] = ["type": .string("code_interpreter")]
        if let container = args["container"] {
            if let containerID = container.stringValue {
                tool["container"] = .string(containerID)
            } else if let containerObject = container.objectValue {
                tool["container"] = .object([
                    "type": .string("auto"),
                    "file_ids": containerObject["fileIds"] ?? containerObject["file_ids"]
                ])
            }
        } else {
            tool["container"] = .object(["type": .string("auto")])
        }
        return .object(tool)
    case "openai.image_generation":
        var tool: [String: JSONValue] = ["type": .string("image_generation")]
        for key in ["background", "model", "moderation", "quality", "size"] {
            if let value = args[key] { tool[key] = value }
        }
        if let value = args["inputFidelity"] ?? args["input_fidelity"] { tool["input_fidelity"] = value }
        if let value = args["inputImageMask"]?.objectValue ?? args["input_image_mask"]?.objectValue {
            tool["input_image_mask"] = .object([
                "file_id": value["fileId"] ?? value["file_id"],
                "image_url": value["imageUrl"] ?? value["image_url"]
            ])
        }
        if let value = args["partialImages"] ?? args["partial_images"] { tool["partial_images"] = value }
        if let value = args["outputCompression"] ?? args["output_compression"] { tool["output_compression"] = value }
        if let value = args["outputFormat"] ?? args["output_format"] { tool["output_format"] = value }
        return .object(tool)
    case "openai.mcp":
        var tool: [String: JSONValue] = ["type": .string("mcp")]
        if let value = args["serverLabel"] ?? args["server_label"] { tool["server_label"] = value }
        if let value = args["allowedTools"] ?? args["allowed_tools"] { tool["allowed_tools"] = openAIResponsesMCPAllowedTools(value) }
        if let value = args["authorization"] { tool["authorization"] = value }
        if let value = args["connectorId"] ?? args["connector_id"] { tool["connector_id"] = value }
        if let value = args["headers"] { tool["headers"] = value }
        tool["require_approval"] = openAIResponsesMCPRequireApproval(args["requireApproval"] ?? args["require_approval"]) ?? .string("never")
        if let value = args["serverDescription"] ?? args["server_description"] { tool["server_description"] = value }
        if let value = args["serverUrl"] ?? args["server_url"] { tool["server_url"] = value }
        return .object(tool)
    case "openai.custom":
        customToolNames.insert(name)
        var tool: [String: JSONValue] = ["type": .string("custom"), "name": .string(name)]
        if let description = args["description"] { tool["description"] = description }
        if let format = args["format"] { tool["format"] = format }
        return .object(tool)
    case "openai.tool_search":
        var tool: [String: JSONValue] = ["type": .string("tool_search")]
        if let execution = args["execution"] { tool["execution"] = execution }
        if let description = args["description"] { tool["description"] = description }
        if let parameters = args["parameters"] { tool["parameters"] = parameters }
        return .object(tool)
    case "xai.web_search":
        var tool: [String: JSONValue] = ["type": .string("web_search")]
        if let value = args["allowedDomains"] ?? args["allowed_domains"] { tool["allowed_domains"] = value }
        if let value = args["excludedDomains"] ?? args["excluded_domains"] { tool["excluded_domains"] = value }
        if let value = args["enableImageSearch"] ?? args["enable_image_search"] { tool["enable_image_search"] = value }
        if let value = args["enableImageUnderstanding"] ?? args["enable_image_understanding"] { tool["enable_image_understanding"] = value }
        return .object(tool)
    case "xai.x_search":
        var tool: [String: JSONValue] = ["type": .string("x_search")]
        if let value = args["allowedXHandles"] ?? args["allowed_x_handles"] { tool["allowed_x_handles"] = value }
        if let value = args["excludedXHandles"] ?? args["excluded_x_handles"] { tool["excluded_x_handles"] = value }
        if let value = args["fromDate"] ?? args["from_date"] { tool["from_date"] = value }
        if let value = args["toDate"] ?? args["to_date"] { tool["to_date"] = value }
        if let value = args["enableImageUnderstanding"] ?? args["enable_image_understanding"] { tool["enable_image_understanding"] = value }
        if let value = args["enableVideoUnderstanding"] ?? args["enable_video_understanding"] { tool["enable_video_understanding"] = value }
        return .object(tool)
    case "xai.code_execution":
        return .object(["type": .string("code_interpreter")])
    case "xai.view_image":
        return .object(["type": .string("view_image")])
    case "xai.view_x_video":
        return .object(["type": .string("view_x_video")])
    case "xai.file_search":
        var tool: [String: JSONValue] = ["type": .string("file_search")]
        if let value = args["vectorStoreIds"] ?? args["vector_store_ids"] { tool["vector_store_ids"] = value }
        if let value = args["maxNumResults"] ?? args["max_num_results"] { tool["max_num_results"] = value }
        return .object(tool)
    case "xai.mcp":
        var tool: [String: JSONValue] = ["type": .string("mcp")]
        if let value = args["serverUrl"] ?? args["server_url"] { tool["server_url"] = value }
        if let value = args["serverLabel"] ?? args["server_label"] { tool["server_label"] = value }
        if let value = args["serverDescription"] ?? args["server_description"] { tool["server_description"] = value }
        if let value = args["allowedTools"] ?? args["allowed_tools"] { tool["allowed_tools"] = value }
        if let value = args["headers"] { tool["headers"] = value }
        if let value = args["authorization"] { tool["authorization"] = value }
        return .object(tool)
    default:
        return nil
    }
}

private func openAIResponsesToolChoice(from value: JSONValue?, customToolNames: Set<String>) -> JSONValue? {
    if let string = value?.stringValue {
        switch string {
        case "auto", "none", "required":
            return .string(string)
        default:
            return nil
        }
    }
    guard let object = value?.objectValue else { return nil }
    switch object["type"]?.stringValue {
    case "auto", "none", "required":
        return object["type"]
    case "tool":
        guard let name = object["toolName"]?.stringValue ?? object["tool_name"]?.stringValue else { return nil }
        let providerToolTypes: Set<String> = ["code_interpreter", "file_search", "image_generation", "web_search_preview", "web_search", "mcp", "apply_patch"]
        if providerToolTypes.contains(name) {
            return .object(["type": .string(name)])
        }
        if customToolNames.contains(name) {
            return .object(["type": .string("custom"), "name": .string(name)])
        }
        return .object(["type": .string("function"), "name": .string(name)])
    default:
        return nil
    }
}

private func openAIResponsesMCPAllowedTools(_ value: JSONValue) -> JSONValue {
    guard var object = value.objectValue else { return value }
    if let readOnly = object.removeValue(forKey: "readOnly") { object["read_only"] = readOnly }
    if let toolNames = object.removeValue(forKey: "toolNames") { object["tool_names"] = toolNames }
    return .object(object)
}

private func openAIResponsesMCPRequireApproval(_ value: JSONValue?) -> JSONValue? {
    guard let value else { return nil }
    if value.stringValue != nil { return value }
    guard var object = value.objectValue else { return value }
    if var never = object["never"]?.objectValue {
        if let toolNames = never.removeValue(forKey: "toolNames") {
            never["tool_names"] = toolNames
        }
        object["never"] = .object(never)
    }
    return .object(object)
}

private func openAIResponsesShellEnvironment(_ environment: [String: JSONValue]) -> JSONValue {
    switch environment["type"]?.stringValue {
    case "containerReference":
        return .object([
            "type": .string("container_reference"),
            "container_id": environment["containerId"] ?? environment["container_id"]
        ])
    case "containerAuto":
        var mapped: [String: JSONValue] = ["type": .string("container_auto")]
        if let fileIds = environment["fileIds"] ?? environment["file_ids"] { mapped["file_ids"] = fileIds }
        if let memoryLimit = environment["memoryLimit"] ?? environment["memory_limit"] { mapped["memory_limit"] = memoryLimit }
        if let networkPolicy = environment["networkPolicy"]?.objectValue ?? environment["network_policy"]?.objectValue {
            mapped["network_policy"] = openAIResponsesShellNetworkPolicy(networkPolicy)
        }
        if let skills = environment["skills"] { mapped["skills"] = skills }
        return .object(mapped)
    default:
        var mapped: [String: JSONValue] = ["type": .string("local")]
        if let skills = environment["skills"] { mapped["skills"] = skills }
        return .object(mapped)
    }
}

private func openAIResponsesShellNetworkPolicy(_ policy: [String: JSONValue]) -> JSONValue {
    guard policy["type"]?.stringValue == "allowlist" else {
        return .object(policy)
    }
    var mapped = policy
    if let allowedDomains = mapped.removeValue(forKey: "allowedDomains") {
        mapped["allowed_domains"] = allowedDomains
    }
    if let domainSecrets = mapped.removeValue(forKey: "domainSecrets") {
        mapped["domain_secrets"] = domainSecrets
    }
    return .object(mapped)
}

private func openAIResponsesMoveKey(_ source: String, to destination: String, in values: inout [String: JSONValue]) {
    if let value = values.removeValue(forKey: source) {
        values[destination] = value
    }
}

private struct OpenAIResponsesStreamingToolCalls {
    private var buffers: [Int: OpenAICompatibleToolCallBuffer] = [:]

    mutating func apply(event raw: JSONValue) -> [LanguageStreamPart] {
        guard let type = raw["type"]?.stringValue else { return [] }
        switch type {
        case "response.output_item.added":
            guard let item = raw["item"], let index = raw["output_index"]?.intValue else { return [] }
            guard let toolCall = openAIResponsesToolCall(from: item) else { return [] }
            buffers[index] = OpenAICompatibleToolCallBuffer(
                id: toolCall.id,
                name: toolCall.name,
                arguments: "",
                rawValue: item
            )
            return [.toolCallDelta(id: toolCall.id, name: toolCall.name, argumentsDelta: "", index: index)]
        case "response.function_call_arguments.delta", "response.custom_tool_call_input.delta":
            guard let index = raw["output_index"]?.intValue else { return [] }
            var buffer = buffers[index] ?? OpenAICompatibleToolCallBuffer()
            let delta = raw["delta"]?.stringValue ?? ""
            buffer.arguments += delta
            buffers[index] = buffer
            return [.toolCallDelta(id: buffer.id, name: buffer.name, argumentsDelta: delta, index: index)]
        case "response.output_item.done":
            guard let item = raw["item"], let index = raw["output_index"]?.intValue else { return [] }
            buffers[index] = nil
            guard let toolCall = openAIResponsesToolCall(from: item) else { return [] }
            return [.toolCall(toolCall)]
        default:
            return []
        }
    }
}

private func openAIResponsesToolCalls(from raw: JSONValue) -> [AIToolCall] {
    raw["output"]?.arrayValue?.compactMap(openAIResponsesToolCall) ?? []
}

private func openAIResponsesToolCall(from item: JSONValue) -> AIToolCall? {
    guard let type = item["type"]?.stringValue else { return nil }
    switch type {
    case "function_call":
        guard let name = item["name"]?.stringValue else { return nil }
        return AIToolCall(
            id: item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? "function-call",
            name: name,
            arguments: item["arguments"]?.stringValue ?? "",
            rawValue: item
        )
    case "custom_tool_call":
        guard let name = item["name"]?.stringValue else { return nil }
        let input = item["input"].flatMap(openAIResponsesJSONString) ?? item["input"]?.stringValue ?? ""
        return AIToolCall(
            id: item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? "custom-tool-call",
            name: name,
            arguments: input,
            rawValue: item
        )
    case "web_search_call":
        return openAIResponsesHostedToolCall(item: item, name: "web_search")
    case "file_search_call":
        return openAIResponsesHostedToolCall(item: item, name: "file_search")
    case "image_generation_call":
        return openAIResponsesHostedToolCall(item: item, name: "image_generation")
    case "code_interpreter_call":
        var input: [String: JSONValue] = [:]
        if let code = item["code"] { input["code"] = code }
        if let containerID = item["container_id"] { input["containerId"] = containerID }
        return AIToolCall(
            id: item["id"]?.stringValue ?? "code-interpreter-call",
            name: "code_interpreter",
            arguments: openAIResponsesJSONString(.object(input)) ?? "{}",
            providerExecuted: true,
            rawValue: item
        )
    case "tool_search_call":
        var input: [String: JSONValue] = [:]
        if let arguments = item["arguments"] { input["arguments"] = arguments }
        if let callID = item["call_id"] { input["call_id"] = callID }
        return AIToolCall(
            id: item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? "tool-search-call",
            name: "tool_search",
            arguments: openAIResponsesJSONString(.object(input)) ?? "{}",
            providerExecuted: item["execution"]?.stringValue == "server",
            rawValue: item
        )
    case "local_shell_call":
        return openAIResponsesHostedToolCall(item: item, name: "local_shell", idKey: "call_id", arguments: openAIResponsesJSONString(.object(["action": item["action"] ?? .null])) ?? "{}")
    case "shell_call":
        return openAIResponsesHostedToolCall(item: item, name: "shell", idKey: "call_id", arguments: openAIResponsesJSONString(.object(["action": item["action"] ?? .null])) ?? "{}")
    case "apply_patch_call":
        return openAIResponsesHostedToolCall(item: item, name: "apply_patch", idKey: "call_id", arguments: openAIResponsesJSONString(.object(["callId": item["call_id"] ?? .null, "operation": item["operation"] ?? .null])) ?? "{}")
    default:
        return nil
    }
}

private func openAIResponsesHostedToolCall(item: JSONValue, name: String, idKey: String = "id", arguments: String = "{}") -> AIToolCall {
    AIToolCall(
        id: item[idKey]?.stringValue ?? item["id"]?.stringValue ?? "\(name)-call",
        name: name,
        arguments: arguments,
        providerExecuted: true,
        rawValue: item
    )
}

private func openAIResponsesJSONString(_ value: JSONValue) -> String? {
    guard let data = try? encodeJSONBody(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

private func openAIResponsesIsTextDelta(_ raw: JSONValue) -> Bool {
    guard let type = raw["type"]?.stringValue else { return true }
    return type == "response.output_text.delta" || type == "response.output_text.done"
}

private func openAIResponsesFinishReason(status: String?, incompleteReason: String?) -> String? {
    if let incompleteReason {
        switch incompleteReason {
        case "max_output_tokens", "length":
            return "length"
        case "content_filter":
            return "content-filter"
        case "tool_calls":
            return "tool-calls"
        case "error":
            return "error"
        case "stop":
            return "stop"
        default:
            return "other"
        }
    }

    switch status {
    case "completed":
        return "stop"
    case "failed":
        return "error"
    case "incomplete":
        return "other"
    default:
        return status
    }
}

private func isOpenAIBackedProvider(_ providerID: String) -> Bool {
    providerID == "openai" || providerID.hasPrefix("openai.")
        || providerID == "azure" || providerID.hasPrefix("azure.")
}

private func openAIProviderOptions(from extraBody: [String: JSONValue], providerID: String = "openai") -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "openai")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    if let root = openAIBackedProviderRoot(providerID), root != "openai", let nested = output.removeValue(forKey: root)?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    if providerID != "openai", providerID != openAIBackedProviderRoot(providerID), let nested = output.removeValue(forKey: providerID)?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func openAIBackedProviderRoot(_ providerID: String) -> String? {
    if providerID == "openai" || providerID.hasPrefix("openai.") {
        return "openai"
    }
    if providerID == "azure" || providerID.hasPrefix("azure.") {
        return "azure"
    }
    return nil
}

private func openAICompatibleProviderOptions(from extraBody: [String: JSONValue], providerID: String, includeCompatibilityNamespace: Bool) -> [String: JSONValue] {
    var output = extraBody
    var nested: [String: JSONValue] = [:]

    if includeCompatibilityNamespace {
        if let deprecated = output.removeValue(forKey: "openai-compatible")?.objectValue {
            nested.merge(deprecated) { _, value in value }
        }
        if let compatible = output.removeValue(forKey: "openaiCompatible")?.objectValue {
            nested.merge(compatible) { _, value in value }
        }
    }

    let providerRoots = openAICompatibleProviderOptionRoots(providerID)
    for providerRoot in providerRoots {
        if let rootProviderOptions = output.removeValue(forKey: providerRoot)?.objectValue {
            nested.merge(rootProviderOptions) { _, value in value }
        }
        let camelRoot = openAICompatibleCamelCase(providerRoot)
        if camelRoot != providerRoot, let camelRootOptions = output.removeValue(forKey: camelRoot)?.objectValue {
            nested.merge(camelRootOptions) { _, value in value }
        }
    }

    let camelProviderID = openAICompatibleCamelCase(providerID)
    if providerID.hasPrefix("xai."), let rootProviderOptions = output.removeValue(forKey: "xai")?.objectValue {
        nested.merge(rootProviderOptions) { _, value in value }
    }
    if let rawProviderOptions = output.removeValue(forKey: providerID)?.objectValue {
        nested.merge(rawProviderOptions) { _, value in value }
    }
    if camelProviderID != providerID, let camelProviderOptions = output.removeValue(forKey: camelProviderID)?.objectValue {
        nested.merge(camelProviderOptions) { _, value in value }
    }

    output.merge(nested) { _, nested in nested }
    return output
}

private func openAICompatibleProviderOptionWarnings(from extraBody: [String: JSONValue], providerID: String, includeCompatibilityNamespace: Bool) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if includeCompatibilityNamespace, extraBody["openai-compatible"] != nil {
        warnings.append(AIWarning(
            type: "deprecated",
            setting: "providerOptions key 'openai-compatible'",
            message: "Use 'openaiCompatible' instead."
        ))
    }

    let providerOptionsKey = openAICompatibleProviderRoot(providerID)
    let camelProviderOptionsKey = openAICompatibleCamelCase(providerOptionsKey)
    if camelProviderOptionsKey != providerOptionsKey, extraBody[providerOptionsKey] != nil {
        warnings.append(AIWarning(
            type: "deprecated",
            setting: "providerOptions key '\(providerOptionsKey)'",
            message: "Use '\(camelProviderOptionsKey)' instead."
        ))
    }
    return warnings
}

private func openAICompatibleProviderRoot(_ providerID: String) -> String {
    String(providerID.split(separator: ".", maxSplits: 1).first.map(String.init) ?? providerID)
}

private func openAICompatibleProviderOptionRoots(_ providerID: String) -> [String] {
    let root = openAICompatibleProviderRoot(providerID)
    switch root {
    case "baseten", "deepinfra", "fireworks", "moonshotai", "togetherai":
        return providerID == root ? [] : [root]
    default:
        return []
    }
}

private func openAICompatibleCamelCase(_ value: String) -> String {
    let separators = CharacterSet(charactersIn: "-_. ")
    let parts = value
        .components(separatedBy: separators)
        .filter { !$0.isEmpty }
    guard let first = parts.first else { return value }
    return parts.dropFirst().reduce(first) { result, part in
        result + part.prefix(1).uppercased() + part.dropFirst()
    }
}

private func openAICompletionProviderOptions(from extraBody: [String: JSONValue], providerID: String) -> [String: JSONValue] {
    openAIProviderOptions(from: extraBody, providerID: providerID)
}

private func openAIResponsesProviderOptions(from extraBody: [String: JSONValue], providerID: String) -> [String: JSONValue] {
    openAIProviderOptions(from: extraBody, providerID: providerID)
}

private func openAIImageOptions(from extraBody: [String: JSONValue], providerID: String = "openai") -> [String: JSONValue] {
    var output = openAIProviderOptions(from: extraBody, providerID: providerID)
    openAIResponsesMoveKey("outputFormat", to: "output_format", in: &output)
    openAIResponsesMoveKey("outputCompression", to: "output_compression", in: &output)
    openAIResponsesMoveKey("inputFidelity", to: "input_fidelity", in: &output)
    return output
}

private func openAIImageHasDefaultResponseFormat(_ modelID: String) -> Bool {
    ["chatgpt-image-", "gpt-image-1-mini", "gpt-image-1.5", "gpt-image-1", "gpt-image-2"].contains { modelID.hasPrefix($0) }
}

private func openAIImageMaxImagesPerCall(_ modelID: String) -> Int {
    switch modelID {
    case "dall-e-2", "gpt-image-1", "gpt-image-1-mini", "gpt-image-1.5", "gpt-image-2", "chatgpt-image-latest":
        return 10
    default:
        return 1
    }
}

private func openAITranscriptionOptions(from extraBody: [String: JSONValue], providerID: String = "openai", modelID: String) -> [String: JSONValue] {
    var output = openAIProviderOptions(from: extraBody, providerID: providerID)
    let hadProviderOptions = !output.isEmpty
    openAIResponsesMoveKey("timestampGranularities", to: "timestamp_granularities", in: &output)
    openAIResponsesMoveKey("responseFormat", to: "response_format", in: &output)

    if modelID != "whisper-1", hadProviderOptions, output["response_format"] == nil {
        output["response_format"] = .string(openAITranscriptionUsesJSONResponseFormat(modelID) ? "json" : "verbose_json")
    }

    return output
}

private func openAITranscriptionUsesJSONResponseFormat(_ modelID: String) -> Bool {
    modelID == "gpt-4o-transcribe" || modelID == "gpt-4o-mini-transcribe"
}

public final class OpenAICompatibleEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig
    private var maxEmbeddingsPerCall: Int { config.maxEmbeddingsPerCall ?? 2048 }

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        guard request.values.count <= maxEmbeddingsPerCall else {
            throw AIError.invalidArgument(argument: "values", message: "OpenAI-compatible embedding models support at most \(maxEmbeddingsPerCall) values per call.")
        }

        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "input": .array(request.values)
        ]
        if let dimensions = request.dimensions { body["dimensions"] = .number(Double(dimensions)) }
        let extraBody = isOpenAIBackedProvider(providerID)
            ? openAIProviderOptions(from: request.extraBody, providerID: providerID)
            : openAICompatibleProviderOptions(from: request.extraBody, providerID: providerID, includeCompatibilityNamespace: true)
        body.merge(extraBody) { _, new in new }

        let raw = try await config.sendJSON(path: "/embeddings", modelID: modelID, body: .object(body), headers: request.headers)
        guard case let .array(data) = raw["data"] else {
            throw AIError.invalidResponse(provider: providerID, message: "No embedding data found.")
        }

        let embeddings = data.compactMap { item -> [Double]? in
            guard case let .array(values) = item["embedding"] else { return nil }
            return values.compactMap(\.doubleValue)
        }
        return EmbeddingResult(embeddings: embeddings, usage: tokenUsage(from: raw), rawValue: raw)
    }
}

public final class OpenAICompatibleImageModel: ImageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig
    private var maxImagesPerCall: Int {
        isOpenAIBackedProvider(providerID) ? openAIImageMaxImagesPerCall(modelID) : 10
    }

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        if let count = request.count, count > maxImagesPerCall {
            throw AIError.invalidArgument(argument: "count", message: "OpenAI-compatible image models support at most \(maxImagesPerCall) image(s) per call.")
        }
        let warnings = openAICompatibleImageWarnings(from: request, providerID: providerID)
        if !request.files.isEmpty {
            return try await editImage(request, warnings: warnings)
        }

        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "prompt": .string(request.prompt)
        ]
        if let size = request.size { body["size"] = .string(size) }
        if let count = request.count { body["n"] = .number(Double(count)) }
        body.merge(isOpenAIBackedProvider(providerID) ? openAIImageOptions(from: request.extraBody, providerID: providerID) : openAICompatibleProviderOptions(from: request.extraBody, providerID: providerID, includeCompatibilityNamespace: false)) { _, new in new }
        if isOpenAIBackedProvider(providerID), body["response_format"] == nil, !openAIImageHasDefaultResponseFormat(modelID) {
            body["response_format"] = .string("b64_json")
        } else if !isOpenAIBackedProvider(providerID) {
            body["response_format"] = .string("b64_json")
        }

        let raw = try await config.sendJSON(path: "/images/generations", modelID: modelID, body: .object(body), headers: request.headers)
        guard case let .array(data) = raw["data"] else {
            throw AIError.invalidResponse(provider: providerID, message: "No image data found.")
        }
        return ImageGenerationResult(
            urls: data.compactMap { $0["url"]?.stringValue },
            base64Images: data.compactMap { $0["b64_json"]?.stringValue },
            rawValue: raw,
            warnings: warnings
        )
    }

    private func editImage(_ request: ImageGenerationRequest, warnings: [AIWarning]) async throws -> ImageGenerationResult {
        var form = MultipartFormData()
        form.appendField(name: "model", value: modelID)
        form.appendField(name: "prompt", value: request.prompt)
        for file in request.files {
            let resolved = try await openAICompatibleResolveImageFile(file, providerID: providerID, transport: config.transport)
            form.appendFile(name: "image", fileName: resolved.fileName, mimeType: resolved.mediaType, data: resolved.data)
        }
        if let mask = request.mask {
            let resolved = try await openAICompatibleResolveImageFile(mask, providerID: providerID, transport: config.transport)
            form.appendFile(name: "mask", fileName: resolved.fileName, mimeType: resolved.mediaType, data: resolved.data)
        }
        if let count = request.count {
            form.appendField(name: "n", value: String(count))
        }
        if let size = request.size {
            form.appendField(name: "size", value: size)
        }

        let extraBody = isOpenAIBackedProvider(providerID) ? openAIImageOptions(from: request.extraBody, providerID: providerID) : openAICompatibleProviderOptions(from: request.extraBody, providerID: providerID, includeCompatibilityNamespace: false)
        for (key, value) in extraBody {
            if case let .array(items) = value {
                for item in items {
                    if let scalar = jsonScalarString(item) {
                        form.appendField(name: key, value: scalar)
                    }
                }
            } else if let scalar = jsonScalarString(value) {
                form.appendField(name: key, value: scalar)
            }
        }

        let response = try await config.transport.send(
            config.rawRequest(
                path: "/images/edits",
                modelID: modelID,
                body: form.finalize(),
                contentType: "multipart/form-data; boundary=\(form.boundary)",
                headers: request.headers
            )
        )
        guard (200..<300).contains(response.statusCode) else {
            throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
        }
        let raw = try response.jsonValue()
        guard case let .array(data) = raw["data"] else {
            throw AIError.invalidResponse(provider: providerID, message: "No image data found.")
        }
        return ImageGenerationResult(
            urls: data.compactMap { $0["url"]?.stringValue },
            base64Images: data.compactMap { $0["b64_json"]?.stringValue },
            rawValue: raw,
            warnings: warnings
        )
    }
}

private func openAICompatibleImageWarnings(from request: ImageGenerationRequest, providerID: String) -> [AIWarning] {
    var warnings = openAICompatibleProviderOptionWarnings(from: request.extraBody, providerID: providerID, includeCompatibilityNamespace: false)
    if request.aspectRatio != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "aspectRatio",
            message: "This model does not support aspect ratio. Use `size` instead."
        ))
    }
    if request.seed != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "seed"))
    }
    return warnings
}

private struct OpenAICompatibleResolvedImageFile {
    var data: Data
    var mediaType: String
    var fileName: String
}

private func openAICompatibleResolveImageFile(_ file: ImageInputFile, providerID: String, transport: AITransport) async throws -> OpenAICompatibleResolvedImageFile {
    if let data = file.data {
        let mediaType = file.mediaType ?? "application/octet-stream"
        return OpenAICompatibleResolvedImageFile(data: data, mediaType: mediaType, fileName: file.fileName ?? openAICompatibleDefaultFileName(mediaType: mediaType))
    }

    guard let url = file.url else {
        throw AIError.invalidResponse(provider: providerID, message: "Image file must contain data or a URL.")
    }
    let response = try await transport.send(AIHTTPRequest(method: "GET", url: try requireURL(url)))
    guard (200..<300).contains(response.statusCode) else {
        throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
    }
    let mediaType = file.mediaType
        ?? response.headers["content-type"]
        ?? response.headers["Content-Type"]
        ?? "application/octet-stream"
    return OpenAICompatibleResolvedImageFile(data: response.body, mediaType: mediaType, fileName: file.fileName ?? openAICompatibleDefaultFileName(mediaType: mediaType))
}

private func openAICompatibleDefaultFileName(mediaType: String) -> String {
    switch mediaType {
    case "image/png": "image.png"
    case "image/jpeg", "image/jpg": "image.jpg"
    case "image/webp": "image.webp"
    default: "image"
    }
}

public final class OpenAICompatibleSpeechModel: SpeechModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func speak(_ request: SpeechRequest) async throws -> SpeechResult {
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "input": .string(request.text)
        ]
        if isOpenAIBackedProvider(providerID) {
            body["voice"] = .string(request.voice ?? "alloy")
            body["response_format"] = .string(request.format ?? "mp3")
        } else {
            if let voice = request.voice { body["voice"] = .string(voice) }
            if let format = request.format { body["response_format"] = .string(format) }
        }
        let extraBody = isOpenAIBackedProvider(providerID) ? openAIProviderOptions(from: request.extraBody, providerID: providerID) : request.extraBody
        body.merge(extraBody) { _, new in new }

        let response = try await config.transport.send(config.request(path: "/audio/speech", modelID: modelID, body: .object(body), headers: request.headers))
        guard (200..<300).contains(response.statusCode) else {
            throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
        }
        return SpeechResult(audio: response.body, contentType: response.headers["content-type"] ?? response.headers["Content-Type"])
    }
}

public final class OpenAICompatibleTranscriptionModel: TranscriptionModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        var form = MultipartFormData()
        form.appendField(name: "model", value: modelID)
        form.appendFile(name: "file", fileName: request.fileName, mimeType: request.mimeType, data: request.audio)
        if modelID == "whisper-1" {
            form.appendField(name: "response_format", value: "verbose_json")
        }
        if let language = request.language {
            form.appendField(name: "language", value: language)
        }
        if let prompt = request.prompt {
            form.appendField(name: "prompt", value: prompt)
        }
        let extraBody = isOpenAIBackedProvider(providerID) ? openAITranscriptionOptions(from: request.extraBody, providerID: providerID, modelID: modelID) : request.extraBody
        for (key, value) in extraBody {
            if case let .array(items) = value {
                for item in items {
                    if let scalar = jsonScalarString(item) {
                        form.appendField(name: "\(key)[]", value: scalar)
                    }
                }
            } else if let scalar = jsonScalarString(value) {
                form.appendField(name: key, value: scalar)
            }
        }
        let body = form.finalize()
        let response = try await config.transport.send(
            config.rawRequest(
                path: "/audio/transcriptions",
                modelID: modelID,
                body: body,
                contentType: "multipart/form-data; boundary=\(form.boundary)",
                headers: request.headers
            )
        )
        guard (200..<300).contains(response.statusCode) else {
            throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
        }
        let raw = try response.jsonValue()
        guard let text = raw["text"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "No transcription text found.")
        }
        return TranscriptionResult(text: text, rawValue: raw)
    }
}
