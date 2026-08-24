import Foundation
import Testing
@testable import SwiftAISDK

@Test func alibabaUnaryToolCallsGenerateDistinctIDsForEmptyProviderIDs() async throws {
    let transport = RecordingTransport(response: jsonResponse(emptyIDChatCompletionResponse))
    let provider = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "alibaba-key", transport: transport))

    let result = try await provider.languageModel("qwen-plus").generate(
        LanguageModelRequest(messages: [.user("Use tools.")])
    )

    expectDistinctGeneratedToolCallIDs(result.toolCalls)
}

@Test func deepSeekUnaryToolCallsGenerateDistinctIDsForEmptyProviderIDs() async throws {
    let transport = RecordingTransport(response: jsonResponse(emptyIDChatCompletionResponse))
    let provider = try AIProviders.deepSeek(settings: ProviderSettings(apiKey: "deepseek-key", transport: transport))

    let result = try await provider.languageModel("deepseek-chat").generate(
        LanguageModelRequest(messages: [.user("Use tools.")])
    )

    expectDistinctGeneratedToolCallIDs(result.toolCalls)
}

@Test func groqUnaryToolCallsGenerateDistinctIDsForEmptyProviderIDs() async throws {
    let transport = RecordingTransport(response: jsonResponse(emptyIDChatCompletionResponse))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))

    let result = try await provider.languageModel("llama-3.3-70b-versatile").generate(
        LanguageModelRequest(messages: [.user("Use tools.")])
    )

    expectDistinctGeneratedToolCallIDs(result.toolCalls)
}

@Test func googleGenerateContentToolCallsGenerateDistinctIDsForEmptyProviderIDs() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "candidates":[{
        "content":{"role":"model","parts":[
          {"functionCall":{"id":"","name":"first","args":{"value":1}}},
          {"functionCall":{"id":"","name":"second","args":{"value":2}}}
        ]},
        "finishReason":"STOP"
      }],
      "usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":1,"totalTokenCount":2}
    }
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "google-key", transport: transport))

    let result = try await provider.languageModel("gemini-2.5-flash").generate(
        LanguageModelRequest(messages: [.user("Use tools.")])
    )

    expectDistinctGeneratedToolCallIDs(result.toolCalls)
}

@Test func googleInteractionsToolCallsGenerateDistinctIDsForEmptyProviderIDs() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "id":"interaction-1",
      "status":"requires_action",
      "steps":[
        {"type":"function_call","id":"","name":"lookup","arguments":{"value":1}},
        {"type":"function_call","id":"","name":"lookup","arguments":{"value":2}}
      ],
      "usage":{"total_tokens":2}
    }
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "google-key", transport: transport))

    let result = try await provider.interactionsModel("gemini-2.5-flash").generate(
        LanguageModelRequest(messages: [.user("Use tools.")])
    )

    expectDistinctGeneratedToolCallIDs(result.toolCalls)
}

@Test func googleGenerateContentPairsEmptyServerToolIDsWithGeneratedFallback() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "candidates":[{
        "content":{"role":"model","parts":[
          {"toolCall":{"toolType":"google_search","id":"","args":{"query":"weather"}}},
          {"toolResponse":{"toolType":"google_search","id":"","response":{"results":[]}}}
        ]},
        "finishReason":"STOP"
      }]
    }
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "google-key", transport: transport))

    let result = try await provider.languageModel("gemini-3-pro").generate(
        LanguageModelRequest(messages: [.user("Search.")])
    )

    let call = try #require(result.toolCalls.first)
    let toolResult = try #require(result.toolResults.first)
    #expect(!call.id.isEmpty)
    #expect(toolResult.toolCallID == call.id)
}

@Test func sharedOpenAIChatPathsGenerateDistinctIDsForEmptyProviderIDs() async throws {
    let openAITransport = RecordingTransport(response: jsonResponse(emptyIDChatCompletionResponse))
    let compatibleTransport = RecordingTransport(response: jsonResponse(emptyIDChatCompletionResponse))
    let moonshotTransport = RecordingTransport(response: jsonResponse(emptyIDChatCompletionResponse))

    let openAI = try AIProviders.openAI(settings: ProviderSettings(apiKey: "openai-key", transport: openAITransport))
    let compatible = try AIProviders.openAICompatible(
        name: "compatible",
        baseURL: "https://compatible.example.com/v1",
        apiKey: "compatible-key",
        transport: compatibleTransport
    )
    let moonshot = try AIProviders.moonshotAI(settings: ProviderSettings(apiKey: "moonshot-key", transport: moonshotTransport))
    let models: [any LanguageModel] = [
        try openAI.chatModel("gpt-4.1-mini"),
        try compatible.chatModel("compatible-model"),
        try moonshot.languageModel("kimi-k2.5")
    ]

    for model in models {
        let result = try await model.generate(LanguageModelRequest(messages: [.user("Use tools.")]))
        expectDistinctGeneratedToolCallIDs(result.toolCalls)
    }
}

private let emptyIDChatCompletionResponse = #"""
{
  "choices":[{
    "message":{"role":"assistant","content":"","tool_calls":[
      {"id":"","type":"function","function":{"name":"first","arguments":"{\"value\":1}"}},
      {"id":"","type":"function","function":{"name":"second","arguments":"{\"value\":2}"}}
    ]},
    "finish_reason":"tool_calls"
  }],
  "usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}
}
"""#

private func expectDistinctGeneratedToolCallIDs(_ toolCalls: [AIToolCall]) {
    let ids = toolCalls.map(\.id)
    #expect(ids.count == 2)
    #expect(ids.allSatisfy { !$0.isEmpty })
    #expect(Set(ids).count == 2)
}
