import Foundation
import Testing
@testable import SwiftAISDK

@Test func googleVertexUpstreamRoutesChirpToCloudTTSAndKeepsGeminiSpeechRouting() throws {
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "us-central1",
        accessToken: "token",
        transport: RecordingTransport(response: jsonResponse("{}"))
    ))

    #expect(try provider.speechModel("chirp-3-hd") is GoogleVertexCloudTTSSpeechModel)
    #expect(try provider.speechModel("gemini-2.5-flash-tts") is GoogleVertexSpeechModel)
}

@Test func googleVertexUpstreamChirpUsesCloudTTSEndpointAndDefaultVoice() async throws {
    let timestamp = Date(timeIntervalSince1970: 0)
    let transport = RecordingTransport(response: jsonResponse(
        #"{"audioContent":"AQIDBAUGBwg="}"#,
        headers: ["x-request-id": "request-123"]
    ))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "us-central1",
        accessToken: "token",
        headers: ["Custom-Provider-Header": "provider-value"],
        transport: transport,
        date: { timestamp }
    ))
    let model = try provider.speechModel("chirp-3-hd")

    let result = try await model.speak(SpeechRequest(
        text: "Hello from the AI SDK!",
        headers: ["Custom-Request-Header": "request-value"]
    ))

    #expect(result.audio == Data([1, 2, 3, 4, 5, 6, 7, 8]))
    #expect(result.contentType == "audio/wav")
    #expect(result.warnings.isEmpty)
    #expect(result.providerMetadata == ["google": ["mimeType": "audio/wav"]])
    #expect(result.requestMetadata.body?["voice"]?["languageCode"]?.stringValue == "en-US")
    #expect(result.requestMetadata.body?["voice"]?["name"]?.stringValue == "en-US-Chirp3-HD-Kore")
    #expect(result.responseMetadata.timestamp == timestamp)
    #expect(result.responseMetadata.modelID == "chirp-3-hd")
    #expect(result.responseMetadata.headers["x-request-id"] == "request-123")
    #expect(result.responseMetadata.body?["audioContent"]?.stringValue == "AQIDBAUGBwg=")

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://texttospeech.googleapis.com/v1/text:synthesize")
    let headers = normalizeHeaders(request.headers)
    #expect(headers["authorization"] == "Bearer token")
    #expect(headers["custom-provider-header"] == "provider-value")
    #expect(headers["custom-request-header"] == "request-value")
    #expect(headers["user-agent"] == "ai-sdk/google-vertex/5.0.56")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body == [
        "input": ["text": "Hello from the AI SDK!"],
        "voice": ["languageCode": "en-US", "name": "en-US-Chirp3-HD-Kore"],
        "audioConfig": ["audioEncoding": "LINEAR16"]
    ])
}

@Test func googleVertexUpstreamChirpMapsVoiceSpeedAndWarnings() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"audioContent":"AQI="}"#))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "us-central1",
        accessToken: "token",
        transport: transport
    ))
    let model = try provider.speechModel("chirp-3-hd")

    _ = try await model.speak(SpeechRequest(
        text: "Bonjour !",
        voice: "fr-FR-Chirp3-HD-Charon"
    ))
    let result = try await model.speak(SpeechRequest(
        text: "Hello!",
        voice: "en-AU-Chirp3-HD-Kore",
        format: "mp3",
        speed: 1.5,
        language: "en-GB",
        instructions: "Speak slowly."
    ))

    let requests = await transport.requests()
    let qualifiedBody = try decodeJSONBody(try #require(requests[0].body))
    #expect(qualifiedBody["voice"]?["languageCode"]?.stringValue == "fr-FR")
    #expect(qualifiedBody["voice"]?["name"]?.stringValue == "fr-FR-Chirp3-HD-Charon")
    let explicitBody = try decodeJSONBody(try #require(requests[1].body))
    #expect(explicitBody["voice"]?["languageCode"]?.stringValue == "en-GB")
    #expect(explicitBody["voice"]?["name"]?.stringValue == "en-AU-Chirp3-HD-Kore")
    #expect(explicitBody["audioConfig"]?["speakingRate"]?.doubleValue == 1.5)
    #expect(result.warnings.contains { $0.type == "unsupported" && $0.feature == "instructions" })
    #expect(result.warnings.contains { $0.type == "unsupported" && $0.feature == "outputFormat" })
}

@Test func googleVertexUpstreamChirpReturnsEmptyAudioAndRejectsExpressMode() async throws {
    let transport = RecordingTransport(response: jsonResponse("{}"))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "us-central1",
        accessToken: "token",
        transport: transport
    ))
    let result = try await provider.speechModel("chirp-3-hd").speak(SpeechRequest(text: "Hello!"))
    #expect(result.audio.isEmpty)

    let expressProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        apiKey: "vertex-key",
        transport: RecordingTransport(response: jsonResponse("{}"))
    ))
    #expect(throws: AIError.invalidArgument(
        argument: "modelID",
        message: "Google Vertex Chirp speech models do not support Express Mode API keys. Use standard Google Cloud credentials instead."
    )) {
        _ = try expressProvider.speechModel("chirp-3-hd")
    }
}

@Test func googleVertexUpstreamChirpRejectsSchemaInvalidResponses() async throws {
    let scalarProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "us-central1",
        accessToken: "token",
        transport: RecordingTransport(response: jsonResponse(#""not-an-object""#))
    ))
    await #expect(throws: AIError.invalidResponse(
        provider: "google.vertex.speech",
        message: "Google Cloud Text-to-Speech response must be an object."
    )) {
        _ = try await scalarProvider.speechModel("chirp-3-hd").speak(SpeechRequest(text: "Hello!"))
    }

    let nonStringAudioProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        project: "test-project",
        location: "us-central1",
        accessToken: "token",
        transport: RecordingTransport(response: jsonResponse(#"{"audioContent":42}"#))
    ))
    await #expect(throws: AIError.invalidResponse(
        provider: "google.vertex.speech",
        message: "Google Cloud Text-to-Speech audioContent must be a string or null."
    )) {
        _ = try await nonStringAudioProvider.speechModel("chirp-3-hd").speak(SpeechRequest(text: "Hello!"))
    }
}
