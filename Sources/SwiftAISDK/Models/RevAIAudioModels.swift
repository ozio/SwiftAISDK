import Foundation

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
            throw audioProviderHTTPStatusError(provider: providerID, response: submitResponse)
        }
        var job = try submitResponse.jsonValue()
        try validateRevAIJobResponse(job, providerID: providerID)
        if job["status"]?.stringValue == "failed" {
            throw AIError.invalidResponse(provider: providerID, message: "Failed to submit transcription job to Rev.ai")
        }
        guard let jobID = job["id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Rev.ai job response did not contain id.")
        }
        let submissionLanguage = job["language"]?.stringValue
        job = try await pollRevAIJob(id: jobID, initial: job, request: request)
        let transcriptResponse = try await config.transport.send(try getRequest(
            path: "/speechtotext/v1/jobs/\(jobID)/transcript",
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(transcriptResponse.statusCode) else {
            throw audioProviderHTTPStatusError(provider: providerID, response: transcriptResponse)
        }
        let raw = try transcriptResponse.jsonValue()
        try validateRevAITranscriptResponse(raw, providerID: providerID)
        let segments = revAITranscriptionSegments(from: raw)
        return TranscriptionResult(
            text: revAITranscriptText(from: raw),
            rawValue: raw,
            segments: segments,
            language: submissionLanguage,
            durationInSeconds: transcriptionDuration(from: segments) ?? 0,
            responseMetadata: aiResponseMetadata(from: raw, response: transcriptResponse, modelID: modelID)
        )
    }

    private func pollRevAIJob(id: String, initial: JSONValue, request: AudioTranscriptionRequest) async throws -> JSONValue {
        var job = initial
        let started = DispatchTime.now().uptimeNanoseconds
        while job["status"]?.stringValue != "transcribed" {
            if DispatchTime.now().uptimeNanoseconds - started > 60_000_000_000 {
                throw AIError.invalidResponse(provider: providerID, message: "Transcription job polling timed out")
            }
            let response = try await config.transport.send(try getRequest(
                path: "/speechtotext/v1/jobs/\(id)",
                headers: request.headers,
                abortSignal: request.abortSignal
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw audioProviderHTTPStatusError(provider: providerID, response: response)
            }
            job = try response.jsonValue()
            try validateRevAIJobResponse(job, providerID: providerID)
            if job["status"]?.stringValue == "failed" {
                throw AIError.invalidResponse(provider: providerID, message: "Transcription job failed")
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

private func validateRevAIJobResponse(_ raw: JSONValue, providerID: String) throws {
    if let id = raw["id"], id != .null, id.stringValue == nil {
        throw AIError.invalidResponse(provider: providerID, message: "Rev.ai job response is invalid.")
    }
    if let status = raw["status"], status != .null, status.stringValue == nil {
        throw AIError.invalidResponse(provider: providerID, message: "Rev.ai job response is invalid.")
    }
    if let language = raw["language"], language != .null, language.stringValue == nil {
        throw AIError.invalidResponse(provider: providerID, message: "Rev.ai job response is invalid.")
    }
}

private func validateRevAITranscriptResponse(_ raw: JSONValue, providerID: String) throws {
    guard let monologues = raw["monologues"] else { return }
    guard monologues != .null else { return }
    guard let monologueArray = monologues.arrayValue else {
        throw AIError.invalidResponse(provider: providerID, message: "Rev.ai transcription response is invalid.")
    }
    for monologue in monologueArray {
        guard let object = monologue.objectValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Rev.ai transcription response is invalid.")
        }
        guard let elements = object["elements"] else { continue }
        guard elements != .null else { continue }
        guard let elementArray = elements.arrayValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Rev.ai transcription response is invalid.")
        }
        for element in elementArray {
            guard let elementObject = element.objectValue else {
                throw AIError.invalidResponse(provider: providerID, message: "Rev.ai transcription response is invalid.")
            }
            if let type = elementObject["type"], type != .null, type.stringValue == nil {
                throw AIError.invalidResponse(provider: providerID, message: "Rev.ai transcription response is invalid.")
            }
            if let value = elementObject["value"], value != .null, value.stringValue == nil {
                throw AIError.invalidResponse(provider: providerID, message: "Rev.ai transcription response is invalid.")
            }
            if let timestamp = elementObject["ts"], timestamp != .null, timestamp.doubleValue == nil {
                throw AIError.invalidResponse(provider: providerID, message: "Rev.ai transcription response is invalid.")
            }
            if let endTimestamp = elementObject["end_ts"], endTimestamp != .null, endTimestamp.doubleValue == nil {
                throw AIError.invalidResponse(provider: providerID, message: "Rev.ai transcription response is invalid.")
            }
        }
    }
}

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

private func revAITranscriptText(from raw: JSONValue) -> String {
    raw["monologues"]?.arrayValue?.map { monologue in
        monologue["elements"]?.arrayValue?.compactMap { $0["value"]?.stringValue }.joined() ?? ""
    }.joined(separator: " ") ?? ""
}

