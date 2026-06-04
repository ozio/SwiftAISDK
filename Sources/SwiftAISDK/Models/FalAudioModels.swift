import Foundation

public final class FalSpeechModel: SpeechModel, @unchecked Sendable {
    public let providerID = "fal.speech"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func speak(_ request: SpeechRequest) async throws -> SpeechResult {
        let options = try falProviderOptions(from: request)
        let outputFormat = request.format == "hex" ? "hex" : "url"
        let warnings = falSpeechWarnings(for: request)
        var body: [String: JSONValue] = [
            "text": .string(request.text),
            "output_format": .string(outputFormat)
        ]
        if let voice = request.voice { body["voice"] = .string(voice) }
        if let speed = request.speed { body["speed"] = .number(speed) }
        body.merge(options) { _, new in new }

        let submit = try await config.sendJSONResponse(path: "/\(modelID)", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        let raw = submit.json
        guard let audioURL = raw["audio"]?["url"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Fal speech response did not contain audio.url.")
        }
        let audioResponse = try await downloadURL(audioURL, transport: config.transport, abortSignal: request.abortSignal)
        guard (200..<300).contains(audioResponse.statusCode) else {
            throw httpStatusError(provider: providerID, response: audioResponse)
        }
        return SpeechResult(
            audio: audioResponse.body,
            contentType: audioResponse.headers.contentType,
            warnings: warnings,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: submit.response, modelID: modelID)
        )
    }
}

public final class FalTranscriptionModel: TranscriptionModel, @unchecked Sendable {
    public let providerID = "fal.transcription"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        let options = try falProviderOptions(from: request)
        var body: [String: JSONValue] = [
            "audio_url": .string("data:\(request.mimeType);base64,\(request.audio.base64EncodedString())"),
            "task": .string("transcribe"),
            "diarize": .bool(true),
            "chunk_level": .string("word")
        ]
        if let language = request.language { body["language"] = .string(language) }
        for (key, value) in options {
            switch key {
            case "chunkLevel":
                body["chunk_level"] = value
            case "batchSize":
                body["batch_size"] = value
            case "numSpeakers":
                body["num_speakers"] = value
            default:
                body[key] = value
            }
        }
        let normalized = modelID.replacingOccurrences(of: #"^(fal-ai/|fal/)"#, with: "", options: .regularExpression)
        let queueResponse = try await config.transport.send(AIHTTPRequest(
            method: "POST",
            url: try requireURL("https://queue.fal.run/fal-ai/\(normalized)"),
            headers: config.headers
                .mergingHeaders(request.headers)
                .mergingHeaders(["content-type": "application/json"]),
            body: try encodeJSONBody(.object(body)),
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(queueResponse.statusCode) else {
            throw httpStatusError(provider: providerID, response: queueResponse)
        }
        let queued = try queueResponse.jsonValue()
        guard let requestID = queued["request_id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Fal transcription queue response did not contain request_id.")
        }
        let finalResponse = try await pollFalTranscriptionResponse(modelPath: normalized, requestID: requestID, headers: request.headers, abortSignal: request.abortSignal)
        let raw = finalResponse.json
        let segments = falTranscriptionSegments(from: raw)
        return TranscriptionResult(
            text: raw["text"]?.stringValue ?? "",
            rawValue: raw,
            segments: segments,
            language: raw["inferred_languages"]?[0]?.stringValue ?? raw["language"]?.stringValue,
            durationInSeconds: raw["duration"]?.doubleValue ?? transcriptionDuration(from: segments),
            responseMetadata: aiResponseMetadata(from: raw, response: finalResponse.response, modelID: modelID)
        )
    }

    private func pollFalTranscriptionResponse(modelPath: String, requestID: String, headers: [String: String], abortSignal: AIAbortSignal?) async throws -> (json: JSONValue, response: AIHTTPResponse) {
        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            let response = try await config.transport.send(AIHTTPRequest(
                method: "GET",
                url: try requireURL("https://queue.fal.run/fal-ai/\(modelPath)/requests/\(requestID)"),
                headers: config.headers.mergingHeaders(headers),
                abortSignal: abortSignal
            ))
            if (200..<300).contains(response.statusCode) {
                return (try response.jsonValue(), response)
            }
            if !falIsTranscriptionInProgress(response) {
                throw httpStatusError(provider: providerID, response: response)
            }
            if DispatchTime.now().uptimeNanoseconds - started > 60_000_000_000 {
                throw AIError.invalidResponse(provider: providerID, message: "Fal transcription request timed out.")
            }
            try await sleepWithAbortSignal(nanoseconds: 1_000_000_000, abortSignal: abortSignal)
        }
    }
}

private func falProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "fal")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func falProviderOptions(from request: SpeechRequest) throws -> [String: JSONValue] {
    try falProviderOptions(
        extraBody: request.extraBody,
        providerOptions: request.providerOptions,
        validateProviderOptions: falValidateSpeechProviderOptions
    )
}

private func falProviderOptions(from request: AudioTranscriptionRequest) throws -> [String: JSONValue] {
    try falProviderOptions(
        extraBody: request.extraBody,
        providerOptions: request.providerOptions,
        validateProviderOptions: falValidateTranscriptionProviderOptions
    )
}

private func falProviderOptions(
    extraBody: [String: JSONValue],
    providerOptions: [String: JSONValue],
    validateProviderOptions: ([String: JSONValue]) throws -> [String: JSONValue]
) throws -> [String: JSONValue] {
    var output = falProviderOptions(from: extraBody)
    if let value = providerOptions["fal"] {
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.fal", message: "fal provider options must be an object.")
        }
        output.merge(try validateProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

private func falSpeechWarnings(for request: SpeechRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if request.language != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "language",
            message: "fal speech models don't support 'language' directly; consider providerOptions.fal.language_boost"
        ))
    }
    if let format = request.format, format != "url", format != "hex" {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "outputFormat",
            message: "Unsupported outputFormat: \(format). Using 'url' instead."
        ))
    }
    return warnings
}

private func falValidateSpeechProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    for (key, value) in options {
        switch key {
        case "voice_setting":
            try falValidateVoiceSetting(value)
        case "audio_setting":
            guard value == .null || value.objectValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.fal.audio_setting", message: "fal audio_setting must be an object or null.")
            }
        case "language_boost":
            try falRequireEnumOrNull(value, argument: "providerOptions.fal.language_boost", label: "language_boost", allowed: falLanguageBoosts)
        case "pronunciation_dict":
            try falRequireStringRecordOrNull(value, argument: "providerOptions.fal.pronunciation_dict", label: "pronunciation_dict")
        default:
            break
        }
    }
    return options
}

private func falValidateTranscriptionProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [
        "language": .string("en"),
        "diarize": .bool(true),
        "chunkLevel": .string("segment"),
        "version": .string("3"),
        "batchSize": .number(64)
    ]
    if let numSpeakers = options["numSpeakers"], numSpeakers != .null {
        output["numSpeakers"] = numSpeakers
    }
    for (key, value) in options {
        switch key {
        case "language":
            try falRequireStringOrNull(value, argument: "providerOptions.fal.language", label: "language")
            output[key] = value
        case "diarize":
            try falRequireBooleanOrNull(value, argument: "providerOptions.fal.diarize", label: "diarize")
            if value == .null {
                output.removeValue(forKey: key)
            } else {
                output[key] = value
            }
        case "chunkLevel":
            try falRequireEnumOrNull(value, argument: "providerOptions.fal.chunkLevel", label: "chunkLevel", allowed: ["segment", "word"])
            if value == .null {
                output.removeValue(forKey: key)
            } else {
                output[key] = value
            }
        case "version":
            try falRequireEnumOrNull(value, argument: "providerOptions.fal.version", label: "version", allowed: ["3"])
            if value == .null {
                output.removeValue(forKey: key)
            } else {
                output[key] = value
            }
        case "batchSize":
            try falRequireNumberOrNull(value, argument: "providerOptions.fal.batchSize", label: "batchSize")
            if value == .null {
                output.removeValue(forKey: key)
            } else {
                output[key] = value
            }
        case "numSpeakers":
            try falRequireNumberOrNull(value, argument: "providerOptions.fal.numSpeakers", label: "numSpeakers")
            if value == .null {
                output.removeValue(forKey: key)
            } else {
                output[key] = value
            }
        default:
            break
        }
    }
    return output
}

private func falValidateVoiceSetting(_ value: JSONValue) throws {
    guard value != .null else { return }
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.fal.voice_setting", message: "fal voice_setting must be an object or null.")
    }
    for (key, nested) in object {
        switch key {
        case "speed", "vol", "pitch":
            try falRequireNumberOrNull(nested, argument: "providerOptions.fal.voice_setting.\(key)", label: "voice_setting.\(key)")
        case "voice_id":
            try falRequireStringOrNull(nested, argument: "providerOptions.fal.voice_setting.voice_id", label: "voice_setting.voice_id")
        case "english_normalization":
            try falRequireBooleanOrNull(nested, argument: "providerOptions.fal.voice_setting.english_normalization", label: "voice_setting.english_normalization")
        case "emotion":
            try falRequireEnumOrNull(nested, argument: "providerOptions.fal.voice_setting.emotion", label: "voice_setting.emotion", allowed: falEmotions)
        default:
            break
        }
    }
}

private func falRequireStringRecordOrNull(_ value: JSONValue, argument: String, label: String) throws {
    guard value != .null else { return }
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: argument, message: "fal \(label) must be an object with string values or null.")
    }
    for (key, nested) in object where nested.stringValue == nil {
        throw AIError.invalidArgument(argument: "\(argument).\(key)", message: "fal \(label) values must be strings.")
    }
}

private func falRequireStringOrNull(_ value: JSONValue, argument: String, label: String) throws {
    guard value == .null || value.stringValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: "fal \(label) must be a string or null.")
    }
}

private func falRequireBooleanOrNull(_ value: JSONValue, argument: String, label: String) throws {
    guard value == .null || value.boolValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: "fal \(label) must be a boolean or null.")
    }
}

private func falRequireNumberOrNull(_ value: JSONValue, argument: String, label: String) throws {
    guard value == .null || value.doubleValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: "fal \(label) must be a number or null.")
    }
}

private func falRequireEnumOrNull(_ value: JSONValue, argument: String, label: String, allowed: Set<String>) throws {
    guard value != .null else { return }
    guard let string = value.stringValue, allowed.contains(string) else {
        throw AIError.invalidArgument(argument: argument, message: "fal \(label) must be one of \(allowed.sorted().joined(separator: ", ")) or null.")
    }
}

private let falLanguageBoosts: Set<String> = [
    "Chinese",
    "Chinese,Yue",
    "English",
    "Arabic",
    "Russian",
    "Spanish",
    "French",
    "Portuguese",
    "German",
    "Turkish",
    "Dutch",
    "Ukrainian",
    "Vietnamese",
    "Indonesian",
    "Japanese",
    "Italian",
    "Korean",
    "Thai",
    "Polish",
    "Romanian",
    "Greek",
    "Czech",
    "Finnish",
    "Hindi",
    "auto"
]

private let falEmotions: Set<String> = [
    "happy",
    "sad",
    "angry",
    "fearful",
    "disgusted",
    "surprised",
    "neutral"
]

private func falTranscriptionSegments(from raw: JSONValue) -> [TranscriptionSegment] {
    raw["chunks"]?.arrayValue?.compactMap { chunk in
        guard let text = chunk["text"]?.stringValue, !text.isEmpty else { return nil }
        let start = chunk["timestamp"]?[0]?.doubleValue ?? 0
        let end = chunk["timestamp"]?[1]?.doubleValue ?? start
        return TranscriptionSegment(text: text, startSecond: start, endSecond: end)
    } ?? []
}

private func falIsTranscriptionInProgress(_ response: AIHTTPResponse) -> Bool {
    guard let raw = try? response.jsonValue() else { return false }
    return raw["detail"]?.stringValue == "Request is still in progress"
}
