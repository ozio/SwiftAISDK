import Foundation

public enum XAITools {
    public static func imageGeneration(action: String? = nil) -> JSONValue {
        providerTool(
            id: "xai.image_generation",
            name: "image_generation",
            args: action.map { ["action": .string($0)] } ?? [:]
        )
    }

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
            throw xaiHTTPStatusError(provider: providerID, response: response)
        }
        let withTimestamps = options["withTimestamps"]?.boolValue == true
        let envelope: JSONValue? = withTimestamps ? try response.jsonValue() : nil
        let audio: Data
        if let encodedAudio = envelope?["audio"]?.stringValue {
            guard let decodedAudio = Data(base64Encoded: encodedAudio) else {
                throw AIError.invalidResponse(provider: providerID, message: "xAI speech response audio was not valid base64.")
            }
            audio = decodedAudio
        } else if withTimestamps {
            audio = Data()
        } else {
            audio = response.body
        }
        return SpeechResult(
            audio: audio,
            contentType: envelope?["content_type"]?.stringValue ?? response.headers.contentType,
            warnings: prepared.warnings,
            providerMetadata: xaiSpeechProviderMetadata(from: envelope, response: response),
            requestMetadata: AIRequestMetadata(body: .object(prepared.body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: envelope, response: response, modelID: modelID)
        )
    }
}

public final class XAITranscriptionModel: TranscriptionModel, StreamingTranscriptionModel, @unchecked Sendable {
    public let providerID = "xai.transcription"
    public let modelID: String
    private let config: ModelHTTPConfig
    private let webSocketTransport: any AIDuplexWebSocketTransport

    init(modelID: String = "", config: ModelHTTPConfig, webSocketTransport: any AIDuplexWebSocketTransport = URLSessionDuplexWebSocketTransport.shared) {
        self.modelID = modelID
        self.config = config
        self.webSocketTransport = webSocketTransport
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
        for (key, value) in xaiTranscriptionFields(from: request, options: options, modelID: modelID) {
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
        guard raw["text"]?.stringValue != nil, xaiTranscriptionNullableString(raw["language"]), xaiTranscriptionNullableNumber(raw["duration"]),
              raw["words"] == nil || raw["words"] == .null || raw["words"]?.arrayValue?.allSatisfy({ word in
                  word["text"]?.stringValue != nil && word["start"]?.doubleValue != nil && word["end"]?.doubleValue != nil && xaiTranscriptionNullableNumber(word["speaker"])
              }) == true else {
            throw AIError.invalidResponse(provider: providerID, message: "Invalid xAI transcription response.")
        }
        let segments = xaiTranscriptionSegments(from: raw)
        let words = raw["words"]?.arrayValue ?? []
        let metadata: [String: JSONValue] = words.contains { $0["speaker"] != nil && $0["speaker"] != .null }
            ? ["xai": .object(["words": .array(words.map { .object(($0.objectValue ?? [:]).filter { ["text", "start", "end", "speaker"].contains($0.key) }) })])]
            : [:]
        return TranscriptionResult(
            text: raw["text"]?.stringValue ?? "",
            rawValue: raw,
            segments: segments,
            language: raw["language"]?.stringValue,
            durationInSeconds: raw["duration"]?.doubleValue ?? transcriptionDuration(from: segments),
            providerMetadata: metadata,
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
        guard !data.contains(where: { $0["respect_moderation"]?.boolValue == false }) else {
            throw AIError.invalidResponse(provider: providerID, message: "Image generation was blocked due to a content policy violation.")
        }
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
        if let generateAudio = request.generateAudio {
            if mode != "edit-video", mode != "extend-video" {
                body["generate_audio"] = .bool(generateAudio)
            } else {
                warnings.append(AIWarning(
                    type: "unsupported",
                    feature: "generateAudio",
                    message: "xAI \(mode == "edit-video" ? "video editing" : "video extension") does not support generateAudio."
                ))
            }
        }
        if let storage = options["storageOptions"]?.objectValue {
            var storageOptions: [String: JSONValue] = ["filename": storage["filename"] ?? .null]
            if let expiresAfter = storage["expiresAfter"] {
                storageOptions["expires_after"] = expiresAfter
            }
            if let publicURL = storage["publicUrl"] {
                if let publicObject = publicURL.objectValue {
                    var mapped: [String: JSONValue] = [:]
                    if let expiresAfter = publicObject["expiresAfter"] {
                        mapped["expires_after"] = expiresAfter
                    }
                    storageOptions["public_url"] = .object(mapped)
                } else {
                    storageOptions["public_url"] = publicURL
                }
            }
            body["storage_options"] = .object(storageOptions)
        }
        if let keyframes = options["keyframes"]?.arrayValue, !keyframes.isEmpty {
            if modelID != "grok-imagine-video-1.5" || mode == "edit-video" || mode == "extend-video" {
                warnings.append(AIWarning(
                    type: "unsupported",
                    feature: "keyframes",
                    message: modelID != "grok-imagine-video-1.5"
                        ? "xAI only supports keyframes with \"grok-imagine-video-1.5\"."
                        : "xAI \(mode == "edit-video" ? "video editing" : "video extension") does not support keyframes."
                ))
            } else {
                body["keyframes"] = .array(keyframes.compactMap { keyframe in
                    guard let object = keyframe.objectValue,
                          let imageURL = object["imageUrl"],
                          let timestamp = object["timestampSeconds"] else { return nil }
                    return .object(["image": .object(["url": imageURL]), "timestamp_s": timestamp])
                })
            }
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
                        message: "Unrecognized resolution \"\(resolution)\". Use providerOptions.xai.resolution with \"480p\", \"720p\", or \"1080p\" instead."
                    ))
                }
            }
        }
        for (key, value) in options {
            switch key {
            case "mode", "pollIntervalMs", "pollTimeoutMs", "resolution", "referenceImageUrls", "reference_image_urls", "referenceVoiceIds", "reference_voice_ids", "keyframes", "storageOptions":
                continue
            case "videoUrl", "video_url":
                if mode == "edit-video" || mode == "extend-video" {
                    body["video"] = .object(["url": value])
                }
            case "image", "imageUrl", "image_url":
                continue
            case "user":
                if mode != "extend-video" {
                    body[key] = value
                }
            default:
                body[key] = value
            }
        }

        if mode == "reference-to-video" {
            let references = xaiVideoReferenceURLs(from: request, options: options, warnings: &warnings)
            let referenceAudios = xaiVideoReferenceAudioURLs(from: request)
            if !references.isEmpty {
                body["reference_images"] = .array(references.map { .object(["url": .string($0)]) })
            } else if referenceAudios.isEmpty {
                warnings.append(AIWarning(
                    type: "unsupported",
                    feature: "referenceImages",
                    message: "xAI reference-to-video requires at least one image reference. The video will be generated without reference images."
                ))
            }
            var audioInputs: [JSONValue] = referenceAudios.map { .object(["url": .string($0)]) }
            if let referenceVoiceIDs = (options["referenceVoiceIds"] ?? options["reference_voice_ids"])?.arrayValue,
               !referenceVoiceIDs.isEmpty {
                audioInputs.append(contentsOf: referenceVoiceIDs.compactMap { voiceID in
                    voiceID.stringValue.map { .object(["voice_id": .string($0)]) }
                })
            }
            if !audioInputs.isEmpty {
                if audioInputs.count > 3 {
                    warnings.append(AIWarning(type: "unsupported", feature: "inputReferences", message: "xAI reference-to-video supports at most 3 audio references. Only the first 3 were used."))
                }
                body["reference_audios"] = .array(Array(audioInputs.prefix(3)))
            }
            if body["resolution"]?.stringValue == "1080p" {
                warnings.append(AIWarning(
                    type: "unsupported",
                    feature: "resolution",
                    message: "xAI reference-to-video is limited to 720p. The request was downgraded from 1080p to 720p."
                ))
                body["resolution"] = .string("720p")
            }
        } else if !request.inputReferences.isEmpty {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "inputReferences",
                message: xaiHasImageInputReference(request) || xaiHasAudioInputReference(request)
                    ? "xAI only supports inputReferences for reference-to-video generation. The references were ignored."
                    : "xAI reference-to-video requires at least one image or audio reference. The references were ignored."
            ))
        }
        if mode != "reference-to-video",
           let referenceVoiceIDs = (options["referenceVoiceIds"] ?? options["reference_voice_ids"])?.arrayValue,
           !referenceVoiceIDs.isEmpty {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "referenceVoiceIds",
                message: "xAI only supports reference voices for reference-to-video generation. The reference voices were ignored."
            ))
        }
        if let firstFrame = request.frameImages.first(where: { $0.frameType == .firstFrame }) {
            if let url = xaiStartImageURL(firstFrame.image, feature: "frameImages", warnings: &warnings) {
                body["image"] = .object(["url": .string(url)])
            }
        } else if let image = xaiVideoImageInput(from: options), body["image"] == nil {
            body["image"] = .object(["url": image])
        }
        if let image = request.image, body["image"] == nil {
            if let url = xaiStartImageURL(image, feature: "image", warnings: &warnings) {
                body["image"] = .object(["url": .string(url)])
            }
        }
        if let lastFrame = request.frameImages.first(where: { $0.frameType == .lastFrame }) {
            if modelID != "grok-imagine-video-1.5" || mode == "edit-video" || mode == "extend-video" || isVideoInputFile(lastFrame.image) {
                warnings.append(AIWarning(
                    type: "unsupported",
                    feature: "frameImages",
                    message: modelID != "grok-imagine-video-1.5"
                        ? "xAI only supports last_frame with \"grok-imagine-video-1.5\". The last frame was ignored."
                        : "xAI only accepts an image last_frame for video generation. The last frame was ignored."
                ))
            } else if let url = xaiStartImageURL(lastFrame.image, feature: "frameImages", warnings: &warnings) {
                body["last_frame"] = .object(["url": .string(url)])
            }
        }
        if body["resolution"]?.stringValue == "1080p", modelID == "grok-imagine-video" {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "resolution",
                message: "xAI model \"grok-imagine-video\" does not support 1080p. Use \"grok-imagine-video-1.5\" for 1080p, or a lower resolution. The request was sent with 1080p."
            ))
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
            throw AIError.invalidResponse(provider: providerID, message: "Video generation was blocked due to a content policy violation.")
        }
        guard let url = raw["video"]?["url"]?.stringValue
            ?? raw["video"]?["file_output"]?["public_url"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Video generation completed but no video URL was returned.")
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
                url: try requireURL("\(withoutTrailingSlash(config.baseURL))/videos/\(xaiEncodedPathSegment(requestID))"),
                headers: config.headers.mergingHeaders(headers),
                abortSignal: abortSignal
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw apiCallError(provider: providerID, response: response)
            }
            let raw: JSONValue
            if response.statusCode == 202 {
                guard response.body.count <= xaiMaxPendingVideoBodyBytes else {
                    throw AIError.invalidResponse(provider: providerID, message: "xAI video status response exceeded \(xaiMaxPendingVideoBodyBytes) bytes")
                }
                if let parsed = try? response.jsonValue(), parsed.objectValue != nil {
                    raw = parsed
                } else {
                    raw = .object(["status": .string("pending")])
                }
            } else {
                raw = try response.jsonValue()
            }
            let status = raw["status"]?.stringValue
            if status == "expired" {
                throw AIError.invalidResponse(provider: providerID, message: "Video generation request expired.")
            }
            if status == "failed" {
                let errorDetails = raw["error"]?["message"]?.stringValue
                    ?? raw["error"]?["code"]?.stringValue
                let message = errorDetails.map { "Video generation failed: \($0)" }
                    ?? "Video generation failed."
                throw AIError.invalidResponse(provider: providerID, message: message)
            }
            if status == "done" || (status == nil && raw["video"]?["url"]?.stringValue != nil) {
                return (raw, response)
            }
            if DispatchTime.now().uptimeNanoseconds - started > timeoutNanoseconds {
                throw AIError.invalidResponse(provider: providerID, message: "xAI video generation timed out.")
            }
        }
    }
}

private func xaiEncodedPathSegment(_ value: String) -> String {
    if value == "." { return "%252E" }
    if value == ".." { return "%252E%252E" }

    let unescaped = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()".utf8)
    return value.utf8.map { byte in
        if unescaped.contains(byte) {
            return String(UnicodeScalar(byte))
        }
        return String(format: "%%%02X", byte)
    }.joined()
}

private let xaiMaxPendingVideoBodyBytes = 1024 * 1024

private let xaiVideoResolutionMap = [
    "1920x1080": "1080p",
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
    if let withTimestamps = options["withTimestamps"] {
        body["with_timestamps"] = withTimestamps
    }
    if let replacements = options["replace"] {
        body["replace"] = replacements
    }
    return XAIPreparedSpeechBody(body: body, warnings: warnings)
}

private func xaiSpeechProviderMetadata(from envelope: JSONValue?, response: AIHTTPResponse) -> [String: JSONValue] {
    var metadata: [String: JSONValue] = [:]
    if let traceID = response.headerValue("x-trace-id") {
        metadata["traceId"] = .string(traceID)
    }
    if let duration = envelope?["duration"] {
        metadata["duration"] = duration
    }
    if let contentType = envelope?["content_type"] {
        metadata["contentType"] = contentType
    }
    if let timestamps = envelope?["audio_timestamps"] {
        metadata["audioTimestamps"] = .object([
            "graphChars": timestamps["graph_chars"] ?? JSONValue.array([JSONValue]()),
            "graphTimes": timestamps["graph_times"] ?? JSONValue.array([JSONValue]())
        ])
    }
    return ["xai": .object(metadata)]
}

private func xaiHTTPStatusError(provider: String, response: AIHTTPResponse) -> AIError {
    let body: String
    if let raw = try? response.jsonValue(), let error = raw["error"]?.stringValue {
        if let code = raw["code"]?.stringValue {
            body = "\(code): \(error)"
        } else {
            body = error
        }
    } else if let raw = try? response.jsonValue(), let message = raw["error"]?["message"]?.stringValue {
        body = message
    } else {
        body = response.bodyText
    }
    return apiCallError(
        provider: provider,
        statusCode: response.statusCode,
        body: body,
        headers: response.headers
    )
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
        if value == .null {
            continue
        }
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
        case "withTimestamps":
            guard value.boolValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.withTimestamps", message: "xAI withTimestamps must be a boolean.")
            }
            output[key] = value
        case "replace":
            guard let replacements = value.objectValue,
                  replacements.values.allSatisfy({ $0.stringValue != nil }) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.replace", message: "xAI replace must be an object with string values.")
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
        if value == .null, !["vadThreshold", "streaming"].contains(key) {
            continue
        }
        switch key {
        case "audioFormat":
            guard let format = value.stringValue, ["pcm", "mulaw", "alaw", "opus"].contains(format) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.audioFormat", message: "xAI audioFormat must be pcm, mulaw, alaw, or opus.")
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
        case "vadThreshold":
            guard let number = value.doubleValue, number.isFinite, (0...1).contains(number) else { throw AIError.invalidArgument(argument: "providerOptions.xai.vadThreshold", message: "xAI vadThreshold must be between 0 and 1.") }
            output[key] = value
        case "streaming":
            guard let streaming = value.objectValue else { throw AIError.invalidArgument(argument: "providerOptions.xai.streaming", message: "xAI streaming options must be an object.") }
            var fields: [String: JSONValue] = [:]
            for (name, value) in streaming where ["interimResults", "endpointing", "smartTurn", "smartTurnTimeout"].contains(name) {
                let valid: Bool
                if name == "interimResults" { valid = value.boolValue != nil }
                else if name == "smartTurn" { valid = value.doubleValue.map { $0.isFinite && (0...1).contains($0) } ?? false }
                else { valid = value.intValue.map { value.doubleValue == Double($0) && ((name == "endpointing" ? 0 : 1)...5000).contains($0) } ?? false }
                if !valid { throw AIError.invalidArgument(argument: "providerOptions.xai.streaming.\(name)", message: "Invalid xAI streaming option \(name).") }
                fields[name] = value
            }
            output[key] = .object(fields)
        default:
            break
        }
    }
    return output
}

private func xaiTranscriptionFields(from request: AudioTranscriptionRequest, options: [String: JSONValue], modelID: String) -> [String: JSONValue] {
    var fields: [String: JSONValue] = [:]
    if !modelID.isEmpty { fields["model"] = .string(modelID) }
    if let audioFormat = options["audioFormat"] { fields["audio_format"] = audioFormat }
    if let sampleRate = options["sampleRate"] { fields["sample_rate"] = sampleRate }
    if let language = request.language.map(JSONValue.string) ?? options["language"] { fields["language"] = language }
    if let format = options["format"] { fields["format"] = format }
    if let multichannel = options["multichannel"] { fields["multichannel"] = multichannel }
    if let channels = options["channels"] { fields["channels"] = channels }
    if let diarize = options["diarize"] { fields["diarize"] = diarize }
    if let fillerWords = options["fillerWords"] { fields["filler_words"] = fillerWords }
    fields["vad_threshold"] = options["vadThreshold"]
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
            guard let resolution = value.stringValue, ["1k", "1.5k", "2k"].contains(resolution) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.resolution", message: "xAI resolution must be 1k, 1.5k, or 2k.")
            }
            output[key] = value
        case "quality":
            guard let quality = value.stringValue, ["low", "medium", "high", "auto"].contains(quality) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.quality", message: "xAI quality must be low, medium, high, or auto.")
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
        case "referenceVoiceIds":
            guard let voiceIDs = value.arrayValue,
                  voiceIDs.count <= 3,
                  voiceIDs.allSatisfy({ ($0.stringValue ?? "").isEmpty == false }) else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.referenceVoiceIds", message: "xAI referenceVoiceIds must contain at most 3 non-empty strings.")
            }
        case "pollIntervalMs", "pollTimeoutMs":
            guard value == .null || (value.doubleValue ?? 0) > 0 else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.\(key)", message: "xAI \(key) must be a positive number or null.")
            }
        case "resolution":
            guard value == .null || ["480p", "720p", "1080p"].contains(value.stringValue ?? "") else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.resolution", message: "xAI resolution must be 480p, 720p, 1080p, or null.")
            }
        case "keyframes":
            guard let keyframes = value.arrayValue, keyframes.count <= 4 else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.keyframes", message: "xAI keyframes must contain at most 4 entries.")
            }
            for keyframe in keyframes {
                guard let object = keyframe.objectValue,
                      let imageURL = object["imageUrl"]?.stringValue,
                      !imageURL.isEmpty,
                      let timestamp = object["timestampSeconds"]?.doubleValue,
                      timestamp > 0 else {
                    throw AIError.invalidArgument(argument: "providerOptions.xai.keyframes", message: "Each xAI keyframe must contain a non-empty imageUrl and a positive timestampSeconds.")
                }
            }
        case "storageOptions":
            guard let storage = value.objectValue,
                  let filename = storage["filename"]?.stringValue,
                  !filename.isEmpty else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.storageOptions", message: "xAI storageOptions must contain a non-empty filename.")
            }
            if let expiresAfter = storage["expiresAfter"] {
                guard let seconds = expiresAfter.intValue,
                      expiresAfter.doubleValue == Double(seconds),
                      (1...2_592_000).contains(seconds) else {
                    throw AIError.invalidArgument(argument: "providerOptions.xai.storageOptions.expiresAfter", message: "xAI storage expiresAfter must be a positive integer no greater than 2592000.")
                }
            }
            if let publicURL = storage["publicUrl"] {
                if publicURL.boolValue == nil {
                    guard let publicObject = publicURL.objectValue else {
                        throw AIError.invalidArgument(argument: "providerOptions.xai.storageOptions.publicUrl", message: "xAI storage publicUrl must be a boolean or an object.")
                    }
                    if let expiresAfter = publicObject["expiresAfter"] {
                        guard let seconds = expiresAfter.intValue,
                              expiresAfter.doubleValue == Double(seconds),
                              (3_600...2_592_000).contains(seconds) else {
                            throw AIError.invalidArgument(argument: "providerOptions.xai.storageOptions.publicUrl.expiresAfter", message: "xAI public URL expiresAfter must be an integer from 3600 through 2592000.")
                        }
                    }
                }
            }
        case "user":
            guard value.stringValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.xai.user", message: "xAI user must be a string.")
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

private func xaiReferenceImageURL(_ file: ImageInputFile, warnings: inout [AIWarning]) -> String? {
    if xaiIsAudioReference(file) {
        return nil
    }
    guard xaiIsImageReference(file) else {
        let message: String
        if isVideoInputFile(file) {
            message = "xAI reference-to-video does not accept video references. The video reference was ignored. Use providerOptions.xai.mode \"extend-video\" to continue from a video."
        } else {
            message = "xAI reference-to-video accepts image references only. The non-image reference was ignored."
        }
        warnings.append(AIWarning(type: "unsupported", feature: "inputReferences", message: message))
        return nil
    }
    return xaiImageFileURL(file)
}

private func xaiIsImageReference(_ file: ImageInputFile) -> Bool {
    guard let mediaType = file.mediaType else { return true }
    return topLevelMediaType(mediaType.lowercased()) == "image"
}

private func xaiHasImageInputReference(_ request: VideoGenerationRequest) -> Bool {
    request.inputReferences.contains(where: xaiIsImageReference)
}

private func xaiIsAudioReference(_ file: ImageInputFile) -> Bool {
    guard let mediaType = file.mediaType else { return false }
    return topLevelMediaType(mediaType.lowercased()) == "audio"
}

private func xaiHasAudioInputReference(_ request: VideoGenerationRequest) -> Bool {
    request.inputReferences.contains(where: xaiIsAudioReference)
}

private func xaiVideoReferenceURLs(
    from request: VideoGenerationRequest,
    options: [String: JSONValue],
    warnings: inout [AIWarning]
) -> [String] {
    if !request.inputReferences.isEmpty {
        return request.inputReferences.compactMap { xaiReferenceImageURL($0, warnings: &warnings) }
    }
    return (options["referenceImageUrls"] ?? options["reference_image_urls"])?
        .arrayValue?
        .compactMap(\.stringValue) ?? []
}

private func xaiVideoReferenceAudioURLs(from request: VideoGenerationRequest) -> [String] {
    request.inputReferences.compactMap { file in
        xaiIsAudioReference(file) ? xaiImageFileURL(file) : nil
    }
}

private func xaiStartImageURL(_ file: ImageInputFile, feature: String, warnings: inout [AIWarning]) -> String? {
    guard !isVideoInputFile(file) else {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: feature,
            message: "xAI does not accept a video as a start/frame image. The video was ignored. Use providerOptions.xai.mode \"extend-video\" to continue from a video instead."
        ))
        return nil
    }
    return xaiImageFileURL(file)
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
    if xaiHasImageInputReference(request) || xaiHasAudioInputReference(request) {
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
    if let fileOutput = raw["video"]?["file_output"]?.objectValue {
        var mapped: [String: JSONValue] = [:]
        if let fileID = fileOutput["file_id"] { mapped["fileId"] = fileID }
        if let filename = fileOutput["filename"] { mapped["filename"] = filename }
        if let expiresAt = fileOutput["expires_at"] { mapped["expiresAt"] = expiresAt }
        if let publicURL = fileOutput["public_url"] { mapped["publicUrl"] = publicURL }
        if let publicURLError = fileOutput["public_url_error"] { mapped["publicUrlError"] = publicURLError }
        if let publicURLExpiresAt = fileOutput["public_url_expires_at"] {
            mapped["publicUrlExpiresAt"] = publicURLExpiresAt
        }
        metadata["fileOutput"] = .object(mapped)
    }
    if let storageError = raw["video"]?["storage_error"] {
        metadata["storageError"] = storageError
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

extension XAITranscriptionModel {
    public func stream(_ request: StreamingTranscriptionRequest) async throws -> StreamingTranscriptionResult {
        let rawOptions = request.providerOptions["xai"]
        guard rawOptions == nil || rawOptions == .null || rawOptions?.objectValue != nil else {
            throw AIError.invalidArgument(argument: "providerOptions.xai", message: "xAI provider options must be an object.")
        }
        let options = try xaiValidateTranscriptionProviderOptions(rawOptions?.objectValue ?? [:])
        if options["multichannel"] == true, options["channels"] == nil {
            throw AIError.invalidArgument(argument: "providerOptions.xai.channels", message: "providerOptions.xai.channels is required when providerOptions.xai.multichannel is true")
        }
        var warnings: [AIWarning] = []
        if options["format"] != nil { warnings.append(AIWarning(type: "unsupported", feature: "providerOptions.xai.format", message: "xAI streaming transcription does not support format.")) }
        let encodings = ["audio/pcm": "pcm", "audio/pcmu": "mulaw", "audio/pcma": "alaw", "audio/opus": "opus"]
        if options["audioFormat"] == nil, encodings[request.inputAudioFormat.mediaType] == nil {
            warnings.append(AIWarning(type: "other", message: "Unrecognized inputAudioFormat.type \"\(request.inputAudioFormat.mediaType)\"; falling back to raw PCM encoding. Use audio/pcm, audio/pcmu, audio/pcma, audio/opus, or set providerOptions.xai.audioFormat explicitly."))
        }
        do { try request.abortSignal?.throwIfAborted() }
        catch { request.audio.cancelFromConsumer(); throw error }
        let http = try config.rawRequest(path: "/stt", modelID: modelID, body: Data(), contentType: nil, headers: request.headers, abortSignal: request.abortSignal)
        guard var components = URLComponents(url: http.url, resolvingAgainstBaseURL: false) else { throw AIError.invalidURL(http.url.absoluteString) }
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        var fields = xaiTranscriptionFields(from: AudioTranscriptionRequest(audio: Data(), mimeType: request.inputAudioFormat.mediaType), options: options, modelID: modelID)
        fields.removeValue(forKey: "audio_format")
        fields.removeValue(forKey: "format")
        fields["encoding"] = options["audioFormat"] ?? .string(encodings[request.inputAudioFormat.mediaType] ?? "pcm")
        if fields["sample_rate"] == nil, let rate = request.inputAudioFormat.sampleRate { fields["sample_rate"] = .number(Double(rate)) }
        if let streaming = options["streaming"]?.objectValue {
            for (name, value) in streaming {
                let mapped = ["interimResults": "interim_results", "endpointing": "endpointing", "smartTurn": "smart_turn", "smartTurnTimeout": "smart_turn_timeout"][name]!
                fields[mapped] = value
            }
        }
        var items = components.queryItems ?? []
        for key in fields.keys.sorted() {
            let values = fields[key]!.arrayValue ?? [fields[key]!]
            for value in values { if let scalar = jsonScalarString(value) { items.append(URLQueryItem(name: key, value: scalar)) } }
        }
        components.queryItems = items
        guard let url = components.url else { throw AIError.invalidURL(http.url.absoluteString) }
        let connection: any AIDuplexWebSocketConnection
        do { connection = try await webSocketTransport.connect(AIDuplexWebSocketRequest(url: url, headers: http.headers, abortSignal: request.abortSignal)) }
        catch { request.audio.cancelFromConsumer(); throw error }
        let session = XAIStreamingTranscriptionSession(connection: connection, request: request, warnings: warnings,
                                                       language: options["language"]?.stringValue,
                                                       expectedDoneCount: options["multichannel"] == true ? options["channels"]!.intValue! : 1)
        let stream = await session.start()
        return StreamingTranscriptionResult(stream: stream, requestMetadata: AIRequestMetadata(body: .string(url.absoluteString), headers: request.headers),
                                            responseMetadata: AIResponseMetadata(timestamp: Date(), modelID: modelID), cancel: { Task { await session.cancel() } })
    }
}

private actor XAIStreamingTranscriptionSession {
    let connection: any AIDuplexWebSocketConnection
    let request: StreamingTranscriptionRequest
    let warnings: [AIWarning]
    let language: String?
    let expectedDoneCount: Int
    var continuation: AsyncThrowingStream<StreamingTranscriptionPart, Error>.Continuation?
    var eventTask: Task<Void, Never>?
    var audioTask: Task<Void, Never>?
    var abortRegistration: AIAbortHandlerRegistration?
    var completed = false
    var audioStarted = false
    var doneTexts: [Int: String] = [:]
    var finalizedTexts: [Int: [String]] = [:]
    var pendingTexts: [Int: String] = [:]
    var duration: Double?

    init(connection: any AIDuplexWebSocketConnection, request: StreamingTranscriptionRequest, warnings: [AIWarning], language: String?, expectedDoneCount: Int) {
        self.connection = connection; self.request = request; self.warnings = warnings; self.language = language; self.expectedDoneCount = expectedDoneCount
    }
    func start() -> AsyncThrowingStream<StreamingTranscriptionPart, Error> {
        let pair = AsyncThrowingStream<StreamingTranscriptionPart, Error>.makeStream()
        continuation = pair.continuation
        continuation?.onTermination = { termination in if case .cancelled = termination { Task { await self.cancel() } } }
        abortRegistration = request.abortSignal?.addAbortHandler { [weak signal = request.abortSignal] reason in
            let error = AIAbortError(reason: reason, reasonName: signal?.reasonName)
            Task { await self.complete(error: error, finish: nil) }
        }
        eventTask = Task { await consumeEvents() }
        return pair.stream
    }
    func cancel() async { await complete(error: nil, finish: nil) }
    private func consumeEvents() async {
        do {
            for try await event in connection.events {
                guard !completed else { return }
                switch event {
                case .opened: break
                case .closed: await complete(error: nil, finish: nil)
                case let .message(message):
                    let data: Data
                    switch message { case let .text(text): data = Data(text.utf8); case let .binary(bytes): data = bytes }
                    guard let raw = try? decodeJSONBody(data) else { continue }
                    if request.includeRawChunks { continuation?.yield(.raw(raw)) }
                    await process(raw)
                }
            }
            if !completed { await complete(error: nil, finish: nil) }
        } catch { await complete(error: error, finish: nil) }
    }
    private func process(_ raw: JSONValue) async {
        let channel = raw["channel_index"]?.intValue
        let channelIndex = channel ?? 0
        let id = channel.map { "channel-\($0)" }
        let text = raw["text"]?.stringValue ?? ""
        switch raw["type"]?.stringValue {
        case "transcript.created":
            guard !audioStarted else { return }
            audioStarted = true
            continuation?.yield(.streamStart(warnings: warnings))
            audioTask = Task { await sendAudio() }
        case "transcript.partial":
            let start = raw["start"]?.doubleValue
            let duration = raw["duration"]?.doubleValue
            if raw["is_final"] == true, raw["speech_final"] == true {
                if !text.isEmpty { finalizedTexts[channelIndex, default: []].append(text) }
                pendingTexts.removeValue(forKey: channelIndex)
                continuation?.yield(.transcriptFinal(id: id, text: text, startSecond: start, endSecond: start.flatMap { start in duration.map { start + $0 } }, channelIndex: channel))
            } else {
                pendingTexts[channelIndex] = text
                continuation?.yield(.transcriptPartial(id: id, text: text, startSecond: start, durationInSeconds: duration, channelIndex: channel))
            }
        case "transcript.done":
            let pending = pendingTexts[channelIndex].flatMap { $0.isEmpty ? nil : $0 }
            let accumulated = ((finalizedTexts[channelIndex] ?? []) + (pending.map { [$0] } ?? [])).joined(separator: " ")
            doneTexts[channelIndex] = text.isEmpty ? accumulated : text
            duration = raw["duration"]?.doubleValue ?? duration
            if doneTexts.count >= expectedDoneCount {
                let text = doneTexts.sorted { $0.key < $1.key }.map(\.value).joined(separator: "\n")
                await complete(error: nil, finish: StreamingTranscriptionFinish(text: text, language: language, durationInSeconds: duration))
            }
        case "error": await complete(error: AIStreamingTranscriptionError(provider: "xai.transcription", message: raw["message"]?.stringValue ?? "xAI STT error", rawValue: raw), finish: nil)
        default: break
        }
    }
    private func sendAudio() async {
        do {
            for try await chunk in request.audio {
                guard !completed else { return }
                try Task.checkCancellation()
                try request.abortSignal?.throwIfAborted()
                try await connection.send(binary: chunk)
            }
            guard !completed else { return }
            try await connection.send(text: "{\"type\":\"audio.done\"}")
        } catch { await complete(error: error, finish: nil) }
    }
    private func complete(error: Error?, finish: StreamingTranscriptionFinish?) async {
        guard !completed else { return }
        completed = true
        eventTask?.cancel(); audioTask?.cancel(); abortRegistration?.cancel()
        eventTask = nil; audioTask = nil; abortRegistration = nil
        request.audio.cancelFromConsumer()
        if let finish { continuation?.yield(.finish(finish)) }
        if let error { continuation?.finish(throwing: error) } else { continuation?.finish() }
        continuation = nil
        await connection.close(code: finish == nil ? 1001 : 1000)
    }
}

private func xaiTranscriptionNullableString(_ value: JSONValue?) -> Bool { value == nil || value == .null || value?.stringValue != nil }
private func xaiTranscriptionNullableNumber(_ value: JSONValue?) -> Bool { value == nil || value == .null || value?.doubleValue?.isFinite == true }
