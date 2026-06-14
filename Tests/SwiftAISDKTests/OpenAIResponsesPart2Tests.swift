import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesMapsFunctionAndProviderTools() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Search, inspect files, and generate an image.")],
        tools: [
            "lookup": [
                "type": "object",
                "description": "Look up a value.",
                "properties": ["query": ["type": "string"]],
                "strict": true,
                "deferLoading": true
            ],
            "web_search": OpenAITools.webSearch(
                filters: ["allowedDomains": ["example.com"]],
                externalWebAccess: true,
                searchContextSize: "high",
                userLocation: ["type": "approximate", "country": "US"]
            ),
            "file_search": OpenAITools.fileSearch(
                vectorStoreIDs: ["vs_123"],
                maxNumResults: 5,
                ranking: ["ranker": "auto", "scoreThreshold": 0.2]
            ),
            "code_interpreter": OpenAITools.codeInterpreter(container: ["fileIds": ["file_1", "file_2"]]),
            "computer_use": OpenAITools.computerUse(displayWidth: 1024, displayHeight: 768, environment: "browser"),
            "shell": OpenAITools.shell(environment: OpenAITools.shellContainerAutoEnvironment(
                fileIDs: ["file_shell_1"],
                memoryLimit: "4g",
                networkPolicy: OpenAITools.shellAllowlistNetworkPolicy(
                    allowedDomains: ["example.com"],
                    domainSecrets: [
                        OpenAITools.shellDomainSecret(domain: "example.com", name: "TOKEN", value: "secret")
                    ]
                ),
                skills: [
                    OpenAITools.shellSkillReference(providerReference: ["openai": "skill_123"], version: "1")
                ]
            )),
            "image_generation": OpenAITools.imageGeneration(
                inputFidelity: "high",
                inputImageMask: ["fileId": "file_mask", "imageUrl": "https://example.com/mask.png"],
                model: "gpt-image-1",
                outputCompression: 70,
                outputFormat: "webp",
                partialImages: 2,
                quality: "high",
                size: "1024x1024"
            ),
            "remote_docs": OpenAITools.mcp(
                serverLabel: "docs",
                allowedTools: ["readOnly": true, "toolNames": ["search"]],
                requireApproval: ["never": ["toolNames": ["search"]]],
                serverURL: "https://mcp.example.com"
            ),
            "grammar_tool": OpenAITools.customTool(
                name: "grammar_tool",
                description: "Return a code.",
                format: ["type": "grammar", "syntax": "regex", "definition": "[A-Z]+"]
            ),
            "tool_search": OpenAITools.toolSearch(execution: "client", description: "Find deferred tools.")
        ],
        extraBody: ["toolChoice": ["type": "tool", "toolName": "web_search"]]
    ))

    #expect(result.text == "done")
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tools = try #require(body["tools"]?.arrayValue)
    #expect(tools.count == 10)

    let functionTool = try #require(tools.first { $0["type"]?.stringValue == "function" })
    #expect(functionTool["name"]?.stringValue == "lookup")
    #expect(functionTool["description"]?.stringValue == "Look up a value.")
    #expect(functionTool["parameters"]?["properties"]?["query"]?["type"]?.stringValue == "string")
    #expect(functionTool["parameters"]?["strict"] == nil)
    #expect(functionTool["strict"]?.boolValue == true)
    #expect(functionTool["defer_loading"]?.boolValue == true)

    let webSearch = try #require(tools.first { $0["type"]?.stringValue == "web_search" })
    #expect(webSearch["external_web_access"]?.boolValue == true)
    #expect(webSearch["search_context_size"]?.stringValue == "high")
    #expect(webSearch["filters"]?["allowed_domains"]?[0]?.stringValue == "example.com")
    #expect(webSearch["user_location"]?["country"]?.stringValue == "US")

    let fileSearch = try #require(tools.first { $0["type"]?.stringValue == "file_search" })
    #expect(fileSearch["vector_store_ids"]?[0]?.stringValue == "vs_123")
    #expect(fileSearch["max_num_results"]?.intValue == 5)
    #expect(fileSearch["ranking_options"]?["score_threshold"]?.doubleValue == 0.2)

    let codeInterpreter = try #require(tools.first { $0["type"]?.stringValue == "code_interpreter" })
    #expect(codeInterpreter["container"]?["type"]?.stringValue == "auto")
    #expect(codeInterpreter["container"]?["file_ids"]?[1]?.stringValue == "file_2")

    let computerUse = try #require(tools.first { $0["type"]?.stringValue == "computer_use" })
    #expect(computerUse["display_width"]?.intValue == 1024)
    #expect(computerUse["display_height"]?.intValue == 768)
    #expect(computerUse["environment"]?.stringValue == "browser")

    let shell = try #require(tools.first { $0["type"]?.stringValue == "shell" })
    #expect(shell["environment"]?["type"]?.stringValue == "container_auto")
    #expect(shell["environment"]?["file_ids"]?[0]?.stringValue == "file_shell_1")
    #expect(shell["environment"]?["memory_limit"]?.stringValue == "4g")
    #expect(shell["environment"]?["network_policy"]?["type"]?.stringValue == "allowlist")
    #expect(shell["environment"]?["network_policy"]?["allowed_domains"]?[0]?.stringValue == "example.com")
    #expect(shell["environment"]?["network_policy"]?["domain_secrets"]?[0]?["name"]?.stringValue == "TOKEN")
    #expect(shell["environment"]?["skills"]?[0]?["type"]?.stringValue == "skill_reference")
    #expect(shell["environment"]?["skills"]?[0]?["skill_id"]?.stringValue == "skill_123")
    #expect(shell["environment"]?["skills"]?[0]?["version"]?.stringValue == "1")

    let imageGeneration = try #require(tools.first { $0["type"]?.stringValue == "image_generation" })
    #expect(imageGeneration["input_fidelity"]?.stringValue == "high")
    #expect(imageGeneration["input_image_mask"]?["file_id"]?.stringValue == "file_mask")
    #expect(imageGeneration["partial_images"]?.intValue == 2)
    #expect(imageGeneration["output_compression"]?.intValue == 70)
    #expect(imageGeneration["output_format"]?.stringValue == "webp")

    let mcp = try #require(tools.first { $0["type"]?.stringValue == "mcp" })
    #expect(mcp["server_label"]?.stringValue == "docs")
    #expect(mcp["allowed_tools"]?["read_only"]?.boolValue == true)
    #expect(mcp["allowed_tools"]?["tool_names"]?[0]?.stringValue == "search")
    #expect(mcp["require_approval"]?["never"]?["tool_names"]?[0]?.stringValue == "search")

    let custom = try #require(tools.first { $0["type"]?.stringValue == "custom" })
    #expect(custom["name"]?.stringValue == "grammar_tool")
    #expect(custom["format"]?["syntax"]?.stringValue == "regex")

    let toolSearch = try #require(tools.first { $0["type"]?.stringValue == "tool_search" })
    #expect(toolSearch["execution"]?.stringValue == "client")
    #expect(body["tool_choice"]?["type"]?.stringValue == "web_search")
    #expect(body["toolChoice"] == nil)
}

@Test func openAIResponsesGroupsFunctionToolsByNamespaceAndIncludesToolCallNamespace() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            .user("Use namespaced tools."),
            .assistant(toolCalls: [
                AIToolCall(
                    id: "call-1",
                    name: "sum",
                    arguments: #"{"a":1,"b":2}"#,
                    providerMetadata: ["openai": ["namespace": "math"]]
                )
            ])
        ],
        tools: [
            "sum": [
                "type": "object",
                "properties": ["a": ["type": "number"], "b": ["type": "number"]],
                "providerOptions": [
                    "openai": [
                        "namespace": ["name": "math", "description": "Math tools"],
                        "deferLoading": true
                    ]
                ]
            ],
            "multiply": [
                "type": "object",
                "properties": ["a": ["type": "number"], "b": ["type": "number"]],
                "providerOptions": [
                    "openai": [
                        "namespace": ["name": "math", "description": "Math tools"]
                    ]
                ]
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let namespace = try #require(body["tools"]?.arrayValue?.first { $0["type"]?.stringValue == "namespace" })
    #expect(namespace["name"]?.stringValue == "math")
    #expect(namespace["description"]?.stringValue == "Math tools")
    #expect(namespace["tools"]?.arrayValue?.count == 2)
    let sum = try #require(namespace["tools"]?.arrayValue?.first { $0["name"]?.stringValue == "sum" })
    #expect(sum["type"]?.stringValue == "function")
    #expect(sum["defer_loading"]?.boolValue == true)
    #expect(sum["parameters"]?["providerOptions"] == nil)
    #expect(sum["parameters"]?["openai"] == nil)
    let input = try #require(body["input"]?.arrayValue)
    let functionCall = try #require(input.first { $0["type"]?.stringValue == "function_call" })
    #expect(functionCall["namespace"]?.stringValue == "math")
}

@Test func openAIResponsesMapsCustomToolChoice() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"custom"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use the custom tool.")],
        tools: [
            "grammar_tool": [
                "type": "provider",
                "id": "openai.custom",
                "name": "grammar_tool",
                "args": ["format": ["type": "text"]]
            ]
        ],
        extraBody: ["toolChoice": ["type": "tool", "toolName": "grammar_tool"]]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["tool_choice"]?["type"]?.stringValue == "custom")
    #expect(body["tool_choice"]?["name"]?.stringValue == "grammar_tool")
}
@Test func openAIResponsesMapsContextManagementCompactionLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2")

    for try await _ in model.stream(LanguageModelRequest(
        messages: [.user("Compact context.")],
        extraBody: [
            "openai": [
                "store": false,
                "contextManagement": [
                    ["type": "compaction", "compactThreshold": 50000]
                ]
            ]
        ]
    )) {}

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["store"]?.boolValue == false)
    #expect(body["context_management"]?[0]?["type"]?.stringValue == "compaction")
    #expect(body["context_management"]?[0]?["compact_threshold"]?.intValue == 50000)
    #expect(body["contextManagement"] == nil)
    #expect(body["context_management"]?[0]?["compactThreshold"] == nil)
}
@Test func openAIResponsesMapsProviderExecutedToolApprovalResponses() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#),
        jsonResponse(#"{"id":"resp-2","status":"completed","output_text":"done"}"#)
    ])
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    let approvalResponse = AIToolApprovalResponse(id: "approval-for-mcp", approved: true, providerExecuted: true)
    let duplicateApprovalResponse = AIToolApprovalResponse(id: "approval-for-mcp", approved: false, providerExecuted: true)
    let localApprovalResponse = AIToolApprovalResponse(id: "local-approval", approved: true)
    let regularResult = AIToolResult(
        toolCallID: "regular-call-1",
        toolName: "calculator",
        result: ["result": 42]
    )
    let deniedProviderResult = AIToolResult(
        toolCallID: "mcp-call-1",
        toolName: "mcp.create_short_url",
        result: ["type": "execution-denied", "reason": "Denied"],
        providerMetadata: ["openai": ["approvalId": "approval-for-mcp"]]
    )

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            .user("Continue."),
            .toolResponses(
                approvalResponses: [approvalResponse, duplicateApprovalResponse, localApprovalResponse],
                toolResults: [regularResult, deniedProviderResult]
            )
        ]
    ))

    let firstBody = try decodeJSONBody(try #require((await transport.requests())[0].body))
    let firstInput = try #require(firstBody["input"]?.arrayValue)
    #expect(firstInput.count == 4)
    #expect(firstInput[1]["type"]?.stringValue == "item_reference")
    #expect(firstInput[1]["id"]?.stringValue == "approval-for-mcp")
    #expect(firstInput[2]["type"]?.stringValue == "mcp_approval_response")
    #expect(firstInput[2]["approval_request_id"]?.stringValue == "approval-for-mcp")
    #expect(firstInput[2]["approve"]?.boolValue == true)
    #expect(firstInput[3]["type"]?.stringValue == "function_call_output")
    #expect(firstInput[3]["call_id"]?.stringValue == "regular-call-1")
    #expect(firstInput[3]["output"]?.stringValue == #"{"result":42}"#)

    _ = try await model.generate(LanguageModelRequest(
        messages: [
            .toolResponses(approvalResponses: [approvalResponse])
        ],
        extraBody: ["openai": ["store": false]]
    ))

    let secondBody = try decodeJSONBody(try #require((await transport.requests())[1].body))
    let secondInput = try #require(secondBody["input"]?.arrayValue)
    #expect(secondInput.count == 1)
    #expect(secondInput[0]["type"]?.stringValue == "mcp_approval_response")
    #expect(secondInput[0]["approval_request_id"]?.stringValue == "approval-for-mcp")
    #expect(secondInput[0]["approve"]?.boolValue == true)
}
@Test func openAIResponsesParsesFunctionAndHostedToolCalls() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp-1","status":"completed","output":[{"type":"function_call","id":"fc_1","call_id":"call_1","name":"lookup","arguments":"{\\"query\\":\\"weather\\"}"},{"type":"web_search_call","id":"ws_1","status":"completed","action":{"type":"search","query":"weather"}}],"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Use tools.")]))

    #expect(result.text == "")
    #expect(result.finishReason == "stop")
    #expect(result.toolCalls.count == 2)
    #expect(result.toolCalls[0].id == "call_1")
    #expect(result.toolCalls[0].name == "lookup")
    #expect(result.toolCalls[0].arguments == #"{"query":"weather"}"#)
    #expect(result.toolCalls[1].id == "ws_1")
    #expect(result.toolCalls[1].name == "web_search")
    #expect(result.toolCalls[1].providerExecuted == true)
    #expect(result.toolCalls[0].providerMetadata["openai"]?["itemId"]?.stringValue == "fc_1")
    #expect(result.toolResults.count == 1)
    #expect(result.toolResults[0].toolCallID == "ws_1")
    #expect(result.toolResults[0].toolName == "web_search")
    #expect(result.toolResults[0].result["action"]?["type"]?.stringValue == "search")
    #expect(result.toolResults[0].result["action"]?["query"]?.stringValue == "weather")
}
@Test func openAIResponsesParsesCustomAndComputerUseToolCallsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp-1","status":"completed","output":[{"type":"custom_tool_call","id":"ct_abc123def456","call_id":"call_custom_sql_001","name":"write_sql","input":"SELECT * FROM users WHERE age > 25"},{"type":"computer_call","id":"computer_67cf2b3051e88190b006770db6fdb13d","status":"completed"}],"usage":{"input_tokens":100,"output_tokens":50,"total_tokens":150}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o-mini")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Use tools.")],
        tools: [
            "write_sql": OpenAITools.customTool(name: "write_sql", format: ["type": "grammar", "syntax": "regex", "definition": "SELECT .+"]),
            "computer_use": OpenAITools.computerUse()
        ],
        extraBody: ["toolChoice": ["type": "tool", "toolName": "computer_use"]]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["tool_choice"]?["type"]?.stringValue == "function")
    #expect(body["tool_choice"]?["name"]?.stringValue == "computer_use")

    #expect(result.text == "")
    #expect(result.toolCalls.count == 2)
    #expect(result.toolCalls[0].id == "call_custom_sql_001")
    #expect(result.toolCalls[0].name == "write_sql")
    #expect(result.toolCalls[0].arguments == "\"SELECT * FROM users WHERE age > 25\"")
    #expect(result.toolCalls[0].providerMetadata["openai"]?["itemId"]?.stringValue == "ct_abc123def456")
    #expect(result.toolCalls[1].id == "computer_67cf2b3051e88190b006770db6fdb13d")
    #expect(result.toolCalls[1].name == "computer_use")
    #expect(result.toolCalls[1].arguments == "")
    #expect(result.toolCalls[1].providerExecuted == true)
    #expect(result.toolResults.count == 1)
    #expect(result.toolResults[0].toolCallID == "computer_67cf2b3051e88190b006770db6fdb13d")
    #expect(result.toolResults[0].toolName == "computer_use")
    #expect(result.toolResults[0].result["type"]?.stringValue == "computer_use_tool_result")
    #expect(result.toolResults[0].result["status"]?.stringValue == "completed")
}
@Test func openAIResponsesParsesToolSearchAndMCPResultsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp-1","status":"completed","output":[{"type":"tool_search_call","id":"tsc_server_1","execution":"server","status":"completed","arguments":{"goal":"Find the weather tool"}},{"type":"tool_search_output","id":"tso_server_1","execution":"server","status":"completed","tools":[{"type":"function","name":"get_weather","description":"Get weather","parameters":{"type":"object","properties":{"location":{"type":"string"}}},"strict":true,"defer_loading":true}]},{"type":"mcp_call","id":"mcp_1","server_label":"docs","name":"search","arguments":"{\\"query\\":\\"swift\\"}","output":"found docs"}],"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.4")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Find a tool and use MCP.")]))

    #expect(result.text == "")
    #expect(result.toolCalls.count == 2)
    #expect(result.toolCalls[0].id == "tsc_server_1")
    #expect(result.toolCalls[0].name == "tool_search")
    #expect(result.toolCalls[0].providerExecuted == true)
    let toolSearchInput = try decodeJSONBody(Data(result.toolCalls[0].arguments.utf8))
    #expect(toolSearchInput["arguments"]?["goal"]?.stringValue == "Find the weather tool")
    #expect(toolSearchInput["call_id"] == .null)
    #expect(result.toolCalls[0].providerMetadata["openai"]?["itemId"]?.stringValue == "tsc_server_1")
    #expect(result.toolCalls[1].id == "mcp_1")
    #expect(result.toolCalls[1].name == "mcp.search")
    #expect(result.toolCalls[1].providerExecuted == true)
    #expect(result.toolCalls[1].dynamic == true)

    #expect(result.toolResults.count == 2)
    #expect(result.toolResults[0].toolCallID == "tsc_server_1")
    #expect(result.toolResults[0].toolName == "tool_search")
    #expect(result.toolResults[0].result["tools"]?[0]?["name"]?.stringValue == "get_weather")
    #expect(result.toolResults[0].providerMetadata["openai"]?["itemId"]?.stringValue == "tso_server_1")
    #expect(result.toolResults[1].toolCallID == "mcp_1")
    #expect(result.toolResults[1].toolName == "mcp.search")
    #expect(result.toolResults[1].dynamic == true)
    #expect(result.toolResults[1].result["type"]?.stringValue == "call")
    #expect(result.toolResults[1].result["serverLabel"]?.stringValue == "docs")
    #expect(result.toolResults[1].result["name"]?.stringValue == "search")
    #expect(result.toolResults[1].result["output"]?.stringValue == "found docs")
    #expect(result.toolResults[1].providerMetadata["openai"]?["itemId"]?.stringValue == "mcp_1")
}
@Test func openAIResponsesParsesMCPApprovalRequests() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp-1","status":"completed","output":[{"type":"mcp_approval_request","id":"mcpr_1","approval_request_id":"approval-1","name":"create_short_url","arguments":"{\\"url\\":\\"https://example.com\\"}"}],"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Shorten this.")] ))

    #expect(result.text == "")
    #expect(result.toolCalls.count == 1)
    #expect(result.toolCalls[0].id == "tool-call-approval-1")
    #expect(result.toolCalls[0].name == "mcp.create_short_url")
    #expect(result.toolCalls[0].arguments == #"{"url":"https://example.com"}"#)
    #expect(result.toolCalls[0].providerExecuted == true)
    #expect(result.toolCalls[0].dynamic == true)
    #expect(result.toolApprovalRequests.count == 1)
    #expect(result.toolApprovalRequests[0].id == "approval-1")
    #expect(result.toolApprovalRequests[0].toolCallID == "tool-call-approval-1")
    #expect(result.toolApprovalRequests[0].toolName == "mcp.create_short_url")
    #expect(result.toolApprovalRequests[0].arguments == #"{"url":"https://example.com"}"#)
}
@Test func openAIResponsesStreamsFunctionToolCalls() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"lookup","arguments":""}}

    data: {"type":"response.function_call_arguments.delta","output_index":0,"delta":"{\\"query\\":"}

    data: {"type":"response.function_call_arguments.delta","output_index":0,"delta":"\\"weather\\"}"}

    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"lookup","arguments":"{\\"query\\":\\"weather\\"}"}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    var deltas: [String] = []
    var inputLifecycle: [String] = []
    var toolCall: AIToolCall?
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Use a tool.")])) {
        switch part {
        case let .toolInputStart(id, name, _, _, _, _):
            inputLifecycle.append("start:\(id):\(name)")
        case let .toolInputDelta(id, delta, _):
            inputLifecycle.append("delta:\(id):\(delta)")
        case let .toolInputEnd(id, _):
            inputLifecycle.append("end:\(id)")
        case let .toolCallDelta(_, _, argumentsDelta, _):
            deltas.append(argumentsDelta)
        case let .toolCall(call):
            toolCall = call
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(deltas == ["", "{\"query\":", "\"weather\"}"])
    #expect(inputLifecycle == [
        "start:call_1:lookup",
        "delta:call_1:{\"query\":",
        "delta:call_1:\"weather\"}",
        "end:call_1"
    ])
    #expect(toolCall?.id == "call_1")
    #expect(toolCall?.name == "lookup")
    #expect(toolCall?.arguments == #"{"query":"weather"}"#)
    #expect(finishReason == "stop")
}
@Test func openAIResponsesStreamsPrototypeNamedFunctionItemsSafely() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"__proto__","call_id":"call_proto","name":"lookup","arguments":""}}

    data: {"type":"response.function_call_arguments.delta","output_index":0,"item_id":"__proto__","delta":"{\\"query\\":"}

    data: {"type":"response.function_call_arguments.delta","output_index":0,"item_id":"__proto__","delta":"\\"weather\\"}"}

    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"__proto__","call_id":"call_proto","name":"lookup","arguments":"{\\"query\\":\\"weather\\"}"}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openResponses(
        name: "open-responses",
        url: "https://open.example.test/responses",
        settings: ProviderSettings(headers: ["Authorization": "Bearer custom-key"], transport: transport)
    )
    let model = try provider.languageModel("local-model")

    var toolCall: AIToolCall?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Use a tool.")])) {
        if case let .toolCall(call) = part {
            toolCall = call
        }
    }

    #expect(toolCall?.id == "call_proto")
    #expect(toolCall?.name == "lookup")
    #expect(toolCall?.arguments == #"{"query":"weather"}"#)
    #expect(toolCall?.providerMetadata["open-responses"]?["itemId"]?.stringValue == "__proto__")
}
