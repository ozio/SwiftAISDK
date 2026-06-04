import Foundation

public final class DeepgramTranscriptionModel: TranscriptionModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = "deepgram.transcription"
        self.modelID = modelID
        self.config = config
    }

    public func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        let options = try deepgramProviderOptions(from: request)
        var query: [String: String] = [
            "model": modelID,
            "diarize": "true"
        ]
        query.merge(deepgramTranscriptionQuery(from: options)) { _, new in new }

        let response = try await config.transport.send(config.rawRequest(
            path: "/v1/listen?\(queryString(query))",
            modelID: modelID,
            body: request.audio,
            contentType: request.mimeType,
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw audioProviderHTTPStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        let text = raw["results"]?["channels"]?[0]?["alternatives"]?[0]?["transcript"]?.stringValue ?? ""
        let segments = deepgramTranscriptionSegments(from: raw)
        return TranscriptionResult(
            text: text,
            rawValue: raw,
            segments: segments,
            language: raw["results"]?["channels"]?[0]?["detected_language"]?.stringValue,
            durationInSeconds: raw["metadata"]?["duration"]?.doubleValue ?? transcriptionDuration(from: segments),
            responseMetadata: aiResponseMetadata(from: raw, response: response, modelID: modelID)
        )
    }
}

public final class DeepgramSpeechModel: SpeechModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = "deepgram.speech"
        self.modelID = modelID
        self.config = config
    }

    public func speak(_ request: SpeechRequest) async throws -> SpeechResult {
        let options = try deepgramProviderOptions(from: request)
        var query = deepgramSpeechQuery(for: request.format)
        query["model"] = modelID
        let prepared = deepgramSpeechOptions(from: options, current: query, request: request, modelID: modelID)
        query = prepared.query
        query["model"] = modelID

        let response = try await config.transport.send(config.request(
            path: "/v1/speak?\(queryString(query))",
            modelID: modelID,
            body: .object(["text": .string(request.text)]),
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
            requestMetadata: AIRequestMetadata(body: .object(["text": .string(request.text)]), headers: request.headers),
            responseMetadata: aiResponseMetadata(response: response, modelID: modelID)
        )
    }
}

private func deepgramTranscriptionQuery(from extraBody: [String: JSONValue]) -> [String: String] {
    var query: [String: String] = [:]
    for (key, value) in extraBody {
        let mappedKey: String
        switch key {
        case "detectEntities":
            mappedKey = "detect_entities"
        case "detectLanguage":
            mappedKey = "detect_language"
        case "fillerWords":
            mappedKey = "filler_words"
        case "smartFormat":
            mappedKey = "smart_format"
        case "uttSplit":
            mappedKey = "utt_split"
        case "language", "punctuate", "paragraphs", "summarize", "topics", "intents", "sentiment", "redact", "replace", "search", "keyterm", "diarize", "utterances":
            mappedKey = key
        default:
            continue
        }
        if let scalar = deepgramQueryValue(value) {
            query[mappedKey] = scalar
        }
    }
    return query
}

private func deepgramProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "deepgram")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func deepgramProviderOptions(from request: AudioTranscriptionRequest) throws -> [String: JSONValue] {
    try deepgramProviderOptions(
        extraBody: request.extraBody,
        providerOptions: request.providerOptions,
        supportedProviderOptionKeys: deepgramTranscriptionProviderOptionKeys,
        validateProviderOptions: deepgramValidateTranscriptionProviderOptions
    )
}

private func deepgramProviderOptions(from request: SpeechRequest) throws -> [String: JSONValue] {
    try deepgramProviderOptions(
        extraBody: request.extraBody,
        providerOptions: request.providerOptions,
        supportedProviderOptionKeys: deepgramSpeechProviderOptionKeys,
        validateProviderOptions: deepgramValidateSpeechProviderOptions
    )
}

private func deepgramProviderOptions(extraBody: [String: JSONValue], providerOptions: [String: JSONValue], supportedProviderOptionKeys: Set<String>, validateProviderOptions: ([String: JSONValue]) throws -> [String: JSONValue]) throws -> [String: JSONValue] {
    var output = deepgramProviderOptions(from: extraBody)
    if let deepgramOptions = providerOptions["deepgram"] {
        guard deepgramOptions != .null else { return output }
        guard let nested = deepgramOptions.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.deepgram", message: "Deepgram provider options must be an object.")
        }
        let validated = try validateProviderOptions(nested)
        output.merge(validated.filter { supportedProviderOptionKeys.contains($0.key) }) { _, providerValue in providerValue }
    }
    return output
}

private func deepgramValidateTranscriptionProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where deepgramTranscriptionProviderOptionKeys.contains(key) {
        if value == .null {
            output[key] = value
            continue
        }
        switch key {
        case "language", "replace", "search", "keyterm":
            try deepgramRequireString(value, argument: "providerOptions.deepgram.\(key)", message: "Deepgram \(key) must be a string.")
        case "detectLanguage", "smartFormat", "punctuate", "paragraphs", "topics", "intents", "sentiment", "detectEntities", "diarize", "utterances", "fillerWords":
            try deepgramRequireBoolean(value, argument: "providerOptions.deepgram.\(key)", message: "Deepgram \(key) must be a boolean.")
        case "summarize":
            guard value == .bool(false) || value.stringValue == "v2" else {
                throw AIError.invalidArgument(argument: "providerOptions.deepgram.summarize", message: "Deepgram summarize must be v2 or false.")
            }
        case "redact":
            try deepgramRequireStringOrStringArray(value, argument: "providerOptions.deepgram.redact", message: "Deepgram redact must be a string or an array of strings.")
        case "uttSplit":
            guard value.doubleValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.deepgram.uttSplit", message: "Deepgram uttSplit must be a number.")
            }
        default:
            break
        }
        output[key] = value
    }
    return output
}

private func deepgramValidateSpeechProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where deepgramSpeechProviderOptionKeys.contains(key) {
        if value == .null {
            output[key] = value
            continue
        }
        switch key {
        case "bitRate":
            guard value.doubleValue != nil || value.stringValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.deepgram.bitRate", message: "Deepgram bitRate must be a number or string.")
            }
        case "container", "encoding":
            try deepgramRequireString(value, argument: "providerOptions.deepgram.\(key)", message: "Deepgram \(key) must be a string.")
        case "sampleRate":
            guard value.doubleValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.deepgram.sampleRate", message: "Deepgram sampleRate must be a number.")
            }
        case "callback":
            guard let callback = value.stringValue, deepgramIsURL(callback) else {
                throw AIError.invalidArgument(argument: "providerOptions.deepgram.callback", message: "Deepgram callback must be a valid URL.")
            }
        case "callbackMethod":
            guard let method = value.stringValue, ["POST", "PUT"].contains(method) else {
                throw AIError.invalidArgument(argument: "providerOptions.deepgram.callbackMethod", message: "Deepgram callbackMethod must be POST or PUT.")
            }
        case "mipOptOut":
            try deepgramRequireBoolean(value, argument: "providerOptions.deepgram.mipOptOut", message: "Deepgram mipOptOut must be a boolean.")
        case "tag":
            try deepgramRequireStringOrStringArray(value, argument: "providerOptions.deepgram.tag", message: "Deepgram tag must be a string or an array of strings.")
        default:
            break
        }
        output[key] = value
    }
    return output
}

private let deepgramTranscriptionProviderOptionKeys: Set<String> = [
    "language",
    "detectLanguage",
    "smartFormat",
    "punctuate",
    "paragraphs",
    "summarize",
    "topics",
    "intents",
    "sentiment",
    "detectEntities",
    "redact",
    "replace",
    "search",
    "keyterm",
    "diarize",
    "utterances",
    "uttSplit",
    "fillerWords"
]

private let deepgramSpeechProviderOptionKeys: Set<String> = [
    "bitRate",
    "container",
    "encoding",
    "sampleRate",
    "callback",
    "callbackMethod",
    "mipOptOut",
    "tag"
]

private struct DeepgramPreparedSpeechOptions {
    var query: [String: String]
    var warnings: [AIWarning]
}

private func deepgramSpeechOptions(from extraBody: [String: JSONValue], current: [String: String], request: SpeechRequest, modelID: String) -> DeepgramPreparedSpeechOptions {
    var query = current
    var warnings: [AIWarning] = []
    for (key, value) in extraBody {
        switch key {
        case "bitRate":
            continue
        case "callbackMethod":
            if let scalar = deepgramQueryValue(value) { query["callback_method"] = scalar }
        case "mipOptOut":
            if let scalar = deepgramQueryValue(value) { query["mip_opt_out"] = scalar }
        case "sampleRate":
            continue
        case "container":
            continue
        case "encoding":
            continue
        case "tag":
            if let scalar = deepgramQueryValue(value) { query["tag"] = scalar }
        default:
            if let scalar = deepgramQueryValue(value) { query[key] = scalar }
        }
    }

    if let encodingValue = extraBody["encoding"],
       let encoding = deepgramQueryValue(encodingValue)?.lowercased() {
        query["encoding"] = encoding
        if let containerValue = extraBody["container"],
           let container = deepgramQueryValue(containerValue)?.lowercased() {
            deepgramApplyContainer(container, for: encoding, query: &query, warnings: &warnings)
        } else if ["mp3", "flac", "aac"].contains(encoding) {
            query.removeValue(forKey: "container")
        } else if ["linear16", "mulaw", "alaw"].contains(encoding), query["container"] == nil {
            query["container"] = "wav"
        } else if encoding == "opus" {
            query["container"] = "ogg"
        }

        if ["mp3", "opus", "aac"].contains(encoding) {
            query.removeValue(forKey: "sample_rate")
        }
        if ["linear16", "mulaw", "alaw", "flac"].contains(encoding) {
            query.removeValue(forKey: "bit_rate")
        }
    } else if let containerValue = extraBody["container"],
              let container = deepgramQueryValue(containerValue)?.lowercased() {
        let oldEncoding = query["encoding"]?.lowercased()
        var newEncoding: String?
        if container == "wav" {
            query["container"] = "wav"
            newEncoding = "linear16"
        } else if container == "ogg" {
            query["container"] = "ogg"
            newEncoding = "opus"
        } else if container == "none" {
            query["container"] = "none"
            newEncoding = "linear16"
        }
        if let newEncoding, newEncoding != oldEncoding {
            query["encoding"] = newEncoding
            if ["mp3", "opus", "aac"].contains(newEncoding) {
                query.removeValue(forKey: "sample_rate")
            }
            if ["linear16", "mulaw", "alaw", "flac"].contains(newEncoding) {
                query.removeValue(forKey: "bit_rate")
            }
        }
    }

    if let sampleRate = extraBody["sampleRate"]?.intValue {
        deepgramApplySampleRate(sampleRate, query: &query, warnings: &warnings)
    }
    if let bitRateValue = extraBody["bitRate"],
       let bitRate = deepgramQueryValue(bitRateValue) {
        deepgramApplyBitRate(bitRate, query: &query, warnings: &warnings)
    }

    if let voice = request.voice, voice != modelID {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "voice",
            message: "Deepgram TTS models embed the voice in the model ID. The voice parameter \"\(voice)\" was ignored. Use the model ID to select a voice (e.g., \"aura-2-helena-en\")."
        ))
    }
    if request.speed != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "speed",
            message: "Deepgram TTS REST API does not support speed adjustment. Speed parameter was ignored."
        ))
    }
    if let language = request.language {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "language",
            message: "Deepgram TTS models are language-specific via the model ID. Language parameter \"\(language)\" was ignored. Select a model with the appropriate language suffix (e.g., \"-en\" for English)."
        ))
    }
    if request.instructions != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "instructions",
            message: "Deepgram TTS REST API does not support instructions. Instructions parameter was ignored."
        ))
    }

    return DeepgramPreparedSpeechOptions(query: query.filter { $0.key != "model" }, warnings: warnings)
}

private func deepgramApplyContainer(_ container: String, for encoding: String, query: inout [String: String], warnings: inout [AIWarning]) {
    if ["linear16", "mulaw", "alaw"].contains(encoding) {
        guard container == "wav" || container == "none" else {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "providerOptions",
                message: "Encoding \"\(encoding)\" only supports containers \"wav\" or \"none\". Container \"\(container)\" was ignored."
            ))
            return
        }
        query["container"] = container
    } else if encoding == "opus" {
        query["container"] = "ogg"
    } else if ["mp3", "flac", "aac"].contains(encoding) {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "providerOptions",
            message: "Encoding \"\(encoding)\" does not support container parameter. Container \"\(container)\" was ignored."
        ))
        query.removeValue(forKey: "container")
    }
}

private func deepgramApplySampleRate(_ sampleRate: Int, query: inout [String: String], warnings: inout [AIWarning]) {
    let encoding = query["encoding"]?.lowercased() ?? ""
    if encoding == "linear16" {
        guard [8000, 16000, 24000, 32000, 48000].contains(sampleRate) else {
            warnings.append(AIWarning(type: "unsupported", feature: "providerOptions", message: "Encoding \"linear16\" only supports sample rates: 8000, 16000, 24000, 32000, 48000. Sample rate \(sampleRate) was ignored."))
            return
        }
        query["sample_rate"] = String(sampleRate)
    } else if encoding == "mulaw" || encoding == "alaw" {
        guard [8000, 16000].contains(sampleRate) else {
            warnings.append(AIWarning(type: "unsupported", feature: "providerOptions", message: "Encoding \"\(encoding)\" only supports sample rates: 8000, 16000. Sample rate \(sampleRate) was ignored."))
            return
        }
        query["sample_rate"] = String(sampleRate)
    } else if encoding == "flac" {
        guard [8000, 16000, 22050, 32000, 48000].contains(sampleRate) else {
            warnings.append(AIWarning(type: "unsupported", feature: "providerOptions", message: "Encoding \"flac\" only supports sample rates: 8000, 16000, 22050, 32000, 48000. Sample rate \(sampleRate) was ignored."))
            return
        }
        query["sample_rate"] = String(sampleRate)
    } else if ["mp3", "opus", "aac"].contains(encoding) {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "providerOptions",
            message: "Encoding \"\(encoding)\" has a fixed sample rate and does not support sample_rate parameter. Sample rate \(sampleRate) was ignored."
        ))
    } else {
        query["sample_rate"] = String(sampleRate)
    }
}

private func deepgramApplyBitRate(_ bitRate: String, query: inout [String: String], warnings: inout [AIWarning]) {
    let encoding = query["encoding"]?.lowercased() ?? ""
    let bitRateNumber = Int(bitRate) ?? 0
    if encoding == "mp3" {
        guard [32000, 48000].contains(bitRateNumber) else {
            warnings.append(AIWarning(type: "unsupported", feature: "providerOptions", message: "Encoding \"mp3\" only supports bit rates: 32000, 48000. Bit rate \(bitRate) was ignored."))
            return
        }
        query["bit_rate"] = bitRate
    } else if encoding == "opus" {
        guard bitRateNumber >= 4000 && bitRateNumber <= 650000 else {
            warnings.append(AIWarning(type: "unsupported", feature: "providerOptions", message: "Encoding \"opus\" supports bit rates between 4000 and 650000. Bit rate \(bitRate) was ignored."))
            return
        }
        query["bit_rate"] = bitRate
    } else if encoding == "aac" {
        guard bitRateNumber >= 4000 && bitRateNumber <= 192000 else {
            warnings.append(AIWarning(type: "unsupported", feature: "providerOptions", message: "Encoding \"aac\" supports bit rates between 4000 and 192000. Bit rate \(bitRate) was ignored."))
            return
        }
        query["bit_rate"] = bitRate
    } else if ["linear16", "mulaw", "alaw", "flac"].contains(encoding) {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "providerOptions",
            message: "Encoding \"\(encoding)\" does not support bit_rate parameter. Bit rate \(bitRate) was ignored."
        ))
    } else {
        query["bit_rate"] = bitRate
    }
}

private func deepgramQueryValue(_ value: JSONValue) -> String? {
    if let scalar = jsonScalarString(value) {
        return scalar
    }
    return value.arrayValue?.compactMap(jsonScalarString).joined(separator: ",")
}

private func deepgramRequireString(_ value: JSONValue, argument: String, message: String) throws {
    guard value.stringValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private func deepgramRequireBoolean(_ value: JSONValue, argument: String, message: String) throws {
    guard value.boolValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private func deepgramRequireStringOrStringArray(_ value: JSONValue, argument: String, message: String) throws {
    if value.stringValue != nil { return }
    guard let array = value.arrayValue else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
    for item in array where item.stringValue == nil {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private func deepgramIsURL(_ value: String) -> Bool {
    guard let components = URLComponents(string: value) else { return false }
    return components.scheme != nil && components.host != nil
}

private func deepgramSpeechQuery(for outputFormat: String?) -> [String: String] {
    let lowercased = (outputFormat ?? "mp3").lowercased()
    switch lowercased {
    case "mp3":
        return ["encoding": "mp3"]
    case "wav", "linear16":
        return ["encoding": "linear16", "container": "wav"]
    case "mulaw":
        return ["encoding": "mulaw", "container": "wav"]
    case "alaw":
        return ["encoding": "alaw", "container": "wav"]
    case "opus", "ogg":
        return ["encoding": "opus", "container": "ogg"]
    case "flac":
        return ["encoding": "flac"]
    case "aac":
        return ["encoding": "aac"]
    case "pcm":
        return ["encoding": "linear16", "container": "none"]
    default:
        let parts = lowercased.split(separator: "_").map(String.init)
        guard parts.count >= 2 else { return [:] }
        let first = parts[0]
        if first == "wav" {
            guard let sampleRate = Int(parts[1]) else { return ["encoding": "linear16", "container": "wav"] }
            return ["encoding": "linear16", "container": "wav", "sample_rate": String(sampleRate)]
        }
        if first == "ogg" {
            guard let sampleRate = Int(parts[1]) else { return ["encoding": "opus", "container": "ogg"] }
            return ["encoding": "opus", "container": "ogg", "sample_rate": String(sampleRate)]
        }
        if first == "linear16" {
            var query = ["encoding": "linear16", "container": "wav"]
            if let sampleRate = Int(parts[1]), [8000, 16000, 24000, 32000, 48000].contains(sampleRate) {
                query["sample_rate"] = String(sampleRate)
            }
            return query
        }
        if first == "mulaw" || first == "alaw" {
            var query = ["encoding": first, "container": "wav"]
            if let sampleRate = Int(parts[1]), [8000, 16000].contains(sampleRate) {
                query["sample_rate"] = String(sampleRate)
            }
            return query
        }
        if first == "flac" {
            var query = ["encoding": "flac"]
            if let sampleRate = Int(parts[1]), [8000, 16000, 22050, 32000, 48000].contains(sampleRate) {
                query["sample_rate"] = String(sampleRate)
            }
            return query
        }
        if first == "opus" {
            return ["encoding": "opus", "container": "ogg"]
        }
        if ["mp3", "aac"].contains(first) {
            return ["encoding": first]
        }
        return [:]
    }
}

