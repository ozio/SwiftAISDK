import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAILanguageDefaultsToResponsesAndMapsMultimodalInput() async throws {
    let pdf = Data("%PDF".utf8)
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"response text","usage":{"input_tokens":3,"output_tokens":4,"total_tokens":7}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        headers: ["OpenAI-Organization": "org-123", "OpenAI-Project": "proj-123"],
        transport: transport
    ))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .system("Be precise."),
            AIMessage(role: .user, content: [
                .text("Inspect this"),
                .imageURL("https://example.com/image.png"),
                .data(mimeType: "application/pdf", data: pdf)
            ])
        ],
        temperature: 0.4,
        topP: 0.9,
        maxOutputTokens: 256,
        extraBody: [
            "reasoningEffort": "medium",
            "reasoningSummary": "auto",
            "previousResponseId": "resp-old",
            "parallelToolCalls": false,
            "serviceTier": "flex"
        ]
    ))

    #expect(result.text == "response text")
    #expect(result.finishReason == "stop")
    #expect(result.usage?.totalTokens == 7)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/responses")
    #expect(request.headers["Authorization"] == "Bearer test-key")
    #expect(request.headers["OpenAI-Organization"] == "org-123")
    #expect(request.headers["OpenAI-Project"] == "proj-123")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "gpt-4.1")
    #expect(body["temperature"]?.doubleValue == 0.4)
    #expect(body["top_p"]?.doubleValue == 0.9)
    #expect(body["max_output_tokens"]?.intValue == 256)
    #expect(body["previous_response_id"]?.stringValue == "resp-old")
    #expect(body["parallel_tool_calls"]?.boolValue == false)
    #expect(body["service_tier"]?.stringValue == "flex")
    #expect(body["reasoning"]?["effort"]?.stringValue == "medium")
    #expect(body["reasoning"]?["summary"]?.stringValue == "auto")
    #expect(body["input"]?[0]?["role"]?.stringValue == "system")
    #expect(body["input"]?[0]?["content"]?.stringValue == "Be precise.")
    #expect(body["input"]?[1]?["role"]?.stringValue == "user")
    #expect(body["input"]?[1]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[1]?["content"]?[0]?["text"]?.stringValue == "Inspect this")
    #expect(body["input"]?[1]?["content"]?[1]?["type"]?.stringValue == "input_image")
    #expect(body["input"]?[1]?["content"]?[1]?["image_url"]?.stringValue == "https://example.com/image.png")
    #expect(body["input"]?[1]?["content"]?[2]?["type"]?.stringValue == "input_file")
    #expect(body["input"]?[1]?["content"]?[2]?["filename"]?.stringValue == "part-2.pdf")
    #expect(body["input"]?[1]?["content"]?[2]?["file_data"]?.stringValue == "data:application/pdf;base64,\(pdf.base64EncodedString())")
}

@Test func openAIProviderSettingsMapBaseURLOrganizationAndProject() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"configured","usage":{"total_tokens":2}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        baseURL: "https://proxy.example.com/openai/v1/",
        organization: "org-123",
        project: "proj-456",
        headers: ["OpenAI-Project": "proj-header"],
        transport: transport
    ))
    let model = try provider.languageModel("gpt-5-mini")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.text == "configured")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://proxy.example.com/openai/v1/responses")
    #expect(request.headers["Authorization"] == "Bearer test-key")
    #expect(request.headers["OpenAI-Organization"] == "org-123")
    #expect(request.headers["OpenAI-Project"] == "proj-header")
}

@Test func openAIProviderAliasesRouteToUpstreamEndpoints() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"responses alias"}"#),
        jsonResponse(#"{"choices":[{"message":{"content":"chat alias"},"finish_reason":"stop"}]}"#),
        jsonResponse(#"{"choices":[{"text":"completion alias","finish_reason":"stop"}]}"#)
    ])
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))

    let languageModel = try provider.languageModel("gpt-4.1")
    let responsesModel = try provider.responses("gpt-4.1")
    let chatModel = try provider.chat("gpt-4.1-mini")
    let completionModel = try provider.completion("gpt-3.5-turbo-instruct")
    let embeddingModel = try provider.embeddingModel("text-embedding-3-small")
    let imageModel = try provider.imageModel("gpt-image-1")
    let transcriptionModel = try provider.transcriptionModel("gpt-4o-transcribe")
    let speechModel = try provider.speechModel("gpt-4o-mini-tts")
    let files = provider.files()
    let skills = try provider.skills()

    #expect(provider.providerID == "openai")
    #expect(languageModel.providerID == "openai.responses")
    #expect(responsesModel.providerID == "openai.responses")
    #expect(chatModel.providerID == "openai.chat")
    #expect(completionModel.providerID == "openai.completion")
    #expect(embeddingModel.providerID == "openai.embedding")
    #expect(imageModel.providerID == "openai.image")
    #expect(transcriptionModel.providerID == "openai.transcription")
    #expect(speechModel.providerID == "openai.speech")
    #expect(files.providerID == "openai.files")
    #expect(skills.providerID == "openai.skills")

    let responsesResult = try await responsesModel.generate(LanguageModelRequest(messages: [.user("Hi")]))
    let chatResult = try await chatModel.generate(LanguageModelRequest(messages: [.user("Hi")]))
    let completionResult = try await completionModel.generate(LanguageModelRequest(messages: [.user("Finish")]))

    #expect(responsesResult.text == "responses alias")
    #expect(chatResult.text == "chat alias")
    #expect(completionResult.text == "completion alias")
    let requests = await transport.requests()
    #expect(requests[0].url.absoluteString == "https://api.openai.com/v1/responses")
    #expect(requests[1].url.absoluteString == "https://api.openai.com/v1/chat/completions")
    #expect(requests[2].url.absoluteString == "https://api.openai.com/v1/completions")
}

@Test func openAIResponsesMapsNestedProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done","usage":{"total_tokens":3}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: [
            "openai": .object([
                "store": .bool(false),
                "previousResponseId": .string("resp-old"),
                "parallelToolCalls": .bool(false),
                "reasoningEffort": .string("low"),
                "reasoningSummary": .string("auto")
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["store"]?.boolValue == false)
    #expect(body["previous_response_id"]?.stringValue == "resp-old")
    #expect(body["parallel_tool_calls"]?.boolValue == false)
    #expect(body["reasoning"]?["effort"]?.stringValue == "low")
    #expect(body["reasoning"]?["summary"]?.stringValue == "auto")
    #expect(body["openai"] == nil)
    #expect(body["previousResponseId"] == nil)
    #expect(body["parallelToolCalls"] == nil)
    #expect(body["reasoningEffort"] == nil)
    #expect(body["reasoningSummary"] == nil)
}

@Test func openAIResponsesGenerateMapsIncompleteFinishReason() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output_text":"partial","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.text == "partial")
    #expect(result.finishReason == "length")
    #expect(result.usage?.totalTokens == 3)
}

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
    #expect(tools.count == 8)

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

@Test func openAIResponsesStreamsMCPApprovalRequests() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"mcp_approval_request","id":"mcpr_1","approval_request_id":"approval-1","name":"create_short_url","arguments":"{\\"url\\":\\"https://example.com\\"}"}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    var toolCall: AIToolCall?
    var approvalRequest: AIToolApprovalRequest?
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Shorten this.")])) {
        switch part {
        case let .toolCall(call):
            toolCall = call
        case let .toolApprovalRequest(request):
            approvalRequest = request
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(toolCall?.id == "tool-call-approval-1")
    #expect(toolCall?.name == "mcp.create_short_url")
    #expect(toolCall?.providerExecuted == true)
    #expect(toolCall?.dynamic == true)
    #expect(approvalRequest?.id == "approval-1")
    #expect(approvalRequest?.toolCallID == "tool-call-approval-1")
    #expect(finishReason == "stop")
}

@Test func openAIResponsesStreamsTextReasoningAndFinishUsage() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.reasoning_summary_text.delta","delta":"think"}

    data: {"type":"response.output_text.delta","delta":"answer"}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    var text: [String] = []
    var reasoning: [String] = []
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textDelta(delta):
            text.append(delta)
        case let .reasoningDelta(delta):
            reasoning.append(delta)
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(reasoning == ["think"])
    #expect(text == ["answer"])
    #expect(finishReason == "stop")
    #expect(totalTokens == 3)
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
}

@Test func openAIResponsesStreamMapsIncompleteFinishReason() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_text.delta","delta":"partial"}

    data: {"type":"response.incomplete","response":{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    var text: [String] = []
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textDelta(delta):
            text.append(delta)
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(text == ["partial"])
    #expect(finishReason == "length")
    #expect(totalTokens == 3)
}
