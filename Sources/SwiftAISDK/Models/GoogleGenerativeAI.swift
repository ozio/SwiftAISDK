import Foundation

public final class GoogleGenerativeLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let response = try await config.sendJSONResponse(
            path: "/models/\(modelID):generateContent",
            modelID: modelID,
            body: try Self.generateContentBody(for: request, modelID: modelID),
            headers: request.headers
        )
        let raw = response.json
        let text = googleGenerateContentText(from: raw)
        let toolCalls = googleGenerateContentToolCalls(from: raw)
        guard text != nil || !toolCalls.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No candidate text found in Google response.")
        }
        return TextGenerationResult(
            text: text ?? "",
            finishReason: googleGenerateContentFinishReason(raw["candidates"]?[0]?["finishReason"]?.stringValue, hasToolCalls: !toolCalls.isEmpty),
            usage: googleGenerateContentUsage(from: raw),
            toolCalls: toolCalls,
            sources: googleGenerateContentSources(from: raw),
            rawValue: raw,
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await config.transport.send(config.request(
                        path: "/models/\(modelID):streamGenerateContent?alt=sse",
                        modelID: modelID,
                        body: try Self.generateContentBody(for: request, modelID: modelID),
                        headers: request.headers
                    ))
                    let parts = try streamFromGoogleGenerateContent(providerID: providerID, response: response, includeRawChunks: request.includeRawChunks, modelID: modelID)
                    for part in parts {
                        continuation.yield(part)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func generateContentBody(for request: LanguageModelRequest, modelID: String) throws -> JSONValue {
        var options = googleGenerateContentOptions(from: request.extraBody)
        let responseFormat = googleResolvedResponseFormat(request: request, options: &options)
        let systemText = request.messages
            .filter { $0.role == .system }
            .map(\.combinedText)
            .joined(separator: "\n")
        let contents = try request.messages
            .filter { $0.role != .system }
            .map { try Self.contentJSON($0) }

        var generationConfig: [String: JSONValue] = [:]
        if let temperature = request.temperature { generationConfig["temperature"] = .number(temperature) }
        if let topP = request.topP { generationConfig["topP"] = .number(topP) }
        if let maxOutputTokens = request.maxOutputTokens { generationConfig["maxOutputTokens"] = .number(Double(maxOutputTokens)) }
        if !request.stopSequences.isEmpty { generationConfig["stopSequences"] = .array(request.stopSequences) }
        googleApplyResponseFormat(responseFormat, options: options, to: &generationConfig)

        var body: [String: JSONValue] = ["contents": .array(contents)]
        if !systemText.isEmpty {
            body["systemInstruction"] = .object(["parts": .array([.object(["text": .string(systemText)])])])
        }
        if !generationConfig.isEmpty { body["generationConfig"] = .object(generationConfig) }
        if let preparedTools = googlePrepareTools(from: request.tools, toolChoice: options["toolChoice"], modelID: modelID, isVertexProvider: false) {
            body["tools"] = .array(preparedTools.tools)
            if let toolConfig = preparedTools.toolConfig {
                body["toolConfig"] = toolConfig
            }
        }
        body.merge(googleExtraBodyWithoutToolChoice(options)) { _, new in new }
        return .object(body)
    }

    private static func contentJSON(_ message: AIMessage) throws -> JSONValue {
        let role = message.role == .assistant ? "model" : "user"
        let parts = try message.content.map { part -> JSONValue in
            switch part {
            case let .text(text):
                return .object(["text": .string(text)])
            case let .imageURL(url):
                return .object(["fileData": .object(["fileUri": .string(url)])])
            case let .data(mimeType, data), let .file(mimeType, data, _):
                let resolvedMimeType = try resolveFullMediaType(mediaType: mimeType, data: data)
                return .object([
                    "inlineData": .object([
                        "mimeType": .string(resolvedMimeType),
                        "data": .string(data.base64EncodedString())
                    ])
                ])
            case let .toolCall(call):
                var output: [String: JSONValue] = [
                    "functionCall": .object([
                        "name": .string(call.name),
                        "args": googleToolArguments(call.arguments)
                    ])
                ]
                if let thoughtSignature = googleThoughtSignature(from: call.providerMetadata) {
                    output["thoughtSignature"] = thoughtSignature
                }
                return .object(output)
            case let .toolResult(result):
                return .object([
                    "functionResponse": .object([
                        "name": .string(result.toolName),
                        "response": result.modelOutput ?? result.result
                    ])
                ])
            case .toolApprovalRequest, .toolApprovalResponse:
                return .object(["text": .string("")])
            }
        }
        return .object(["role": .string(role), "parts": .array(parts)])
    }
}

public final class GoogleEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        let path = request.values.count == 1
            ? "/models/\(modelID):embedContent"
            : "/models/\(modelID):batchEmbedContents"
        let body: JSONValue
        if request.values.count == 1 {
            body = .object([
                "model": .string("models/\(modelID)"),
                "content": .object(["parts": .array([.object(["text": .string(request.values[0])])])])
            ])
        } else {
            body = .object([
                "requests": .array(request.values.map { value in
                    .object([
                        "model": .string("models/\(modelID)"),
                        "content": .object(["parts": .array([.object(["text": .string(value)])])])
                    ])
                })
            ])
        }

        let response = try await config.sendJSONResponse(path: path, modelID: modelID, body: body, headers: request.headers)
        let raw = response.json
        let embeddings: [[Double]]
        if let values = raw["embedding"]?["values"]?.arrayValue {
            embeddings = [values.compactMap(\.doubleValue)]
        } else {
            embeddings = raw["embeddings"]?.arrayValue?.compactMap { item in
                item["values"]?.arrayValue?.compactMap(\.doubleValue)
            } ?? []
        }
        return EmbeddingResult(
            embeddings: embeddings,
            rawValue: raw,
            requestMetadata: AIRequestMetadata(body: body, headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

public final class GoogleImageGenerationModel: ImageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        if modelID.hasPrefix("gemini-") {
            return try await generateGeminiImage(request)
        }
        return try await generateImagen(request)
    }

    private func generateImagen(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        if !request.files.isEmpty {
            return try await editImagen(request)
        }
        let body = JSONValue.object([
            "instances": .array([.object(["prompt": .string(request.prompt)])]),
            "parameters": .object(googleImagenParameters(for: request))
        ])
        let response = try await config.sendJSONResponse(path: "/models/\(modelID):predict", modelID: modelID, body: body, headers: request.headers)
        let raw = response.json
        let images = raw["predictions"]?.arrayValue?.compactMap { $0["bytesBase64Encoded"]?.stringValue } ?? []
        guard !images.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No Imagen predictions found.")
        }
        return ImageGenerationResult(
            urls: [],
            base64Images: images,
            rawValue: raw,
            requestMetadata: imageGenerationRequestMetadata(request, body: body),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    private func editImagen(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        let options = googleImageProviderOptions(from: request.extraBody)
        let edit = options["edit"]?.objectValue ?? [:]
        var referenceImages: [JSONValue] = []

        for (index, file) in request.files.enumerated() {
            referenceImages.append(.object([
                "referenceType": .string("REFERENCE_TYPE_RAW"),
                "referenceId": .number(Double(index + 1)),
                "referenceImage": .object([
                    "bytesBase64Encoded": .string(try googleImageEditBase64(file))
                ])
            ]))
        }

        if let mask = request.mask {
            var maskImageConfig: [String: JSONValue] = [
                "maskMode": edit["maskMode"] ?? .string("MASK_MODE_USER_PROVIDED")
            ]
            if let dilation = edit["maskDilation"] {
                maskImageConfig["dilation"] = dilation
            }
            referenceImages.append(.object([
                "referenceType": .string("REFERENCE_TYPE_MASK"),
                "referenceId": .number(Double(request.files.count + 1)),
                "referenceImage": .object([
                    "bytesBase64Encoded": .string(try googleImageEditBase64(mask))
                ]),
                "maskImageConfig": .object(maskImageConfig)
            ]))
        }

        let body = JSONValue.object([
            "instances": .array([.object([
                "prompt": .string(request.prompt),
                "referenceImages": .array(referenceImages)
            ])]),
            "parameters": .object(googleImagenEditParameters(for: request, options: options, edit: edit))
        ])
        let response = try await config.sendJSONResponse(path: "/models/\(modelID):predict", modelID: modelID, body: body, headers: request.headers)
        let raw = response.json
        let images = raw["predictions"]?.arrayValue?.compactMap { $0["bytesBase64Encoded"]?.stringValue } ?? []
        guard !images.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No Imagen edit predictions found.")
        }
        return ImageGenerationResult(
            urls: [],
            base64Images: images,
            rawValue: raw,
            requestMetadata: imageGenerationRequestMetadata(request, body: body),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    private func generateGeminiImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        var body = GoogleGenerativeLanguageModel.imageGenerationContentBody(prompt: request.prompt, aspectRatio: googleAspectRatio(from: request))
        body.merge(request.extraBody) { _, new in new }
        let response = try await config.sendJSONResponse(path: "/models/\(modelID):generateContent", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let parts = raw["candidates"]?[0]?["content"]?["parts"]?.arrayValue ?? []
        let images = parts.compactMap { part in
            part["inlineData"]?["data"]?.stringValue
        }
        guard !images.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No Gemini image inlineData found.")
        }
        return ImageGenerationResult(
            urls: [],
            base64Images: images,
            rawValue: raw,
            requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

public final class GoogleVideoGenerationModel: VideoModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        let body = JSONValue.object([
            "instances": .array([.object(googleVideoInstance(for: request))]),
            "parameters": .object(googleVideoParameters(for: request))
        ])
        let operation = try await config.sendJSON(path: "/models/\(modelID):predictLongRunning", modelID: modelID, body: body, headers: request.headers, abortSignal: request.abortSignal)
        guard let operationName = operation["name"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Google video create response did not contain an operation name.")
        }

        let finalResponse = try await pollOperationResponse(named: operationName, headers: request.headers, timeoutNanoseconds: googlePollTimeout(request.extraBody), intervalNanoseconds: googlePollInterval(request.extraBody), abortSignal: request.abortSignal)
        let finalOperation = finalResponse.json
        let samples = finalOperation["response"]?["generateVideoResponse"]?["generatedSamples"]?.arrayValue ?? []
        let urls = samples.compactMap { sample in
            sample["video"]?["uri"]?.stringValue.map(googleVideoURLWithAPIKey)
        }
        guard !urls.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "Google video response did not contain generatedSamples video URIs.")
        }
        return VideoGenerationResult(
            urls: urls,
            operationID: operationName,
            rawValue: finalOperation,
            requestMetadata: videoGenerationRequestMetadata(request, body: body),
            responseMetadata: aiResponseMetadata(from: finalOperation, response: finalResponse.response, modelID: modelID)
        )
    }

    private func pollOperationResponse(named operationName: String, headers: [String: String], timeoutNanoseconds: UInt64, intervalNanoseconds: UInt64, abortSignal: AIAbortSignal?) async throws -> (json: JSONValue, response: AIHTTPResponse) {
        let started = DispatchTime.now().uptimeNanoseconds
        var latest: JSONValue?
        repeat {
            let response = try await config.transport.send(AIHTTPRequest(
                method: "GET",
                url: try requireURL("\(config.baseURL)/\(operationName)"),
                headers: config.headers.mergingHeaders(headers),
                abortSignal: abortSignal
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            latest = raw
            if raw["error"] != nil {
                throw AIError.invalidResponse(provider: providerID, message: raw["error"]?["message"]?.stringValue ?? "Google video generation failed.")
            }
            if raw["done"]?.boolValue == true {
                return (raw, response)
            }
            if intervalNanoseconds > 0 {
                try await sleepWithAbortSignal(nanoseconds: intervalNanoseconds, abortSignal: abortSignal)
            }
        } while DispatchTime.now().uptimeNanoseconds - started < timeoutNanoseconds

        throw AIError.invalidResponse(provider: providerID, message: "Google video generation timed out. Last response: \(latest.map(String.init(describing:)) ?? "none")")
    }

    private func googleVideoURLWithAPIKey(_ uri: String) -> String {
        guard let key = config.headers["x-goog-api-key"], !key.isEmpty else { return uri }
        return "\(uri)\(uri.contains("?") ? "&" : "?")key=\(key)"
    }
}

public final class GoogleInteractionsLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let agent: String?
    private let config: ModelHTTPConfig

    init(modelID: String, agent: String?, config: ModelHTTPConfig) {
        self.providerID = "\(config.providerID).interactions"
        self.modelID = modelID
        self.agent = agent
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = try googleInteractionsPreparedCall(for: request, modelID: modelID, agent: agent, stream: false)
        let raw = try await sendInteractions(body: .object(prepared.body), headers: request.headers, abortSignal: request.abortSignal)
        let final = try await resolvedInteraction(raw, requestHeaders: request.headers, abortSignal: request.abortSignal)
        let text = googleInteractionsText(from: final)
        let toolCalls = googleInteractionsToolCalls(from: final)
        guard !text.isEmpty || !toolCalls.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No model_output text found in Google Interactions response.")
        }
        return TextGenerationResult(
            text: text,
            finishReason: googleInteractionsFinishReason(status: final["status"]?.stringValue, hasFunctionCall: googleInteractionsHasFunctionCall(final)),
            usage: googleInteractionsUsage(from: final),
            toolCalls: toolCalls,
            sources: googleInteractionsSources(from: final),
            providerMetadata: googleInteractionsProviderMetadata(from: final),
            rawValue: final,
            warnings: prepared.warnings
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = try googleInteractionsPreparedCall(for: request, modelID: modelID, agent: agent, stream: true)
                    let response = try await config.transport.send(config.request(
                        path: "/interactions",
                        modelID: modelID,
                        body: .object(prepared.body),
                        headers: googleInteractionsHeaders(request.headers),
                        abortSignal: request.abortSignal
                    ))
                    guard (200..<300).contains(response.statusCode) else {
                        throw httpStatusError(provider: providerID, response: response)
                    }

                    if !prepared.warnings.isEmpty {
                        continuation.yield(.streamStart(warnings: prepared.warnings))
                    }
                    var toolCalls = GoogleInteractionsStreamingToolCalls()
                    var hasFunctionCall = false
                    var sourceCounter = 0
                    var emittedSourceKeys: Set<String> = []
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        for source in googleInteractionsSources(from: raw, sourceCounter: &sourceCounter, emittedKeys: &emittedSourceKeys) {
                            continuation.yield(.source(source))
                        }
                        let eventType = raw["event_type"]?.stringValue
                        if let interaction = raw["interaction"] {
                            let metadata = googleInteractionsProviderMetadata(from: interaction)
                            if !metadata.isEmpty {
                                continuation.yield(.metadata(metadata))
                            }
                        }
                        if eventType == "step.start",
                           raw["step"]?["type"]?.stringValue == "function_call" {
                            hasFunctionCall = true
                            for part in toolCalls.start(step: raw["step"], index: raw["index"]?.intValue) {
                                continuation.yield(part)
                            }
                        }
                        if eventType == "step.delta", let delta = raw["delta"] {
                            if let text = delta["text"]?.stringValue, !text.isEmpty {
                                continuation.yield(.textDelta(text))
                            }
                            if let summary = delta["summary"]?.stringValue, !summary.isEmpty {
                                continuation.yield(.reasoningDelta(summary))
                            }
                            if delta["type"]?.stringValue == "arguments_delta" {
                                hasFunctionCall = true
                                for part in toolCalls.delta(delta, index: raw["index"]?.intValue) {
                                    continuation.yield(part)
                                }
                            }
                        }
                        if eventType == "step.stop" {
                            for part in toolCalls.stop(index: raw["index"]?.intValue) {
                                continuation.yield(part)
                            }
                        }
                        if eventType == "interaction.completed" || eventType == "interaction.failed" || eventType == "interaction.incomplete" || eventType == "interaction.cancelled" {
                            let interaction = raw["interaction"] ?? raw
                            continuation.yield(.finish(
                                reason: googleInteractionsFinishReason(status: interaction["status"]?.stringValue, hasFunctionCall: hasFunctionCall),
                                usage: googleInteractionsUsage(from: interaction)
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

    private func sendInteractions(body: JSONValue, headers: [String: String], abortSignal: AIAbortSignal?) async throws -> JSONValue {
        let response = try await config.transport.send(config.request(path: "/interactions", modelID: modelID, body: body, headers: googleInteractionsHeaders(headers), abortSignal: abortSignal))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        return try response.jsonValue()
    }

    private func resolvedInteraction(_ raw: JSONValue, requestHeaders: [String: String], abortSignal: AIAbortSignal?) async throws -> JSONValue {
        guard agent != nil,
              !googleInteractionsIsTerminal(raw["status"]?.stringValue),
              let id = raw["id"]?.stringValue else {
            return raw
        }
        return try await pollInteraction(id: id, requestHeaders: requestHeaders, timeoutNanoseconds: googleInteractionsPollTimeout(raw: raw), abortSignal: abortSignal)
    }

    private func pollInteraction(id: String, requestHeaders: [String: String], timeoutNanoseconds: UInt64, abortSignal: AIAbortSignal?) async throws -> JSONValue {
        let started = DispatchTime.now().uptimeNanoseconds
        repeat {
            let response = try await config.transport.send(AIHTTPRequest(
                method: "GET",
                url: try requireURL("\(config.baseURL)/interactions/\(id)"),
                headers: config.headers.mergingHeaders(googleInteractionsHeaders(requestHeaders)),
                abortSignal: abortSignal
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            if googleInteractionsIsTerminal(raw["status"]?.stringValue) {
                return raw
            }
            try await sleepWithAbortSignal(nanoseconds: 10_000_000, abortSignal: abortSignal)
        } while DispatchTime.now().uptimeNanoseconds - started < timeoutNanoseconds

        throw AIError.invalidResponse(provider: providerID, message: "Google Interactions polling timed out.")
    }
}

extension GoogleGenerativeLanguageModel {
    static func imageGenerationContentBody(prompt: String, aspectRatio: String?) -> [String: JSONValue] {
        var generationConfig: [String: JSONValue] = ["responseModalities": .array(["IMAGE"])]
        if let aspectRatio {
            generationConfig["imageConfig"] = .object(["aspectRatio": .string(aspectRatio)])
        }
        return [
            "contents": .array([
                .object([
                    "role": .string("user"),
                    "parts": .array([.object(["text": .string(prompt)])])
                ])
            ]),
            "generationConfig": .object(generationConfig)
        ]
    }
}

private func googleImagenParameters(for request: ImageGenerationRequest) -> [String: JSONValue] {
    var parameters: [String: JSONValue] = ["sampleCount": .number(Double(request.count ?? 1))]
    if let aspectRatio = googleAspectRatio(from: request) {
        parameters["aspectRatio"] = .string(aspectRatio)
    }
    parameters.merge(googleOptionsWithoutPoll(googleImageProviderOptions(from: request.extraBody), excluding: ["googleSearch", "edit"])) { _, new in new }
    if let seed = request.extraBody["seed"] {
        parameters["seed"] = seed
    }
    return parameters
}

private func googleImagenEditParameters(for request: ImageGenerationRequest, options: [String: JSONValue], edit: [String: JSONValue]) -> [String: JSONValue] {
    var parameters = googleImagenParameters(for: request)
    parameters["editMode"] = edit["mode"] ?? .string("EDIT_MODE_INPAINT_INSERTION")
    if let baseSteps = edit["baseSteps"] {
        parameters["editConfig"] = .object(["baseSteps": baseSteps])
    }
    return parameters
}

private func googleImageProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    if let googleVertex = extraBody["googleVertex"]?.objectValue {
        return googleVertex
    }
    if let vertex = extraBody["vertex"]?.objectValue {
        return vertex
    }
    return extraBody.filter { $0.key != "googleVertex" && $0.key != "vertex" }
}

private func googleImageEditBase64(_ file: ImageInputFile) throws -> String {
    if file.url != nil {
        throw AIError.invalidArgument(argument: "files", message: "URL-based images are not supported for Google Vertex image editing. Provide image data directly.")
    }
    guard let data = file.data else {
        throw AIError.invalidArgument(argument: "files", message: "Image file must contain data for Google Vertex image editing.")
    }
    return data.base64EncodedString()
}

private func googleVideoInstance(for request: VideoGenerationRequest) -> [String: JSONValue] {
    var instance: [String: JSONValue] = ["prompt": .string(request.prompt)]
    if let image = request.extraBody["image"]?.objectValue {
        if let data = image["data"]?.stringValue {
            instance["image"] = .object([
                "inlineData": .object([
                    "mimeType": image["mimeType"] ?? .string("image/png"),
                    "data": .string(data)
                ])
            ])
        }
    }
    if let referenceImages = request.extraBody["referenceImages"] {
        instance["referenceImages"] = referenceImages
    }
    return instance
}

private func googleVideoParameters(for request: VideoGenerationRequest) -> [String: JSONValue] {
    var parameters: [String: JSONValue] = ["sampleCount": request.extraBody["sampleCount"] ?? request.extraBody["n"] ?? .number(1)]
    if let aspectRatio = request.aspectRatio {
        parameters["aspectRatio"] = .string(aspectRatio)
    }
    if let resolution = request.extraBody["resolution"]?.stringValue {
        parameters["resolution"] = .string(googleVideoResolution(resolution))
    }
    if let duration = request.durationSeconds {
        parameters["durationSeconds"] = .number(duration)
    }
    if let seed = request.extraBody["seed"] {
        parameters["seed"] = seed
    }
    parameters.merge(googleOptionsWithoutPoll(request.extraBody, excluding: ["sampleCount", "n", "resolution", "seed", "pollIntervalMs", "pollTimeoutMs", "image", "referenceImages"])) { _, new in new }
    return parameters
}

private func googleOptionsWithoutPoll(_ options: [String: JSONValue], excluding keys: Set<String>) -> [String: JSONValue] {
    options.filter { !keys.contains($0.key) }
}

private func googleAspectRatio(from request: ImageGenerationRequest) -> String? {
    if let aspectRatio = request.extraBody["aspectRatio"]?.stringValue {
        return aspectRatio
    }
    if let size = request.size, size.contains(":") {
        return size
    }
    return nil
}

private func googleVideoResolution(_ resolution: String) -> String {
    switch resolution {
    case "1280x720":
        return "720p"
    case "1920x1080":
        return "1080p"
    case "3840x2160":
        return "4k"
    default:
        return resolution
    }
}

private func googlePollTimeout(_ extraBody: [String: JSONValue]) -> UInt64 {
    let milliseconds = extraBody["pollTimeoutMs"]?.intValue ?? 600_000
    return UInt64(milliseconds) * 1_000_000
}

private func googlePollInterval(_ extraBody: [String: JSONValue]) -> UInt64 {
    let milliseconds = extraBody["pollIntervalMs"]?.intValue ?? 10_000
    return UInt64(milliseconds) * 1_000_000
}

private func googleInteractionsHeaders(_ requestHeaders: [String: String]) -> [String: String] {
    ["Api-Revision": "2026-05-20"].mergingHeaders(requestHeaders)
}

private struct GoogleInteractionsPreparedCall {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
}

private func googleInteractionsPreparedCall(for request: LanguageModelRequest, modelID: String, agent: String?, stream: Bool) throws -> GoogleInteractionsPreparedCall {
    var options = googleGenerateContentOptions(from: request.extraBody)
    let callResponseFormat = googleInteractionsResolvedCallResponseFormat(request: request, options: &options)
    let providerResponseFormat = options.removeValue(forKey: "responseFormat")
    let systemInstruction = request.messages
        .filter { $0.role == .system }
        .map(\.combinedText)
        .joined(separator: "\n\n")
    let input = try request.messages
        .filter { $0.role != .system }
        .compactMap { try googleInteractionsStep($0) }

    var body: [String: JSONValue] = [
        agent == nil ? "model" : "agent": .string(agent ?? modelID),
        "input": .array(input)
    ]
    if stream, agent == nil {
        body["stream"] = true
    }
    if !systemInstruction.isEmpty {
        body["system_instruction"] = .string(systemInstruction)
    }
    if agent == nil {
        var generationConfig: [String: JSONValue] = [:]
        if let temperature = request.temperature { generationConfig["temperature"] = .number(temperature) }
        if let topP = request.topP { generationConfig["top_p"] = .number(topP) }
        if let maxOutputTokens = request.maxOutputTokens { generationConfig["max_output_tokens"] = .number(Double(maxOutputTokens)) }
        if !request.stopSequences.isEmpty { generationConfig["stop_sequences"] = .array(request.stopSequences) }
        if let thinkingLevel = request.extraBody["thinkingLevel"] { generationConfig["thinking_level"] = thinkingLevel }
        if let thinkingSummaries = request.extraBody["thinkingSummaries"] { generationConfig["thinking_summaries"] = thinkingSummaries }
        if !generationConfig.isEmpty {
            body["generation_config"] = .object(generationConfig)
        }
    }
    body.merge(googleInteractionsOptions(from: options, callResponseFormat: callResponseFormat, providerResponseFormat: providerResponseFormat, isAgent: agent != nil)) { _, new in new }
    return GoogleInteractionsPreparedCall(
        body: body,
        warnings: googleInteractionsWarnings(callResponseFormat: callResponseFormat, isAgent: agent != nil)
    )
}

private func googleInteractionsStep(_ message: AIMessage) throws -> JSONValue? {
    switch message.role {
    case .user:
        let content = try googleInteractionsContent(message.content)
        return content.isEmpty ? nil : .object(["type": .string("user_input"), "content": .array(content)])
    case .assistant:
        let content = try googleInteractionsContent(message.content)
        return content.isEmpty ? nil : .object(["type": .string("model_output"), "content": .array(content)])
    case .tool:
        return message.combinedText.isEmpty ? nil : .object([
            "type": .string("user_input"),
            "content": .array([.object(["type": .string("text"), "text": .string(message.combinedText)])])
        ])
    case .system:
        return nil
    }
}

private func googleInteractionsContent(_ content: [AIContentPart]) throws -> [JSONValue] {
    try content.map { part in
        switch part {
        case let .text(text):
            return .object(["type": .string("text"), "text": .string(text)])
        case let .imageURL(url):
            return .object(["type": .string("image"), "uri": .string(url)])
        case let .data(mimeType, data), let .file(mimeType, data, _):
            let resolvedMimeType = try resolveFullMediaType(mediaType: mimeType, data: data)
            let topLevel = resolvedMimeType.split(separator: "/").first.map(String.init) ?? "document"
            let type = ["image", "audio", "video"].contains(topLevel) ? topLevel : "document"
            return .object([
                "type": .string(type),
                "mime_type": .string(resolvedMimeType),
                "data": .string(data.base64EncodedString())
            ])
        case let .toolCall(call):
            return .object([
                "type": .string("function_call"),
                "name": .string(call.name),
                "arguments": googleToolArguments(call.arguments)
            ])
        case let .toolResult(result):
            return .object([
                "type": .string("function_response"),
                "name": .string(result.toolName),
                "response": result.modelOutput ?? result.result
            ])
        case .toolApprovalRequest, .toolApprovalResponse:
            return .object(["type": .string("text"), "text": .string("")])
        }
    }
}

private func googleToolArguments(_ arguments: String) -> JSONValue {
    (try? decodeJSONBody(Data(arguments.utf8))) ?? .object([:])
}

private func googleInteractionsOptions(from extraBody: [String: JSONValue], callResponseFormat: JSONValue?, providerResponseFormat: JSONValue?, isAgent: Bool) -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    if let previousInteractionId = extraBody["previousInteractionId"] { output["previous_interaction_id"] = previousInteractionId }
    if let serviceTier = extraBody["serviceTier"] { output["service_tier"] = serviceTier }
    if let store = extraBody["store"] { output["store"] = store }
    if let background = extraBody["background"] { output["background"] = background }
    if let responseModalities = extraBody["responseModalities"] { output["response_modalities"] = responseModalities }
    let responseFormat = googleInteractionsResponseFormat(callResponseFormat: callResponseFormat, providerResponseFormat: providerResponseFormat, isAgent: isAgent)
    if !responseFormat.isEmpty {
        output["response_format"] = .array(responseFormat)
    }
    if isAgent, let agentConfig = extraBody["agentConfig"] { output["agent_config"] = googleInteractionsSnakeCaseObject(agentConfig) }
    if isAgent, let environment = extraBody["environment"] { output["environment"] = googleInteractionsSnakeCaseObject(environment) }
    return output
}

private func googleInteractionsResolvedCallResponseFormat(request: LanguageModelRequest, options: inout [String: JSONValue]) -> JSONValue? {
    if let responseFormat = request.responseFormat {
        if googleInteractionsIsCallResponseFormat(options["responseFormat"]) {
            options.removeValue(forKey: "responseFormat")
        }
        return googleInteractionsResponseFormatJSON(responseFormat)
    }
    guard googleInteractionsIsCallResponseFormat(options["responseFormat"]) else {
        return nil
    }
    return options.removeValue(forKey: "responseFormat")
}

private func googleInteractionsIsCallResponseFormat(_ value: JSONValue?) -> Bool {
    guard let type = value?.objectValue?["type"]?.stringValue else { return false }
    return type == "json" || type == "text"
}

private func googleInteractionsResponseFormatJSON(_ responseFormat: AIResponseFormat) -> JSONValue? {
    switch responseFormat {
    case .text:
        return nil
    case let .json(schema, name, description):
        return .object([
            "type": .string("json"),
            "schema": schema,
            "name": name.map(JSONValue.string),
            "description": description.map(JSONValue.string)
        ])
    }
}

private func googleInteractionsResponseFormat(callResponseFormat: JSONValue?, providerResponseFormat: JSONValue?, isAgent: Bool) -> [JSONValue] {
    var entries: [JSONValue] = []
    if !isAgent, callResponseFormat?["type"]?.stringValue == "json" {
        var entry: [String: JSONValue] = [
            "type": .string("text"),
            "mime_type": .string("application/json")
        ]
        if let schema = callResponseFormat?["schema"] {
            entry["schema"] = schema
        }
        entries.append(.object(entry))
    }
    if let providerResponseFormat {
        if let providerEntries = providerResponseFormat.arrayValue {
            entries.append(contentsOf: providerEntries.map(googleInteractionsSnakeCaseObject))
        } else {
            entries.append(googleInteractionsSnakeCaseObject(providerResponseFormat))
        }
    }
    return entries
}

private func googleInteractionsWarnings(callResponseFormat: JSONValue?, isAgent: Bool) -> [AIWarning] {
    guard isAgent, callResponseFormat?["type"]?.stringValue == "json" else { return [] }
    return [
        AIWarning(
            type: "other",
            message: "google.interactions: structured output (responseFormat) is not supported when an agent is set; responseFormat will be ignored."
        )
    ]
}

private func googleInteractionsSnakeCaseObject(_ value: JSONValue) -> JSONValue {
    guard let object = value.objectValue else { return value }
    var converted: [String: JSONValue] = [:]
    for (key, value) in object {
        let mappedKey: String
        switch key {
        case "mimeType": mappedKey = "mime_type"
        case "aspectRatio": mappedKey = "aspect_ratio"
        case "imageSize": mappedKey = "image_size"
        case "thinkingSummaries": mappedKey = "thinking_summaries"
        case "collaborativePlanning": mappedKey = "collaborative_planning"
        default: mappedKey = key
        }
        converted[mappedKey] = googleInteractionsSnakeCaseObject(value)
    }
    return .object(converted)
}

private func googleInteractionsText(from raw: JSONValue) -> String {
    (raw["steps"]?.arrayValue ?? []).compactMap { step in
        guard step["type"]?.stringValue == "model_output" else { return nil }
        return step["content"]?.arrayValue?.compactMap { block in
            block["type"]?.stringValue == "text" ? block["text"]?.stringValue : nil
        }.joined()
    }.joined()
}

private func googleInteractionsProviderMetadata(from raw: JSONValue) -> [String: JSONValue] {
    var google: [String: JSONValue] = [:]
    if let id = raw["id"] {
        google["interactionId"] = id
    }
    if let serviceTier = raw["service_tier"] {
        google["serviceTier"] = serviceTier
    }
    guard !google.isEmpty else { return [:] }
    return ["google": .object(google)]
}

private func googleInteractionsSources(from raw: JSONValue) -> [AISource] {
    var sourceCounter = 0
    var emittedKeys: Set<String> = []
    return googleInteractionsSources(from: raw, sourceCounter: &sourceCounter, emittedKeys: &emittedKeys)
}

private func googleInteractionsSources(from raw: JSONValue, sourceCounter: inout Int, emittedKeys: inout Set<String>) -> [AISource] {
    var sources: [AISource] = []

    if let steps = raw["steps"]?.arrayValue {
        for step in steps {
            sources.append(contentsOf: googleInteractionsSources(fromStep: step, sourceCounter: &sourceCounter, emittedKeys: &emittedKeys))
        }
    }

    if let step = raw["step"] {
        sources.append(contentsOf: googleInteractionsSources(fromStep: step, sourceCounter: &sourceCounter, emittedKeys: &emittedKeys))
    }

    if let delta = raw["delta"],
       delta["type"]?.stringValue == "text_annotation" || delta["type"]?.stringValue == "text_annotation_delta" {
        sources.append(contentsOf: googleInteractionsSources(fromAnnotations: delta["annotations"]?.arrayValue, sourceCounter: &sourceCounter, emittedKeys: &emittedKeys))
    }

    return sources
}

private func googleInteractionsSources(fromStep step: JSONValue, sourceCounter: inout Int, emittedKeys: inout Set<String>) -> [AISource] {
    var sources: [AISource] = []
    if step["type"]?.stringValue == "model_output" {
        for block in step["content"]?.arrayValue ?? [] where block["type"]?.stringValue == "text" {
            sources.append(contentsOf: googleInteractionsSources(fromAnnotations: block["annotations"]?.arrayValue, sourceCounter: &sourceCounter, emittedKeys: &emittedKeys))
        }
    }
    sources.append(contentsOf: googleInteractionsBuiltinToolResultSources(from: step, sourceCounter: &sourceCounter, emittedKeys: &emittedKeys))
    return sources
}

private func googleInteractionsSources(fromAnnotations annotations: [JSONValue]?, sourceCounter: inout Int, emittedKeys: inout Set<String>) -> [AISource] {
    annotations?.compactMap { annotation in
        guard let source = googleInteractionsAnnotationSource(from: annotation, id: "interactions-source-\(sourceCounter)") else {
            return nil
        }
        let key = googleInteractionsSourceKey(source)
        guard !emittedKeys.contains(key) else {
            return nil
        }
        emittedKeys.insert(key)
        sourceCounter += 1
        return source
    } ?? []
}

private func googleInteractionsAnnotationSource(from annotation: JSONValue, id: String) -> AISource? {
    switch annotation["type"]?.stringValue {
    case "url_citation":
        guard let url = annotation["url"]?.stringValue, !url.isEmpty else { return nil }
        return AISource(id: id, sourceType: "url", url: url, title: annotation["title"]?.stringValue, rawValue: annotation)
    case "file_citation":
        guard let uri = annotation["url"]?.stringValue ?? annotation["document_uri"]?.stringValue ?? annotation["file_name"]?.stringValue, !uri.isEmpty else {
            return nil
        }
        if googleInteractionsIsHTTP(uri) {
            return AISource(id: id, sourceType: "url", url: uri, title: annotation["file_name"]?.stringValue, rawValue: annotation)
        }
        let filename = annotation["file_name"]?.stringValue ?? googleInteractionsBasename(uri)
        return AISource(
            id: id,
            sourceType: "document",
            title: annotation["file_name"]?.stringValue ?? filename ?? uri,
            mediaType: googleInteractionsDocumentMediaType(uri),
            filename: filename,
            rawValue: annotation
        )
    case "place_citation":
        guard let url = annotation["url"]?.stringValue, !url.isEmpty else { return nil }
        return AISource(id: id, sourceType: "url", url: url, title: annotation["name"]?.stringValue, rawValue: annotation)
    default:
        return nil
    }
}

private func googleInteractionsBuiltinToolResultSources(from step: JSONValue, sourceCounter: inout Int, emittedKeys: inout Set<String>) -> [AISource] {
    guard let type = step["type"]?.stringValue else { return [] }
    let rawSources: [AISource]
    switch type {
    case "url_context_result":
        rawSources = (step["result"]?.arrayValue ?? []).compactMap { entry in
            guard let url = entry["url"]?.stringValue, !url.isEmpty else { return nil }
            if let status = entry["status"]?.stringValue, status != "success" { return nil }
            return AISource(id: "interactions-source-\(sourceCounter)", sourceType: "url", url: url, rawValue: entry)
        }
    case "google_search_result":
        rawSources = (step["result"]?.arrayValue ?? []).compactMap { entry in
            guard let url = entry["url"]?.stringValue, !url.isEmpty else { return nil }
            return AISource(id: "interactions-source-\(sourceCounter)", sourceType: "url", url: url, title: entry["title"]?.stringValue, rawValue: entry)
        }
    case "google_maps_result":
        rawSources = (step["result"]?.arrayValue ?? []).flatMap { entry in
            (entry["places"]?.arrayValue ?? []).compactMap { place in
                guard let url = place["url"]?.stringValue, !url.isEmpty else { return nil }
                return AISource(id: "interactions-source-\(sourceCounter)", sourceType: "url", url: url, title: place["name"]?.stringValue, rawValue: place)
            }
        }
    case "file_search_result":
        rawSources = (step["result"]?.arrayValue ?? []).compactMap { entry in
            guard let uri = entry["url"]?.stringValue ?? entry["document_uri"]?.stringValue ?? entry["file_name"]?.stringValue ?? entry["source"]?.stringValue, !uri.isEmpty else {
                return nil
            }
            if googleInteractionsIsHTTP(uri) {
                return AISource(id: "interactions-source-\(sourceCounter)", sourceType: "url", url: uri, title: entry["title"]?.stringValue, rawValue: entry)
            }
            let filename = entry["file_name"]?.stringValue ?? googleInteractionsBasename(uri)
            return AISource(
                id: "interactions-source-\(sourceCounter)",
                sourceType: "document",
                title: entry["title"]?.stringValue ?? entry["file_name"]?.stringValue ?? filename ?? uri,
                mediaType: googleInteractionsDocumentMediaType(uri),
                filename: filename,
                rawValue: entry
            )
        }
    default:
        return []
    }

    var sources: [AISource] = []
    for var source in rawSources {
        source.id = "interactions-source-\(sourceCounter)"
        let key = googleInteractionsSourceKey(source)
        guard !emittedKeys.contains(key) else { continue }
        emittedKeys.insert(key)
        sourceCounter += 1
        sources.append(source)
    }
    return sources
}

private func googleInteractionsSourceKey(_ source: AISource) -> String {
    if source.sourceType == "url", let url = source.url {
        return "url:\(url)"
    }
    return "doc:\(source.filename ?? source.title ?? source.id)"
}

private func googleInteractionsIsHTTP(_ value: String) -> Bool {
    value.hasPrefix("http://") || value.hasPrefix("https://")
}

private func googleInteractionsBasename(_ value: String) -> String? {
    value.split(separator: "/").last.map(String.init)
}

private func googleInteractionsDocumentMediaType(_ value: String) -> String {
    let lower = value.lowercased()
    if lower.hasSuffix(".pdf") { return "application/pdf" }
    if lower.hasSuffix(".txt") { return "text/plain" }
    if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") { return "text/markdown" }
    if lower.hasSuffix(".doc") { return "application/msword" }
    if lower.hasSuffix(".docx") { return "application/vnd.openxmlformats-officedocument.wordprocessingml.document" }
    return "application/octet-stream"
}

private func googleInteractionsHasFunctionCall(_ raw: JSONValue) -> Bool {
    (raw["steps"]?.arrayValue ?? []).contains { step in
        step["type"]?.stringValue == "function_call" || step["type"]?.stringValue == "google_search_call" || step["type"]?.stringValue == "code_execution_call"
    }
}

private func googleInteractionsToolCalls(from raw: JSONValue) -> [AIToolCall] {
    (raw["steps"]?.arrayValue ?? []).compactMap { step in
        guard step["type"]?.stringValue == "function_call",
              let name = step["name"]?.stringValue else {
            return nil
        }
        return AIToolCall(
            id: step["id"]?.stringValue ?? "tool-call-\(name)",
            name: name,
            arguments: googleInteractionsArguments(step["arguments"]),
            rawValue: step
        )
    }
}

private struct GoogleInteractionsToolCallBuffer {
    var id: String
    var name: String
    var arguments: String
    var inputStarted: Bool
    var rawValue: JSONValue?
}

private struct GoogleInteractionsStreamingToolCalls {
    private var buffers: [Int: GoogleInteractionsToolCallBuffer] = [:]

    mutating func start(step: JSONValue?, index: Int?) -> [LanguageStreamPart] {
        let key = index ?? 0
        guard let step,
              let name = step["name"]?.stringValue else {
            return []
        }
        let id = step["id"]?.stringValue ?? "tool-call-\(key)"
        let arguments = googleInteractionsArguments(step["arguments"])
        buffers[key] = GoogleInteractionsToolCallBuffer(
            id: id,
            name: name,
            arguments: arguments == "{}" ? "" : arguments,
            inputStarted: true,
            rawValue: step
        )
        var parts: [LanguageStreamPart] = [.toolInputStart(id: id, name: name)]
        if arguments != "{}" {
            parts.append(.toolCallDelta(id: id, name: name, argumentsDelta: arguments, index: key))
            parts.append(.toolInputDelta(id: id, delta: arguments))
        }
        return parts
    }

    mutating func delta(_ delta: JSONValue, index: Int?) -> [LanguageStreamPart] {
        let key = index ?? 0
        guard var buffer = buffers[key] else {
            return []
        }
        let argumentsDelta = delta["arguments"]?.stringValue ?? ""
        buffer.arguments += argumentsDelta
        buffer.rawValue = delta
        buffers[key] = buffer
        var parts: [LanguageStreamPart] = [.toolCallDelta(id: buffer.id, name: buffer.name, argumentsDelta: argumentsDelta, index: key)]
        if !argumentsDelta.isEmpty {
            parts.append(.toolInputDelta(id: buffer.id, delta: argumentsDelta))
        }
        return parts
    }

    mutating func stop(index: Int?) -> [LanguageStreamPart] {
        let key = index ?? 0
        guard let buffer = buffers[key] else {
            return []
        }
        return [
            .toolInputEnd(id: buffer.id),
            .toolCall(AIToolCall(
            id: buffer.id,
            name: buffer.name,
            arguments: buffer.arguments.isEmpty ? "{}" : buffer.arguments,
            rawValue: buffer.rawValue
            ))
        ]
    }
}

private func googleInteractionsArguments(_ value: JSONValue?) -> String {
    guard let value else { return "{}" }
    guard let data = try? encodeJSONBody(value),
          let text = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return text
}

private func googleInteractionsFinishReason(status: String?, hasFunctionCall: Bool) -> String? {
    switch status {
    case "completed":
        return hasFunctionCall ? "tool-calls" : "stop"
    case "requires_action":
        return "tool-calls"
    case "failed":
        return "error"
    case "incomplete":
        return "length"
    case "cancelled":
        return "other"
    default:
        return status
    }
}

private func googleInteractionsUsage(from raw: JSONValue) -> TokenUsage? {
    guard let usage = raw["usage"] else { return nil }
    let output = (usage["total_output_tokens"]?.intValue ?? 0) + (usage["total_thought_tokens"]?.intValue ?? 0)
    return TokenUsage(
        inputTokens: usage["total_input_tokens"]?.intValue,
        outputTokens: output == 0 && usage["total_output_tokens"] == nil && usage["total_thought_tokens"] == nil ? nil : output,
        totalTokens: usage["total_tokens"]?.intValue
    )
}

private func googleInteractionsIsTerminal(_ status: String?) -> Bool {
    switch status {
    case "completed", "failed", "incomplete", "cancelled":
        return true
    default:
        return false
    }
}

private func googleInteractionsPollTimeout(raw: JSONValue) -> UInt64 {
    let milliseconds = raw["pollingTimeoutMs"]?.intValue ?? 600_000
    return UInt64(milliseconds) * 1_000_000
}
