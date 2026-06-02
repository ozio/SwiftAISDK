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
        let options = try lmntProviderOptions(from: request)
        let warnings = lmntSpeechWarnings(for: request)
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "text": .string(request.text),
            "voice": .string(request.voice ?? "ava"),
            "response_format": .string(lmntResponseFormat(request.format))
        ]
        if let speed = request.speed {
            body["speed"] = .number(speed)
        }
        body.merge(lmntSpeechOptions(from: options)) { _, new in new }
        if let language = request.language {
            body["language"] = .string(language)
        }

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
        let options = try humeProviderOptions(from: request)
        let warnings = humeSpeechWarnings(for: request)
        let voice = request.voice ?? "d8ab67c6-953d-4bd8-9370-8fa53a0f1453"
        var utterance: [String: JSONValue] = [
            "text": .string(request.text),
            "voice": .object([
                "id": .string(voice),
                "provider": .string("HUME_AI")
            ])
        ]
        if let speed = request.speed {
            utterance["speed"] = .number(speed)
        }
        if let instructions = request.instructions {
            utterance["description"] = .string(instructions)
        }
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
        let options = try elevenLabsProviderOptions(from: request)
        let warnings = elevenLabsSpeechWarnings(for: request)
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
        if let language = request.language ?? options["languageCode"]?.stringValue ?? options["language_code"]?.stringValue {
            body["language_code"] = .string(language)
        }
        var voiceSettings: [String: JSONValue] = [:]
        if let speed = request.speed {
            voiceSettings["speed"] = .number(speed)
        }
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
            warnings: warnings,
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
        let options = try elevenLabsProviderOptions(from: request)
        var form = MultipartFormData()
        form.appendField(name: "model_id", value: modelID)
        form.appendFile(name: "file", fileName: "audio.\(mediaTypeToExtension(request.mimeType))", mimeType: request.mimeType, data: request.audio)
        form.appendField(name: "diarize", value: String(options["diarize"]?.boolValue ?? true))
        if let language = options["languageCode"]?.stringValue ?? options["language_code"]?.stringValue {
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
        let options = try assemblyAIProviderOptions(from: request)
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
        guard let submitStatus = submitRaw["status"]?.stringValue, assemblyAITranscriptStatuses.contains(submitStatus) else {
            throw AIError.invalidResponse(provider: providerID, message: "AssemblyAI submit response status is invalid.")
        }
        guard let transcriptID = submitRaw["id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "AssemblyAI submit response did not contain id.")
        }

        let finalResponse = try await pollAssemblyAITranscriptResponse(id: transcriptID, request: request)
        let raw = finalResponse.json
        try validateAssemblyAITranscriptResponse(raw, providerID: providerID)
        let status = raw["status"]?.stringValue
        if status == "error" {
            throw AIError.invalidResponse(provider: providerID, message: "Transcription failed: \(raw["error"]?.stringValue ?? "Unknown error")")
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
            guard let status = raw["status"]?.stringValue, assemblyAITranscriptStatuses.contains(status) else {
                throw AIError.invalidResponse(provider: providerID, message: "AssemblyAI transcription status is invalid.")
            }
            switch status {
            case "completed", "error":
                return (raw, response)
            default:
                if DispatchTime.now().uptimeNanoseconds - started > 60_000_000_000 {
                    throw AIError.invalidResponse(provider: providerID, message: "AssemblyAI transcription polling timed out.")
                }
                try await sleepWithAbortSignal(nanoseconds: 3_000_000_000, abortSignal: request.abortSignal)
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

private let assemblyAITranscriptStatuses: Set<String> = ["queued", "processing", "completed", "error"]

private func validateAssemblyAITranscriptResponse(_ raw: JSONValue, providerID: String) throws {
    guard raw["id"]?.stringValue != nil else {
        throw AIError.invalidResponse(provider: providerID, message: "AssemblyAI transcription result is invalid.")
    }
    if let text = raw["text"], text != .null, text.stringValue == nil {
        throw AIError.invalidResponse(provider: providerID, message: "AssemblyAI transcription result is invalid.")
    }
    if let languageCode = raw["language_code"], languageCode != .null, languageCode.stringValue == nil {
        throw AIError.invalidResponse(provider: providerID, message: "AssemblyAI transcription result is invalid.")
    }
    if let audioDuration = raw["audio_duration"], audioDuration != .null, audioDuration.doubleValue == nil {
        throw AIError.invalidResponse(provider: providerID, message: "AssemblyAI transcription result is invalid.")
    }
    if let error = raw["error"], error != .null, error.stringValue == nil {
        throw AIError.invalidResponse(provider: providerID, message: "AssemblyAI transcription result is invalid.")
    }
    guard let words = raw["words"] else { return }
    guard words != .null else { return }
    guard let array = words.arrayValue else {
        throw AIError.invalidResponse(provider: providerID, message: "AssemblyAI transcription result is invalid.")
    }
    for word in array {
        guard
            word["start"]?.doubleValue != nil,
            word["end"]?.doubleValue != nil,
            word["text"]?.stringValue != nil
        else {
            throw AIError.invalidResponse(provider: providerID, message: "AssemblyAI transcription result is invalid.")
        }
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
        let options = try revAIProviderOptions(from: request)
        var form = MultipartFormData()
        form.appendFile(name: "media", fileName: "audio.\(mediaTypeToExtension(request.mimeType))", mimeType: request.mimeType, data: request.audio)
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
        if job["status"]?.stringValue == "failed" {
            throw AIError.invalidResponse(provider: providerID, message: "Rev.ai transcription job submission failed.")
        }
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
            if DispatchTime.now().uptimeNanoseconds - started > 60_000_000_000 {
                throw AIError.invalidResponse(provider: providerID, message: "Rev.ai transcription polling timed out.")
            }
            let response = try await config.transport.send(try getRequest(
                path: "/speechtotext/v1/jobs/\(id)",
                headers: request.headers,
                abortSignal: request.abortSignal
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: providerID, response: response)
            }
            job = try response.jsonValue()
            if job["status"]?.stringValue == "failed" {
                throw AIError.invalidResponse(provider: providerID, message: "Rev.ai transcription job failed.")
            }
            if job["status"]?.stringValue != "transcribed" {
                try await sleepWithAbortSignal(nanoseconds: 1_000_000_000, abortSignal: request.abortSignal)
            }
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
        let options = try gladiaProviderOptions(from: request)
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
        try validateGladiaTranscriptionResult(raw, providerID: providerID)
        guard raw["result"]?.objectValue != nil else {
            throw AIError.invalidResponse(provider: providerID, message: "Gladia transcription result is empty.")
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
            if DispatchTime.now().uptimeNanoseconds - started > 60_000_000_000 {
                throw AIError.invalidResponse(provider: providerID, message: "Gladia transcription polling timed out.")
            }
            let response = try await downloadURL(url, transport: config.transport, headers: config.headers.mergingHeaders(request.headers), abortSignal: request.abortSignal)
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            guard let status = raw["status"]?.stringValue, ["queued", "processing", "done", "error"].contains(status) else {
                throw AIError.invalidResponse(provider: providerID, message: "Gladia transcription status is invalid.")
            }
            switch status {
            case "done", "error":
                return (raw, response)
            default:
                try await sleepWithAbortSignal(nanoseconds: 1_000_000_000, abortSignal: request.abortSignal)
            }
        }
    }
}

private func validateGladiaTranscriptionResult(_ raw: JSONValue, providerID: String) throws {
    guard let result = raw["result"] else { return }
    guard result != .null else { return }
    guard
        result["metadata"]?["audio_duration"]?.doubleValue != nil,
        result["transcription"]?["full_transcript"]?.stringValue != nil,
        let languages = result["transcription"]?["languages"]?.arrayValue,
        let utterances = result["transcription"]?["utterances"]?.arrayValue
    else {
        throw AIError.invalidResponse(provider: providerID, message: "Gladia transcription result is invalid.")
    }
    guard languages.allSatisfy({ $0.stringValue != nil }) else {
        throw AIError.invalidResponse(provider: providerID, message: "Gladia transcription result is invalid.")
    }
    for utterance in utterances {
        guard
            utterance["start"]?.doubleValue != nil,
            utterance["end"]?.doubleValue != nil,
            utterance["text"]?.stringValue != nil
        else {
            throw AIError.invalidResponse(provider: providerID, message: "Gladia transcription result is invalid.")
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
        case "language", "punctuate", "redact", "search", "summarize", "topics", "utterances", "diarize":
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

private func assemblyAIProviderOptions(from request: AudioTranscriptionRequest) throws -> [String: JSONValue] {
    try assemblyAIProviderOptions(
        extraBody: request.extraBody,
        providerOptions: request.providerOptions,
        supportedProviderOptionKeys: assemblyAITranscriptionProviderOptionKeys,
        validateProviderOptions: assemblyAIValidateTranscriptionProviderOptions
    )
}

private func assemblyAIProviderOptions(extraBody: [String: JSONValue], providerOptions: [String: JSONValue], supportedProviderOptionKeys: Set<String>, validateProviderOptions: ([String: JSONValue]) throws -> [String: JSONValue]) throws -> [String: JSONValue] {
    var output = assemblyAIProviderOptions(from: extraBody)
    if let assemblyAIOptions = providerOptions["assemblyai"] {
        guard assemblyAIOptions != .null else { return output }
        guard let nested = assemblyAIOptions.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.assemblyai", message: "AssemblyAI provider options must be an object.")
        }
        for key in supportedProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try validateProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

private func assemblyAIValidateTranscriptionProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where assemblyAITranscriptionProviderOptionKeys.contains(key) {
        guard value != .null else { continue }
        switch key {
        case "audioEndAt", "audioStartFrom", "speakersExpected":
            try assemblyAIRequireInteger(value, argument: "providerOptions.assemblyai.\(key)", message: "AssemblyAI \(key) must be an integer.")
            output[key] = value
        case "contentSafetyConfidence":
            guard let number = value.doubleValue, assemblyAIIsInteger(number), number >= 25, number <= 100 else {
                throw AIError.invalidArgument(argument: "providerOptions.assemblyai.contentSafetyConfidence", message: "AssemblyAI contentSafetyConfidence must be an integer between 25 and 100.")
            }
            output[key] = value
        case "autoChapters", "autoHighlights", "contentSafety", "disfluencies", "entityDetection", "filterProfanity", "formatText", "iabCategories", "languageDetection", "multichannel", "punctuate", "redactPii", "redactPiiAudio", "sentimentAnalysis", "speakerLabels", "summarization":
            try assemblyAIRequireBoolean(value, argument: "providerOptions.assemblyai.\(key)", message: "AssemblyAI \(key) must be a boolean.")
            output[key] = value
        case "boostParam", "languageCode", "redactPiiAudioQuality", "redactPiiSub", "summaryModel", "summaryType", "webhookAuthHeaderName", "webhookAuthHeaderValue", "webhookUrl":
            try assemblyAIRequireString(value, argument: "providerOptions.assemblyai.\(key)", message: "AssemblyAI \(key) must be a string.")
            output[key] = value
        case "languageConfidenceThreshold":
            try assemblyAIRequireNumber(value, argument: "providerOptions.assemblyai.languageConfidenceThreshold", message: "AssemblyAI languageConfidenceThreshold must be a number.")
            output[key] = value
        case "speechThreshold":
            guard let number = value.doubleValue, number >= 0, number <= 1 else {
                throw AIError.invalidArgument(argument: "providerOptions.assemblyai.speechThreshold", message: "AssemblyAI speechThreshold must be a number between 0 and 1.")
            }
            output[key] = value
        case "redactPiiPolicies", "wordBoost":
            output[key] = try assemblyAIStringArray(value, argument: "providerOptions.assemblyai.\(key)")
        case "customSpelling":
            output[key] = try assemblyAIValidatedCustomSpelling(value)
        default:
            break
        }
    }
    return output
}

private func assemblyAIValidatedCustomSpelling(_ value: JSONValue) throws -> JSONValue {
    guard let array = value.arrayValue else {
        throw AIError.invalidArgument(argument: "providerOptions.assemblyai.customSpelling", message: "AssemblyAI customSpelling must be an array.")
    }
    return .array(try array.enumerated().map { index, item in
        guard let object = item.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.assemblyai.customSpelling[\(index)]", message: "AssemblyAI customSpelling items must be objects.")
        }
        guard let from = object["from"] else {
            throw AIError.invalidArgument(argument: "providerOptions.assemblyai.customSpelling[\(index)].from", message: "AssemblyAI customSpelling from is required.")
        }
        guard let to = object["to"], to.stringValue != nil else {
            throw AIError.invalidArgument(argument: "providerOptions.assemblyai.customSpelling[\(index)].to", message: "AssemblyAI customSpelling to must be a string.")
        }
        return .object([
            "from": try assemblyAIStringArray(from, argument: "providerOptions.assemblyai.customSpelling[\(index)].from"),
            "to": to
        ])
    })
}

private func assemblyAIStringArray(_ value: JSONValue, argument: String) throws -> JSONValue {
    guard let array = value.arrayValue else {
        throw AIError.invalidArgument(argument: argument, message: "AssemblyAI \(argument) must be an array of strings.")
    }
    for item in array where item.stringValue == nil {
        throw AIError.invalidArgument(argument: argument, message: "AssemblyAI \(argument) values must be strings.")
    }
    return value
}

private func assemblyAIRequireString(_ value: JSONValue, argument: String, message: String) throws {
    guard value.stringValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private func assemblyAIRequireNumber(_ value: JSONValue, argument: String, message: String) throws {
    guard value.doubleValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private func assemblyAIRequireInteger(_ value: JSONValue, argument: String, message: String) throws {
    guard let number = value.doubleValue, assemblyAIIsInteger(number) else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private func assemblyAIRequireBoolean(_ value: JSONValue, argument: String, message: String) throws {
    guard value.boolValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private func assemblyAIIsInteger(_ value: Double) -> Bool {
    value.rounded() == value
}

private let assemblyAITranscriptionProviderOptionKeys: Set<String> = [
    "audioEndAt",
    "audioStartFrom",
    "autoChapters",
    "autoHighlights",
    "boostParam",
    "contentSafety",
    "contentSafetyConfidence",
    "customSpelling",
    "disfluencies",
    "entityDetection",
    "filterProfanity",
    "formatText",
    "iabCategories",
    "languageCode",
    "languageConfidenceThreshold",
    "languageDetection",
    "multichannel",
    "punctuate",
    "redactPii",
    "redactPiiAudio",
    "redactPiiAudioQuality",
    "redactPiiPolicies",
    "redactPiiSub",
    "sentimentAnalysis",
    "speakerLabels",
    "speakersExpected",
    "speechThreshold",
    "summarization",
    "summaryModel",
    "summaryType",
    "webhookAuthHeaderName",
    "webhookAuthHeaderValue",
    "webhookUrl",
    "wordBoost"
]

private func revAIProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "revai")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func revAIProviderOptions(from request: AudioTranscriptionRequest) throws -> [String: JSONValue] {
    var output = revAIProviderOptions(from: request.extraBody)
    if let value = request.providerOptions["revai"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.revai", message: "Rev.ai provider options must be an object.")
        }
        for key in revAITranscriptionProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try revAIValidateTranscriptionProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

private let revAITranscriptionProviderOptionKeys: Set<String> = [
    "metadata",
    "notification_config",
    "delete_after_seconds",
    "verbatim",
    "rush",
    "test_mode",
    "segments_to_transcribe",
    "speaker_names",
    "skip_diarization",
    "skip_postprocessing",
    "skip_punctuation",
    "remove_disfluencies",
    "remove_atmospherics",
    "filter_profanity",
    "speaker_channels_count",
    "speakers_count",
    "diarization_type",
    "custom_vocabulary_id",
    "custom_vocabularies",
    "strict_custom_vocabulary",
    "summarization_config",
    "translation_config",
    "language",
    "forced_alignment"
]

private let revAITranscriptionProviderOptionDefaults: [String: JSONValue] = [
    "rush": .bool(false),
    "test_mode": .bool(false),
    "skip_diarization": .bool(false),
    "skip_postprocessing": .bool(false),
    "skip_punctuation": .bool(false),
    "remove_disfluencies": .bool(false),
    "remove_atmospherics": .bool(false),
    "filter_profanity": .bool(false),
    "diarization_type": .string("standard"),
    "language": .string("en"),
    "forced_alignment": .bool(false)
]

private func revAIValidateTranscriptionProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output = revAITranscriptionProviderOptionDefaults
    for (key, value) in options where revAITranscriptionProviderOptionKeys.contains(key) {
        if value == .null {
            guard revAINullishTranscriptionProviderOptionKeys.contains(key) else {
                throw AIError.invalidArgument(argument: "providerOptions.revai.\(key)", message: "Rev.ai \(key) cannot be null.")
            }
            output.removeValue(forKey: key)
            continue
        }
        switch key {
        case "metadata", "custom_vocabulary_id", "language":
            try revAIRequireString(value, argument: "providerOptions.revai.\(key)", message: "Rev.ai \(key) must be a string.")
            output[key] = value
        case "notification_config":
            output[key] = try revAIValidatedNotificationConfig(value)
        case "delete_after_seconds", "speaker_channels_count", "speakers_count":
            try revAIRequireNumber(value, argument: "providerOptions.revai.\(key)", message: "Rev.ai \(key) must be a number.")
            output[key] = value
        case "verbatim", "strict_custom_vocabulary":
            try revAIRequireBoolean(value, argument: "providerOptions.revai.\(key)", message: "Rev.ai \(key) must be a boolean.")
            output[key] = value
        case "rush", "test_mode", "skip_diarization", "skip_postprocessing", "skip_punctuation", "remove_disfluencies", "remove_atmospherics", "filter_profanity", "forced_alignment":
            try revAIRequireBoolean(value, argument: "providerOptions.revai.\(key)", message: "Rev.ai \(key) must be a boolean.")
            output[key] = value
        case "segments_to_transcribe":
            output[key] = try revAIValidatedSegments(value)
        case "speaker_names":
            output[key] = try revAIValidatedSpeakerNames(value)
        case "diarization_type":
            guard let type = value.stringValue, ["standard", "premium"].contains(type) else {
                throw AIError.invalidArgument(argument: "providerOptions.revai.diarization_type", message: "Rev.ai diarization_type must be standard or premium.")
            }
            output[key] = value
        case "custom_vocabularies":
            output[key] = try revAIValidatedCustomVocabularies(value)
        case "summarization_config":
            output[key] = try revAIValidatedSummarizationConfig(value)
        case "translation_config":
            output[key] = try revAIValidatedTranslationConfig(value)
        default:
            break
        }
    }
    return output
}

private let revAINullishTranscriptionProviderOptionKeys: Set<String> = [
    "metadata",
    "notification_config",
    "delete_after_seconds",
    "rush",
    "test_mode",
    "segments_to_transcribe",
    "speaker_names",
    "skip_diarization",
    "skip_postprocessing",
    "skip_punctuation",
    "remove_disfluencies",
    "remove_atmospherics",
    "filter_profanity",
    "speaker_channels_count",
    "speakers_count",
    "diarization_type",
    "custom_vocabulary_id",
    "summarization_config",
    "translation_config",
    "language",
    "forced_alignment"
]

private func revAIValidatedNotificationConfig(_ value: JSONValue) throws -> JSONValue {
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.revai.notification_config", message: "Rev.ai notification_config must be an object.")
    }
    guard let url = object["url"], url.stringValue != nil else {
        throw AIError.invalidArgument(argument: "providerOptions.revai.notification_config.url", message: "Rev.ai notification_config.url must be a string.")
    }
    var output: [String: JSONValue] = ["url": url]
    if let authHeaders = object["auth_headers"] {
        guard authHeaders != .null else { return .object(output) }
        guard let authObject = authHeaders.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.revai.notification_config.auth_headers", message: "Rev.ai notification_config.auth_headers must be an object.")
        }
        guard let authorization = authObject["Authorization"], authorization.stringValue != nil else {
            throw AIError.invalidArgument(argument: "providerOptions.revai.notification_config.auth_headers.Authorization", message: "Rev.ai notification_config.auth_headers.Authorization must be a string.")
        }
        output["auth_headers"] = .object(["Authorization": authorization])
    }
    return .object(output)
}

private func revAIValidatedSegments(_ value: JSONValue) throws -> JSONValue {
    guard let array = value.arrayValue else {
        throw AIError.invalidArgument(argument: "providerOptions.revai.segments_to_transcribe", message: "Rev.ai segments_to_transcribe must be an array.")
    }
    return .array(try array.enumerated().map { index, item in
        guard let object = item.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.revai.segments_to_transcribe[\(index)]", message: "Rev.ai segments_to_transcribe items must be objects.")
        }
        guard let start = object["start"], start.doubleValue != nil else {
            throw AIError.invalidArgument(argument: "providerOptions.revai.segments_to_transcribe[\(index)].start", message: "Rev.ai segment start must be a number.")
        }
        guard let end = object["end"], end.doubleValue != nil else {
            throw AIError.invalidArgument(argument: "providerOptions.revai.segments_to_transcribe[\(index)].end", message: "Rev.ai segment end must be a number.")
        }
        return .object(["start": start, "end": end])
    })
}

private func revAIValidatedSpeakerNames(_ value: JSONValue) throws -> JSONValue {
    guard let array = value.arrayValue else {
        throw AIError.invalidArgument(argument: "providerOptions.revai.speaker_names", message: "Rev.ai speaker_names must be an array.")
    }
    return .array(try array.enumerated().map { index, item in
        guard let object = item.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.revai.speaker_names[\(index)]", message: "Rev.ai speaker_names items must be objects.")
        }
        guard let displayName = object["display_name"], displayName.stringValue != nil else {
            throw AIError.invalidArgument(argument: "providerOptions.revai.speaker_names[\(index)].display_name", message: "Rev.ai speaker display_name must be a string.")
        }
        return .object(["display_name": displayName])
    })
}

private func revAIValidatedCustomVocabularies(_ value: JSONValue) throws -> JSONValue {
    guard let array = value.arrayValue else {
        throw AIError.invalidArgument(argument: "providerOptions.revai.custom_vocabularies", message: "Rev.ai custom_vocabularies must be an array.")
    }
    return .array(try array.enumerated().map { index, item in
        guard item.objectValue != nil else {
            throw AIError.invalidArgument(argument: "providerOptions.revai.custom_vocabularies[\(index)]", message: "Rev.ai custom_vocabularies items must be objects.")
        }
        return .object([:])
    })
}

private func revAIValidatedSummarizationConfig(_ value: JSONValue) throws -> JSONValue {
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.revai.summarization_config", message: "Rev.ai summarization_config must be an object.")
    }
    var output: [String: JSONValue] = [
        "model": .string("standard"),
        "type": .string("paragraph")
    ]
    if let model = object["model"] {
        if model == .null {
            output.removeValue(forKey: "model")
        } else {
            guard let modelName = model.stringValue, ["standard", "premium"].contains(modelName) else {
                throw AIError.invalidArgument(argument: "providerOptions.revai.summarization_config.model", message: "Rev.ai summarization_config.model must be standard or premium.")
            }
            output["model"] = model
        }
    }
    if let type = object["type"] {
        if type == .null {
            output.removeValue(forKey: "type")
        } else {
            guard let typeName = type.stringValue, ["paragraph", "bullets"].contains(typeName) else {
                throw AIError.invalidArgument(argument: "providerOptions.revai.summarization_config.type", message: "Rev.ai summarization_config.type must be paragraph or bullets.")
            }
            output["type"] = type
        }
    }
    if let prompt = object["prompt"] {
        guard prompt != .null else { return .object(output) }
        guard prompt.stringValue != nil else {
            throw AIError.invalidArgument(argument: "providerOptions.revai.summarization_config.prompt", message: "Rev.ai summarization_config.prompt must be a string.")
        }
        output["prompt"] = prompt
    }
    return .object(output)
}

private func revAIValidatedTranslationConfig(_ value: JSONValue) throws -> JSONValue {
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.revai.translation_config", message: "Rev.ai translation_config must be an object.")
    }
    guard let targetLanguages = object["target_languages"] else {
        throw AIError.invalidArgument(argument: "providerOptions.revai.translation_config.target_languages", message: "Rev.ai translation_config.target_languages is required.")
    }
    var output: [String: JSONValue] = [
        "target_languages": try revAIValidatedTranslationTargetLanguages(targetLanguages),
        "model": .string("standard")
    ]
    if let model = object["model"] {
        if model == .null {
            output.removeValue(forKey: "model")
        } else {
            guard let modelName = model.stringValue, ["standard", "premium"].contains(modelName) else {
                throw AIError.invalidArgument(argument: "providerOptions.revai.translation_config.model", message: "Rev.ai translation_config.model must be standard or premium.")
            }
            output["model"] = model
        }
    }
    return .object(output)
}

private let revAITranslationTargetLanguageCodes: Set<String> = [
    "en", "en-us", "en-gb", "ar", "pt", "pt-br", "pt-pt", "fr", "fr-ca", "es", "es-es", "es-la", "it", "ja", "ko", "de", "ru"
]

private func revAIValidatedTranslationTargetLanguages(_ value: JSONValue) throws -> JSONValue {
    guard let array = value.arrayValue else {
        throw AIError.invalidArgument(argument: "providerOptions.revai.translation_config.target_languages", message: "Rev.ai translation_config.target_languages must be an array.")
    }
    return .array(try array.enumerated().map { index, item in
        guard let object = item.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.revai.translation_config.target_languages[\(index)]", message: "Rev.ai translation target languages must be objects.")
        }
        guard let language = object["language"], let code = language.stringValue, revAITranslationTargetLanguageCodes.contains(code) else {
            throw AIError.invalidArgument(argument: "providerOptions.revai.translation_config.target_languages[\(index)].language", message: "Rev.ai translation target language is invalid.")
        }
        return .object(["language": language])
    })
}

private func revAIRequireString(_ value: JSONValue, argument: String, message: String) throws {
    guard value.stringValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private func revAIRequireNumber(_ value: JSONValue, argument: String, message: String) throws {
    guard value.doubleValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private func revAIRequireBoolean(_ value: JSONValue, argument: String, message: String) throws {
    guard value.boolValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private func gladiaProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    if let nested = output.removeValue(forKey: "gladia")?.objectValue {
        output.merge(nested) { _, nested in nested }
    }
    return output
}

private func gladiaProviderOptions(from request: AudioTranscriptionRequest) throws -> [String: JSONValue] {
    var output = gladiaProviderOptions(from: request.extraBody)
    if let value = request.providerOptions["gladia"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.gladia", message: "Gladia provider options must be an object.")
        }
        for key in gladiaTranscriptionProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try gladiaValidateTranscriptionProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

private let gladiaTranscriptionProviderOptionKeys: Set<String> = [
    "contextPrompt",
    "customVocabulary",
    "customVocabularyConfig",
    "detectLanguage",
    "enableCodeSwitching",
    "codeSwitchingConfig",
    "language",
    "callback",
    "callbackConfig",
    "subtitles",
    "subtitlesConfig",
    "diarization",
    "diarizationConfig",
    "translation",
    "translationConfig",
    "summarization",
    "summarizationConfig",
    "moderation",
    "namedEntityRecognition",
    "chapterization",
    "nameConsistency",
    "customSpelling",
    "customSpellingConfig",
    "structuredDataExtraction",
    "structuredDataExtractionConfig",
    "sentimentAnalysis",
    "audioToLlm",
    "audioToLlmConfig",
    "customMetadata",
    "sentences",
    "displayMode",
    "punctuationEnhanced"
]

private func gladiaValidateTranscriptionProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where gladiaTranscriptionProviderOptionKeys.contains(key) {
        guard value != .null else { continue }
        switch key {
        case "contextPrompt", "language":
            try gladiaRequireString(value, argument: "providerOptions.gladia.\(key)", message: "Gladia \(key) must be a string.")
            output[key] = value
        case "customVocabulary":
            output[key] = try gladiaValidatedCustomVocabulary(value)
        case "customVocabularyConfig":
            output[key] = try gladiaValidatedCustomVocabularyConfig(value)
        case "detectLanguage", "enableCodeSwitching", "callback", "subtitles", "diarization", "translation", "summarization", "moderation", "namedEntityRecognition", "chapterization", "nameConsistency", "customSpelling", "structuredDataExtraction", "sentimentAnalysis", "audioToLlm", "sentences", "displayMode", "punctuationEnhanced":
            try gladiaRequireBoolean(value, argument: "providerOptions.gladia.\(key)", message: "Gladia \(key) must be a boolean.")
            output[key] = value
        case "codeSwitchingConfig":
            output[key] = try gladiaValidatedCodeSwitchingConfig(value)
        case "callbackConfig":
            output[key] = try gladiaValidatedCallbackConfig(value)
        case "subtitlesConfig":
            output[key] = try gladiaValidatedSubtitlesConfig(value)
        case "diarizationConfig":
            output[key] = try gladiaValidatedDiarizationConfig(value)
        case "translationConfig":
            output[key] = try gladiaValidatedTranslationConfig(value)
        case "summarizationConfig":
            output[key] = try gladiaValidatedSummarizationConfig(value)
        case "customSpellingConfig":
            output[key] = try gladiaValidatedCustomSpellingConfig(value)
        case "structuredDataExtractionConfig":
            output[key] = try gladiaValidatedStructuredDataExtractionConfig(value)
        case "audioToLlmConfig":
            output[key] = try gladiaValidatedAudioToLLMConfig(value)
        case "customMetadata":
            guard value.objectValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.gladia.customMetadata", message: "Gladia customMetadata must be an object.")
            }
            output[key] = value
        default:
            break
        }
    }
    return output
}

private func gladiaValidatedCustomVocabulary(_ value: JSONValue) throws -> JSONValue {
    if value.boolValue != nil { return value }
    guard value.arrayValue != nil else {
        throw AIError.invalidArgument(argument: "providerOptions.gladia.customVocabulary", message: "Gladia customVocabulary must be a boolean or array.")
    }
    return value
}

private func gladiaValidatedCustomVocabularyConfig(_ value: JSONValue) throws -> JSONValue {
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.gladia.customVocabularyConfig", message: "Gladia customVocabularyConfig must be an object.")
    }
    guard let vocabulary = object["vocabulary"] else {
        throw AIError.invalidArgument(argument: "providerOptions.gladia.customVocabularyConfig.vocabulary", message: "Gladia customVocabularyConfig.vocabulary is required.")
    }
    var output: [String: JSONValue] = ["vocabulary": try gladiaValidatedVocabulary(vocabulary)]
    if let defaultIntensity = object["defaultIntensity"] {
        if defaultIntensity != .null {
            try gladiaRequireNumber(defaultIntensity, argument: "providerOptions.gladia.customVocabularyConfig.defaultIntensity", message: "Gladia customVocabularyConfig.defaultIntensity must be a number.")
            output["defaultIntensity"] = defaultIntensity
        }
    }
    return .object(output)
}

private func gladiaValidatedVocabulary(_ value: JSONValue) throws -> JSONValue {
    guard let array = value.arrayValue else {
        throw AIError.invalidArgument(argument: "providerOptions.gladia.customVocabularyConfig.vocabulary", message: "Gladia customVocabularyConfig.vocabulary must be an array.")
    }
    return .array(try array.enumerated().map { index, item in
        if item.stringValue != nil { return item }
        guard let object = item.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.gladia.customVocabularyConfig.vocabulary[\(index)]", message: "Gladia vocabulary items must be strings or objects.")
        }
        guard let term = object["value"], term.stringValue != nil else {
            throw AIError.invalidArgument(argument: "providerOptions.gladia.customVocabularyConfig.vocabulary[\(index)].value", message: "Gladia vocabulary item value must be a string.")
        }
        var output: [String: JSONValue] = ["value": term]
        if let intensity = object["intensity"] {
            if intensity != .null {
                try gladiaRequireNumber(intensity, argument: "providerOptions.gladia.customVocabularyConfig.vocabulary[\(index)].intensity", message: "Gladia vocabulary intensity must be a number.")
                output["intensity"] = intensity
            }
        }
        if let pronunciations = object["pronunciations"] {
            if pronunciations != .null {
                output["pronunciations"] = try gladiaStringArray(pronunciations, argument: "providerOptions.gladia.customVocabularyConfig.vocabulary[\(index)].pronunciations")
            }
        }
        if let language = object["language"] {
            if language != .null {
                try gladiaRequireString(language, argument: "providerOptions.gladia.customVocabularyConfig.vocabulary[\(index)].language", message: "Gladia vocabulary language must be a string.")
                output["language"] = language
            }
        }
        return .object(output)
    })
}

private func gladiaValidatedCodeSwitchingConfig(_ value: JSONValue) throws -> JSONValue {
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.gladia.codeSwitchingConfig", message: "Gladia codeSwitchingConfig must be an object.")
    }
    var output: [String: JSONValue] = [:]
    if let languages = object["languages"] {
        if languages != .null {
            output["languages"] = try gladiaStringArray(languages, argument: "providerOptions.gladia.codeSwitchingConfig.languages")
        }
    }
    return .object(output)
}

private func gladiaValidatedCallbackConfig(_ value: JSONValue) throws -> JSONValue {
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.gladia.callbackConfig", message: "Gladia callbackConfig must be an object.")
    }
    guard let url = object["url"], url.stringValue != nil else {
        throw AIError.invalidArgument(argument: "providerOptions.gladia.callbackConfig.url", message: "Gladia callbackConfig.url must be a string.")
    }
    var output: [String: JSONValue] = ["url": url]
    if let method = object["method"] {
        if method != .null {
            guard let methodValue = method.stringValue, ["POST", "PUT"].contains(methodValue) else {
                throw AIError.invalidArgument(argument: "providerOptions.gladia.callbackConfig.method", message: "Gladia callbackConfig.method must be POST or PUT.")
            }
            output["method"] = method
        }
    }
    return .object(output)
}

private func gladiaValidatedSubtitlesConfig(_ value: JSONValue) throws -> JSONValue {
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.gladia.subtitlesConfig", message: "Gladia subtitlesConfig must be an object.")
    }
    var output: [String: JSONValue] = [:]
    if let formats = object["formats"] {
        if formats != .null {
            output["formats"] = try gladiaStringArray(formats, argument: "providerOptions.gladia.subtitlesConfig.formats", allowedValues: ["srt", "vtt"])
        }
    }
    for key in ["minimumDuration", "maximumDuration", "maximumCharactersPerRow", "maximumRowsPerCaption"] {
        if let number = object[key] {
            guard number != .null else { continue }
            try gladiaRequireNumber(number, argument: "providerOptions.gladia.subtitlesConfig.\(key)", message: "Gladia subtitlesConfig.\(key) must be a number.")
            output[key] = number
        }
    }
    if let style = object["style"] {
        if style != .null {
            guard let styleValue = style.stringValue, ["default", "compliance"].contains(styleValue) else {
                throw AIError.invalidArgument(argument: "providerOptions.gladia.subtitlesConfig.style", message: "Gladia subtitlesConfig.style must be default or compliance.")
            }
            output["style"] = style
        }
    }
    return .object(output)
}

private func gladiaValidatedDiarizationConfig(_ value: JSONValue) throws -> JSONValue {
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.gladia.diarizationConfig", message: "Gladia diarizationConfig must be an object.")
    }
    var output: [String: JSONValue] = [:]
    for key in ["numberOfSpeakers", "minSpeakers", "maxSpeakers"] {
        if let number = object[key] {
            guard number != .null else { continue }
            try gladiaRequireNumber(number, argument: "providerOptions.gladia.diarizationConfig.\(key)", message: "Gladia diarizationConfig.\(key) must be a number.")
            output[key] = number
        }
    }
    if let enhanced = object["enhanced"] {
        if enhanced != .null {
            try gladiaRequireBoolean(enhanced, argument: "providerOptions.gladia.diarizationConfig.enhanced", message: "Gladia diarizationConfig.enhanced must be a boolean.")
            output["enhanced"] = enhanced
        }
    }
    return .object(output)
}

private func gladiaValidatedTranslationConfig(_ value: JSONValue) throws -> JSONValue {
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.gladia.translationConfig", message: "Gladia translationConfig must be an object.")
    }
    guard let targetLanguages = object["targetLanguages"] else {
        throw AIError.invalidArgument(argument: "providerOptions.gladia.translationConfig.targetLanguages", message: "Gladia translationConfig.targetLanguages is required.")
    }
    var output: [String: JSONValue] = [
        "targetLanguages": try gladiaStringArray(targetLanguages, argument: "providerOptions.gladia.translationConfig.targetLanguages")
    ]
    if let model = object["model"] {
        if model != .null {
            guard let modelValue = model.stringValue, ["base", "enhanced"].contains(modelValue) else {
                throw AIError.invalidArgument(argument: "providerOptions.gladia.translationConfig.model", message: "Gladia translationConfig.model must be base or enhanced.")
            }
            output["model"] = model
        }
    }
    if let matchOriginalUtterances = object["matchOriginalUtterances"] {
        if matchOriginalUtterances != .null {
            try gladiaRequireBoolean(matchOriginalUtterances, argument: "providerOptions.gladia.translationConfig.matchOriginalUtterances", message: "Gladia translationConfig.matchOriginalUtterances must be a boolean.")
            output["matchOriginalUtterances"] = matchOriginalUtterances
        }
    }
    return .object(output)
}

private func gladiaValidatedSummarizationConfig(_ value: JSONValue) throws -> JSONValue {
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.gladia.summarizationConfig", message: "Gladia summarizationConfig must be an object.")
    }
    var output: [String: JSONValue] = [:]
    if let type = object["type"] {
        if type != .null {
            guard let typeValue = type.stringValue, ["general", "bullet_points", "concise"].contains(typeValue) else {
                throw AIError.invalidArgument(argument: "providerOptions.gladia.summarizationConfig.type", message: "Gladia summarizationConfig.type is invalid.")
            }
            output["type"] = type
        }
    }
    return .object(output)
}

private func gladiaValidatedCustomSpellingConfig(_ value: JSONValue) throws -> JSONValue {
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.gladia.customSpellingConfig", message: "Gladia customSpellingConfig must be an object.")
    }
    guard let dictionary = object["spellingDictionary"], let entries = dictionary.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.gladia.customSpellingConfig.spellingDictionary", message: "Gladia customSpellingConfig.spellingDictionary must be an object.")
    }
    var output: [String: JSONValue] = [:]
    for (key, value) in entries {
        output[key] = try gladiaStringArray(value, argument: "providerOptions.gladia.customSpellingConfig.spellingDictionary.\(key)")
    }
    return .object(["spellingDictionary": .object(output)])
}

private func gladiaValidatedStructuredDataExtractionConfig(_ value: JSONValue) throws -> JSONValue {
    guard let object = value.objectValue, let classes = object["classes"] else {
        throw AIError.invalidArgument(argument: "providerOptions.gladia.structuredDataExtractionConfig.classes", message: "Gladia structuredDataExtractionConfig.classes is required.")
    }
    return .object(["classes": try gladiaStringArray(classes, argument: "providerOptions.gladia.structuredDataExtractionConfig.classes")])
}

private func gladiaValidatedAudioToLLMConfig(_ value: JSONValue) throws -> JSONValue {
    guard let object = value.objectValue, let prompts = object["prompts"] else {
        throw AIError.invalidArgument(argument: "providerOptions.gladia.audioToLlmConfig.prompts", message: "Gladia audioToLlmConfig.prompts is required.")
    }
    return .object(["prompts": try gladiaStringArray(prompts, argument: "providerOptions.gladia.audioToLlmConfig.prompts")])
}

private func gladiaStringArray(_ value: JSONValue, argument: String, allowedValues: Set<String>? = nil) throws -> JSONValue {
    guard let array = value.arrayValue else {
        throw AIError.invalidArgument(argument: argument, message: "Gladia \(argument) must be an array of strings.")
    }
    for item in array {
        guard let string = item.stringValue else {
            throw AIError.invalidArgument(argument: argument, message: "Gladia \(argument) values must be strings.")
        }
        if let allowedValues, !allowedValues.contains(string) {
            throw AIError.invalidArgument(argument: argument, message: "Gladia \(argument) contains an unsupported value.")
        }
    }
    return value
}

private func gladiaRequireString(_ value: JSONValue, argument: String, message: String) throws {
    guard value.stringValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private func gladiaRequireNumber(_ value: JSONValue, argument: String, message: String) throws {
    guard value.doubleValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private func gladiaRequireBoolean(_ value: JSONValue, argument: String, message: String) throws {
    guard value.boolValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
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

private func lmntProviderOptions(from request: SpeechRequest) throws -> [String: JSONValue] {
    var output = lmntProviderOptions(from: request.extraBody)
    if let value = request.providerOptions["lmnt"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.lmnt", message: "LMNT provider options must be an object.")
        }
        for key in lmntSpeechProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try lmntValidateSpeechProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

private let lmntSpeechProviderOptionKeys: Set<String> = [
    "model",
    "format",
    "sampleRate",
    "speed",
    "seed",
    "conversational",
    "length",
    "topP",
    "temperature"
]

private let lmntSpeechProviderOptionDefaults: [String: JSONValue] = [
    "sampleRate": .number(24_000),
    "speed": .number(1),
    "conversational": .bool(false),
    "topP": .number(1),
    "temperature": .number(1)
]

private func lmntValidateSpeechProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output = lmntSpeechProviderOptionDefaults
    for (key, value) in options where lmntSpeechProviderOptionKeys.contains(key) {
        if value == .null {
            output.removeValue(forKey: key)
            continue
        }
        switch key {
        case "model":
            try lmntRequireString(value, argument: "providerOptions.lmnt.model", message: "LMNT model must be a string.")
        case "format":
            guard let format = value.stringValue, ["aac", "mp3", "mulaw", "raw", "wav"].contains(format) else {
                throw AIError.invalidArgument(argument: "providerOptions.lmnt.format", message: "LMNT format must be one of aac, mp3, mulaw, raw, wav.")
            }
        case "sampleRate":
            guard let sampleRate = value.doubleValue, [8_000, 16_000, 24_000].contains(sampleRate) else {
                throw AIError.invalidArgument(argument: "providerOptions.lmnt.sampleRate", message: "LMNT sampleRate must be one of 8000, 16000, 24000.")
            }
        case "speed":
            guard let speed = value.doubleValue, speed >= 0.25, speed <= 2 else {
                throw AIError.invalidArgument(argument: "providerOptions.lmnt.speed", message: "LMNT speed must be a number between 0.25 and 2.")
            }
        case "seed":
            guard let seed = value.doubleValue, lmntIsInteger(seed) else {
                throw AIError.invalidArgument(argument: "providerOptions.lmnt.seed", message: "LMNT seed must be an integer.")
            }
        case "conversational":
            try lmntRequireBoolean(value, argument: "providerOptions.lmnt.conversational", message: "LMNT conversational must be a boolean.")
        case "length":
            guard let length = value.doubleValue, length <= 300 else {
                throw AIError.invalidArgument(argument: "providerOptions.lmnt.length", message: "LMNT length must be a number no greater than 300.")
            }
        case "topP":
            guard let topP = value.doubleValue, topP >= 0, topP <= 1 else {
                throw AIError.invalidArgument(argument: "providerOptions.lmnt.topP", message: "LMNT topP must be a number between 0 and 1.")
            }
        case "temperature":
            guard let temperature = value.doubleValue, temperature >= 0 else {
                throw AIError.invalidArgument(argument: "providerOptions.lmnt.temperature", message: "LMNT temperature must be a number no less than 0.")
            }
        default:
            break
        }
        output[key] = value
    }
    return output
}

private func lmntRequireString(_ value: JSONValue, argument: String, message: String) throws {
    guard value.stringValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private func lmntRequireBoolean(_ value: JSONValue, argument: String, message: String) throws {
    guard value.boolValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private func lmntIsInteger(_ value: Double) -> Bool {
    value.isFinite && value.rounded(.towardZero) == value
}

private func lmntSpeechWarnings(for request: SpeechRequest) -> [AIWarning] {
    guard let format = request.format,
          !["mp3", "aac", "mulaw", "raw", "wav"].contains(format) else {
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
    if let context = output.removeValue(forKey: "context"),
       let humeContext = humeContext(context) {
        output["context"] = humeContext
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

private func humeProviderOptions(from request: SpeechRequest) throws -> [String: JSONValue] {
    var output = humeProviderOptions(from: request.extraBody)
    if let value = request.providerOptions["hume"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.hume", message: "Hume provider options must be an object.")
        }
        for key in humeSpeechProviderOptionKeys {
            output.removeValue(forKey: key)
        }
        output.merge(try humeValidateSpeechProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

private let humeSpeechProviderOptionKeys: Set<String> = [
    "context"
]

private func humeValidateSpeechProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    if let context = options["context"] {
        guard context != .null else { return output }
        output["context"] = try humeValidatedContext(context)
    }
    return output
}

private func humeValidatedContext(_ value: JSONValue) throws -> JSONValue {
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.hume.context", message: "Hume context must be an object.")
    }
    if let generationID = object["generationId"] {
        guard generationID.stringValue != nil else {
            throw AIError.invalidArgument(argument: "providerOptions.hume.context.generationId", message: "Hume context.generationId must be a string.")
        }
        return .object(["generationId": generationID])
    }
    guard let utterances = object["utterances"]?.arrayValue else {
        throw AIError.invalidArgument(argument: "providerOptions.hume.context", message: "Hume context must include generationId or utterances.")
    }
    return .object([
        "utterances": .array(try utterances.enumerated().map { index, utterance in
            try humeValidatedContextUtterance(utterance, index: index)
        })
    ])
}

private func humeValidatedContextUtterance(_ value: JSONValue, index: Int) throws -> JSONValue {
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.hume.context.utterances[\(index)]", message: "Hume context utterances must be objects.")
    }
    guard let text = object["text"], text.stringValue != nil else {
        throw AIError.invalidArgument(argument: "providerOptions.hume.context.utterances[\(index)].text", message: "Hume context utterance text must be a string.")
    }
    var output: [String: JSONValue] = ["text": text]
    if let description = object["description"] {
        guard description.stringValue != nil else {
            throw AIError.invalidArgument(argument: "providerOptions.hume.context.utterances[\(index)].description", message: "Hume context utterance description must be a string.")
        }
        output["description"] = description
    }
    if let speed = object["speed"] {
        guard speed.doubleValue != nil else {
            throw AIError.invalidArgument(argument: "providerOptions.hume.context.utterances[\(index)].speed", message: "Hume context utterance speed must be a number.")
        }
        output["speed"] = speed
    }
    if let trailingSilence = object["trailingSilence"] {
        guard trailingSilence.doubleValue != nil else {
            throw AIError.invalidArgument(argument: "providerOptions.hume.context.utterances[\(index)].trailingSilence", message: "Hume context utterance trailingSilence must be a number.")
        }
        output["trailingSilence"] = trailingSilence
    }
    if let voice = object["voice"] {
        output["voice"] = try humeValidatedVoice(voice, argument: "providerOptions.hume.context.utterances[\(index)].voice")
    }
    return .object(output)
}

private func humeValidatedVoice(_ value: JSONValue, argument: String) throws -> JSONValue {
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: argument, message: "Hume voice must be an object.")
    }
    var output: [String: JSONValue] = [:]
    if let id = object["id"] {
        guard id.stringValue != nil else {
            throw AIError.invalidArgument(argument: "\(argument).id", message: "Hume voice id must be a string.")
        }
        output["id"] = id
    } else if let name = object["name"] {
        guard name.stringValue != nil else {
            throw AIError.invalidArgument(argument: "\(argument).name", message: "Hume voice name must be a string.")
        }
        output["name"] = name
    } else {
        throw AIError.invalidArgument(argument: argument, message: "Hume voice must include id or name.")
    }
    if let provider = object["provider"] {
        guard let providerName = provider.stringValue, ["HUME_AI", "CUSTOM_VOICE"].contains(providerName) else {
            throw AIError.invalidArgument(argument: "\(argument).provider", message: "Hume voice provider must be HUME_AI or CUSTOM_VOICE.")
        }
        output["provider"] = provider
    }
    return .object(output)
}

private func humeSpeechWarnings(for request: SpeechRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if let format = request.format,
       !["mp3", "pcm", "wav"].contains(format) {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "outputFormat",
            message: "Unsupported output format: \(format). Using mp3 instead."
        ))
    }
    if let language = request.language {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "language",
            message: "Hume speech models do not support language selection. Language parameter \"\(language)\" was ignored."
        ))
    }
    return warnings
}

private func humeContext(_ value: JSONValue) -> JSONValue? {
    guard let object = value.objectValue else { return nil }
    if let generationID = object["generationId"] {
        return .object(["generation_id": generationID])
    }
    if let utterances = object["utterances"]?.arrayValue {
        return .object([
            "utterances": .array(utterances.compactMap(humeContextUtterance))
        ])
    }
    return nil
}

private func humeContextUtterance(_ value: JSONValue) -> JSONValue? {
    guard let object = value.objectValue else { return nil }
    var output: [String: JSONValue] = [:]
    for key in ["text", "description", "speed"] {
        if let value = object[key] {
            output[key] = value
        }
    }
    if let trailingSilence = object["trailingSilence"] {
        output["trailing_silence"] = trailingSilence
    }
    if let voice = object["voice"]?.objectValue {
        var filteredVoice: [String: JSONValue] = [:]
        if let id = voice["id"] {
            filteredVoice["id"] = id
        } else if let name = voice["name"] {
            filteredVoice["name"] = name
        }
        if let provider = voice["provider"] {
            filteredVoice["provider"] = provider
        }
        if !filteredVoice.isEmpty {
            output["voice"] = .object(filteredVoice)
        }
    }
    return .object(output)
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

private func revAITranscriptText(from raw: JSONValue) -> String {
    raw["monologues"]?.arrayValue?.map { monologue in
        monologue["elements"]?.arrayValue?.compactMap { $0["value"]?.stringValue }.joined() ?? ""
    }.joined(separator: " ") ?? ""
}

private func lmntResponseFormat(_ outputFormat: String?) -> String {
    guard let outputFormat, ["mp3", "aac", "mulaw", "raw", "wav"].contains(outputFormat) else {
        return "mp3"
    }
    return outputFormat
}

private func humeFormat(_ outputFormat: String?) -> String {
    guard let outputFormat, ["mp3", "pcm", "wav"].contains(outputFormat) else {
        return "mp3"
    }
    return outputFormat
}

private func elevenLabsOutputFormat(_ outputFormat: String?) -> String {
    switch outputFormat {
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

private func elevenLabsProviderOptions(from request: SpeechRequest) throws -> [String: JSONValue] {
    try elevenLabsProviderOptions(
        extraBody: request.extraBody,
        providerOptions: request.providerOptions,
        supportedProviderOptionKeys: elevenLabsSpeechProviderOptionKeys,
        validateProviderOptions: elevenLabsValidateSpeechProviderOptions
    )
}

private func elevenLabsProviderOptions(from request: AudioTranscriptionRequest) throws -> [String: JSONValue] {
    var output = elevenLabsProviderOptions(from: request.extraBody)
    if let value = request.providerOptions["elevenlabs"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.elevenlabs", message: "ElevenLabs provider options must be an object.")
        }
        output.merge(elevenLabsTranscriptionProviderOptionDefaults) { _, defaultValue in defaultValue }
        output.merge(try elevenLabsValidateTranscriptionProviderOptions(nested)) { _, providerValue in providerValue }
    }
    return output
}

private func elevenLabsProviderOptions(extraBody: [String: JSONValue], providerOptions: [String: JSONValue], supportedProviderOptionKeys: Set<String>, validateProviderOptions: ([String: JSONValue]) throws -> [String: JSONValue]) throws -> [String: JSONValue] {
    var output = elevenLabsProviderOptions(from: extraBody)
    if let value = providerOptions["elevenlabs"] {
        guard value != .null else { return output }
        guard let nested = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.elevenlabs", message: "ElevenLabs provider options must be an object.")
        }
        let validated = try validateProviderOptions(nested)
        output.merge(validated.filter { supportedProviderOptionKeys.contains($0.key) }) { _, providerValue in providerValue }
    }
    return output
}

private func elevenLabsValidateSpeechProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where elevenLabsSpeechProviderOptionKeys.contains(key) {
        switch key {
        case "languageCode", "previousText", "nextText":
            try elevenLabsRequireString(value, argument: "providerOptions.elevenlabs.\(key)", message: "ElevenLabs \(key) must be a string.")
            output[key] = value
        case "voiceSettings":
            output[key] = try elevenLabsValidatedVoiceSettings(value)
        case "pronunciationDictionaryLocators":
            output[key] = try elevenLabsValidatedPronunciationLocators(value)
        case "seed":
            guard let number = value.doubleValue, number >= 0, number <= 4_294_967_295 else {
                throw AIError.invalidArgument(argument: "providerOptions.elevenlabs.seed", message: "ElevenLabs seed must be a number between 0 and 4294967295.")
            }
            output[key] = value
        case "previousRequestIds", "nextRequestIds":
            output[key] = try elevenLabsStringArray(value, argument: "providerOptions.elevenlabs.\(key)", maxCount: 3)
        case "applyTextNormalization":
            guard let mode = value.stringValue, ["auto", "on", "off"].contains(mode) else {
                throw AIError.invalidArgument(argument: "providerOptions.elevenlabs.applyTextNormalization", message: "ElevenLabs applyTextNormalization must be one of auto, on, off.")
            }
            output[key] = value
        case "applyLanguageTextNormalization", "enableLogging":
            try elevenLabsRequireBoolean(value, argument: "providerOptions.elevenlabs.\(key)", message: "ElevenLabs \(key) must be a boolean.")
            output[key] = value
        default:
            break
        }
    }
    return output
}

private func elevenLabsValidateTranscriptionProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where elevenLabsTranscriptionProviderOptionKeys.contains(key) {
        if value == .null {
            output[key] = value
            continue
        }
        switch key {
        case "languageCode":
            try elevenLabsRequireString(value, argument: "providerOptions.elevenlabs.languageCode", message: "ElevenLabs languageCode must be a string.")
        case "tagAudioEvents", "diarize":
            try elevenLabsRequireBoolean(value, argument: "providerOptions.elevenlabs.\(key)", message: "ElevenLabs \(key) must be a boolean.")
        case "numSpeakers":
            guard let number = value.doubleValue, elevenLabsIsInteger(number), number >= 1, number <= 32 else {
                throw AIError.invalidArgument(argument: "providerOptions.elevenlabs.numSpeakers", message: "ElevenLabs numSpeakers must be an integer between 1 and 32.")
            }
        case "timestampsGranularity":
            guard let granularity = value.stringValue, ["none", "word", "character"].contains(granularity) else {
                throw AIError.invalidArgument(argument: "providerOptions.elevenlabs.timestampsGranularity", message: "ElevenLabs timestampsGranularity must be one of none, word, character.")
            }
        case "fileFormat":
            guard let format = value.stringValue, ["pcm_s16le_16", "other"].contains(format) else {
                throw AIError.invalidArgument(argument: "providerOptions.elevenlabs.fileFormat", message: "ElevenLabs fileFormat must be one of pcm_s16le_16, other.")
            }
        default:
            break
        }
        output[key] = value
    }
    return output
}

private let elevenLabsSpeechProviderOptionKeys: Set<String> = [
    "languageCode",
    "voiceSettings",
    "pronunciationDictionaryLocators",
    "seed",
    "previousText",
    "nextText",
    "previousRequestIds",
    "nextRequestIds",
    "applyTextNormalization",
    "applyLanguageTextNormalization",
    "enableLogging"
]

private let elevenLabsTranscriptionProviderOptionKeys: Set<String> = [
    "languageCode",
    "tagAudioEvents",
    "numSpeakers",
    "timestampsGranularity",
    "diarize",
    "fileFormat"
]

private let elevenLabsTranscriptionProviderOptionDefaults: [String: JSONValue] = [
    "tagAudioEvents": .bool(true),
    "timestampsGranularity": .string("word"),
    "diarize": .bool(false),
    "fileFormat": .string("other")
]

private func elevenLabsSpeechWarnings(for request: SpeechRequest) -> [AIWarning] {
    guard request.instructions != nil else { return [] }
    return [
        AIWarning(
            type: "unsupported",
            feature: "instructions",
            message: "ElevenLabs speech models do not support instructions. Instructions parameter was ignored."
        )
    ]
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

private func elevenLabsValidatedVoiceSettings(_ value: JSONValue) throws -> JSONValue {
    guard let settings = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.elevenlabs.voiceSettings", message: "ElevenLabs voiceSettings must be an object.")
    }
    var output: [String: JSONValue] = [:]
    for key in ["stability", "similarityBoost", "style"] {
        if let setting = settings[key] {
            guard let number = setting.doubleValue, number >= 0, number <= 1 else {
                throw AIError.invalidArgument(argument: "providerOptions.elevenlabs.voiceSettings.\(key)", message: "ElevenLabs voiceSettings.\(key) must be a number between 0 and 1.")
            }
            output[key] = setting
        }
    }
    if let useSpeakerBoost = settings["useSpeakerBoost"] {
        guard useSpeakerBoost.boolValue != nil else {
            throw AIError.invalidArgument(argument: "providerOptions.elevenlabs.voiceSettings.useSpeakerBoost", message: "ElevenLabs voiceSettings.useSpeakerBoost must be a boolean.")
        }
        output["useSpeakerBoost"] = useSpeakerBoost
    }
    return .object(output)
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

private func elevenLabsValidatedPronunciationLocators(_ value: JSONValue) throws -> JSONValue {
    guard let array = value.arrayValue, array.count <= 3 else {
        throw AIError.invalidArgument(argument: "providerOptions.elevenlabs.pronunciationDictionaryLocators", message: "ElevenLabs pronunciationDictionaryLocators must be an array with at most 3 items.")
    }
    return .array(try array.enumerated().map { index, item in
        guard let object = item.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.elevenlabs.pronunciationDictionaryLocators[\(index)]", message: "ElevenLabs pronunciationDictionaryLocators items must be objects.")
        }
        guard let pronunciationDictionaryID = object["pronunciationDictionaryId"], pronunciationDictionaryID.stringValue != nil else {
            throw AIError.invalidArgument(argument: "providerOptions.elevenlabs.pronunciationDictionaryLocators[\(index)].pronunciationDictionaryId", message: "ElevenLabs pronunciationDictionaryId must be a string.")
        }
        var output: [String: JSONValue] = ["pronunciationDictionaryId": pronunciationDictionaryID]
        if let versionID = object["versionId"] {
            guard versionID.stringValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.elevenlabs.pronunciationDictionaryLocators[\(index)].versionId", message: "ElevenLabs versionId must be a string.")
            }
            output["versionId"] = versionID
        }
        return .object(output)
    })
}

private func elevenLabsStringArray(_ value: JSONValue, argument: String, maxCount: Int) throws -> JSONValue {
    guard let array = value.arrayValue, array.count <= maxCount else {
        throw AIError.invalidArgument(argument: argument, message: "ElevenLabs \(argument) must be an array of strings with at most \(maxCount) items.")
    }
    for item in array where item.stringValue == nil {
        throw AIError.invalidArgument(argument: argument, message: "ElevenLabs \(argument) values must be strings.")
    }
    return value
}

private func elevenLabsRequireString(_ value: JSONValue, argument: String, message: String) throws {
    guard value.stringValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private func elevenLabsRequireBoolean(_ value: JSONValue, argument: String, message: String) throws {
    guard value.boolValue != nil else {
        throw AIError.invalidArgument(argument: argument, message: message)
    }
}

private func elevenLabsIsInteger(_ value: Double) -> Bool {
    value.isFinite && value.rounded(.towardZero) == value
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
