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

@Test func mistralLanguageForwardsAbortSignalToGenerateAndStreamRequests() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"id":"cmpl-1","model":"mistral-small-latest","choices":[{"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]}
    """))
    let generateProvider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: generateTransport))
    let generateModel = try generateProvider.languageModel("mistral-small-latest")
    let generateController = AIAbortController()

    _ = try await generateModel.generate(LanguageModelRequest(messages: [.user("Hi")], abortSignal: generateController.signal))

    let generateRequest = try #require(await generateTransport.requests().first)
    #expect(generateRequest.abortSignal === generateController.signal)

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"id":"cmpl-1","model":"mistral-small-latest","choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}

    """))
    let streamProvider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: streamTransport))
    let streamModel = try streamProvider.languageModel("mistral-small-latest")
    let streamController = AIAbortController()

    for try await _ in streamModel.stream(LanguageModelRequest(messages: [.user("Hi")], abortSignal: streamController.signal)) {}

    let streamRequest = try #require(await streamTransport.requests().first)
    #expect(streamRequest.abortSignal === streamController.signal)
}

@Test func cerebrasLanguageForwardsAbortSignalToGenerateAndStreamRequests() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"id":"cerebras-1","model":"zai-glm-4.7","choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}
    """))
    let generateProvider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: generateTransport))
    let generateModel = try generateProvider.languageModel("zai-glm-4.7")
    let generateController = AIAbortController()

    _ = try await generateModel.generate(LanguageModelRequest(messages: [.user("Hi")], abortSignal: generateController.signal))

    let generateRequest = try #require(await generateTransport.requests().first)
    #expect(generateRequest.abortSignal === generateController.signal)

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"id":"cerebras-1","model":"zai-glm-4.7","choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}

    """))
    let streamProvider = try AIProviders.cerebras(settings: ProviderSettings(apiKey: "cerebras-key", transport: streamTransport))
    let streamModel = try streamProvider.languageModel("zai-glm-4.7")
    let streamController = AIAbortController()

    for try await _ in streamModel.stream(LanguageModelRequest(messages: [.user("Hi")], abortSignal: streamController.signal)) {}

    let streamRequest = try #require(await streamTransport.requests().first)
    #expect(streamRequest.abortSignal === streamController.signal)
}

@Test func alibabaLanguageForwardsAbortSignalToGenerateAndStreamRequests() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"id":"alibaba-1","model":"qwen3-max","choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}
    """))
    let generateProvider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: generateTransport))
    let generateModel = try generateProvider.languageModel("qwen3-max")
    let generateController = AIAbortController()

    _ = try await generateModel.generate(LanguageModelRequest(messages: [.user("Hi")], abortSignal: generateController.signal))

    let generateRequest = try #require(await generateTransport.requests().first)
    #expect(generateRequest.abortSignal === generateController.signal)

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"id":"alibaba-1","model":"qwen3-max","choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}

    """))
    let streamProvider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "dashscope-key", transport: streamTransport))
    let streamModel = try streamProvider.languageModel("qwen3-max")
    let streamController = AIAbortController()

    for try await _ in streamModel.stream(LanguageModelRequest(messages: [.user("Hi")], abortSignal: streamController.signal)) {}

    let streamRequest = try #require(await streamTransport.requests().first)
    #expect(streamRequest.abortSignal === streamController.signal)
}

@Test func deepSeekLanguageForwardsAbortSignalToGenerateAndStreamRequests() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"id":"deepseek-1","model":"deepseek-chat","choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}
    """))
    let generateProvider = try AIProviders.deepSeek(settings: ProviderSettings(apiKey: "deepseek-key", transport: generateTransport))
    let generateModel = try generateProvider.languageModel("deepseek-chat")
    let generateController = AIAbortController()

    _ = try await generateModel.generate(LanguageModelRequest(messages: [.user("Hi")], abortSignal: generateController.signal))

    let generateRequest = try #require(await generateTransport.requests().first)
    #expect(generateRequest.abortSignal === generateController.signal)

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"id":"deepseek-1","model":"deepseek-chat","choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}

    """))
    let streamProvider = try AIProviders.deepSeek(settings: ProviderSettings(apiKey: "deepseek-key", transport: streamTransport))
    let streamModel = try streamProvider.languageModel("deepseek-chat")
    let streamController = AIAbortController()

    for try await _ in streamModel.stream(LanguageModelRequest(messages: [.user("Hi")], abortSignal: streamController.signal)) {}

    let streamRequest = try #require(await streamTransport.requests().first)
    #expect(streamRequest.abortSignal === streamController.signal)
}

@Test func groqLanguageForwardsAbortSignalToGenerateAndStreamRequests() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"id":"groq-1","model":"llama-3.3-70b-versatile","choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}
    """))
    let generateProvider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: generateTransport))
    let generateModel = try generateProvider.languageModel("llama-3.3-70b-versatile")
    let generateController = AIAbortController()

    _ = try await generateModel.generate(LanguageModelRequest(messages: [.user("Hi")], abortSignal: generateController.signal))

    let generateRequest = try #require(await generateTransport.requests().first)
    #expect(generateRequest.abortSignal === generateController.signal)

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"id":"groq-1","model":"llama-3.3-70b-versatile","choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}

    """))
    let streamProvider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: streamTransport))
    let streamModel = try streamProvider.languageModel("llama-3.3-70b-versatile")
    let streamController = AIAbortController()

    for try await _ in streamModel.stream(LanguageModelRequest(messages: [.user("Hi")], abortSignal: streamController.signal)) {}

    let streamRequest = try #require(await streamTransport.requests().first)
    #expect(streamRequest.abortSignal === streamController.signal)
}

@Test func perplexityLanguageForwardsAbortSignalToGenerateAndStreamRequests() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"id":"ppl-1","created":1710000000,"model":"sonar","choices":[{"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]}
    """))
    let generateProvider = try AIProviders.perplexity(settings: ProviderSettings(apiKey: "pplx-key", transport: generateTransport))
    let generateModel = try generateProvider.languageModel("sonar")
    let generateController = AIAbortController()

    _ = try await generateModel.generate(LanguageModelRequest(messages: [.user("Hi")], abortSignal: generateController.signal))

    let generateRequest = try #require(await generateTransport.requests().first)
    #expect(generateRequest.abortSignal === generateController.signal)

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"id":"ppl-1","created":1710000000,"model":"sonar","choices":[{"delta":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]}

    """))
    let streamProvider = try AIProviders.perplexity(settings: ProviderSettings(apiKey: "pplx-key", transport: streamTransport))
    let streamModel = try streamProvider.languageModel("sonar")
    let streamController = AIAbortController()

    for try await _ in streamModel.stream(LanguageModelRequest(messages: [.user("Hi")], abortSignal: streamController.signal)) {}

    let streamRequest = try #require(await streamTransport.requests().first)
    #expect(streamRequest.abortSignal === streamController.signal)
}

@Test func moonshotLanguageForwardsAbortSignalToGenerateAndStreamRequests() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"id":"moonshot-1","model":"kimi-k2","choices":[{"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]}
    """))
    let generateProvider = try AIProviders.moonshotAI(settings: ProviderSettings(apiKey: "moonshot-key", transport: generateTransport))
    let generateModel = try generateProvider.languageModel("kimi-k2")
    let generateController = AIAbortController()

    _ = try await generateModel.generate(LanguageModelRequest(messages: [.user("Hi")], abortSignal: generateController.signal))

    let generateRequest = try #require(await generateTransport.requests().first)
    #expect(generateRequest.abortSignal === generateController.signal)

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"id":"moonshot-1","model":"kimi-k2","choices":[{"delta":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]}

    """))
    let streamProvider = try AIProviders.moonshotAI(settings: ProviderSettings(apiKey: "moonshot-key", transport: streamTransport))
    let streamModel = try streamProvider.languageModel("kimi-k2")
    let streamController = AIAbortController()

    for try await _ in streamModel.stream(LanguageModelRequest(messages: [.user("Hi")], abortSignal: streamController.signal)) {}

    let streamRequest = try #require(await streamTransport.requests().first)
    #expect(streamRequest.abortSignal === streamController.signal)
}

@Test func basetenForwardsAbortSignalToChatStreamAndEmbeddingRequests() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]}
    """))
    let generateProvider = try AIProviders.baseten(settings: ProviderSettings(apiKey: "baseten-key", transport: generateTransport))
    let generateModel = try generateProvider.languageModel("deepseek-ai/DeepSeek-V3-0324")
    let generateController = AIAbortController()

    _ = try await generateModel.generate(LanguageModelRequest(messages: [.user("Hi")], abortSignal: generateController.signal))

    let generateRequest = try #require(await generateTransport.requests().first)
    #expect(generateRequest.abortSignal === generateController.signal)

    let streamTransport = RecordingTransport(response: sseResponse("""
    data: {"choices":[{"delta":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]}

    """))
    let streamProvider = try AIProviders.baseten(settings: ProviderSettings(apiKey: "baseten-key", transport: streamTransport))
    let streamModel = try streamProvider.languageModel("deepseek-ai/DeepSeek-V3-0324")
    let streamController = AIAbortController()

    for try await _ in streamModel.stream(LanguageModelRequest(messages: [.user("Hi")], abortSignal: streamController.signal)) {}

    let streamRequest = try #require(await streamTransport.requests().first)
    #expect(streamRequest.abortSignal === streamController.signal)

    let embeddingTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"embedding":[0.1]}]}"#))
    let embeddingProvider = try AIProviders.baseten(settings: ProviderSettings(
        apiKey: "baseten-key",
        modelURL: "https://model-123.api.baseten.co/environments/production/sync",
        transport: embeddingTransport
    ))
    let embeddingModel = try embeddingProvider.embeddingModel()
    let embeddingController = AIAbortController()

    _ = try await embeddingModel.embed(EmbeddingRequest(values: ["Hi"], abortSignal: embeddingController.signal))

    let embeddingRequest = try #require(await embeddingTransport.requests().first)
    #expect(embeddingRequest.abortSignal === embeddingController.signal)
}

@Test func togetherAIForwardsAbortSignalToImageAndRerankingRequests() async throws {
    let imageTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"image"}]}"#))
    let imageProvider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("black-forest-labs/FLUX.1-schnell-Free")
    let imageController = AIAbortController()

    _ = try await imageModel.generateImage(ImageGenerationRequest(prompt: "cat", abortSignal: imageController.signal))

    let imageRequest = try #require(await imageTransport.requests().first)
    #expect(imageRequest.abortSignal === imageController.signal)

    let rerankTransport = RecordingTransport(response: jsonResponse(#"{"results":[{"index":0,"relevance_score":0.9}]}"#))
    let rerankProvider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: rerankTransport))
    let rerankModel = try rerankProvider.rerankingModel("Salesforce/Llama-Rank-v1")
    let rerankController = AIAbortController()

    _ = try await rerankModel.rerank(RerankingRequest(query: "q", documents: ["a"], abortSignal: rerankController.signal))

    let rerankRequest = try #require(await rerankTransport.requests().first)
    #expect(rerankRequest.abortSignal === rerankController.signal)
}

@Test func deepgramForwardsAbortSignalToTranscriptionAndSpeechRequests() async throws {
    let transcriptionTransport = RecordingTransport(response: jsonResponse(#"{"results":{"channels":[{"alternatives":[{"transcript":"deepgram"}]}]}}"#))
    let transcriptionProvider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transcriptionTransport))
    let transcriptionModel = try transcriptionProvider.transcriptionModel("nova-3")
    let transcriptionController = AIAbortController()

    _ = try await transcriptionModel.transcribe(AudioTranscriptionRequest(
        audio: Data("wav".utf8),
        mimeType: "audio/wav",
        abortSignal: transcriptionController.signal
    ))

    let transcriptionRequest = try #require(await transcriptionTransport.requests().first)
    #expect(transcriptionRequest.abortSignal === transcriptionController.signal)

    let speechTransport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("audio".utf8)))
    let speechProvider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: speechTransport))
    let speechModel = try speechProvider.speechModel("aura-2-helena-en")
    let speechController = AIAbortController()

    _ = try await speechModel.speak(SpeechRequest(text: "hello", abortSignal: speechController.signal))

    let speechRequest = try #require(await speechTransport.requests().first)
    #expect(speechRequest.abortSignal === speechController.signal)
}

@Test func elevenLabsForwardsAbortSignalToTranscriptionAndSpeechRequests() async throws {
    let transcriptionTransport = RecordingTransport(response: jsonResponse(#"{"language_code":"en","language_probability":0.99,"text":"eleven transcript","words":[]}"#))
    let transcriptionProvider = try AIProviders.elevenLabs(settings: ProviderSettings(apiKey: "eleven-key", transport: transcriptionTransport))
    let transcriptionModel = try transcriptionProvider.transcriptionModel("scribe_v1")
    let transcriptionController = AIAbortController()

    _ = try await transcriptionModel.transcribe(AudioTranscriptionRequest(
        audio: Data("mp3".utf8),
        fileName: "clip.mp3",
        mimeType: "audio/mpeg",
        abortSignal: transcriptionController.signal
    ))

    let transcriptionRequest = try #require(await transcriptionTransport.requests().first)
    #expect(transcriptionRequest.abortSignal === transcriptionController.signal)

    let speechTransport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("audio".utf8)))
    let speechProvider = try AIProviders.elevenLabs(settings: ProviderSettings(apiKey: "eleven-key", transport: speechTransport))
    let speechModel = try speechProvider.speechModel("eleven_multilingual_v2")
    let speechController = AIAbortController()

    _ = try await speechModel.speak(SpeechRequest(text: "hello", abortSignal: speechController.signal))

    let speechRequest = try #require(await speechTransport.requests().first)
    #expect(speechRequest.abortSignal === speechController.signal)
}

@Test func lmntForwardsAbortSignalToSpeechRequests() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("audio".utf8)))
    let provider = try AIProviders.lmnt(settings: ProviderSettings(apiKey: "lmnt-key", transport: transport))
    let model = try provider.speechModel("aurora")
    let controller = AIAbortController()

    _ = try await model.speak(SpeechRequest(text: "hello", abortSignal: controller.signal))

    let request = try #require(await transport.requests().first)
    #expect(request.abortSignal === controller.signal)
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

@Test func falForwardsAbortSignalToImageVideoAndTranscriptionRequests() async throws {
    let imageTransport = RecordingTransport(responses: [
        jsonResponse(#"{"image":{"url":"https://fal.example.com/image.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("png".utf8))
    ])
    let imageProvider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("fal-ai/qwen-image")
    let imageController = AIAbortController()

    _ = try await imageModel.generateImage(ImageGenerationRequest(prompt: "cat", abortSignal: imageController.signal))

    let imageRequests = await imageTransport.requests()
    #expect(imageRequests.count == 2)
    #expect(imageRequests[0].abortSignal === imageController.signal)
    #expect(imageRequests[1].abortSignal === imageController.signal)

    let videoTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"video-1","response_url":"https://queue.fal.run/fal-ai/luma-dream-machine/requests/video-1"}"#),
        jsonResponse(#"{"video":{"url":"https://fal.example.com/video.mp4"}}"#)
    ])
    let videoProvider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: videoTransport))
    let videoModel = try videoProvider.videoModel("fal-ai/luma-dream-machine")
    let videoController = AIAbortController()

    _ = try await videoModel.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        providerOptions: ["fal": .object(["pollIntervalMs": .number(1), "pollTimeoutMs": .number(1_000)])],
        abortSignal: videoController.signal
    ))

    let videoRequests = await videoTransport.requests()
    #expect(videoRequests.count == 2)
    #expect(videoRequests[0].abortSignal === videoController.signal)
    #expect(videoRequests[1].abortSignal === videoController.signal)

    let transcriptionTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"transcription-1"}"#),
        jsonResponse(#"{"text":"fal transcript","chunks":[]}"#)
    ])
    let transcriptionProvider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transcriptionTransport))
    let transcriptionModel = try transcriptionProvider.transcriptionModel("fal-ai/wizper")
    let transcriptionController = AIAbortController()

    _ = try await transcriptionModel.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        mimeType: "audio/wav",
        abortSignal: transcriptionController.signal
    ))

    let transcriptionRequests = await transcriptionTransport.requests()
    #expect(transcriptionRequests.count == 2)
    #expect(transcriptionRequests[0].abortSignal === transcriptionController.signal)
    #expect(transcriptionRequests[1].abortSignal === transcriptionController.signal)
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
