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
    public static let markdownSnapshotDate = "2026-06-03"

    public static let all: [AIProviderCapabilityRow] = [
        providerRow("alibaba", "@ai-sdk/alibaba", ["AIProviders.alibaba"], [.language, .video]),
        providerRow("amazon-bedrock", "@ai-sdk/amazon-bedrock", ["AIProviders.amazonBedrock"], [.language, .embedding, .image, .reranking]),
        providerRow("amazon-bedrock.anthropic", "@ai-sdk/amazon-bedrock", ["AIProviders.amazonBedrockAnthropic"], [.language]),
        providerRow("bedrock-mantle", "@ai-sdk/amazon-bedrock", ["AIProviders.bedrockMantle", "AIProviders.amazonBedrockMantle"], [.language]),
        providerRow("anthropic", "@ai-sdk/anthropic", ["AIProviders.anthropic"], [.language], files: true, skills: true),
        providerRow("anthropic-aws", "@ai-sdk/anthropic-aws", ["AIProviders.anthropicAWS", "AIProviders.anthropicAws"], [.language], files: true, skills: true),
        providerRow("assemblyai", "@ai-sdk/assemblyai", ["AIProviders.assemblyAI", "AIProviders.assemblyai"], [.transcription]),
        providerRow("azure", "@ai-sdk/azure", ["AIProviders.azure", "AIProviders.azureOpenAI", "AIProviders.azureOpenai"], [.language, .completion, .embedding, .image, .transcription, .speech]),
        providerRow("baseten", "@ai-sdk/baseten", ["AIProviders.baseten"], [.language, .embedding], notes: "`ProviderSettings.modelURL` selects dedicated Baseten endpoints: chat uses `/sync/v1`, rejects `/predict`, and falls back to the Model API for plain `/sync`, while embeddings require `/sync` or `/sync/v1`."),
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
        providerRow("moonshotai", "@ai-sdk/moonshotai", ["AIProviders.moonshotAI", "AIProviders.moonshotai"], [.language], notes: "Chat requests stream usage by default and maps `providerOptions.moonshotai` thinking/reasoningHistory through the upstream option schema."),
        providerRow("open-responses.responses", "@ai-sdk/open-responses", ["AIProviders.openResponses"], [.language], notes: "Custom URL factory; provider ID is derived from the caller supplied name. Uses the upstream open-responses request builder, optional API key, versioned user-agent suffix, and the caller supplied providerOptions namespace."),
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

    public static func markdownDocument(snapshotDate: String = markdownSnapshotDate) -> String {
        var lines: [String] = [
            "# Provider Capability Matrix",
            "",
            "Snapshot date: \(snapshotDate)",
            "",
            "This document is generated from `AIProviderCapabilities` in",
            "`Sources/SwiftAISDK/Providers/ProviderCapabilityMatrix.swift`. Update that",
            "file first when adding or changing provider coverage; the drift test will",
            "fail until this document is regenerated from the same source.",
            "",
            "Legend:",
            "",
            "- `L`: language",
            "- `C`: completion",
            "- `E`: embedding",
            "- `I`: image",
            "- `T`: transcription",
            "- `S`: speech",
            "- `V`: video",
            "- `R`: reranking",
            "- `F`: file upload client",
            "- `K`: skill upload client",
            "",
            markdownTable(),
        ]

        let rowsWithNotes = all.filter { $0.notes != nil }
        if !rowsWithNotes.isEmpty {
            lines.append(contentsOf: [
                "",
                "## Provider Notes",
                "",
                "| Provider ID | Note |",
                "| --- | --- |",
            ])

            for row in rowsWithNotes {
                lines.append("| `\(escapeMarkdownTable(row.providerID))` | \(escapeMarkdownTable(row.notes ?? "")) |")
            }
        }

        lines.append(contentsOf: [
            "",
            "## Reality Gates",
            "",
            "Use three gates when judging provider completeness:",
            "",
            "1. The provider appears in `AIProviderCapabilities.all`.",
            "2. Unit tests cover the request and response or stream shape for every",
            "   supported capability in the matrix.",
            "3. At least one opt-in live smoke test exists for representative first-party",
            "   providers and can be run with real keys.",
            "",
            "The live smoke suite is intentionally off by default. Run it with:",
            "",
            "```sh",
            "LIVE_AI_TESTS=1 swift test --filter LiveProviderSmoke",
            "```",
            "",
            "The suite reads `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, and `GEMINI_API_KEY`",
            "first, then falls back to `openai-api-key.txt`, `claude-api-key.txt`, and",
            "`gemini-api-key.txt` in the package root. Override model IDs with",
            "`LIVE_OPENAI_MODEL`, `LIVE_ANTHROPIC_MODEL`, and `LIVE_GOOGLE_MODEL`.",
            "It covers text generation, text streaming, executable generate/stream tool loops, and",
            "representative embeddings. Embedding checks also read",
            "`LIVE_OPENAI_EMBEDDING_MODEL` and `LIVE_GOOGLE_EMBEDDING_MODEL`.",
            "",
        ])

        return lines.joined(separator: "\n")
    }

    public static func markdownTable() -> String {
        let header = "| Upstream package | Provider ID | Swift factories | L | C | E | I | T | S | V | R | F | K |"
        let separator = "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"
        let rows = all.map { row in
            let values = capabilityColumns.map { column in
                row.supports(column.capability) ? "yes" : ""
            }
            let flags = values + [
                row.supportsFileUpload ? "yes" : "",
                row.supportsSkillUpload ? "yes" : "",
            ]
            return (
                [
                    "`\(escapeMarkdownTable(row.upstreamPackage))`",
                    "`\(escapeMarkdownTable(row.providerID))`",
                    row.factoryNames.map { "`\(escapeMarkdownTable($0))`" }.joined(separator: ", "),
                ] + flags
            ).asMarkdownTableRow()
        }

        return ([header, separator] + rows).joined(separator: "\n")
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

private let capabilityColumns: [(label: String, capability: ModelCapability)] = [
    ("L", .language),
    ("C", .completion),
    ("E", .embedding),
    ("I", .image),
    ("T", .transcription),
    ("S", .speech),
    ("V", .video),
    ("R", .reranking),
]

private func escapeMarkdownTable(_ value: String) -> String {
    value.replacingOccurrences(of: "|", with: "\\|")
}

private extension Array where Element == String {
    func asMarkdownTableRow() -> String {
        "| \(joined(separator: " | ")) |"
    }
}
