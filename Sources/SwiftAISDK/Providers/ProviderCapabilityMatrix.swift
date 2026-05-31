import Foundation

public struct AIProviderCapabilityRow: Equatable, Sendable {
    public var providerID: String
    public var upstreamPackage: String
    public var factoryNames: [String]
    public var supportedCapabilities: Set<ModelCapability>
    public var supportsFileUpload: Bool
    public var supportsSkillUpload: Bool
    public var notes: String?

    public init(
        providerID: String,
        upstreamPackage: String,
        factoryNames: [String],
        supportedCapabilities: Set<ModelCapability>,
        supportsFileUpload: Bool = false,
        supportsSkillUpload: Bool = false,
        notes: String? = nil
    ) {
        self.providerID = providerID
        self.upstreamPackage = upstreamPackage
        self.factoryNames = factoryNames
        self.supportedCapabilities = supportedCapabilities
        self.supportsFileUpload = supportsFileUpload
        self.supportsSkillUpload = supportsSkillUpload
        self.notes = notes
    }

    public func supports(_ capability: ModelCapability) -> Bool {
        supportedCapabilities.contains(capability)
    }
}

public enum AIProviderCapabilities {
    public static let all: [AIProviderCapabilityRow] = [
        providerRow("alibaba", "@ai-sdk/alibaba", ["AIProviders.alibaba"], [.language, .video]),
        providerRow("amazon-bedrock", "@ai-sdk/amazon-bedrock", ["AIProviders.amazonBedrock"], [.language, .embedding, .image, .reranking]),
        providerRow("amazon-bedrock.anthropic", "@ai-sdk/amazon-bedrock", ["AIProviders.amazonBedrockAnthropic"], [.language]),
        providerRow("bedrock-mantle", "@ai-sdk/amazon-bedrock", ["AIProviders.bedrockMantle", "AIProviders.amazonBedrockMantle"], [.language]),
        providerRow("anthropic", "@ai-sdk/anthropic", ["AIProviders.anthropic"], [.language], files: true, skills: true),
        providerRow("anthropic-aws", "@ai-sdk/anthropic-aws", ["AIProviders.anthropicAWS", "AIProviders.anthropicAws"], [.language], files: true, skills: true),
        providerRow("assemblyai", "@ai-sdk/assemblyai", ["AIProviders.assemblyAI", "AIProviders.assemblyai"], [.transcription]),
        providerRow("azure", "@ai-sdk/azure", ["AIProviders.azure"], [.language, .completion, .embedding, .image, .transcription, .speech]),
        providerRow("baseten", "@ai-sdk/baseten", ["AIProviders.baseten"], [.language, .embedding], notes: "Embedding requires a synchronous model URL, matching the upstream Baseten split."),
        providerRow("black-forest-labs", "@ai-sdk/black-forest-labs", ["AIProviders.blackForestLabs"], [.image]),
        providerRow("bytedance", "@ai-sdk/bytedance", ["AIProviders.byteDance", "AIProviders.bytedance"], [.video]),
        providerRow("cerebras", "@ai-sdk/cerebras", ["AIProviders.cerebras"], [.language]),
        providerRow("cohere", "@ai-sdk/cohere", ["AIProviders.cohere"], [.language, .embedding, .reranking]),
        providerRow("deepgram", "@ai-sdk/deepgram", ["AIProviders.deepgram"], [.transcription, .speech]),
        providerRow("deepinfra", "@ai-sdk/deepinfra", ["AIProviders.deepInfra", "AIProviders.deepinfra"], [.language, .completion, .embedding, .image]),
        providerRow("deepseek", "@ai-sdk/deepseek", ["AIProviders.deepSeek", "AIProviders.deepseek"], [.language]),
        providerRow("elevenlabs", "@ai-sdk/elevenlabs", ["AIProviders.elevenLabs", "AIProviders.elevenlabs"], [.transcription, .speech]),
        providerRow("fal", "@ai-sdk/fal", ["AIProviders.fal"], [.image, .transcription, .speech, .video]),
        providerRow("fireworks", "@ai-sdk/fireworks", ["AIProviders.fireworks"], [.language, .completion, .embedding, .image]),
        providerRow("gateway", "@ai-sdk/gateway", ["AIProviders.gateway"], Set(ModelCapability.allCases), notes: "Gateway also exposes model, credits, spend, and generation metadata management APIs."),
        providerRow("gladia", "@ai-sdk/gladia", ["AIProviders.gladia"], [.transcription]),
        providerRow("google.generative-ai", "@ai-sdk/google", ["AIProviders.google"], [.language, .embedding, .image, .video], files: true, notes: "Also exposes Gemini interactions models and agents."),
        providerRow("google.vertex", "@ai-sdk/google-vertex", ["AIProviders.googleVertex"], [.language, .embedding, .image, .video]),
        providerRow("googleVertex.maas", "@ai-sdk/google-vertex", ["AIProviders.googleVertexMaaS"], [.language, .completion, .embedding, .image]),
        providerRow("googleVertex.xai", "@ai-sdk/google-vertex", ["AIProviders.googleVertexXAI"], [.language]),
        providerRow("googleVertex.anthropic", "@ai-sdk/google-vertex", ["AIProviders.googleVertexAnthropic"], [.language]),
        providerRow("groq", "@ai-sdk/groq", ["AIProviders.groq"], [.language, .transcription]),
        providerRow("huggingface", "@ai-sdk/huggingface", ["AIProviders.huggingFace", "AIProviders.huggingface"], [.language]),
        providerRow("hume", "@ai-sdk/hume", ["AIProviders.hume"], [.speech]),
        providerRow("klingai", "@ai-sdk/klingai", ["AIProviders.klingAI", "AIProviders.klingai"], [.video]),
        providerRow("lmnt", "@ai-sdk/lmnt", ["AIProviders.lmnt"], [.speech]),
        providerRow("luma", "@ai-sdk/luma", ["AIProviders.luma"], [.image]),
        providerRow("mistral", "@ai-sdk/mistral", ["AIProviders.mistral"], [.language, .embedding]),
        providerRow("moonshotai", "@ai-sdk/moonshotai", ["AIProviders.moonshotAI", "AIProviders.moonshotai"], [.language]),
        providerRow("open-responses.responses", "@ai-sdk/open-responses", ["AIProviders.openResponses"], [.language], notes: "Custom URL factory; provider ID is derived from the caller supplied name."),
        providerRow("openai", "@ai-sdk/openai", ["AIProviders.openAI", "AIProviders.openai"], [.language, .completion, .embedding, .image, .transcription, .speech], files: true, skills: true),
        providerRow("openai-compatible", "@ai-sdk/openai-compatible", ["AIProviders.openAICompatible", "AIProviders.openaiCompatible"], [.language, .completion, .embedding, .image], notes: "Generic OpenAI-compatible factory; caller supplies provider ID and base URL."),
        providerRow("perplexity", "@ai-sdk/perplexity", ["AIProviders.perplexity"], [.language]),
        providerRow("prodia", "@ai-sdk/prodia", ["AIProviders.prodia"], [.language, .image, .video]),
        providerRow("quiverai", "@ai-sdk/quiverai", ["AIProviders.quiverAI", "AIProviders.quiverai"], [.image]),
        providerRow("replicate", "@ai-sdk/replicate", ["AIProviders.replicate"], [.image, .video]),
        providerRow("revai", "@ai-sdk/revai", ["AIProviders.revAI", "AIProviders.revai"], [.transcription]),
        providerRow("togetherai", "@ai-sdk/togetherai", ["AIProviders.togetherAI", "AIProviders.togetherai"], [.language, .completion, .embedding, .image, .reranking]),
        providerRow("vercel", "@ai-sdk/vercel", ["AIProviders.vercel"], [.language]),
        providerRow("voyage", "@ai-sdk/voyage", ["AIProviders.voyage"], [.embedding, .reranking]),
        providerRow("xai", "@ai-sdk/xai", ["AIProviders.xAI", "AIProviders.xai"], [.language, .image, .video], files: true)
    ]

    public static func row(providerID: String) -> AIProviderCapabilityRow? {
        all.first { $0.providerID == providerID }
    }

    public static func rows(upstreamPackage: String) -> [AIProviderCapabilityRow] {
        all.filter { $0.upstreamPackage == upstreamPackage }
    }
}

private func providerRow(
    _ providerID: String,
    _ upstreamPackage: String,
    _ factoryNames: [String],
    _ capabilities: Set<ModelCapability>,
    files: Bool = false,
    skills: Bool = false,
    notes: String? = nil
) -> AIProviderCapabilityRow {
    AIProviderCapabilityRow(
        providerID: providerID,
        upstreamPackage: upstreamPackage,
        factoryNames: factoryNames,
        supportedCapabilities: capabilities,
        supportsFileUpload: files,
        supportsSkillUpload: skills,
        notes: notes
    )
}
