import Foundation
import Testing
@testable import SwiftAISDK

@Test func providerCapabilityMatrixDocumentationMatchesGeneratedMarkdown() throws {
    let documentURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Docs/ProviderCapabilityMatrix.md")
    let document = try String(contentsOf: documentURL, encoding: .utf8)

    #expect(document == AIProviderCapabilities.markdownDocument())
}

@Test func providerCapabilityMatrixCoversDiscoveredProviderPackages() {
    let expectedPackages: Set<String> = [
        "@ai-sdk/alibaba",
        "@ai-sdk/amazon-bedrock",
        "@ai-sdk/anthropic",
        "@ai-sdk/anthropic-aws",
        "@ai-sdk/assemblyai",
        "@ai-sdk/azure",
        "@ai-sdk/baseten",
        "@ai-sdk/black-forest-labs",
        "@ai-sdk/bytedance",
        "@ai-sdk/cerebras",
        "@ai-sdk/cohere",
        "@ai-sdk/deepgram",
        "@ai-sdk/deepinfra",
        "@ai-sdk/deepseek",
        "@ai-sdk/elevenlabs",
        "@ai-sdk/fal",
        "@ai-sdk/fireworks",
        "@ai-sdk/gateway",
        "@ai-sdk/gladia",
        "@ai-sdk/google",
        "@ai-sdk/google-vertex",
        "@ai-sdk/groq",
        "@ai-sdk/huggingface",
        "@ai-sdk/hume",
        "@ai-sdk/klingai",
        "@ai-sdk/lmnt",
        "@ai-sdk/luma",
        "@ai-sdk/mistral",
        "@ai-sdk/moonshotai",
        "@ai-sdk/open-responses",
        "@ai-sdk/openai",
        "@ai-sdk/openai-compatible",
        "@ai-sdk/perplexity",
        "@ai-sdk/prodia",
        "@ai-sdk/quiverai",
        "@ai-sdk/replicate",
        "@ai-sdk/revai",
        "@ai-sdk/togetherai",
        "@ai-sdk/vercel",
        "@ai-sdk/voyage",
        "@ai-sdk/xai"
    ]

    let actualPackages = Set(AIProviderCapabilities.all.map(\.upstreamPackage))
    #expect(actualPackages == expectedPackages)
}

@Test func providerCapabilityMatrixHasUniqueProviderIDsAndFactories() {
    let rows = AIProviderCapabilities.all
    #expect(Set(rows.map(\.providerID)).count == rows.count)
    #expect(rows.allSatisfy { !$0.factoryNames.isEmpty })
    #expect(rows.allSatisfy { !$0.supportedCapabilities.isEmpty })
}

@Test func providerCapabilityMatrixMatchesRepresentativeRegistryCapabilities() throws {
    let openAI = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key"))
    let openAIRow = try #require(AIProviderCapabilities.row(providerID: "openai"))
    #expect(openAIRow.supportedCapabilities == openAI.supportedCapabilities)
    #expect(openAIRow.supportsFileUpload)
    #expect(openAIRow.supportsSkillUpload)

    let anthropicRow = try #require(AIProviderCapabilities.row(providerID: "anthropic"))
    #expect(anthropicRow.supports(.language))
    #expect(!anthropicRow.supports(.embedding))
    #expect(anthropicRow.supportsFileUpload)
    #expect(anthropicRow.supportsSkillUpload)

    let voyage = try AIProviders.voyage(settings: ProviderSettings(apiKey: "voyage-key"))
    let voyageRow = try #require(AIProviderCapabilities.row(providerID: "voyage"))
    #expect(voyageRow.supportedCapabilities == voyage.supportedCapabilities)
    #expect(voyageRow.supports(.embedding))
    #expect(voyageRow.supports(.reranking))

    let gateway = try AIProviders.gateway(settings: ProviderSettings(apiKey: "gateway-key"))
    let gatewayRow = try #require(AIProviderCapabilities.row(providerID: "gateway"))
    #expect(gatewayRow.supportedCapabilities == gateway.supportedCapabilities)
    #expect(!gatewayRow.supports(.audioGeneration))
    #expect(!gatewayRow.supports(.audioTransformation))
    #expect(!gatewayRow.supports(.dubbing))
}
