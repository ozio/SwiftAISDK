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
        let options = deepgramProviderOptions(from: request)
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
        let options = deepgramProviderOptions(from: request)
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
            throw httpStatusError(provider: providerID, response: response)
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
        let options = lmntProviderOptions(from: request)
        let warnings = lmntSpeechWarnings(for: request)
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
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        return SpeechResult(
            audio: response.body,
            contentType: response.headers.contentType,
            warnings: warnings,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(response: response, modelID: modelID)
        )
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
        let options = humeProviderOptions(from: request)
        let warnings = humeSpeechWarnings(for: request)
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
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        return SpeechResult(
            audio: response.body,
            contentType: response.headers.contentType,
            warnings: warnings,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(response: response, modelID: modelID)
        )
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
        let options = elevenLabsProviderOptions(from: request)
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
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        return SpeechResult(
            audio: response.body,
            contentType: response.headers.contentType,
            requestMetadata: AIRequestMetadata(body: .object(body), headers: request.headers),
            responseMetadata: aiResponseMetadata(response: response, modelID: modelID)
        )
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
        let options = elevenLabsProviderOptions(from: request)
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
        let segments = elevenLabsTranscriptionSegments(from: raw)
        return TranscriptionResult(
            text: raw["text"]?.stringValue ?? "",
            rawValue: raw,
            segments: segments,
            language: raw["language_code"]?.stringValue,
            durationInSeconds: transcriptionDuration(from: segments),
            responseMetadata: aiResponseMetadata(from: raw, response: response, modelID: modelID)
        )
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
        let options = falProviderOptions(from: request)
        let outputFormat = request.format == "hex" ? "hex" : "url"
        let warnings = falSpeechWarnings(for: request)
        var body: [String: JSONValue] = [
            "text": .string(request.text),
            "output_format": .string(outputFormat)
        ]
        if let voice = request.voice { body["voice"] = .string(voice) }
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
        let options = falProviderOptions(from: request)
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
        let options = assemblyAIProviderOptions(from: request)
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

        let finalResponse = try await pollAssemblyAITranscriptResponse(id: transcriptID, request: request)
        let raw = finalResponse.json
        let status = raw["status"]?.stringValue
        if status == "error" {
            throw AIError.invalidResponse(provider: providerID, message: raw["error"]?.stringValue ?? "AssemblyAI transcription failed.")
        }
        let segments = assemblyAITranscriptionSegments(from: raw)
        return TranscriptionResult(
            text: raw["text"]?.stringValue ?? "",
            rawValue: raw,
            segments: segments,
            language: raw["language_code"]?.stringValue,
            durationInSeconds: raw["audio_duration"]?.doubleValue ?? transcriptionDuration(from: segments),
            responseMetadata: aiResponseMetadata(from: raw, response: finalResponse.response, modelID: modelID)
        )
    }

    private func pollAssemblyAITranscriptResponse(id: String, request: AudioTranscriptionRequest) async throws -> (json: JSONValue, response: AIHTTPResponse) {
        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            let response = try await config.transport.send(try getRequest(path: "/v2/transcript/\(id)", headers: request.headers, abortSignal: request.abortSignal))
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            switch raw["status"]?.stringValue {
            case "completed", "error":
                return (raw, response)
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
        let options = revAIProviderOptions(from: request)
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
        let segments = revAITranscriptionSegments(from: raw)
        return TranscriptionResult(
            text: revAITranscriptText(from: raw),
            rawValue: raw,
            segments: segments,
            language: job["language"]?.stringValue,
            durationInSeconds: transcriptionDuration(from: segments),
            responseMetadata: aiResponseMetadata(from: raw, response: transcriptResponse, modelID: modelID)
        )
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
        let options = gladiaProviderOptions(from: request)
        var form = MultipartFormData()
        form.appendFile(name: "audio", fileName: "audio.\(mediaTypeToExtension(request.mimeType))", mimeType: request.mimeType, data: request.audio)
        let uploadResponse = try await config.transport.send(config.rawRequest(
            path: "/v2/upload",
            modelID: modelID,
            body: form.finalize(),
            contentType: "multipart/form-data; boundary=\(form.boundary)",
            headers: request.headers,
            abortSignal: request.abortSignal
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

        let finalResponse = try await pollGladiaResultResponse(url: resultURL, request: request)
        let raw = finalResponse.json
        guard raw["status"]?.stringValue != "error" else {
            throw AIError.invalidResponse(provider: providerID, message: "Gladia transcription failed.")
        }
        let text = raw["result"]?["transcription"]?["full_transcript"]?.stringValue ?? ""
        let segments = gladiaTranscriptionSegments(from: raw)
        return TranscriptionResult(
            text: text,
            rawValue: raw,
            segments: segments,
            language: raw["result"]?["transcription"]?["languages"]?[0]?.stringValue,
            durationInSeconds: raw["result"]?["metadata"]?["audio_duration"]?.doubleValue ?? transcriptionDuration(from: segments),
            responseMetadata: aiResponseMetadata(from: raw, response: finalResponse.response, modelID: modelID)
        )
    }

    private func pollGladiaResultResponse(url: String, request: AudioTranscriptionRequest) async throws -> (json: JSONValue, response: AIHTTPResponse) {
        let started = DispatchTime.now().uptimeNanoseconds
        while true {
            let response = try await downloadURL(url, transport: config.transport, headers: config.headers.mergingHeaders(request.headers), abortSignal: request.abortSignal)
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            switch raw["status"]?.stringValue {
            case "done", "error":
                return (raw, response)
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

private func deepgramProviderOptions(from request: AudioTranscriptionRequest) -> [String: JSONValue] {
    deepgramProviderOptions(extraBody: request.extraBody, providerOptions: request.providerOptions)
}

private func deepgramProviderOptions(from request: SpeechRequest) -> [String: JSONValue] {
    deepgramProviderOptions(extraBody: request.extraBody, providerOptions: request.providerOptions)
}

private func deepgramProviderOptions(extraBody: [String: JSONValue], providerOptions: [String: JSONValue]) -> [String: JSONValue] {
    var output = deepgramProviderOptions(from: extraBody)
    output.merge(deepgramProviderOptions(from: providerOptions)) { _, providerValue in providerValue }
    return output
}

private func falProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "fal")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func falProviderOptions(from request: SpeechRequest) -> [String: JSONValue] {
    falProviderOptions(extraBody: request.extraBody, providerOptions: request.providerOptions)
}

private func falProviderOptions(from request: AudioTranscriptionRequest) -> [String: JSONValue] {
    falProviderOptions(extraBody: request.extraBody, providerOptions: request.providerOptions)
}

private func falProviderOptions(extraBody: [String: JSONValue], providerOptions: [String: JSONValue]) -> [String: JSONValue] {
    var output = falProviderOptions(from: extraBody)
    output.merge(falProviderOptions(from: providerOptions)) { _, providerValue in providerValue }
    return output
}

private func falSpeechWarnings(for request: SpeechRequest) -> [AIWarning] {
    guard let format = request.format, format != "url", format != "hex" else {
        return []
    }
    return [
        AIWarning(
            type: "unsupported",
            feature: "outputFormat",
            message: "Unsupported outputFormat: \(format). Using 'url' instead."
        )
    ]
}

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

private func assemblyAIProviderOptions(from request: AudioTranscriptionRequest) -> [String: JSONValue] {
    assemblyAIProviderOptions(extraBody: request.extraBody, providerOptions: request.providerOptions)
}

private func assemblyAIProviderOptions(extraBody: [String: JSONValue], providerOptions: [String: JSONValue]) -> [String: JSONValue] {
    var output = assemblyAIProviderOptions(from: extraBody)
    output.merge(assemblyAIProviderOptions(from: providerOptions)) { _, providerValue in providerValue }
    return output
}

private func revAIProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "revai")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func revAIProviderOptions(from request: AudioTranscriptionRequest) -> [String: JSONValue] {
    revAIProviderOptions(extraBody: request.extraBody, providerOptions: request.providerOptions)
}

private func revAIProviderOptions(extraBody: [String: JSONValue], providerOptions: [String: JSONValue]) -> [String: JSONValue] {
    var output = revAIProviderOptions(from: extraBody)
    output.merge(revAIProviderOptions(from: providerOptions)) { _, providerValue in providerValue }
    return output
}

private func gladiaProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "gladia")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func gladiaProviderOptions(from request: AudioTranscriptionRequest) -> [String: JSONValue] {
    gladiaProviderOptions(extraBody: request.extraBody, providerOptions: request.providerOptions)
}

private func gladiaProviderOptions(extraBody: [String: JSONValue], providerOptions: [String: JSONValue]) -> [String: JSONValue] {
    var output = gladiaProviderOptions(from: extraBody)
    output.merge(gladiaProviderOptions(from: providerOptions)) { _, providerValue in providerValue }
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

private func lmntProviderOptions(from request: SpeechRequest) -> [String: JSONValue] {
    lmntProviderOptions(extraBody: request.extraBody, providerOptions: request.providerOptions)
}

private func lmntProviderOptions(extraBody: [String: JSONValue], providerOptions: [String: JSONValue]) -> [String: JSONValue] {
    var output = lmntProviderOptions(from: extraBody)
    output.merge(lmntProviderOptions(from: providerOptions)) { _, providerValue in providerValue }
    return output
}

private func lmntSpeechWarnings(for request: SpeechRequest) -> [AIWarning] {
    guard let format = request.format,
          !["mp3", "aac", "mulaw", "raw", "wav"].contains(format.lowercased()) else {
        return []
    }
    return [
        AIWarning(
            type: "unsupported",
            feature: "outputFormat",
            message: "Unsupported output format: \(format). Using mp3 instead."
        )
    ]
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

private func humeProviderOptions(from request: SpeechRequest) -> [String: JSONValue] {
    humeProviderOptions(extraBody: request.extraBody, providerOptions: request.providerOptions)
}

private func humeProviderOptions(extraBody: [String: JSONValue], providerOptions: [String: JSONValue]) -> [String: JSONValue] {
    var output = humeProviderOptions(from: extraBody)
    output.merge(humeProviderOptions(from: providerOptions)) { _, providerValue in providerValue }
    return output
}

private func humeSpeechWarnings(for request: SpeechRequest) -> [AIWarning] {
    guard let format = request.format,
          !["mp3", "pcm", "wav"].contains(format.lowercased()) else {
        return []
    }
    return [
        AIWarning(
            type: "unsupported",
            feature: "outputFormat",
            message: "Unsupported output format: \(format). Using mp3 instead."
        )
    ]
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

private func elevenLabsProviderOptions(from request: SpeechRequest) -> [String: JSONValue] {
    elevenLabsProviderOptions(extraBody: request.extraBody, providerOptions: request.providerOptions)
}

private func elevenLabsProviderOptions(from request: AudioTranscriptionRequest) -> [String: JSONValue] {
    elevenLabsProviderOptions(extraBody: request.extraBody, providerOptions: request.providerOptions)
}

private func elevenLabsProviderOptions(extraBody: [String: JSONValue], providerOptions: [String: JSONValue]) -> [String: JSONValue] {
    var output = elevenLabsProviderOptions(from: extraBody)
    output.merge(elevenLabsProviderOptions(from: providerOptions)) { _, providerValue in providerValue }
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
