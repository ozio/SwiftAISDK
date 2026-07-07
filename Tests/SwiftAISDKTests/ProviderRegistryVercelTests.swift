import Foundation
import Testing
@testable import SwiftAISDK

@Test func providerRegistryConstructsDiscoveredProvidersWithExplicitKeys() throws {
    let transport = RecordingTransport(response: jsonResponse("{}"))
    let settings = ProviderSettings(apiKey: "key", transport: transport)

    _ = try AIProviders.anthropicAWS(settings: AnthropicAWSProviderSettings(region: "us-east-1", workspaceID: "workspace", apiKey: "key", transport: transport))
    _ = try AIProviders.googleVertexMaaS(project: "project", settings: settings)
    _ = try AIProviders.googleVertexXAI(project: "project", settings: settings)
    _ = try AIProviders.googleVertexAnthropic(project: "project", settings: settings)
    _ = try AIProviders.mistral(settings: settings)
    _ = try AIProviders.xAI(settings: settings)
    _ = try AIProviders.deepSeek(settings: settings)
    _ = try AIProviders.togetherAI(settings: settings)
    _ = try AIProviders.cohere(settings: settings)
    _ = try AIProviders.groq(settings: settings)
    _ = try AIProviders.perplexity(settings: settings)
    _ = try AIProviders.fireworks(settings: settings)
    _ = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(region: "us-east-1", accessKeyID: "access", secretAccessKey: "secret", transport: transport))
    _ = try AIProviders.bedrockMantle(settings: AmazonBedrockProviderSettings(region: "us-east-1", accessKeyID: "access", secretAccessKey: "secret", transport: transport))
    _ = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(apiKey: "vertex-key", transport: transport))
    _ = try AIProviders.deepInfra(settings: settings)
    _ = try AIProviders.baseten(settings: settings)
    _ = try AIProviders.cerebras(settings: settings)
    _ = try AIProviders.vercel(settings: settings)
    _ = try AIProviders.alibaba(settings: settings)
    _ = try AIProviders.moonshotAI(settings: settings)
    _ = try AIProviders.huggingFace(settings: settings)
    _ = try AIProviders.replicate(settings: settings)
    _ = try AIProviders.fal(settings: settings)
    _ = try AIProviders.deepgram(settings: settings)
    _ = try AIProviders.assemblyAI(settings: settings)
    _ = try AIProviders.elevenLabs(settings: settings)
    _ = try AIProviders.revAI(settings: settings)
    _ = try AIProviders.gladia(settings: settings)
    _ = try AIProviders.hume(settings: settings)
    _ = try AIProviders.lmnt(settings: settings)
    _ = try AIProviders.blackForestLabs(settings: settings)
    _ = try AIProviders.prodia(settings: settings)
    _ = try AIProviders.luma(settings: settings)
    _ = try AIProviders.klingAI(settings: settings)
    _ = try AIProviders.byteDance(settings: settings)
    _ = try AIProviders.voyage(settings: settings)
    _ = try AIProviders.quiverAI(settings: settings)
    _ = try AIProviders.azure(resourceName: "resource", settings: settings)
    _ = try AIProviders.gateway(settings: settings)
    _ = try AIProviders.openResponses(name: "open-responses", url: "https://example.com/responses", settings: settings)
}

@Test func providerRegistryExposesCanonicalFactoryNames() throws {
    let transport = RecordingTransport(response: jsonResponse("{}"))
    let settings = ProviderSettings(apiKey: "key", transport: transport)

    #expect(try AIProviders.openAI(settings: settings).providerID == "openai")
    #expect(try AIProviders.anthropicAWS(settings: AnthropicAWSProviderSettings(region: "us-east-1", workspaceID: "workspace", apiKey: "key", transport: transport)).providerID == "anthropic-aws")
    #expect(try AIProviders.openAICompatible(name: "compat", baseURL: "https://api.example.com", apiKey: "key", transport: transport).providerID == "compat")
    #expect(try AIProviders.xAI(settings: settings).providerID == "xai")
    #expect(try AIProviders.deepSeek(settings: settings).providerID == "deepseek")
    #expect(try AIProviders.togetherAI(settings: settings).providerID == "togetherai")
    #expect(try AIProviders.deepInfra(settings: settings).providerID == "deepinfra")
    #expect(try AIProviders.moonshotAI(settings: settings).providerID == "moonshotai")
    #expect(try AIProviders.huggingFace(settings: settings).providerID == "huggingface")
    #expect(try AIProviders.assemblyAI(settings: settings).providerID == "assemblyai")
    #expect(try AIProviders.elevenLabs(settings: settings).providerID == "elevenlabs")
    #expect(try AIProviders.revAI(settings: settings).providerID == "revai")
    #expect(try AIProviders.klingAI(settings: settings).providerID == "klingai")
    #expect(try AIProviders.byteDance(settings: settings).providerID == "bytedance")
    #expect(try AIProviders.quiverAI(settings: settings).providerID == "quiverai")
    #expect(try AIProviders.azure(resourceName: "resource", settings: settings).providerID == "azure")
}

@Test func providerFactoryAliasesMirrorUpstreamNames() throws {
    let provider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key", transport: RecordingTransport(response: jsonResponse("{}"))))

    let language = try provider("openai/gpt-4.1-mini")
    let chat = try provider.chat("openai/gpt-4.1-mini")
    let embedding = try provider.embedding("openai/text-embedding-3-small")
    let textEmbeddingModel = try provider.textEmbeddingModel("openai/text-embedding-3-small")
    let textEmbedding = try provider.textEmbedding("openai/text-embedding-3-small")
    let image = try provider.image("openai/gpt-image-1")
    let transcription = try provider.transcription("openai/gpt-4o-transcribe")
    let speech = try provider.speech("openai/gpt-4o-mini-tts")
    let video = try provider.video("fal/minimax/hailuo-02/standard/text-to-video")
    let reranking = try provider.reranking("cohere/rerank-v3.5")

    #expect(language.providerID == "gateway")
    #expect(language.modelID == "openai/gpt-4.1-mini")
    #expect(chat.providerID == "gateway")
    #expect(embedding.providerID == "gateway")
    #expect(textEmbeddingModel.providerID == "gateway")
    #expect(textEmbedding.providerID == "gateway")
    #expect(image.providerID == "gateway")
    #expect(transcription.providerID == "gateway")
    #expect(speech.providerID == "gateway")
    #expect(video.providerID == "gateway")
    #expect(reranking.providerID == "gateway")
}

@Test func vercelLanguageUsesV0EndpointAndChatProviderID() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"v0 response"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}
    """))
    let provider = try AIProviders.vercel(settings: ProviderSettings(apiKey: "vercel-key", transport: transport))
    let model = try provider.languageModel("v0-1.5-md")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Build UI")]))

    #expect(provider.providerID == "vercel")
    #expect(model.providerID == "vercel.chat")
    #expect(result.text == "v0 response")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.v0.dev/v1/chat/completions")
    #expect(request.headers["authorization"] == "Bearer vercel-key")
    #expect(request.headers["user-agent"] == "ai-sdk/vercel/3.0.5")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "v0-1.5-md")
    #expect(body["messages"]?[0]?["content"]?.stringValue == "Build UI")
}

@Test func vercelCallableProviderReturnsChatModelLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"callable v0"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}
    """))
    let provider = try AIProviders.vercel(settings: ProviderSettings(apiKey: "vercel-key", transport: transport))
    let model = try provider("v0-1.5-lg")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Build UI")]))

    #expect(model.providerID == "vercel.chat")
    #expect(model.modelID == "v0-1.5-lg")
    #expect(result.text == "callable v0")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.v0.dev/v1/chat/completions")
    #expect(request.headers["authorization"] == "Bearer vercel-key")
    #expect(request.headers["user-agent"] == "ai-sdk/vercel/3.0.5")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "v0-1.5-lg")
}

@Test func vercelLanguageUsesCustomSettingsLikeUpstreamProvider() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"custom v0"},"finish_reason":"stop"}]}
    """))
    let provider = try AIProviders.vercel(settings: ProviderSettings(
        apiKey: "ignored-key",
        baseURL: "https://custom.v0.example/v1/",
        headers: [
            "Authorization": "Bearer custom-key",
            "Custom-Header": "custom-value",
            "User-Agent": "CustomApp/1.0"
        ],
        transport: transport
    ))
    let model = try provider("v0-1.0-md")

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Build custom UI")]))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://custom.v0.example/v1/chat/completions")
    #expect(request.headers["authorization"] == "Bearer custom-key")
    #expect(request.headers["custom-header"] == "custom-value")
    #expect(request.headers["user-agent"] == "CustomApp/1.0 ai-sdk/vercel/3.0.5")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "v0-1.0-md")
}

@Test func vercelProviderLoadsAPIKeyBeforeCustomAuthorizationOverrideLikeUpstream() async throws {
    #expect(throws: AIError.missingAPIKey(provider: "vercel", environmentVariables: ["VERCEL_API_KEY"])) {
        _ = try AIProviders.vercel(settings: ProviderSettings(
            headers: ["Authorization": "Bearer custom-key"],
            transport: RecordingTransport(response: jsonResponse("{}"))
        ))
    }

    let transport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"custom auth"},"finish_reason":"stop"}]}
    """))
    let provider = try AIProviders.vercel(settings: ProviderSettings(
        apiKey: "loaded-key",
        headers: ["Authorization": "Bearer custom-key"],
        transport: transport
    ))
    let model = try provider.languageModel("v0-1.5-md")

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    let request = try #require(await transport.requests().first)
    #expect(request.headers["authorization"] == "Bearer custom-key")
}

@Test func vercelProviderRejectsUnsupportedModelFamiliesWithVercelID() throws {
    let provider = try AIProviders.vercel(settings: ProviderSettings(apiKey: "vercel-key", transport: RecordingTransport(response: jsonResponse("{}"))))

    #expect(throws: AIError.unsupportedModel(provider: "vercel", capability: .embedding, modelID: "embed")) {
        _ = try provider.embeddingModel("embed")
    }
    #expect(throws: AIError.unsupportedModel(provider: "vercel", capability: .embedding, modelID: "embed")) {
        _ = try provider.textEmbeddingModel("embed")
    }
    #expect(throws: AIError.unsupportedModel(provider: "vercel", capability: .image, modelID: "image")) {
        _ = try provider.imageModel("image")
    }
}
