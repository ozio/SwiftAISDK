import Foundation

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
            throw audioProviderHTTPStatusError(provider: providerID, response: uploadResponse)
        }
        let uploadRaw = try uploadResponse.jsonValue()
        guard let audioURL = uploadRaw["audio_url"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Gladia upload response did not contain audio_url.")
        }

        var body: [String: JSONValue] = ["audio_url": .string(audioURL)]
        body.merge(gladiaTranscriptionOptions(from: options)) { _, new in new }
        let initResponse = try await config.transport.send(config.request(
            path: "/v2/pre-recorded",
            modelID: modelID,
            body: .object(body),
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(initResponse.statusCode) else {
            throw audioProviderHTTPStatusError(provider: providerID, response: initResponse)
        }
        let initRaw = try initResponse.jsonValue()
        guard let resultURL = initRaw["result_url"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Gladia initiation response did not contain result_url.")
        }

        let finalResponse = try await pollGladiaResultResponse(url: resultURL, request: request)
        let raw = finalResponse.json
        guard raw["status"]?.stringValue != "error" else {
            throw AIError.invalidResponse(provider: providerID, message: "Transcription job failed")
        }
        try validateGladiaTranscriptionResult(raw, providerID: providerID)
        guard raw["result"]?.objectValue != nil else {
            throw AIError.invalidResponse(provider: providerID, message: "Transcription result is empty")
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
                throw AIError.invalidResponse(provider: providerID, message: "Transcription job polling timed out")
            }
            let pollHeaders = isSameOrigin(url, config.baseURL) ? config.headers.mergingHeaders(request.headers) : [:]
            let response = try await downloadURL(url, transport: config.transport, headers: pollHeaders, abortSignal: request.abortSignal)
            guard (200..<300).contains(response.statusCode) else {
                throw audioProviderHTTPStatusError(provider: providerID, response: response)
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
