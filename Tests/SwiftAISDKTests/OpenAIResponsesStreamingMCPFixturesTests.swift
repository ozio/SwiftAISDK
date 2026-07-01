import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesStreamsMCPToolResultsFromFixtureLikeUpstream() async throws {
    let fixtureName = "openai-mcp-tool.1.chunks.txt"
    let fixtureEvents = try openAIResponsesChunksFixtureEvents(fixtureName)
    let doneItems = fixtureEvents
        .filter { $0["type"]?.stringValue == "response.output_item.done" }
        .compactMap { $0["item"] }
    let expectedReasonings = doneItems.filter { $0["type"]?.stringValue == "reasoning" }
    let expectedMCPCalls = doneItems.filter { $0["type"]?.stringValue == "mcp_call" }
    let expectedMessage = try #require(doneItems.first { $0["type"]?.stringValue == "message" })
    let expectedText = fixtureEvents
        .filter { $0["type"]?.stringValue == "response.output_text.delta" }
        .compactMap { $0["delta"]?.stringValue }
        .joined()

    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse(fixtureName))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-mini")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var sawInputLifecycle = false
    var reasoningStarts: [(String, [String: JSONValue])] = []
    var reasoningEnds: [(String, [String: JSONValue])] = []
    var toolCalls: [AIToolCall] = []
    var toolResults: [AIToolResult] = []
    var textStarts: [(String, [String: JSONValue])] = []
    var textDeltas: [String] = []
    var textEnds: [(String, [String: JSONValue])] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishProviderMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesStreamingMCPTool()
    )) {
        switch part {
        case .streamStart:
            streamStarted = true
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case .toolInputStart, .toolInputDelta, .toolInputEnd:
            sawInputLifecycle = true
        case let .reasoningStart(id, metadata):
            reasoningStarts.append((id, metadata))
        case let .reasoningEnd(id, metadata):
            reasoningEnds.append((id, metadata))
        case let .toolCall(call) where call.name.hasPrefix("mcp."):
            toolCalls.append(call)
        case let .toolResult(result) where result.toolName.hasPrefix("mcp."):
            toolResults.append(result)
        case let .textStart(id, metadata):
            textStarts.append((id, metadata))
        case let .textDeltaPart(_, delta, _):
            textDeltas.append(delta)
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
    #expect(responseMetadata?.id == "resp_0c72b1033351981300690ccf79c6d88193b7d054f4f83ad50a")
    #expect(responseMetadata?.modelID == "gpt-5-mini-2025-08-07")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_762_447_225))
    #expect(sawInputLifecycle == false)

    #expect(reasoningStarts.map { $0.0 } == expectedReasonings.map { "\($0["id"]?.stringValue ?? ""):0" })
    #expect(reasoningEnds.map { $0.0 } == reasoningStarts.map { $0.0 })
    for index in expectedReasonings.indices {
        let expectedID = try #require(expectedReasonings[index]["id"]?.stringValue)
        #expect(reasoningStarts[index].1["openai"]?["itemId"]?.stringValue == expectedID)
        #expect(reasoningStarts[index].1["openai"]?["reasoningEncryptedContent"] == .null)
        #expect(reasoningEnds[index].1["openai"]?["itemId"]?.stringValue == expectedID)
        #expect(reasoningEnds[index].1["openai"]?["reasoningEncryptedContent"] == .null)
    }

    try #require(toolCalls.count == expectedMCPCalls.count)
    for index in expectedMCPCalls.indices {
        let expectedCall = expectedMCPCalls[index]
        let call = toolCalls[index]
        #expect(call.id == expectedCall["id"]?.stringValue)
        #expect(call.name == "mcp.\(expectedCall["name"]?.stringValue ?? "")")
        #expect(call.arguments == expectedCall["arguments"]?.stringValue)
        #expect(call.providerExecuted == true)
        #expect(call.dynamic == true)
        #expect(call.providerMetadata.isEmpty)
    }

    try #require(toolResults.count == expectedMCPCalls.count)
    for index in expectedMCPCalls.indices {
        let expectedCall = expectedMCPCalls[index]
        let result = toolResults[index]
        #expect(result.toolCallID == expectedCall["id"]?.stringValue)
        #expect(result.toolName == "mcp.\(expectedCall["name"]?.stringValue ?? "")")
        #expect(result.dynamic == true)
        #expect(result.result["type"]?.stringValue == "call")
        #expect(result.result["serverLabel"]?.stringValue == expectedCall["server_label"]?.stringValue)
        #expect(result.result["name"]?.stringValue == expectedCall["name"]?.stringValue)
        #expect(result.result["arguments"]?.stringValue == expectedCall["arguments"]?.stringValue)
        #expect(result.result["output"]?.stringValue == expectedCall["output"]?.stringValue)
        #expect(result.providerMetadata["openai"]?["itemId"]?.stringValue == expectedCall["id"]?.stringValue)
    }

    let expectedMessageID = try #require(expectedMessage["id"]?.stringValue)
    #expect(textStarts.map { $0.0 } == [expectedMessageID])
    #expect(textStarts[0].1["openai"]?["itemId"]?.stringValue == expectedMessageID)
    #expect(textDeltas.joined() == expectedText)
    #expect(textEnds.map { $0.0 } == [expectedMessageID])
    #expect(textEnds[0].1["openai"]?["itemId"]?.stringValue == expectedMessageID)

    #expect(finishReason == "stop")
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == "resp_0c72b1033351981300690ccf79c6d88193b7d054f4f83ad50a")
    #expect(finishProviderMetadata["openai"]?["serviceTier"]?.stringValue == "default")
    #expect(finishUsage?.inputTokens == 11791)
    #expect(finishUsage?.inputTokensCacheRead == 0)
    #expect(finishUsage?.outputTokens == 963)
    #expect(finishUsage?.outputReasoningTokens == 512)
    #expect(finishUsage?.totalTokens == 12754)
}

@Test func openAIResponsesStreamsMCPApprovalRequestFromFixtureLikeUpstream() async throws {
    let fixtureName = "openai-mcp-tool-approval.1.chunks.txt"
    let fixtureEvents = try openAIResponsesChunksFixtureEvents(fixtureName)
    let doneItems = fixtureEvents
        .filter { $0["type"]?.stringValue == "response.output_item.done" }
        .compactMap { $0["item"] }
    let expectedReasonings = doneItems.filter { $0["type"]?.stringValue == "reasoning" }
    let expectedApproval = try #require(doneItems.first { $0["type"]?.stringValue == "mcp_approval_request" })

    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse(fixtureName))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-mini")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var sawInputLifecycle = false
    var sawText = false
    var reasoningStarts: [(String, [String: JSONValue])] = []
    var reasoningEnds: [(String, [String: JSONValue])] = []
    var toolCalls: [AIToolCall] = []
    var toolResults: [AIToolResult] = []
    var approvalRequests: [AIToolApprovalRequest] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishProviderMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesStreamingMCPApprovalTool()
    )) {
        switch part {
        case .streamStart:
            streamStarted = true
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case .toolInputStart, .toolInputDelta, .toolInputEnd:
            sawInputLifecycle = true
        case .textStart, .textDeltaPart, .textEnd:
            sawText = true
        case let .reasoningStart(id, metadata):
            reasoningStarts.append((id, metadata))
        case let .reasoningEnd(id, metadata):
            reasoningEnds.append((id, metadata))
        case let .toolCall(call):
            toolCalls.append(call)
        case let .toolResult(result):
            toolResults.append(result)
        case let .toolApprovalRequest(request):
            approvalRequests.append(request)
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
    #expect(responseMetadata?.id == "resp_04a97b4fce127879006949a837a3a48195b37f26ae73f550c0")
    #expect(responseMetadata?.modelID == "gpt-5-mini-2025-08-07")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_766_434_871))
    #expect(sawInputLifecycle == false)
    #expect(sawText == false)

    #expect(reasoningStarts.map { $0.0 } == expectedReasonings.map { "\($0["id"]?.stringValue ?? ""):0" })
    #expect(reasoningEnds.map { $0.0 } == reasoningStarts.map { $0.0 })
    for index in expectedReasonings.indices {
        let expectedID = try #require(expectedReasonings[index]["id"]?.stringValue)
        #expect(reasoningStarts[index].1["openai"]?["itemId"]?.stringValue == expectedID)
        #expect(reasoningStarts[index].1["openai"]?["reasoningEncryptedContent"] == .null)
        #expect(reasoningEnds[index].1["openai"]?["itemId"]?.stringValue == expectedID)
        #expect(reasoningEnds[index].1["openai"]?["reasoningEncryptedContent"] == .null)
    }

    try #require(toolCalls.count == 1)
    let toolCall = toolCalls[0]
    #expect(toolCall.id == "id-0")
    #expect(toolCall.name == "mcp.\(expectedApproval["name"]?.stringValue ?? "")")
    #expect(toolCall.arguments == expectedApproval["arguments"]?.stringValue)
    #expect(toolCall.providerExecuted == true)
    #expect(toolCall.dynamic == true)
    #expect(toolCall.providerMetadata.isEmpty)

    #expect(toolResults.isEmpty)

    try #require(approvalRequests.count == 1)
    let approvalRequest = approvalRequests[0]
    #expect(approvalRequest.id == expectedApproval["id"]?.stringValue)
    #expect(approvalRequest.toolCallID == "id-0")
    #expect(approvalRequest.toolName == "mcp.\(expectedApproval["name"]?.stringValue ?? "")")
    #expect(approvalRequest.arguments == expectedApproval["arguments"]?.stringValue)

    #expect(finishReason == "stop")
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == "resp_04a97b4fce127879006949a837a3a48195b37f26ae73f550c0")
    #expect(finishProviderMetadata["openai"]?["serviceTier"]?.stringValue == "default")
    #expect(finishUsage?.inputTokens == 422)
    #expect(finishUsage?.inputTokensCacheRead == 0)
    #expect(finishUsage?.outputTokens == 48)
    #expect(finishUsage?.outputReasoningTokens == 0)
    #expect(finishUsage?.totalTokens == 470)
}

@Test func openAIResponsesStreamsMCPApprovalDenialTextFromFixtureLikeUpstream() async throws {
    let fixtureName = "openai-mcp-tool-approval.2.chunks.txt"
    let fixtureEvents = try openAIResponsesChunksFixtureEvents(fixtureName)
    let doneItems = fixtureEvents
        .filter { $0["type"]?.stringValue == "response.output_item.done" }
        .compactMap { $0["item"] }
    let expectedReasonings = doneItems.filter { $0["type"]?.stringValue == "reasoning" }
    let expectedMessage = try #require(doneItems.first { $0["type"]?.stringValue == "message" })
    let expectedText = fixtureEvents
        .filter { $0["type"]?.stringValue == "response.output_text.delta" }
        .compactMap { $0["delta"]?.stringValue }
        .joined()

    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse(fixtureName))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-mini")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var sawInputLifecycle = false
    var toolCalls: [AIToolCall] = []
    var toolResults: [AIToolResult] = []
    var approvalRequests: [AIToolApprovalRequest] = []
    var reasoningStarts: [(String, [String: JSONValue])] = []
    var reasoningEnds: [(String, [String: JSONValue])] = []
    var textStarts: [(String, [String: JSONValue])] = []
    var textDeltas: [String] = []
    var textEnds: [(String, [String: JSONValue])] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishProviderMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: openAIResponsesStreamingMCPApprovalDeniedMessages(),
        tools: openAIResponsesStreamingMCPApprovalTool()
    )) {
        switch part {
        case .streamStart:
            streamStarted = true
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case .toolInputStart, .toolInputDelta, .toolInputEnd:
            sawInputLifecycle = true
        case let .toolCall(call):
            toolCalls.append(call)
        case let .toolResult(result):
            toolResults.append(result)
        case let .toolApprovalRequest(request):
            approvalRequests.append(request)
        case let .reasoningStart(id, metadata):
            reasoningStarts.append((id, metadata))
        case let .reasoningEnd(id, metadata):
            reasoningEnds.append((id, metadata))
        case let .textStart(id, metadata):
            textStarts.append((id, metadata))
        case let .textDeltaPart(_, delta, _):
            textDeltas.append(delta)
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
    #expect(responseMetadata?.id == "resp_04a97b4fce127879006949a855fa68819598a2a379fd5b6c38")
    #expect(responseMetadata?.modelID == "gpt-5-mini-2025-08-07")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_766_434_902))
    #expect(sawInputLifecycle == false)
    #expect(toolCalls.isEmpty)
    #expect(toolResults.isEmpty)
    #expect(approvalRequests.isEmpty)

    #expect(reasoningStarts.map { $0.0 } == expectedReasonings.map { "\($0["id"]?.stringValue ?? ""):0" })
    #expect(reasoningEnds.map { $0.0 } == reasoningStarts.map { $0.0 })
    for index in expectedReasonings.indices {
        let expectedID = try #require(expectedReasonings[index]["id"]?.stringValue)
        #expect(reasoningStarts[index].1["openai"]?["itemId"]?.stringValue == expectedID)
        #expect(reasoningStarts[index].1["openai"]?["reasoningEncryptedContent"] == .null)
        #expect(reasoningEnds[index].1["openai"]?["itemId"]?.stringValue == expectedID)
        #expect(reasoningEnds[index].1["openai"]?["reasoningEncryptedContent"] == .null)
    }

    let expectedMessageID = try #require(expectedMessage["id"]?.stringValue)
    #expect(textStarts.map { $0.0 } == [expectedMessageID])
    #expect(textStarts[0].1["openai"]?["itemId"]?.stringValue == expectedMessageID)
    #expect(textDeltas.joined() == expectedText)
    #expect(textEnds.map { $0.0 } == [expectedMessageID])
    #expect(textEnds[0].1["openai"]?["itemId"]?.stringValue == expectedMessageID)

    #expect(finishReason == "stop")
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == "resp_04a97b4fce127879006949a855fa68819598a2a379fd5b6c38")
    #expect(finishProviderMetadata["openai"]?["serviceTier"]?.stringValue == "default")
    #expect(finishUsage?.inputTokens == 553)
    #expect(finishUsage?.inputTokensCacheRead == 0)
    #expect(finishUsage?.outputTokens == 371)
    #expect(finishUsage?.outputReasoningTokens == 256)
    #expect(finishUsage?.totalTokens == 924)
}

@Test func openAIResponsesStreamsNewMCPApprovalRequestAfterRetryFromFixtureLikeUpstream() async throws {
    let fixtureName = "openai-mcp-tool-approval.3.chunks.txt"
    let fixtureEvents = try openAIResponsesChunksFixtureEvents(fixtureName)
    let doneItems = fixtureEvents
        .filter { $0["type"]?.stringValue == "response.output_item.done" }
        .compactMap { $0["item"] }
    let expectedReasonings = doneItems.filter { $0["type"]?.stringValue == "reasoning" }
    let expectedApproval = try #require(doneItems.first { $0["type"]?.stringValue == "mcp_approval_request" })

    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse(fixtureName))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-mini")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var sawInputLifecycle = false
    var sawText = false
    var reasoningStarts: [(String, [String: JSONValue])] = []
    var reasoningEnds: [(String, [String: JSONValue])] = []
    var toolCalls: [AIToolCall] = []
    var toolResults: [AIToolResult] = []
    var approvalRequests: [AIToolApprovalRequest] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishProviderMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: openAIResponsesStreamingMCPApprovalRetryMessages(),
        tools: openAIResponsesStreamingMCPApprovalTool()
    )) {
        switch part {
        case .streamStart:
            streamStarted = true
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case .toolInputStart, .toolInputDelta, .toolInputEnd:
            sawInputLifecycle = true
        case .textStart, .textDeltaPart, .textEnd:
            sawText = true
        case let .reasoningStart(id, metadata):
            reasoningStarts.append((id, metadata))
        case let .reasoningEnd(id, metadata):
            reasoningEnds.append((id, metadata))
        case let .toolCall(call):
            toolCalls.append(call)
        case let .toolResult(result):
            toolResults.append(result)
        case let .toolApprovalRequest(request):
            approvalRequests.append(request)
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
    #expect(responseMetadata?.id == "resp_04a97b4fce127879006949a864795c8195a77efd798149326b")
    #expect(responseMetadata?.modelID == "gpt-5-mini-2025-08-07")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_766_434_916))
    #expect(sawInputLifecycle == false)
    #expect(sawText == false)

    #expect(reasoningStarts.map { $0.0 } == expectedReasonings.map { "\($0["id"]?.stringValue ?? ""):0" })
    #expect(reasoningEnds.map { $0.0 } == reasoningStarts.map { $0.0 })
    for index in expectedReasonings.indices {
        let expectedID = try #require(expectedReasonings[index]["id"]?.stringValue)
        #expect(reasoningStarts[index].1["openai"]?["itemId"]?.stringValue == expectedID)
        #expect(reasoningStarts[index].1["openai"]?["reasoningEncryptedContent"] == .null)
        #expect(reasoningEnds[index].1["openai"]?["itemId"]?.stringValue == expectedID)
        #expect(reasoningEnds[index].1["openai"]?["reasoningEncryptedContent"] == .null)
    }

    try #require(toolCalls.count == 1)
    let toolCall = toolCalls[0]
    #expect(toolCall.id == "id-0")
    #expect(toolCall.name == "mcp.\(expectedApproval["name"]?.stringValue ?? "")")
    #expect(toolCall.arguments == expectedApproval["arguments"]?.stringValue)
    #expect(toolCall.providerExecuted == true)
    #expect(toolCall.dynamic == true)
    #expect(toolCall.providerMetadata.isEmpty)

    #expect(toolResults.isEmpty)

    try #require(approvalRequests.count == 1)
    let approvalRequest = approvalRequests[0]
    #expect(approvalRequest.id == expectedApproval["id"]?.stringValue)
    #expect(approvalRequest.toolCallID == "id-0")
    #expect(approvalRequest.toolName == "mcp.\(expectedApproval["name"]?.stringValue ?? "")")
    #expect(approvalRequest.arguments == expectedApproval["arguments"]?.stringValue)

    #expect(finishReason == "stop")
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == "resp_04a97b4fce127879006949a864795c8195a77efd798149326b")
    #expect(finishProviderMetadata["openai"]?["serviceTier"]?.stringValue == "default")
    #expect(finishUsage?.inputTokens == 609)
    #expect(finishUsage?.inputTokensCacheRead == 0)
    #expect(finishUsage?.outputTokens == 48)
    #expect(finishUsage?.outputReasoningTokens == 0)
    #expect(finishUsage?.totalTokens == 657)
}

@Test func openAIResponsesStreamsMCPToolResultAfterApprovalFromFixtureLikeUpstream() async throws {
    let fixtureName = "openai-mcp-tool-approval.4.chunks.txt"
    let fixtureEvents = try openAIResponsesChunksFixtureEvents(fixtureName)
    let doneItems = fixtureEvents
        .filter { $0["type"]?.stringValue == "response.output_item.done" }
        .compactMap { $0["item"] }
    let expectedMCPCall = try #require(doneItems.first { $0["type"]?.stringValue == "mcp_call" })
    let expectedMessage = try #require(doneItems.first { $0["type"]?.stringValue == "message" })
    let expectedText = fixtureEvents
        .filter { $0["type"]?.stringValue == "response.output_text.delta" }
        .compactMap { $0["delta"]?.stringValue }
        .joined()

    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse(fixtureName))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-mini")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var sawInputLifecycle = false
    var sawReasoning = false
    var approvalRequests: [AIToolApprovalRequest] = []
    var toolCalls: [AIToolCall] = []
    var toolResults: [AIToolResult] = []
    var textStarts: [(String, [String: JSONValue])] = []
    var textDeltas: [String] = []
    var textEnds: [(String, [String: JSONValue])] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishProviderMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: openAIResponsesStreamingMCPApprovalApprovedMessages(),
        tools: openAIResponsesStreamingMCPApprovalTool()
    )) {
        switch part {
        case .streamStart:
            streamStarted = true
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case .toolInputStart, .toolInputDelta, .toolInputEnd:
            sawInputLifecycle = true
        case .reasoningStart, .reasoningDelta, .reasoningEnd:
            sawReasoning = true
        case let .toolApprovalRequest(request):
            approvalRequests.append(request)
        case let .toolCall(call):
            toolCalls.append(call)
        case let .toolResult(result):
            toolResults.append(result)
        case let .textStart(id, metadata):
            textStarts.append((id, metadata))
        case let .textDeltaPart(_, delta, _):
            textDeltas.append(delta)
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
    #expect(responseMetadata?.id == "resp_04a97b4fce127879006949a87ab0cc8195b3175edc260d6a88")
    #expect(responseMetadata?.modelID == "gpt-5-mini-2025-08-07")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_766_434_938))
    #expect(sawInputLifecycle == false)
    #expect(sawReasoning == false)
    #expect(approvalRequests.isEmpty)

    try #require(toolCalls.count == 1)
    let toolCall = toolCalls[0]
    #expect(toolCall.id == expectedMCPCall["id"]?.stringValue)
    #expect(toolCall.name == "mcp.\(expectedMCPCall["name"]?.stringValue ?? "")")
    #expect(toolCall.arguments == expectedMCPCall["arguments"]?.stringValue)
    #expect(toolCall.providerExecuted == true)
    #expect(toolCall.dynamic == true)
    #expect(toolCall.providerMetadata.isEmpty)

    try #require(toolResults.count == 1)
    let toolResult = toolResults[0]
    #expect(toolResult.toolCallID == expectedMCPCall["id"]?.stringValue)
    #expect(toolResult.toolName == "mcp.\(expectedMCPCall["name"]?.stringValue ?? "")")
    #expect(toolResult.dynamic == true)
    #expect(toolResult.result["type"]?.stringValue == "call")
    #expect(toolResult.result["serverLabel"]?.stringValue == expectedMCPCall["server_label"]?.stringValue)
    #expect(toolResult.result["name"]?.stringValue == expectedMCPCall["name"]?.stringValue)
    #expect(toolResult.result["arguments"]?.stringValue == expectedMCPCall["arguments"]?.stringValue)
    #expect(toolResult.result["output"]?.stringValue == expectedMCPCall["output"]?.stringValue)
    #expect(toolResult.providerMetadata["openai"]?["itemId"]?.stringValue == expectedMCPCall["id"]?.stringValue)

    let expectedMessageID = try #require(expectedMessage["id"]?.stringValue)
    #expect(textStarts.map { $0.0 } == [expectedMessageID])
    #expect(textStarts[0].1["openai"]?["itemId"]?.stringValue == expectedMessageID)
    #expect(textDeltas.joined() == expectedText)
    #expect(textEnds.map { $0.0 } == [expectedMessageID])
    #expect(textEnds[0].1["openai"]?["itemId"]?.stringValue == expectedMessageID)

    #expect(finishReason == "stop")
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == "resp_04a97b4fce127879006949a87ab0cc8195b3175edc260d6a88")
    #expect(finishProviderMetadata["openai"]?["serviceTier"]?.stringValue == "default")
    #expect(finishUsage?.inputTokens == 779)
    #expect(finishUsage?.inputTokensCacheRead == 0)
    #expect(finishUsage?.outputTokens == 69)
    #expect(finishUsage?.outputReasoningTokens == 0)
    #expect(finishUsage?.totalTokens == 848)
}
