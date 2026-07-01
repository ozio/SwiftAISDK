import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesStreamsWebSearchResultsFromFixtureLikeUpstream() async throws {
    let fixtureName = "openai-web-search-tool.1.chunks.txt"
    let fixtureEvents = try openAIResponsesChunksFixtureEvents(fixtureName)
    let completed = try #require(fixtureEvents.first { $0["type"]?.stringValue == "response.completed" })
    let expectedMessage = try #require(completed["response"]?["output"]?.arrayValue?.first { $0["type"]?.stringValue == "message" })
    let expectedText = try #require(expectedMessage["content"]?[0]?["text"]?.stringValue)

    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse(fixtureName))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var reasoningStarts: [(String, [String: JSONValue])] = []
    var reasoningEnds: [(String, [String: JSONValue])] = []
    var toolLifecycle: [String] = []
    var toolCalls: [AIToolCall] = []
    var toolResults: [AIToolResult] = []
    var textStarts: [(String, [String: JSONValue])] = []
    var textDeltas: [(String, String)] = []
    var textEnds: [(String, [String: JSONValue])] = []
    var sources: [AISource] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishProviderMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "webSearch": [
                "type": "provider",
                "id": "openai.web_search",
                "name": "webSearch",
                "args": [:]
            ]
        ]
    )) {
        switch part {
        case .streamStart:
            streamStarted = true
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .reasoningStart(id, metadata):
            reasoningStarts.append((id, metadata))
        case let .reasoningEnd(id, metadata):
            reasoningEnds.append((id, metadata))
        case let .toolInputStart(id, name, providerExecuted, _, _, _):
            toolLifecycle.append("start:\(id):\(name):\(providerExecuted)")
        case let .toolInputEnd(id, _):
            toolLifecycle.append("end:\(id)")
        case let .toolCall(call):
            toolCalls.append(call)
        case let .toolResult(result):
            toolResults.append(result)
        case let .textStart(id, metadata):
            textStarts.append((id, metadata))
        case let .textDeltaPart(id, delta, _):
            textDeltas.append((id, delta))
        case let .textEnd(id, metadata):
            textEnds.append((id, metadata))
        case let .source(source):
            sources.append(source)
        case let .finish(reason, usage):
            finishReason = reason
            finishUsage = usage
        case let .finishMetadata(reason, usage, metadata):
            finishReason = reason
            finishUsage = usage
            finishProviderMetadata = metadata
        default:
            break
        }
    }

    #expect(streamStarted)
    #expect(responseMetadata?.id == "resp_0cc96ac817fdc57e00693337060a408198b92bf1f99cf1b8ec")
    #expect(responseMetadata?.modelID == "gpt-5-mini-2025-08-07")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_764_964_102))

    #expect(reasoningStarts.map { $0.0 } == [
        "rs_0cc96ac817fdc57e0069333706f5748198ad6f9d56c74ba528:0",
        "rs_0cc96ac817fdc57e0069333710f97081989fba3cbe0726ee76:0",
        "rs_0cc96ac817fdc57e00693337185c648198ab92fcd140ad72a8:0",
        "rs_0cc96ac817fdc57e006933371ff26081989c3ff8fefad9c804:0",
        "rs_0cc96ac817fdc57e0069333724535c8198b39ab21fa3f4e559:0",
        "rs_0cc96ac817fdc57e006933372e866c81988386fd0b0408eb28:0",
        "rs_0cc96ac817fdc57e006933373641e8819899b5ecb68564ac56:0"
    ])
    #expect(reasoningEnds.map { $0.0 } == reasoningStarts.map { $0.0 })
    #expect(reasoningStarts[0].1["openai"]?["itemId"]?.stringValue == "rs_0cc96ac817fdc57e0069333706f5748198ad6f9d56c74ba528")
    #expect(reasoningStarts[0].1["openai"]?["reasoningEncryptedContent"] == .null)

    #expect(toolCalls.count == 6)
    #expect(toolResults.count == 6)
    #expect(toolCalls.map(\.name) == Array(repeating: "webSearch", count: 6))
    #expect(toolResults.map(\.toolName) == Array(repeating: "webSearch", count: 6))
    #expect(toolCalls.allSatisfy { $0.providerExecuted })
    #expect(toolCalls.map(\.arguments) == Array(repeating: "{}", count: 6))
    #expect(toolResults.map(\.toolCallID) == toolCalls.map(\.id))
    #expect(toolLifecycle == toolCalls.flatMap { call in
        ["start:\(call.id):webSearch:true", "end:\(call.id)"]
    })

    #expect(toolResults[0].result["action"]?["type"]?.stringValue == "search")
    #expect(toolResults[0].result["action"]?["query"]?.stringValue == "tech news today December 5 2025")
    #expect(toolResults[0].result["sources"]?.arrayValue?.count == 10)
    #expect(toolResults[0].result["sources"]?[0]?["url"]?.stringValue == "https://www.wired.com/story/the-big-interview-2025-recap")
    #expect(toolResults[1].result["action"]?["query"]?.stringValue == "site:theverge.com \"December 5, 2025\" \"technology\"")
    #expect(toolResults[2].result["action"]?["type"]?.stringValue == "openPage")
    #expect(toolResults[2].result["action"]?["url"]?.stringValue == "https://techcrunch.com/2025/12/05/petco-confirms-security-lapse-exposed-customers-personal-data/")
    #expect(toolResults[3].result["action"]?["type"]?.stringValue == "findInPage")
    #expect(toolResults[3].result["action"]?["pattern"]?.stringValue == "vercel")
    #expect(toolResults[4].result["action"]?["pattern"]?.stringValue == "Vercel")
    #expect(toolResults[5].result["action"]?["url"]?.stringValue == "https://techcrunch.com/2025/12/05/petco-confirms-security-lapse-exposed-customers-personal-data/")

    #expect(textStarts.map { $0.0 } == ["msg_0cc96ac817fdc57e006933374a84348198a4e1ac9bc0c4607b"])
    #expect(textStarts[0].1["openai"]?["itemId"]?.stringValue == "msg_0cc96ac817fdc57e006933374a84348198a4e1ac9bc0c4607b")
    #expect(textDeltas.map { $0.0 }.allSatisfy { $0 == "msg_0cc96ac817fdc57e006933374a84348198a4e1ac9bc0c4607b" })
    #expect(textDeltas.map { $0.1 }.joined() == expectedText)
    #expect(textEnds.map { $0.0 } == ["msg_0cc96ac817fdc57e006933374a84348198a4e1ac9bc0c4607b"])
    #expect(textEnds[0].1["openai"]?["annotations"]?.arrayValue?.count == 12)

    #expect(sources.count == 12)
    #expect(sources[0].id == "id-0")
    #expect(sources[0].sourceType == "url")
    #expect(sources[0].title == "Petco confirms security lapse exposed customers’ personal data | TechCrunch")
    #expect(sources[0].url == "https://techcrunch.com/2025/12/05/petco-confirms-security-lapse-exposed-customers-personal-data/?utm_source=openai")
    #expect(sources[11].id == "id-11")
    #expect(sources[11].title == "AI coding startup Vercel raises $300 million, valued at $9.3 billion")

    #expect(finishReason == "stop")
    #expect(finishUsage?.inputTokens == 31_073)
    #expect(finishUsage?.inputTokensCacheRead == 3_712)
    #expect(finishUsage?.inputTokensNoCache == 27_361)
    #expect(finishUsage?.outputTokens == 4_416)
    #expect(finishUsage?.outputReasoningTokens == 3_712)
    #expect(finishUsage?.outputTextTokens == 704)
    #expect(finishUsage?.totalTokens == 35_489)
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == "resp_0cc96ac817fdc57e00693337060a408198b92bf1f99cf1b8ec")
    #expect(finishProviderMetadata["openai"]?["serviceTier"]?.stringValue == "default")
}

@Test func openAIResponsesStreamsWebSearchWithActionQueryFieldLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data:{"type":"response.created","response":{"id":"resp_test","object":"response","created_at":1741630255,"status":"in_progress","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"o3-2025-04-16","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":"medium","summary":"auto"},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[{"type":"web_search","search_context_size":"medium"}],"top_p":1,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data:{"type":"response.output_item.added","output_index":0,"item":{"type":"web_search_call","id":"ws_test","status":"in_progress","action":{"type":"search","query":"Vercel AI SDK next version features"}}}

    data:{"type":"response.web_search_call.in_progress","output_index":0,"item_id":"ws_test"}

    data:{"type":"response.web_search_call.searching","output_index":0,"item_id":"ws_test"}

    data:{"type":"response.web_search_call.completed","output_index":0,"item_id":"ws_test"}

    data:{"type":"response.output_item.done","output_index":0,"item":{"type":"web_search_call","id":"ws_test","status":"completed","action":{"type":"search","query":"Vercel AI SDK next version features"}}}

    data:{"type":"response.output_item.added","output_index":1,"item":{"type":"message","id":"msg_test","status":"in_progress","role":"assistant","content":[]}}

    data:{"type":"response.content_part.added","item_id":"msg_test","output_index":1,"content_index":0,"part":{"type":"output_text","text":"","annotations":[]}}

    data:{"type":"response.output_text.delta","item_id":"msg_test","output_index":1,"content_index":0,"delta":"Based on the search results, here are the upcoming features."}

    data:{"type":"response.output_text.done","item_id":"msg_test","output_index":1,"content_index":0,"text":"Based on the search results, here are the upcoming features."}

    data:{"type":"response.content_part.done","item_id":"msg_test","output_index":1,"content_index":0,"part":{"type":"output_text","text":"Based on the search results, here are the upcoming features.","annotations":[]}}

    data:{"type":"response.output_item.done","output_index":1,"item":{"type":"message","id":"msg_test","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Based on the search results, here are the upcoming features.","annotations":[]}]}}

    data:{"type":"response.completed","response":{"id":"resp_test","object":"response","created_at":1741630255,"status":"completed","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"o3-2025-04-16","output":[{"type":"web_search_call","id":"ws_test","status":"completed","action":{"type":"search","query":"Vercel AI SDK next version features"}},{"type":"message","id":"msg_test","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Based on the search results, here are the upcoming features.","annotations":[]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":"medium","summary":"auto"},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[{"type":"web_search","search_context_size":"medium"}],"top_p":1,"truncation":"disabled","usage":{"input_tokens":50,"input_tokens_details":{"cached_tokens":0},"output_tokens":25,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":75},"user":null,"metadata":{}}}

    data: [DONE]

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var toolLifecycle: [String] = []
    var toolCall: AIToolCall?
    var toolResult: AIToolResult?
    var textStarts: [(String, [String: JSONValue])] = []
    var textDeltas: [(String, String)] = []
    var textEnds: [(String, [String: JSONValue])] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishProviderMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "webSearch": [
                "type": "provider",
                "id": "openai.web_search",
                "name": "webSearch",
                "args": [:]
            ]
        ]
    )) {
        switch part {
        case .streamStart:
            streamStarted = true
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .toolInputStart(id, name, providerExecuted, _, _, _):
            toolLifecycle.append("start:\(id):\(name):\(providerExecuted)")
        case let .toolInputEnd(id, _):
            toolLifecycle.append("end:\(id)")
        case let .toolCall(call):
            toolCall = call
        case let .toolResult(result):
            toolResult = result
        case let .textStart(id, metadata):
            textStarts.append((id, metadata))
        case let .textDeltaPart(id, delta, _):
            textDeltas.append((id, delta))
        case let .textEnd(id, metadata):
            textEnds.append((id, metadata))
        case let .finish(reason, usage):
            finishReason = reason
            finishUsage = usage
        case let .finishMetadata(reason, usage, metadata):
            finishReason = reason
            finishUsage = usage
            finishProviderMetadata = metadata
        default:
            break
        }
    }

    #expect(streamStarted)
    #expect(responseMetadata?.id == "resp_test")
    #expect(responseMetadata?.modelID == "o3-2025-04-16")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_741_630_255))
    #expect(toolLifecycle == ["start:ws_test:webSearch:true", "end:ws_test"])
    #expect(toolCall?.id == "ws_test")
    #expect(toolCall?.name == "webSearch")
    #expect(toolCall?.arguments == "{}")
    #expect(toolCall?.providerExecuted == true)
    #expect(toolResult?.toolCallID == "ws_test")
    #expect(toolResult?.toolName == "webSearch")
    #expect(toolResult?.result["action"]?["type"]?.stringValue == "search")
    #expect(toolResult?.result["action"]?["query"]?.stringValue == "Vercel AI SDK next version features")
    #expect(textStarts.map { $0.0 } == ["msg_test"])
    #expect(textStarts[0].1["openai"]?["itemId"]?.stringValue == "msg_test")
    #expect(textDeltas.map { $0.0 } == ["msg_test"])
    #expect(textDeltas.map { $0.1 } == ["Based on the search results, here are the upcoming features."])
    #expect(textEnds.map { $0.0 } == ["msg_test"])
    #expect(textEnds[0].1["openai"]?["itemId"]?.stringValue == "msg_test")
    #expect(finishReason == "stop")
    #expect(finishUsage?.inputTokens == 50)
    #expect(finishUsage?.inputTokensCacheRead == 0)
    #expect(finishUsage?.inputTokensNoCache == 50)
    #expect(finishUsage?.outputTokens == 25)
    #expect(finishUsage?.outputReasoningTokens == 0)
    #expect(finishUsage?.outputTextTokens == 25)
    #expect(finishUsage?.totalTokens == 75)
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == "resp_test")
}

@Test func openAIResponsesStreamsWebSearchWithoutActionLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data:{"type":"response.created","response":{"id":"resp_missing_action","object":"response","created_at":1741630255,"status":"in_progress","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"o3-2025-04-16","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":"medium","summary":"auto"},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[{"type":"web_search","search_context_size":"medium"}],"top_p":1,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data:{"type":"response.output_item.added","output_index":0,"item":{"type":"web_search_call","id":"ws_missing_action","status":"in_progress"}}

    data:{"type":"response.web_search_call.in_progress","output_index":0,"item_id":"ws_missing_action"}

    data:{"type":"response.web_search_call.completed","output_index":0,"item_id":"ws_missing_action"}

    data:{"type":"response.output_item.done","output_index":0,"item":{"type":"web_search_call","id":"ws_missing_action","status":"completed"}}

    data:{"type":"response.completed","response":{"id":"resp_missing_action","object":"response","created_at":1741630255,"status":"completed","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"o3-2025-04-16","output":[{"type":"web_search_call","id":"ws_missing_action","status":"completed"}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":"medium","summary":"auto"},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[{"type":"web_search","search_context_size":"medium"}],"top_p":1,"truncation":"disabled","usage":{"input_tokens":10,"input_tokens_details":{"cached_tokens":0},"output_tokens":2,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":12},"user":null,"metadata":{}}}

    data: [DONE]

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    var toolCall: AIToolCall?
    var toolResult: AIToolResult?
    var finishReason: String?

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "webSearch": [
                "type": "provider",
                "id": "openai.web_search",
                "name": "webSearch",
                "args": [:]
            ]
        ]
    )) {
        switch part {
        case let .toolCall(call):
            toolCall = call
        case let .toolResult(result):
            toolResult = result
        case let .finish(reason, _):
            finishReason = reason
        case let .finishMetadata(reason, _, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(toolCall?.id == "ws_missing_action")
    #expect(toolCall?.name == "webSearch")
    #expect(toolCall?.providerExecuted == true)
    #expect(toolResult?.toolCallID == "ws_missing_action")
    #expect(toolResult?.toolName == "webSearch")
    #expect(toolResult?.result == .object([:]))
    #expect(finishReason == "stop")
}

@Test func openAIResponsesStreamsHostedToolSearchPartsLikeUpstream() async throws {
    let fixtureName = "openai-tool-search.1.chunks.txt"
    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse(fixtureName))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    var toolSearchParts: [LanguageStreamPart] = []
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "toolSearch": [
                "type": "provider",
                "id": "openai.tool_search",
                "name": "toolSearch",
                "args": [:]
            ],
            "get_weather": [
                "type": "function",
                "description": "Get the current weather at a specific location",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "location": [
                            "type": "string",
                            "description": "The city and state, e.g. San Francisco, CA"
                        ],
                        "unit": [
                            "type": "string",
                            "enum": ["celsius", "fahrenheit"],
                            "description": "Temperature unit"
                        ]
                    ],
                    "required": ["location", "unit"],
                    "additionalProperties": false
                ],
                "strict": true,
                "providerOptions": ["openai": ["deferLoading": true]]
            ]
        ]
    )) {
        switch part {
        case let .toolCall(call) where call.name == "toolSearch":
            toolSearchParts.append(part)
        case let .toolResult(result) where result.toolName == "toolSearch":
            toolSearchParts.append(part)
        default:
            break
        }
    }

    guard toolSearchParts.count == 2,
          case let .toolCall(toolCall) = toolSearchParts[0],
          case let .toolResult(toolResult) = toolSearchParts[1] else {
        Issue.record("Expected upstream hosted tool search call/result stream parts")
        return
    }

    #expect(toolCall.id == "tsc_08a14073c7135dc10069aa686296c88190bff77ad137e79d59")
    #expect(toolCall.name == "toolSearch")
    #expect(toolCall.providerExecuted == true)
    #expect(toolCall.providerMetadata["openai"]?["itemId"]?.stringValue == "tsc_08a14073c7135dc10069aa686296c88190bff77ad137e79d59")
    let input = try decodeJSONBody(Data(toolCall.arguments.utf8))
    #expect(input["arguments"]?["paths"]?[0]?.stringValue == "get_weather")
    #expect(input["call_id"] == JSONValue.null)

    #expect(toolResult.toolCallID == "tsc_08a14073c7135dc10069aa686296c88190bff77ad137e79d59")
    #expect(toolResult.toolName == "toolSearch")
    #expect(toolResult.providerMetadata["openai"]?["itemId"]?.stringValue == "tso_08a14073c7135dc10069aa6862b1248190ba40cbba918ecfa2")
    let tool = try #require(toolResult.result["tools"]?[0])
    #expect(tool["type"]?.stringValue == "function")
    #expect(tool["defer_loading"]?.boolValue == true)
    #expect(tool["description"]?.stringValue == "Get the current weather at a specific location")
    #expect(tool["name"]?.stringValue == "get_weather")
    #expect(tool["parameters"]?["additionalProperties"]?.boolValue == false)
    #expect(tool["parameters"]?["properties"]?["location"]?["description"]?.stringValue == "The city and state, e.g. San Francisco, CA")
    #expect(tool["parameters"]?["properties"]?["unit"]?["enum"]?[1]?.stringValue == "fahrenheit")
    #expect(tool["parameters"]?["required"]?[1]?.stringValue == "unit")
    #expect(tool["strict"]?.boolValue == true)
}

@Test func openAIResponsesStreamsClientToolSearchCallAsNonProviderExecutedLikeUpstream() async throws {
    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse("openai-client-tool-search.1.chunks.txt"))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.4")

    var toolSearchParts: [LanguageStreamPart] = []
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesStreamingClientToolSearchTools()
    )) {
        switch part {
        case let .toolInputStart(_, name, _, _, _, _) where name == "toolSearch":
            toolSearchParts.append(part)
        case .toolInputEnd:
            toolSearchParts.append(part)
        case let .toolCall(call) where call.name == "toolSearch":
            toolSearchParts.append(part)
        default:
            break
        }
    }

    guard toolSearchParts.count == 3,
          case let .toolInputStart(startID, startName, startProviderExecuted, _, _, _) = toolSearchParts[0],
          case let .toolInputEnd(endID, _) = toolSearchParts[1],
          case let .toolCall(toolCall) = toolSearchParts[2] else {
        Issue.record("Expected upstream client tool search start/end/call stream parts")
        return
    }

    #expect(startID == "call_RWTIIVfxsJW9fecsg6fy23Dy")
    #expect(startName == "toolSearch")
    #expect(startProviderExecuted == false)
    #expect(endID == "call_RWTIIVfxsJW9fecsg6fy23Dy")
    #expect(toolCall.id == "call_RWTIIVfxsJW9fecsg6fy23Dy")
    #expect(toolCall.name == "toolSearch")
    #expect(toolCall.providerExecuted == false)
    #expect(toolCall.providerMetadata["openai"]?["itemId"]?.stringValue == "tsc_05147bbe356953b60069ab673598f88196b499a756b524b64c")
    let input = try decodeJSONBody(Data(toolCall.arguments.utf8))
    #expect(input["arguments"]?["goal"]?.stringValue == "Find a tool that can provide current weather information for San Francisco.")
    #expect(input["call_id"]?.stringValue == "call_RWTIIVfxsJW9fecsg6fy23Dy")
}

@Test func openAIResponsesClientToolSearchStreamProviderExecutedFlagIsFalseLikeUpstream() async throws {
    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse("openai-client-tool-search.1.chunks.txt"))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.4")

    var toolInputStartProviderExecuted: Bool?
    var toolCallProviderExecuted: Bool?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesStreamingClientToolSearchTools()
    )) {
        switch part {
        case let .toolInputStart(_, name, providerExecuted, _, _, _) where name == "toolSearch":
            toolInputStartProviderExecuted = providerExecuted
        case let .toolCall(call) where call.name == "toolSearch":
            toolCallProviderExecuted = call.providerExecuted
        default:
            break
        }
    }

    #expect(toolInputStartProviderExecuted == false)
    #expect(toolCallProviderExecuted == false)
}

@Test func openAIResponsesClientToolSearchStreamUsesFinalCallIDLikeUpstream() async throws {
    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse("openai-client-tool-search.1.chunks.txt"))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.4")

    var toolCall: AIToolCall?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesStreamingClientToolSearchTools()
    )) {
        switch part {
        case let .toolCall(call) where call.name == "toolSearch":
            toolCall = call
        default:
            break
        }
    }

    let call = try #require(toolCall)
    let input = try decodeJSONBody(Data(call.arguments.utf8))
    #expect(call.id == "call_RWTIIVfxsJW9fecsg6fy23Dy")
    #expect(input["call_id"]?.stringValue == "call_RWTIIVfxsJW9fecsg6fy23Dy")
    #expect(call.id == input["call_id"]?.stringValue)
}

@Test func openAIResponsesStreamsStepTwoFunctionCallAfterClientToolSearchOutputLikeUpstream() async throws {
    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse("openai-client-tool-search.2.chunks.txt"))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.4")

    var functionCall: AIToolCall?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesStreamingClientToolSearchTools()
    )) {
        switch part {
        case let .toolCall(call) where call.name == "get_weather":
            functionCall = call
        default:
            break
        }
    }

    let call = try #require(functionCall)
    #expect(call.id == "call_Q7pq6EfVGRnauPLWSSYBGJ1l")
    let input = try decodeJSONBody(Data(call.arguments.utf8))
    #expect(input == .object([
        "location": .string("San Francisco, CA"),
        "unit": .string("fahrenheit")
    ]))
}

