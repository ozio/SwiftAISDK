import Foundation

/// The published `@ai-sdk/fish-audio` package version mirrored by this port.
public let fishAudioProviderVersion = "3.0.7"

/// Creates a Fish Audio provider using the same defaults as
/// `createFishAudio` from `@ai-sdk/fish-audio`.
public func createFishAudio(
    settings: ProviderSettings = ProviderSettings()
) throws -> FishAudioProvider {
    try FishAudioProvider(settings: settings)
}

public final class FishAudioProvider: AIProvider, @unchecked Sendable {
    public let providerID = "fish-audio"
    public let supportedCapabilities: Set<ModelCapability> = [
        .speech,
        .transcription
    ]

    private let config: ModelHTTPConfig

    public init(settings: ProviderSettings = ProviderSettings()) throws {
        let apiKey = settings.apiKey
            ?? settings.environmentValue(["FISH_AUDIO_API_KEY"])
        guard let apiKey else {
            throw AIError.missingAPIKey(
                provider: providerID,
                environmentVariables: ["FISH_AUDIO_API_KEY"]
            )
        }

        var headers = withUserAgentSuffix(
            settings.headers,
            "ai-sdk/fish-audio/\(fishAudioProviderVersion)"
        )
        headers["authorization"] = headers["authorization"]
            ?? "Bearer \(apiKey)"

        config = ModelHTTPConfig(
            providerID: providerID,
            baseURL: settings.baseURL ?? "https://api.fish.audio",
            headers: headers,
            transport: settings.transport,
            queryParams: settings.queryParams
        )
    }

    public func speechModel(_ modelID: String) throws -> any SpeechModel {
        FishAudioSpeechModel(
            modelID: modelID,
            config: config.withProviderID("fish-audio.speech")
        )
    }

    public func speech(_ modelID: String) throws -> any SpeechModel {
        try speechModel(modelID)
    }

    /// Fish Audio currently exposes a single ASR model. The model ID is a
    /// local routing label and is not sent to `/v1/asr`.
    public func transcriptionModel(
        _ modelID: String = "transcribe-1"
    ) throws -> any TranscriptionModel {
        FishAudioTranscriptionModel(
            modelID: modelID,
            config: config.withProviderID("fish-audio.transcription")
        )
    }

    public func transcription(
        _ modelID: String = "transcribe-1"
    ) throws -> any TranscriptionModel {
        try transcriptionModel(modelID)
    }

    public func languageModel(_ modelID: String) throws -> any LanguageModel {
        throw AIError.unsupportedModel(
            provider: providerID,
            capability: .language,
            modelID: modelID
        )
    }

    public func embeddingModel(_ modelID: String) throws -> any EmbeddingModel {
        throw AIError.unsupportedModel(
            provider: providerID,
            capability: .embedding,
            modelID: modelID
        )
    }

    public func imageModel(_ modelID: String) throws -> any ImageModel {
        throw AIError.unsupportedModel(
            provider: providerID,
            capability: .image,
            modelID: modelID
        )
    }

    public func videoModel(_ modelID: String) throws -> any VideoModel {
        throw AIError.unsupportedModel(
            provider: providerID,
            capability: .video,
            modelID: modelID
        )
    }

    public func rerankingModel(_ modelID: String) throws -> any RerankingModel {
        throw AIError.unsupportedModel(
            provider: providerID,
            capability: .reranking,
            modelID: modelID
        )
    }
}

func fishAudioHTTPStatusError(
    provider: String,
    response: AIHTTPResponse
) -> AIError {
    let message: String
    if let raw = try? response.jsonValue(),
       fishAudioNullishNumber(raw["status"]),
       fishAudioNullishString(raw["message"]) {
        message = raw["message"]?.stringValue ?? "Unknown Fish Audio error"
    } else {
        message = response.bodyText
    }
    return apiCallError(
        provider: provider,
        statusCode: response.statusCode,
        body: message,
        headers: response.headers
    )
}

private func fishAudioNullishNumber(_ value: JSONValue?) -> Bool {
    value == nil || value == .null || value?.doubleValue != nil
}

private func fishAudioNullishString(_ value: JSONValue?) -> Bool {
    value == nil || value == .null || value?.stringValue != nil
}
