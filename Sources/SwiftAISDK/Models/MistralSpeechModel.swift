import Foundation

public final class MistralSpeechModel: SpeechModel, @unchecked Sendable {
    public let providerID = "mistral.speech"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config.withProviderID("mistral.speech")
    }

    public func speak(_ request: SpeechRequest) async throws -> SpeechResult {
        var warnings: [AIWarning] = []
        let options = try mistralSpeechProviderOptions(request)
        let outputFormat = mistralSpeechOutputFormat(request.format, warnings: &warnings)
        let refAudio = options["refAudio"]?.stringValue

        if request.instructions != nil {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "instructions",
                message: "Mistral speech models do not support the `instructions` option. Use a reference audio clip to guide delivery."
            ))
        }
        if request.speed != nil {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "speed",
                message: "Mistral speech models do not support the `speed` option. It was ignored."
            ))
        }
        if request.language != nil {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "language",
                message: "Mistral speech models do not support the `language` option. Language is inferred from the input text and voice."
            ))
        }

        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "input": .string(request.text),
            "response_format": .string(outputFormat),
            "stream": .bool(false)
        ]
        if let refAudio {
            body["ref_audio"] = .string(refAudio)
        } else if let voice = request.voice {
            body["voice_id"] = .string(voice)
        }

        let response = try await config.sendJSONResponse(
            path: "/audio/speech",
            modelID: modelID,
            body: .object(body),
            headers: request.headers,
            abortSignal: request.abortSignal
        )
        let raw = response.json
        guard let audioData = raw["audio_data"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "No Mistral audio_data found.")
        }
        let audio = Data(base64Encoded: audioData) ?? Data(audioData.utf8)
        return SpeechResult(
            audio: audio,
            contentType: "audio/\(outputFormat)",
            warnings: warnings,
            requestMetadata: AIRequestMetadata(body: .object(mistralSpeechMetadataBody(body)), headers: request.headers),
            responseMetadata: aiResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }
}

private let mistralSpeechFormats: Set<String> = ["pcm", "wav", "mp3", "flac", "opus"]

private func mistralSpeechOutputFormat(_ format: String?, warnings: inout [AIWarning]) -> String {
    guard let format else { return "mp3" }
    if mistralSpeechFormats.contains(format) {
        return format
    }
    warnings.append(AIWarning(
        type: "unsupported",
        feature: "outputFormat",
        message: "Unsupported output format: \(format). Using mp3 instead."
    ))
    return "mp3"
}

private func mistralSpeechProviderOptions(_ request: SpeechRequest) throws -> [String: JSONValue] {
    var output = mistralProviderOptions(from: request.extraBody)
    if let value = request.providerOptions["mistral"] {
        if value != .null {
            guard let nested = value.objectValue else {
                throw AIError.invalidArgument(argument: "providerOptions.mistral", message: "Mistral provider options must be an object.")
            }
            output.removeValue(forKey: "refAudio")
            output.merge(try mistralValidateSpeechProviderOptions(nested)) { _, nested in nested }
        }
    }
    return output
}

private func mistralValidateSpeechProviderOptions(_ options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    if let refAudio = options["refAudio"] {
        guard refAudio != .null else { return output }
        guard let value = refAudio.stringValue, !value.isEmpty else {
            throw AIError.invalidArgument(argument: "providerOptions.mistral.refAudio", message: "Mistral refAudio must be a non-empty string.")
        }
        output["refAudio"] = .string(value)
    }
    return output
}

private func mistralSpeechMetadataBody(_ body: [String: JSONValue]) -> [String: JSONValue] {
    var metadataBody = body
    if metadataBody["ref_audio"] != nil {
        metadataBody["ref_audio"] = .string("[redacted]")
    }
    return metadataBody
}
