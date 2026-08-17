import Foundation

final class GoogleVertexCloudTTSSpeechModel: SpeechModel, @unchecked Sendable {
    let providerID: String
    let modelID: String
    private let config: GoogleVertexConfig

    private static let defaultVoice = "Kore"
    private static let defaultLanguage = "en-US"
    private static let chirpVoiceInfix = "Chirp3-HD"
    private static let synthesizeURL = "https://texttospeech.googleapis.com/v1/text:synthesize"

    init(modelID: String, config: GoogleVertexConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    func speak(_ request: SpeechRequest) async throws -> SpeechResult {
        let currentDate = config.date()
        var warnings: [AIWarning] = []
        let voice = request.voice ?? Self.defaultVoice
        let voiceName: String
        let languageCode: String

        if let infixRange = voice.range(of: Self.chirpVoiceInfix) {
            voiceName = voice
            var localePrefix = String(voice[..<infixRange.lowerBound])
            if localePrefix.hasSuffix("-") {
                localePrefix.removeLast()
            }
            languageCode = request.language ?? (localePrefix.isEmpty ? Self.defaultLanguage : localePrefix)
        } else {
            languageCode = request.language ?? Self.defaultLanguage
            voiceName = "\(languageCode)-\(Self.chirpVoiceInfix)-\(voice)"
        }

        if request.instructions != nil {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "instructions",
                message: "Google Cloud Text-to-Speech Chirp 3: HD voices do not support the `instructions` option. It was ignored."
            ))
        }
        if let outputFormat = request.format, outputFormat != "wav" {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "outputFormat",
                message: "Unsupported output format: \(outputFormat). Using wav instead."
            ))
        }

        var audioConfig: [String: JSONValue] = [
            "audioEncoding": .string("LINEAR16")
        ]
        if let speed = request.speed {
            audioConfig["speakingRate"] = .number(speed)
        }
        let body: JSONValue = .object([
            "input": .object(["text": .string(request.text)]),
            "voice": .object([
                "languageCode": .string(languageCode),
                "name": .string(voiceName)
            ]),
            "audioConfig": .object(audioConfig)
        ])

        let response = try await config.sendJSONResponse(
            url: Self.synthesizeURL,
            body: body,
            headers: request.headers,
            abortSignal: request.abortSignal
        )
        let raw = response.json
        guard case let .object(responseObject) = raw else {
            throw AIError.invalidResponse(
                provider: providerID,
                message: "Google Cloud Text-to-Speech response must be an object."
            )
        }
        let audio: Data
        switch responseObject["audioContent"] {
        case let .string(audioContent):
            guard let decoded = Data(base64Encoded: audioContent) else {
                throw AIError.invalidResponse(provider: providerID, message: "Google Cloud Text-to-Speech returned invalid base64 audioContent.")
            }
            audio = decoded
        case nil, .null:
            audio = Data()
        default:
            throw AIError.invalidResponse(
                provider: providerID,
                message: "Google Cloud Text-to-Speech audioContent must be a string or null."
            )
        }

        return SpeechResult(
            audio: audio,
            contentType: "audio/wav",
            warnings: warnings,
            providerMetadata: [
                "google": .object(["mimeType": .string("audio/wav")])
            ],
            requestMetadata: AIRequestMetadata(body: body, headers: request.headers),
            responseMetadata: AIResponseMetadata(
                timestamp: currentDate,
                modelID: modelID,
                headers: response.response.headers,
                body: raw
            )
        )
    }
}
