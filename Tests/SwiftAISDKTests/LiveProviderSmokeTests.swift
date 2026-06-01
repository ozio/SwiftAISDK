import Foundation
import Testing
@testable import SwiftAISDK

@Test func liveProviderSmokeOpenAIGenerateText() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.openAIProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_OPENAI_MODEL", defaultValue: "gpt-4.1-mini"))
    let result = try await AI.generateText(
        model: model,
        prompt: "Reply with two short words.",
        temperature: 0,
        maxOutputTokens: 24,
        retryPolicy: .none
    )

    #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test func liveProviderSmokeOpenAIStreamText() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.openAIProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_OPENAI_MODEL", defaultValue: "gpt-4.1-mini"))
    let text = try await LiveProviderSmoke.collectText(
        from: AI.streamText(
            model: model,
            prompt: "Reply with two short words.",
            temperature: 0,
            maxOutputTokens: 24,
            retryPolicy: .none
        )
    )

    #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test func liveProviderSmokeOpenAIEmbedding() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.openAIProvider()
    let model = try provider.embeddingModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_OPENAI_EMBEDDING_MODEL", defaultValue: "text-embedding-3-small"))
    let result = try await AI.embed(model: model, value: "live embedding smoke", retryPolicy: .none)

    #expect(result.embeddings.count == 1)
    #expect(result.embeddings.first?.isEmpty == false)
}

@Test func liveProviderSmokeOpenAIToolLoop() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.openAIProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_OPENAI_MODEL", defaultValue: "gpt-4.1-mini"))
    try await LiveProviderSmoke.assertToolLoop(model: model, maxOutputTokens: 64)
}

@Test func liveProviderSmokeOpenAIStreamToolLoop() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.openAIProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_OPENAI_MODEL", defaultValue: "gpt-4.1-mini"))
    try await LiveProviderSmoke.assertStreamToolLoop(model: model, maxOutputTokens: 64, expectsToolInputLifecycle: true)
}

@Test func liveProviderSmokeAnthropicGenerateText() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.anthropicProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_ANTHROPIC_MODEL", defaultValue: "claude-haiku-4-5-20251001"))
    let result = try await AI.generateText(
        model: model,
        prompt: "Reply with two short words.",
        temperature: 0,
        maxOutputTokens: 24,
        retryPolicy: .none
    )

    #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test func liveProviderSmokeAnthropicStreamText() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.anthropicProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_ANTHROPIC_MODEL", defaultValue: "claude-haiku-4-5-20251001"))
    let text = try await LiveProviderSmoke.collectText(
        from: AI.streamText(
            model: model,
            prompt: "Reply with two short words.",
            temperature: 0,
            maxOutputTokens: 24,
            retryPolicy: .none
        )
    )

    #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test func liveProviderSmokeAnthropicToolLoop() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.anthropicProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_ANTHROPIC_MODEL", defaultValue: "claude-haiku-4-5-20251001"))
    try await LiveProviderSmoke.assertToolLoop(model: model, maxOutputTokens: 96)
}

@Test func liveProviderSmokeAnthropicStreamToolLoop() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.anthropicProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_ANTHROPIC_MODEL", defaultValue: "claude-haiku-4-5-20251001"))
    try await LiveProviderSmoke.assertStreamToolLoop(model: model, maxOutputTokens: 96, expectsToolInputLifecycle: false)
}

@Test func liveProviderSmokeGoogleGenerateText() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.googleProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_GOOGLE_MODEL", defaultValue: "gemini-flash-lite-latest"))
    let result = try await AI.generateText(
        model: model,
        prompt: "Reply with two short words.",
        temperature: 0,
        maxOutputTokens: 64,
        retryPolicy: .none
    )

    #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test func liveProviderSmokeGoogleStreamText() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.googleProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_GOOGLE_MODEL", defaultValue: "gemini-flash-lite-latest"))
    let text = try await LiveProviderSmoke.collectText(
        from: AI.streamText(
            model: model,
            prompt: "Reply with two short words.",
            temperature: 0,
            maxOutputTokens: 64,
            retryPolicy: .none
        )
    )

    #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test func liveProviderSmokeGoogleEmbedding() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.googleProvider()
    let model = try provider.embeddingModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_GOOGLE_EMBEDDING_MODEL", defaultValue: "gemini-embedding-001"))
    let result = try await AI.embed(model: model, value: "live embedding smoke", retryPolicy: .none)

    #expect(result.embeddings.count == 1)
    #expect(result.embeddings.first?.isEmpty == false)
}

@Test func liveProviderSmokeGoogleToolLoop() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.googleProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_GOOGLE_MODEL", defaultValue: "gemini-flash-lite-latest"))
    try await LiveProviderSmoke.assertToolLoop(model: model, maxOutputTokens: 96)
}

@Test func liveProviderSmokeGoogleStreamToolLoop() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let provider = try LiveProviderSmoke.googleProvider()
    let model = try provider.languageModel(LiveProviderSmoke.modelID(environmentVariable: "LIVE_GOOGLE_MODEL", defaultValue: "gemini-flash-lite-latest"))
    try await LiveProviderSmoke.assertStreamToolLoop(model: model, maxOutputTokens: 96, expectsToolInputLifecycle: true)
}

private enum LiveProviderSmoke {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["LIVE_AI_TESTS"] == "1"
    }

    static func openAIProvider() throws -> OpenAICompatibleProvider {
        let apiKey = try apiKey(environmentVariable: "OPENAI_API_KEY", fileName: "openai-api-key.txt")
        return try AIProviders.openAI(settings: ProviderSettings(apiKey: apiKey))
    }

    static func anthropicProvider() throws -> AnthropicProvider {
        let apiKey = try apiKey(environmentVariable: "ANTHROPIC_API_KEY", fileName: "claude-api-key.txt")
        return try AIProviders.anthropic(settings: ProviderSettings(apiKey: apiKey))
    }

    static func googleProvider() throws -> GoogleGenerativeAIProvider {
        let apiKey = try apiKey(environmentVariable: "GEMINI_API_KEY", fileName: "gemini-api-key.txt")
        return try AIProviders.google(settings: ProviderSettings(apiKey: apiKey))
    }

    static func collectText(from stream: AsyncThrowingStream<LanguageStreamPart, Error>) async throws -> String {
        var text = ""
        for try await part in stream {
            switch part {
            case let .textDelta(delta):
                text += delta
            case let .textDeltaPart(_, delta, _):
                text += delta
            default:
                break
            }
        }
        return text
    }

    static func assertToolLoop(model: any LanguageModel, maxOutputTokens: Int) async throws {
        let tracker = LiveToolTracker()
        let tool = weatherTool(tracker: tracker)

        let result = try await AI.generateText(
            model: model,
            prompt: "Use the lookup_weather tool exactly once for Tokyo. Then reply with the forecast word only.",
            temperature: 0,
            maxOutputTokens: maxOutputTokens,
            executableTools: [tool],
            maxSteps: 2,
            retryPolicy: .none
        )

        let toolCallCount = await tracker.count()
        #expect(toolCallCount == 1)
        #expect(result.toolResults.count == 1)
        #expect(result.toolResults.first?.result["forecast"]?.stringValue == "sunny")
        #expect(!result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    static func assertStreamToolLoop(model: any LanguageModel, maxOutputTokens: Int, expectsToolInputLifecycle: Bool) async throws {
        let tracker = LiveToolTracker()
        let tool = weatherTool(tracker: tracker)

        var text = ""
        var toolResults: [AIToolResult] = []
        var toolInputStarts = 0
        var toolInputEnds = 0
        for try await part in AI.streamText(
            model: model,
            prompt: "Use the lookup_weather tool exactly once for Tokyo. Then reply with the forecast word only.",
            temperature: 0,
            maxOutputTokens: maxOutputTokens,
            executableTools: [tool],
            maxSteps: 2,
            retryPolicy: .none
        ) {
            switch part {
            case let .textDelta(delta):
                text += delta
            case let .textDeltaPart(_, delta, _):
                text += delta
            case let .toolResult(result):
                toolResults.append(result)
            case .toolInputStart(_, _, _, _, _, _):
                toolInputStarts += 1
            case .toolInputEnd(_, _):
                toolInputEnds += 1
            default:
                break
            }
        }

        let toolCallCount = await tracker.count()
        #expect(toolCallCount == 1)
        #expect(toolResults.count == 1)
        #expect(toolResults.first?.result["forecast"]?.stringValue == "sunny")
        #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if expectsToolInputLifecycle {
            #expect(toolInputStarts >= 1)
            #expect(toolInputEnds >= 1)
        }
    }

    static func weatherTool(tracker: LiveToolTracker) -> AITool {
        AITool(
            name: "lookup_weather",
            description: "Looks up a deterministic weather forecast for a city.",
            parameters: [
                "type": "object",
                "properties": [
                    "city": [
                        "type": "string",
                        "description": "City name to look up."
                    ]
                ],
                "required": ["city"]
            ]
        ) { arguments in
            await tracker.record(city: arguments["city"]?.stringValue)
        }
    }

    static func modelID(environmentVariable: String, defaultValue: String) -> String {
        let rawValue = ProcessInfo.processInfo.environment[environmentVariable] ?? defaultValue
        return rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func apiKey(environmentVariable: String, fileName: String) throws -> String {
        if let value = ProcessInfo.processInfo.environment[environmentVariable]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }

        let fileURL = packageRoot.appendingPathComponent(fileName)
        if let value = try? String(contentsOf: fileURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }

        throw AIError.missingAPIKey(provider: "live-smoke", environmentVariables: [environmentVariable, fileName])
    }

    private static var packageRoot: URL {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).resolvingSymlinksInPath()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

private actor LiveToolTracker {
    private var toolCallCount = 0

    func record(city: String?) -> JSONValue {
        toolCallCount += 1
        return .object([
            "city": .string(city ?? "missing"),
            "forecast": .string("sunny")
        ])
    }

    func count() -> Int {
        toolCallCount
    }
}
