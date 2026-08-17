import Foundation
import Testing
@testable import SwiftAISDK

@Test func xAIResponsesImageGenerationGrok46AndPriorityTierMatchUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"resp-priority","status":"completed","service_tier":"default","output_text":"done"}"#),
        jsonResponse(#"{"id":"resp-xhigh","status":"completed","output_text":"done"}"#),
        jsonResponse(#"{"id":"resp-high","status":"completed","output_text":"done"}"#)
    ])
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))

    let priorityResult = try await provider.responses("grok-4.6").generate(LanguageModelRequest(
        messages: [.user("Generate an image")],
        tools: ["create_image": XAITools.imageGeneration(action: "edit")],
        providerOptions: [
            "xai": [
                "reasoningEffort": "xhigh",
                "serviceTier": "priority"
            ]
        ]
    ))
    _ = try await provider.responses("grok-4.6").generate(LanguageModelRequest(messages: [.user("Think")], reasoning: "xhigh"))
    _ = try await provider.responses("grok-4.5").generate(LanguageModelRequest(messages: [.user("Think")], reasoning: "xhigh"))

    #expect(priorityResult.providerMetadata["xai"]?["serviceTier"]?.stringValue == "default")
    let requests = await transport.requests()
    let priorityBody = try decodeJSONBody(try #require(requests[0].body))
    #expect(priorityBody["reasoning"]?["effort"]?.stringValue == "xhigh")
    #expect(priorityBody["service_tier"]?.stringValue == "priority")
    #expect(priorityBody["serviceTier"] == nil)
    let imageTool = try #require(priorityBody["tools"]?.arrayValue?.first)
    #expect(imageTool["type"]?.stringValue == "image_generation")
    #expect(imageTool["action"]?.stringValue == "edit")
    let grok46Body = try decodeJSONBody(try #require(requests[1].body))
    #expect(grok46Body["reasoning"]?["effort"]?.stringValue == "xhigh")
    let otherModelBody = try decodeJSONBody(try #require(requests[2].body))
    #expect(otherModelBody["reasoning"]?["effort"]?.stringValue == "high")
}

@Test func xAIResponsesImageGenerationAndPriorityOptionsValidateLikeUpstream() async throws {
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: RecordingTransport(responses: [])))
    let model = try provider.responses("grok-4.6")

    await #expect(throws: AIError.invalidArgument(
        argument: "tools.create_image.action",
        message: "xAI image generation action must be auto, generate, or edit."
    )) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Generate an image")],
            tools: ["create_image": XAITools.imageGeneration(action: "transform")]
        ))
    }

    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.xai.serviceTier",
        message: "xAI serviceTier must be default or priority."
    )) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["xai": ["serviceTier": "flex"]]
        ))
    }

    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.xai.reasoningSummary",
        message: "xAI reasoningSummary must be auto, concise, or detailed."
    )) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: ["xai": ["reasoningSummary": "verbose"]]
        ))
    }
}

@Test func xAIResponsesReasoningGateAndSummaryObjectMatchUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"resp-unsupported","status":"completed","output_text":"done"}"#),
        jsonResponse(#"{"id":"resp-auto","status":"completed","output_text":"done"}"#),
        jsonResponse(#"{"id":"resp-concise","status":"completed","output_text":"done"}"#),
        jsonResponse(#"{"id":"resp-detailed","status":"completed","output_text":"done"}"#)
    ])
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))

    let unsupportedResult = try await provider.responses("grok-4.20-reasoning").generate(LanguageModelRequest(
        messages: [.user("Think")],
        reasoning: "none"
    ))
    #expect(unsupportedResult.warnings.contains(AIWarning(
        type: "unsupported",
        feature: "reasoning",
        message: #"reasoning "none" is not supported by this model."#
    )))

    for summary in ["auto", "concise", "detailed"] {
        _ = try await provider.responses("grok-4.20-reasoning").generate(LanguageModelRequest(
            messages: [.user("Think")],
            providerOptions: [
                "xai": [
                    "reasoningEffort": "high",
                    "reasoningSummary": .string(summary)
                ]
            ]
        ))
    }

    let requests = await transport.requests()
    let unsupportedBody = try decodeJSONBody(try #require(requests[0].body))
    #expect(unsupportedBody["reasoning"] == nil)

    for (index, summary) in ["auto", "concise", "detailed"].enumerated() {
        let body = try decodeJSONBody(try #require(requests[index + 1].body))
        #expect(body["reasoning"] == [
            "effort": "high",
            "summary": .string(summary)
        ])
        #expect(body["reasoningEffort"] == nil)
        #expect(body["reasoningSummary"] == nil)
    }
}

@Test func xAIResponsesImageGenerationParsesPromptFailureAndCustomAliasLikeUpstream() throws {
    let aliases = openAIResponsesProviderToolNameAliases(from: [
        "create_image": [
            "type": "provider",
            "id": "xai.image_generation",
            "name": "create_image",
            "args": ["action": "generate"]
        ]
    ])
    #expect(aliases["image_generation"] == "create_image")

    let success = try #require(openAIResponsesToolResult(
        from: [
            "type": "image_generation_call",
            "id": "ig-success",
            "status": "completed",
            "prompt": "An origami fox",
            "result": "base64-image"
        ],
        providerID: "xai.responses",
        toolNameAliases: aliases
    ))
    #expect(success.toolCallID == "ig-success")
    #expect(success.toolName == "create_image")
    #expect(success.result == ["result": "base64-image", "prompt": "An origami fox"])
    #expect(success.isError == false)

    let failure = try #require(openAIResponsesToolResult(
        from: [
            "type": "image_generation_call",
            "id": "ig-failure",
            "status": "failed"
        ],
        providerID: "xai.responses",
        toolNameAliases: aliases
    ))
    #expect(failure.toolName == "create_image")
    #expect(failure.result == "Image generation failed (status: failed).")
    #expect(failure.isError)
}

@Test func xAIResponsesImageGenerationProgressEmitsOneLifecycleAndResultLikeUpstream() throws {
    var tracker = OpenAIResponsesStreamingToolCalls(
        providerID: "xai.responses",
        toolNameAliases: ["image_generation": "create_image"]
    )
    var parts: [LanguageStreamPart] = []
    for type in [
        "response.image_generation_call.in_progress",
        "response.image_generation_call.generating",
        "response.image_generation_call.completed"
    ] {
        parts.append(contentsOf: tracker.apply(event: [
            "type": .string(type),
            "item_id": "ig-progress",
            "output_index": 0
        ]))
    }
    parts.append(contentsOf: tracker.apply(event: [
        "type": "response.output_item.done",
        "output_index": 0,
        "item": [
            "type": "image_generation_call",
            "id": "ig-progress",
            "status": "completed",
            "prompt": "An origami fox",
            "result": "base64-image"
        ]
    ]))

    #expect(parts.count == 5)
    #expect(parts.filter {
        if case .toolInputStart = $0 { return true }
        return false
    }.count == 1)
    #expect(parts.filter {
        if case .toolCall = $0 { return true }
        return false
    }.count == 1)
    #expect(parts.contains(.toolInputDelta(id: "ig-progress", delta: "{}")))
    guard case let .toolResult(result) = parts.last else {
        Issue.record("Expected final image generation tool result")
        return
    }
    #expect(result.toolName == "create_image")
    #expect(result.result == ["result": "base64-image", "prompt": "An origami fox"])
}

@Test func xAIResponsesImageGenerationDoneOnlyEmitsLifecycleAndFailureLikeUpstream() throws {
    var tracker = OpenAIResponsesStreamingToolCalls(providerID: "xai.responses")
    let parts = tracker.apply(event: [
        "type": "response.output_item.done",
        "output_index": 0,
        "item": [
            "type": "image_generation_call",
            "id": "ig-failed",
            "status": "failed"
        ]
    ])

    #expect(parts.count == 5)
    #expect(parts.contains(.toolInputStart(id: "ig-failed", name: "image_generation")))
    #expect(parts.contains(.toolInputDelta(id: "ig-failed", delta: "{}")))
    #expect(parts.contains(.toolInputEnd(id: "ig-failed")))
    guard case let .toolCall(call) = parts[3], case let .toolResult(result) = parts[4] else {
        Issue.record("Expected xAI image generation tool call and failure result")
        return
    }
    #expect(call.id == "ig-failed")
    #expect(call.arguments == "{}")
    #expect(call.providerExecuted)
    #expect(result.result == "Image generation failed (status: failed).")
    #expect(result.isError)
}
