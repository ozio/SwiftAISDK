import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAICompatibleNativeProviderSurfaceIDsMirrorUpstream() throws {
    let settings = ProviderSettings(apiKey: "key", baseURL: "https://api.example.com", transport: RecordingTransport(response: jsonResponse("{}")))

    let baseten = try AIProviders.baseten(settings: settings)
    #expect(try baseten.languageModel("chat").providerID == "baseten.chat")
    #expect(try baseten.chatModel("chat").providerID == "baseten.chat")

    let deepInfra = try AIProviders.deepInfra(settings: settings)
    #expect(try deepInfra.languageModel("chat").providerID == "deepinfra.chat")
    #expect(try deepInfra.chatModel("chat").providerID == "deepinfra.chat")
    #expect(try deepInfra.completionModel("completion").providerID == "deepinfra.completion")
    #expect(try deepInfra.embeddingModel("embedding").providerID == "deepinfra.embedding")
    #expect(try deepInfra.imageModel("image").providerID == "deepinfra.image")

    let fireworks = try AIProviders.fireworks(settings: settings)
    #expect(try fireworks.languageModel("chat").providerID == "fireworks.chat")
    #expect(try fireworks.chatModel("chat").providerID == "fireworks.chat")
    #expect(try fireworks.completionModel("completion").providerID == "fireworks.completion")
    #expect(try fireworks.embeddingModel("embedding").providerID == "fireworks.embedding")
    #expect(try fireworks.imageModel("image").providerID == "fireworks.image")

    let moonshot = try AIProviders.moonshotAI(settings: settings)
    #expect(try moonshot.languageModel("kimi-k2").providerID == "moonshotai.chat")
    #expect(try moonshot.chatModel("kimi-k2").providerID == "moonshotai.chat")

    let together = try AIProviders.togetherAI(settings: settings)
    #expect(try together.languageModel("chat").providerID == "togetherai.chat")
    #expect(try together.chatModel("chat").providerID == "togetherai.chat")
    #expect(try together.completionModel("completion").providerID == "togetherai.completion")
    #expect(try together.embeddingModel("embedding").providerID == "togetherai.embedding")
    #expect(try together.imageModel("image").providerID == "togetherai.image")
    #expect(try together.rerankingModel("rerank").providerID == "togetherai.reranking")
}
