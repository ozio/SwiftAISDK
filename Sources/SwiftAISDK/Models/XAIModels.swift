import Foundation

public enum XAITools {
    public static func codeExecution() -> JSONValue {
        providerTool(id: "xai.code_execution", name: "code_execution")
    }

    public static func fileSearch(vectorStoreIDs: [String], maxNumResults: Int? = nil) -> JSONValue {
        providerTool(id: "xai.file_search", name: "file_search", args: JSONValue.object([
            "vectorStoreIds": .array(vectorStoreIDs),
            "maxNumResults": maxNumResults.map { .number(Double($0)) }
        ]).objectValue ?? [:])
    }

    public static func mcpServer(
        serverURL: String,
        serverLabel: String? = nil,
        serverDescription: String? = nil,
        allowedTools: [String]? = nil,
        headers: JSONValue? = nil,
        authorization: String? = nil
    ) -> JSONValue {
        providerTool(id: "xai.mcp", name: "mcp", args: JSONValue.object([
            "serverUrl": .string(serverURL),
            "serverLabel": serverLabel.map(JSONValue.string),
            "serverDescription": serverDescription.map(JSONValue.string),
            "allowedTools": allowedTools.map { .array($0.map(JSONValue.string)) },
            "headers": headers,
            "authorization": authorization.map(JSONValue.string)
        ]).objectValue ?? [:])
    }

    public static func viewImage() -> JSONValue {
        providerTool(id: "xai.view_image", name: "view_image")
    }

    public static func viewXVideo() -> JSONValue {
        providerTool(id: "xai.view_x_video", name: "view_x_video")
    }

    public static func webSearch(
        allowedDomains: [String]? = nil,
        excludedDomains: [String]? = nil,
        enableImageSearch: Bool? = nil,
        enableImageUnderstanding: Bool? = nil
    ) -> JSONValue {
        providerTool(id: "xai.web_search", name: "web_search", args: JSONValue.object([
            "allowedDomains": allowedDomains.map { .array($0.map(JSONValue.string)) },
            "excludedDomains": excludedDomains.map { .array($0.map(JSONValue.string)) },
            "enableImageSearch": enableImageSearch.map(JSONValue.bool),
            "enableImageUnderstanding": enableImageUnderstanding.map(JSONValue.bool)
        ]).objectValue ?? [:])
    }

    public static func xSearch(
        allowedXHandles: [String]? = nil,
        excludedXHandles: [String]? = nil,
        fromDate: String? = nil,
        toDate: String? = nil,
        enableImageUnderstanding: Bool? = nil,
        enableVideoUnderstanding: Bool? = nil
    ) -> JSONValue {
        providerTool(id: "xai.x_search", name: "x_search", args: JSONValue.object([
            "allowedXHandles": allowedXHandles.map { .array($0.map(JSONValue.string)) },
            "excludedXHandles": excludedXHandles.map { .array($0.map(JSONValue.string)) },
            "fromDate": fromDate.map(JSONValue.string),
            "toDate": toDate.map(JSONValue.string),
            "enableImageUnderstanding": enableImageUnderstanding.map(JSONValue.bool),
            "enableVideoUnderstanding": enableVideoUnderstanding.map(JSONValue.bool)
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

public final class XAISpeechModel: SpeechModel, @unchecked Sendable {
    public let providerID = "xai.speech"
    public let modelID = ""
    private let config: ModelHTTPConfig

    init(config: ModelHTTPConfig) {
        self.config = config
    }

    public func speak(_ request: SpeechRequest) async throws -> SpeechResult {
        let options = try xaiSpeechProviderOptions(from: request)
        let prepared = try xaiSpeechBody(for: request, options: options)
        let response = try await config.transport.send(config.request(
            path: "/tts",
            modelID: modelID,
            body: .object(prepared.body),
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw audioProviderHTTPStatusError(provider: providerID, response: response)
        }
        return SpeechResult(
            audio: response.body,
            contentType: response.headers.contentType,
            warnings: prepared.warnings,
            requestMetadata: AIRequestMetadata(body: .object(prepared.body), headers: request.headers),
            responseMetadata: aiResponseMetadata(response: response, modelID: modelID)
        )
    }
}

public final class XAITranscriptionModel: TranscriptionModel, @unchecked Sendable {
    public let providerID = "xai.transcription"
    public let modelID = ""
    private let config: ModelHTTPConfig

    init(config: ModelHTTPConfig) {
        self.config = config
    }

    public func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        let options = try xaiTranscriptionProviderOptions(from: request)
        var form = MultipartFormData()
        var metadataBody: [String: JSONValue] = [
            "file": .object([
                "filename": .string("audio.\(mediaTypeToExtension(request.mimeType))"),
                "mimeType": .string(request.mimeType),
                "byteLength": .number(Double(request.audio.count))
            ])
        ]
        for (key, value) in xaiTranscriptionFields(from: request, options: options) {
            if key == "keyterm", case let .array(items) = value {
                metadataBody[key] = value
                for item in items {
                    if let scalar = jsonScalarString(item) {
                        form.appendField(name: key, value: scalar)
                    }
                }
            } else if let scalar = jsonScalarString(value) {
                form.appendField(name: key, value: scalar)
                metadataBody[key] = value
            }
        }
        let fileName = "audio.\(mediaTypeToExtension(request.mimeType))"
        form.appendFile(name: "file", fileName: fileName, mimeType: request.mimeType, data: request.audio)

        let response = try await config.transport.send(config.rawRequest(
            path: "/stt",
            modelID: modelID,
            body: form.finalize(),
            contentType: "multipart/form-data; boundary=\(form.boundary)",
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw audioProviderHTTPStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        let segments = xaiTranscriptionSegments(from: raw)
        return TranscriptionResult(
            text: raw["text"]?.stringValue ?? "",
            rawValue: raw,
            segments: segments,
            language: raw["language"]?.stringValue,
            durationInSeconds: raw["duration"]?.doubleValue ?? transcriptionDuration(from: segments),
            requestMetadata: AIRequestMetadata(body: .object(metadataBody), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response, modelID: modelID)
        )
    }
}

public final class XAIImageModel: ImageModel, @unchecked Sendable {
    public let providerID = "xai.image"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        if let count = request.count, count > 3 {
            throw AIError.invalidResponse(provider: providerID, message: "xAI supports at most 3 images per call.")
        }
        let options = try xaiProviderOptions(from: request)
        let warnings = xaiImageWarnings(for: request)
        let endpoint = request.files.isEmpty ? "/images/generations" : "/images/edits"
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "prompt": .string(request.prompt),
            "response_format": .string("b64_json")
        ]
        if let count = request.count { body["n"] = .number(Double(count)) }
        if let aspectRatio = request.aspectRatio {
            body["aspect_ratio"] = .string(aspectRatio)
        } else if let aspectRatio = options["aspectRatio"] ?? options["aspect_ratio"] {
            body["aspect_ratio"] = aspectRatio
        }
        body.merge(xaiImageOptions(from: options)) { _, new in new }
        body.merge(xaiImageEditInputs(from: request.files)) { _, new in new }

        let response = try await config.sendJSONResponse(path: endpoint, modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = response.json
        let data = raw["data"]?.arrayValue ?? []
        let urls = data.compactMap { $0["url"]?.stringValue }
        let base64Images: [String]
        let inlineImages = data.compactMap { $0["b64_json"]?.stringValue }
        if inlineImages.count == data.count {
            base64Images = inlineImages
        } else {
            base64Images = try await downloadXAIImages(urls: urls, abortSignal: request.abortSignal)
        }
        return ImageGenerationResult(
            urls: urls,
            base64Images: base64Images,
            rawValue: raw,
            warnings: warnings,
            providerMetadata: xaiImageProviderMetadata(from: raw),
            requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    private func downloadXAIImages(urls: [String], abortSignal: AIAbortSignal?) async throws -> [String] {
        var images: [String] = []
        for url in urls {
            let response = try await downloadURL(url, transport: config.transport, abortSignal: abortSignal)
            guard (200..<300).contains(response.statusCode) else {
                throw apiCallError(provider: providerID, response: response)
            }
            images.append(response.body.base64EncodedString())
        }
        return images
    }
}

public final class XAIVideoModel: VideoModel, @unchecked Sendable {
    public let providerID = "xai.video"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        let options = try xaiProviderOptions(from: request)
        let mode = xaiVideoMode(from: options, request: request)
        let endpoint: String
        if mode == "edit-video" {
            endpoint = "/videos/edits"
        } else if mode == "extend-video" {
            endpoint = "/videos/extensions"
        } else {
            endpoint = "/videos/generations"
        }

        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "prompt": .string(request.prompt)
        ]
        var warnings = xaiVideoWarnings(for: request, options: options, mode: mode)
        if let duration = request.durationSeconds, mode != "edit-video" {
            body["duration"] = .number(duration)
        }
        if let aspectRatio = request.aspectRatio, mode != "edit-video", mode != "extend-video" {
            body["aspect_ratio"] = .string(aspectRatio)
        }
        if mode != "edit-video", mode != "extend-video" {
            if let resolution = options["resolution"], resolution != .null {
                body["resolution"] = resolution
            } else if let resolution = request.resolution {
                if let mapped = xaiVideoResolutionMap[resolution] {
                    body["resolution"] = .string(mapped)
                } else {
                    warnings.append(AIWarning(
                        type: "unsupported",
                        feature: "resolution",
                        message: "Unrecognized resolution \"\(resolution)\". Use providerOptions.xai.resolution with \"480p\" or \"720p\" instead."
                    ))
                }
            }
        }
        for (key, value) in options {
            switch key {
            case "mode", "pollIntervalMs", "pollTimeoutMs", "resolution":
                continue
            case "videoUrl", "video_url":
                body["video"] = .object(["url": value])
            case "referenceImageUrls", "reference_image_urls":
                body["reference_images"] = .array(value.arrayValue?.compactMap { item in
                    item.stringValue.map { .object(["url": .string($0)]) }
                } ?? [])
            case "image", "imageUrl", "image_url":
                continue
            default:
                body[key] = value
            }
        }
        if !request.frameImages.isEmpty || mode == "edit-video" {
            body["reference_images"] = nil
        }
        if !request.inputReferences.isEmpty, request.frameImages.isEmpty, mode != "edit-video" {
            body["reference_images"] = .array(request.inputReferences.map { .object(["url": .string(xaiImageFileURL($0))]) })
        }
        if let firstFrame = request.frameImages.first(where: { $0.frameType == .firstFrame }) {
            body["image"] = .object(["url": .string(xaiImageFileURL(firstFrame.image))])
        } else if let image = xaiVideoImageInput(from: options), body["image"] == nil {
            body["image"] = .object(["url": image])
        }
        if let image = request.image, body["image"] == nil {
            body["image"] = .object(["url": .string(xaiImageFileURL(image))])
        }

        let created = try await config.sendJSON(path: endpoint, modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        guard let requestID = created["request_id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "xAI video create response did not contain request_id.")
        }
        let finalResponse = try await pollXAIResponse(
            requestID: requestID,
            headers: request.headers,
            intervalNanoseconds: xaiPollInterval(options),
            timeoutNanoseconds: xaiPollTimeout(options),
            abortSignal: request.abortSignal
        )
        let raw = finalResponse.json
        guard raw["video"]?["respect_moderation"]?.boolValue != false else {
            throw AIError.invalidResponse(provider: providerID, message: "xAI video generation was blocked by moderation.")
        }
        guard let url = raw["video"]?["url"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "xAI video status response did not contain video.url.")
        }
        return VideoGenerationResult(
            urls: [url],
            operationID: requestID,
            rawValue: raw,
            warnings: warnings,
            providerMetadata: xaiVideoProviderMetadata(from: raw, requestID: requestID, url: url),
            requestMetadata: videoGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: aiResponseMetadata(from: raw, response: finalResponse.response, modelID: modelID)
        )
    }

    private func pollXAIResponse(requestID: String, headers: [String: String], intervalNanoseconds: UInt64, timeoutNanoseconds: UInt64, abortSignal: AIAbortSignal?) async throws -> (json: JSONValue, response: AIHTTPResponse) {
        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            try await sleepWithAbortSignal(nanoseconds: intervalNanoseconds, abortSignal: abortSignal)
            let response = try await config.transport.send(AIHTTPRequest(
                method: "GET",
                url: try requireURL("\(withoutTrailingSlash(config.baseURL))/videos/\(requestID)"),
                headers: config.headers.mergingHeaders(headers),
                abortSignal: abortSignal
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw apiCallError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            if raw["status"]?.stringValue == "done" || raw["video"]?["url"]?.stringValue != nil {
                return (raw, response)
            }
            if ["expired", "failed"].contains(raw["status"]?.stringValue ?? "") {
                throw AIError.invalidResponse(provider: providerID, message: "xAI video generation \(raw["status"]?.stringValue ?? "failed").")
            }
            if DispatchTime.now().uptimeNanoseconds - started > timeoutNanoseconds {
                throw AIError.invalidResponse(provider: providerID, message: "xAI video generation timed out.")
            }
        }
    }
}

private let xaiVideoResolutionMap = [
    "1280x720": "720p",
    "854x480": "480p",
    "640x480": "480p"
]

private func xaiProviderOptions(from request: ImageGenerationRequest) throws -> [String: JSONValue] {
    try xaiProviderOptions(
        providerOptions: request.providerOptions,
        extraBody: request.extraBody,
        validateProviderOptions: xaiValidateImageProviderOptions
    )
}

private func xaiProviderOptions(from request: VideoGenerationRequest) throws -> [String: JSONValue] {
    try xaiProviderOptions(
        providerOptions: request.providerOptions,
        extraBody: request.extraBody,
        validateProviderOptions: xaiValidateVideoProviderOptions
    )
}

private func xaiProviderOptions(
    providerOptions: [String: JSONValue],
    extraBody: [String: JSONValue],
    validateProviderOptions: ([String: JSONValue]) throws -> [String: JSONValue]
) throws -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "xai")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    if let value = providerOptions["xai"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.xai", message: "xAI provider options must be an object.")
        }
        output.merge(try validateProviderOptions(nested)) { _, nested in nested }
    }
    return output
}

private struct XAIPreparedSpeechBody {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
}

private func xaiSpeechBody(for request: SpeechRequest, options: [String: JSONValue]) throws -> XAIPreparedSpeechBody {
    var warnings: [AIWarning] = []
    let codec: String
    if let format = request.format {
        if ["mp3", "wav", "pcm", "mulaw", "alaw"].contains(format) {
            codec = format
        } else {
            codec = "mp3"
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "outputFormat",
                message: "Unsupported output format: \(format). Using mp3 instead."
            ))
        }
    } else {
        codec = "mp3"
    }

    if request.instructions != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "instructions",
            message: "xAI speech models do not support the `instructions` option. Use xAI speech tags in `text` to control delivery."
        ))
    }

    var outputFormat: [String: JSONValue] = ["codec": .string(codec)]
    if let sampleRate = options["sampleRate"] {
        outputFormat["sample_rate"] = sampleRate
    }
    if let bitRate = options["bitRate"] {
        if codec == "mp3" {
            outputFormat["bit_rate"] = bitRate
        } else {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "providerOptions",
                message: "xAI `bitRate` is supported only for mp3 output. It was ignored."
            ))
        }
    }

    var body: [String: JSONValue] = [
        "text": .string(request.text),
        "voice_id": .string(request.voice ?? "eve"),
        "language": .string(request.language ?? "auto"),
        "output_format": .object(outputFormat)
    ]
    if let speed = request.speed {
        body["speed"] = .number(speed)
    }
    if let latency = options["optimizeStreamingLatency"] {
        body["optimize_streaming_latency"] = latency
    }
    if let textNormalization = options["textNormalization"] {
        body["text_normalization"] = textNormalization
    }
    return XAIPreparedSpeechBody(body: body, warnings: warnings)
}

private func xaiSpeechProviderOptions(from request: SpeechRequest) throws -> [String: JSONValue] {
    try xaiNamespacedProviderOptions(
        providerOptions: request.providerOptions,
        extraBody: request.extraBody,
        validateProviderOptions: xaiValidateSpeechProviderOptions
    )
}

private func xaiTranscriptionProviderOptions(from request: AudioTranscriptionRequest) throws -> [String: JSONValue] {
    try xaiNamespacedProviderOptions(
        providerOptions: request.providerOptions,
        extraBody: request.extraBody,
        validateProviderOptions: xaiValidateTranscriptionProviderOptions
    )
}

private func xaiNamespacedProviderOptions(
    providerOptions: [String: JSONValue],
    extraBody: [String: JSONValue],
    validateProviderOptions: ([String: JSONValue]) throws -> [String: JSONValue]
) throws -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "xai")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    if let value = providerOptions["xai"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.xai", message: "xAI provider options must be an object.")
        }
        output.merge(try validateProviderOptions(nested)) { _, nested in nested }
    }
    return output
}

private func xaiValidateSpeechProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options {
        switch key {
        case "sampleRate":
            guard let sampleRate = value.intValue,
                  value.doubleValue == Double(sampleRate),
                  [8_000, 16_000, 22_050, 24_000, 44_100, 48_000].contains(sampleRate) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.sampleRate", message: "xAI sampleRate must be one of 8000, 16000, 22050, 24000, 44100, 48000.")
            }
            output[key] = value
        case "bitRate":
            guard let bitRate = value.intValue,
                  value.doubleValue == Double(bitRate),
                  [32_000, 64_000, 96_000, 128_000, 192_000].contains(bitRate) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.bitRate", message: "xAI bitRate must be one of 32000, 64000, 96000, 128000, 192000.")
            }
            output[key] = value
        case "optimizeStreamingLatency":
            guard let latency = value.intValue,
                  value.doubleValue == Double(latency),
                  [0, 1, 2].contains(latency) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.optimizeStreamingLatency", message: "xAI optimizeStreamingLatency must be 0, 1, or 2.")
            }
            output[key] = value
        case "textNormalization":
            guard value.boolValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.textNormalization", message: "xAI textNormalization must be a boolean.")
            }
            output[key] = value
        default:
            break
        }
    }
    return output
}

private func xaiValidateTranscriptionProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options {
        switch key {
        case "audioFormat":
            guard let format = value.stringValue, ["pcm", "mulaw", "alaw"].contains(format) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.audioFormat", message: "xAI audioFormat must be pcm, mulaw, or alaw.")
            }
            output[key] = value
        case "sampleRate":
            guard let sampleRate = value.intValue,
                  value.doubleValue == Double(sampleRate),
                  [8_000, 16_000, 22_050, 24_000, 44_100, 48_000].contains(sampleRate) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.sampleRate", message: "xAI sampleRate must be one of 8000, 16000, 22050, 24000, 44100, 48000.")
            }
            output[key] = value
        case "language":
            guard value.stringValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.language", message: "xAI language must be a string.")
            }
            output[key] = value
        case "format", "multichannel", "diarize", "fillerWords":
            guard value.boolValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.\(key)", message: "xAI \(key) must be a boolean.")
            }
            output[key] = value
        case "channels":
            guard let channels = value.intValue,
                  value.doubleValue == Double(channels),
                  (2...8).contains(channels) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.channels", message: "xAI channels must be an integer from 2 to 8.")
            }
            output[key] = value
        case "keyterm":
            if value.stringValue != nil {
                output[key] = value
            } else if let array = value.arrayValue, array.allSatisfy({ $0.stringValue != nil }) {
                output[key] = value
            } else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.keyterm", message: "xAI keyterm must be a string or an array of strings.")
            }
        case "streaming":
            continue
        default:
            break
        }
    }
    return output
}

private func xaiTranscriptionFields(from request: AudioTranscriptionRequest, options: [String: JSONValue]) -> [String: JSONValue] {
    var fields: [String: JSONValue] = [:]
    if let audioFormat = options["audioFormat"] { fields["audio_format"] = audioFormat }
    if let sampleRate = options["sampleRate"] { fields["sample_rate"] = sampleRate }
    if let language = request.language.map(JSONValue.string) ?? options["language"] { fields["language"] = language }
    if let format = options["format"] { fields["format"] = format }
    if let multichannel = options["multichannel"] { fields["multichannel"] = multichannel }
    if let channels = options["channels"] { fields["channels"] = channels }
    if let diarize = options["diarize"] { fields["diarize"] = diarize }
    if let fillerWords = options["fillerWords"] { fields["filler_words"] = fillerWords }
    if let keyterm = options["keyterm"] {
        if let string = keyterm.stringValue {
            fields["keyterm"] = .array([.string(string)])
        } else {
            fields["keyterm"] = keyterm
        }
    }
    return fields
}

private func xaiTranscriptionSegments(from raw: JSONValue) -> [TranscriptionSegment] {
    transcriptionSegments(from: raw["words"])
}

private func xaiValidateImageProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options {
        switch key {
        case "aspect_ratio", "output_format", "user":
            guard value.stringValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.\(key)", message: "xAI \(key) must be a string.")
            }
            output[key] = value
        case "sync_mode":
            guard value.boolValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.sync_mode", message: "xAI sync_mode must be a boolean.")
            }
            output[key] = value
        case "resolution":
            guard let resolution = value.stringValue, ["1k", "2k"].contains(resolution) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.resolution", message: "xAI resolution must be 1k or 2k.")
            }
            output[key] = value
        case "quality":
            guard let quality = value.stringValue, ["low", "medium", "high"].contains(quality) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.quality", message: "xAI quality must be low, medium, or high.")
            }
            output[key] = value
        default:
            break
        }
    }
    return output
}

private func xaiValidateVideoProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    for (key, value) in options {
        switch key {
        case "mode":
            guard let mode = value.stringValue, ["edit-video", "extend-video", "reference-to-video"].contains(mode) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.mode", message: "xAI mode must be edit-video, extend-video, or reference-to-video.")
            }
        case "videoUrl":
            guard let videoURL = value.stringValue, !videoURL.isEmpty else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.videoUrl", message: "xAI videoUrl must be a non-empty string.")
            }
        case "referenceImageUrls":
            guard let urls = value.arrayValue, (1...7).contains(urls.count), urls.allSatisfy({ ($0.stringValue ?? "").isEmpty == false }) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.referenceImageUrls", message: "xAI referenceImageUrls must contain 1 to 7 non-empty strings.")
            }
        case "pollIntervalMs", "pollTimeoutMs":
            guard value == .null || (value.doubleValue ?? 0) > 0 else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.\(key)", message: "xAI \(key) must be a positive number or null.")
            }
        case "resolution":
            guard value == .null || ["480p", "720p"].contains(value.stringValue ?? "") else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.resolution", message: "xAI resolution must be 480p, 720p, or null.")
            }
        default:
            break
        }
    }
    return options
}

private func xaiImageWarnings(for request: ImageGenerationRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.size != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "size",
            message: "This model does not support the `size` option. Use `aspectRatio` instead."
        ))
    }
    if request.seed != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "seed"))
    }
    if request.mask != nil {
        warnings.append(AIWarning(type: "unsupported", feature: "mask"))
    }
    return warnings
}

private func xaiVideoWarnings(for request: VideoGenerationRequest, options: [String: JSONValue], mode: String?) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.fps != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "fps",
            message: "xAI video models do not support custom FPS."
        ))
    }
    if request.seed != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "seed",
            message: "xAI video models do not support seed."
        ))
    }
    if let count = request.count, count > 1 {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "n",
            message: "xAI video models do not support generating multiple videos per call. Only 1 video will be generated."
        ))
    }
    if mode == "edit-video", request.durationSeconds != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "duration",
            message: "xAI video editing does not support custom duration."
        ))
    }
    if mode == "edit-video", request.aspectRatio != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "aspectRatio",
            message: "xAI video editing does not support custom aspect ratio."
        ))
    }
    if mode == "edit-video", request.resolution != nil || options["resolution"] != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "resolution",
            message: "xAI video editing does not support custom resolution."
        ))
    }
    if mode == "extend-video", request.aspectRatio != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "aspectRatio",
            message: "xAI video extension does not support custom aspect ratio."
        ))
    }
    if mode == "extend-video", request.resolution != nil || options["resolution"] != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "resolution",
            message: "xAI video extension does not support custom resolution."
        ))
    }
    if request.frameImages.contains(where: { $0.frameType == .lastFrame }) {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "frameImages",
            message: "xAI video models do not support last_frame frameImages. The last_frame image will be ignored."
        ))
    }
    if !request.inputReferences.isEmpty, !request.frameImages.isEmpty {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "inputReferences",
            message: "xAI inputReferences are ignored when frameImages are provided."
        ))
    } else if !request.inputReferences.isEmpty, mode == "edit-video" {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "inputReferences",
            message: "xAI video editing does not support inputReferences."
        ))
    }
    return warnings
}

private func xaiImageOptions(from options: [String: JSONValue]) -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    if let outputFormat = options["outputFormat"] ?? options["output_format"] { output["output_format"] = outputFormat }
    if let syncMode = options["syncMode"] ?? options["sync_mode"] { output["sync_mode"] = syncMode }
    if let resolution = options["resolution"] { output["resolution"] = resolution }
    if let quality = options["quality"] { output["quality"] = quality }
    if let user = options["user"] { output["user"] = user }
    return output
}

private func xaiImageEditInputs(from files: [ImageInputFile]) -> [String: JSONValue] {
    let images = files.map { file -> JSONValue in
        .object([
            "url": .string(xaiImageFileURL(file)),
            "type": .string("image_url")
        ])
    }
    if images.count == 1 {
        return ["image": images[0]]
    }
    if images.count > 1 {
        return ["images": .array(images)]
    }
    return [:]
}

private func xaiImageFileURL(_ file: ImageInputFile) -> String {
    (try? convertImageModelFileToDataURI(file)) ?? ""
}

private func xaiVideoImageInput(from options: [String: JSONValue]) -> JSONValue? {
    let value = options["image"] ?? options["imageUrl"] ?? options["image_url"]
    if let object = value?.objectValue {
        if let url = object["url"] {
            return url
        }
        if let data = object["data"] {
            let mediaType = object["mediaType"]?.stringValue ?? object["media_type"]?.stringValue ?? "image/png"
            return .string("data:\(mediaType);base64,\(data.stringValue ?? "")")
        }
    }
    return value
}

private func xaiVideoMode(from extraBody: [String: JSONValue], request: VideoGenerationRequest) -> String? {
    if let mode = extraBody["mode"]?.stringValue {
        return mode
    }
    if extraBody["videoUrl"]?.stringValue != nil || extraBody["video_url"]?.stringValue != nil {
        return "edit-video"
    }
    let references = extraBody["referenceImageUrls"]?.arrayValue ?? extraBody["reference_image_urls"]?.arrayValue
    if references?.isEmpty == false {
        return "reference-to-video"
    }
    if !request.inputReferences.isEmpty, request.frameImages.isEmpty {
        return "reference-to-video"
    }
    return nil
}

private func xaiImageProviderMetadata(from raw: JSONValue) -> [String: JSONValue] {
    var metadata: [String: JSONValue] = [
        "images": .array((raw["data"]?.arrayValue ?? []).map { item in
            var image: [String: JSONValue] = [:]
            if let revisedPrompt = item["revised_prompt"]?.stringValue {
                image["revisedPrompt"] = .string(revisedPrompt)
            }
            return .object(image)
        })
    ]
    if let cost = raw["usage"]?["cost_in_usd_ticks"] {
        metadata["costInUsdTicks"] = cost
    }
    return ["xai": .object(metadata)]
}

private func xaiVideoProviderMetadata(from raw: JSONValue, requestID: String, url: String) -> [String: JSONValue] {
    var metadata: [String: JSONValue] = [
        "requestId": .string(requestID),
        "videoUrl": .string(url)
    ]
    if let duration = raw["video"]?["duration"] {
        metadata["duration"] = duration
    }
    if let cost = raw["usage"]?["cost_in_usd_ticks"] {
        metadata["costInUsdTicks"] = cost
    }
    if let progress = raw["progress"] {
        metadata["progress"] = progress
    }
    return ["xai": .object(metadata)]
}

private func xaiPollTimeout(_ extraBody: [String: JSONValue]) -> UInt64 {
    guard let milliseconds = extraBody["pollTimeoutMs"]?.doubleValue else { return 600_000_000_000 }
    return UInt64(milliseconds * 1_000_000)
}

private func xaiPollInterval(_ extraBody: [String: JSONValue]) -> UInt64 {
    guard let milliseconds = extraBody["pollIntervalMs"]?.doubleValue else { return 5_000_000_000 }
    return UInt64(max(milliseconds, 1) * 1_000_000.0)
}
