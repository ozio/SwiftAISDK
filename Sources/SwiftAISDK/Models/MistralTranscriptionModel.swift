import Foundation

public final class MistralTranscriptionModel: TranscriptionModel, @unchecked Sendable {
    public let providerID = "mistral.transcription"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        let options = try mistralTranscriptionOptions(from: request)
        if options.language != nil, options.timestampGranularities != nil {
            throw AIError.invalidArgument(
                argument: "providerOptions",
                message: "providerOptions.mistral.language cannot be combined with providerOptions.mistral.timestampGranularities"
            )
        }

        var form = MultipartFormData()
        form.appendField(name: "model", value: modelID)
        form.appendFile(
            name: "file",
            fileName: "audio.\(mediaTypeToExtension(request.mimeType))",
            mimeType: request.mimeType,
            data: request.audio
        )
        var metadataBody: [String: JSONValue] = [
            "model": .string(modelID),
            "filename": .string("audio.\(mediaTypeToExtension(request.mimeType))"),
            "mime_type": .string(request.mimeType)
        ]
        if let language = options.language {
            form.appendField(name: "language", value: language)
            metadataBody["language"] = .string(language)
        }
        if let temperature = options.temperature {
            form.appendField(name: "temperature", value: String(temperature))
            metadataBody["temperature"] = .number(temperature)
        }
        if let granularities = options.timestampGranularities {
            metadataBody["timestamp_granularities"] = .array(granularities.map(JSONValue.string))
            for granularity in granularities {
                form.appendField(name: "timestamp_granularities", value: granularity)
            }
        }
        if let diarize = options.diarize {
            form.appendField(name: "diarize", value: String(diarize))
            metadataBody["diarize"] = .bool(diarize)
        }
        if let contextBias = options.contextBias {
            metadataBody["context_bias"] = .array(contextBias.map(JSONValue.string))
            for item in contextBias {
                form.appendField(name: "context_bias", value: item)
            }
        }

        let response = try await config.transport.send(config.rawRequest(
            path: "/audio/transcriptions",
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
        try validateMistralTranscriptionResponse(raw)
        let segments = standardTranscriptionSegments(from: raw)
        let metadata = mistralTranscriptionMetadata(from: raw)
        return TranscriptionResult(
            text: raw["text"]?.stringValue ?? "",
            rawValue: raw,
            segments: segments,
            language: raw["language"]?.stringValue,
            durationInSeconds: raw["usage"]?["prompt_audio_seconds"]?.doubleValue ?? transcriptionDuration(from: segments),
            providerMetadata: metadata.isEmpty ? [:] : ["mistral": .object(metadata)],
            requestMetadata: AIRequestMetadata(body: .object(metadataBody), headers: request.headers),
            responseMetadata: aiResponseMetadata(
                from: raw,
                response: response,
                modelID: raw["model"]?.stringValue ?? modelID
            )
        )
    }
}

private struct MistralTranscriptionOptions {
    var language: String?
    var temperature: Double?
    var timestampGranularities: [String]?
    var diarize: Bool?
    var contextBias: [String]?
}

private func mistralTranscriptionOptions(from request: AudioTranscriptionRequest) throws -> MistralTranscriptionOptions {
    var values: [String: JSONValue] = [:]
    if let nested = request.extraBody["mistral"]?.objectValue {
        values.merge(nested) { _, new in new }
    }
    if let nested = request.providerOptions["mistral"] {
        guard nested != .null else {
            return MistralTranscriptionOptions(language: request.language)
        }
        guard let object = nested.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.mistral", message: "Mistral provider options must be an object.")
        }
        values.merge(object) { _, new in new }
    }

    let language: String?
    if let value = values["language"], value != .null {
        guard let parsed = value.stringValue, !parsed.isEmpty else {
            throw AIError.invalidArgument(argument: "providerOptions.mistral.language", message: "Mistral language must be a non-empty string.")
        }
        language = parsed
    } else {
        language = request.language
    }
    let temperature: Double?
    if let value = values["temperature"], value != .null {
        guard let parsed = value.doubleValue else {
            throw AIError.invalidArgument(argument: "providerOptions.mistral.temperature", message: "Mistral temperature must be a number.")
        }
        temperature = parsed
    } else {
        temperature = nil
    }
    let granularities: [String]?
    if let value = values["timestampGranularities"], value != .null {
        guard let items = value.arrayValue, !items.isEmpty else {
            throw AIError.invalidArgument(argument: "providerOptions.mistral.timestampGranularities", message: "Mistral timestampGranularities must be a non-empty array containing segment or word.")
        }
        let parsed = items.compactMap(\.stringValue)
        guard parsed.count == items.count, parsed.allSatisfy({ ["segment", "word"].contains($0) }) else {
            throw AIError.invalidArgument(argument: "providerOptions.mistral.timestampGranularities", message: "Mistral timestampGranularities must be a non-empty array containing segment or word.")
        }
        granularities = parsed
    } else {
        granularities = nil
    }
    let diarize: Bool?
    if let value = values["diarize"], value != .null {
        guard let parsed = value.boolValue else {
            throw AIError.invalidArgument(argument: "providerOptions.mistral.diarize", message: "Mistral diarize must be a boolean.")
        }
        diarize = parsed
    } else {
        diarize = nil
    }
    let contextBias: [String]?
    if let value = values["contextBias"], value != .null {
        guard let items = value.arrayValue, items.count <= 100 else {
            throw AIError.invalidArgument(argument: "providerOptions.mistral.contextBias", message: "Mistral contextBias must contain at most 100 non-empty strings without commas or whitespace.")
        }
        let parsed = items.compactMap(\.stringValue)
        guard parsed.count == items.count, parsed.allSatisfy({ string in
            !string.isEmpty && string.rangeOfCharacter(from: .whitespacesAndNewlines) == nil && !string.contains(",")
        }) else {
            throw AIError.invalidArgument(argument: "providerOptions.mistral.contextBias", message: "Mistral contextBias must contain at most 100 non-empty strings without commas or whitespace.")
        }
        contextBias = parsed
    } else {
        contextBias = nil
    }
    return MistralTranscriptionOptions(
        language: language,
        temperature: temperature,
        timestampGranularities: granularities,
        diarize: diarize,
        contextBias: contextBias
    )
}

private func validateMistralTranscriptionResponse(_ raw: JSONValue) throws {
    guard raw["model"]?.stringValue != nil, raw["text"]?.stringValue != nil else {
        throw AIError.invalidResponse(provider: "mistral.transcription", message: "Mistral transcription response is invalid.")
    }
    if let language = raw["language"], language != .null, language.stringValue == nil {
        throw AIError.invalidResponse(provider: "mistral.transcription", message: "Mistral transcription response is invalid.")
    }
    if let segments = raw["segments"], segments != .null {
        guard let items = segments.arrayValue, items.allSatisfy({ item in
            guard item["text"]?.stringValue != nil,
                  item["start"]?.doubleValue != nil,
                  item["end"]?.doubleValue != nil
            else {
                return false
            }
            if let type = item["type"], type != .null, type.stringValue != "transcription_segment" {
                return false
            }
            if let score = item["score"], score != .null, score.doubleValue == nil {
                return false
            }
            if let speakerID = item["speaker_id"], speakerID != .null, speakerID.stringValue == nil {
                return false
            }
            return true
        }) else {
            throw AIError.invalidResponse(provider: "mistral.transcription", message: "Mistral transcription response is invalid.")
        }
    }
    if let usage = raw["usage"], usage != .null {
        guard usage.objectValue != nil else {
            throw AIError.invalidResponse(provider: "mistral.transcription", message: "Mistral transcription response is invalid.")
        }
        for key in [
            "prompt_tokens",
            "completion_tokens",
            "total_tokens",
            "prompt_audio_seconds",
            "request_count"
        ] {
            if let value = usage[key], value != .null, value.doubleValue == nil {
                throw AIError.invalidResponse(provider: "mistral.transcription", message: "Mistral transcription response is invalid.")
            }
        }
    }
}

private func mistralTranscriptionMetadata(from raw: JSONValue) -> [String: JSONValue] {
    var metadata: [String: JSONValue] = [:]
    if let usage = raw["usage"], usage != .null {
        var mapped: [String: JSONValue] = [:]
        for (source, target) in [
            ("prompt_tokens", "promptTokens"),
            ("completion_tokens", "completionTokens"),
            ("total_tokens", "totalTokens"),
            ("prompt_audio_seconds", "promptAudioSeconds"),
            ("request_count", "requestCount")
        ] where usage[source] != nil && usage[source] != .null {
            mapped[target] = usage[source]
        }
        metadata["usage"] = .object(mapped)
    }
    let richSegments = raw["segments"]?.arrayValue?.compactMap { item -> JSONValue? in
        guard item["type"] != nil || item["score"] != nil || item["speaker_id"] != nil else { return nil }
        var mapped: [String: JSONValue] = [
            "text": item["text"] ?? .string(""),
            "startSecond": item["start"] ?? .number(0),
            "endSecond": item["end"] ?? .number(0)
        ]
        if let type = item["type"], type != .null { mapped["type"] = type }
        if let score = item["score"], score != .null { mapped["score"] = score }
        if let speaker = item["speaker_id"], speaker != .null { mapped["speakerId"] = speaker }
        return .object(mapped)
    } ?? []
    if !richSegments.isEmpty {
        metadata["segments"] = .array(richSegments)
    }
    return metadata
}
