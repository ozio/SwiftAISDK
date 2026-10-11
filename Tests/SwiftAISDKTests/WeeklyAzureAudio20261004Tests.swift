import Foundation
import Testing
@testable import SwiftAISDK

@Test func Weekly20261004AzureSpeechRoutesMAIVoicesAndEscapesSSML() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/ogg"], body: Data([1, 2])))
    let provider = try AIProviders.azure(resourceName: "weekly", settings: .init(apiKey: "key", transport: transport))
    let result = try await provider.speechModel("mai-voice-2.1").speak(SpeechRequest(text: "<Hello & \"world\">", format: "opus", speed: 1.25, language: "ru", providerOptions: ["azure": ["style": "cheerful", "styleDegree": 1.5]]))
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://weekly.cognitiveservices.azure.com/tts/cognitiveservices/v1")
    #expect(request.headers.first { $0.key.lowercased() == "ocp-apim-subscription-key" }?.value == "key")
    #expect(request.headers["api-key"] == nil)
    #expect(request.headers["X-Microsoft-OutputFormat"] == "ogg-24khz-16bit-mono-opus")
    let ssml = String(decoding: try #require(request.body), as: UTF8.self)
    #expect(ssml.contains("ru-RU-Masha:MAI-Voice-2.1"))
    #expect(ssml.contains("&lt;Hello &amp; &quot;world&quot;&gt;"))
    #expect(ssml.contains("rate=\"1.25\""))
    #expect(ssml.contains("styledegree=\"1.5\""))
    #expect(result.audio == Data([1, 2]))
    #expect(result.contentType == "audio/ogg")
}

@Test(arguments: [400, 502, 503])
func Weekly20261004AzureSpeechErrorsKeepWireEvidenceAndRetryPolicy(_ status: Int) async throws {
    let body = status == 502 ? "upstream reset reason: protocol error" : "invalid voice"
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: status, body: Data(body.utf8)))
    let model = try AIProviders.azure(resourceName: "weekly", settings: .init(apiKey: "key", transport: transport)).speechModel("mai-voice-2")
    do {
        _ = try await model.speak(SpeechRequest(text: "test"))
        Issue.record("Expected Azure error")
    } catch let AIError.apiCall(error) {
        #expect(error.responseBody == body)
        #expect(error.statusCode == (status == 502 ? 400 : status))
        #expect(error.isRetryable == (status == 503))
        #expect(error.description.contains(status == 502 ? "Check that the voice" : "status \(status)"))
    }
}

@Test func Weekly20261004AzureAudioCustomHostsAndEntraAuthReachBothAPIs() async throws {
    let transport = RecordingTransport(responses: [AIHTTPResponse(statusCode: 200, body: Data([1])), jsonResponse("{\"text\":\"legacy\"}")])
    let provider = try AIProviders.azure(tokenProvider: { "entra" }, settings: .init(baseURL: "https://openai.example/v1", transport: transport), audioSettings: .init(speechBaseURL: "https://speech.example"))
    _ = try await provider.speechModel("mai-voice-2").speak(SpeechRequest(text: "test"))
    _ = try await provider.transcriptionModel("whisper-1").transcribe(AudioTranscriptionRequest(audio: Data([2]), mimeType: "audio/wav"))
    let requests = await transport.requests()
    #expect(requests[0].url.host == "speech.example")
    #expect(requests[1].url.path == "/v1/audio/transcriptions")
    #expect(requests.allSatisfy { $0.headers.first { $0.key.lowercased() == "authorization" }?.value == "Bearer entra" })
    #expect(requests.allSatisfy { $0.headers["api-key"] == nil && $0.headers["Ocp-Apim-Subscription-Key"] == nil })
}

@Test func Weekly20261004AzureSpeechTranscriptionMapsPhrasesAndMixedLocales() async throws {
    let raw = """
    {"combinedPhrases":[{"text":"one"},{"text":"two"}],"durationMilliseconds":1200,"phrases":[{"text":"one","offsetMilliseconds":100,"durationMilliseconds":400,"locale":"en-US","speaker":0},{"text":"two","offsetMilliseconds":700,"durationMilliseconds":300,"locale":"fil-PH"}]}
    """
    let transport = RecordingTransport(response: jsonResponse(raw))
    let provider = try AIProviders.azure(resourceName: "weekly", settings: .init(apiKey: "key", transport: transport))
    let result = try await provider.transcriptionModel("mai-transcribe-2").transcribe(AudioTranscriptionRequest(audio: Data([1, 2]), mimeType: "audio/wav", providerOptions: ["azure": ["transcribeStyle": "clean", "locales": ["en-US"], "diarization": ["enabled": true], "phraseList": ["phrases": ["Swift"]]]]))
    #expect(result.text == "one two")
    #expect(result.language == nil)
    #expect(result.durationInSeconds == 1.2)
    #expect(result.segments == [.init(text: "one", startSecond: 0.1, endSecond: 0.5), .init(text: "two", startSecond: 0.7, endSecond: 1)])
    #expect(result.providerMetadata["azure"]?["phrases"]?[0]?["speaker"] == 0)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://weekly.cognitiveservices.azure.com/speechtotext/transcriptions:transcribe?api-version=2025-10-15")
    let body = String(decoding: try #require(request.body), as: UTF8.self)
    #expect(body.contains("name=\"audio\"; filename=\"audio.wav\""))
    #expect(body.contains("MAI-Transcribe-2"))
    #expect(body.contains("\"timestamps\":\"segment\""))
}

@Test(arguments: [JSONValue.object(["unknown": true]), ["styleDegree": 3], ["style": ""], ["api": "mai"]])
func Weekly20261004AzureSpeechStrictOptionsRejectBeforeSending(_ options: JSONValue) async throws {
    let transport = RecordingTransport(response: jsonResponse("{}"))
    let model = try AIProviders.azure(resourceName: "weekly", settings: .init(apiKey: "key", transport: transport)).speechModel("mai-voice-2")
    await #expect(throws: AIError.self) { try await model.speak(SpeechRequest(text: "test", providerOptions: ["azure": options])) }
    #expect(await transport.requests().isEmpty)
}

@Test func Weekly20261004AzureMAIHandshakeStreamsPCMAndFinishesOnce() async throws {
    let socket = RealtimeTestWebSocketTransport()
    let provider = try AIProviders.azure(resourceName: "weekly", settings: .init(apiKey: "key"), audioSettings: .init(webSocketTransport: socket))
    let audio = AIStreamingAudioInput.makeStream()
    let result = try await provider.streamingTranscriptionModel("mai-transcribe-2-streaming").stream(.init(audio: audio.input, inputAudioFormat: .init(mediaType: "audio/pcm", sampleRate: 16_000), providerOptions: ["azure": ["language": "en"]], includeRawChunks: true))
    let collector = Task { try await realtimeCollect(result.stream) }
    #expect(socket.requests().first?.url.absoluteString == "wss://weekly.services.ai.azure.com/mai/v1/realtime?intent=transcription")
    #expect(socket.requests().first?.headers["api-key"] == "key")
    socket.connection.open()
    socket.connection.sendJSON(["type": "session.created"])
    #expect(await realtimeWait { socket.connection.sentMessages().count == 1 })
    let update = try #require(socket.connection.sentJSONMessages().first)
    #expect(update["session"]?["audio"]?["input"]?["format"]?["rate"] == 16_000)
    #expect(update["session"]?["audio"]?["input"]?["turn_detection"] == .null)
    socket.connection.sendJSON(["type": "session.updated"])
    audio.writer.send(Data(repeating: 1, count: 320))
    audio.writer.finish()
    #expect(await realtimeWait { (try? socket.connection.sentJSONMessages().contains { $0["type"] == "input_audio_buffer.commit" }) == true })
    socket.connection.sendJSON(["type": "conversation.item.input_audio_transcription.delta", "item_id": "i", "delta": "Hel"])
    socket.connection.sendJSON(["type": "conversation.item.input_audio_transcription.completed", "item_id": "i", "transcript": "Hello"])
    let parts = try await collector.value
    let finishes = parts.compactMap { part -> StreamingTranscriptionFinish? in if case let .finish(finish) = part { return finish }; return nil }
    #expect(finishes.count == 1)
    #expect(finishes.first?.text == "Hello")
    #expect(finishes.first?.durationInSeconds == 0.01)
    #expect(parts.contains { if case .raw = $0 { return true }; return false })
    #expect(socket.connection.closeCalls().count == 1)
    #expect(audio.writer.send(Data([1])) == .terminated)
}

@Test func Weekly20261004AzureMAIEarlyCloseFailsAndCancelsAudio() async throws {
    let socket = RealtimeTestWebSocketTransport()
    let provider = try AIProviders.azure(resourceName: "weekly", settings: .init(apiKey: "key"), audioSettings: .init(webSocketTransport: socket))
    let audio = AIStreamingAudioInput.makeStream()
    let result = try await provider.streamingTranscriptionModel("mai-transcribe-2-streaming").stream(.init(audio: audio.input, inputAudioFormat: .init(mediaType: "audio/pcm")))
    socket.connection.serverClose(code: 1006, reason: "gone")
    do { _ = try await realtimeCollect(result.stream); Issue.record("Expected early-close failure") }
    catch let error as AIStreamingTranscriptionError { #expect(error.closeMetadata?.code == 1006) }
    #expect(audio.writer.send(Data([1])) == .terminated)
    #expect(socket.connection.closeCalls().count == 1)
}

@Test func Weekly20261004AzureMAIEmptyAudioFinishesWithoutCommit() async throws {
    let socket = RealtimeTestWebSocketTransport()
    let provider = try AIProviders.azure(resourceName: "weekly", settings: .init(apiKey: "key"), audioSettings: .init(webSocketTransport: socket))
    let audio = AIStreamingAudioInput.makeStream()
    audio.writer.finish()
    let result = try await provider.streamingTranscriptionModel("mai-transcribe-2-streaming").stream(.init(audio: audio.input, inputAudioFormat: .init(mediaType: "audio/pcm")))
    socket.connection.open(); socket.connection.sendJSON(["type": "session.created"]); socket.connection.sendJSON(["type": "session.updated"])
    let parts = try await realtimeCollect(result.stream)
    #expect(parts.contains { if case let .finish(finish) = $0 { return finish.text.isEmpty }; return false })
    #expect(try socket.connection.sentJSONMessages().allSatisfy { $0["type"] != "input_audio_buffer.commit" })
}
