import Foundation

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

private func lmntResponseFormat(_ outputFormat: String?) -> String {
    guard let outputFormat, ["mp3", "aac", "mulaw", "raw", "wav"].contains(outputFormat) else {
        return "mp3"
    }
    return outputFormat
}

