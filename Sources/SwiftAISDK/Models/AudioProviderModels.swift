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
        let options = deepgramProviderOptions(from: request.extraBody)
        var query: [String: String] = [
            "model": modelID,
            "diarize": "true"
        ]
        if let language = request.language { query["language"] = language }
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
            throw httpStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        let text = raw["results"]?["channels"]?[0]?["alternatives"]?[0]?["transcript"]?.stringValue ?? ""
        return TranscriptionResult(text: text, rawValue: raw)
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
        let options = deepgramProviderOptions(from: request.extraBody)
        var query = deepgramSpeechQuery(for: request.format)
        query["model"] = modelID
        query = deepgramSpeechOptions(from: options, current: query)
        query["model"] = modelID

        let response = try await config.transport.send(config.request(
            path: "/v1/speak?\(queryString(query))",
            modelID: modelID,
            body: .object(["text": .string(request.text)]),
            headers: request.headers
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        return SpeechResult(audio: response.body, contentType: response.headers.contentType)
    }
}

public final class LMNTSpeechModel: SpeechModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = "lmnt.speech"
        self.modelID = modelID
        self.config = config
    }

    public func speak(_ request: SpeechRequest) async throws -> SpeechResult {
        let options = lmntProviderOptions(from: request.extraBody)
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "text": .string(request.text),
            "voice": .string(request.voice ?? "ava"),
            "response_format": .string(lmntResponseFormat(request.format))
        ]
        body.merge(lmntSpeechOptions(from: options)) { _, new in new }

        let response = try await config.transport.send(config.request(
            path: "/v1/ai/speech/bytes",
            modelID: modelID,
            body: .object(body),
            headers: request.headers
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        return SpeechResult(audio: response.body, contentType: response.headers.contentType)
    }
}

public final class HumeSpeechModel: SpeechModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = "hume.speech"
        self.modelID = modelID
        self.config = config
    }

    public func speak(_ request: SpeechRequest) async throws -> SpeechResult {
        let options = humeProviderOptions(from: request.extraBody)
        let voice = request.voice ?? "d8ab67c6-953d-4bd8-9370-8fa53a0f1453"
        var utterance: [String: JSONValue] = [
            "text": .string(request.text),
            "voice": .object([
                "id": .string(voice),
                "provider": .string("HUME_AI")
            ])
        ]
        if let speed = options["speed"] {
            utterance["speed"] = speed
        }
        if let description = options["description"] ?? options["instructions"] {
            utterance["description"] = description
        }
        var body: [String: JSONValue] = [
            "utterances": .array([.object(utterance)]),
            "format": .object(["type": .string(humeFormat(request.format))])
        ]
        body.merge(humeSpeechOptions(from: options)) { _, new in new }

        let response = try await config.transport.send(config.request(
            path: "/v0/tts/file",
            modelID: modelID,
            body: .object(body),
            headers: request.headers
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        return SpeechResult(audio: response.body, contentType: response.headers.contentType)
    }
}

public final class ElevenLabsSpeechModel: SpeechModel, @unchecked Sendable {
    public let providerID = "elevenlabs.speech"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func speak(_ request: SpeechRequest) async throws -> SpeechResult {
        let options = elevenLabsProviderOptions(from: request.extraBody)
        let voice = request.voice ?? "21m00Tcm4TlvDq8ikWAM"
        var query: [String: String] = [
            "output_format": elevenLabsOutputFormat(request.format)
        ]
        if let enableLogging = options["enableLogging"]?.boolValue ?? options["enable_logging"]?.boolValue {
            query["enable_logging"] = String(enableLogging)
        }

        var body: [String: JSONValue] = [
            "text": .string(request.text),
            "model_id": .string(modelID)
        ]
        if let language = options["languageCode"]?.stringValue ?? options["language_code"]?.stringValue {
            body["language_code"] = .string(language)
        }
        var voiceSettings: [String: JSONValue] = [:]
        if let speed = options["speed"] {
            voiceSettings["speed"] = speed
        }
        if let voiceSettingsValue = options["voiceSettings"] ?? options["voice_settings"],
           let mapped = elevenLabsVoiceSettings(voiceSettingsValue).objectValue {
            voiceSettings.merge(mapped) { _, new in new }
        }
        if !voiceSettings.isEmpty {
            body["voice_settings"] = .object(voiceSettings)
        }
        for (key, value) in options {
            switch key {
            case "languageCode", "language_code", "voiceSettings", "voice_settings", "enableLogging", "enable_logging", "speed":
                continue
            case "pronunciationDictionaryLocators":
                body["pronunciation_dictionary_locators"] = elevenLabsPronunciationLocators(value)
            case "previousText":
                body["previous_text"] = value
            case "nextText":
                body["next_text"] = value
            case "previousRequestIds":
                body["previous_request_ids"] = value
            case "nextRequestIds":
                body["next_request_ids"] = value
            case "applyTextNormalization":
                body["apply_text_normalization"] = value
            case "applyLanguageTextNormalization":
                body["apply_language_text_normalization"] = value
            default:
                body[key] = value
            }
        }

        let response = try await config.transport.send(config.request(
            path: "/v1/text-to-speech/\(voice)?\(queryString(query))",
            modelID: modelID,
            body: .object(body),
            headers: request.headers
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        return SpeechResult(audio: response.body, contentType: response.headers.contentType)
    }
}

public final class ElevenLabsTranscriptionModel: TranscriptionModel, @unchecked Sendable {
    public let providerID = "elevenlabs.transcription"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        let options = elevenLabsProviderOptions(from: request.extraBody)
        var form = MultipartFormData()
        form.appendField(name: "model_id", value: modelID)
        form.appendFile(name: "file", fileName: request.fileName, mimeType: request.mimeType, data: request.audio)
        form.appendField(name: "diarize", value: String(options["diarize"]?.boolValue ?? true))
        if let language = request.language ?? options["languageCode"]?.stringValue ?? options["language_code"]?.stringValue {
            form.appendField(name: "language_code", value: language)
        }
        for (key, value) in options {
            guard let scalar = jsonScalarString(value) else { continue }
            switch key {
            case "languageCode", "language_code", "diarize":
                continue
            case "tagAudioEvents":
                form.appendField(name: "tag_audio_events", value: scalar)
            case "numSpeakers":
                form.appendField(name: "num_speakers", value: scalar)
            case "timestampsGranularity":
                form.appendField(name: "timestamps_granularity", value: scalar)
            case "fileFormat":
                form.appendField(name: "file_format", value: scalar)
            default:
                form.appendField(name: key, value: scalar)
            }
        }

        let response = try await config.transport.send(config.rawRequest(
            path: "/v1/speech-to-text",
            modelID: modelID,
            body: form.finalize(),
            contentType: "multipart/form-data; boundary=\(form.boundary)",
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        return TranscriptionResult(text: raw["text"]?.stringValue ?? "", rawValue: raw)
    }
}

public final class FalSpeechModel: SpeechModel, @unchecked Sendable {
    public let providerID = "fal.speech"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func speak(_ request: SpeechRequest) async throws -> SpeechResult {
        let options = falProviderOptions(from: request.extraBody)
        var body: [String: JSONValue] = [
            "text": .string(request.text),
            "output_format": .string(request.format == "hex" ? "hex" : "url")
        ]
        if let voice = request.voice { body["voice"] = .string(voice) }
        body.merge(options) { _, new in new }

        let raw = try await config.sendJSON(path: "/\(modelID)", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        guard let audioURL = raw["audio"]?["url"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Fal speech response did not contain audio.url.")
        }
        let audioResponse = try await config.transport.send(AIHTTPRequest(
            method: "GET",
            url: try validateDownloadURL(audioURL),
            headers: [:],
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(audioResponse.statusCode) else {
            throw httpStatusError(provider: providerID, response: audioResponse)
        }
        return SpeechResult(audio: audioResponse.body, contentType: audioResponse.headers.contentType)
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
        let options = falProviderOptions(from: request.extraBody)
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
        let raw = try await pollFalTranscription(modelPath: normalized, requestID: requestID, headers: request.headers, abortSignal: request.abortSignal)
        return TranscriptionResult(text: raw["text"]?.stringValue ?? "", rawValue: raw)
    }

    private func pollFalTranscription(modelPath: String, requestID: String, headers: [String: String], abortSignal: AIAbortSignal?) async throws -> JSONValue {
        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            let response = try await config.transport.send(AIHTTPRequest(
                method: "GET",
                url: try requireURL("https://queue.fal.run/fal-ai/\(modelPath)/requests/\(requestID)"),
                headers: config.headers.mergingHeaders(headers),
                abortSignal: abortSignal
            ))
            if (200..<300).contains(response.statusCode) {
                return try response.jsonValue()
            }
            if DispatchTime.now().uptimeNanoseconds - started > 60_000_000_000 {
                throw AIError.invalidResponse(provider: providerID, message: "Fal transcription request timed out.")
            }
            try await sleepWithAbortSignal(nanoseconds: 1_000_000_000, abortSignal: abortSignal)
        }
    }
}

public final class AssemblyAITranscriptionModel: TranscriptionModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = "assemblyai.transcription"
        self.modelID = modelID
        self.config = config
    }

    public func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        let options = assemblyAIProviderOptions(from: request.extraBody)
        let uploadResponse = try await config.transport.send(config.rawRequest(
            path: "/v2/upload",
            modelID: modelID,
            body: request.audio,
            contentType: "application/octet-stream",
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(uploadResponse.statusCode) else {
            throw httpStatusError(provider: providerID, response: uploadResponse)
        }
        let uploadRaw = try uploadResponse.jsonValue()
        guard let uploadURL = uploadRaw["upload_url"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "AssemblyAI upload response did not contain upload_url.")
        }

        var body: [String: JSONValue] = [
            "speech_model": .string(modelID),
            "audio_url": .string(uploadURL)
        ]
        if let language = request.language { body["language_code"] = .string(language) }
        body.merge(assemblyAITranscriptionOptions(from: options)) { _, new in new }

        let submitRaw = try await config.sendJSON(path: "/v2/transcript", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        guard let transcriptID = submitRaw["id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "AssemblyAI submit response did not contain id.")
        }

        let raw = try await pollAssemblyAITranscript(id: transcriptID, request: request)
        let status = raw["status"]?.stringValue
        if status == "error" {
            throw AIError.invalidResponse(provider: providerID, message: raw["error"]?.stringValue ?? "AssemblyAI transcription failed.")
        }
        return TranscriptionResult(text: raw["text"]?.stringValue ?? "", rawValue: raw)
    }

    private func pollAssemblyAITranscript(id: String, request: AudioTranscriptionRequest) async throws -> JSONValue {
        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            let response = try await config.transport.send(try getRequest(path: "/v2/transcript/\(id)", headers: request.headers, abortSignal: request.abortSignal))
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            switch raw["status"]?.stringValue {
            case "completed", "error":
                return raw
            default:
                if DispatchTime.now().uptimeNanoseconds - started > 60_000_000_000 {
                    throw AIError.invalidResponse(provider: providerID, message: "AssemblyAI transcription polling timed out.")
                }
                try await sleepWithAbortSignal(nanoseconds: 1_000_000_000, abortSignal: request.abortSignal)
            }
        }
    }

    private func getRequest(path: String, headers requestHeaders: [String: String], abortSignal: AIAbortSignal? = nil) throws -> AIHTTPRequest {
        AIHTTPRequest(
            method: "GET",
            url: try requireURL("\(withoutTrailingSlash(config.baseURL))\(path)"),
            headers: config.headers.mergingHeaders(requestHeaders),
            abortSignal: abortSignal
        )
    }
}

public final class RevAITranscriptionModel: TranscriptionModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = "revai.transcription"
        self.modelID = modelID
        self.config = config
    }

    public func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        let options = revAIProviderOptions(from: request.extraBody)
        var form = MultipartFormData()
        form.appendFile(name: "media", fileName: request.fileName, mimeType: request.mimeType, data: request.audio)
        var configBody: [String: JSONValue] = ["transcriber": .string(modelID)]
        if let language = request.language { configBody["language"] = .string(language) }
        configBody.merge(options) { _, new in new }
        form.appendField(name: "config", value: String(data: try encodeJSONBody(.object(configBody)), encoding: .utf8) ?? "{}")

        let submitResponse = try await config.transport.send(config.rawRequest(
            path: "/speechtotext/v1/jobs",
            modelID: modelID,
            body: form.finalize(),
            contentType: "multipart/form-data; boundary=\(form.boundary)",
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(submitResponse.statusCode) else {
            throw httpStatusError(provider: providerID, response: submitResponse)
        }
        var job = try submitResponse.jsonValue()
        guard let jobID = job["id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Rev.ai job response did not contain id.")
        }
        job = try await pollRevAIJob(id: jobID, initial: job, request: request)
        let transcriptResponse = try await config.transport.send(try getRequest(
            path: "/speechtotext/v1/jobs/\(jobID)/transcript",
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(transcriptResponse.statusCode) else {
            throw httpStatusError(provider: providerID, response: transcriptResponse)
        }
        let raw = try transcriptResponse.jsonValue()
        return TranscriptionResult(text: revAITranscriptText(from: raw), rawValue: raw)
    }

    private func pollRevAIJob(id: String, initial: JSONValue, request: AudioTranscriptionRequest) async throws -> JSONValue {
        var job = initial
        let started = DispatchTime.now().uptimeNanoseconds
        while job["status"]?.stringValue != "transcribed" {
            if job["status"]?.stringValue == "failed" {
                throw AIError.invalidResponse(provider: providerID, message: "Rev.ai transcription job failed.")
            }
            if DispatchTime.now().uptimeNanoseconds - started > 60_000_000_000 {
                throw AIError.invalidResponse(provider: providerID, message: "Rev.ai transcription polling timed out.")
            }
            try await sleepWithAbortSignal(nanoseconds: 1_000_000_000, abortSignal: request.abortSignal)
            let response = try await config.transport.send(try getRequest(
                path: "/speechtotext/v1/jobs/\(id)",
                headers: request.headers,
                abortSignal: request.abortSignal
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: providerID, response: response)
            }
            job = try response.jsonValue()
        }
        return job
    }

    private func getRequest(path: String, headers requestHeaders: [String: String], abortSignal: AIAbortSignal? = nil) throws -> AIHTTPRequest {
        AIHTTPRequest(
            method: "GET",
            url: try requireURL("\(withoutTrailingSlash(config.baseURL))\(path)"),
            headers: config.headers.mergingHeaders(requestHeaders),
            abortSignal: abortSignal
        )
    }
}

public final class GladiaTranscriptionModel: TranscriptionModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = "gladia.transcription"
        self.modelID = modelID
        self.config = config
    }

    public func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        let options = gladiaProviderOptions(from: request.extraBody)
        var form = MultipartFormData()
        form.appendFile(name: "audio", fileName: request.fileName, mimeType: request.mimeType, data: request.audio)
        let uploadResponse = try await config.transport.send(config.rawRequest(
            path: "/v2/upload",
            modelID: modelID,
            body: form.finalize(),
            contentType: "multipart/form-data; boundary=\(form.boundary)",
            headers: request.headers
        ))
        guard (200..<300).contains(uploadResponse.statusCode) else {
            throw httpStatusError(provider: providerID, response: uploadResponse)
        }
        let uploadRaw = try uploadResponse.jsonValue()
        guard let audioURL = uploadRaw["audio_url"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Gladia upload response did not contain audio_url.")
        }

        var body: [String: JSONValue] = ["audio_url": .string(audioURL)]
        if let language = request.language { body["language"] = .string(language) }
        body.merge(gladiaTranscriptionOptions(from: options)) { _, new in new }
        let initRaw = try await config.sendJSON(path: "/v2/pre-recorded", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal)
        guard let resultURL = initRaw["result_url"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Gladia initiation response did not contain result_url.")
        }

        let raw = try await pollGladiaResult(url: resultURL, request: request)
        guard raw["status"]?.stringValue != "error" else {
            throw AIError.invalidResponse(provider: providerID, message: "Gladia transcription failed.")
        }
        let text = raw["result"]?["transcription"]?["full_transcript"]?.stringValue ?? ""
        return TranscriptionResult(text: text, rawValue: raw)
    }

    private func pollGladiaResult(url: String, request: AudioTranscriptionRequest) async throws -> JSONValue {
        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            let response = try await config.transport.send(AIHTTPRequest(
                method: "GET",
                url: try validateDownloadURL(url),
                headers: config.headers.mergingHeaders(request.headers),
                abortSignal: request.abortSignal
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            switch raw["status"]?.stringValue {
            case "done", "error":
                return raw
            default:
                if DispatchTime.now().uptimeNanoseconds - started > 60_000_000_000 {
                    throw AIError.invalidResponse(provider: providerID, message: "Gladia transcription polling timed out.")
                }
                try await sleepWithAbortSignal(nanoseconds: 1_000_000_000, abortSignal: request.abortSignal)
            }
        }
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
        default:
            mappedKey = key
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

private func falProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "fal")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func assemblyAITranscriptionOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    mapKeys(extraBody, [
        "audioEndAt": "audio_end_at",
        "audioStartFrom": "audio_start_from",
        "autoChapters": "auto_chapters",
        "autoHighlights": "auto_highlights",
        "boostParam": "boost_param",
        "contentSafety": "content_safety",
        "contentSafetyConfidence": "content_safety_confidence",
        "customSpelling": "custom_spelling",
        "disfluencies": "disfluencies",
        "entityDetection": "entity_detection",
        "filterProfanity": "filter_profanity",
        "formatText": "format_text",
        "iabCategories": "iab_categories",
        "languageCode": "language_code",
        "languageConfidenceThreshold": "language_confidence_threshold",
        "languageDetection": "language_detection",
        "multichannel": "multichannel",
        "punctuate": "punctuate",
        "redactPii": "redact_pii",
        "redactPiiAudio": "redact_pii_audio",
        "redactPiiAudioQuality": "redact_pii_audio_quality",
        "redactPiiPolicies": "redact_pii_policies",
        "redactPiiSub": "redact_pii_sub",
        "sentimentAnalysis": "sentiment_analysis",
        "speakerLabels": "speaker_labels",
        "speakersExpected": "speakers_expected",
        "speechThreshold": "speech_threshold",
        "summarization": "summarization",
        "summaryModel": "summary_model",
        "summaryType": "summary_type",
        "webhookAuthHeaderName": "webhook_auth_header_name",
        "webhookAuthHeaderValue": "webhook_auth_header_value",
        "webhookUrl": "webhook_url",
        "wordBoost": "word_boost"
    ])
}

private func assemblyAIProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "assemblyai")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func revAIProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "revai")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func gladiaProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "gladia")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func gladiaTranscriptionOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in extraBody {
        switch key {
        case "contextPrompt":
            output["context_prompt"] = value
        case "customVocabulary":
            output["custom_vocabulary"] = value
        case "customVocabularyConfig":
            output["custom_vocabulary_config"] = gladiaNestedOptions(value, mapping: ["defaultIntensity": "default_intensity"])
        case "detectLanguage":
            output["detect_language"] = value
        case "enableCodeSwitching":
            output["enable_code_switching"] = value
        case "language":
            output["language"] = value
        case "codeSwitchingConfig":
            output["code_switching_config"] = gladiaNestedOptions(value, mapping: [:])
        case "callback":
            output["callback"] = value
        case "callbackConfig":
            output["callback_config"] = gladiaNestedOptions(value, mapping: [:])
        case "subtitles":
            output["subtitles"] = value
        case "subtitlesConfig":
            output["subtitles_config"] = gladiaNestedOptions(value, mapping: [
                "minimumDuration": "minimum_duration",
                "maximumDuration": "maximum_duration",
                "maximumCharactersPerRow": "maximum_characters_per_row",
                "maximumRowsPerCaption": "maximum_rows_per_caption"
            ])
        case "diarization":
            output["diarization"] = value
        case "diarizationConfig":
            output["diarization_config"] = gladiaNestedOptions(value, mapping: [
                "numberOfSpeakers": "number_of_speakers",
                "minSpeakers": "min_speakers",
                "maxSpeakers": "max_speakers"
            ])
        case "translation":
            output["translation"] = value
        case "translationConfig":
            output["translation_config"] = gladiaNestedOptions(value, mapping: [
                "targetLanguages": "target_languages",
                "matchOriginalUtterances": "match_original_utterances"
            ])
        case "summarization":
            output["summarization"] = value
        case "summarizationConfig":
            output["summarization_config"] = gladiaNestedOptions(value, mapping: [:])
        case "moderation":
            output["moderation"] = value
        case "namedEntityRecognition":
            output["named_entity_recognition"] = value
        case "chapterization":
            output["chapterization"] = value
        case "nameConsistency":
            output["name_consistency"] = value
        case "customSpelling":
            output["custom_spelling"] = value
        case "customSpellingConfig":
            output["custom_spelling_config"] = gladiaNestedOptions(value, mapping: ["spellingDictionary": "spelling_dictionary"])
        case "structuredDataExtraction":
            output["structured_data_extraction"] = value
        case "structuredDataExtractionConfig":
            output["structured_data_extraction_config"] = value
        case "sentimentAnalysis":
            output["sentiment_analysis"] = value
        case "audioToLlm":
            output["audio_to_llm"] = value
        case "audioToLlmConfig":
            output["audio_to_llm_config"] = value
        case "customMetadata":
            output["custom_metadata"] = value
        case "sentences":
            output["sentences"] = value
        case "displayMode":
            output["display_mode"] = value
        case "punctuationEnhanced":
            output["punctuation_enhanced"] = value
        default:
            output[key] = value
        }
    }
    return output
}

private func gladiaNestedOptions(_ value: JSONValue, mapping: [String: String]) -> JSONValue {
    guard let object = value.objectValue else { return value }
    return .object(mapKeys(object, mapping))
}

private func mapKeys(_ values: [String: JSONValue], _ mapping: [String: String]) -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in values {
        output[mapping[key] ?? key] = value
    }
    return output
}

private func lmntSpeechOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = mapKeys(extraBody, [
        "sampleRate": "sample_rate",
        "topP": "top_p"
    ])
    output.removeValue(forKey: "format")
    output.removeValue(forKey: "model")
    return output
}

private func lmntProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "lmnt")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func humeSpeechOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    output.removeValue(forKey: "speed")
    output.removeValue(forKey: "description")
    output.removeValue(forKey: "instructions")
    if let context = output.removeValue(forKey: "context") {
        output["context"] = humeContext(context)
    }
    return output
}

private func humeProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "hume")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func humeContext(_ value: JSONValue) -> JSONValue {
    guard let object = value.objectValue else { return value }
    if let generationID = object["generationId"] {
        return .object(["generation_id": generationID])
    }
    if let utterances = object["utterances"]?.arrayValue {
        return .object([
            "utterances": .array(utterances.map(humeContextUtterance))
        ])
    }
    return value
}

private func humeContextUtterance(_ value: JSONValue) -> JSONValue {
    guard let object = value.objectValue else { return value }
    return .object(mapKeys(object, ["trailingSilence": "trailing_silence"]))
}

private func deepgramSpeechOptions(from extraBody: [String: JSONValue], current: [String: String]) -> [String: String] {
    var query = current
    for (key, value) in extraBody {
        switch key {
        case "bitRate":
            if let scalar = deepgramQueryValue(value) { query["bit_rate"] = scalar }
        case "callbackMethod":
            if let scalar = deepgramQueryValue(value) { query["callback_method"] = scalar }
        case "mipOptOut":
            if let scalar = deepgramQueryValue(value) { query["mip_opt_out"] = scalar }
        case "sampleRate":
            if let scalar = deepgramQueryValue(value) { query["sample_rate"] = scalar }
        case "container":
            if let container = deepgramQueryValue(value)?.lowercased() {
                query["container"] = container
                if query["encoding"] == nil {
                    if container == "wav" || container == "none" {
                        query["encoding"] = "linear16"
                    } else if container == "ogg" {
                        query["encoding"] = "opus"
                    }
                }
            }
        case "encoding":
            if let encoding = deepgramQueryValue(value)?.lowercased() {
                query["encoding"] = encoding
                if encoding == "opus" {
                    query["container"] = "ogg"
                    query.removeValue(forKey: "sample_rate")
                } else if encoding == "mp3" || encoding == "flac" || encoding == "aac" {
                    query.removeValue(forKey: "container")
                    if encoding == "mp3" || encoding == "aac" {
                        query.removeValue(forKey: "sample_rate")
                    }
                } else if ["linear16", "mulaw", "alaw"].contains(encoding), query["container"] == nil {
                    query["container"] = "wav"
                }
            }
        case "tag":
            if let scalar = deepgramQueryValue(value) { query["tag"] = scalar }
        default:
            if let scalar = deepgramQueryValue(value) { query[key] = scalar }
        }
    }
    switch query["encoding"]?.lowercased() {
    case "mp3", "opus", "aac":
        query.removeValue(forKey: "sample_rate")
    case "linear16", "mulaw", "alaw", "flac":
        query.removeValue(forKey: "bit_rate")
    default:
        break
    }
    if query["encoding"]?.lowercased() == "opus" {
        query["container"] = "ogg"
    }
    return query.filter { $0.key != "model" }
}

private func deepgramQueryValue(_ value: JSONValue) -> String? {
    if let scalar = jsonScalarString(value) {
        return scalar
    }
    return value.arrayValue?.compactMap(jsonScalarString).joined(separator: ",")
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
        guard parts.count >= 2, let sampleRate = Int(parts[1]) else { return [:] }
        let first = parts[0]
        if first == "wav" {
            return ["encoding": "linear16", "container": "wav", "sample_rate": String(sampleRate)]
        }
        if first == "ogg" {
            return ["encoding": "opus", "container": "ogg"]
        }
        if ["linear16", "mulaw", "alaw"].contains(first) {
            return ["encoding": first, "container": "wav", "sample_rate": String(sampleRate)]
        }
        if first == "opus" {
            return ["encoding": "opus", "container": "ogg"]
        }
        if ["mp3", "aac"].contains(first) {
            return ["encoding": first]
        }
        return ["encoding": first, "sample_rate": String(sampleRate)]
    }
}

private func revAITranscriptText(from raw: JSONValue) -> String {
    raw["monologues"]?.arrayValue?.map { monologue in
        monologue["elements"]?.arrayValue?.compactMap { $0["value"]?.stringValue }.joined() ?? ""
    }.joined(separator: " ") ?? ""
}

private func lmntResponseFormat(_ outputFormat: String?) -> String {
    guard let outputFormat, ["mp3", "aac", "mulaw", "raw", "wav"].contains(outputFormat.lowercased()) else {
        return "mp3"
    }
    return outputFormat.lowercased()
}

private func humeFormat(_ outputFormat: String?) -> String {
    guard let outputFormat, ["mp3", "pcm", "wav"].contains(outputFormat.lowercased()) else {
        return "mp3"
    }
    return outputFormat.lowercased()
}

private func elevenLabsOutputFormat(_ outputFormat: String?) -> String {
    switch outputFormat?.lowercased() {
    case "mp3":
        return "mp3_44100_128"
    case "mp3_32":
        return "mp3_44100_32"
    case "mp3_64":
        return "mp3_44100_64"
    case "mp3_96":
        return "mp3_44100_96"
    case "mp3_128":
        return "mp3_44100_128"
    case "mp3_192":
        return "mp3_44100_192"
    case "pcm":
        return "pcm_44100"
    case "ulaw":
        return "ulaw_8000"
    case let value?:
        return value
    case nil:
        return "mp3_44100_128"
    }
}

private func elevenLabsProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "elevenlabs")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func elevenLabsVoiceSettings(_ value: JSONValue) -> JSONValue {
    guard let settings = value.objectValue else { return value }
    var mapped: [String: JSONValue] = [:]
    for (key, item) in settings {
        switch key {
        case "similarityBoost":
            mapped["similarity_boost"] = item
        case "useSpeakerBoost":
            mapped["use_speaker_boost"] = item
        default:
            mapped[key] = item
        }
    }
    return .object(mapped)
}

private func elevenLabsPronunciationLocators(_ value: JSONValue) -> JSONValue {
    guard let array = value.arrayValue else { return value }
    return .array(array.map { item in
        guard let object = item.objectValue else { return item }
        var mapped: [String: JSONValue] = [:]
        for (key, value) in object {
            switch key {
            case "pronunciationDictionaryId":
                mapped["pronunciation_dictionary_id"] = value
            case "versionId":
                mapped["version_id"] = value
            default:
                mapped[key] = value
            }
        }
        return .object(mapped)
    })
}

private func queryString(_ values: [String: String]) -> String {
    values
        .sorted { $0.key < $1.key }
        .map { "\(urlQueryEncode($0.key))=\(urlQueryEncode($0.value))" }
        .joined(separator: "&")
}

private func urlQueryEncode(_ value: String) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: ":#[]@!$&'()*+,;=/")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

private extension Dictionary where Key == String, Value == String {
    var contentType: String? {
        first { $0.key.caseInsensitiveCompare("content-type") == .orderedSame }?.value
    }
}
