import Foundation
import Testing
@testable import SwiftAISDK

private let weeklyProviderGroupABedrockResponse = jsonResponse("""
{"output":{"message":{"content":[{"text":"ok"}]}},"stopReason":"end_turn","usage":{"inputTokens":1,"outputTokens":1,"totalTokens":2}}
""")

private func weeklyProviderGroupABedrockCall(
    modelID: String,
    request: LanguageModelRequest
) async throws -> (body: JSONValue, result: TextGenerationResult) {
    let transport = RecordingTransport(response: weeklyProviderGroupABedrockResponse)
    let provider = try AIProviders.amazonBedrock(settings: AmazonBedrockProviderSettings(
        region: "us-east-1",
        apiKey: "test-key",
        transport: transport
    ))
    let result = try await provider.languageModel(modelID).generate(request)
    let rawRequest = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(rawRequest.body))
    return (body, result)
}

@Test func WeeklyProviderGroupA20260927AlibabaResponseFormatUsesModelAwareFallback() {
    let schema: JSONValue = [
        "type": "object",
        "properties": ["answer": ["type": "string"]]
    ]
    let request = LanguageModelRequest(
        messages: [.user("Answer")],
        responseFormat: .json(schema: schema, name: nil, description: nil)
    )

    var legacyOptions: [String: JSONValue] = [:]
    let legacy = alibabaResolvedResponseFormat(
        request: request,
        modelID: "qwen-max",
        options: &legacyOptions
    )
    #expect(legacy.value?["type"]?.stringValue == "json_object")
    #expect(legacy.schema == schema)
    #expect(legacy.injectJSONInstruction)
    #expect(legacy.warning?.type == "compatibility")

    var currentOptions: [String: JSONValue] = [:]
    let current = alibabaResolvedResponseFormat(
        request: request,
        modelID: "qwen3.8-flash-2026-09-01",
        options: &currentOptions
    )
    #expect(current.value?["type"]?.stringValue == "json_schema")
    #expect(!current.injectJSONInstruction)
    #expect(current.warning == nil)
}

@Test func WeeklyProviderGroupA20260927AnthropicCapabilitiesBetasAndToolsetMatchUpstream() throws {
    let capabilities = anthropicModelCapabilities("us.anthropic.claude-opus-5-5")
    #expect(capabilities.isKnownModel)
    #expect(capabilities.supportsAdaptiveThinking)
    #expect(capabilities.rejectsSamplingParameters)
    #expect(capabilities.rejectsThinkingDisabled)
    #expect(capabilities.rejectsForcedToolUse)

    let safeguards: JSONValue = [[
        "type": "tool_safety",
        "classifierContext": "Only permit read-only operations"
    ]]
    let mappedSafeguards = anthropicSafeguards(safeguards)
    #expect(mappedSafeguards[0]?["classifier_context"]?.stringValue == "Only permit read-only operations")
    #expect(mappedSafeguards[0]?["classifierContext"] == nil)
    let betas = anthropicAutomaticBetas(from: [
        "safeguards": mappedSafeguards,
        "compaction": ["type": "auto"]
    ])
    #expect(betas.contains("dangerous-tool-use-2026-09-03"))
    #expect(betas.contains("compact-2026-09-04"))

    let toolset = AnthropicTools.computerToolset_20260801(configs: [
        "computer": ["enabled": true, "deferLoading": true]
    ])
    let prepared = try anthropicPrepareTools(from: ["computer": toolset])
    let wireTool = try #require(prepared.tools.first)
    #expect(wireTool["type"]?.stringValue == "computer_toolset_20260801")
    #expect(wireTool["name"] == nil)
    #expect(wireTool["configs"]?["computer"]?["enabled"]?.boolValue == true)
    #expect(wireTool["configs"]?["computer"]?["defer_loading"]?.boolValue == true)
}

@Test func WeeklyProviderGroupA20260927AnthropicForcedToolChoiceFallsBackToAuto() throws {
    let tools: [String: JSONValue] = [
        "weather": ["type": "object"],
        "time": ["type": "object"]
    ]
    let prepared = try anthropicPrepareTools(
        from: tools,
        toolChoice: ["type": "tool", "toolName": "weather"],
        disableParallelToolUse: true,
        rejectsForcedToolUse: true
    )
    #expect(prepared.tools.count == 1)
    #expect(prepared.tools.first?["name"]?.stringValue == "weather")
    #expect(prepared.toolChoice?["type"]?.stringValue == "auto")
    #expect(prepared.toolChoice?["disable_parallel_tool_use"]?.boolValue == true)
    #expect(prepared.warnings.first?.feature == "toolChoice")
}

@Test func WeeklyProviderGroupA20260927BedrockMistralIDsUseStableBase62Hash() {
    let examples: [(String, String)] = [
        ("tooluse_bpe71yCfRu2b5i-nKGDr5g", "8eHypBDcw"),
        ("tool-use_123ABC456", "hvVDqPNyj"),
        ("___abc123DEF___", "TnzPqldGU"),
        ("abc", "GRuIyUwcV"),
        ("___---___", "5C589HVqG")
    ]
    for (raw, expected) in examples {
        #expect(bedrockNormalizeToolCallID(raw, modelID: "us.mistral.pixtral-large-2502-v1:0") == expected)
    }
    #expect(bedrockNormalizeToolCallID("abc123XYZ", modelID: "mistral.large") == "abc123XYZ")
    #expect(bedrockNormalizeToolCallID("tool-use_123ABC456", modelID: "amazon.nova-pro") == "tool-use_123ABC456")
}

@Test func WeeklyProviderGroupA20260927BedrockForcedChoiceAndMantleRoutingAreModelAware() throws {
    let tools: [String: JSONValue] = [
        "weather": ["type": "object"],
        "time": ["type": "object"]
    ]
    let prepared = bedrockPrepareTools(
        from: tools,
        toolChoice: ["type": "tool", "toolName": "weather"],
        modelID: "us.anthropic.claude-opus-5-5",
        disableParallelToolUse: true
    )
    let toolConfig = try #require(prepared.toolConfig)
    let configuredTools = toolConfig["tools"]?.arrayValue ?? []
    #expect(configuredTools.count == 1)
    #expect(configuredTools.first?["toolSpec"]?["name"]?.stringValue == "weather")
    #expect(toolConfig["toolChoice"] == nil)
    #expect(prepared.additionalModelRequestFields?["tool_choice"]?["type"]?.stringValue == "auto")
    #expect(prepared.additionalModelRequestFields?["tool_choice"]?["disable_parallel_tool_use"]?.boolValue == true)
    #expect(prepared.warnings.first?.feature == "toolChoice")

    #expect(bedrockMantleUsesOpenAIRoute("openai.gpt-6-sol"))
    #expect(bedrockMantleUsesOpenAIRoute("google.gemma-4-31b"))
    #expect(bedrockMantleUsesOpenAIRoute("xai.grok-4.3"))
    #expect(!bedrockMantleUsesOpenAIRoute("openai.gpt-oss-120b"))
    #expect(!bedrockMantleUsesOpenAIRoute("google.gemma-3-27b-it"))
}

@Test func WeeklyProviderGroupA20260927BedrockSamplingAndReasoningGatesMatchUpstream() async throws {
    let anthropic = try await weeklyProviderGroupABedrockCall(
        modelID: "global.anthropic.claude-opus-4-7",
        request: LanguageModelRequest(
            messages: [.user("Hello")],
            temperature: 0.5,
            topP: 0.7,
            topK: 10
        )
    )
    #expect(anthropic.body["inferenceConfig"] == nil)
    #expect(anthropic.result.warnings.map(\.feature) == ["temperature", "topK", "topP"])

    let openAI = try await weeklyProviderGroupABedrockCall(
        modelID: "us.openai.gpt-5.6-luna",
        request: LanguageModelRequest(
            messages: [.user("Hello")],
            temperature: 2,
            topP: 0.5,
            topK: 5,
            maxOutputTokens: 100,
            stopSequences: ["STOP"]
        )
    )
    #expect(openAI.body["inferenceConfig"] == ["maxTokens": 100, "topK": 5])
    #expect(openAI.result.warnings.map(\.feature) == ["temperature", "topP", "stopSequences"])
    #expect(!openAI.result.warnings.contains { $0.message?.contains("clamped") == true })

    var unknownOptions: [String: JSONValue] = [:]
    var warnings: [AIWarning] = []
    bedrockApplyTopLevelReasoning(
        "high",
        modelID: "us.amazon.nova-micro-v1:0",
        maxOutputTokens: nil,
        providerOptions: &unknownOptions,
        warnings: &warnings
    )
    #expect(unknownOptions["reasoningConfig"] == nil)
    #expect(warnings.first?.feature == "reasoning")

    var novaOptions: [String: JSONValue] = [:]
    warnings = []
    bedrockApplyTopLevelReasoning(
        "high",
        modelID: "us.amazon.nova-2-lite-v1:0",
        maxOutputTokens: nil,
        providerOptions: &novaOptions,
        warnings: &warnings
    )
    #expect(novaOptions["reasoningConfig"]?["type"]?.stringValue == "enabled")
    #expect(novaOptions["reasoningConfig"]?["maxReasoningEffort"]?.stringValue == "high")
}

@Test func WeeklyProviderGroupA20260927BedrockOpus55UsesJSONInstructionInsteadOfForcedTool() async throws {
    let schema: JSONValue = [
        "type": "object",
        "properties": ["answer": ["type": "string"]],
        "required": ["answer"]
    ]
    let call = try await weeklyProviderGroupABedrockCall(
        modelID: "us.anthropic.claude-opus-5-5",
        request: LanguageModelRequest(
            messages: [.user("Return an answer")],
            responseFormat: .json(schema: schema, name: nil, description: nil)
        )
    )
    #expect(call.body["toolConfig"] == nil)
    #expect(call.body["additionalModelRequestFields"]?["output_config"] == nil)
    let systemText = call.body["system"]?[0]?["text"]?.stringValue ?? ""
    #expect(systemText.contains("JSON schema:"))
    #expect(systemText.contains("You MUST answer with only a JSON object"))
}

@Test func WeeklyProviderGroupA20260927GoogleEmbeddingOptionsSlicePreservesNullEntries() async throws {
    let config = ModelHTTPConfig(
        providerID: "google.generative-ai",
        baseURL: "https://example.test/v1beta",
        headers: [:],
        transport: RecordingTransport(response: jsonResponse("{}"))
    )
    let model = GoogleEmbeddingModel(modelID: "gemini-embedding-001", config: config)
    let transformer = try #require(model.providerOptionsTransformer)
    let transformed = try await transformer(AIEmbeddingProviderOptionsTransformContext(
        providerOptions: [
            "google": [
                "content": [
                    ["parts": [["text": "zero"]]],
                    .null,
                    ["parts": [["text": "two"]]],
                    .null
                ],
                "taskType": "RETRIEVAL_DOCUMENT"
            ],
            "other": ["preserved": true]
        ],
        values: ["zero", "one", "two", "three"],
        startIndex: 1,
        endIndex: 3
    ))
    #expect(transformed["google"]?["content"]?.arrayValue == [.null, ["parts": [["text": "two"]]]])
    #expect(transformed["google"]?["taskType"]?.stringValue == "RETRIEVAL_DOCUMENT")
    #expect(transformed["other"]?["preserved"]?.boolValue == true)
}

@Test func WeeklyProviderGroupA20260927GoogleToolResultsAndStructuredSpeechMatchUpstream() throws {
    let referenced: JSONValue = [
        "value": ["$ref": "#/definitions/answer"],
        "definitions": ["answer": ["type": "string"]]
    ]
    let serialized = googleSerializeFunctionResponseContent(referenced)
    #expect(serialized.stringValue?.contains("$ref") == true)

    let cloudPart: JSONValue = [
        "type": "file",
        "mediaType": "application/pdf",
        "data": ["type": "url", "url": "gs://bucket/report.pdf"]
    ]
    let cloudFileData = try #require(googleCloudStorageFileDataFromToolContent(cloudPart))
    #expect(cloudFileData["fileData"]?["fileUri"]?.stringValue == "gs://bucket/report.pdf")

    let prepared = try googlePrepareSpeechRequest(
        SpeechRequest(
            text: "Hello",
            format: "mulaw",
            instructions: "warm"
        ),
        modelID: "gemini-3.8-pro-preview-tts",
        options: ["speechMetadata": ["style": "calm"]]
    )
    #expect(prepared.usesStructuredSpeech)
    #expect(prepared.outputFormat == "AUDIO_MULAW")
    #expect(prepared.body["contents"]?[0]?["parts"]?[0]?["speechMetadata"]?["style"]?.stringValue == "calm")
    #expect(prepared.body["generationConfig"]?["responseFormat"]?["audio"]?["mimeType"]?.stringValue == "AUDIO_MULAW")
}
