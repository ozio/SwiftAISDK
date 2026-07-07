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
        let warnings = assemblyAITranscriptionWarnings(modelID: modelID, options: options)
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

        var body: [String: JSONValue] = ["audio_url": .string(uploadURL)]
        if modelID == "best" {
            body["speech_model"] = .string(modelID)
        } else {
            body["speech_models"] = .array([.string(modelID)])
        }
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
            warnings: warnings,
            providerMetadata: assemblyAIProviderMetadata(from: raw),
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
    if let utterances = raw["utterances"], utterances != .null {
        guard let utteranceArray = utterances.arrayValue else {
            throw AIError.invalidResponse(provider: providerID, message: "AssemblyAI transcription result is invalid.")
        }
        for utterance in utteranceArray {
            guard
                utterance["start"]?.doubleValue != nil,
                utterance["end"]?.doubleValue != nil,
                utterance["text"]?.stringValue != nil
            else {
                throw AIError.invalidResponse(provider: providerID, message: "AssemblyAI transcription result is invalid.")
            }
        }
    }
}

private func assemblyAITranscriptionOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = mapKeys(extraBody, [
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
        "keytermsPrompt": "keyterms_prompt",
        "multichannel": "multichannel",
        "prompt": "prompt",
        "punctuate": "punctuate",
        "redactPii": "redact_pii",
        "redactPiiAudio": "redact_pii_audio",
        "redactPiiReturnUnredacted": "redact_pii_return_unredacted",
        "redactPiiAudioQuality": "redact_pii_audio_quality",
        "redactPiiPolicies": "redact_pii_policies",
        "redactPiiSub": "redact_pii_sub",
        "redactStaticEntities": "redact_static_entities",
        "removeAudioTags": "remove_audio_tags",
        "sentimentAnalysis": "sentiment_analysis",
        "speakerLabels": "speaker_labels",
        "speakersExpected": "speakers_expected",
        "speechThreshold": "speech_threshold",
        "summarization": "summarization",
        "summaryModel": "summary_model",
        "summaryType": "summary_type",
        "temperature": "temperature",
        "webhookAuthHeaderName": "webhook_auth_header_name",
        "webhookAuthHeaderValue": "webhook_auth_header_value",
        "webhookUrl": "webhook_url",
        "wordBoost": "word_boost"
    ])
    if let speakerOptions = extraBody["speakerOptions"]?.objectValue {
        output["speaker_options"] = .object(mapKeys(speakerOptions, [
            "minSpeakersExpected": "min_speakers_expected",
            "maxSpeakersExpected": "max_speakers_expected"
        ]))
    }
    if let languageDetectionOptions = extraBody["languageDetectionOptions"]?.objectValue {
        output["language_detection_options"] = .object(mapKeys(languageDetectionOptions, [
            "expectedLanguages": "expected_languages",
            "fallbackLanguage": "fallback_language",
            "codeSwitching": "code_switching",
            "codeSwitchingConfidenceThreshold": "code_switching_confidence_threshold"
        ]))
    }
    if let redactPiiAudioOptions = extraBody["redactPiiAudioOptions"]?.objectValue {
        output["redact_pii_audio_options"] = .object(mapKeys(redactPiiAudioOptions, [
            "returnRedactedNoSpeechAudio": "return_redacted_no_speech_audio",
            "overrideAudioRedactionMethod": "override_audio_redaction_method"
        ]))
    }
    return output
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
        case "domain", "prompt":
            try assemblyAIRequireString(value, argument: "providerOptions.assemblyai.\(key)", message: "AssemblyAI \(key) must be a string.")
            output[key] = value
        case "removeAudioTags":
            guard let string = value.stringValue, ["all", "speaker"].contains(string) else {
                throw AIError.invalidArgument(argument: "providerOptions.assemblyai.removeAudioTags", message: "AssemblyAI removeAudioTags must be `all` or `speaker`.")
            }
            output[key] = value
        case "languageConfidenceThreshold":
            try assemblyAIRequireNumber(value, argument: "providerOptions.assemblyai.languageConfidenceThreshold", message: "AssemblyAI languageConfidenceThreshold must be a number.")
            output[key] = value
        case "temperature":
            guard let number = value.doubleValue, number >= 0, number <= 1 else {
                throw AIError.invalidArgument(argument: "providerOptions.assemblyai.temperature", message: "AssemblyAI temperature must be a number between 0 and 1.")
            }
            output[key] = value
        case "speechThreshold":
            guard let number = value.doubleValue, number >= 0, number <= 1 else {
                throw AIError.invalidArgument(argument: "providerOptions.assemblyai.speechThreshold", message: "AssemblyAI speechThreshold must be a number between 0 and 1.")
            }
            output[key] = value
        case "keytermsPrompt", "redactPiiPolicies", "wordBoost":
            output[key] = try assemblyAIStringArray(value, argument: "providerOptions.assemblyai.\(key)")
        case "customSpelling":
            output[key] = try assemblyAIValidatedCustomSpelling(value)
        case "speakerOptions":
            output[key] = try assemblyAIValidatedSpeakerOptions(value)
        case "languageDetectionOptions":
            output[key] = try assemblyAIValidatedLanguageDetectionOptions(value)
        case "redactPiiAudioOptions":
            output[key] = try assemblyAIValidatedRedactPiiAudioOptions(value)
        case "redactPiiReturnUnredacted":
            try assemblyAIRequireBoolean(value, argument: "providerOptions.assemblyai.redactPiiReturnUnredacted", message: "AssemblyAI redactPiiReturnUnredacted must be a boolean.")
            output[key] = value
        case "redactStaticEntities":
            output[key] = try assemblyAIValidatedStaticEntities(value)
        default:
            break
        }
    }
    return output
}

private func assemblyAITranscriptionWarnings(modelID: String, options: [String: JSONValue]) -> [AIWarning] {
    var warnings: [AIWarning] = []
    let modelDocsURL = "https://www.assemblyai.com/docs/pre-recorded-audio/select-the-speech-model"
    if modelID == "best" {
        warnings.append(AIWarning(
            type: "deprecated",
            setting: "model 'best'",
            message: "The 'best' model is a legacy AssemblyAI model. Use 'universal-3-5-pro' instead. See documentation: \(modelDocsURL)"
        ))
    } else if modelID == "universal-3-pro" {
        warnings.append(AIWarning(
            type: "other",
            message: "'universal-3-5-pro' is AssemblyAI's latest flagship model and is set to replace 'universal-3-pro'. See \(modelDocsURL)"
        ))
    } else if modelID == "universal-2" {
        warnings.append(AIWarning(
            type: "other",
            message: "'universal-3-5-pro' is AssemblyAI's latest flagship model. See \(modelDocsURL)"
        ))
    }

    var deprecatedBoostOptions: [String] = []
    if options["wordBoost"] != nil { deprecatedBoostOptions.append("wordBoost") }
    if options["boostParam"] != nil { deprecatedBoostOptions.append("boostParam") }
    if !deprecatedBoostOptions.isEmpty {
        warnings.append(AIWarning(
            type: "deprecated",
            setting: deprecatedBoostOptions.joined(separator: ", "),
            message: "'wordBoost' and 'boostParam' are deprecated and are rejected by 'universal-3-pro' / 'universal-3-5-pro' and 'slam-1'. Use 'keytermsPrompt' instead."
        ))
    }

    if (options["redactPiiReturnUnredacted"] != nil || options["redactStaticEntities"] != nil),
       options["redactPii"]?.boolValue != true {
        warnings.append(AIWarning(
            type: "other",
            message: "'redactPiiReturnUnredacted' and 'redactStaticEntities' require 'redactPii' to be enabled; AssemblyAI rejects the request otherwise."
        ))
    }
    if options["redactPiiAudioOptions"] != nil,
       options["redactPiiAudio"]?.boolValue != true {
        warnings.append(AIWarning(
            type: "other",
            message: "'redactPiiAudioOptions' only applies when 'redactPiiAudio' is enabled; it is otherwise ignored."
        ))
    }
    if options["languageCode"] != nil,
       options["languageDetection"]?.boolValue == true {
        warnings.append(AIWarning(
            type: "other",
            message: "'languageDetection' cannot be combined with an explicit 'languageCode'; AssemblyAI rejects requests that set both."
        ))
    }
    return warnings
}

private func assemblyAIProviderMetadata(from raw: JSONValue) -> [String: JSONValue] {
    var metadata: [String: JSONValue] = [:]
    if let utterances = raw["utterances"], utterances != .null {
        metadata["utterances"] = utterances
    }
    if let sentiment = raw["sentiment_analysis_results"], sentiment != .null {
        metadata["sentimentAnalysisResults"] = sentiment
    }
    if let entities = raw["entities"], entities != .null {
        metadata["entities"] = entities
    }
    if let contentSafety = raw["content_safety_labels"], contentSafety != .null {
        metadata["contentSafetyLabels"] = contentSafety
    }
    if let iab = raw["iab_categories_result"], iab != .null {
        metadata["iabCategoriesResult"] = iab
    }
    if let highlights = raw["auto_highlights_result"], highlights != .null {
        metadata["autoHighlightsResult"] = highlights
    }
    guard !metadata.isEmpty else { return [:] }
    return ["assemblyai": .object(metadata)]
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

private func assemblyAIValidatedSpeakerOptions(_ value: JSONValue) throws -> JSONValue {
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.assemblyai.speakerOptions", message: "AssemblyAI speakerOptions must be an object.")
    }
    var output: [String: JSONValue] = [:]
    for key in ["minSpeakersExpected", "maxSpeakersExpected"] {
        guard let item = object[key], item != .null else { continue }
        try assemblyAIRequireInteger(item, argument: "providerOptions.assemblyai.speakerOptions.\(key)", message: "AssemblyAI speakerOptions.\(key) must be an integer.")
        output[key] = item
    }
    return .object(output)
}

private func assemblyAIValidatedLanguageDetectionOptions(_ value: JSONValue) throws -> JSONValue {
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.assemblyai.languageDetectionOptions", message: "AssemblyAI languageDetectionOptions must be an object.")
    }
    var output: [String: JSONValue] = [:]
    if let expected = object["expectedLanguages"], expected != .null {
        output["expectedLanguages"] = try assemblyAIStringArray(expected, argument: "providerOptions.assemblyai.languageDetectionOptions.expectedLanguages")
    }
    if let fallback = object["fallbackLanguage"], fallback != .null {
        try assemblyAIRequireString(fallback, argument: "providerOptions.assemblyai.languageDetectionOptions.fallbackLanguage", message: "AssemblyAI languageDetectionOptions.fallbackLanguage must be a string.")
        output["fallbackLanguage"] = fallback
    }
    if let codeSwitching = object["codeSwitching"], codeSwitching != .null {
        try assemblyAIRequireBoolean(codeSwitching, argument: "providerOptions.assemblyai.languageDetectionOptions.codeSwitching", message: "AssemblyAI languageDetectionOptions.codeSwitching must be a boolean.")
        output["codeSwitching"] = codeSwitching
    }
    if let threshold = object["codeSwitchingConfidenceThreshold"], threshold != .null {
        guard let number = threshold.doubleValue, number >= 0, number <= 1 else {
            throw AIError.invalidArgument(argument: "providerOptions.assemblyai.languageDetectionOptions.codeSwitchingConfidenceThreshold", message: "AssemblyAI languageDetectionOptions.codeSwitchingConfidenceThreshold must be a number between 0 and 1.")
        }
        output["codeSwitchingConfidenceThreshold"] = threshold
    }
    return .object(output)
}

private func assemblyAIValidatedRedactPiiAudioOptions(_ value: JSONValue) throws -> JSONValue {
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.assemblyai.redactPiiAudioOptions", message: "AssemblyAI redactPiiAudioOptions must be an object.")
    }
    var output: [String: JSONValue] = [:]
    if let returnAudio = object["returnRedactedNoSpeechAudio"], returnAudio != .null {
        try assemblyAIRequireBoolean(returnAudio, argument: "providerOptions.assemblyai.redactPiiAudioOptions.returnRedactedNoSpeechAudio", message: "AssemblyAI redactPiiAudioOptions.returnRedactedNoSpeechAudio must be a boolean.")
        output["returnRedactedNoSpeechAudio"] = returnAudio
    }
    if let method = object["overrideAudioRedactionMethod"], method != .null {
        guard method.stringValue == "silence" else {
            throw AIError.invalidArgument(argument: "providerOptions.assemblyai.redactPiiAudioOptions.overrideAudioRedactionMethod", message: "AssemblyAI redactPiiAudioOptions.overrideAudioRedactionMethod must be `silence`.")
        }
        output["overrideAudioRedactionMethod"] = method
    }
    return .object(output)
}

private func assemblyAIValidatedStaticEntities(_ value: JSONValue) throws -> JSONValue {
    guard let object = value.objectValue else {
        throw AIError.invalidArgument(argument: "providerOptions.assemblyai.redactStaticEntities", message: "AssemblyAI redactStaticEntities must be an object.")
    }
    var output: [String: JSONValue] = [:]
    for (key, item) in object {
        output[key] = try assemblyAIStringArray(item, argument: "providerOptions.assemblyai.redactStaticEntities.\(key)")
    }
    return .object(output)
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
    "domain",
    "entityDetection",
    "filterProfanity",
    "formatText",
    "iabCategories",
    "keytermsPrompt",
    "languageCode",
    "languageConfidenceThreshold",
    "languageDetection",
    "languageDetectionOptions",
    "multichannel",
    "prompt",
    "punctuate",
    "redactPii",
    "redactPiiAudio",
    "redactPiiAudioOptions",
    "redactPiiAudioQuality",
    "redactPiiPolicies",
    "redactPiiReturnUnredacted",
    "redactPiiSub",
    "redactStaticEntities",
    "removeAudioTags",
    "sentimentAnalysis",
    "speakerLabels",
    "speakerOptions",
    "speakersExpected",
    "speechThreshold",
    "summarization",
    "summaryModel",
    "summaryType",
    "temperature",
    "webhookAuthHeaderName",
    "webhookAuthHeaderValue",
    "webhookUrl",
    "wordBoost"
]
