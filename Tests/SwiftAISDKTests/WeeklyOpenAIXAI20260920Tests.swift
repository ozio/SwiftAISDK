import Foundation
import Testing
@testable import SwiftAISDK

@Test func weeklyOpenAIXAI20260920XAI5BatchOwnsChatShapedUsageConversion() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"batch_id":"batch_usage","state":{"num_requests":1,"num_pending":0,"num_success":1,"num_error":0,"num_cancelled":0}}"#),
        jsonResponse(#"""
        {
          "results":[
            {
              "batch_request_id":"usage",
              "batch_result":{"response":{"chat_get_completion":{
                "id":"response_123",
                "object":"chat.completion",
                "created":1700000000,
                "model":"grok-4.3",
                "choices":[
                  {
                    "index":0,
                    "message":{
                      "role":"assistant",
                      "content":"Paris",
                      "reasoning_content":null,
                      "tool_calls":null
                    },
                    "finish_reason":"stop"
                  }
                ],
                "usage":{
                  "prompt_tokens":2,
                  "completion_tokens":3,
                  "total_tokens":5,
                  "prompt_tokens_details":{"cached_tokens":5},
                  "completion_tokens_details":{"reasoning_tokens":1}
                }
              }}}
            }
          ],
          "pagination_token":null
        }
        """#)
    ])
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try #require(try provider.languageModel("grok-4.3") as? any BatchLanguageModel)

    let stream = try await model.getBatchResults(AIBatchOperationOptions(batchID: "batch_usage"))
    var results: [AIBatchItemResult<TextGenerationResult>] = []
    for try await result in stream {
        results.append(result)
    }

    guard case let .succeeded(id, generation) = try #require(results.first) else {
        Issue.record("Expected successful xAI batch text result")
        return
    }
    #expect(id == "usage")
    #expect(generation.text == "Paris")
    #expect(generation.usage?.inputTokens == 7)
    #expect(generation.usage?.inputTokensNoCache == 2)
    #expect(generation.usage?.inputTokensCacheRead == 5)
    #expect(generation.usage?.outputTokens == 4)
    #expect(generation.usage?.outputTextTokens == 3)
    #expect(generation.usage?.outputReasoningTokens == 1)
    #expect(generation.usage?.totalTokens == 11)
    #expect(generation.usage?.rawValue?["total_tokens"]?.intValue == 5)
    #expect(await transport.requests().map(\.url.absoluteString) == [
        "https://api.x.ai/v1/batches/batch_usage",
        "https://api.x.ai/v1/batches/batch_usage/results?limit=1000"
    ])
}

@Test func weeklyOpenAIXAI20260920OpenAIProviderAutoRoutesKnownLiveModel() throws {
    let openAI = try AIProviders.openAI(
        settings: ProviderSettings(apiKey: "openai-key", name: "custom-openai")
    )
    let live = try #require(
        try openAI.experimentalRealtime("gpt-live-1") as? OpenAILiveModel
    )

    #expect(live.providerID == "custom-openai.live")
    #expect(live.modelID == "gpt-live-1")
    let webSocket = try live.getServerWebSocketConfig()
    #expect(webSocket.url == "wss://api.openai.com/v1/live/sessions")
    #expect(webSocket.headers["authorization"] == "Bearer openai-key")

    #expect(throws: AIError.invalidArgument(
        argument: "modelID",
        message: "OpenAI realtime model IDs other than 'gpt-live-1' require the Realtime API, which is not yet available in SwiftAISDK."
    )) {
        _ = try openAI.experimentalRealtime("gpt-realtime")
    }

    let xAI = try AIProviders.xAI(
        settings: ProviderSettings(apiKey: "xai-key")
    )
    let xAIRealtime = try xAI.experimentalRealtime("grok-voice-agent")
    #expect(xAIRealtime is XAIRealtimeModel)
    #expect(xAIRealtime.providerID == "xai.realtime")
    #expect(xAIRealtime.modelID == "grok-voice-agent")
}
