import Foundation

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
        let warnings = isOpenAIBackedProvider(providerID, config: config)
            ? []
            : (config.usesGenericOpenAICompatibleProviderOptions
                ? openAICompatibleProviderOptionWarnings(providerOptions: request.providerOptions, extraBody: request.extraBody, providerID: providerID, includeCompatibilityNamespace: true)
                : openAICompatibleProviderOptionWarnings(from: request.extraBody, providerID: providerID, includeCompatibilityNamespace: true))

        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "input": .array(request.values)
        ]
        if let dimensions = request.dimensions { body["dimensions"] = .number(Double(dimensions)) }
        if isOpenAIBackedProvider(providerID, config: config) || openAICompatibleProviderSurface(providerID) == "embedding" {
            body["encoding_format"] = .string("float")
        }
        let extraBody: [String: JSONValue]
        if isOpenAIBackedProvider(providerID, config: config) {
            extraBody = openAIProviderOptions(providerOptions: request.providerOptions, extraBody: request.extraBody, providerID: providerID, providerRoot: config.openAIBackedProviderRoot)
        } else if config.usesGenericOpenAICompatibleProviderOptions {
            extraBody = openAICompatibleProviderOptions(providerOptions: request.providerOptions, extraBody: request.extraBody, providerID: providerID, includeCompatibilityNamespace: true)
        } else {
            extraBody = openAICompatibleProviderOptions(from: request.extraBody, providerID: providerID, includeCompatibilityNamespace: true)
        }
        body.merge(extraBody) { _, new in new }

        let response = try await config.sendJSONResponse(path: "/embeddings", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        guard case let .array(data) = raw["data"] else {
            throw AIError.invalidResponse(provider: providerID, message: "No embedding data found.")
        }

        let embeddings = data.compactMap { item -> [Double]? in
            guard case let .array(values) = item["embedding"] else { return nil }
            return values.compactMap(\.doubleValue)
        }
        return EmbeddingResult(
            embeddings: embeddings,
            usage: tokenUsage(from: raw),
            rawValue: raw,
            warnings: warnings,
            providerMetadata: raw["providerMetadata"]?.objectValue ?? [:],
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: openAICompatibleResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

public final class OpenAICompatibleImageModel: ImageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig
    private var maxImagesPerCall: Int {
        isOpenAIBackedProvider(providerID, config: config) ? openAIImageMaxImagesPerCall(modelID) : 10
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
        let warnings = openAICompatibleImageWarnings(from: request, providerID: providerID, openAIBackedProviderRoot: config.openAIBackedProviderRoot, usesGenericProviderOptions: config.usesGenericOpenAICompatibleProviderOptions)
        if !request.files.isEmpty {
            return try await editImage(request, warnings: warnings)
        }

        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "prompt": .string(request.prompt)
        ]
        if let size = request.size { body["size"] = .string(size) }
        if let count = request.count { body["n"] = .number(Double(count)) }
        let imageOptions: [String: JSONValue]
        if isOpenAIBackedProvider(providerID, config: config) {
            imageOptions = openAIImageOptions(providerOptions: request.providerOptions, extraBody: request.extraBody, providerID: providerID, providerRoot: config.openAIBackedProviderRoot)
        } else if config.usesGenericOpenAICompatibleProviderOptions {
            imageOptions = openAICompatibleProviderOptions(providerOptions: request.providerOptions, extraBody: request.extraBody, providerID: providerID, includeCompatibilityNamespace: false)
        } else {
            imageOptions = openAICompatibleProviderOptions(from: request.extraBody, providerID: providerID, includeCompatibilityNamespace: false)
        }
        body.merge(imageOptions) { _, new in new }
        if isOpenAIBackedProvider(providerID, config: config), body["response_format"] == nil, !openAIImageHasDefaultResponseFormat(modelID) {
            body["response_format"] = .string("b64_json")
        } else if !isOpenAIBackedProvider(providerID, config: config) {
            body["response_format"] = .string("b64_json")
        }

        let response = try await config.sendJSONResponse(path: "/images/generations", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        guard case let .array(data) = raw["data"] else {
            throw AIError.invalidResponse(provider: providerID, message: "No image data found.")
        }
        return ImageGenerationResult(
            urls: data.compactMap { $0["url"]?.stringValue },
            base64Images: data.compactMap { $0["b64_json"]?.stringValue },
            rawValue: raw,
            warnings: warnings,
            usage: tokenUsage(from: raw),
            providerMetadata: openAIImageProviderMetadata(from: raw, providerID: providerID, openAIBackedProviderRoot: config.openAIBackedProviderRoot),
            requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: openAICompatibleResponseMetadata(from: raw, response: response.response, modelID: modelID)
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

        let extraBody: [String: JSONValue]
        if isOpenAIBackedProvider(providerID, config: config) {
            extraBody = openAIImageOptions(providerOptions: request.providerOptions, extraBody: request.extraBody, providerID: providerID, providerRoot: config.openAIBackedProviderRoot)
        } else if config.usesGenericOpenAICompatibleProviderOptions {
            extraBody = openAICompatibleProviderOptions(providerOptions: request.providerOptions, extraBody: request.extraBody, providerID: providerID, includeCompatibilityNamespace: false)
        } else {
            extraBody = openAICompatibleProviderOptions(from: request.extraBody, providerID: providerID, includeCompatibilityNamespace: false)
        }
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
            throw httpStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        guard case let .array(data) = raw["data"] else {
            throw AIError.invalidResponse(provider: providerID, message: "No image data found.")
        }
        return ImageGenerationResult(
            urls: data.compactMap { $0["url"]?.stringValue },
            base64Images: data.compactMap { $0["b64_json"]?.stringValue },
            rawValue: raw,
            warnings: warnings,
            usage: tokenUsage(from: raw),
            providerMetadata: openAIImageProviderMetadata(from: raw, providerID: providerID, openAIBackedProviderRoot: config.openAIBackedProviderRoot),
            requestMetadata: imageGenerationRequestMetadata(request),
            responseMetadata: openAICompatibleResponseMetadata(from: raw, response: response, modelID: modelID)
        )
    }
}

func openAIImageProviderMetadata(from raw: JSONValue, providerID: String, openAIBackedProviderRoot: String? = nil) -> [String: JSONValue] {
    guard openAIBackedProviderRoot != nil || isOpenAIBackedProvider(providerID) else { return [:] }
    let images = raw["data"]?.arrayValue ?? []
    return [
        "openai": .object([
            "images": .array(images.enumerated().map { index, image in
                var metadata: [String: JSONValue] = [:]
                if let revisedPrompt = image["revised_prompt"]?.stringValue, !revisedPrompt.isEmpty {
                    metadata["revisedPrompt"] = .string(revisedPrompt)
                }
                if let created = raw["created"] {
                    metadata["created"] = created
                }
                if let size = raw["size"] {
                    metadata["size"] = size
                }
                if let quality = raw["quality"] {
                    metadata["quality"] = quality
                }
                if let background = raw["background"] {
                    metadata["background"] = background
                }
                if let outputFormat = raw["output_format"] {
                    metadata["outputFormat"] = outputFormat
                }
                metadata.merge(openAIImageTokenDetails(from: raw["usage"]?["input_tokens_details"], index: index, total: images.count)) { _, new in new }
                return .object(metadata)
            })
        ])
    ]
}

func openAIImageTokenDetails(from details: JSONValue?, index: Int, total: Int) -> [String: JSONValue] {
    guard total > 0 else { return [:] }
    var metadata: [String: JSONValue] = [:]
    if let imageTokens = details?["image_tokens"]?.intValue {
        metadata["imageTokens"] = .number(Double(openAIImageDistributedTokens(imageTokens, index: index, total: total)))
    }
    if let textTokens = details?["text_tokens"]?.intValue {
        metadata["textTokens"] = .number(Double(openAIImageDistributedTokens(textTokens, index: index, total: total)))
    }
    return metadata
}

func openAIImageDistributedTokens(_ tokens: Int, index: Int, total: Int) -> Int {
    let base = tokens / total
    let remainder = tokens - base * (total - 1)
    return index == total - 1 ? remainder : base
}

func openAICompatibleImageWarnings(from request: ImageGenerationRequest, providerID: String, openAIBackedProviderRoot: String? = nil, usesGenericProviderOptions: Bool = false) -> [AIWarning] {
    guard openAIBackedProviderRoot == nil, !isOpenAIBackedProvider(providerID) else { return [] }
    var warnings = usesGenericProviderOptions
        ? openAICompatibleProviderOptionWarnings(providerOptions: request.providerOptions, extraBody: request.extraBody, providerID: providerID, includeCompatibilityNamespace: false)
        : openAICompatibleProviderOptionWarnings(from: request.extraBody, providerID: providerID, includeCompatibilityNamespace: false)
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

struct OpenAICompatibleResolvedImageFile {
    var data: Data
    var mediaType: String
    var fileName: String
}

func openAICompatibleResolveImageFile(_ file: ImageInputFile, providerID: String, transport: AITransport) async throws -> OpenAICompatibleResolvedImageFile {
    if let data = file.data {
        let mediaType = file.mediaType ?? "application/octet-stream"
        return OpenAICompatibleResolvedImageFile(data: data, mediaType: mediaType, fileName: file.fileName ?? openAICompatibleDefaultFileName(mediaType: mediaType))
    }

    guard let url = file.url else {
        throw AIError.invalidResponse(provider: providerID, message: "Image file must contain data or a URL.")
    }
    let response = try await downloadURL(url, transport: transport)
    guard (200..<300).contains(response.statusCode) else {
        throw httpStatusError(provider: providerID, response: response)
    }
    let mediaType = file.mediaType
        ?? response.headers["content-type"]
        ?? response.headers["Content-Type"]
        ?? "application/octet-stream"
    return OpenAICompatibleResolvedImageFile(data: response.body, mediaType: mediaType, fileName: file.fileName ?? openAICompatibleDefaultFileName(mediaType: mediaType))
}

func openAICompatibleDefaultFileName(mediaType: String) -> String {
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
        var warnings: [AIWarning] = []
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "input": .string(request.text)
        ]
        if isOpenAIBackedProvider(providerID, config: config) {
            body["voice"] = .string(request.voice ?? "alloy")
            let outputFormat = request.format ?? "mp3"
            if openAISpeechSupportedOutputFormats.contains(outputFormat) {
                body["response_format"] = .string(outputFormat)
            } else {
                body["response_format"] = .string("mp3")
                warnings.append(AIWarning(type: "unsupported", feature: "outputFormat", message: "Unsupported output format: \(outputFormat). Using mp3 instead."))
            }
            if let language = request.language {
                warnings.append(AIWarning(type: "unsupported", feature: "language", message: "OpenAI speech models do not support language selection. Language parameter \"\(language)\" was ignored."))
            }
        } else {
            if let voice = request.voice { body["voice"] = .string(voice) }
            if let format = request.format { body["response_format"] = .string(format) }
            if let language = request.language { body["language"] = .string(language) }
        }
        if let speed = request.speed { body["speed"] = .number(speed) }
        if let instructions = request.instructions { body["instructions"] = .string(instructions) }
        let extraBody = isOpenAIBackedProvider(providerID, config: config) ? openAIProviderOptions(providerOptions: request.providerOptions, extraBody: request.extraBody, providerID: providerID, providerRoot: config.openAIBackedProviderRoot) : request.extraBody
        body.merge(extraBody) { _, new in new }

        let response = try await config.transport.send(config.request(path: "/audio/speech", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        return SpeechResult(
            audio: response.body,
            contentType: response.headers["content-type"] ?? response.headers["Content-Type"],
            warnings: warnings,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: openAICompatibleResponseMetadata(response: response, modelID: modelID)
        )
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
        var metadataBody: [String: JSONValue] = [
            "model": .string(modelID),
            "filename": .string(request.fileName),
            "mime_type": .string(request.mimeType)
        ]
        if modelID == "whisper-1" {
            form.appendField(name: "response_format", value: "verbose_json")
            metadataBody["response_format"] = .string("verbose_json")
        }
        if let language = request.language {
            form.appendField(name: "language", value: language)
            metadataBody["language"] = .string(language)
        }
        if let prompt = request.prompt {
            form.appendField(name: "prompt", value: prompt)
            metadataBody["prompt"] = .string(prompt)
        }
        let extraBody = isOpenAIBackedProvider(providerID, config: config) ? openAITranscriptionOptions(providerOptions: request.providerOptions, extraBody: request.extraBody, providerID: providerID, providerRoot: config.openAIBackedProviderRoot, modelID: modelID) : request.extraBody
        for (key, value) in extraBody {
            if case let .array(items) = value {
                metadataBody[key] = value
                for item in items {
                    if let scalar = jsonScalarString(item) {
                        form.appendField(name: "\(key)[]", value: scalar)
                    }
                }
            } else if let scalar = jsonScalarString(value) {
                form.appendField(name: key, value: scalar)
                metadataBody[key] = value
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
            throw httpStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        guard let text = raw["text"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "No transcription text found.")
        }
        let segments = standardTranscriptionSegments(from: raw)
        return TranscriptionResult(
            text: text,
            rawValue: raw,
            segments: segments,
            language: openAITranscriptionLanguageCode(raw["language"]?.stringValue),
            durationInSeconds: raw["duration"]?.doubleValue ?? transcriptionDuration(from: segments),
            requestMetadata: AIRequestMetadata(body: .object(metadataBody), headers: request.headers),
            responseMetadata: openAICompatibleResponseMetadata(from: raw, response: response, modelID: modelID)
        )
    }
}

let openAISpeechSupportedOutputFormats: Set<String> = ["mp3", "opus", "aac", "flac", "wav", "pcm"]

func openAITranscriptionLanguageCode(_ language: String?) -> String? {
    guard let language else { return nil }
    return openAITranscriptionLanguageMap[language] ?? language
}

let openAITranscriptionLanguageMap: [String: String] = [
    "afrikaans": "af",
    "arabic": "ar",
    "armenian": "hy",
    "azerbaijani": "az",
    "belarusian": "be",
    "bosnian": "bs",
    "bulgarian": "bg",
    "catalan": "ca",
    "chinese": "zh",
    "croatian": "hr",
    "czech": "cs",
    "danish": "da",
    "dutch": "nl",
    "english": "en",
    "estonian": "et",
    "finnish": "fi",
    "french": "fr",
    "galician": "gl",
    "german": "de",
    "greek": "el",
    "hebrew": "he",
    "hindi": "hi",
    "hungarian": "hu",
    "icelandic": "is",
    "indonesian": "id",
    "italian": "it",
    "japanese": "ja",
    "kannada": "kn",
    "kazakh": "kk",
    "korean": "ko",
    "latvian": "lv",
    "lithuanian": "lt",
    "macedonian": "mk",
    "malay": "ms",
    "marathi": "mr",
    "maori": "mi",
    "nepali": "ne",
    "norwegian": "no",
    "persian": "fa",
    "polish": "pl",
    "portuguese": "pt",
    "romanian": "ro",
    "russian": "ru",
    "serbian": "sr",
    "slovak": "sk",
    "slovenian": "sl",
    "spanish": "es",
    "swahili": "sw",
    "swedish": "sv",
    "tagalog": "tl",
    "tamil": "ta",
    "thai": "th",
    "turkish": "tr",
    "ukrainian": "uk",
    "urdu": "ur",
    "vietnamese": "vi",
    "welsh": "cy"
]
