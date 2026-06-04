import Foundation

public final class GoogleVertexLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: GoogleVertexConfig

    init(modelID: String, config: GoogleVertexConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = try googleGenerateContentBody(request, modelID: modelID, providerID: providerID)
        let response = try await config.sendJSONResponse(path: "/models/\(modelID):generateContent", body: prepared.body, headers: request.headers.mergingHeaders(prepared.headers), abortSignal: request.abortSignal)
        let raw = response.json
        let text = googleGenerateContentText(from: raw)
        let toolCalls = googleGenerateContentToolCalls(from: raw)
        let toolResults = googleGenerateContentToolResults(from: raw)
        guard text != nil || !toolCalls.isEmpty || !toolResults.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No candidate text found in Vertex response.")
        }
        return TextGenerationResult(
            text: text ?? "",
            finishReason: googleGenerateContentFinishReason(raw["candidates"]?[0]?["finishReason"]?.stringValue, hasToolCalls: !toolCalls.isEmpty),
            usage: googleGenerateContentUsage(from: raw),
            toolCalls: toolCalls,
            toolResults: toolResults,
            sources: googleGenerateContentSources(from: raw),
            providerMetadata: googleGenerateContentProviderMetadata(from: raw),
            rawValue: raw,
            warnings: prepared.warnings,
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = try googleGenerateContentBody(request, modelID: modelID, providerID: providerID, isStreaming: true)
                    let httpRequest = try await config.request(
                        path: "/models/\(modelID):streamGenerateContent?alt=sse",
                        body: prepared.body,
                        headers: request.headers.mergingHeaders(prepared.headers),
                        abortSignal: request.abortSignal
                    )
                    let response = try await config.transport.send(httpRequest)
                    let parts = try streamFromGoogleGenerateContent(
                        providerID: providerID,
                        response: response,
                        includeRawChunks: request.includeRawChunks,
                        modelID: modelID,
                        warnings: prepared.warnings
                    )
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
}

public final class GoogleVertexEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: GoogleVertexConfig

    init(modelID: String, config: GoogleVertexConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        guard request.values.count <= 2048 else {
            throw AITooManyEmbeddingValuesForCallError(
                provider: providerID,
                modelID: modelID,
                maxEmbeddingsPerCall: 2048,
                values: request.values
            )
        }
        let options = googleVertexEmbeddingProviderOptions(from: request)
        var parameters: [String: JSONValue] = [:]
        if let dimensions = request.dimensions {
            parameters["outputDimensionality"] = .number(Double(dimensions))
        }
        if let outputDimensionality = options["outputDimensionality"] {
            parameters["outputDimensionality"] = outputDimensionality
        }
        if let autoTruncate = options["autoTruncate"] {
            parameters["autoTruncate"] = autoTruncate
        }
        let taskType = options["taskType"]
        let title = options["title"]
        var body: [String: JSONValue] = [
            "instances": .array(request.values.map { value in
                var instance: [String: JSONValue] = ["content": .string(value)]
                if let taskType { instance["task_type"] = taskType }
                if let title { instance["title"] = title }
                return .object(instance)
            })
        ]
        if !parameters.isEmpty { body["parameters"] = .object(parameters) }
        body.merge(request.extraBody) { _, new in new }
        let response = try await config.sendJSONResponse(path: "/models/\(modelID):predict", body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let embeddings = raw["predictions"]?.arrayValue?.compactMap { prediction in
            prediction["embeddings"]?["values"]?.arrayValue?.compactMap(\.doubleValue)
        } ?? []
        let totalTokens = raw["predictions"]?.arrayValue?.reduce(0) { partial, prediction in
            partial + (prediction["embeddings"]?["statistics"]?["token_count"]?.intValue ?? 0)
        }
        return EmbeddingResult(
            embeddings: embeddings,
            usage: totalTokens.map { TokenUsage(totalTokens: $0) },
            rawValue: raw,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

public final class GoogleVertexImageModel: ImageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: GoogleVertexConfig

    init(modelID: String, config: GoogleVertexConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        if modelID.starts(with: "gemini-") {
            let languageResult = try await GoogleVertexLanguageModel(modelID: modelID, config: config).generate(LanguageModelRequest(messages: [.user(request.prompt)], extraBody: request.extraBody, headers: request.headers, abortSignal: request.abortSignal))
            let images = languageResult.rawValue["candidates"]?[0]?["content"]?["parts"]?.arrayValue?.compactMap { part in
                part["inlineData"]?["data"]?.stringValue
            } ?? []
            return ImageGenerationResult(
                urls: [],
                base64Images: images,
                rawValue: languageResult.rawValue,
                requestMetadata: imageGenerationRequestMetadata(request),
                responseMetadata: languageResult.responseMetadata
            )
        }

        let body = try googleVertexImageBody(for: request)
        let response = try await config.sendJSONResponse(path: "/models/\(modelID):predict", body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let images = raw["predictions"]?.arrayValue?.compactMap { prediction in
            prediction["bytesBase64Encoded"]?.stringValue
        } ?? []
        return ImageGenerationResult(
            urls: [],
            base64Images: images,
            rawValue: raw,
            requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

public final class GoogleVertexVideoModel: VideoModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: GoogleVertexConfig

    init(modelID: String, config: GoogleVertexConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        let options = googleVertexVideoProviderOptions(from: request)
        var warnings: [AIWarning] = []
        var instance: [String: JSONValue] = [:]
        if !request.prompt.isEmpty {
            instance["prompt"] = .string(request.prompt)
        }
        if let image = request.image {
            if image.url != nil {
                warnings.append(AIWarning(
                    type: "unsupported",
                    feature: "URL-based image input",
                    message: "Vertex AI video models require base64-encoded images or GCS URIs. URL will be ignored."
                ))
            } else if let data = image.data {
                instance["image"] = .object([
                    "bytesBase64Encoded": .string(data.base64EncodedString()),
                    "mimeType": .string(image.mediaType ?? "image/png")
                ])
            }
        }
        if let referenceImages = options["referenceImages"] {
            instance["referenceImages"] = referenceImages
        }

        var parameters: [String: JSONValue] = [:]
        if let count = request.count { parameters["sampleCount"] = .number(Double(count)) }
        if let aspectRatio = request.aspectRatio { parameters["aspectRatio"] = .string(aspectRatio) }
        if let resolution = request.resolution { parameters["resolution"] = .string(googleVertexVideoResolution(resolution)) }
        if let duration = request.durationSeconds { parameters["durationSeconds"] = .number(duration) }
        if let seed = request.seed { parameters["seed"] = .number(Double(seed)) }
        parameters.merge(options.filter { key, value in
            !googleVertexVideoInternalOptionKeys.contains(key) && value != .null
        }) { _, new in new }
        var body: [String: JSONValue] = [
            "instances": .array([.object(instance)])
        ]
        if !parameters.isEmpty { body["parameters"] = .object(parameters) }
        let initialResponse = try await config.sendJSONResponse(path: "/models/\(modelID):predictLongRunning", body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let operationName = try googleVertexVideoOperationName(from: initialResponse.json, providerID: providerID)
        let finalResponse = try await googleVertexPollVideoOperation(
            initial: initialResponse,
            operationName: operationName,
            config: config,
            modelID: modelID,
            headers: request.headers,
            options: options,
            abortSignal: request.abortSignal
        )
        let raw = finalResponse.json
        let videos = raw["response"]?["videos"]?.arrayValue ?? raw["videos"]?.arrayValue ?? []
        guard !videos.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No videos in Vertex video response.")
        }
        let urls = videos.compactMap { $0["gcsUri"]?.stringValue ?? $0["url"]?.stringValue }
        let base64Videos = videos.compactMap { $0["bytesBase64Encoded"]?.stringValue }
        guard !urls.isEmpty || !base64Videos.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No valid videos in Vertex video response.")
        }
        return VideoGenerationResult(
            urls: urls,
            base64Videos: base64Videos,
            operationID: operationName,
            rawValue: raw,
            warnings: warnings,
            providerMetadata: ["google-vertex": .object([
                "videos": .array(videos.map { video in
                    .object([
                        "gcsUri": video["gcsUri"] ?? .null,
                        "mimeType": video["mimeType"] ?? .null
                    ])
                })
            ])],
            requestMetadata: videoGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: finalResponse.response, modelID: modelID)
        )
    }
}

private struct GoogleVertexGenerateContentPreparedCall {
    var body: JSONValue
    var warnings: [AIWarning]
    var headers: [String: String]
}

private func googleGenerateContentBody(_ request: LanguageModelRequest, modelID: String, providerID: String, isStreaming: Bool = false) throws -> GoogleVertexGenerateContentPreparedCall {
    let preparedOptions = googlePrepareGenerateContentOptions(
        from: request,
        modelID: modelID,
        providerID: providerID,
        isVertexProvider: true
    )
    var options = preparedOptions.options
    let responseFormat = googleResolvedResponseFormat(request: request, options: &options)
    var warnings = preparedOptions.warnings
    let systemText = request.messages.filter { $0.role == .system }.map(\.combinedText).joined(separator: "\n")
    let rawContents = try request.messages.filter { $0.role != .system }.map { message in
        try googleGenerateContentMessageJSON(message, modelID: modelID, warnings: &warnings)
    }
    let preparedMessages = googleContentsWithSystemInstruction(systemText: systemText, contents: rawContents, modelID: modelID)
    var body: [String: JSONValue] = ["contents": .array(preparedMessages.contents)]
    if let systemInstruction = preparedMessages.systemInstruction {
        body["systemInstruction"] = systemInstruction
    }
    var generationConfig: [String: JSONValue] = [:]
    googleApplyStandardGenerationSettings(request, to: &generationConfig)
    googleApplyResponseFormat(responseFormat, options: options, to: &generationConfig)
    googleApplyProviderGenerationOptions(options, to: &generationConfig)
    if !generationConfig.isEmpty { body["generationConfig"] = .object(generationConfig) }
    if let preparedTools = googlePrepareTools(from: request.tools, toolChoice: options["toolChoice"], modelID: modelID, isVertexProvider: true) {
        warnings.append(contentsOf: preparedTools.warnings)
        if !preparedTools.tools.isEmpty {
            body["tools"] = .array(preparedTools.tools)
        }
        if let toolConfig = googleToolConfigWithProviderOptions(preparedTools.toolConfig, options: options, isStreaming: isStreaming, isVertexProvider: true) {
            body["toolConfig"] = toolConfig
        }
    } else if let toolConfig = googleToolConfigWithProviderOptions(nil, options: options, isStreaming: isStreaming, isVertexProvider: true) {
        body["toolConfig"] = toolConfig
    }
    body.merge(googleTopLevelGenerateContentOptions(options)) { _, new in new }
    body.merge(googleExtraBodyWithoutToolChoice(options)) { _, new in new }
    return GoogleVertexGenerateContentPreparedCall(body: .object(body), warnings: warnings, headers: preparedOptions.headers)
}

private func googleVertexImageBody(for request: ImageGenerationRequest) throws -> [String: JSONValue] {
    let options = googleVertexImageProviderOptions(from: request.extraBody)
    if request.files.isEmpty {
        var body: [String: JSONValue] = [
            "instances": .array([.object(["prompt": .string(request.prompt)])])
        ]
        let parameters = googleVertexImagenParameters(for: request, options: options)
        if !parameters.isEmpty {
            body["parameters"] = .object(parameters)
        }
        return body
    }

    let edit = options["edit"]?.objectValue ?? [:]
    var referenceImages: [JSONValue] = []
    for (index, file) in request.files.enumerated() {
        referenceImages.append(.object([
            "referenceType": .string("REFERENCE_TYPE_RAW"),
            "referenceId": .number(Double(index + 1)),
            "referenceImage": .object([
                "bytesBase64Encoded": .string(try googleVertexImageEditBase64(file))
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
                "bytesBase64Encoded": .string(try googleVertexImageEditBase64(mask))
            ]),
            "maskImageConfig": .object(maskImageConfig)
        ]))
    }

    var parameters = googleVertexImagenParameters(for: request, options: options)
    parameters["editMode"] = edit["mode"] ?? .string("EDIT_MODE_INPAINT_INSERTION")
    if let baseSteps = edit["baseSteps"] {
        parameters["editConfig"] = .object(["baseSteps": baseSteps])
    }

    return [
        "instances": .array([.object([
            "prompt": .string(request.prompt),
            "referenceImages": .array(referenceImages)
        ])]),
        "parameters": .object(parameters)
    ]
}

private func googleVertexImagenParameters(for request: ImageGenerationRequest, options: [String: JSONValue]) -> [String: JSONValue] {
    var parameters: [String: JSONValue] = ["sampleCount": .number(Double(request.count ?? 1))]
    if let aspectRatio = googleVertexImageAspectRatio(from: request) {
        parameters["aspectRatio"] = .string(aspectRatio)
    }
    parameters.merge(options.filter { key, _ in key != "edit" && key != "googleSearch" }) { _, new in new }
    if let seed = request.extraBody["seed"] {
        parameters["seed"] = seed
    }
    return parameters
}

private func googleVertexImageProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    if let googleVertex = extraBody["googleVertex"]?.objectValue {
        return googleVertex
    }
    if let vertex = extraBody["vertex"]?.objectValue {
        return vertex
    }
    return extraBody.filter { $0.key != "googleVertex" && $0.key != "vertex" }
}

private func googleVertexEmbeddingProviderOptions(from request: EmbeddingRequest) -> [String: JSONValue] {
    if let googleVertex = request.providerOptions["googleVertex"]?.objectValue {
        return googleVertex
    }
    if let vertex = request.providerOptions["vertex"]?.objectValue {
        return vertex
    }
    if let google = request.providerOptions["google"]?.objectValue {
        return google
    }
    return [:]
}

private func googleVertexVideoProviderOptions(from request: VideoGenerationRequest) -> [String: JSONValue] {
    var options = request.extraBody
    if let googleVertex = request.providerOptions["googleVertex"]?.objectValue {
        options.merge(googleVertex) { _, new in new }
    } else if let vertex = request.providerOptions["vertex"]?.objectValue {
        options.merge(vertex) { _, new in new }
    }
    return options
}

private let googleVertexVideoInternalOptionKeys: Set<String> = [
    "pollIntervalMs",
    "pollTimeoutMs",
    "referenceImages"
]

private func googleVertexVideoResolution(_ resolution: String) -> String {
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

private func googleVertexPollVideoOperation(
    initial: (json: JSONValue, response: AIHTTPResponse),
    operationName: String,
    config: GoogleVertexConfig,
    modelID: String,
    headers: [String: String],
    options: [String: JSONValue],
    abortSignal: AIAbortSignal?
) async throws -> (json: JSONValue, response: AIHTTPResponse) {
    var current = initial
    let pollIntervalNanoseconds = googleVertexVideoPollInterval(options)
    let pollTimeoutNanoseconds = googleVertexVideoPollTimeout(options)
    let started = DispatchTime.now().uptimeNanoseconds
    while current.json["done"]?.boolValue != true {
        if DispatchTime.now().uptimeNanoseconds - started > pollTimeoutNanoseconds {
            throw AIError.invalidResponse(provider: config.providerID, message: "Video generation timed out after \(pollTimeoutNanoseconds / 1_000_000)ms.")
        }
        try await sleepWithAbortSignal(nanoseconds: pollIntervalNanoseconds, abortSignal: abortSignal)
        current = try await config.sendJSONResponse(
            path: "/models/\(modelID):fetchPredictOperation",
            body: .object(["operationName": .string(operationName)]),
            headers: headers,
            abortSignal: abortSignal
        )
    }
    if let message = current.json["error"]?["message"]?.stringValue {
        throw AIError.invalidResponse(provider: config.providerID, message: "Video generation failed: \(message)")
    }
    return current
}

private func googleVertexVideoOperationName(from operation: JSONValue, providerID: String) throws -> String {
    guard let operationName = operation["name"]?.stringValue, !operationName.isEmpty else {
        throw AIError.invalidResponse(provider: providerID, message: "No operation name returned from Vertex video response.")
    }
    return operationName
}

private func googleVertexVideoPollInterval(_ options: [String: JSONValue]) -> UInt64 {
    let milliseconds = options["pollIntervalMs"]?.intValue ?? 10_000
    return UInt64(milliseconds) * 1_000_000
}

private func googleVertexVideoPollTimeout(_ options: [String: JSONValue]) -> UInt64 {
    let milliseconds = options["pollTimeoutMs"]?.intValue ?? 600_000
    return UInt64(milliseconds) * 1_000_000
}

private func googleVertexImageAspectRatio(from request: ImageGenerationRequest) -> String? {
    if let aspectRatio = request.extraBody["aspectRatio"]?.stringValue {
        return aspectRatio
    }
    if let size = request.size, size.contains(":") {
        return size
    }
    return nil
}

private func googleVertexImageEditBase64(_ file: ImageInputFile) throws -> String {
    if file.url != nil {
        throw AIError.invalidArgument(argument: "files", message: "URL-based images are not supported for Google Vertex image editing. Provide image data directly.")
    }
    guard let data = file.data else {
        throw AIError.invalidArgument(argument: "files", message: "Image file must contain data for Google Vertex image editing.")
    }
    return data.base64EncodedString()
}
