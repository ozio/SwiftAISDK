import Foundation

public final class GroqTranscriptionModel: TranscriptionModel, @unchecked Sendable {
    public let providerID = "groq.transcription"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        var form = MultipartFormData()
        form.appendField(name: "model", value: modelID)
        let uploadFileName = "audio.\(mediaTypeToExtension(request.mimeType))"
        form.appendFile(name: "file", fileName: uploadFileName, mimeType: request.mimeType, data: request.audio)
        var metadataBody: [String: JSONValue] = [
            "model": .string(modelID),
            "filename": .string(uploadFileName),
            "mime_type": .string(request.mimeType)
        ]
        if let language = request.language {
            form.appendField(name: "language", value: language)
            metadataBody["language"] = .string(language)
        }
        if let prompt = request.prompt {
            form.appendField(name: "prompt", value: prompt)
            metadataBody["prompt"] = .string(prompt)
        }

        let providerOptions = try groqTranscriptionOptions(from: request)
        if let language = providerOptions["language"]?.stringValue, request.language == nil {
            form.appendField(name: "language", value: language)
            metadataBody["language"] = .string(language)
        }
        if let prompt = providerOptions["prompt"]?.stringValue, request.prompt == nil {
            form.appendField(name: "prompt", value: prompt)
            metadataBody["prompt"] = .string(prompt)
        }

        for (key, value) in providerOptions where key != "language" && key != "prompt" {
            if case let .array(items) = value {
                metadataBody[key] = value
                for item in items {
                    if let scalar = jsonScalarString(item) {
                        form.appendField(name: "\(key)[]", value: scalar)
                    }
                }
            } else if let scalar = jsonScalarString(value) {
                form.appendField(name: key, value: scalar)
                metadataBody[key] = value
            }
        }

        let body = form.finalize()
        let response = try await config.transport.send(config.rawRequest(
            path: "/audio/transcriptions",
            modelID: modelID,
            body: body,
            contentType: "multipart/form-data; boundary=\(form.boundary)",
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        guard let text = raw["text"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "No transcription text found.")
        }
        try validateGroqTranscriptionResponse(raw)
        let segments = standardTranscriptionSegments(from: raw)
        return TranscriptionResult(
            text: text,
            rawValue: raw,
            segments: segments,
            language: raw["language"]?.stringValue,
            durationInSeconds: raw["duration"]?.doubleValue ?? transcriptionDuration(from: segments),
            requestMetadata: AIRequestMetadata(body: .object(metadataBody), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response, modelID: modelID)
        )
    }
}

func validateGroqTranscriptionResponse(_ raw: JSONValue) throws {
    guard raw["x_groq"]?["id"]?.stringValue != nil else {
        throw AIError.invalidResponse(provider: "groq.transcription", message: "Groq transcription response is invalid.")
    }
    if let task = raw["task"], task != .null, task.stringValue == nil {
        throw AIError.invalidResponse(provider: "groq.transcription", message: "Groq transcription response is invalid.")
    }
    if let language = raw["language"], language != .null, language.stringValue == nil {
        throw AIError.invalidResponse(provider: "groq.transcription", message: "Groq transcription response is invalid.")
    }
    if let duration = raw["duration"], duration != .null, duration.doubleValue == nil {
        throw AIError.invalidResponse(provider: "groq.transcription", message: "Groq transcription response is invalid.")
    }
    guard let segments = raw["segments"] else { return }
    guard segments != .null else { return }
    guard let array = segments.arrayValue else {
        throw AIError.invalidResponse(provider: "groq.transcription", message: "Groq transcription response is invalid.")
    }
    for segment in array {
        guard
            segment["id"]?.doubleValue != nil,
            segment["seek"]?.doubleValue != nil,
            segment["start"]?.doubleValue != nil,
            segment["end"]?.doubleValue != nil,
            segment["text"]?.stringValue != nil,
            let tokens = segment["tokens"]?.arrayValue,
            segment["temperature"]?.doubleValue != nil,
            segment["avg_logprob"]?.doubleValue != nil,
            segment["compression_ratio"]?.doubleValue != nil,
            segment["no_speech_prob"]?.doubleValue != nil
        else {
            throw AIError.invalidResponse(provider: "groq.transcription", message: "Groq transcription response is invalid.")
        }
        guard tokens.allSatisfy({ $0.doubleValue != nil }) else {
            throw AIError.invalidResponse(provider: "groq.transcription", message: "Groq transcription response is invalid.")
        }
    }
}
