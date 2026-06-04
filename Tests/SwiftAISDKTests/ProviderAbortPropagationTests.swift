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
@Test func amazonBedrockAnthropicForwardsAbortSignalToGenerateAndStreamRequests() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}
    """))
    let generateProvider = try AIProviders.amazonBedrockAnthropic(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        transport: generateTransport
    ))
    let generateController = AIAbortController()

    _ = try await generateProvider.languageModel("anthropic.claude-3-haiku-20240307-v1:0").generate(LanguageModelRequest(messages: [.user("Hi")], abortSignal: generateController.signal))

    let generateRequest = try #require(await generateTransport.requests().first)
    #expect(generateRequest.abortSignal === generateController.signal)

    let streamTransport = RecordingTransport(response: amazonEventStreamResponse([
        ("messageStop", #"{}"#)
    ]))
    let streamProvider = try AIProviders.amazonBedrockAnthropic(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        transport: streamTransport
    ))
    let streamController = AIAbortController()

    for try await _ in try streamProvider.languageModel("anthropic.claude-3-haiku-20240307-v1:0").stream(LanguageModelRequest(messages: [.user("Hi")], abortSignal: streamController.signal)) {}

    let streamRequest = try #require(await streamTransport.requests().first)
    #expect(streamRequest.abortSignal === streamController.signal)
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
@Test func prodiaLanguageForwardsAbortSignalToGenerateAndStreamRequests() async throws {
    let generateTransport = RecordingTransport(response: multipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"prodia-language"}"#.utf8)),
        (name: "output", contentType: "text/plain", body: Data("ok".utf8))
    ]))
    let generateProvider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-key", transport: generateTransport))
    let generateModel = try generateProvider.languageModel("inference.nano-banana.img2img.v2")
    let generateController = AIAbortController()

    _ = try await generateModel.generate(LanguageModelRequest(messages: [.user("Hi")], abortSignal: generateController.signal))

    let generateRequest = try #require(await generateTransport.requests().first)
    #expect(generateRequest.abortSignal === generateController.signal)

    let streamTransport = RecordingTransport(response: multipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"prodia-stream"}"#.utf8)),
        (name: "output", contentType: "text/plain", body: Data("ok".utf8))
    ]))
    let streamProvider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-key", transport: streamTransport))
    let streamModel = try streamProvider.languageModel("inference.nano-banana.img2img.v2")
    let streamController = AIAbortController()

    for try await _ in streamModel.stream(LanguageModelRequest(messages: [.user("Hi")], abortSignal: streamController.signal)) {}

    let streamRequest = try #require(await streamTransport.requests().first)
    #expect(streamRequest.abortSignal === streamController.signal)
}
@Test func prodiaMediaModelsForwardAbortSignalToJobRequests() async throws {
    let imageTransport = RecordingTransport(response: multipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"prodia-image"}"#.utf8)),
        (name: "output", contentType: "image/png", body: Data("png".utf8))
    ]))
    let imageProvider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("inference.flux-fast.schnell.txt2img.v2")
    let imageController = AIAbortController()

    _ = try await imageModel.generateImage(ImageGenerationRequest(prompt: "cat", abortSignal: imageController.signal))

    let imageRequest = try #require(await imageTransport.requests().first)
    #expect(imageRequest.abortSignal === imageController.signal)

    let videoTransport = RecordingTransport(response: multipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"prodia-video"}"#.utf8)),
        (name: "output", contentType: "video/mp4", body: Data("mp4".utf8))
    ]))
    let videoProvider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-key", transport: videoTransport))
    let videoModel = try videoProvider.videoModel("inference.wan2-2.lightning.txt2vid.v0")
    let videoController = AIAbortController()

    _ = try await videoModel.generateVideo(VideoGenerationRequest(prompt: "cat", abortSignal: videoController.signal))

    let videoRequest = try #require(await videoTransport.requests().first)
    #expect(videoRequest.abortSignal === videoController.signal)

    let img2vidTransport = RecordingTransport(response: multipartResponse(parts: [
        (name: "job", contentType: "application/json", body: Data(#"{"id":"prodia-img2vid"}"#.utf8)),
        (name: "output", contentType: "video/mp4", body: Data("mp4".utf8))
    ]))
    let img2vidProvider = try AIProviders.prodia(settings: ProviderSettings(apiKey: "prodia-key", transport: img2vidTransport))
    let img2vidModel = try img2vidProvider.videoModel("inference.wan2-2.lightning.img2vid.v0")
    let img2vidController = AIAbortController()

    _ = try await img2vidModel.generateVideo(VideoGenerationRequest(
        prompt: "cat",
        image: ImageInputFile(data: Data("png".utf8), mediaType: "image/png"),
        abortSignal: img2vidController.signal
    ))

    let img2vidRequest = try #require(await img2vidTransport.requests().first)
    #expect(img2vidRequest.abortSignal === img2vidController.signal)
}
@Test func quiverAIImageForwardsAbortSignalToGenerationRequest() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"svg-1","created":1713374400,"data":[{"svg":"<svg/>","mime_type":"image/svg+xml"}]}
    """))
    let provider = try AIProviders.quiverAI(settings: ProviderSettings(apiKey: "quiver-key", transport: transport))
    let model = try provider.imageModel("arrow-1")
    let controller = AIAbortController()

    _ = try await model.generateImage(ImageGenerationRequest(prompt: "Draw", abortSignal: controller.signal))

    let request = try #require(await transport.requests().first)
    #expect(request.abortSignal === controller.signal)
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
@Test func groqTranscriptionForwardsAbortSignalToMultipartRequest() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"ok","x_groq":{"id":"groq-abort"}}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.transcriptionModel("whisper-large-v3")
    let controller = AIAbortController()

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("wav".utf8),
        abortSignal: controller.signal
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.abortSignal === controller.signal)
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

    let rerankTransport = RecordingTransport(response: jsonResponse(#"{"results":[{"index":0,"relevance_score":0.9}],"usage":{"prompt_tokens":1,"completion_tokens":0,"total_tokens":1}}"#))
    let rerankProvider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: rerankTransport))
    let rerankModel = try rerankProvider.rerankingModel("Salesforce/Llama-Rank-v1")
    let rerankController = AIAbortController()

    _ = try await rerankModel.rerank(RerankingRequest(query: "q", documents: ["a"], abortSignal: rerankController.signal))

    let rerankRequest = try #require(await rerankTransport.requests().first)
    #expect(rerankRequest.abortSignal === rerankController.signal)
}
