import Foundation

/// Routes known MAI image families to Azure AI Foundry, with a per-request API override.
public final class AzureImageModel: ImageModel, @unchecked Sendable {
    public let providerID = "azure.image"
    public let modelID: String
    private let openAI: any ImageModel
    private let mai: AzureMAIImageModel

    init(modelID: String, openAI: any ImageModel, config: AzureAudioConfig) {
        self.modelID = modelID
        self.openAI = openAI
        self.mai = AzureMAIImageModel(modelID: modelID, config: config)
    }

    private var defaultsToMAI: Bool { azureMAIImageModels.contains(modelID.lowercased()) }
    public var maxImagesPerCall: Int { defaultsToMAI ? 1 : openAIImageMaxImagesPerCall(modelID) }
    public var supportsFileInputs: Bool? { get async { defaultsToMAI ? true : await openAI.supportsFileInputs } }
    public var supportsMaskInputs: Bool? { get async { defaultsToMAI ? false : await openAI.supportsMaskInputs } }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        let options = try azureImageOptions(request.providerOptions)
        if (options["api"]?.stringValue ?? (defaultsToMAI ? "mai" : "openai")) == "mai" {
            return try await mai.generateImage(request, options: options)
        }
        var result = try await openAI.generateImage(request)
        result.warnings += options.keys.sorted().filter { $0 != "api" }.map {
            AIWarning(type: "unsupported", feature: "providerOptions.azure.\($0)", message: "This option requires the MAI image API.")
        }
        return result
    }
}

/// Native MAI image generations and multipart reference-image edits.
public final class AzureMAIImageModel: ImageModel, @unchecked Sendable {
    public let providerID = "azure.image"
    public let modelID: String
    public let supportsFileInputs: Bool? = true
    public let supportsMaskInputs: Bool? = false
    public let maxImagesPerCall = 1
    private let config: AzureAudioConfig

    init(modelID: String, config: AzureAudioConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        try await generateImage(request, options: azureImageOptions(request.providerOptions))
    }

    func generateImage(_ request: ImageGenerationRequest, options: [String: JSONValue]) async throws -> ImageGenerationResult {
        try request.abortSignal?.throwIfAborted()
        let timestamp = Date()
        var warnings: [AIWarning] = []
        if request.seed != nil { warnings.append(AIWarning(type: "unsupported", feature: "seed", message: "MAI image models do not support seed.")) }
        if request.mask != nil { warnings.append(AIWarning(type: "unsupported", feature: "mask", message: "MAI image edits do not support masks.")) }
        var dimensions: (width: Int, height: Int)?
        if let size = request.size {
            let sides = size.split(separator: "x").compactMap { Int($0) }
            if sides.count == 2 { dimensions = (sides[0], sides[1]) }
            if request.aspectRatio != nil { warnings.append(AIWarning(type: "unsupported", feature: "aspectRatio", message: "aspectRatio is ignored when size is set.")) }
        } else if let aspectRatio = request.aspectRatio {
            dimensions = azureMAIDimensionsForAspectRatio(aspectRatio)
            if dimensions == nil { warnings.append(AIWarning(type: "unsupported", feature: "aspectRatio", message: "Invalid aspect ratio: \(aspectRatio).")) }
        }
        var fields: [String: JSONValue] = ["model": .string(modelID), "prompt": .string(request.prompt)]
        if let dimensions { fields["width"] = .number(Double(dimensions.width)); fields["height"] = .number(Double(dimensions.height)) }
        fields["auto_aspect_ratio"] = options["autoAspectRatio"]
        fields["web_grounding"] = options["webGrounding"]

        var files: [(data: Data, mediaType: String)] = []
        for file in request.files {
            if let data = file.data {
                files.append((data, file.mediaType ?? "image/png"))
            } else if let url = file.url {
                let downloaded = try await downloadURL(url, transport: config.downloadTransport, abortSignal: request.abortSignal)
                guard (200..<300).contains(downloaded.statusCode) else { throw apiCallError(provider: providerID, response: downloaded) }
                files.append((downloaded.body, downloaded.headers.contentType ?? file.mediaType ?? "image/png"))
            } else {
                throw AIError.invalidArgument(argument: "files", message: "Image file must contain data or a URL.")
            }
        }
        let url = try requireURL(config.baseURL(api: "mai") + (files.isEmpty ? "/images/generations" : "/images/edits"))
        var contentType = "application/json"
        let body: Data
        if files.isEmpty {
            body = try encodeJSONBody(.object(fields))
        } else {
            var form = MultipartFormData()
            for key in fields.keys.sorted() {
                if let value = fields[key].flatMap(jsonScalarString) {
                    form.appendField(name: key, value: value)
                }
            }
            for (index, file) in files.enumerated() {
                let ext = file.mediaType == "image/jpeg" ? "jpg" : "png"
                form.appendFile(name: "image", fileName: "image-\(index + 1).\(ext)", mimeType: file.mediaType, data: file.data)
            }
            contentType = "multipart/form-data; boundary=\(form.boundary)"
            body = form.finalize()
        }
        let http = AIHTTPRequest(method: "POST", url: url, headers: config.requestHeaders(api: "mai").mergingHeaders(["Content-Type": contentType]).mergingHeaders(request.headers), body: body, abortSignal: request.abortSignal)
        let count = max(1, request.count ?? 1)
        try request.abortSignal?.throwIfAborted()
        let responses = try await withThrowingTaskGroup(of: (Int, AIHTTPResponse).self) { group in
            for index in 0..<count { group.addTask { (index, try await self.config.transport.send(http)) } }
            var values: [(Int, AIHTTPResponse)] = []
            for try await value in group { values.append(value) }
            return values.sorted { $0.0 < $1.0 }.map(\.1)
        }
        var images: [String] = []
        var metadata: [JSONValue] = []
        var rawValues: [JSONValue] = []
        var usage: TokenUsage?
        for response in responses {
            guard (200..<300).contains(response.statusCode) else {
                var error = apiCallError(provider: providerID, response: response)
                if case var .apiCall(call) = error, let message = (try? response.jsonValue())?["error"]?["message"]?.stringValue { call.message = message; error = .apiCall(call) }
                throw error
            }
            let raw = try response.jsonValue()
            guard let data = raw["data"]?.arrayValue, data.allSatisfy({ $0["b64_json"]?.stringValue != nil }),
                  azureMAIOptionalNumber(raw["created"]), raw["size"] == nil || raw["size"] == .null || raw["size"]?.stringValue != nil,
                  raw["usage"] == nil || raw["usage"] == .null || (raw["usage"]?.objectValue != nil && ["num_input_text_tokens", "num_input_image_tokens", "num_output_tokens"].allSatisfy { azureMAIOptionalNumber(raw["usage"]?[$0]) }) else {
                throw AIError.invalidResponse(provider: providerID, message: "Invalid Azure MAI image response.")
            }
            rawValues.append(raw)
            let textTokens = raw["usage"]?["num_input_text_tokens"]?.intValue
            let imageTokens = raw["usage"]?["num_input_image_tokens"]?.intValue
            if raw["usage"]?.objectValue != nil {
                let input = azureMAIAddTokens(textTokens, imageTokens)
                let output = raw["usage"]?["num_output_tokens"]?.intValue
                usage = TokenUsage(inputTokens: azureMAIAddTokens(usage?.inputTokens, input), outputTokens: azureMAIAddTokens(usage?.outputTokens, output), totalTokens: azureMAIAddTokens(usage?.totalTokens, azureMAIAddTokens(input, output)))
            }
            for item in data {
                images.append(item["b64_json"]!.stringValue!)
                var entry: [String: JSONValue] = [:]
                for key in ["created", "size"] { if let value = raw[key], value != .null { entry[key] = value } }
                if let textTokens { entry["textTokens"] = .number(Double(textTokens)) }
                if let imageTokens { entry["imageTokens"] = .number(Double(imageTokens)) }
                metadata.append(.object(entry))
            }
        }
        return ImageGenerationResult(urls: [], base64Images: images, rawValue: count == 1 ? rawValues[0] : .array(rawValues), warnings: warnings, usage: usage, providerMetadata: ["azure": .object(["images": .array(metadata)])], requestMetadata: imageGenerationRequestMetadata(request, body: .object(fields)), responseMetadata: AIResponseMetadata(timestamp: timestamp, modelID: modelID, headers: responses[0].headers))
    }
}

func azureMAIDimensionsForAspectRatio(_ aspectRatio: String) -> (width: Int, height: Int)? {
    let sides = aspectRatio.split(separator: ":").compactMap { Double($0) }
    guard sides.count == 2, sides.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
    let ratio = sides[0] / sides[1]
    var width = sqrt(1024 * 1024 * ratio)
    var height = width / ratio
    if min(width, height) < 768 { if width < height { width = 768; height = 768 / ratio } else { width = 768 * ratio; height = 768 } }
    guard width.isFinite, height.isFinite, width < Double(Int.max), height < Double(Int.max) else { return nil }
    return (max(768, Int(floor(width / 16 + 1e-9)) * 16), max(768, Int(floor(height / 16 + 1e-9)) * 16))
}

private let azureMAIImageModels: Set<String> = ["mai-image-2.5", "mai-image-2.5-flash", "mai-image-2.5-pro", "mai-image-2.6", "mai-image-2.6-flash"]
private func azureImageOptions(_ providerOptions: [String: JSONValue]) throws -> [String: JSONValue] {
    guard let value = providerOptions["azure"], value != .null else { return [:] }
    guard let raw = value.objectValue else { throw AIError.invalidArgument(argument: "providerOptions.azure", message: "Azure image options must be an object.") }
    let options = raw.filter { ["api", "autoAspectRatio", "webGrounding"].contains($0.key) }
    for (key, value) in options {
        let valid = key == "api" ? value.stringValue.map { ["openai", "mai"].contains($0) } ?? false : value.boolValue != nil
        if !valid { throw AIError.invalidArgument(argument: "providerOptions.azure.\(key)", message: "Invalid Azure image option \(key).") }
    }
    return options
}
private func azureMAIAddTokens(_ a: Int?, _ b: Int?) -> Int? { a == nil && b == nil ? nil : (a ?? 0) + (b ?? 0) }
private func azureMAIOptionalNumber(_ value: JSONValue?) -> Bool { value == nil || value == .null || value?.doubleValue?.isFinite == true }
