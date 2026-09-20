import Foundation

public enum QuiverAIImageReference: Equatable, Sendable {
    case url(String)
    case base64(String)

    public var jsonValue: JSONValue {
        switch self {
        case let .url(url):
            return .object(["url": .string(url)])
        case let .base64(base64):
            return .object(["base64": .string(base64)])
        }
    }
}

public func prepareQuiverAIImageReference(_ input: URL) throws -> QuiverAIImageReference {
    .url(try quiverAIValidatedImageURL(input.absoluteString, argument: "input"))
}

public func prepareQuiverAIImageReference(_ input: Data) throws -> QuiverAIImageReference {
    try quiverAIValidateReferenceData(input, argument: "input")
    return .base64(input.base64EncodedString())
}

public func prepareQuiverAIImageReference(_ input: String) throws -> QuiverAIImageReference {
    if input.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*://"#, options: .regularExpression) != nil {
        return .url(try quiverAIValidatedImageURL(input, argument: "input"))
    }
    if input.hasPrefix("data:") {
        guard let comma = input.firstIndex(of: ",") else {
            throw AIError.invalidArgument(
                argument: "input",
                message: "QuiverAI reference image data URLs must use base64 encoding and a supported image media type."
            )
        }
        let header = String(input[..<comma])
        let components = header.dropFirst("data:".count).split(separator: ";", omittingEmptySubsequences: false)
        guard components.count == 2,
              components[1].lowercased() == "base64",
              quiverAISupportedReferenceMediaTypes.contains(String(components[0]).lowercased()) else {
            throw AIError.invalidArgument(
                argument: "input",
                message: "QuiverAI reference image data URLs must use base64 encoding and a supported image media type."
            )
        }
        let base64 = String(input[input.index(after: comma)...])
        _ = try quiverAIValidatedReferenceBase64(base64, argument: "input")
        return .base64(base64)
    }
    _ = try quiverAIValidatedReferenceBase64(input, argument: "input")
    return .base64(input)
}

public final class QuiverAIImageModel: ImageModel, @unchecked Sendable {
    public let providerID = "quiverai.image"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        if let count = request.count, count > 16 {
            throw AIError.invalidArgument(argument: "count", message: "QuiverAI image models support at most 16 images per call.")
        }
        let options = try quiverAIImageOptions(from: request)
        let operation = options.operation ?? "generate"
        let body = try quiverAIRequestBody(modelID: modelID, request: request, options: options, operation: operation)
        let response = try await config.sendJSONResponse(
            path: quiverAIOperationPath(operation),
            modelID: modelID,
            body: .object(body),
            headers: request.headers,
            abortSignal: request.abortSignal
        )
        let raw = response.json
        let documents = try quiverAISVGDocuments(from: raw, providerID: providerID)
        return ImageGenerationResult(
            urls: [],
            base64Images: documents.map { Data(($0["svg"]?.stringValue ?? "").utf8).base64EncodedString() },
            rawValue: raw,
            warnings: quiverAIWarnings(for: request),
            usage: tokenUsage(from: raw),
            providerMetadata: quiverAIProviderMetadata(from: raw),
            requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

private let quiverAISupportedReferenceMediaTypes: Set<String> = [
    "image/gif", "image/jpeg", "image/png", "image/svg+xml", "image/webp"
]
private let quiverAIMaxReferenceBase64Length = 16_777_216
private let quiverAIMaxReferenceBytes = 12_582_912
private let quiverAIMaxAnimationSourceBase64Length = 1_066_668
private let quiverAIMaxEditSVGBytes = 200_000

private struct QuiverAIImageOptions {
    var operation: String?
    var instructions: JSONValue?
    var reasoningEffort: JSONValue?
    var referenceImages: [JSONValue]?
    var maxReviewSteps: JSONValue?
    var attributes: JSONValue?
    var temperature: JSONValue?
    var topP: JSONValue?
    var presencePenalty: JSONValue?
    var maxOutputTokens: JSONValue?
    var orchestratorMaxOutputTokens: JSONValue?
    var shallowMaxOutputTokens: JSONValue?
    var autoCrop: JSONValue?
    var targetSize: JSONValue?
}

private let quiverAIProviderOptionKeys: Set<String> = [
    "operation", "instructions", "reasoningEffort", "referenceImages", "maxReviewSteps",
    "attributes", "temperature", "topP", "presencePenalty", "maxOutputTokens",
    "orchestratorMaxOutputTokens", "shallowMaxOutputTokens", "autoCrop", "targetSize"
]

private func quiverAIImageOptions(from request: ImageGenerationRequest) throws -> QuiverAIImageOptions {
    var values = quiverAIOptionsDictionary(from: request.extraBody)
    if let providerValue = request.providerOptions["quiverai"] {
        guard providerValue != .null else {
            return try quiverAIImageOptions(from: quiverAICanonicalOptions(values))
        }
        guard let nested = providerValue.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.quiverai", message: "QuiverAI provider options must be an object.")
        }
        values.merge(nested) { _, providerValue in providerValue }
    }
    return try quiverAIImageOptions(from: quiverAICanonicalOptions(values))
}

private func quiverAIOptionsDictionary(from options: [String: JSONValue]) -> [String: JSONValue] {
    if let nested = options["quiverai"]?.objectValue { return nested }
    return options.filter { $0.key != "quiverai" }
}

private func quiverAICanonicalOptions(_ input: [String: JSONValue]) -> [String: JSONValue] {
    var output = input
    let aliases = [
        "top_p": "topP",
        "presence_penalty": "presencePenalty",
        "max_output_tokens": "maxOutputTokens",
        "reasoning_effort": "reasoningEffort",
        "reference_images": "referenceImages",
        "max_review_steps": "maxReviewSteps",
        "orchestrator_max_output_tokens": "orchestratorMaxOutputTokens",
        "shallow_max_output_tokens": "shallowMaxOutputTokens",
        "auto_crop": "autoCrop",
        "target_size": "targetSize"
    ]
    for (alias, canonical) in aliases where output[canonical] == nil {
        output[canonical] = output[alias]
    }
    return output
}

private func quiverAIImageOptions(from values: [String: JSONValue]) throws -> QuiverAIImageOptions {
    var normalized: [String: JSONValue] = [:]
    for (key, value) in values where quiverAIProviderOptionKeys.contains(key) {
        switch key {
        case "operation":
            try quiverAIRequireEnum(value, argument: "providerOptions.quiverai.operation", label: "operation", allowed: ["generate", "vectorize", "animate", "edit"])
        case "instructions":
            try quiverAIRequireNonEmptyString(value, argument: "providerOptions.quiverai.instructions", label: "instructions")
        case "reasoningEffort":
            try quiverAIRequireEnum(value, argument: "providerOptions.quiverai.reasoningEffort", label: "reasoningEffort", allowed: ["low", "medium", "high", "xhigh"])
        case "referenceImages":
            normalized[key] = .array(try quiverAIReferenceImages(value))
            continue
        case "maxReviewSteps":
            try quiverAIRequireInteger(value, argument: "providerOptions.quiverai.maxReviewSteps", label: "maxReviewSteps", min: 0, max: 5)
        case "attributes":
            normalized[key] = try quiverAIAttributes(value)
            continue
        case "temperature":
            try quiverAIRequireNumber(value, argument: "providerOptions.quiverai.temperature", label: "temperature", min: 0, max: 2)
        case "topP":
            try quiverAIRequireNumber(value, argument: "providerOptions.quiverai.topP", label: "topP", min: 0, max: 1)
        case "presencePenalty":
            try quiverAIRequireNumberOrNull(value, argument: "providerOptions.quiverai.presencePenalty", label: "presencePenalty", min: -2, max: 2)
        case "maxOutputTokens":
            try quiverAIRequireInteger(value, argument: "providerOptions.quiverai.maxOutputTokens", label: "maxOutputTokens", min: 1, max: 131_072)
        case "orchestratorMaxOutputTokens", "shallowMaxOutputTokens":
            try quiverAIRequireInteger(value, argument: "providerOptions.quiverai.\(key)", label: key, min: 1, max: 65_536)
        case "autoCrop":
            try quiverAIRequireBoolean(value, argument: "providerOptions.quiverai.autoCrop", label: "autoCrop")
        case "targetSize":
            try quiverAIRequireInteger(value, argument: "providerOptions.quiverai.targetSize", label: "targetSize", min: 128, max: 4096)
        default:
            break
        }
        normalized[key] = value
    }
    return QuiverAIImageOptions(
        operation: normalized["operation"]?.stringValue,
        instructions: normalized["instructions"],
        reasoningEffort: normalized["reasoningEffort"],
        referenceImages: normalized["referenceImages"]?.arrayValue,
        maxReviewSteps: normalized["maxReviewSteps"],
        attributes: normalized["attributes"],
        temperature: normalized["temperature"],
        topP: normalized["topP"],
        presencePenalty: normalized["presencePenalty"],
        maxOutputTokens: normalized["maxOutputTokens"],
        orchestratorMaxOutputTokens: normalized["orchestratorMaxOutputTokens"],
        shallowMaxOutputTokens: normalized["shallowMaxOutputTokens"],
        autoCrop: normalized["autoCrop"],
        targetSize: normalized["targetSize"]
    )
}

private func quiverAIReferenceImages(_ value: JSONValue) throws -> [JSONValue] {
    guard let references = value.arrayValue, references.count <= 4 else {
        throw AIError.invalidArgument(argument: "providerOptions.quiverai.referenceImages", message: "QuiverAI referenceImages must contain at most 4 image references.")
    }
    return try references.enumerated().map { index, reference in
        guard let object = reference.objectValue, object.count == 1 else {
            throw AIError.invalidArgument(argument: "providerOptions.quiverai.referenceImages[\(index)]", message: "QuiverAI image references must contain exactly one url or base64 value.")
        }
        if let url = object["url"]?.stringValue, !url.isEmpty {
            return .object(["url": .string(url)])
        }
        if let base64 = object["base64"]?.stringValue, !base64.isEmpty, base64.count <= quiverAIMaxReferenceBase64Length {
            return .object(["base64": .string(base64)])
        }
        throw AIError.invalidArgument(argument: "providerOptions.quiverai.referenceImages[\(index)]", message: "QuiverAI image references require a non-empty url or base64 value.")
    }
}

private func quiverAIAttributes(_ value: JSONValue) throws -> JSONValue {
    guard let attributes = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.quiverai.attributes", message: "QuiverAI attributes must be an object.")
    }
    guard let viewBoxValue = attributes["viewBox"] else { return .object([:]) }
    guard let viewBox = viewBoxValue.objectValue,
          let minX = viewBox["minX"]?.doubleValue, minX.isFinite,
          let minY = viewBox["minY"]?.doubleValue, minY.isFinite,
          let width = viewBox["width"]?.doubleValue, width.isFinite, width > 0,
          let height = viewBox["height"]?.doubleValue, height.isFinite, height > 0 else {
        throw AIError.invalidArgument(argument: "providerOptions.quiverai.attributes.viewBox", message: "QuiverAI viewBox requires finite minX/minY values and positive width/height values.")
    }
    return .object(["viewBox": .object([
        "minX": .number(minX), "minY": .number(minY), "width": .number(width), "height": .number(height)
    ])])
}

private func quiverAIOperationPath(_ operation: String) -> String {
    switch operation {
    case "vectorize": return "/svgs/vectorizations"
    case "animate": return "/svgs/animations"
    case "edit": return "/svgs/edits"
    default: return "/svgs/generations"
    }
}

private func quiverAIRequestBody(
    modelID: String,
    request: ImageGenerationRequest,
    options: QuiverAIImageOptions,
    operation: String
) throws -> [String: JSONValue] {
    if ["arrow-2", "arrow-2-telos"].contains(modelID),
       let maxOutputTokens = options.maxOutputTokens?.intValue,
       maxOutputTokens > 65_536 {
        throw AIError.invalidArgument(argument: "maxOutputTokens", message: "QuiverAI model \"\(modelID)\" supports at most 65536 output tokens.")
    }
    if operation != "edit" {
        try quiverAIRejectEditOnlyOptions(operation: operation, options: options)
    }

    switch operation {
    case "generate":
        return try quiverAIGenerateBody(modelID: modelID, request: request, options: options)
    case "vectorize":
        return try quiverAIVectorizeBody(modelID: modelID, request: request, options: options)
    case "animate":
        return try quiverAIAnimationBody(modelID: modelID, request: request, options: options)
    case "edit":
        return try quiverAIEditBody(modelID: modelID, request: request, options: options)
    default:
        throw AIError.invalidArgument(argument: "operation", message: "QuiverAI operation must be generate, vectorize, animate, or edit.")
    }
}

private func quiverAISharedBody(modelID: String, options: QuiverAIImageOptions) -> [String: JSONValue] {
    var body: [String: JSONValue] = ["model": .string(modelID), "stream": .bool(false)]
    body["temperature"] = options.temperature
    body["top_p"] = options.topP
    body["presence_penalty"] = options.presencePenalty
    body["max_output_tokens"] = options.maxOutputTokens
    body["reasoning_effort"] = options.reasoningEffort
    body["attributes"] = options.attributes
    return body
}

private func quiverAIGenerateBody(modelID: String, request: ImageGenerationRequest, options: QuiverAIImageOptions) throws -> [String: JSONValue] {
    guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw AIError.invalidArgument(argument: "prompt", message: "QuiverAI image generation requires a non-empty prompt for generateImage.")
    }
    let maxReferences = ["arrow-1", "arrow-1.0", "arrow-1.1"].contains(modelID) ? 4 : 16
    guard request.files.count <= maxReferences else {
        throw AIError.invalidArgument(argument: "files", message: "QuiverAI generate supports up to \(maxReferences) reference images for model \"\(modelID)\".")
    }
    var body = quiverAISharedBody(modelID: modelID, options: options)
    body["n"] = .number(Double(request.count ?? 1))
    body["prompt"] = .string(request.prompt)
    body["instructions"] = options.instructions
    if !request.files.isEmpty { body["references"] = .array(request.files.map(quiverAIImageReference)) }
    return body
}

private func quiverAIVectorizeBody(modelID: String, request: ImageGenerationRequest, options: QuiverAIImageOptions) throws -> [String: JSONValue] {
    guard let file = request.files.first else {
        throw AIError.invalidArgument(argument: "files", message: "QuiverAI vectorize requires an input image. Pass an image in the generateImage prompt and set providerOptions.quiverai.operation to \"vectorize\".")
    }
    guard request.files.count == 1 else {
        throw AIError.invalidArgument(argument: "files", message: "QuiverAI vectorize accepts a single input image.")
    }
    guard request.count ?? 1 == 1 else {
        throw AIError.invalidArgument(argument: "n", message: "QuiverAI vectorize returns one SVG per request. Set maxImagesPerCall to 1 in generateImage to vectorize multiple times.")
    }
    var body = quiverAISharedBody(modelID: modelID, options: options)
    body["image"] = quiverAIImageReference(file)
    body["auto_crop"] = options.autoCrop
    body["target_size"] = options.targetSize
    return body
}

private func quiverAIAnimationBody(modelID: String, request: ImageGenerationRequest, options: QuiverAIImageOptions) throws -> [String: JSONValue] {
    guard ["arrow-2", "arrow-2-telos"].contains(modelID) else {
        throw AIError.invalidArgument(argument: "modelId", message: "QuiverAI animate is supported by the \"arrow-2\" and \"arrow-2-telos\" models.")
    }
    guard request.files.count == 1, let source = request.files.first else {
        let message = request.files.isEmpty
            ? "QuiverAI animate requires exactly one source SVG in prompt.images."
            : "QuiverAI animate accepts exactly one source SVG in prompt.images."
        throw AIError.invalidArgument(argument: "files", message: message)
    }
    guard request.count ?? 1 == 1 else {
        throw AIError.invalidArgument(argument: "n", message: "QuiverAI animate returns one SVG per request. Set maxImagesPerCall to 1 in generateImage to animate multiple times.")
    }
    guard request.mask == nil else {
        throw AIError.invalidArgument(argument: "mask", message: "QuiverAI animate does not support masks.")
    }
    if !request.prompt.isEmpty, request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        throw AIError.invalidArgument(argument: "prompt", message: "QuiverAI animate requires a non-empty prompt when an animation instruction is provided.")
    }
    let unsupported: [(String, JSONValue?)] = [
        ("instructions", options.instructions), ("topP", options.topP),
        ("presencePenalty", options.presencePenalty), ("attributes", options.attributes),
        ("autoCrop", options.autoCrop), ("targetSize", options.targetSize)
    ]
    if let name = unsupported.first(where: { $0.1 != nil })?.0 {
        throw AIError.invalidArgument(
            argument: "providerOptions.quiverai.\(name)",
            message: "QuiverAI animate does not support providerOptions.quiverai.\(name)."
        )
    }
    var body: [String: JSONValue] = [
        "model": .string(modelID),
        "svg_source": try quiverAIAnimationSource(source),
        "stream": .bool(false)
    ]
    if !request.prompt.isEmpty { body["prompt"] = .string(request.prompt) }
    body["temperature"] = options.temperature
    body["max_output_tokens"] = options.maxOutputTokens
    body["reasoning_effort"] = options.reasoningEffort
    return body
}

private func quiverAIEditBody(modelID: String, request: ImageGenerationRequest, options: QuiverAIImageOptions) throws -> [String: JSONValue] {
    guard ["arrow-2", "arrow-2-telos"].contains(modelID) else {
        throw AIError.invalidArgument(argument: "modelId", message: "QuiverAI SVG editing is supported by the \"arrow-2\" and \"arrow-2-telos\" models.")
    }
    guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw AIError.invalidArgument(argument: "prompt", message: "QuiverAI SVG editing requires a non-empty instruction in generateImage prompt.text.")
    }
    guard request.prompt.count <= 4000 else {
        throw AIError.invalidArgument(argument: "prompt", message: "QuiverAI SVG editing instructions must contain at most 4000 characters.")
    }
    guard request.files.count == 1, let source = request.files.first else {
        let message = request.files.isEmpty
            ? "QuiverAI SVG editing requires one source SVG in generateImage prompt.images."
            : "QuiverAI SVG editing accepts exactly one source SVG."
        throw AIError.invalidArgument(argument: "files", message: message)
    }
    guard request.count ?? 1 == 1 else {
        throw AIError.invalidArgument(argument: "n", message: "QuiverAI SVG editing returns exactly one SVG per request. Set maxImagesPerCall to 1 in generateImage to edit multiple times.")
    }
    guard request.mask == nil else {
        throw AIError.invalidArgument(argument: "mask", message: "QuiverAI SVG editing does not support masks.")
    }
    let unsupported: [(String, JSONValue?)] = [
        ("instructions", options.instructions), ("attributes", options.attributes),
        ("topP", options.topP), ("presencePenalty", options.presencePenalty == .null ? nil : options.presencePenalty),
        ("autoCrop", options.autoCrop), ("targetSize", options.targetSize)
    ]
    let unsupportedNames = unsupported.compactMap { $0.1 == nil ? nil : $0.0 }
    if !unsupportedNames.isEmpty {
        throw AIError.invalidArgument(argument: "providerOptions", message: "QuiverAI SVG editing does not support these provider options: \(unsupportedNames.joined(separator: ", ")).")
    }

    var body: [String: JSONValue] = [
        "model": .string(modelID),
        "prompt": .string(request.prompt),
        "svg_source": try quiverAIEditSource(source),
        "stream": .bool(false)
    ]
    if let references = options.referenceImages {
        body["reference_images"] = .array(try references.enumerated().map { index, reference in
            try quiverAIValidatedReference(reference, argument: "providerOptions.quiverai.referenceImages[\(index)]")
        })
    }
    body["max_review_steps"] = options.maxReviewSteps
    body["reasoning_effort"] = options.reasoningEffort

    var settings: [String: JSONValue] = [:]
    settings["max_output_tokens"] = options.maxOutputTokens
    settings["orchestrator_max_output_tokens"] = options.orchestratorMaxOutputTokens
    settings["shallow_max_output_tokens"] = options.shallowMaxOutputTokens
    settings["temperature"] = options.temperature
    if !settings.isEmpty { body["settings"] = .object(settings) }
    return body
}

private func quiverAIRejectEditOnlyOptions(operation: String, options: QuiverAIImageOptions) throws {
    let values: [(String, Any?)] = [
        ("referenceImages", options.referenceImages),
        ("maxReviewSteps", options.maxReviewSteps),
        ("orchestratorMaxOutputTokens", options.orchestratorMaxOutputTokens),
        ("shallowMaxOutputTokens", options.shallowMaxOutputTokens)
    ]
    let names = values.compactMap { $0.1 == nil ? nil : $0.0 }
    if !names.isEmpty {
        throw AIError.invalidArgument(argument: "providerOptions", message: "QuiverAI \(operation) does not support these edit-only provider options: \(names.joined(separator: ", ")).")
    }
}

private func quiverAIImageReference(_ file: ImageInputFile) -> JSONValue {
    if let url = file.url { return .object(["url": .string(url)]) }
    return .object(["base64": .string(file.data?.base64EncodedString() ?? "")])
}

private func quiverAIAnimationSource(_ file: ImageInputFile) throws -> JSONValue {
    if let url = file.url {
        return .object(["url": .string(try quiverAIValidatedImageURL(url, argument: "files"))])
    }
    guard let data = file.data, quiverAIHasSVGPrefix(data) else {
        throw AIError.invalidArgument(argument: "files", message: "QuiverAI animate requires the input file to contain SVG data.")
    }
    let base64 = data.base64EncodedString()
    guard base64.count <= quiverAIMaxAnimationSourceBase64Length else {
        throw AIError.invalidArgument(argument: "files", message: "QuiverAI animate accepts at most \(quiverAIMaxAnimationSourceBase64Length) base64 characters for the source SVG.")
    }
    return .object(["base64": .string(base64)])
}

private func quiverAIEditSource(_ file: ImageInputFile) throws -> JSONValue {
    if let url = file.url {
        return .object(["url": .string(try quiverAIValidatedImageURL(url, argument: "files"))])
    }
    guard let data = file.data, !data.isEmpty, data.count <= quiverAIMaxEditSVGBytes else {
        throw AIError.invalidArgument(argument: "files", message: "QuiverAI SVG source data must contain 1-\(quiverAIMaxEditSVGBytes) bytes.")
    }
    guard String(data: data, encoding: .utf8) != nil else {
        throw AIError.invalidArgument(argument: "files", message: "QuiverAI SVG source data must be valid UTF-8.")
    }
    guard quiverAIIsCompleteSVGDocument(data) else {
        throw AIError.invalidArgument(argument: "files", message: "QuiverAI SVG source data must contain a complete SVG document.")
    }
    return .object(["base64": .string(data.base64EncodedString())])
}

private func quiverAIValidatedReference(_ reference: JSONValue, argument: String) throws -> JSONValue {
    guard let object = reference.objectValue else {
        throw AIError.invalidArgument(argument: argument, message: "QuiverAI image reference must be an object.")
    }
    if let url = object["url"]?.stringValue {
        return .object(["url": .string(try quiverAIValidatedImageURL(url, argument: argument))])
    }
    if let base64 = object["base64"]?.stringValue {
        _ = try quiverAIValidatedReferenceBase64(base64, argument: argument)
        return .object(["base64": .string(base64)])
    }
    throw AIError.invalidArgument(argument: argument, message: "QuiverAI image reference requires url or base64.")
}

private func quiverAIValidatedImageURL(_ value: String, argument: String) throws -> String {
    guard let components = URLComponents(string: value),
          let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
          let host = components.host, !host.isEmpty else {
        throw AIError.invalidArgument(argument: argument, message: "QuiverAI image URLs must be valid HTTP or HTTPS URLs.")
    }
    return value
}

private func quiverAIValidatedReferenceBase64(_ base64: String, argument: String) throws -> Data {
    guard !base64.isEmpty, base64.count <= quiverAIMaxReferenceBase64Length else {
        throw AIError.invalidArgument(argument: argument, message: "QuiverAI reference images must contain 1-\(quiverAIMaxReferenceBase64Length) base64 characters.")
    }
    guard let data = Data(base64Encoded: base64) else {
        throw AIError.invalidArgument(argument: argument, message: "QuiverAI reference image data must be valid base64.")
    }
    try quiverAIValidateReferenceData(data, argument: argument)
    return data
}

private func quiverAIValidateReferenceData(_ data: Data, argument: String) throws {
    guard !data.isEmpty, data.count <= quiverAIMaxReferenceBytes else {
        throw AIError.invalidArgument(argument: argument, message: "QuiverAI reference images must decode to 1-\(quiverAIMaxReferenceBytes) bytes.")
    }
    let mediaType = quiverAIIsReferenceSVG(data) ? "image/svg+xml" : detectMediaType(data: data, topLevelType: "image")
    guard let mediaType, quiverAISupportedReferenceMediaTypes.contains(mediaType) else {
        throw AIError.invalidArgument(argument: argument, message: "QuiverAI reference images must be PNG, JPEG, WebP, GIF, or SVG data.")
    }
}

private func quiverAIIsReferenceSVG(_ data: Data) -> Bool {
    guard var text = String(data: data, encoding: .utf8) else { return false }
    if text.first == "\u{FEFF}" { text.removeFirst() }
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.range(
        of: #"(?is)^(?:<\?xml[\s\S]*?\?>\s*)?(?:<!--[\s\S]*?-->\s*)?(?:<!DOCTYPE[\s\S]*?>\s*)?<svg(?:\s|>)"#,
        options: .regularExpression
    ) != nil else { return false }
    return normalized.range(of: #"(?is)</svg>\s*$"#, options: .regularExpression) != nil
        || normalized.range(of: #"(?is)<svg(?:\s[^>]*)?/>\s*$"#, options: .regularExpression) != nil
}

private func quiverAIHasSVGPrefix(_ data: Data) -> Bool {
    let text = String(decoding: data.prefix(4096), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return text.range(
        of: #"(?is)^(?:(?:<\?xml[\s\S]*?\?>|<!--[\s\S]*?-->|<!DOCTYPE[\s\S]*?>)\s*)*<svg(?:\s|>)"#,
        options: .regularExpression
    ) != nil
}

private final class QuiverAISVGParserDelegate: NSObject, XMLParserDelegate {
    var rootName: String?
    var rootCount = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if rootName == nil {
            rootName = elementName
            rootCount += 1
        }
    }
}

private func quiverAIIsCompleteSVGDocument(_ data: Data) -> Bool {
    guard String(data: data, encoding: .utf8) != nil else { return false }
    let delegate = QuiverAISVGParserDelegate()
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = false
    parser.shouldReportNamespacePrefixes = false
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    return parser.parse() && delegate.rootCount == 1 && delegate.rootName?.lowercased() == "svg"
}

private func quiverAISVGDocuments(from raw: JSONValue, providerID: String) throws -> [JSONValue] {
    guard let id = raw["id"]?.stringValue, !id.isEmpty,
          quiverAINonNegativeInteger(raw["created"]),
          let data = raw["data"]?.arrayValue, !data.isEmpty else {
        throw AIError.invalidResponse(provider: providerID, message: "QuiverAI image response is invalid.")
    }
    for item in data {
        guard let svg = item["svg"]?.stringValue, !svg.isEmpty,
              item["mime_type"]?.stringValue == "image/svg+xml",
              quiverAINullishNonNegativeInteger(item["loop_period_ms"]),
              quiverAINullishNonNegativeInteger(item["opening_animation_ms"]) else {
            throw AIError.invalidResponse(provider: providerID, message: "QuiverAI image response is invalid.")
        }
    }
    if let usage = raw["usage"], usage != .null {
        guard quiverAINonNegativeInteger(usage["total_tokens"]),
              quiverAINonNegativeInteger(usage["input_tokens"]),
              quiverAINonNegativeInteger(usage["output_tokens"]) else {
            throw AIError.invalidResponse(provider: providerID, message: "QuiverAI image response is invalid.")
        }
    }
    guard quiverAINullishNonNegativeInteger(raw["credits"]) else {
        throw AIError.invalidResponse(provider: providerID, message: "QuiverAI image response is invalid.")
    }
    return data
}

private func quiverAINonNegativeInteger(_ value: JSONValue?) -> Bool {
    guard let number = value?.doubleValue else { return false }
    return number >= 0 && number.rounded() == number
}

private func quiverAINullishNonNegativeInteger(_ value: JSONValue?) -> Bool {
    value == nil || value == .null || quiverAINonNegativeInteger(value)
}

private func quiverAIProviderMetadata(from raw: JSONValue) -> [String: JSONValue] {
    let images = raw["data"]?.arrayValue?.enumerated().map { index, image -> JSONValue in
        var metadata: [String: JSONValue] = [
            "index": .number(Double(index)),
            "mimeType": image["mime_type"] ?? .string("image/svg+xml")
        ]
        if let loopPeriod = image["loop_period_ms"] { metadata["loopPeriodMs"] = loopPeriod }
        if let openingAnimation = image["opening_animation_ms"] { metadata["openingAnimationMs"] = openingAnimation }
        return .object(metadata)
    } ?? []
    var metadata: [String: JSONValue] = ["images": .array(images)]
    if let credits = raw["credits"], credits != .null { metadata["credits"] = credits }
    return ["quiverai": .object(metadata)]
}

private func quiverAIWarnings(for request: ImageGenerationRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.size != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "size", message: "QuiverAI SVG generation does not support the `size` option. The setting was ignored."))
    }
    if request.aspectRatio != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "aspectRatio", message: "QuiverAI SVG generation does not support the `aspectRatio` option. The setting was ignored."))
    }
    if request.seed != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "seed", message: "QuiverAI SVG generation does not support the `seed` option. The setting was ignored."))
    }
    if request.mask != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "mask", message: "QuiverAI SVG generation does not support masks. The mask was ignored."))
    }
    return warnings
}

private func quiverAIRequireNonEmptyString(_ value: JSONValue, argument: String, label: String) throws {
    guard let string = value.stringValue, !string.isEmpty else {
        throw AIError.invalidArgument(argument: argument, message: "QuiverAI \(label) must be a non-empty string.")
    }
}

private func quiverAIRequireBoolean(_ value: JSONValue, argument: String, label: String) throws {
    guard value.boolValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: "QuiverAI \(label) must be a boolean.")
    }
}

private func quiverAIRequireNumber(_ value: JSONValue, argument: String, label: String, min: Double, max: Double) throws {
    guard let number = value.doubleValue, number.isFinite else {
        throw AIError.invalidArgument(argument: argument, message: "QuiverAI \(label) must be a number.")
    }
    if number < min || number > max {
        throw AIError.invalidArgument(argument: argument, message: "QuiverAI \(label) must be between \(quiverAIFormatNumber(min)) and \(quiverAIFormatNumber(max)).")
    }
}

private func quiverAIRequireNumberOrNull(_ value: JSONValue, argument: String, label: String, min: Double, max: Double) throws {
    guard value != .null else { return }
    try quiverAIRequireNumber(value, argument: argument, label: label, min: min, max: max)
}

private func quiverAIRequireInteger(_ value: JSONValue, argument: String, label: String, min: Int, max: Int) throws {
    guard let number = value.doubleValue, number.isFinite, number.rounded() == number else {
        throw AIError.invalidArgument(argument: argument, message: "QuiverAI \(label) must be an integer.")
    }
    if number < Double(min) || number > Double(max) {
        throw AIError.invalidArgument(argument: argument, message: "QuiverAI \(label) must be an integer between \(min) and \(max).")
    }
}

private func quiverAIRequireEnum(_ value: JSONValue, argument: String, label: String, allowed: Set<String>) throws {
    guard let string = value.stringValue, allowed.contains(string) else {
        throw AIError.invalidArgument(argument: argument, message: "QuiverAI \(label) must be one of \(allowed.sorted().joined(separator: ", ")).")
    }
}

private func quiverAIFormatNumber(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(value)
}
