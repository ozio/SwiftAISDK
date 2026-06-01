import Foundation
import Testing
@testable import SwiftAISDK

@Test func googleVertexLanguageForwardsAbortSignalToProviderRequest() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"vertex"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        apiKey: "vertex-key",
        baseURL: "https://api.example.com",
        transport: transport
    ))
    let model = try provider.languageModel("gemini-2.5-pro")
    let controller = AIAbortController()

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], abortSignal: controller.signal))

    let request = try #require(await transport.requests().first)
    #expect(request.abortSignal === controller.signal)
}

@Test func amazonBedrockLanguageForwardsAbortSignalThroughSigV4Request() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"output":{"message":{"content":[{"text":"bedrock"}]}},"stopReason":"end_turn","usage":{"inputTokens":1,"outputTokens":1,"totalTokens":2}}
    """))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        accessKeyID: "AKIDEXAMPLE",
        secretAccessKey: "secret",
        transport: transport
    ))
    let model = try provider.languageModel("anthropic.claude-3-haiku-20240307-v1:0")
    let controller = AIAbortController()

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")], abortSignal: controller.signal))

    let request = try #require(await transport.requests().first)
    #expect(request.abortSignal === controller.signal)
}

@Test func cohereLanguageForwardsAbortSignalToGenerateAndStreamRequests() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"generation_id":"gen-1","message":{"role":"assistant","content":[{"type":"text","text":"cohere"}]},"finish_reason":"COMPLETE","usage":{"tokens":{"input_tokens":1,"output_tokens":1}}}
    """))
    let generateProvider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: generateTransport))
    let generateModel = try generateProvider.languageModel("command-a-03-2025")
    let generateController = AIAbortController()

    _ = try await generateModel.generate(LanguageModelRequest(messages: [.user("Hi")], abortSignal: generateController.signal))

    let generateRequest = try #require(await generateTransport.requests().first)
    #expect(generateRequest.abortSignal === generateController.signal)

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"type":"content-delta","index":0,"delta":{"message":{"content":{"text":"cohere"}}}}

    data: {"type":"message-end","delta":{"finish_reason":"COMPLETE","usage":{"tokens":{"input_tokens":1,"output_tokens":1}}}}

    """))
    let streamProvider = try AIProviders.cohere(settings: ProviderSettings(apiKey: "cohere-key", transport: streamTransport))
    let streamModel = try streamProvider.languageModel("command-a-03-2025")
    let streamController = AIAbortController()

    for try await _ in streamModel.stream(LanguageModelRequest(messages: [.user("Hi")], abortSignal: streamController.signal)) {}

    let streamRequest = try #require(await streamTransport.requests().first)
    #expect(streamRequest.abortSignal === streamController.signal)
}

@Test func replicateImageForwardsAbortSignalToSubmitAndDownloadRequests() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"pred-1","status":"succeeded","output":["https://replicate.example.com/image.png"]}
        """),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("png".utf8))
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/flux-schnell")
    let controller = AIAbortController()

    _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", abortSignal: controller.signal))

    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].abortSignal === controller.signal)
    #expect(requests[1].abortSignal === controller.signal)
}

@Test func googleVideoForwardsAbortSignalToCreateAndPollRequests() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"name":"operations/video-1","done":false}"#),
        jsonResponse(#"{"name":"operations/video-1","done":true,"response":{"generateVideoResponse":{"generatedSamples":[{"video":{"uri":"https://generativelanguage.googleapis.com/files/video-123.mp4?alt=media"}}]}}}"#)
    ])
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.videoModel("veo-3.1-generate-preview")
    let controller = AIAbortController()

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        extraBody: ["pollIntervalMs": 0],
        abortSignal: controller.signal
    ))

    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].abortSignal === controller.signal)
    #expect(requests[1].abortSignal === controller.signal)
}

@Test func xAIVideoForwardsAbortSignalToCreateAndPollRequests() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"vid-1"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/video.mp4","respect_moderation":true}}"#)
    ])
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try provider.videoModel("grok-2-video")
    let controller = AIAbortController()

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        extraBody: ["pollIntervalMs": 0],
        abortSignal: controller.signal
    ))

    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].abortSignal === controller.signal)
    #expect(requests[1].abortSignal === controller.signal)
}

@Test func fireworksAsyncImageForwardsAbortSignalToSubmitPollAndDownloadRequests() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"fw-1"}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://assets.example.com/fireworks.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("png".utf8))
    ])
    let provider = try AIProviders.fireworks(settings: ProviderSettings(apiKey: "fireworks-key", transport: transport))
    let model = try provider.imageModel("accounts/fireworks/models/flux-kontext-pro")
    let controller = AIAbortController()

    _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", abortSignal: controller.signal))

    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].abortSignal === controller.signal)
    #expect(requests[1].abortSignal === controller.signal)
    #expect(requests[2].abortSignal === controller.signal)
}
