import Foundation

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
            throw audioProviderHTTPStatusError(provider: providerID, response: uploadResponse)
        }
        let uploadRaw = try uploadResponse.jsonValue()
        guard let uploadURL = uploadRaw["upload_url"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "AssemblyAI upload response did not contain upload_url.")
        }

        var body: [String: JSONValue] = [
            "speech_models": .array([.string(modelID)]),
            "audio_url": .string(uploadURL)
        ]
        if let language = request.language { body["language_code"] = .string(language) }
        body.merge(assemblyAITranscriptionOptions(from: options)) { _, new in new }

        let submitResponse = try await config.transport.send(config.request(
            path: "/v2/transcript",
            modelID: modelID,
            body: .object(body),
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(submitResponse.statusCode) else {
            throw audioProviderHTTPStatusError(provider: providerID, response: submitResponse)
        }
        let submitRaw = try submitResponse.jsonValue()
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
                throw audioProviderHTTPStatusError(provider: providerID, response: response)
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
