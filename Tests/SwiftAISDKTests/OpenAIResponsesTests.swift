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

@Test func openAIResponsesGenerateMapsAnnotationSourcesLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"""
    {
      "id": "resp-annotations",
      "status": "completed",
      "output_text": "Based on web search and file content.",
      "output": [
        {
          "id": "msg-annotations",
          "type": "message",
          "status": "completed",
          "role": "assistant",
          "content": [
            {
              "type": "output_text",
              "text": "Based on web search and file content.",
              "annotations": [
                {"type":"url_citation","url":"https://example.com","title":"Example URL","start_index":0,"end_index":10},
                {"type":"file_citation","file_id":"file-abc123","filename":"resource1.json","index":123},
                {"type":"container_file_citation","container_id":"cntr-1","file_id":"cfile-1","filename":"rolls.csv","start_index":42,"end_index":51},
                {"type":"file_path","file_id":"cfile-path","index":7}
              ]
            }
          ]
        }
      ],
      "usage": {"input_tokens":1,"output_tokens":2,"total_tokens":3}
    }
    """#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.sources.map(\.sourceType) == ["url", "document", "document", "document"])
    #expect(result.sources[0].url == "https://example.com")
    #expect(result.sources[0].title == "Example URL")
    #expect(result.sources[1].mediaType == "text/plain")
    #expect(result.sources[1].filename == "resource1.json")
    #expect(result.sources[1].providerMetadata["openai"]?["type"]?.stringValue == "file_citation")
    #expect(result.sources[1].providerMetadata["openai"]?["fileId"]?.stringValue == "file-abc123")
    #expect(result.sources[1].providerMetadata["openai"]?["index"]?.intValue == 123)
    #expect(result.sources[2].providerMetadata["openai"]?["type"]?.stringValue == "container_file_citation")
    #expect(result.sources[2].providerMetadata["openai"]?["containerId"]?.stringValue == "cntr-1")
    #expect(result.sources[3].mediaType == "application/octet-stream")
    #expect(result.sources[3].filename == "cfile-path")
    #expect(result.sources[3].providerMetadata["openai"]?["type"]?.stringValue == "file_path")
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
            "computer_use": OpenAITools.computerUse(displayWidth: 1024, displayHeight: 768, environment: "browser"),
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
    #expect(tools.count == 9)

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
    #expect(body["tool_choice"]?["type"]?.stringValue == "computer_use")

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

@Test func openAIResponsesStreamsComputerUseToolResultsLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"type":"computer_call","id":"computer_67cf2b3051e88190b006770db6fdb13d","status":"in_progress"}}

    data: {"type":"response.output_item.done","output_index":0,"item":{"type":"computer_call","id":"computer_67cf2b3051e88190b006770db6fdb13d","status":"completed"}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o-mini")

    var lifecycle: [String] = []
    var toolCall: AIToolCall?
    var toolResult: AIToolResult?
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Use the computer.")])) {
        switch part {
        case let .toolInputStart(id, name, providerExecuted, _, _, _):
            lifecycle.append("start:\(id):\(name):\(providerExecuted)")
        case let .toolInputEnd(id, _):
            lifecycle.append("end:\(id)")
        case let .toolCall(call):
            toolCall = call
        case let .toolResult(result):
            toolResult = result
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(lifecycle == [
        "start:computer_67cf2b3051e88190b006770db6fdb13d:computer_use:true",
        "end:computer_67cf2b3051e88190b006770db6fdb13d"
    ])
    #expect(toolCall?.id == "computer_67cf2b3051e88190b006770db6fdb13d")
    #expect(toolCall?.name == "computer_use")
    #expect(toolCall?.arguments == "")
    #expect(toolCall?.providerExecuted == true)
    #expect(toolResult?.toolCallID == "computer_67cf2b3051e88190b006770db6fdb13d")
    #expect(toolResult?.toolName == "computer_use")
    #expect(toolResult?.result["type"]?.stringValue == "computer_use_tool_result")
    #expect(toolResult?.result["status"]?.stringValue == "completed")
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

@Test func openAIResponsesStreamsTextLifecycleProviderMetadataLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"msg_commentary","type":"message","status":"in_progress","content":[],"phase":"commentary","role":"assistant"}}

    data: {"type":"response.output_text.delta","item_id":"msg_commentary","output_index":0,"content_index":0,"delta":"checking"}

    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"msg_commentary","type":"message","status":"completed","content":[{"type":"output_text","text":"checking","annotations":[]}],"phase":"commentary","role":"assistant"}}

    data: {"type":"response.output_item.added","output_index":1,"item":{"id":"msg_final","type":"message","status":"in_progress","content":[],"phase":"final_answer","role":"assistant"}}

    data: {"type":"response.output_text.delta","item_id":"msg_final","output_index":1,"content_index":0,"delta":"answer"}

    data: {"type":"response.output_item.done","output_index":1,"item":{"id":"msg_final","type":"message","status":"completed","content":[{"type":"output_text","text":"answer","annotations":[]}],"phase":"final_answer","role":"assistant"}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.3-codex")

    var textStarts: [(String, [String: JSONValue])] = []
    var textDeltas: [(String, String, [String: JSONValue])] = []
    var textEnds: [(String, [String: JSONValue])] = []
    var legacyText: [String] = []
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textStart(id, metadata):
            textStarts.append((id, metadata))
        case let .textDelta(delta):
            legacyText.append(delta)
        case let .textDeltaPart(id, delta, metadata):
            textDeltas.append((id, delta, metadata))
        case let .textEnd(id, metadata):
            textEnds.append((id, metadata))
        default:
            break
        }
    }

    #expect(legacyText == ["checking", "answer"])
    #expect(textStarts.map { $0.0 } == ["msg_commentary", "msg_final"])
    #expect(textDeltas.map { $0.0 } == ["msg_commentary", "msg_final"])
    #expect(textDeltas.map { $0.1 } == ["checking", "answer"])
    #expect(textEnds.map { $0.0 } == ["msg_commentary", "msg_final"])
    #expect(textStarts[0].1["openai"]?["itemId"]?.stringValue == "msg_commentary")
    #expect(textStarts[0].1["openai"]?["phase"]?.stringValue == "commentary")
    #expect(textDeltas[0].2["openai"]?["phase"]?.stringValue == "commentary")
    #expect(textEnds[0].1["openai"]?["phase"]?.stringValue == "commentary")
    #expect(textStarts[1].1["openai"]?["itemId"]?.stringValue == "msg_final")
    #expect(textStarts[1].1["openai"]?["phase"]?.stringValue == "final_answer")
    #expect(textDeltas[1].2["openai"]?["phase"]?.stringValue == "final_answer")
    #expect(textEnds[1].1["openai"]?["phase"]?.stringValue == "final_answer")
}

@Test func openAIResponsesStreamsReasoningLifecycleProviderMetadataLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"rs_reasoning","type":"reasoning","encrypted_content":"encrypted_reasoning_data_initial"}}

    data: {"type":"response.reasoning_summary_part.added","item_id":"rs_reasoning","summary_index":0}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_reasoning","summary_index":0,"delta":"first thought"}

    data: {"type":"response.reasoning_summary_part.done","item_id":"rs_reasoning","summary_index":0}

    data: {"type":"response.reasoning_summary_part.added","item_id":"rs_reasoning","summary_index":1}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_reasoning","summary_index":1,"delta":"second thought"}

    data: {"type":"response.reasoning_summary_part.done","item_id":"rs_reasoning","summary_index":1}

    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"rs_reasoning","type":"reasoning","encrypted_content":"encrypted_reasoning_data_final"}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("o3-mini")

    var reasoningStarts: [(String, [String: JSONValue])] = []
    var reasoningDeltas: [(String, String, [String: JSONValue])] = []
    var reasoningEnds: [(String, [String: JSONValue])] = []
    var legacyReasoning: [String] = []
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: ["store": false]
    )) {
        switch part {
        case let .reasoningStart(id, metadata):
            reasoningStarts.append((id, metadata))
        case let .reasoningDelta(delta):
            legacyReasoning.append(delta)
        case let .reasoningDeltaPart(id, delta, metadata):
            reasoningDeltas.append((id, delta, metadata))
        case let .reasoningEnd(id, metadata):
            reasoningEnds.append((id, metadata))
        default:
            break
        }
    }

    #expect(legacyReasoning == ["first thought", "second thought"])
    #expect(reasoningStarts.map { $0.0 } == ["rs_reasoning:0", "rs_reasoning:1"])
    #expect(reasoningDeltas.map { $0.0 } == ["rs_reasoning:0", "rs_reasoning:1"])
    #expect(reasoningDeltas.map { $0.1 } == ["first thought", "second thought"])
    #expect(reasoningEnds.map { $0.0 } == ["rs_reasoning:0", "rs_reasoning:1"])
    #expect(reasoningStarts[0].1["openai"]?["itemId"]?.stringValue == "rs_reasoning")
    #expect(reasoningStarts[0].1["openai"]?["reasoningEncryptedContent"]?.stringValue == "encrypted_reasoning_data_initial")
    #expect(reasoningDeltas[0].2["openai"]?["itemId"]?.stringValue == "rs_reasoning")
    #expect(reasoningDeltas[0].2["openai"]?["reasoningEncryptedContent"] == nil)
    #expect(reasoningEnds[0].1["openai"]?["itemId"]?.stringValue == "rs_reasoning")
    #expect(reasoningEnds[0].1["openai"]?["reasoningEncryptedContent"] == nil)
    #expect(reasoningStarts[1].1["openai"]?["reasoningEncryptedContent"]?.stringValue == "encrypted_reasoning_data_initial")
    #expect(reasoningEnds[1].1["openai"]?["reasoningEncryptedContent"]?.stringValue == "encrypted_reasoning_data_final")
}

@Test func openAIResponsesStreamsAnnotationSourcesAndTextMetadataLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"msg_annotations","type":"message","status":"in_progress","content":[],"role":"assistant"}}

    data: {"type":"response.output_text.annotation.added","item_id":"msg_annotations","output_index":0,"content_index":0,"annotation_index":0,"annotation":{"type":"url_citation","url":"https://example.com","title":"Example URL","start_index":0,"end_index":10}}

    data: {"type":"response.output_text.annotation.added","item_id":"msg_annotations","output_index":0,"content_index":0,"annotation_index":1,"annotation":{"type":"file_citation","file_id":"file-abc123","filename":"resource1.json","index":123}}

    data: {"type":"response.output_text.annotation.added","item_id":"msg_annotations","output_index":0,"content_index":0,"annotation_index":2,"annotation":{"type":"container_file_citation","container_id":"cntr-1","file_id":"cfile-1","filename":"rolls.csv","start_index":42,"end_index":51}}

    data: {"type":"response.output_text.annotation.added","item_id":"msg_annotations","output_index":0,"content_index":0,"annotation_index":3,"annotation":{"type":"file_path","file_id":"cfile-path","index":7}}

    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"msg_annotations","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Based on sources.","annotations":[]}]}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    var sources: [AISource] = []
    var textEndMetadata: [String: JSONValue] = [:]
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .source(source):
            sources.append(source)
        case let .textEnd(id, metadata) where id == "msg_annotations":
            textEndMetadata = metadata
        default:
            break
        }
    }

    #expect(sources.map(\.sourceType) == ["url", "document", "document", "document"])
    #expect(sources[0].url == "https://example.com")
    #expect(sources[1].filename == "resource1.json")
    #expect(sources[1].providerMetadata["openai"]?["type"]?.stringValue == "file_citation")
    #expect(sources[1].providerMetadata["openai"]?["fileId"]?.stringValue == "file-abc123")
    #expect(sources[1].providerMetadata["openai"]?["index"]?.intValue == 123)
    #expect(sources[2].providerMetadata["openai"]?["containerId"]?.stringValue == "cntr-1")
    #expect(sources[3].mediaType == "application/octet-stream")
    #expect(sources[3].filename == "cfile-path")
    let annotations = try #require(textEndMetadata["openai"]?["annotations"]?.arrayValue)
    #expect(textEndMetadata["openai"]?["itemId"]?.stringValue == "msg_annotations")
    #expect(annotations.count == 4)
    #expect(annotations[0]["type"]?.stringValue == "url_citation")
    #expect(annotations[1]["type"]?.stringValue == "file_citation")
    #expect(annotations[2]["type"]?.stringValue == "container_file_citation")
    #expect(annotations[3]["type"]?.stringValue == "file_path")
}

@Test func openAIResponsesStreamsCompactionCustomPartLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"cmp_123","type":"compaction","encrypted_content":"encrypted_compaction"}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2")

    var customParts: [(JSONValue, [String: JSONValue])] = []
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Compact context.")])) {
        if case let .custom(value, metadata) = part {
            customParts.append((value, metadata))
        }
    }

    let custom = try #require(customParts.first)
    #expect(custom.0["kind"]?.stringValue == "openai.compaction")
    #expect(custom.1["openai"]?["type"]?.stringValue == "compaction")
    #expect(custom.1["openai"]?["itemId"]?.stringValue == "cmp_123")
    #expect(custom.1["openai"]?["encryptedContent"]?.stringValue == "encrypted_compaction")
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
