import Foundation

public struct AzureOpenAIAudioSettings: Sendable {
    public var speechBaseURL: String?
    public var maiBaseURL: String?
    public var webSocketTransport: any AIDuplexWebSocketTransport

    public init(speechBaseURL: String? = nil, maiBaseURL: String? = nil,
                webSocketTransport: any AIDuplexWebSocketTransport = URLSessionDuplexWebSocketTransport.shared) {
        self.speechBaseURL = speechBaseURL
        self.maiBaseURL = maiBaseURL
        self.webSocketTransport = webSocketTransport
    }
}

struct AzureAudioConfig: Sendable {
    var resourceName: String?
    var settings: AzureOpenAIAudioSettings
    var apiKey: String?
    var headers: [String: String]
    var transport: any AITransport
    var tokenProvider: AzureOpenAITokenProvider?

    func baseURL(api: String) throws -> String {
        if let configured = api == "speech" ? settings.speechBaseURL : settings.maiBaseURL {
            return withoutTrailingSlash(configured)
        }
        guard let resourceName else {
            throw AIError.invalidArgument(argument: "resourceName", message: "Azure \(api) audio requires resourceName or its own base URL.")
        }
        try validateHostnamePart(resourceName, argument: "resourceName")
        return api == "speech" ? "https://\(resourceName).cognitiveservices.azure.com" : "https://\(resourceName).services.ai.azure.com/mai/v1"
    }

    func requestHeaders(api: String) -> [String: String] {
        let authentication = tokenProvider == nil ? apiKey.map { [api == "speech" ? "Ocp-Apim-Subscription-Key" : "api-key": $0] } ?? [:] : [:]
        return withUserAgentSuffix(authentication.mergingHeaders(headers), "ai-sdk-azure/4.0.90")
    }
}

public final class AzureSpeechModel: SpeechModel, @unchecked Sendable {
    public let providerID = "azure.speech"
    public let modelID: String
    private let openAI: any SpeechModel
    private let config: AzureAudioConfig

    init(modelID: String, openAI: any SpeechModel, config: AzureAudioConfig) {
        self.modelID = modelID; self.openAI = openAI; self.config = config
    }

    public func speak(_ request: SpeechRequest) async throws -> SpeechResult {
        let options = try azureAudioOptions(request.providerOptions, transcription: false)
        let model = azureVoiceModels[modelID.lowercased()]
        let api = options["api"]?.stringValue ?? (model == nil ? "openai" : "speech")
        if api == "openai" {
            var result = try await openAI.speak(request)
            result.warnings += azureAudioUnusedOptions(options.filter { $0.key != "api" }, api: "Speech")
            return result
        }
        var warnings: [AIWarning] = []
        if request.instructions != nil {
            warnings.append(AIWarning(type: "unsupported", feature: "instructions", message: "Use providerOptions.azure.style to control speaking style."))
        }
        let language = request.language?.split(separator: "-").first.map { $0.lowercased() }
        let voice = request.voice ?? language.flatMap { azureDefaultVoices[$0] } ?? "en-US-Harper"
        if request.voice == nil, let language, azureDefaultVoices[language] == nil {
            warnings.append(AIWarning(type: "unsupported", feature: "language", message: language == "auto"
                ? "Automatic language detection is not supported. en-US-Harper was used."
                : "No default MAI voice for language \"\(request.language ?? language)\". en-US-Harper was used."))
        } else if request.voice != nil, let language, language != "auto",
                  let voiceLanguage = azureVoiceLocale(voice)?.split(separator: "-").first?.lowercased(), language != voiceLanguage {
            warnings.append(AIWarning(type: "unsupported", feature: "language", message: "The voice \(voice) selects the language. Language \"\(request.language ?? language)\" was ignored."))
        }
        let style = options["style"]?.stringValue
        let degree = options["styleDegree"]?.doubleValue
        if degree != nil, style == nil {
            warnings.append(AIWarning(type: "unsupported", feature: "providerOptions.azure.styleDegree", message: "styleDegree requires style."))
        }
        let formats = ["mp3": "audio-24khz-160kbitrate-mono-mp3", "opus": "ogg-24khz-16bit-mono-opus", "pcm": "raw-24khz-16bit-mono-pcm", "wav": "riff-24khz-16bit-mono-pcm"]
        var outputFormat = formats["mp3"]!
        if let requested = request.format {
            let format = requested.lowercased()
            if let mapped = formats[format] { outputFormat = mapped }
            else if format.range(of: #"^(?:amr|audio|g722|ogg|raw|riff|webm)-[a-z0-9-]+$"#, options: .regularExpression)?.upperBound == format.endIndex { outputFormat = format }
            else { warnings.append(AIWarning(type: "unsupported", feature: "outputFormat", message: "Unsupported output format: \(requested). Using mp3 instead.")) }
        }
        let voiceName = voice.contains(":") ? voice : "\(voice):\(model ?? modelID)"
        var content = azureEscapeXML(request.text)
        if let speed = request.speed { content = "<prosody rate=\"\(azureAudioNumber(speed))\">\(content)</prosody>" }
        if let style {
            let intensity = degree.map { " styledegree=\"\(azureAudioNumber($0))\"" } ?? ""
            content = "<mstts:express-as style=\"\(azureEscapeXML(style))\"\(intensity)>\(content)</mstts:express-as>"
        }
        let ssml = "<speak version=\"1.0\" xmlns=\"http://www.w3.org/2001/10/synthesis\" xmlns:mstts=\"http://www.w3.org/2001/mstts\" xml:lang=\"\(azureEscapeXML(azureVoiceLocale(voice) ?? "en-US"))\"><voice name=\"\(azureEscapeXML(voiceName))\">\(content)</voice></speak>"
        let url = try requireURL(config.baseURL(api: "speech") + "/tts/cognitiveservices/v1")
        let headers = config.requestHeaders(api: "speech").mergingHeaders(["Content-Type": "application/ssml+xml", "X-Microsoft-OutputFormat": outputFormat]).mergingHeaders(request.headers)
        let response = try await config.transport.send(AIHTTPRequest(method: "POST", url: url, headers: headers, body: Data(ssml.utf8), abortSignal: request.abortSignal))
        guard (200..<300).contains(response.statusCode) else {
            let voiceReset = response.statusCode == 502 && response.bodyText.contains("reset reason: protocol error")
            let message = (try? response.jsonValue())?["error"]?["message"]?.stringValue
                ?? (voiceReset ? "Azure Speech could not synthesize the request. Check that the voice is available for this model and that the style is supported by the voice."
                    : response.statusCode == 400 ? "Azure Speech request failed with status 400. Check the voice name, style, and output format."
                    : "Azure Speech request failed with status \(response.statusCode).")
            var error = AIAPICallError(provider: providerID, url: url.absoluteString, requestBody: .string(ssml), statusCode: response.statusCode,
                                      responseHeaders: response.headers, responseBody: response.bodyText, isRetryable: voiceReset ? false : nil)
            error.message = message
            throw AIError.apiCall(error)
        }
        return SpeechResult(audio: response.body, contentType: response.headers.contentType, warnings: warnings,
                            requestMetadata: AIRequestMetadata(body: .string(ssml), headers: request.headers),
                            responseMetadata: aiResponseMetadata(response: response, modelID: modelID))
    }
}

public final class AzureTranscriptionModel: TranscriptionModel, StreamingTranscriptionModel, @unchecked Sendable {
    public let providerID = "azure.transcription"
    public let modelID: String
    let openAI: any TranscriptionModel
    let config: AzureAudioConfig

    init(modelID: String, openAI: any TranscriptionModel, config: AzureAudioConfig) {
        self.modelID = modelID; self.openAI = openAI; self.config = config
    }

    func api(for options: [String: JSONValue]) -> String {
        options["api"]?.stringValue ?? (modelID.lowercased() == "mai-transcribe-2-streaming" ? "mai" : azureTranscribeModels[modelID.lowercased()] != nil ? "speech" : "openai")
    }

    public func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        let options = try azureAudioOptions(request.providerOptions, transcription: true)
        let api = api(for: options)
        if api == "mai" { throw AIError.invalidArgument(argument: "model", message: "File transcription with \(modelID) is unsupported; use streaming transcription.") }
        let speechOptions = options.filter { !["api", "language"].contains($0.key) }
        if api == "openai" {
            var result = try await openAI.transcribe(request)
            result.warnings += azureAudioUnusedOptions(speechOptions, api: "Speech")
            if options["language"] != nil { result.warnings += azureAudioUnusedOptions(["language": options["language"]!], api: "MAI streaming transcription") }
            return result
        }
        let model = azureTranscribeModels[modelID.lowercased()]
        var modelOptions = speechOptions.filter { ["timestamps", "transcribeStyle"].contains($0.key) }
        if modelOptions["timestamps"] == nil, modelID.lowercased() != "mai-transcribe-1.5" { modelOptions["timestamps"] = "segment" }
        var definition: [String: JSONValue] = ["enhancedMode": .object(["enabled": true, "model": .string(model ?? modelID), "modelOptions": .object(modelOptions)])]
        for key in ["locales", "diarization", "phraseList"] { definition[key] = speechOptions[key] }
        var form = MultipartFormData()
        form.appendFile(name: "audio", fileName: "audio.\(mediaTypeToExtension(request.mimeType))", mimeType: request.mimeType, data: request.audio)
        form.appendField(name: "definition", value: String(decoding: try encodeJSONBody(.object(definition)), as: UTF8.self))
        let url = try requireURL(config.baseURL(api: "speech") + "/speechtotext/transcriptions:transcribe?api-version=2025-10-15")
        let headers = config.requestHeaders(api: "speech").mergingHeaders(["Content-Type": "multipart/form-data; boundary=\(form.boundary)"]).mergingHeaders(request.headers)
        let response = try await config.transport.send(AIHTTPRequest(method: "POST", url: url, headers: headers, body: form.finalize(), abortSignal: request.abortSignal))
        guard (200..<300).contains(response.statusCode) else { throw apiCallError(provider: providerID, response: response) }
        let raw = try response.jsonValue()
        guard let combined = raw["combinedPhrases"]?.arrayValue, combined.allSatisfy({ $0["text"]?.stringValue != nil }),
              raw["phrases"] == nil || raw["phrases"] == .null || raw["phrases"]?.arrayValue != nil else {
            throw AIError.invalidResponse(provider: providerID, message: "Invalid Azure Speech transcription response.")
        }
        let phrases = raw["phrases"]?.arrayValue ?? []
        guard azureNullableNumber(raw["durationMilliseconds"]), phrases.allSatisfy(azureValidTranscriptionPhrase) else {
            throw AIError.invalidResponse(provider: providerID, message: "Invalid Azure Speech phrases or duration.")
        }
        let normalizedPhrases = phrases.map { phrase -> JSONValue in
            var fields = (phrase.objectValue ?? [:]).filter { ["text", "offsetMilliseconds", "durationMilliseconds", "locale", "speaker", "confidence", "words"].contains($0.key) }
            if let words = fields["words"]?.arrayValue {
                fields["words"] = .array(words.map { .object(($0.objectValue ?? [:]).filter { ["text", "offsetMilliseconds", "durationMilliseconds"].contains($0.key) }) })
            }
            return .object(fields)
        }
        let languages = Set(phrases.compactMap { $0["locale"]?.stringValue?.split(separator: "-").first?.lowercased() })
        let language = languages.count == 1 ? languages.first : nil
        let segments = phrases.compactMap { phrase -> TranscriptionSegment? in
            guard let offset = phrase["offsetMilliseconds"]?.doubleValue, let duration = phrase["durationMilliseconds"]?.doubleValue else { return nil }
            return TranscriptionSegment(text: phrase["text"]?.stringValue ?? "", startSecond: offset / 1000, endSecond: (offset + duration) / 1000)
        }
        let warnings = options["language"].map { azureAudioUnusedOptions(["language": $0], api: "MAI streaming transcription") } ?? []
        return TranscriptionResult(text: combined.compactMap { $0["text"]?.stringValue }.joined(separator: " "), rawValue: raw, segments: segments,
                                   language: language.flatMap { $0.range(of: #"^[a-z]{2}$"#, options: .regularExpression) == nil ? nil : $0 },
                                   durationInSeconds: raw["durationMilliseconds"]?.doubleValue.map { $0 / 1000 }, warnings: warnings,
                                   providerMetadata: ["azure": .object(["phrases": .array(normalizedPhrases)])],
                                   requestMetadata: AIRequestMetadata(body: .object(definition), headers: request.headers),
                                   responseMetadata: aiResponseMetadata(from: raw, response: response, modelID: modelID))
    }
}

private func azureNullableNumber(_ value: JSONValue?) -> Bool {
    value == nil || value == .null || value?.doubleValue?.isFinite == true
}

private func azureValidTranscriptionPhrase(_ phrase: JSONValue) -> Bool {
    guard phrase["text"]?.stringValue != nil,
          ["offsetMilliseconds", "durationMilliseconds", "speaker", "confidence"].allSatisfy({ azureNullableNumber(phrase[$0]) }),
          phrase["locale"] == nil || phrase["locale"] == .null || phrase["locale"]?.stringValue != nil else { return false }
    guard let words = phrase["words"], words != .null else { return true }
    return words.arrayValue?.allSatisfy { word in
        word["text"]?.stringValue != nil && azureNullableNumber(word["offsetMilliseconds"]) && azureNullableNumber(word["durationMilliseconds"])
    } == true
}

func azureAudioOptions(_ providerOptions: [String: JSONValue], transcription: Bool) throws -> [String: JSONValue] {
    guard let value = providerOptions["azure"] else { return [:] }
    guard let options = value.objectValue else { throw azureAudioOptionError("options", "must be an object") }
    let allowed: Set<String> = transcription ? ["api", "timestamps", "transcribeStyle", "locales", "diarization", "phraseList", "language"] : ["api", "style", "styleDegree"]
    guard Set(options.keys).isSubset(of: allowed) else { throw azureAudioOptionError("options", "contains unknown keys") }
    for (key, value) in options {
        let valid: Bool
        switch key {
        case "api": valid = value.stringValue.map { (transcription ? ["openai", "speech", "mai"] : ["openai", "speech"]).contains($0) } ?? false
        case "timestamps": valid = value.stringValue.map { ["word", "segment", "none"].contains($0) } ?? false
        case "transcribeStyle": valid = value.stringValue.map { ["verbatim", "clean"].contains($0) } ?? false
        case "style", "language": valid = value.stringValue?.isEmpty == false
        case "styleDegree": valid = value.doubleValue.map { $0.isFinite && (0.01...2).contains($0) } ?? false
        case "locales": valid = value.arrayValue?.count == 1 && value.arrayValue?.allSatisfy { $0.stringValue != nil } == true
        case "diarization": valid = value.objectValue?.keys.sorted() == ["enabled"] && value["enabled"]?.boolValue != nil
        case "phraseList": valid = value.objectValue?.keys.sorted() == ["phrases"] && value["phrases"]?.arrayValue?.allSatisfy { $0.stringValue != nil } == true
        default: valid = false
        }
        if !valid { throw azureAudioOptionError(key, "has an invalid value") }
    }
    return options
}

private func azureAudioOptionError(_ key: String, _ message: String) -> AIError {
    .invalidArgument(argument: "providerOptions.azure.\(key)", message: "Azure \(key) \(message).")
}
func azureAudioUnusedOptions(_ options: [String: JSONValue], api: String) -> [AIWarning] {
    options.keys.sorted().map { AIWarning(type: "unsupported", feature: "providerOptions.azure.\($0)", message: api == "Speech" ? "This option requires the Azure Speech API." : "This option requires MAI streaming transcription.") }
}
private let azureVoiceModels = ["mai-voice-2.1-flash": "MAI-Voice-2.1-Flash", "mai-voice-2.1": "MAI-Voice-2.1", "mai-voice-2-flash": "MAI-Voice-2-Flash", "mai-voice-2": "MAI-Voice-2"]
private let azureTranscribeModels = ["mai-transcribe-2": "MAI-Transcribe-2", "mai-transcribe-1.5": "MAI-Transcribe-1.5"]
private let azureDefaultVoices = ["de": "de-DE-Mia", "en": "en-US-Harper", "es": "es-MX-Valeria", "fr": "fr-FR-Soleil", "hi": "hi-IN-Kavya", "hu": "hu-HU-Lilla", "it": "it-IT-Rosa", "ko": "ko-KR-Haena", "nl": "nl-NL-Fleur", "pt": "pt-BR-Luana", "ro": "ro-RO-Elena", "ru": "ru-RU-Masha", "th": "th-TH-Krit", "tr": "tr-TR-Elif", "zh": "zh-CN-Mei"]
private func azureVoiceLocale(_ voice: String) -> String? {
    let parts = voice.split(separator: "-")
    guard parts.count >= 3, (2...3).contains(parts[0].count), (2...4).contains(parts[1].count),
          (String(parts[0]) + String(parts[1])).unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) && $0.isASCII }) else { return nil }
    return "\(parts[0])-\(parts[1])"
}
private func azureEscapeXML(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
}
private func azureAudioNumber(_ number: Double) -> String {
    number == number.rounded() && abs(number) < Double(Int.max) ? String(Int(number)) : String(number)
}
