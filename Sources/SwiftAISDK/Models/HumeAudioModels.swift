import Foundation

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
            throw audioProviderHTTPStatusError(provider: providerID, response: response)
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
private func humeFormat(_ outputFormat: String?) -> String {
    guard let outputFormat, ["mp3", "pcm", "wav"].contains(outputFormat) else {
        return "mp3"
    }
    return outputFormat
}

