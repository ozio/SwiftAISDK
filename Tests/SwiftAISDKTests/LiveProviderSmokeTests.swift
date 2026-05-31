import Foundation
import Testing
@testable import SwiftAISDK

@Test func liveProviderSmokeOpenAIGenerateText() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let apiKey = try LiveProviderSmoke.apiKey(environmentVariable: "OPENAI_API_KEY", fileName: "openai-api-key.txt")
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: apiKey))
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

@Test func liveProviderSmokeAnthropicGenerateText() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let apiKey = try LiveProviderSmoke.apiKey(environmentVariable: "ANTHROPIC_API_KEY", fileName: "claude-api-key.txt")
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: apiKey))
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

@Test func liveProviderSmokeGoogleGenerateText() async throws {
    guard LiveProviderSmoke.isEnabled else { return }

    let apiKey = try LiveProviderSmoke.apiKey(environmentVariable: "GEMINI_API_KEY", fileName: "gemini-api-key.txt")
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: apiKey))
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

private enum LiveProviderSmoke {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["LIVE_AI_TESTS"] == "1"
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
