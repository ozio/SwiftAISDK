import Foundation
import Testing
@testable import SwiftAISDK

private func weeklyBFLTransport(host: String = "api.bfl.ai", status: String = "Ready") -> RecordingTransport {
    RecordingTransport(responses: [jsonResponse("{\"id\":\"b\",\"polling_url\":\"https://\(host)/poll\"}"), jsonResponse("{\"status\":\"\(status)\",\"result\":{\"sample\":\"https://\(host)/image.png\"}}"), AIHTTPResponse(statusCode: 200, body: Data([1]))])
}

@Test(arguments: ["7:3", "3:7", "17:13"])
func WeeklyBFLXAI20261011FLUX3MapsRatiosReferencesAndRestrictedOptions(_ ratio: String) async throws {
    let transport = weeklyBFLTransport()
    let model = try AIProviders.blackForestLabs(settings: .init(apiKey: "key", transport: transport)).image("flux-3-image")
    let result = try await model.generateImage(.init(prompt: "apple", aspectRatio: ratio, seed: 42, files: [.init(data: Data([1]), mediaType: "image/png"), .init(url: "https://images.example/a.png")],
                                                   providerOptions: ["blackForestLabs": ["resolution": "1.5k", "grounding": true, "version": "latest", "safetyTolerance": 4, "steps": 10, "pollIntervalMillis": 1]]))
    let requests = await transport.requests()
    let body = try decodeJSONBody(try #require(requests.first?.body))
    #expect(body["aspect_ratio"] == (ratio == "7:3" ? "21:9" : ratio == "3:7" ? "9:21" : nil))
    #expect(body["images"] == ["AQ==", "https://images.example/a.png"])
    #expect(body["resolution"] == "1.5k")
    #expect(body["grounding"] == true)
    #expect(body["steps"] == nil && body["seed"] == nil && body["width"] == nil)
    #expect(result.warnings.contains { $0.feature == "seed" })
    #expect(result.warnings.contains { $0.feature == "blackForestLabs.steps" })
    #expect(await model.supportsFileInputs == true)
    #expect(await model.supportsMaskInputs == false)
    #expect(requests[1].headers["x-key"] == "key")
    #expect(requests[2].headers["x-key"] == nil)
    #expect(requests[2].headers["user-agent"]?.contains("ai-sdk-black-forest-labs/") == true)
}

@Test func WeeklyBFLXAI20261011FLUX3RejectsMasksSafetyAndKeepsCustomProxyHeaders() async throws {
    let transport = weeklyBFLTransport(host: "proxy.example")
    let model = try AIProviders.blackForestLabs(settings: .init(apiKey: "key", baseURL: "https://proxy.example/v1", headers: ["Authorization": "Bearer custom", "x-extra": "value"], transport: transport)).image("flux-3-image")
    await #expect(throws: AIError.self) { try await model.generateImage(.init(prompt: "a", mask: .init(data: Data([1]), mediaType: "image/png"))) }
    await #expect(throws: AIError.self) { try await model.generateImage(.init(prompt: "a", providerOptions: ["blackForestLabs": ["safetyTolerance": 5]])) }
    #expect(await transport.requests().isEmpty)
    _ = try await model.generateImage(.init(prompt: "a", size: "2100x900"))
    let requests = await transport.requests()
    #expect(try decodeJSONBody(try #require(requests[0].body))["aspect_ratio"] == "21:9")
    #expect(requests[2].headers["x-key"] == "key")
    #expect(requests[2].headers["authorization"] == "Bearer custom")
    #expect(requests[2].headers["x-extra"] == "value")
}

@Test(arguments: ["Content Moderated", "Error", "Failed", "Request Moderated", "Task not found"])
func WeeklyBFLXAI20261011TerminalBFLTaskErrorsDoNotRetry503(_ status: String) async throws {
    let raw = "{\"status\":\"\(status)\"}"
    let model = try AIProviders.blackForestLabs(settings: .init(apiKey: "key", transport: RecordingTransport(response: AIHTTPResponse(statusCode: 503, body: Data(raw.utf8))))).image("flux-3-image")
    do { _ = try await model.generateImage(.init(prompt: "a")); Issue.record("Expected task failure") }
    catch let AIError.apiCall(error) { #expect(error.statusCode == 503); #expect(!error.isRetryable); #expect(error.responseBody == raw); #expect(error.message?.contains(status) == true) }
}

@Test(arguments: ["Content Moderated", "Request Moderated", "Task not found"])
func WeeklyBFLXAI20261011BFLTerminalPollStatesStopImmediately(_ status: String) async throws {
    let transport = weeklyBFLTransport(status: status)
    let model = try AIProviders.blackForestLabs(settings: .init(apiKey: "key", transport: transport)).image("flux-3-image")
    await #expect(throws: AIError.self) { try await model.generateImage(.init(prompt: "a", providerOptions: ["blackForestLabs": ["pollIntervalMillis": 1]])) }
    #expect(await transport.requests().count == 2)
}

@Test func WeeklyBFLXAI20261011XAIImage2SupportsEditingAndNewImageOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"aGk="}]}"#))
    let model = try AIProviders.xAI(settings: .init(apiKey: "key", transport: transport)).image("grok-imagine-image-2.0")
    _ = try await model.generateImage(.init(prompt: "edit", files: [.init(data: Data([1]), mediaType: "image/png")], providerOptions: ["xai": ["resolution": "1.5k", "quality": "auto"]]))
    let sent = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(sent.body))
    #expect(sent.url.path == "/v1/images/edits")
    #expect(body["resolution"] == "1.5k" && body["quality"] == "auto")
    #expect(await model.supportsFileInputs == true)
    #expect(await model.supportsMaskInputs == false)
}

@Test func WeeklyBFLXAI20261011XAITranscriptionModelOpusVADAndSpeakerMetadata() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"hello","words":[{"text":"hello","start":0,"end":1,"speaker":0,"extra":"drop"}]}"#))
    let model = try AIProviders.xAI(settings: .init(apiKey: "key", transport: transport)).transcriptionModel("grok-voice-transcribe-2.0")
    let result = try await model.transcribe(.init(audio: Data([1]), mimeType: "audio/ogg", providerOptions: ["xai": ["audioFormat": "opus", "vadThreshold": 0.3]]))
    let body = String(decoding: try #require(await transport.requests().first?.body), as: UTF8.self)
    #expect(body.contains("name=\"model\"") && body.contains("grok-voice-transcribe-2.0"))
    #expect(body.contains("name=\"vad_threshold\"") && body.contains("0.3"))
    #expect(body.contains("opus"))
    #expect(result.responseMetadata.modelID == "grok-voice-transcribe-2.0")
    #expect(result.providerMetadata["xai"]?["words"]?[0]?["speaker"] == 0)
    #expect(result.providerMetadata["xai"]?["words"]?[0]?["extra"] == nil)
}

@Test(arguments: [-0.1, 1.1])
func WeeklyBFLXAI20261011XAIRejectsInvalidVADBeforeSending(_ threshold: Double) async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"hello"}"#))
    let model = try AIProviders.xAI(settings: .init(apiKey: "key", transport: transport)).transcription()
    await #expect(throws: AIError.self) { try await model.transcribe(.init(audio: Data([1]), providerOptions: ["xai": ["vadThreshold": .number(threshold)]])) }
    #expect(await transport.requests().isEmpty)
}

@Test func WeeklyBFLXAI20261011XAIStreamingTranscriptionUsesOpusModelVADAndAccumulatesChannels() async throws {
    let socket = RealtimeTestWebSocketTransport()
    let provider = try AIProviders.xAI(settings: .init(apiKey: "key"))
    let model = try provider.streamingTranscriptionModel("grok-voice-transcribe-2.0", webSocketTransport: socket)
    let result = try await model.stream(.init(audio: .chunks([Data([1, 2])]), inputAudioFormat: .init(mediaType: "audio/opus", sampleRate: 48000), providerOptions: ["xai": ["vadThreshold": 0.3, "multichannel": true, "channels": 2, "keyterm": ["Grok", "AI SDK"], "streaming": ["interimResults": true]]], includeRawChunks: true))
    let collector = Task { try await weeklyMediumCollect(result.stream) }
    let request = try #require(socket.requests().first)
    let parameters = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(parameters.contains(URLQueryItem(name: "encoding", value: "opus")))
    #expect(parameters.contains(URLQueryItem(name: "model", value: "grok-voice-transcribe-2.0")))
    #expect(parameters.contains(URLQueryItem(name: "vad_threshold", value: "0.3")))
    #expect(parameters.filter { $0.name == "keyterm" }.count == 2)
    #expect(request.headers["authorization"] == "Bearer key")
    #expect(socket.connection.sentMessages().isEmpty)
    socket.connection.sendJSON(["type": "transcript.created"])
    #expect(await realtimeWait { socket.connection.sentMessages().count == 2 })
    socket.connection.sendJSON(["type": "transcript.partial", "channel_index": 1, "text": "revisable", "is_final": true, "speech_final": false])
    socket.connection.sendJSON(["type": "transcript.partial", "channel_index": 1, "text": "second", "is_final": true, "speech_final": true])
    socket.connection.sendJSON(["type": "transcript.partial", "channel_index": 0, "text": "first", "is_final": true, "speech_final": true])
    socket.connection.sendJSON(["type": "transcript.done", "channel_index": 1, "text": "", "duration": 1])
    socket.connection.sendJSON(["type": "transcript.done", "channel_index": 0, "text": "", "duration": 1])
    let parts = try await collector.value
    #expect(parts.contains(.streamStart(warnings: [])))
    if case let .finish(finish) = parts.last { #expect(finish.text == "first\nsecond"); #expect(finish.durationInSeconds == 1) } else { Issue.record("Missing finish") }
    #expect(await realtimeWait { socket.connection.closeCalls().count == 1 })
}

@Test(arguments: ["error", "abort", "cancel", "close"])
func WeeklyBFLXAI20261011XAIStreamingTerminationCancelsProducer(_ terminal: String) async throws {
    let socket = RealtimeTestWebSocketTransport()
    let pipe = AIStreamingAudioInput.makeStream()
    let abort = AIAbortController()
    let model = try AIProviders.xAI(settings: .init(apiKey: "key")).streamingTranscriptionModel(webSocketTransport: socket)
    let result = try await model.stream(.init(audio: pipe.input, inputAudioFormat: .init(mediaType: "audio/pcm"), abortSignal: abort.signal))
    let collector = Task { try await weeklyMediumCollect(result.stream) }
    switch terminal {
    case "error": socket.connection.sendJSON(["type": "error", "message": "bad audio"])
    case "abort": abort.abort(reason: "microphone stopped")
    case "cancel": result.cancel()
    default: socket.connection.serverClose(code: 1000)
    }
    do {
        #expect(try await collector.value.isEmpty)
        #expect(terminal == "cancel" || terminal == "close")
    } catch let error as AIStreamingTranscriptionError {
        #expect(terminal == "error")
        #expect(error.message == "bad audio")
        #expect(error.rawValue?["type"] == "error")
    } catch let error as AIAbortError {
        #expect(terminal == "abort")
        #expect(error.reason == "microphone stopped")
    }
    #expect(pipe.writer.send(Data([1])) == .terminated)
    #expect(await realtimeWait { socket.connection.closeCalls().count == 1 })
}

@Test func WeeklyBFLXAI20261011XAIPreAbortedStreamCancelsUnopenedInput() async throws {
    let socket = RealtimeTestWebSocketTransport()
    let pipe = AIStreamingAudioInput.makeStream()
    let abort = AIAbortController()
    abort.abort(reason: "stopped before connection")
    let model = try AIProviders.xAI(settings: .init(apiKey: "key")).streamingTranscriptionModel(webSocketTransport: socket)
    await #expect(throws: AIAbortError.self) {
        _ = try await model.stream(.init(audio: pipe.input, inputAudioFormat: .init(mediaType: "audio/pcm"), abortSignal: abort.signal))
    }
    #expect(socket.requests().isEmpty)
    #expect(pipe.writer.send(Data([1])) == .terminated)
}

@Test(arguments: [20, 21])
func WeeklyBFLXAI20261011XAISearchAcceptsTwentyHandlesAndRejectsMore(_ count: Int) async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"r","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"done"}]}],"status":"completed"}"#))
    let model = try AIProviders.xAI(settings: .init(apiKey: "key", transport: transport)).languageModel("grok-4.6")
    let handles = (0..<count).map { "h\($0)" }
    let request = LanguageModelRequest(messages: [.user("search")], reasoning: "max", tools: ["search": XAITools.xSearch(allowedXHandles: handles, excludedXHandles: handles)])
    if count == 20 {
        _ = try await model.generate(request)
        let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
        #expect(body["tools"]?[0]?["allowed_x_handles"]?.arrayValue?.count == 20)
        #expect(body["reasoning"]?["effort"] == "xhigh")
    } else {
        await #expect(throws: AIError.self) { try await model.generate(request) }
        #expect(await transport.requests().isEmpty)
    }
}
