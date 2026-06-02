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
        let response = try await config.sendJSONResponse(path: "/models/\(modelID):generateContent", body: googleGenerateContentBody(request, modelID: modelID), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let text = googleGenerateContentText(from: raw)
        let toolCalls = googleGenerateContentToolCalls(from: raw)
        guard text != nil || !toolCalls.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No candidate text found in Vertex response.")
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
                    let httpRequest = try await config.request(
                        path: "/models/\(modelID):streamGenerateContent?alt=sse",
                        body: googleGenerateContentBody(request, modelID: modelID),
                        headers: request.headers,
                        abortSignal: request.abortSignal
                    )
                    let response = try await config.transport.send(httpRequest)
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
        var parameters: [String: JSONValue] = [:]
        if let dimensions = request.dimensions {
            parameters["outputDimensionality"] = .number(Double(dimensions))
        }
        var body: [String: JSONValue] = [
            "instances": .array(request.values.map { .object(["content": .string($0)]) })
        ]
        if !parameters.isEmpty { body["parameters"] = .object(parameters) }
        body.merge(request.extraBody) { _, new in new }
        let response = try await config.sendJSONResponse(path: "/models/\(modelID):predict", body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let embeddings = raw["predictions"]?.arrayValue?.compactMap { prediction in
            prediction["embeddings"]?["values"]?.arrayValue?.compactMap(\.doubleValue)
        } ?? []
        return EmbeddingResult(
            embeddings: embeddings,
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
        var parameters: [String: JSONValue] = [:]
        if let count = request.count { parameters["sampleCount"] = .number(Double(count)) }
        if let aspectRatio = request.aspectRatio { parameters["aspectRatio"] = .string(aspectRatio) }
        if let duration = request.durationSeconds { parameters["durationSeconds"] = .number(duration) }
        var body: [String: JSONValue] = [
            "instances": .array([.object(["prompt": .string(request.prompt)])])
        ]
        if !parameters.isEmpty { body["parameters"] = .object(parameters) }
        body.merge(request.extraBody) { _, new in new }
        let response = try await config.sendJSONResponse(path: "/models/\(modelID):predictLongRunning", body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let videos = raw["response"]?["videos"]?.arrayValue ?? raw["videos"]?.arrayValue ?? []
        return VideoGenerationResult(
            urls: videos.compactMap { $0["gcsUri"]?.stringValue ?? $0["url"]?.stringValue },
            operationID: raw["name"]?.stringValue,
            rawValue: raw,
            requestMetadata: videoGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

private func googleGenerateContentBody(_ request: LanguageModelRequest, modelID: String) -> JSONValue {
    var options = googleGenerateContentOptions(from: request.extraBody)
    let responseFormat = googleResolvedResponseFormat(request: request, options: &options)
    let systemText = request.messages.filter { $0.role == .system }.map(\.combinedText).joined(separator: "\n")
    let contents = request.messages.filter { $0.role != .system }.map { message in
        JSONValue.object([
            "role": .string(message.role == .assistant ? "model" : "user"),
            "parts": .array(message.content.map { part in
                switch part {
                case let .text(text):
                    return .object(["text": .string(text)])
                case let .imageURL(url):
                    return .object(["fileData": .object(["fileUri": .string(url)])])
                case let .data(mimeType, data), let .file(mimeType, data, _):
                    return .object(["inlineData": .object(["mimeType": .string(mimeType), "data": .string(data.base64EncodedString())])])
                case let .providerReference(_, reference):
                    return .object(["fileData": .object(["fileUri": .string((try? resolveProviderReference(reference, provider: "google")) ?? reference.values.first ?? "")])])
                case let .toolCall(call):
                    return .object([
                        "functionCall": .object([
                            "name": .string(call.name),
                            "args": googleVertexToolArguments(call.arguments)
                        ])
                    ])
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
            })
        ])
    }
    var body: [String: JSONValue] = ["contents": .array(contents)]
    if !systemText.isEmpty {
        body["systemInstruction"] = .object(["parts": .array([.object(["text": .string(systemText)])])])
    }
    var generationConfig: [String: JSONValue] = [:]
    if let temperature = request.temperature { generationConfig["temperature"] = .number(temperature) }
    if let topP = request.topP { generationConfig["topP"] = .number(topP) }
    if let maxOutputTokens = request.maxOutputTokens { generationConfig["maxOutputTokens"] = .number(Double(maxOutputTokens)) }
    if !request.stopSequences.isEmpty { generationConfig["stopSequences"] = .array(request.stopSequences) }
    googleApplyResponseFormat(responseFormat, options: options, to: &generationConfig)
    if !generationConfig.isEmpty { body["generationConfig"] = .object(generationConfig) }
    if let preparedTools = googlePrepareTools(from: request.tools, toolChoice: options["toolChoice"], modelID: modelID, isVertexProvider: true) {
        body["tools"] = .array(preparedTools.tools)
        if let toolConfig = preparedTools.toolConfig {
            body["toolConfig"] = toolConfig
        }
    }
    body.merge(googleExtraBodyWithoutToolChoice(options)) { _, new in new }
    return .object(body)
}

private func googleVertexToolArguments(_ arguments: String) -> JSONValue {
    (try? decodeJSONBody(Data(arguments.utf8))) ?? .object([:])
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
