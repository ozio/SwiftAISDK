import Foundation
import Testing
@testable import SwiftAISDK

@Suite("WeeklyMajorProviders20260920", .serialized)
struct WeeklyMajorProviders20260920Tests {
    @Test func alibabaPreserveThinkingUsesModelDefaultsAndKeepsCurrentRoundReasoning() throws {
        let messages: [AIMessage] = [
            .user("First"),
            AIMessage(role: .assistant, content: [.reasoning("historical")]),
            .user("Second"),
            AIMessage(role: .assistant, content: [.reasoning("current")])
        ]

        let defaulted = try alibabaPreparedCall(
            for: LanguageModelRequest(messages: messages),
            modelID: "qwen3.8-max",
            stream: false,
            transformRequestBody: nil
        )
        let defaultedMessages = try #require(defaulted.body["messages"]?.arrayValue)
        #expect(defaulted.body["preserve_thinking"]?.boolValue == true)
        #expect(defaultedMessages.count == 4)
        #expect(defaultedMessages[1]["reasoning_content"]?.stringValue == "historical")
        #expect(defaultedMessages[3]["reasoning_content"]?.stringValue == "current")
        #expect(defaultedMessages[3]["content"] == .null)

        let disabled = try alibabaPreparedCall(
            for: LanguageModelRequest(
                messages: messages,
                providerOptions: ["alibaba": ["preserveThinking": false]]
            ),
            modelID: "qwen3.8-max",
            stream: false,
            transformRequestBody: nil
        )
        let disabledMessages = try #require(disabled.body["messages"]?.arrayValue)
        #expect(disabled.body["preserve_thinking"]?.boolValue == false)
        #expect(disabledMessages.count == 3)
        #expect(disabledMessages[2]["reasoning_content"]?.stringValue == "current")

        let unsupported = try alibabaPreparedCall(
            for: LanguageModelRequest(messages: messages),
            modelID: "qwen-plus",
            stream: false,
            transformRequestBody: nil
        )
        #expect(unsupported.body["preserve_thinking"] == nil)
        #expect(unsupported.body["messages"]?.arrayValue?.count == 3)

        #expect(throws: AIError.invalidArgument(
            argument: "providerOptions.alibaba.preserveThinking",
            message: "Alibaba preserveThinking must be a boolean."
        )) {
            _ = try alibabaPreparedCall(
                for: LanguageModelRequest(
                    messages: [.user("Hi")],
                    providerOptions: ["alibaba": ["preserveThinking": "yes"]]
                ),
                modelID: "qwen3.8-max",
                stream: false,
                transformRequestBody: nil
            )
        }
    }

    @Test func bedrockOpaqueAnthropicFamilyFiltersNewWebToolsAndRetainsToolChoice() throws {
        #expect(bedrockIsAnthropicModel(
            modelID: "opaque-application-profile",
            modelFamily: .anthropic,
            reasoningConfig: nil
        ))

        let prepared = bedrockPrepareTools(
            from: [
                "research": AnthropicTools.webSearch_20260318(responseInclusion: "full"),
                "lookup": [
                    "type": "object",
                    "properties": ["query": ["type": "string"]],
                    "required": ["query"]
                ]
            ],
            toolChoice: ["type": "required"],
            modelID: "opaque-application-profile",
            modelFamily: .anthropic,
            disableParallelToolUse: true
        )

        let tools = try #require(prepared.toolConfig?["tools"]?.arrayValue)
        #expect(tools.count == 1)
        #expect(tools[0]["toolSpec"]?["name"]?.stringValue == "lookup")
        #expect(prepared.additionalModelRequestFields?["tool_choice"]?["type"]?.stringValue == "any")
        #expect(prepared.additionalModelRequestFields?["tool_choice"]?["disable_parallel_tool_use"]?.boolValue == true)
        #expect(prepared.warnings.contains {
            $0.type == "unsupported" && $0.feature == "web_search_20260318 tool"
        })
    }

    @Test func bedrockStrictSchemaChecksNestedObjectsAndThinkingBindingUsesCurrentKey() throws {
        let incompatible: JSONValue = [
            "type": "object",
            "strict": true,
            "additionalProperties": false,
            "properties": [
                "nested": [
                    "type": "object",
                    "properties": ["value": ["type": "string"]]
                ]
            ]
        ]
        let prepared = bedrockPrepareTools(
            from: ["nested": incompatible],
            toolChoice: nil,
            modelID: "amazon.nova-pro-v1:0"
        )
        #expect(prepared.toolConfig?["tools"]?[0]?["toolSpec"]?["strict"] == nil)
        #expect(prepared.warnings.contains {
            $0.feature == "strict" && $0.message?.contains("every object") == true
        })

        let body = amazonBedrockThinkingBindingBody([
            "thinking": [
                "type": "enabled",
                "block_binding": [
                    "prefix_mismatch_behavior": "ignore",
                    "other": "discard"
                ]
            ]
        ])
        #expect(body["thinking"]?["block_binding"]?["mismatch_behavior"]?.stringValue == "ignore")
        #expect(body["thinking"]?["block_binding"]?["prefix_mismatch_behavior"] == nil)
        #expect(body["thinking"]?["block_binding"]?["other"] == nil)
    }

    @Test func bedrockFailedResponsePreservesTypedAndUntypedMessages() {
        let typed = bedrockHTTPStatusError(
            provider: "amazon-bedrock",
            response: AIHTTPResponse(
                statusCode: 400,
                headers: ["x-amzn-requestid": "req-1"],
                body: Data(#"{"type":"ValidationException","message":"invalid request"}"#.utf8)
            )
        )
        #expect(typed == .apiCall(
            provider: "amazon-bedrock",
            statusCode: 400,
            body: "ValidationException: invalid request",
            headers: ["x-amzn-requestid": "req-1"]
        ))

        let untyped = bedrockHTTPStatusError(
            provider: "amazon-bedrock",
            response: AIHTTPResponse(
                statusCode: 429,
                body: Data(#"{"message":"slow down"}"#.utf8)
            )
        )
        #expect(untyped == .apiCall(provider: "amazon-bedrock", statusCode: 429, body: "slow down"))
    }

    @Test func anthropicWebTools20260318ExposeSchemasAndAvoidSpuriousBeta() throws {
        let search = AnthropicTools.webSearch_20260318(
            maxUses: 2,
            responseInclusion: "excluded"
        )
        let fetch = AnthropicTools.webFetch_20260318(
            useCache: false,
            responseInclusion: "full"
        )
        #expect(search["inputSchema"]?["properties"]?["query"]?["type"]?.stringValue == "string")
        #expect(search["outputSchema"]?["items"]?["properties"]?["type"]?["const"]?.stringValue == "web_search_result")
        #expect(search["supportsDeferredResults"]?.boolValue == true)
        #expect(fetch["inputSchema"]?["properties"]?["url"]?["type"]?.stringValue == "string")
        #expect(fetch["supportsDeferredResults"]?.boolValue == true)

        let prepared = try AnthropicLanguageModel.body(
            for: LanguageModelRequest(
                messages: [.user("Research")],
                tools: ["research": search]
            ),
            modelID: "claude-sonnet-4-6",
            providerID: "anthropic.messages"
        )
        #expect(prepared.body["tools"]?[0]?["type"]?.stringValue == "web_search_20260318")
        #expect(prepared.body["tools"]?[0]?["name"]?.stringValue == "web_search")
        #expect(prepared.body["tools"]?[0]?["response_inclusion"]?.stringValue == "excluded")
        #expect(!prepared.betas.contains("code-execution-web-tools-2026-02-09"))
        #expect(prepared.markCodeExecutionDynamic)
        #expect(prepared.toolNameMapping.toCustomToolName("web_search") == "research")

        #expect(throws: AIError.invalidArgument(
            argument: "tools.research.args.responseInclusion",
            message: "Anthropic responseInclusion must be \"full\" or \"excluded\"."
        )) {
            _ = try anthropicPrepareTools(from: [
                "research": AnthropicTools.webSearch_20260318(responseInclusion: "summary")
            ])
        }
    }

    @Test func anthropicGeneratedAndDeferredStreamToolsKeepCustomNamesAndLifecycle() throws {
        let mapping = AIToolNameMapping(customToolNameToProviderToolName: ["research": "web_search"])
        let generated = anthropicGeneratedContent(
            from: .array([
                [
                    "type": "server_tool_use",
                    "id": "srv-code",
                    "name": "code_execution",
                    "input": ["code": "print(1)"]
                ],
                [
                    "type": "server_tool_use",
                    "id": "srv-search",
                    "name": "web_search",
                    "input": ["query": "Swift"]
                ],
                [
                    "type": "web_search_tool_result",
                    "tool_use_id": "srv-search",
                    "content": [[
                        "url": "https://example.com",
                        "title": "Example",
                        "page_age": nil,
                        "encrypted_content": "ciphertext",
                        "type": "web_search_result"
                    ]]
                ]
            ]),
            providerID: "anthropic.messages",
            citationDocuments: [],
            toolNameMapping: mapping,
            markCodeExecutionDynamic: true
        )
        #expect(generated.toolCalls[0].name == "code_execution")
        #expect(generated.toolCalls[0].dynamic)
        #expect(generated.toolCalls[1].name == "research")
        #expect(generated.toolResults[0].toolName == "research")

        var streaming = AnthropicStreamingToolCalls(
            providerID: "anthropic.messages",
            toolNameMapping: mapping
        )
        let parts = streaming.apply(messageStartContent: .array([[
            "type": "tool_use",
            "id": "toolu-deferred",
            "name": "lookup",
            "input": ["query": "ready"]
        ]]))
        let call = try #require(parts.compactMap { part -> AIToolCall? in
            guard case let .toolCall(call) = part else { return nil }
            return call
        }.first)
        #expect(call.id == "toolu-deferred")
        #expect(call.name == "lookup")
        #expect(call.arguments == #"{"query":"ready"}"#)
        #expect(parts.contains { part in
            if case let .toolInputStart(id, name, _, _, _, _) = part {
                return id == "toolu-deferred" && name == "lookup"
            }
            return false
        })
        #expect(parts.contains { part in
            if case let .toolInputEnd(id, _) = part { return id == "toolu-deferred" }
            return false
        })
    }

    @Test func deepSeekEmptyChoicesUsesExactInvalidResponse() async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"choices":[]}"#))
        let provider = try AIProviders.deepSeek(settings: ProviderSettings(apiKey: "deepseek-key", transport: transport))
        let model = try provider.languageModel("deepseek-chat")

        await #expect(throws: AIError.invalidResponse(
            provider: "deepseek.chat",
            message: "Response did not contain any choices."
        )) {
            _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))
        }
    }

    @Test func googleLosslessJSONSchemaUsesCurrentWireKeysRecursively() throws {
        let schema: JSONValue = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$defs": [
                "Tag": [
                    "type": "object",
                    "properties": ["kind": ["const": "nested"]],
                    "additionalProperties": false
                ]
            ],
            "type": "object",
            "properties": [
                "status": ["const": "ok"],
                "tuple": ["items": [["const": 1], ["const": 2]]]
            ],
            "additionalProperties": ["const": false],
            "anyOf": [["const": "a"], ["const": "b"]],
            "oneOf": [["const": 3], ["const": 4]]
        ]
        let converted = googleResponseJSONSchema(schema)
        #expect(converted["$schema"]?.stringValue == "https://json-schema.org/draft/2020-12/schema")
        #expect(converted["properties"]?["status"]?["const"] == nil)
        #expect(converted["properties"]?["status"]?["enum"]?[0]?.stringValue == "ok")
        #expect(converted["properties"]?["tuple"]?["items"]?[1]?["enum"]?[0]?.intValue == 2)
        #expect(converted["additionalProperties"]?["enum"]?[0]?.boolValue == false)
        #expect(converted["anyOf"]?[0]?["enum"]?[0]?.stringValue == "a")
        #expect(converted["oneOf"]?[1]?["enum"]?[0]?.intValue == 4)
        #expect(converted["$defs"]?["Tag"]?["properties"]?["kind"]?["enum"]?[0]?.stringValue == "nested")

        let declarations = try googleFunctionDeclarations(from: ["lookup": schema])
        #expect(declarations[0]["parametersJsonSchema"] == schema)
        #expect(declarations[0]["parameters"] == nil)

        var generationConfig: [String: JSONValue] = [:]
        try googleApplyResponseFormat(
            ["type": "json", "schema": schema],
            options: [:],
            to: &generationConfig
        )
        #expect(generationConfig["responseJsonSchema"] == converted)
        #expect(generationConfig["responseSchema"] == nil)
    }

    @Test func googleStreamingMetadataMergesAcrossChunksAndCountsToolPromptTokens() throws {
        #expect(googleConfirmedPromptBlockReason("BLOCK_REASON_UNSPECIFIED") == nil)
        #expect(googleConfirmedPromptBlockReason("BLOCKED_REASON_UNSPECIFIED") == nil)
        #expect(googleConfirmedPromptBlockReason("SAFETY") == "SAFETY")

        let usage = googleGenerateContentUsage(fromUsageMetadata: [
            "promptTokenCount": 10,
            "toolUsePromptTokenCount": 3,
            "cachedContentTokenCount": 2,
            "candidatesTokenCount": 4,
            "thoughtsTokenCount": 5,
            "totalTokenCount": 22
        ])
        #expect(usage.inputTokens == 13)
        #expect(usage.inputTokensNoCache == 11)
        #expect(usage.outputTokens == 9)

        var state = GoogleGenerateContentStreamState(
            response: AIHTTPResponse(statusCode: 200),
            includeRawChunks: false,
            modelID: "gemini-2.5-flash",
            warnings: []
        )
        _ = state.apply([
            "promptFeedback": ["blockReason": "BLOCK_REASON_UNSPECIFIED"],
            "candidates": [[
                "content": ["parts": [["text": "first"]]],
                "groundingMetadata": [
                    "webSearchQueries": ["Swift"],
                    "groundingChunks": [["web": ["uri": "https://example.com", "title": "Example"]]]
                ],
                "urlContextMetadata": [
                    "urlMetadata": [["retrievedUrl": "https://docs.example", "urlRetrievalStatus": "URL_RETRIEVAL_STATUS_SUCCESS"]]
                ]
            ]]
        ])
        _ = state.apply([
            "candidates": [[
                "content": ["parts": [["text": " second"]]],
                "finishReason": "STOP",
                "finishMessage": "complete",
                "safetyRatings": [["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "probability": "NEGLIGIBLE"]]
            ]],
            "usageMetadata": [
                "promptTokenCount": 10,
                "toolUsePromptTokenCount": 3,
                "candidatesTokenCount": 4,
                "thoughtsTokenCount": 5,
                "totalTokenCount": 22
            ]
        ])
        let finish = try #require(state.finish().compactMap { part -> (String?, TokenUsage?, [String: JSONValue])? in
            guard case let .finishMetadata(reason, usage, metadata) = part else { return nil }
            return (reason, usage, metadata)
        }.first)
        #expect(finish.0 == "stop")
        #expect(finish.1?.inputTokens == 13)
        #expect(finish.2["google"]?["groundingMetadata"]?["webSearchQueries"]?[0]?.stringValue == "Swift")
        #expect(finish.2["google"]?["urlContextMetadata"]?["urlMetadata"]?[0]?["retrievedUrl"]?.stringValue == "https://docs.example")
        #expect(finish.2["google"]?["safetyRatings"]?[0]?["probability"]?.stringValue == "NEGLIGIBLE")
        #expect(finish.2["google"]?["finishMessage"]?.stringValue == "complete")

        let shallow = googleMergeProviderMetadata(
            ["google": [
                "groundingMetadata": ["kept": true],
                "usageMetadata": ["promptTokenCount": 1, "serviceTier": "old"]
            ]],
            ["google": ["usageMetadata": ["promptTokenCount": 2]]]
        )
        #expect(shallow["google"]?["groundingMetadata"]?["kept"]?.boolValue == true)
        #expect(shallow["google"]?["usageMetadata"]?["promptTokenCount"]?.intValue == 2)
        #expect(shallow["google"]?["usageMetadata"]?["serviceTier"] == nil)
    }

    @Test func googleGeminiImageEnforcesOneImageWithinCurrentArchitecture() async throws {
        let transport = RecordingTransport(responses: [])
        let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
        let model = try provider.imageModel("gemini-2.5-flash-image")

        await #expect(throws: AIError.invalidArgument(
            argument: "count",
            message: "Gemini image models do not support generating a set number of images per call. Use n=1 or omit the n parameter."
        )) {
            _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", count: 2))
        }
        #expect(await transport.requests().isEmpty)
    }

    @Test func togetherAIGeminiImageOmitsDiffusionFieldsButKeepsSizeAndCustomOptions() async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"image"}]}"#))
        let provider = try AIProviders.togetherAI(settings: ProviderSettings(apiKey: "together-key", transport: transport))
        let model = try provider.imageModel("google/gemini-3-pro-image")

        let result = try await model.generateImage(ImageGenerationRequest(
            prompt: "cat",
            size: "1024x768",
            seed: 42,
            providerOptions: [
                "togetherai": [
                    "steps": 4,
                    "guidance": 3.5,
                    "negative_prompt": "blur",
                    "disable_safety_checker": true,
                    "custom_option": "kept"
                ]
            ]
        ))

        let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
        #expect(body["width"]?.intValue == 1024)
        #expect(body["height"]?.intValue == 768)
        #expect(body["custom_option"]?.stringValue == "kept")
        #expect(body["steps"] == nil)
        #expect(body["guidance"] == nil)
        #expect(body["negative_prompt"] == nil)
        #expect(body["disable_safety_checker"] == nil)
        #expect(body["seed"] == nil)
        #expect(result.warnings.contains { $0.type == "unsupported" && $0.feature == "seed" })
    }
    @Test func anthropicNormalizesImplicitCodeAndToolSearchParity() throws {
        let mapping = AIToolNameMapping(
            customToolNameToProviderToolName: ["searchTools": "tool_search_tool_regex"]
        )
        let generated = anthropicGeneratedContent(
            from: .array([
                ["type": "server_tool_use", "id": "direct", "name": "code_execution", "input": ["code": "print(1)"]],
                ["type": "server_tool_use", "id": "bash", "name": "bash_code_execution", "input": ["command": "pwd"]],
                ["type": "server_tool_use", "id": "editor", "name": "text_editor_code_execution", "input": ["command": "view", "path": "/tmp/a"]],
                ["type": "server_tool_use", "id": "search", "name": "tool_search_tool_regex", "input": ["query": "weather"]],
                ["type": "tool_search_tool_result", "tool_use_id": "search", "content": [
                    "type": "tool_search_tool_search_result",
                    "tool_references": [["type": "tool", "tool_name": "weather"]]
                ]]
            ]),
            providerID: "anthropic.messages",
            citationDocuments: [],
            toolNameMapping: mapping,
            markCodeExecutionDynamic: true
        )

        #expect(generated.toolCalls.count == 4)
        for call in generated.toolCalls.prefix(3) {
            #expect(call.name == "code_execution")
            #expect(call.dynamic)
        }
        #expect(try decodeJSONBody(Data(generated.toolCalls[0].arguments.utf8))["type"]?.stringValue == "programmatic-tool-call")
        #expect(try decodeJSONBody(Data(generated.toolCalls[1].arguments.utf8))["type"]?.stringValue == "bash_code_execution")
        #expect(try decodeJSONBody(Data(generated.toolCalls[2].arguments.utf8))["type"]?.stringValue == "text_editor_code_execution")
        #expect(generated.toolCalls[3].name == "searchTools")
        #expect(generated.toolResults[0].toolName == "searchTools")

        let bm25Mapping = AIToolNameMapping(
            customToolNameToProviderToolName: ["find": "tool_search_tool_bm25"]
        )
        #expect(anthropicToolSearchToolName(nil, toolNameMapping: bm25Mapping) == "tool_search_tool_bm25")
        #expect(anthropicToolSearchToolName(nil, toolNameMapping: mapping) == "tool_search_tool_regex")
        #expect(anthropicToolSearchToolName(nil) == "tool_search_tool_regex")

        var streaming = AnthropicStreamingToolCalls(
            providerID: "anthropic.messages",
            markCodeExecutionDynamic: true
        )
        for (index, name) in ["bash_code_execution", "text_editor_code_execution"].enumerated() {
            let event: JSONValue = [
                "type": "content_block_start",
                "index": .number(Double(index)),
                "content_block": [
                    "type": "server_tool_use",
                    "id": .string("stream-\(index)"),
                    "name": .string(name),
                    "input": [:]
                ]
            ]
            let parts = streaming.apply(event: event)
            #expect(parts.contains {
                if case let .toolInputStart(_, toolName, _, dynamic, _, _) = $0 {
                    return toolName == "code_execution" && dynamic
                }
                return false
            })
        }
    }
}
