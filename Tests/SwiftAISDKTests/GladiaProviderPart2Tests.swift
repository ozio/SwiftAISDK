import Foundation
import Testing
@testable import SwiftAISDK

@Test func gladiaTranscriptionProviderOptionsRejectInvalidSchemaFields() async throws {
    let provider = try AIProviders.gladia(settings: ProviderSettings(apiKey: "gladia-key", transport: RecordingTransport(response: jsonResponse(#"{}"#))))
    let model = try provider.transcriptionModel("default")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.gladia", message: "Gladia provider options must be an object.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .string("invalid")]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["contextPrompt": .number(1)])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["customVocabulary": .string("term")])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["customVocabularyConfig": .object(["defaultIntensity": .number(0.5)])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["customVocabularyConfig": .object(["vocabulary": .array([.object(["intensity": .number(0.5)])])])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["detectLanguage": .string("true")])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["codeSwitchingConfig": .object(["languages": .array([.number(1)])])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["callbackConfig": .object(["method": .string("PATCH")])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["subtitlesConfig": .object(["formats": .array([.string("ass")])])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["diarizationConfig": .object(["enhanced": .string("true")])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["translationConfig": .object(["model": .string("enhanced")])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["translationConfig": .object(["targetLanguages": .array([.string("en")]), "model": .string("premium")])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["summarizationConfig": .object(["type": .string("paragraph")])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["customSpellingConfig": .object(["spellingDictionary": .object(["Codex": .array([.number(1)])])])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["structuredDataExtractionConfig": .object([:])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["audioToLlmConfig": .object(["prompts": .array([.number(1)])])])]
        ))
    }

    await #expect(throws: AIError.self) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: ["gladia": .object(["customMetadata": .string("invalid")])]
        ))
    }
}
@Test func gladiaTranscriptionRejectsUnknownPollingStatusLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"audio_url":"https://audio.example.com/file.wav"}"#),
        jsonResponse(#"{"result_url":"https://api.gladia.io/v2/pre-recorded/result/job-123"}"#),
        jsonResponse(#"{"status":"paused"}"#)
    ])
    let provider = try AIProviders.gladia(settings: ProviderSettings(apiKey: "gladia-key", transport: transport))
    let model = try provider.transcriptionModel("default")

    await #expect(throws: AIError.invalidResponse(provider: "gladia.transcription", message: "Gladia transcription status is invalid.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8), mimeType: "audio/wav"))
    }
}
@Test func gladiaTranscriptionUsesUpstreamHTTPErrorMessageSchema() async throws {
    let uploadProvider = try AIProviders.gladia(settings: ProviderSettings(
        apiKey: "gladia-key",
        transport: RecordingTransport(response: AIHTTPResponse(
            statusCode: 401,
            headers: ["content-type": "application/json", "x-gladia": "upload"],
            body: Data(#"{"error":{"message":"upload unauthorized","code":401}}"#.utf8)
        ))
    ))
    let uploadModel = try uploadProvider.transcriptionModel("default")

    await #expect(throws: AIError.apiCall(
        provider: "gladia.transcription",
        statusCode: 401,
        body: "upload unauthorized",
        headers: ["content-type": "application/json", "x-gladia": "upload"]
    )) {
        _ = try await uploadModel.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8), mimeType: "audio/wav"))
    }

    let initProvider = try AIProviders.gladia(settings: ProviderSettings(
        apiKey: "gladia-key",
        transport: RecordingTransport(responses: [
            jsonResponse(#"{"audio_url":"https://audio.example.com/file.wav"}"#),
            AIHTTPResponse(
                statusCode: 400,
                headers: ["content-type": "application/json", "x-gladia": "init"],
                body: Data(#"{"error":{"message":"init failed","code":400}}"#.utf8)
            )
        ])
    ))
    let initModel = try initProvider.transcriptionModel("default")

    await #expect(throws: AIError.apiCall(
        provider: "gladia.transcription",
        statusCode: 400,
        body: "init failed",
        headers: ["content-type": "application/json", "x-gladia": "init"]
    )) {
        _ = try await initModel.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8), mimeType: "audio/wav"))
    }

    let pollProvider = try AIProviders.gladia(settings: ProviderSettings(
        apiKey: "gladia-key",
        transport: RecordingTransport(responses: [
            jsonResponse(#"{"audio_url":"https://audio.example.com/file.wav"}"#),
            jsonResponse(#"{"result_url":"https://api.gladia.io/v2/pre-recorded/result/job-123"}"#),
            AIHTTPResponse(
                statusCode: 500,
                headers: ["content-type": "application/json", "x-gladia": "poll"],
                body: Data(#"{"error":{"message":"poll failed","code":500}}"#.utf8)
            )
        ])
    ))
    let pollModel = try pollProvider.transcriptionModel("default")

    await #expect(throws: AIError.apiCall(
        provider: "gladia.transcription",
        statusCode: 500,
        body: "poll failed",
        headers: ["content-type": "application/json", "x-gladia": "poll"]
    )) {
        _ = try await pollModel.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8), mimeType: "audio/wav"))
    }
}
@Test func gladiaTranscriptionUsesUpstreamLifecycleMessages() async throws {
    let failedProvider = try AIProviders.gladia(settings: ProviderSettings(
        apiKey: "gladia-key",
        transport: RecordingTransport(responses: [
            jsonResponse(#"{"audio_url":"https://audio.example.com/file.wav"}"#),
            jsonResponse(#"{"result_url":"https://api.gladia.io/v2/pre-recorded/result/job-123"}"#),
            jsonResponse(#"{"status":"error"}"#)
        ])
    ))
    let failedModel = try failedProvider.transcriptionModel("default")

    await #expect(throws: AIError.invalidResponse(provider: "gladia.transcription", message: "Transcription job failed")) {
        _ = try await failedModel.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8), mimeType: "audio/wav"))
    }

    let emptyProvider = try AIProviders.gladia(settings: ProviderSettings(
        apiKey: "gladia-key",
        transport: RecordingTransport(responses: [
            jsonResponse(#"{"audio_url":"https://audio.example.com/file.wav"}"#),
            jsonResponse(#"{"result_url":"https://api.gladia.io/v2/pre-recorded/result/job-123"}"#),
            jsonResponse(#"{"status":"done"}"#)
        ])
    ))
    let emptyModel = try emptyProvider.transcriptionModel("default")

    await #expect(throws: AIError.invalidResponse(provider: "gladia.transcription", message: "Transcription result is empty")) {
        _ = try await emptyModel.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8), mimeType: "audio/wav"))
    }
}
@Test func gladiaTranscriptionRejectsInvalidDoneResultLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"audio_url":"https://audio.example.com/file.wav"}"#),
        jsonResponse(#"{"result_url":"https://api.gladia.io/v2/pre-recorded/result/job-123"}"#),
        jsonResponse(#"{"status":"done","result":{"transcription":{"full_transcript":"missing metadata"}}}"#)
    ])
    let provider = try AIProviders.gladia(settings: ProviderSettings(apiKey: "gladia-key", transport: transport))
    let model = try provider.transcriptionModel("default")

    await #expect(throws: AIError.invalidResponse(provider: "gladia.transcription", message: "Gladia transcription result is invalid.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8), mimeType: "audio/wav"))
    }
}
@Test func gladiaTranscriptionThrowsWhenDoneResultIsEmpty() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"audio_url":"https://audio.example.com/file.wav"}"#),
        jsonResponse(#"{"result_url":"https://api.gladia.io/v2/pre-recorded/result/job-123"}"#),
        jsonResponse(#"{"status":"done"}"#)
    ])
    let provider = try AIProviders.gladia(settings: ProviderSettings(apiKey: "gladia-key", transport: transport))
    let model = try provider.transcriptionModel("default")

    await #expect(throws: AIError.invalidResponse(provider: "gladia.transcription", message: "Transcription result is empty")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(audio: Data("audio".utf8), mimeType: "audio/wav"))
    }
}
