import Foundation
import Testing
@testable import SwiftAISDK

private let anthropicSeptemberResponse = jsonResponse("""
{"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}
""")

private let amazonBedrockSeptemberResponse = jsonResponse("""
{"output":{"message":{"content":[{"text":"ok"}]}},"stopReason":"end_turn","usage":{"inputTokens":1,"outputTokens":1,"totalTokens":2}}
""")

private func amazonBedrockSeptemberCall(
    modelID: String,
    messages: [AIMessage] = [.user("Return JSON")],
    tools: [String: JSONValue] = [:],
    providerOptions: [String: JSONValue] = [:],
    responseFormat: AIResponseFormat? = nil
) async throws -> (body: JSONValue, result: TextGenerationResult) {
    let transport = RecordingTransport(response: amazonBedrockSeptemberResponse)
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        transport: transport
    ))
    let model = try provider.languageModel(modelID)
    let result = try await model.generate(LanguageModelRequest(
        messages: messages,
        responseFormat: responseFormat,
        tools: tools,
        providerOptions: providerOptions
    ))
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    return (body, result)
}

@Test func anthropicMidConversationClearAtAndEffortMatchUpstream() async throws {
    let transport = RecordingTransport(response: anthropicSeptemberResponse)
    let provider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "claude-key",
        transport: transport
    ))
    let model = try provider.languageModel("claude-fable-5")

    _ = try await model.generate(LanguageModelRequest(messages: [
        .user("Draft an answer."),
        .assistant("Draft."),
        AIMessage(
            role: .system,
            content: [.text("")],
            providerMetadata: ["anthropic": [
                "clearAt": "next_user_message",
                "effort": "xhigh"
            ]]
        ),
        .user("Now finalize it.")
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let inlineSystem = try #require(body["messages"]?.arrayValue?.first {
        $0["role"]?.stringValue == "system"
    })
    #expect(inlineSystem["content"] == [])
    #expect(inlineSystem["clear_at"]?.stringValue == "next_user_message")
    #expect(inlineSystem["output_config"]?["effort"]?.stringValue == "xhigh")
    #expect(request.headers["anthropic-beta"]?.contains("mid-conversation-system-clear-at-2026-08-21") == true)
    #expect(request.headers["anthropic-beta"]?.contains("mid-conversation-effort-2026-08-01") == true)
}

@Test func anthropicInitialSystemControlsAreDroppedWithWarningLikeUpstream() async throws {
    let transport = RecordingTransport(response: anthropicSeptemberResponse)
    let provider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "claude-key",
        transport: transport
    ))
    let model = try provider.languageModel("claude-fable-5")

    let result = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(
            role: .system,
            content: [.text("")],
            providerMetadata: ["anthropic": [
                "clearAt": "next_user_message",
                "effort": "high"
            ]]
        ),
        .user("Hello")
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["system"] == nil)
    #expect(request.headers["anthropic-beta"] == nil)
    #expect(result.warnings.contains(AIWarning(
        type: "other",
        message: "clearAt and effort on the initial system message are not supported by Anthropic. These options have been ignored."
    )))
}

@Test func anthropicThinkingUpdatesAndBindingOnlyRequestsMatchUpstream() async throws {
    let updateTransport = RecordingTransport(response: anthropicSeptemberResponse)
    let updateProvider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "claude-key",
        transport: updateTransport
    ))
    let updateModel = try updateProvider.languageModel("claude-opus-4-7")
    _ = try await updateModel.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: ["anthropic": [
            "thinking": ["type": "adaptive", "display": "updates"]
        ]]
    ))

    let updateRequest = try #require(await updateTransport.requests().first)
    let updateBody = try decodeJSONBody(try #require(updateRequest.body))
    #expect(updateBody["thinking"] == ["type": "adaptive", "display": "updates"])
    #expect(updateRequest.headers["anthropic-beta"]?.contains("thinking-display-updates-2026-08-18") == true)

    let bindingTransport = RecordingTransport(response: sseResponse("""
    data: {"type":"message_start","message":{"id":"msg-binding","usage":{"input_tokens":1,"output_tokens":0}}}

    data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":1}}

    data: {"type":"message_stop"}

    """))
    let bindingProvider = try AIProviders.anthropic(settings: ProviderSettings(
        apiKey: "claude-key",
        transport: bindingTransport
    ))
    let bindingModel = try bindingProvider.languageModel("claude-fable-5")
    for try await _ in bindingModel.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: ["anthropic": [
            "thinking": [
                "blockBinding": ["prefixMismatchBehavior": "drop_block"]
            ]
        ]]
    )) {}

    let bindingRequest = try #require(await bindingTransport.streamRequests().first)
    let bindingBody = try decodeJSONBody(try #require(bindingRequest.body))
    #expect(bindingBody["thinking"]?["type"] == nil)
    #expect(bindingBody["thinking"]?["block_binding"]?["prefix_mismatch_behavior"]?.stringValue == "drop_block")
    #expect(bindingRequest.headers["anthropic-beta"]?.contains("thinking-binding-controls-2026-08-01") == true)
}

@Test func anthropicSeptemberBetasPropagateThroughAWSProviders() async throws {
    let request = LanguageModelRequest(
        messages: [
            .user("Draft"),
            .assistant("Drafted"),
            AIMessage(
                role: .system,
                content: [.text("")],
                providerMetadata: ["anthropic": [
                    "clearAt": "next_user_message",
                    "effort": "high"
                ]]
            ),
            .user("Finish")
        ],
        providerOptions: ["anthropic": [
            "thinking": [
                "type": "adaptive",
                "display": "updates",
                "blockBinding": ["prefixMismatchBehavior": "drop_block"]
            ]
        ]]
    )

    let awsTransport = RecordingTransport(response: anthropicSeptemberResponse)
    let awsProvider = try AIProviders.anthropicAWS(settings: AnthropicAWSProviderSettings(
        region: "us-east-1",
        workspaceID: "workspace",
        apiKey: "aws-anthropic-key",
        transport: awsTransport
    ))
    _ = try await awsProvider.languageModel("claude-fable-5").generate(request)

    let awsRequest = try #require(await awsTransport.requests().first)
    let awsBody = try decodeJSONBody(try #require(awsRequest.body))
    #expect(awsBody["thinking"]?["display"]?.stringValue == "updates")
    #expect(awsBody["thinking"]?["block_binding"]?["prefix_mismatch_behavior"]?.stringValue == "drop_block")
    for beta in [
        "mid-conversation-system-clear-at-2026-08-21",
        "mid-conversation-effort-2026-08-01",
        "thinking-display-updates-2026-08-18",
        "thinking-binding-controls-2026-08-01"
    ] {
        #expect(awsRequest.headers["anthropic-beta"]?.contains(beta) == true)
    }

    let bedrockTransport = RecordingTransport(response: anthropicSeptemberResponse)
    let bedrockProvider = try AIProviders.amazonBedrockAnthropic(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        transport: bedrockTransport
    ))
    _ = try await bedrockProvider.languageModel("anthropic.claude-fable-5").generate(request)

    let bedrockRequest = try #require(await bedrockTransport.requests().first)
    let bedrockBody = try decodeJSONBody(try #require(bedrockRequest.body))
    let bedrockBetas = bedrockBody["anthropic_beta"]?.arrayValue?.compactMap(\.stringValue) ?? []
    #expect(bedrockBetas.contains("mid-conversation-system-clear-at-2026-08-21"))
    #expect(bedrockBetas.contains("mid-conversation-effort-2026-08-01"))
    #expect(bedrockBetas.contains("thinking-display-updates-2026-08-18"))
    #expect(bedrockBetas.contains("thinking-binding-controls-2026-08-01"))
}

@Test func anthropicFable51AndDatedVertexClaude4ModelsAreRecognized() {
    let fable = anthropicModelCapabilities("claude-fable-5-1")
    #expect(fable.isKnownModel)
    #expect(fable.maxOutputTokens == 128_000)
    #expect(fable.supportsAdaptiveThinking)

    let sonnet = anthropicModelCapabilities("claude-sonnet-4@20250514")
    #expect(sonnet.isKnownModel)
    #expect(sonnet.maxOutputTokens == 64_000)

    let opus = anthropicModelCapabilities("claude-opus-4@20250514")
    #expect(opus.isKnownModel)
    #expect(opus.maxOutputTokens == 32_000)
}

@Test func amazonBedrockStructuredOutputModesAndCapabilitySplitMatchUpstream() async throws {
    let schema: JSONValue = [
        "type": "object",
        "properties": ["name": ["type": "string"]],
        "required": ["name"]
    ]
    let sonnet46 = "anthropic.claude-sonnet-4-6-20250514-v1:0"
    let haiku45 = "anthropic.claude-haiku-4-5-20251001-v1:0"
    #expect(bedrockSupportsStrictToolSpec(modelID: sonnet46))
    #expect(!bedrockSupportsNativeStructuredOutput(modelID: sonnet46))
    #expect(bedrockSupportsStrictToolSpec(modelID: haiku45))
    #expect(!bedrockSupportsNativeStructuredOutput(modelID: haiku45))

    let automatic = try await amazonBedrockSeptemberCall(
        modelID: sonnet46,
        responseFormat: .json(schema: schema)
    )
    #expect(automatic.body["toolConfig"]?["tools"]?[0]?["toolSpec"]?["name"]?.stringValue == "json")
    #expect(automatic.body["toolConfig"]?["toolChoice"]?["any"] != nil)
    #expect(automatic.body["additionalModelRequestFields"]?["output_config"]?["format"] == nil)

    let forcedNative = try await amazonBedrockSeptemberCall(
        modelID: "anthropic.claude-opus-5-20260701-v1:0",
        providerOptions: ["amazonBedrock": ["structuredOutputMode": "outputFormat"]],
        responseFormat: .json(schema: schema)
    )
    #expect(forcedNative.body["toolConfig"] == nil)
    #expect(forcedNative.body["additionalModelRequestFields"]?["output_config"]?["format"]?["type"]?.stringValue == "json_schema")
}

@Test func amazonBedrockJSONToolModePreservesOutputConfigSiblingsAndPrecedence() async throws {
    let schema: JSONValue = [
        "type": "object",
        "properties": ["name": ["type": "string"]],
        "required": ["name"]
    ]
    let modelID = "anthropic.claude-sonnet-4-5-20250929-v1:0"
    let sibling = try await amazonBedrockSeptemberCall(
        modelID: modelID,
        providerOptions: ["amazonBedrock": [
            "structuredOutputMode": "jsonTool",
            "additionalModelRequestFields": [
                "output_config": [
                    "effort": "medium",
                    "format": ["type": "manually-supplied-format"]
                ]
            ]
        ]],
        responseFormat: .json(schema: schema)
    )
    #expect(sibling.body["additionalModelRequestFields"]?["output_config"] == ["effort": "medium"])
    #expect(sibling.body["toolConfig"]?["tools"]?[0]?["toolSpec"]?["name"]?.stringValue == "json")

    let anthropicAlias = try await amazonBedrockSeptemberCall(
        modelID: modelID,
        providerOptions: ["anthropic": ["structuredOutputMode": "jsonTool"]],
        responseFormat: .json(schema: schema)
    )
    #expect(anthropicAlias.body["toolConfig"]?["tools"]?[0]?["toolSpec"]?["name"]?.stringValue == "json")

    let canonicalWins = try await amazonBedrockSeptemberCall(
        modelID: modelID,
        providerOptions: [
            "amazonBedrock": ["structuredOutputMode": "jsonTool"],
            "anthropic": ["structuredOutputMode": "outputFormat"]
        ],
        responseFormat: .json(schema: schema)
    )
    #expect(canonicalWins.body["toolConfig"]?["tools"]?[0]?["toolSpec"]?["name"]?.stringValue == "json")
    #expect(canonicalWins.body["additionalModelRequestFields"]?["output_config"]?["format"] == nil)
}

@Test func amazonBedrockExtractsNestedCitationTextAndAllowsEmptyCitationContent() async throws {
    let citationTransport = RecordingTransport(response: jsonResponse("""
    {"output":{"message":{"content":[{"citationsContent":{"content":[{"text":"Citation "},{"text":"response"}],"citations":[]}}]}},"stopReason":"end_turn","usage":{"inputTokens":1,"outputTokens":2,"totalTokens":3}}
    """))
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        transport: citationTransport
    ))
    let result = try await provider.languageModel("anthropic.claude-3-haiku-20240307-v1:0")
        .generate(LanguageModelRequest(messages: [.user("Hello")]))
    #expect(result.text == "Citation response")
    #expect(result.content == [.text("Citation "), .text("response")])

    let emptyTransport = RecordingTransport(response: jsonResponse("""
    {"output":{"message":{"content":[{"citationsContent":{"content":null,"citations":[]}}]}},"stopReason":"end_turn","usage":{"inputTokens":1,"outputTokens":0,"totalTokens":1}}
    """))
    let emptyProvider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "bedrock-key",
        transport: emptyTransport
    ))
    let empty = try await emptyProvider.languageModel("anthropic.claude-3-haiku-20240307-v1:0")
        .generate(LanguageModelRequest(messages: [.user("Hello")]))
    #expect(empty.text == "")
    #expect(empty.content.isEmpty)
}

@Test func amazonBedrockSanitizesDocumentNamesLikeUpstream() async throws {
    let filenames = [
        "John's report.txt",
        "invoice #123.txt",
        "a&b.txt",
        "report,2026.txt",
        "résumé.txt",
        "분기보고서.txt",
        "Report -  Final.txt",
        "a\tb.txt",
        "\(String(repeating: "a", count: 201)).txt",
        ".txt",
        "report (final) [v2]_draft.txt"
    ]
    let call = try await amazonBedrockSeptemberCall(
        modelID: "anthropic.claude-3-haiku-20240307-v1:0",
        messages: [AIMessage(
            role: .user,
            content: filenames.map {
                .file(mimeType: "application/pdf", data: Data([0, 1, 2, 3]), filename: $0)
            }
        )]
    )
    let names = call.body["messages"]?[0]?["content"]?.arrayValue?.compactMap {
        $0["document"]?["name"]?.stringValue
    }
    #expect(names == [
        "Johns report",
        "invoice 123",
        "ab",
        "report2026",
        "rsum",
        "document-1",
        "Report - Final",
        "a b",
        String(repeating: "a", count: 200),
        "document-2",
        "report (final) [v2]draft"
    ])
}

@Test func amazonBedrockReplaysProviderExecutedResultsInAlternatingUserTurns() async throws {
    let call = try await amazonBedrockSeptemberCall(
        modelID: "anthropic.claude-sonnet-4-5-20250929-v1:0",
        messages: [
            .user("Add 2 and 2, then read the report."),
            AIMessage(role: .assistant, content: [
                .text("Running tools."),
                .toolCall(AIToolCall(
                    id: "call-1",
                    name: "add",
                    arguments: #"{"a":2,"b":2}"#,
                    providerExecuted: true
                )),
                .toolResult(AIToolResult(
                    toolCallID: "call-1",
                    toolName: "add",
                    result: ["type": "json", "value": ["sum": 4]],
                    providerExecuted: true
                )),
                .toolCall(AIToolCall(
                    id: "call-2",
                    name: "read_report",
                    arguments: #"{}"#,
                    providerExecuted: true
                )),
                .toolResult(AIToolResult(
                    toolCallID: "call-2",
                    toolName: "read_report",
                    result: .null,
                    modelOutput: [
                        "type": "content",
                        "value": [[
                            "type": "file",
                            "data": ["type": "data", "data": "AAECAw=="],
                            "mediaType": "application/pdf",
                            "filename": "John's report.txt"
                        ]]
                    ],
                    providerExecuted: true
                ))
            ]),
            .user("Now use both results.")
        ],
        tools: [
            "add": ["type": "object", "properties": [:]],
            "read_report": ["type": "object", "properties": [:]]
        ]
    )

    let messages = try #require(call.body["messages"]?.arrayValue)
    #expect(messages.map { $0["role"]?.stringValue } == [
        "user", "assistant", "user", "assistant", "user"
    ])
    #expect(messages[1]["content"]?[1]?["toolUse"]?["toolUseId"]?.stringValue == "call-1")
    #expect(messages[2]["content"]?[0]?["toolResult"]?["toolUseId"]?.stringValue == "call-1")
    #expect(messages[3]["content"]?[0]?["toolUse"]?["toolUseId"]?.stringValue == "call-2")
    #expect(messages[4]["content"]?[0]?["toolResult"]?["content"]?[0]?["document"]?["name"]?.stringValue == "Johns report")
    #expect(messages[4]["content"]?[1]?["text"]?.stringValue == "Now use both results.")
}
