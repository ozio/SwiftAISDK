import Foundation

public typealias FishAudioSpeechModelID = String
public typealias FishAudioSpeechVoiceID = String
public typealias FishAudioTranscriptionModelID = String

public final class FishAudioSpeechModel: SpeechModel, @unchecked Sendable {
    public let providerID = "fish-audio.speech"
    public let modelID: FishAudioSpeechModelID

    private let config: ModelHTTPConfig

    init(modelID: FishAudioSpeechModelID, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func speak(_ request: SpeechRequest) async throws -> SpeechResult {
        var warnings: [AIWarning] = []
        let parsed = try fishAudioSpeechOptions(from: request)
        let format = fishAudioSpeechFormat(request.format, warnings: &warnings)

        var body: [String: JSONValue] = [
            "text": .string(request.text),
            "format": .string(format)
        ]

        if let referenceID = parsed.options["referenceId"] {
            body["reference_id"] = referenceID
        } else if let voice = request.voice {
            body["reference_id"] = .string(voice)
        }

        var prosody: [String: JSONValue] = [:]
        if let speed = request.speed {
            if (0.5...2).contains(speed) {
                prosody["speed"] = .number(speed)
            } else {
                warnings.append(AIWarning(
                    type: "unsupported",
                    feature: "speed",
                    message: "Fish Audio speed must be between 0.5 and 2. The speed option was ignored."
                ))
            }
        }
        if let volume = parsed.options["volume"] {
            prosody["volume"] = volume
        }
        if let normalizeLoudness = parsed.options["normalizeLoudness"] {
            if modelID == "s1" {
                warnings.append(AIWarning(
                    type: "unsupported",
                    feature: "providerOptions.fishAudio.normalizeLoudness",
                    message: "Fish Audio ignores normalizeLoudness on s1. It is supported by the S2 family (s2-pro, s2.1-pro)."
                ))
            } else {
                prosody["normalize_loudness"] = normalizeLoudness
            }
        }
        if !prosody.isEmpty {
            body["prosody"] = .object(prosody)
        }

        if request.language != nil {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "language",
                message: "Fish Audio infers the language from the input text and the selected voice, and has no language parameter. The language option was ignored."
            ))
        }
        if request.instructions != nil {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "instructions",
                message: "Fish Audio does not support instructions. The instructions option was ignored."
            ))
        }

        fishAudioApplySpeechOptions(
            parsed.options,
            format: format,
            body: &body,
            warnings: &warnings
        )
        body.merge(parsed.bodyOverrides) { _, override in override }

        let response = try await config.transport.send(config.request(
            path: "/v1/tts",
            modelID: modelID,
            body: .object(body),
            headers: ["model": modelID].mergingHeaders(request.headers),
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw fishAudioHTTPStatusError(
                provider: providerID,
                response: response
            )
        }

        return SpeechResult(
            audio: response.body,
            contentType: response.headers.contentType,
            warnings: warnings,
            requestMetadata: AIRequestMetadata(
                body: .object(body),
                headers: request.headers
            ),
            responseMetadata: aiResponseMetadata(
                response: response,
                modelID: modelID
            )
        )
    }
}

public final class FishAudioTranscriptionModel: TranscriptionModel, @unchecked Sendable {
    public let providerID = "fish-audio.transcription"
    public let modelID: FishAudioTranscriptionModelID

    private let config: ModelHTTPConfig

    init(modelID: FishAudioTranscriptionModelID, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func transcribe(
        _ request: AudioTranscriptionRequest
    ) async throws -> TranscriptionResult {
        var parsed = try fishAudioTranscriptionOptions(from: request)
        let fileName = "audio.\(mediaTypeToExtension(request.mimeType))"
        var form = MultipartFormData()
        form.appendFile(
            name: "audio",
            fileName: fileName,
            mimeType: request.mimeType,
            data: request.audio
        )

        var metadataBody: [String: JSONValue] = [
            "audio": .object([
                "filename": .string(fileName),
                "mimeType": .string(request.mimeType),
                "byteLength": .number(Double(request.audio.count))
            ])
        ]
        if let language = parsed.options["language"]?.stringValue {
            form.appendField(name: "language", value: language)
            metadataBody["language"] = .string(language)
        }

        if let rawIgnoreTimestamps = parsed.formOverrides.removeValue(
            forKey: "ignore_timestamps"
        ), let scalar = jsonScalarString(rawIgnoreTimestamps) {
            form.appendField(name: "ignore_timestamps", value: scalar)
            metadataBody["ignore_timestamps"] = rawIgnoreTimestamps
        } else {
            let ignoreTimestamps = parsed.options["ignoreTimestamps"]?.boolValue
                ?? false
            form.appendField(
                name: "ignore_timestamps",
                value: String(ignoreTimestamps)
            )
            metadataBody["ignore_timestamps"] = .bool(ignoreTimestamps)
        }

        for (key, value) in parsed.formOverrides {
            appendFishAudioMultipartField(
                name: key,
                value: value,
                form: &form
            )
            metadataBody[key] = value
        }

        let response = try await config.transport.send(config.rawRequest(
            path: "/v1/asr",
            modelID: modelID,
            body: form.finalize(),
            contentType: "multipart/form-data; boundary=\(form.boundary)",
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw fishAudioHTTPStatusError(
                provider: providerID,
                response: response
            )
        }

        let raw = try response.jsonValue()
        let parsedResponse = try parseFishAudioTranscriptionResponse(raw)
        var providerMetadata: [String: JSONValue] = [:]
        if let displayLanguage = parsedResponse.displayLanguage {
            providerMetadata["fishAudio"] = .object([
                "language": .string(displayLanguage)
            ])
        }

        return TranscriptionResult(
            text: parsedResponse.text,
            rawValue: raw,
            segments: parsedResponse.segments,
            language: parsedResponse.languageCode,
            durationInSeconds: parsedResponse.duration,
            providerMetadata: providerMetadata,
            requestMetadata: AIRequestMetadata(
                body: .object(metadataBody),
                headers: request.headers
            ),
            responseMetadata: aiResponseMetadata(
                from: raw,
                response: response,
                modelID: modelID
            )
        )
    }
}

private struct FishAudioParsedOptions {
    var options: [String: JSONValue]
    var bodyOverrides: [String: JSONValue]
}

private struct FishAudioParsedTranscriptionOptions {
    var options: [String: JSONValue]
    var formOverrides: [String: JSONValue]
}

private struct FishAudioTranscriptionResponse {
    var text: String
    var displayLanguage: String?
    var languageCode: String?
    var duration: Double?
    var segments: [TranscriptionSegment]
}

private let fishAudioSpeechOptionKeys: Set<String> = [
    "referenceId",
    "sampleRate",
    "mp3Bitrate",
    "opusBitrate",
    "latency",
    "volume",
    "normalizeLoudness",
    "temperature",
    "topP",
    "chunkLength",
    "minChunkLength",
    "normalize",
    "maxNewTokens",
    "repetitionPenalty",
    "conditionOnPreviousChunks",
    "earlyStopThreshold",
    "features"
]

private let fishAudioTranscriptionOptionKeys: Set<String> = [
    "language",
    "ignoreTimestamps"
]

private let fishAudioSpeechOptionFieldNames: [String: String] = [
    "sampleRate": "sample_rate",
    "mp3Bitrate": "mp3_bitrate",
    "opusBitrate": "opus_bitrate",
    "latency": "latency",
    "temperature": "temperature",
    "topP": "top_p",
    "chunkLength": "chunk_length",
    "minChunkLength": "min_chunk_length",
    "normalize": "normalize",
    "maxNewTokens": "max_new_tokens",
    "repetitionPenalty": "repetition_penalty",
    "conditionOnPreviousChunks": "condition_on_previous_chunks",
    "earlyStopThreshold": "early_stop_threshold",
    "features": "features"
]

private func fishAudioSpeechOptions(
    from request: SpeechRequest
) throws -> FishAudioParsedOptions {
    let parsed = try fishAudioOptions(
        extraBody: request.extraBody,
        providerOptions: request.providerOptions,
        optionKeys: fishAudioSpeechOptionKeys,
        validate: validateFishAudioSpeechOptions
    )
    return FishAudioParsedOptions(
        options: parsed.options,
        bodyOverrides: parsed.overrides
    )
}

private func fishAudioTranscriptionOptions(
    from request: AudioTranscriptionRequest
) throws -> FishAudioParsedTranscriptionOptions {
    let parsed = try fishAudioOptions(
        extraBody: request.extraBody,
        providerOptions: request.providerOptions,
        optionKeys: fishAudioTranscriptionOptionKeys,
        validate: validateFishAudioTranscriptionOptions
    )
    return FishAudioParsedTranscriptionOptions(
        options: parsed.options,
        formOverrides: parsed.overrides
    )
}

private func fishAudioOptions(
    extraBody: [String: JSONValue],
    providerOptions: [String: JSONValue],
    optionKeys: Set<String>,
    validate: ([String: JSONValue], String) throws -> [String: JSONValue]
) throws -> (options: [String: JSONValue], overrides: [String: JSONValue]) {
    var overrides = extraBody
    var legacyOptions: [String: JSONValue] = [:]

    if let namespace = overrides.removeValue(forKey: "fishAudio") {
        if namespace != .null {
            guard let nested = namespace.objectValue else {
                throw AIError.invalidArgument(
                    argument: "extraBody.fishAudio",
                    message: "Fish Audio provider options must be an object."
                )
            }
            legacyOptions.merge(nested) { _, nestedValue in nestedValue }
        }
    }
    for key in optionKeys {
        if let value = overrides.removeValue(forKey: key) {
            legacyOptions[key] = value
        }
    }

    var options = try validate(legacyOptions, "extraBody.fishAudio")
    if let namespace = providerOptions["fishAudio"], namespace != .null {
        guard let nested = namespace.objectValue else {
            throw AIError.invalidArgument(
                argument: "providerOptions.fishAudio",
                message: "Fish Audio provider options must be an object."
            )
        }
        let validated = try validate(nested, "providerOptions.fishAudio")
        options.merge(validated) { _, providerValue in providerValue }
    }
    return (options, overrides)
}

private func validateFishAudioSpeechOptions(
    _ input: [String: JSONValue],
    _ prefix: String
) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in input where fishAudioSpeechOptionKeys.contains(key) {
        switch key {
        case "referenceId":
            guard value.stringValue != nil || fishAudioStringArray(value) != nil else {
                throw fishAudioInvalidOption(
                    prefix,
                    key,
                    "must be a string or an array of strings"
                )
            }
        case "sampleRate", "maxNewTokens":
            guard let number = fishAudioInteger(value), number > 0 else {
                throw fishAudioInvalidOption(prefix, key, "must be a positive integer")
            }
        case "mp3Bitrate":
            guard let number = fishAudioInteger(value), [64, 128, 192].contains(number) else {
                throw fishAudioInvalidOption(prefix, key, "must be 64, 128, or 192")
            }
        case "opusBitrate":
            guard let number = fishAudioInteger(value),
                  [-1000, 24_000, 32_000, 48_000, 64_000].contains(number) else {
                throw fishAudioInvalidOption(
                    prefix,
                    key,
                    "must be -1000, 24000, 32000, 48000, or 64000"
                )
            }
        case "latency":
            guard let latency = value.stringValue,
                  ["low", "normal", "balanced"].contains(latency) else {
                throw fishAudioInvalidOption(
                    prefix,
                    key,
                    "must be low, normal, or balanced"
                )
            }
        case "volume", "repetitionPenalty":
            guard fishAudioNumber(value) != nil else {
                throw fishAudioInvalidOption(prefix, key, "must be a number")
            }
        case "normalizeLoudness", "normalize", "conditionOnPreviousChunks":
            guard value.boolValue != nil else {
                throw fishAudioInvalidOption(prefix, key, "must be a boolean")
            }
        case "temperature", "topP", "earlyStopThreshold":
            guard let number = fishAudioNumber(value), (0...1).contains(number) else {
                throw fishAudioInvalidOption(prefix, key, "must be between 0 and 1")
            }
        case "chunkLength":
            guard let number = fishAudioInteger(value), (100...300).contains(number) else {
                throw fishAudioInvalidOption(prefix, key, "must be an integer between 100 and 300")
            }
        case "minChunkLength":
            guard let number = fishAudioInteger(value), (0...100).contains(number) else {
                throw fishAudioInvalidOption(prefix, key, "must be an integer between 0 and 100")
            }
        case "features":
            guard fishAudioStringArray(value) != nil else {
                throw fishAudioInvalidOption(prefix, key, "must be an array of strings")
            }
        default:
            break
        }
        output[key] = value
    }
    return output
}

private func validateFishAudioTranscriptionOptions(
    _ input: [String: JSONValue],
    _ prefix: String
) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in input where fishAudioTranscriptionOptionKeys.contains(key) {
        switch key {
        case "language":
            guard value.stringValue != nil else {
                throw fishAudioInvalidOption(prefix, key, "must be a string")
            }
        case "ignoreTimestamps":
            guard value.boolValue != nil else {
                throw fishAudioInvalidOption(prefix, key, "must be a boolean")
            }
        default:
            break
        }
        output[key] = value
    }
    return output
}

private func fishAudioSpeechFormat(
    _ requested: String?,
    warnings: inout [AIWarning]
) -> String {
    let supported = ["wav", "pcm", "mp3", "opus"]
    guard let requested else { return "mp3" }
    let normalized = requested.lowercased()
    guard supported.contains(normalized) else {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "outputFormat",
            message: "Fish Audio does not support the output format \"\(requested)\". Falling back to mp3. Supported formats are wav, pcm, mp3, opus."
        ))
        return "mp3"
    }
    return normalized
}

private func fishAudioApplySpeechOptions(
    _ options: [String: JSONValue],
    format: String,
    body: inout [String: JSONValue],
    warnings: inout [AIWarning]
) {
    if let mp3Bitrate = options["mp3Bitrate"] {
        if format == "mp3" {
            body["mp3_bitrate"] = mp3Bitrate
        } else {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "providerOptions.fishAudio.mp3Bitrate",
                message: "mp3Bitrate only applies to mp3 output. The option was ignored for \(format) output."
            ))
        }
    }
    if let opusBitrate = options["opusBitrate"] {
        if format == "opus" {
            body["opus_bitrate"] = opusBitrate
        } else {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "providerOptions.fishAudio.opusBitrate",
                message: "opusBitrate only applies to opus output. The option was ignored for \(format) output."
            ))
        }
    }
    for (option, field) in fishAudioSpeechOptionFieldNames
        where option != "mp3Bitrate" && option != "opusBitrate" {
        if let value = options[option] {
            body[field] = value
        }
    }
}

private func parseFishAudioTranscriptionResponse(
    _ raw: JSONValue
) throws -> FishAudioTranscriptionResponse {
    guard let object = raw.objectValue,
          let text = object["text"]?.stringValue,
          fishAudioOptionalString(object["language"]),
          fishAudioOptionalString(object["language_code"]),
          fishAudioOptionalNumber(object["duration"]) else {
        throw AIError.invalidResponse(
            provider: "fish-audio.transcription",
            message: "Fish Audio transcription response is invalid."
        )
    }

    var segments: [TranscriptionSegment] = []
    if let rawSegments = object["segments"], rawSegments != .null {
        guard let values = rawSegments.arrayValue else {
            throw AIError.invalidResponse(
                provider: "fish-audio.transcription",
                message: "Fish Audio transcription response segments are invalid."
            )
        }
        segments = try values.enumerated().map { index, value in
            guard let segment = value.objectValue,
                  let text = segment["text"]?.stringValue,
                  let start = segment["start"]?.doubleValue,
                  let end = segment["end"]?.doubleValue else {
                throw AIError.invalidResponse(
                    provider: "fish-audio.transcription",
                    message: "Fish Audio transcription response segments[\(index)] is invalid."
                )
            }
            return TranscriptionSegment(
                text: text,
                startSecond: start,
                endSecond: end
            )
        }
    }

    return FishAudioTranscriptionResponse(
        text: text,
        displayLanguage: object["language"]?.stringValue,
        languageCode: object["language_code"]?.stringValue,
        duration: object["duration"]?.doubleValue,
        segments: segments
    )
}

private func appendFishAudioMultipartField(
    name: String,
    value: JSONValue,
    form: inout MultipartFormData
) {
    if case let .array(values) = value {
        for item in values {
            if let scalar = jsonScalarString(item) {
                form.appendField(name: name, value: scalar)
            }
        }
    } else if let scalar = jsonScalarString(value) {
        form.appendField(name: name, value: scalar)
    }
}

private func fishAudioInvalidOption(
    _ prefix: String,
    _ key: String,
    _ requirement: String
) -> AIError {
    AIError.invalidArgument(
        argument: "\(prefix).\(key)",
        message: "Fish Audio \(key) \(requirement)."
    )
}

private func fishAudioNumber(_ value: JSONValue) -> Double? {
    guard let number = value.doubleValue, number.isFinite else { return nil }
    return number
}

private func fishAudioInteger(_ value: JSONValue) -> Int? {
    guard let number = fishAudioNumber(value),
          number.rounded() == number,
          number >= Double(Int.min),
          number <= Double(Int.max) else {
        return nil
    }
    return Int(number)
}

private func fishAudioStringArray(_ value: JSONValue) -> [String]? {
    guard let values = value.arrayValue else { return nil }
    let strings = values.compactMap(\.stringValue)
    return strings.count == values.count ? strings : nil
}

private func fishAudioOptionalString(_ value: JSONValue?) -> Bool {
    value == nil || value == .null || value?.stringValue != nil
}

private func fishAudioOptionalNumber(_ value: JSONValue?) -> Bool {
    value == nil || value == .null || value?.doubleValue != nil
}
