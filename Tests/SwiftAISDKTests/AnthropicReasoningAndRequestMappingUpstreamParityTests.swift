import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicTopLevelReasoningMapsAdaptiveThinkingLikeUpstream() async throws {
    let providerDefault = try await anthropicGeneratedBody(modelID: "claude-sonnet-4-6", reasoning: "provider-default")
    #expect(providerDefault.body["thinking"] == nil)
    #expect(providerDefault.body["output_config"] == nil)
    #expect(providerDefault.warnings.isEmpty)

    let none = try await anthropicGeneratedBody(modelID: "claude-sonnet-4-6", reasoning: "none")
    #expect(none.body["thinking"] == nil)
    #expect(none.body["output_config"] == nil)
    #expect(none.warnings.isEmpty)

    for (reasoning, effort) in [("low", "low"), ("medium", "medium"), ("high", "high")] {
        let result = try await anthropicGeneratedBody(modelID: "claude-sonnet-4-6", reasoning: reasoning)
        #expect(result.body["thinking"] == ["type": "adaptive"])
        #expect(result.body["output_config"]?["effort"]?.stringValue == effort)
        #expect(result.warnings.isEmpty)
    }

    let xhigh = try await anthropicGeneratedBody(modelID: "claude-sonnet-4-6", reasoning: "xhigh")
    #expect(xhigh.body["thinking"] == ["type": "adaptive"])
    #expect(xhigh.body["output_config"]?["effort"]?.stringValue == "max")
    #expect(xhigh.warnings.contains(AIWarning(
        type: "compatibility",
        feature: "reasoning",
        message: "reasoning \"xhigh\" is not directly supported by this model. mapped to effort \"max\"."
    )))

    let minimal = try await anthropicGeneratedBody(modelID: "claude-opus-4-6", reasoning: "minimal")
    #expect(minimal.body["thinking"] == ["type": "adaptive"])
    #expect(minimal.body["output_config"]?["effort"]?.stringValue == "low")
    #expect(minimal.warnings.contains(AIWarning(
        type: "compatibility",
        feature: "reasoning",
        message: "reasoning \"minimal\" is not directly supported by this model. mapped to effort \"low\"."
    )))
}

@Test func anthropicTopLevelReasoningMapsBudgetThinkingLikeUpstream() async throws {
    let providerDefault = try await anthropicGeneratedBody(modelID: "claude-sonnet-4-5", reasoning: "provider-default")
    #expect(providerDefault.body["thinking"] == nil)
    #expect(providerDefault.warnings.isEmpty)

    let none = try await anthropicGeneratedBody(modelID: "claude-sonnet-4-5", reasoning: "none")
    #expect(none.body["thinking"] == nil)
    #expect(none.warnings.isEmpty)

    for (reasoning, budget) in [
        ("minimal", 1_280),
        ("low", 6_400),
        ("medium", 19_200),
        ("high", 38_400),
        ("xhigh", 57_600)
    ] {
        let result = try await anthropicGeneratedBody(modelID: "claude-sonnet-4-5", reasoning: reasoning)
        #expect(result.body["thinking"]?["type"]?.stringValue == "enabled")
        #expect(result.body["thinking"]?["budget_tokens"]?.intValue == budget)
    }

    let clamped = try await anthropicGeneratedBody(modelID: "claude-3-haiku-20240307", reasoning: "minimal")
    #expect(clamped.body["thinking"]?["type"]?.stringValue == "enabled")
    #expect(clamped.body["thinking"]?["budget_tokens"]?.intValue == 1_024)

    let adjusted = try await anthropicGeneratedBody(modelID: "claude-sonnet-4-5", reasoning: "low", maxOutputTokens: 10_000)
    #expect(adjusted.body["max_tokens"]?.intValue == 16_400)
    #expect(adjusted.body["thinking"]?["budget_tokens"]?.intValue == 6_400)
}

@Test func anthropicTopLevelReasoningStripsSamplingWhenThinkingLikeUpstream() async throws {
    let adaptive = try await anthropicGeneratedBody(
        modelID: "claude-sonnet-4-6",
        reasoning: "high",
        temperature: 0.5,
        topP: 0.7,
        topK: 10
    )
    #expect(adaptive.body["temperature"] == nil)
    #expect(adaptive.body["top_p"] == nil)
    #expect(adaptive.body["top_k"] == nil)
    #expect(adaptive.warnings.contains(AIWarning(type: "unsupported", feature: "temperature", message: "temperature is not supported when thinking is enabled")))
    #expect(adaptive.warnings.contains(AIWarning(type: "unsupported", feature: "topK", message: "topK is not supported when thinking is enabled")))
    #expect(adaptive.warnings.contains(AIWarning(type: "unsupported", feature: "topP", message: "topP is not supported when thinking is enabled")))

    let budget = try await anthropicGeneratedBody(
        modelID: "claude-sonnet-4-5",
        reasoning: "medium",
        temperature: 0.5,
        topP: 0.7,
        topK: 10
    )
    #expect(budget.body["temperature"] == nil)
    #expect(budget.body["top_p"] == nil)
    #expect(budget.body["top_k"] == nil)
    #expect(budget.warnings.contains(AIWarning(type: "unsupported", feature: "temperature", message: "temperature is not supported when thinking is enabled")))
}

@Test func anthropicTopLevelReasoningProviderOptionsPrecedenceLikeUpstream() async throws {
    let disabled = try await anthropicGeneratedBody(
        modelID: "claude-sonnet-4-6",
        reasoning: "high",
        providerOptions: ["anthropic": ["thinking": ["type": "disabled"]]]
    )
    #expect(disabled.body["thinking"] == nil)
    #expect(disabled.body["output_config"] == nil)

    let effort = try await anthropicGeneratedBody(
        modelID: "claude-sonnet-4-6",
        reasoning: "high",
        providerOptions: ["anthropic": ["effort": "low"]]
    )
    #expect(effort.body["thinking"] == nil)
    #expect(effort.body["output_config"]?["effort"]?.stringValue == "low")

    let thinking = try await anthropicGeneratedBody(
        modelID: "claude-sonnet-4-5",
        reasoning: "xhigh",
        providerOptions: ["anthropic": ["thinking": ["type": "enabled", "budgetTokens": 5_000]]]
    )
    #expect(thinking.body["thinking"]?["type"]?.stringValue == "enabled")
    #expect(thinking.body["thinking"]?["budget_tokens"]?.intValue == 5_000)
}

@Test func anthropicOpus47RejectsSamplingParametersLikeUpstream() async throws {
    let result = try await anthropicGeneratedBody(
        modelID: "claude-opus-4-7",
        temperature: 0.7,
        topP: 0.9,
        topK: 40
    )

    #expect(result.body["temperature"] == nil)
    #expect(result.body["top_p"] == nil)
    #expect(result.body["top_k"] == nil)
    #expect(result.warnings.contains(AIWarning(
        type: "unsupported",
        feature: "temperature",
        message: "temperature is not supported by claude-opus-4-7 and will be ignored"
    )))
    #expect(result.warnings.contains(AIWarning(
        type: "unsupported",
        feature: "topK",
        message: "topK is not supported by claude-opus-4-7 and will be ignored"
    )))
    #expect(result.warnings.contains(AIWarning(
        type: "unsupported",
        feature: "topP",
        message: "topP is not supported by claude-opus-4-7 and will be ignored"
    )))
}

@Test func anthropicOpus47XhighAndAdaptiveDisplayMapLikeUpstream() async throws {
    let xhigh = try await anthropicGeneratedBody(modelID: "claude-opus-4-7", reasoning: "xhigh")
    #expect(xhigh.body["thinking"] == ["type": "adaptive"])
    #expect(xhigh.body["output_config"]?["effort"]?.stringValue == "xhigh")

    let opus46 = try await anthropicGeneratedBody(modelID: "claude-opus-4-6", reasoning: "xhigh")
    #expect(opus46.body["thinking"] == ["type": "adaptive"])
    #expect(opus46.body["output_config"]?["effort"]?.stringValue == "max")

    let taskBudget = try await anthropicGeneratedBody(
        modelID: "claude-opus-4-7",
        providerOptions: ["anthropic": ["taskBudget": ["type": "tokens", "total": 400_000]]]
    )
    #expect(taskBudget.body["output_config"]?["task_budget"] == ["type": "tokens", "total": 400_000])
    #expect(taskBudget.headers["anthropic-beta"]?.contains("task-budgets-2026-03-13") == true)

    let remainingTaskBudget = try await anthropicGeneratedBody(
        modelID: "claude-opus-4-7",
        providerOptions: ["anthropic": ["taskBudget": ["type": "tokens", "total": 400_000, "remaining": 215_000]]]
    )
    #expect(remainingTaskBudget.body["output_config"]?["task_budget"] == [
        "type": "tokens",
        "total": 400_000,
        "remaining": 215_000
    ])

    let display = try await anthropicGeneratedBody(
        modelID: "claude-opus-4-7",
        providerOptions: ["anthropic": ["thinking": ["type": "adaptive", "display": "summarized"]]]
    )
    #expect(display.body["thinking"] == ["type": "adaptive", "display": "summarized"])
}

@Test func anthropicDefaultMaxTokensUsesModelCapabilityLikeUpstream() async throws {
    let haiku = try await anthropicGeneratedBody(modelID: "claude-3-haiku-20240307")
    #expect(haiku.body["max_tokens"]?.intValue == 4_096)
    #expect(haiku.warnings.isEmpty)

    let sonnet = try await anthropicGeneratedBody(modelID: "claude-sonnet-4-5")
    #expect(sonnet.body["max_tokens"]?.intValue == 64_000)
    #expect(sonnet.warnings.isEmpty)
}

@Test func anthropicLimitsMaxOutputTokensToKnownModelMaxLikeUpstream() async throws {
    let result = try await anthropicGeneratedBody(
        modelID: "claude-haiku-4-5",
        maxOutputTokens: 999_999
    )

    #expect(result.body["max_tokens"]?.intValue == 64_000)
    #expect(result.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "maxOutputTokens",
            message: "999999 (maxOutputTokens + thinkingBudget) is greater than claude-haiku-4-5 64000 max output tokens. The max output tokens have been limited to 64000."
        )
    ])
}

@Test func anthropicDoesNotLimitMaxOutputTokensForUnknownModelsLikeUpstream() async throws {
    let result = try await anthropicGeneratedBody(
        modelID: "future-model",
        maxOutputTokens: 123_456
    )

    #expect(result.body["max_tokens"]?.intValue == 123_456)
    #expect(result.warnings.isEmpty)
}

@Test func anthropicSendsModelIDSettingsAndFrequencyPenaltyWarningLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-haiku-20240307")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        temperature: 0.5,
        topK: 1,
        frequencyPenalty: 0.15,
        maxOutputTokens: 100,
        stopSequences: ["abc", "def"]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "claude-3-haiku-20240307")
    #expect(body["messages"]?[0]?["role"]?.stringValue == "user")
    #expect(body["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
    #expect(body["max_tokens"]?.intValue == 100)
    #expect(body["temperature"]?.doubleValue == 0.5)
    #expect(body["top_k"]?.intValue == 1)
    #expect(body["stop_sequences"] == ["abc", "def"])
    #expect(body["frequency_penalty"] == nil)
    #expect(result.warnings == [AIWarning(type: "unsupported", feature: "frequencyPenalty")])
}

@Test func anthropicTemperatureAndTopPMutualExclusivityLikeUpstream() async throws {
    let both = try await anthropicGeneratedBody(
        modelID: "claude-3-haiku-20240307",
        temperature: 0.7,
        topP: 0.9
    )
    #expect(both.body["temperature"]?.doubleValue == 0.7)
    #expect(both.body["top_p"] == nil)
    #expect(both.warnings.contains(AIWarning(
        type: "unsupported",
        feature: "topP",
        message: "topP is not supported when temperature is set. topP is ignored."
    )))

    let temperatureOnly = try await anthropicGeneratedBody(
        modelID: "claude-3-haiku-20240307",
        temperature: 0.7
    )
    #expect(temperatureOnly.body["temperature"]?.doubleValue == 0.7)
    #expect(temperatureOnly.body["top_p"] == nil)

    let topPOnly = try await anthropicGeneratedBody(
        modelID: "claude-3-haiku-20240307",
        topP: 0.9
    )
    #expect(topPOnly.body["temperature"] == nil)
    #expect(topPOnly.body["top_p"]?.doubleValue == 0.9)

    let neither = try await anthropicGeneratedBody(modelID: "claude-3-haiku-20240307")
    #expect(neither.body["temperature"] == nil)
    #expect(neither.body["top_p"] == nil)

    let nonAnthropic = try await anthropicGeneratedBody(
        modelID: "MiniMax-M2.7",
        temperature: 0.7,
        topP: 0.9
    )
    #expect(nonAnthropic.body["temperature"]?.doubleValue == 0.7)
    #expect(nonAnthropic.body["top_p"]?.doubleValue == 0.9)
    #expect(!nonAnthropic.warnings.contains { $0.feature == "topP" })
}

@Test func anthropicTemperatureClampingLikeUpstream() async throws {
    let aboveRange = try await anthropicGeneratedBody(
        modelID: "claude-3-haiku-20240307",
        temperature: 1.5
    )
    #expect(aboveRange.body["temperature"]?.doubleValue == 1)
    #expect(aboveRange.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "temperature",
            message: "1.5 exceeds anthropic maximum of 1.0. clamped to 1.0"
        )
    ])

    let belowRange = try await anthropicGeneratedBody(
        modelID: "claude-3-haiku-20240307",
        temperature: -0.5
    )
    #expect(belowRange.body["temperature"]?.doubleValue == 0)
    #expect(belowRange.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "temperature",
            message: "-0.5 is below anthropic minimum of 0. clamped to 0"
        )
    ])

    let valid = try await anthropicGeneratedBody(
        modelID: "claude-3-haiku-20240307",
        temperature: 0.7
    )
    #expect(valid.body["temperature"]?.doubleValue == 0.7)
    #expect(valid.warnings.isEmpty)
}

@Test func anthropicProviderOptionsRequestMappingLikeUpstream() async throws {
    let effort = try await anthropicGeneratedBody(
        modelID: "claude-3-haiku-20240307",
        providerOptions: ["anthropic": ["effort": "medium"]]
    )
    #expect(effort.body["output_config"]?["effort"]?.stringValue == "medium")
    #expect(effort.warnings.isEmpty)

    let fastSpeed = try await anthropicGeneratedBody(
        modelID: "claude-3-haiku-20240307",
        providerOptions: ["anthropic": ["speed": "fast"]]
    )
    #expect(fastSpeed.body["speed"]?.stringValue == "fast")
    #expect(fastSpeed.headers["anthropic-beta"]?.contains("fast-mode-2026-02-01") == true)
    #expect(fastSpeed.warnings.isEmpty)

    let standardSpeed = try await anthropicGeneratedBody(
        modelID: "claude-3-haiku-20240307",
        providerOptions: ["anthropic": ["speed": "standard"]]
    )
    #expect(standardSpeed.body["speed"]?.stringValue == "standard")
    #expect(standardSpeed.headers["anthropic-beta"]?.contains("fast-mode-2026-02-01") != true)
    #expect(standardSpeed.warnings.isEmpty)

    let inferenceGeo = try await anthropicGeneratedBody(
        modelID: "claude-3-haiku-20240307",
        providerOptions: ["anthropic": ["inferenceGeo": "us"]]
    )
    #expect(inferenceGeo.body["inference_geo"]?.stringValue == "us")
    #expect(inferenceGeo.warnings.isEmpty)

    let cacheControl = try await anthropicGeneratedBody(
        modelID: "claude-3-haiku-20240307",
        providerOptions: ["anthropic": ["cacheControl": ["type": "ephemeral"]]]
    )
    #expect(cacheControl.body["cache_control"] == ["type": "ephemeral"])
    #expect(cacheControl.warnings.isEmpty)

    let cacheControlWithTTL = try await anthropicGeneratedBody(
        modelID: "claude-3-haiku-20240307",
        providerOptions: ["anthropic": ["cacheControl": ["type": "ephemeral", "ttl": "1h"]]]
    )
    #expect(cacheControlWithTTL.body["cache_control"] == ["type": "ephemeral", "ttl": "1h"])
    #expect(cacheControlWithTTL.warnings.isEmpty)

    let metadata = try await anthropicGeneratedBody(
        modelID: "claude-3-haiku-20240307",
        providerOptions: ["anthropic": ["metadata": ["userId": "test-user-id"]]]
    )
    #expect(metadata.body["metadata"]?["user_id"]?.stringValue == "test-user-id")
    #expect(metadata.warnings.isEmpty)
}

@Test func anthropicContextManagementRequestMappingLikeUpstream() async throws {
    let clearToolUses = try await anthropicGeneratedBody(
        modelID: "claude-3-haiku-20240307",
        providerOptions: [
            "anthropic": [
                "contextManagement": [
                    "edits": [
                        ["type": "clear_tool_uses_20250919"]
                    ]
                ]
            ]
        ]
    )
    #expect(clearToolUses.body["context_management"]?["edits"]?[0]?["type"]?.stringValue == "clear_tool_uses_20250919")
    #expect(clearToolUses.headers["anthropic-beta"]?.contains("context-management-2025-06-27") == true)
    #expect(clearToolUses.warnings.isEmpty)

    let clearToolUsesAllOptions = try await anthropicGeneratedBody(
        modelID: "claude-3-haiku-20240307",
        providerOptions: [
            "anthropic": [
                "contextManagement": [
                    "edits": [
                        [
                            "type": "clear_tool_uses_20250919",
                            "trigger": ["type": "input_tokens", "value": 50_000],
                            "keep": ["type": "tool_uses", "value": 5],
                            "clearAtLeast": ["type": "input_tokens", "value": 10_000],
                            "clearToolInputs": true,
                            "excludeTools": ["important_tool"]
                        ]
                    ]
                ]
            ]
        ]
    )
    let clearEdit = try #require(clearToolUsesAllOptions.body["context_management"]?["edits"]?[0])
    #expect(clearEdit["trigger"]?["value"]?.intValue == 50_000)
    #expect(clearEdit["keep"]?["value"]?.intValue == 5)
    #expect(clearEdit["clear_at_least"]?["value"]?.intValue == 10_000)
    #expect(clearEdit["clear_tool_inputs"]?.boolValue == true)
    #expect(clearEdit["exclude_tools"]?[0]?.stringValue == "important_tool")

    let clearThinking = try await anthropicGeneratedBody(
        modelID: "claude-3-haiku-20240307",
        providerOptions: [
            "anthropic": [
                "contextManagement": [
                    "edits": [
                        [
                            "type": "clear_thinking_20251015",
                            "keep": ["type": "thinking_turns", "value": 3]
                        ]
                    ]
                ]
            ]
        ]
    )
    let thinkingEdit = try #require(clearThinking.body["context_management"]?["edits"]?[0])
    #expect(thinkingEdit["type"]?.stringValue == "clear_thinking_20251015")
    #expect(thinkingEdit["keep"]?["type"]?.stringValue == "thinking_turns")
    #expect(thinkingEdit["keep"]?["value"]?.intValue == 3)

    let multipleEdits = try await anthropicGeneratedBody(
        modelID: "claude-3-haiku-20240307",
        providerOptions: [
            "anthropic": [
                "contextManagement": [
                    "edits": [
                        ["type": "clear_tool_uses_20250919"],
                        ["type": "clear_thinking_20251015"]
                    ]
                ]
            ]
        ]
    )
    #expect(multipleEdits.body["context_management"]?["edits"]?[0]?["type"]?.stringValue == "clear_tool_uses_20250919")
    #expect(multipleEdits.body["context_management"]?["edits"]?[1]?["type"]?.stringValue == "clear_thinking_20251015")

    let compact = try await anthropicGeneratedBody(
        modelID: "claude-3-haiku-20240307",
        providerOptions: [
            "anthropic": [
                "contextManagement": [
                    "edits": [
                        [
                            "type": "compact_20260112",
                            "trigger": ["type": "input_tokens", "value": 50_000],
                            "pauseAfterCompaction": true,
                            "instructions": "Summarize the conversation concisely."
                        ]
                    ]
                ]
            ]
        ]
    )
    let compactEdit = try #require(compact.body["context_management"]?["edits"]?[0])
    #expect(compactEdit["type"]?.stringValue == "compact_20260112")
    #expect(compactEdit["trigger"]?["value"]?.intValue == 50_000)
    #expect(compactEdit["pause_after_compaction"]?.boolValue == true)
    #expect(compactEdit["instructions"]?.stringValue == "Summarize the conversation concisely.")
    #expect(compact.headers["anthropic-beta"]?.contains("context-management-2025-06-27") == true)
    #expect(compact.headers["anthropic-beta"]?.contains("compact-2026-01-12") == true)
    #expect(compact.warnings.isEmpty)
}

@Test func anthropicStructuredOutputRequestModesLikeUpstream() async throws {
    let schema: JSONValue = [
        "$schema": "http://json-schema.org/draft-07/schema#",
        "type": "object",
        "properties": ["name": ["type": "string"]],
        "required": ["name"],
        "additionalProperties": false
    ]

    let unsupported = try await anthropicGeneratedBody(
        modelID: "claude-3-haiku-20240307",
        responseFormat: .json(schema: schema)
    )
    #expect(unsupported.body["output_config"]?["format"] == nil)
    #expect(unsupported.body["tools"]?[0]?["name"]?.stringValue == "json")
    #expect(unsupported.body["tools"]?[0]?["description"]?.stringValue == "Respond with a JSON object.")
    #expect(unsupported.body["tools"]?[0]?["input_schema"] == schema)
    #expect(unsupported.body["tool_choice"]?["type"]?.stringValue == "any")
    #expect(unsupported.body["tool_choice"]?["disable_parallel_tool_use"]?.boolValue == true)
    #expect(unsupported.headers["anthropic-beta"]?.contains("structured-outputs-2025-11-13") != true)

    let supported = try await anthropicGeneratedBody(
        modelID: "claude-sonnet-4-5",
        responseFormat: .json(schema: schema)
    )
    #expect(supported.body["tools"] == nil)
    #expect(supported.body["tool_choice"] == nil)
    #expect(supported.body["output_config"]?["format"]?["type"]?.stringValue == "json_schema")
    #expect(supported.body["output_config"]?["format"]?["schema"]?["properties"]?["name"]?["type"]?.stringValue == "string")
    #expect(supported.headers["anthropic-beta"]?.contains("structured-outputs-2025-11-13") != true)

    let supportedToolMode = try await anthropicGeneratedBody(
        modelID: "claude-sonnet-4-5",
        responseFormat: .json(schema: schema),
        providerOptions: ["anthropic": ["structuredOutputMode": "jsonTool"]]
    )
    #expect(supportedToolMode.body["output_config"]?["format"] == nil)
    #expect(supportedToolMode.body["tools"]?[0]?["name"]?.stringValue == "json")
    #expect(supportedToolMode.headers["anthropic-beta"]?.contains("structured-outputs-2025-11-13") != true)

    let forcedOutputFormat = try await anthropicGeneratedBody(
        modelID: "claude-unknown",
        responseFormat: .json(schema: schema),
        providerOptions: ["anthropic": ["structuredOutputMode": "outputFormat"]]
    )
    #expect(forcedOutputFormat.body["tools"] == nil)
    #expect(forcedOutputFormat.body["output_config"]?["format"]?["type"]?.stringValue == "json_schema")

    let otherTool = try await anthropicGeneratedBody(
        modelID: "claude-3-haiku-20240307",
        responseFormat: .json(schema: [
            "type": "object",
            "properties": ["weather": ["type": "string"], "temperature": ["type": "number"]],
            "required": ["weather", "temperature"],
            "additionalProperties": false
        ]),
        tools: [
            "get-weather": [
                "description": "Get the weather in a location",
                "type": "object",
                "properties": ["location": ["type": "string"]],
                "required": ["location"],
                "additionalProperties": false
            ]
        ]
    )
    #expect(otherTool.body["tools"]?.arrayValue?.count == 2)
    #expect(otherTool.body["tools"]?[0]?["name"]?.stringValue == "get-weather")
    #expect(otherTool.body["tools"]?[1]?["name"]?.stringValue == "json")
    #expect(otherTool.body["tool_choice"]?["type"]?.stringValue == "any")
}

