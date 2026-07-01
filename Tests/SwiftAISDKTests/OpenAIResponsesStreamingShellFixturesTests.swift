import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesStreamsLocalShellResultsLikeUpstream() async throws {
    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse("openai-local-shell-tool.1.chunks.txt"))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-codex")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var reasoningStarts: [(String, [String: JSONValue])] = []
    var reasoningEnds: [(String, [String: JSONValue])] = []
    var sawInputLifecycle = false
    var toolCall: AIToolCall?
    var toolResults: [AIToolResult] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishProviderMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesStreamingLocalShellTool()
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
        case .toolInputStart, .toolInputDelta, .toolInputEnd:
            sawInputLifecycle = true
        case let .toolCall(call) where call.name == "shell":
            toolCall = call
        case let .toolResult(result):
            toolResults.append(result)
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
    #expect(responseMetadata?.id == "resp_68da7fd5d24481949fc2cf1cc60377050faf5df54b42d9a6")
    #expect(responseMetadata?.modelID == "gpt-5-codex")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_759_150_037))

    #expect(reasoningStarts.map { $0.0 } == ["rs_68da7fd65a3481948bbb35ff2c79c6c20faf5df54b42d9a6:0"])
    #expect(reasoningEnds.map { $0.0 } == reasoningStarts.map { $0.0 })
    #expect(reasoningStarts[0].1["openai"]?["itemId"]?.stringValue == "rs_68da7fd65a3481948bbb35ff2c79c6c20faf5df54b42d9a6")
    #expect(reasoningStarts[0].1["openai"]?["reasoningEncryptedContent"] == .null)

    #expect(sawInputLifecycle == false)
    #expect(toolResults.isEmpty)
    let call = try #require(toolCall)
    #expect(call.id == "call_h3nm8hUG0KO9tVNuRACkL1ri")
    #expect(call.name == "shell")
    #expect(call.providerExecuted == false)
    #expect(call.providerMetadata["openai"]?["itemId"]?.stringValue == "lsh_68da7fd99b3c8194bd624b18c0c0851b0faf5df54b42d9a6")
    let input = try decodeJSONBody(Data(call.arguments.utf8))
    #expect(input["action"]?["type"]?.stringValue == "exec")
    #expect(input["action"]?["command"]?.arrayValue?.compactMap(\.stringValue) == ["ls", "-a", "~"])
    #expect(input["action"]?["env"]?.objectValue?.isEmpty == true)

    #expect(finishReason == "stop")
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == "resp_68da7fd5d24481949fc2cf1cc60377050faf5df54b42d9a6")
    #expect(finishProviderMetadata["openai"]?["serviceTier"]?.stringValue == "default")
    #expect(finishUsage?.inputTokens == 407)
    #expect(finishUsage?.inputTokensCacheRead == 0)
    #expect(finishUsage?.outputTokens == 151)
    #expect(finishUsage?.outputReasoningTokens == 128)
    #expect(finishUsage?.totalTokens == 558)
}

@Test func openAIResponsesStreamsShellResultsLikeUpstream() async throws {
    let fixtureName = "openai-shell-tool.1.chunks.txt"
    let fixtureEvents = try openAIResponsesChunksFixtureEvents(fixtureName)
    let completedResponses = fixtureEvents.filter { $0["type"]?.stringValue == "response.completed" }
    let finalResponse = try #require(completedResponses.last?["response"])
    let expectedMessage = try #require(finalResponse["output"]?.arrayValue?.first { $0["type"]?.stringValue == "message" })
    let expectedText = try #require(expectedMessage["content"]?[0]?["text"]?.stringValue)

    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse(fixtureName))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    var streamStarted = false
    var responseMetadata: [AIResponseMetadata] = []
    var sawInputLifecycle = false
    var toolCall: AIToolCall?
    var toolResults: [AIToolResult] = []
    var textStarts: [(String, [String: JSONValue])] = []
    var textDeltas: [String] = []
    var textEnds: [(String, [String: JSONValue])] = []
    var finishReasons: [String?] = []
    var finishUsages: [TokenUsage?] = []
    var finishProviderMetadata: [[String: JSONValue]] = []

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesStreamingShellTool()
    )) {
        switch part {
        case .streamStart:
            streamStarted = true
        case let .responseMetadata(metadata):
            responseMetadata.append(metadata)
        case .toolInputStart, .toolInputDelta, .toolInputEnd:
            sawInputLifecycle = true
        case let .toolCall(call) where call.name == "shell":
            toolCall = call
        case let .toolResult(result):
            toolResults.append(result)
        case let .textStart(id, metadata):
            textStarts.append((id, metadata))
        case let .textDeltaPart(_, delta, _):
            textDeltas.append(delta)
        case let .textEnd(id, metadata):
            textEnds.append((id, metadata))
        case let .finish(reason, usage):
            finishReasons.append(reason)
            finishUsages.append(usage)
        case let .finishMetadata(reason, usage, metadata):
            finishReasons.append(reason)
            finishUsages.append(usage)
            finishProviderMetadata.append(metadata)
        default:
            break
        }
    }

    #expect(streamStarted)
    #expect(responseMetadata.map(\.id) == [
        "resp_0434d6d64b12b08900692f639c40408195a50fd07b77ce08a7",
        "resp_0434d6d64b12b08900692f639d784481959af65f985b9c13e2"
    ])
    #expect(responseMetadata.map(\.modelID) == Array(repeating: "gpt-5.1-2025-11-13", count: 2))
    #expect(responseMetadata.map(\.timestamp) == [
        Date(timeIntervalSince1970: 1_764_713_372),
        Date(timeIntervalSince1970: 1_764_713_373)
    ])

    #expect(sawInputLifecycle == false)
    #expect(toolResults.isEmpty)
    let call = try #require(toolCall)
    #expect(call.id == "call_pbxjNs1tMJUahLZKAS9qLtvw")
    #expect(call.name == "shell")
    #expect(call.providerExecuted == false)
    #expect(call.providerMetadata["openai"]?["itemId"]?.stringValue == "sh_0434d6d64b12b08900692f639c9f0481959c30e03ca0bb2ef8")
    let input = try decodeJSONBody(Data(call.arguments.utf8))
    #expect(input["action"]?["commands"]?.arrayValue?.compactMap(\.stringValue) == ["ls -a ~/Desktop"])
    #expect(input["action"]?["max_output_length"] == nil)
    #expect(input["action"]?["timeout_ms"] == nil)

    #expect(textStarts.map { $0.0 } == ["msg_0434d6d64b12b08900692f639dc53c819594ea97586113d73b"])
    #expect(textStarts[0].1["openai"]?["itemId"]?.stringValue == "msg_0434d6d64b12b08900692f639dc53c819594ea97586113d73b")
    #expect(textDeltas.joined() == expectedText)
    #expect(textEnds.map { $0.0 } == ["msg_0434d6d64b12b08900692f639dc53c819594ea97586113d73b"])
    #expect(textEnds[0].1["openai"]?["itemId"]?.stringValue == "msg_0434d6d64b12b08900692f639dc53c819594ea97586113d73b")

    #expect(finishReasons == ["stop"])
    #expect(finishProviderMetadata.count == 1)
    #expect(finishProviderMetadata[0]["openai"]?["responseId"]?.stringValue == "resp_0434d6d64b12b08900692f639d784481959af65f985b9c13e2")
    #expect(finishProviderMetadata[0]["openai"]?["serviceTier"]?.stringValue == "default")
    let finishUsage = try #require(finishUsages.first ?? nil)
    #expect(finishUsage.inputTokens == 331)
    #expect(finishUsage.inputTokensCacheRead == 0)
    #expect(finishUsage.outputTokens == 166)
    #expect(finishUsage.outputReasoningTokens == 0)
    #expect(finishUsage.totalTokens == 497)
}

@Test func openAIResponsesStreamsShellContainerResultsLikeUpstream() async throws {
    let fixtureName = "openai-shell-container.1.chunks.txt"
    let fixtureEvents = try openAIResponsesChunksFixtureEvents(fixtureName)
    let expectedText = fixtureEvents
        .filter { $0["type"]?.stringValue == "response.output_text.delta" }
        .compactMap { $0["delta"]?.stringValue }
        .joined()

    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse(fixtureName))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var sawInputLifecycle = false
    var toolCall: AIToolCall?
    var toolResults: [AIToolResult] = []
    var textStarts: [(String, [String: JSONValue])] = []
    var textDeltas: [String] = []
    var textEnds: [(String, [String: JSONValue])] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishProviderMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesStreamingShellContainerTool()
    )) {
        switch part {
        case .streamStart:
            streamStarted = true
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case .toolInputStart, .toolInputDelta, .toolInputEnd:
            sawInputLifecycle = true
        case let .toolCall(call) where call.name == "shell":
            toolCall = call
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
    #expect(responseMetadata?.id == "resp_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f")
    #expect(responseMetadata?.modelID == "gpt-5.2-2025-12-11")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_771_009_000))

    #expect(sawInputLifecycle == false)
    let call = try #require(toolCall)
    #expect(call.id == "call_abc123def456ghi789jkl012")
    #expect(call.name == "shell")
    #expect(call.providerExecuted == true)
    #expect(call.providerMetadata["openai"]?["itemId"]?.stringValue == "sh_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e50")
    let input = try decodeJSONBody(Data(call.arguments.utf8))
    #expect(input["action"]?["commands"]?.arrayValue?.compactMap(\.stringValue) == ["echo 'Hello from container!' && uname -a"])

    #expect(toolResults.count == 1)
    let toolResult = try #require(toolResults.first)
    #expect(toolResult.toolCallID == "call_abc123def456ghi789jkl012")
    #expect(toolResult.toolName == "shell")
    let output = try #require(toolResult.result["output"]?.arrayValue)
    #expect(output.count == 1)
    #expect(output[0]["outcome"]?["type"]?.stringValue == "exit")
    #expect(output[0]["outcome"]?["exitCode"]?.intValue == 0)
    #expect(output[0]["stderr"]?.stringValue == "")
    #expect(output[0]["stdout"]?.stringValue == "Hello from container!\nLinux container-host 6.1.0 #1 SMP x86_64 GNU/Linux\n")

    #expect(textStarts.map { $0.0 } == ["msg_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e52"])
    #expect(textStarts[0].1["openai"]?["itemId"]?.stringValue == "msg_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e52")
    #expect(textDeltas.joined() == expectedText)
    #expect(textEnds.map { $0.0 } == ["msg_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e52"])
    #expect(textEnds[0].1["openai"]?["itemId"]?.stringValue == "msg_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e52")

    #expect(finishReason == "stop")
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == "resp_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f")
    #expect(finishProviderMetadata["openai"]?["serviceTier"]?.stringValue == "default")
    #expect(finishUsage?.inputTokens == 200)
    #expect(finishUsage?.inputTokensCacheRead == 0)
    #expect(finishUsage?.outputTokens == 120)
    #expect(finishUsage?.outputReasoningTokens == 0)
    #expect(finishUsage?.totalTokens == 320)
}

@Test func openAIResponsesStreamsShellContainerMultiturnFollowUpLikeUpstream() async throws {
    let fixtureName = "openai-shell-container-multiturn.1.chunks.txt"
    let fixtureEvents = try openAIResponsesChunksFixtureEvents(fixtureName)
    let expectedText = fixtureEvents
        .filter { $0["type"]?.stringValue == "response.output_text.delta" }
        .compactMap { $0["delta"]?.stringValue }
        .joined()

    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse(fixtureName))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var sawInputLifecycle = false
    var toolCalls: [AIToolCall] = []
    var toolResults: [AIToolResult] = []
    var textStarts: [(String, [String: JSONValue])] = []
    var textDeltas: [String] = []
    var textEnds: [(String, [String: JSONValue])] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishProviderMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: openAIResponsesStreamingShellContainerMultiturnMessages(),
        tools: openAIResponsesStreamingShellContainerTool()
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
    #expect(responseMetadata?.id == "resp_07226f71de51f72b006994e63fe86881a3ac247b9463ce4550")
    #expect(responseMetadata?.modelID == "gpt-5.2-2025-12-11")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_771_365_951))

    #expect(sawInputLifecycle == false)
    #expect(toolCalls.isEmpty)
    #expect(toolResults.isEmpty)
    #expect(textStarts.map { $0.0 } == ["msg_07226f71de51f72b006994e641127c81a3ba3d54eedadff969"])
    #expect(textStarts[0].1["openai"]?["itemId"]?.stringValue == "msg_07226f71de51f72b006994e641127c81a3ba3d54eedadff969")
    #expect(textDeltas.joined() == expectedText)
    #expect(textEnds.map { $0.0 } == ["msg_07226f71de51f72b006994e641127c81a3ba3d54eedadff969"])
    #expect(textEnds[0].1["openai"]?["itemId"]?.stringValue == "msg_07226f71de51f72b006994e641127c81a3ba3d54eedadff969")

    #expect(finishReason == "stop")
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == "resp_07226f71de51f72b006994e63fe86881a3ac247b9463ce4550")
    #expect(finishProviderMetadata["openai"]?["serviceTier"]?.stringValue == "default")
    #expect(finishUsage?.inputTokens == 802)
    #expect(finishUsage?.inputTokensCacheRead == 0)
    #expect(finishUsage?.outputTokens == 20)
    #expect(finishUsage?.outputReasoningTokens == 0)
    #expect(finishUsage?.totalTokens == 822)
}

@Test func openAIResponsesStreamsShellLocalMultiturnFollowUpLikeUpstream() async throws {
    let fixtureName = "openai-shell-local-multiturn.1.chunks.txt"
    let fixtureEvents = try openAIResponsesChunksFixtureEvents(fixtureName)
    let expectedText = fixtureEvents
        .filter { $0["type"]?.stringValue == "response.output_text.delta" }
        .compactMap { $0["delta"]?.stringValue }
        .joined()

    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse(fixtureName))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var sawInputLifecycle = false
    var toolCalls: [AIToolCall] = []
    var toolResults: [AIToolResult] = []
    var textStarts: [(String, [String: JSONValue])] = []
    var textDeltas: [String] = []
    var textEnds: [(String, [String: JSONValue])] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishProviderMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: openAIResponsesStreamingShellLocalMultiturnMessages(),
        tools: openAIResponsesStreamingShellTool()
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
    #expect(responseMetadata?.id == "resp_0b0392bd3bb81302006994e83ac0ac819396f3f5aa5f239e03")
    #expect(responseMetadata?.modelID == "gpt-5.2-2025-12-11")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_771_366_458))

    #expect(sawInputLifecycle == false)
    #expect(toolCalls.isEmpty)
    #expect(toolResults.isEmpty)
    #expect(textStarts.map { $0.0 } == ["msg_0b0392bd3bb81302006994e83b32748193aa637cdb31658266"])
    #expect(textStarts[0].1["openai"]?["itemId"]?.stringValue == "msg_0b0392bd3bb81302006994e83b32748193aa637cdb31658266")
    #expect(textDeltas.joined() == expectedText)
    #expect(textEnds.map { $0.0 } == ["msg_0b0392bd3bb81302006994e83b32748193aa637cdb31658266"])
    #expect(textEnds[0].1["openai"]?["itemId"]?.stringValue == "msg_0b0392bd3bb81302006994e83b32748193aa637cdb31658266")

    #expect(finishReason == "stop")
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == "resp_0b0392bd3bb81302006994e83ac0ac819396f3f5aa5f239e03")
    #expect(finishProviderMetadata["openai"]?["serviceTier"]?.stringValue == "default")
    #expect(finishUsage?.inputTokens == 444)
    #expect(finishUsage?.inputTokensCacheRead == 0)
    #expect(finishUsage?.outputTokens == 12)
    #expect(finishUsage?.outputReasoningTokens == 0)
    #expect(finishUsage?.totalTokens == 456)
}

@Test func openAIResponsesStreamsShellEnvironmentResultsLikeUpstream() async throws {
    let fixtureName = "openai-shell-skills.1.chunks.txt"
    let fixtureEvents = try openAIResponsesChunksFixtureEvents(fixtureName)
    let doneItems = fixtureEvents
        .filter { $0["type"]?.stringValue == "response.output_item.done" }
        .compactMap { $0["item"] }
    let expectedShellCalls = doneItems.filter { $0["type"]?.stringValue == "shell_call" }
    let expectedShellOutputs = doneItems.filter { $0["type"]?.stringValue == "shell_call_output" }
    let expectedMessage = try #require(doneItems.first { $0["type"]?.stringValue == "message" })
    let expectedText = fixtureEvents
        .filter { $0["type"]?.stringValue == "response.output_text.delta" }
        .compactMap { $0["delta"]?.stringValue }
        .joined()

    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse(fixtureName))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var sawInputLifecycle = false
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
        tools: openAIResponsesStreamingShellContainerTool()
    )) {
        switch part {
        case .streamStart:
            streamStarted = true
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case .toolInputStart, .toolInputDelta, .toolInputEnd:
            sawInputLifecycle = true
        case let .toolCall(call) where call.name == "shell":
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
    #expect(responseMetadata?.id == "resp_049350089f7281c400698f717727d08191a446ae1621ed9503")
    #expect(responseMetadata?.modelID == "gpt-5.2-2025-12-11")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_771_008_375))
    #expect(sawInputLifecycle == false)

    try #require(toolCalls.count == expectedShellCalls.count)
    for index in expectedShellCalls.indices {
        let expectedCall = expectedShellCalls[index]
        let call = toolCalls[index]
        #expect(call.id == expectedCall["call_id"]?.stringValue)
        #expect(call.name == "shell")
        #expect(call.providerExecuted == true)
        #expect(call.providerMetadata["openai"]?["itemId"]?.stringValue == expectedCall["id"]?.stringValue)
        let input = try decodeJSONBody(Data(call.arguments.utf8))
        #expect(input["action"]?["commands"]?.arrayValue?.compactMap(\.stringValue) == expectedCall["action"]?["commands"]?.arrayValue?.compactMap(\.stringValue))
    }

    try #require(toolResults.count == expectedShellOutputs.count)
    for index in expectedShellOutputs.indices {
        let expectedOutput = expectedShellOutputs[index]
        let result = toolResults[index]
        #expect(result.toolCallID == expectedOutput["call_id"]?.stringValue)
        #expect(result.toolName == "shell")
        let output = try #require(result.result["output"]?.arrayValue)
        #expect(output.count == expectedOutput["output"]?.arrayValue?.count)
        #expect(output[0]["outcome"]?["type"]?.stringValue == expectedOutput["output"]?[0]?["outcome"]?["type"]?.stringValue)
        #expect(output[0]["outcome"]?["exitCode"]?.intValue == expectedOutput["output"]?[0]?["outcome"]?["exit_code"]?.intValue)
        #expect(output[0]["stderr"]?.stringValue == expectedOutput["output"]?[0]?["stderr"]?.stringValue)
        #expect(output[0]["stdout"]?.stringValue == expectedOutput["output"]?[0]?["stdout"]?.stringValue)
    }

    let expectedMessageID = try #require(expectedMessage["id"]?.stringValue)
    #expect(textStarts.map { $0.0 } == [expectedMessageID])
    #expect(textStarts[0].1["openai"]?["itemId"]?.stringValue == expectedMessageID)
    #expect(textDeltas.joined() == expectedText)
    #expect(textEnds.map { $0.0 } == [expectedMessageID])
    #expect(textEnds[0].1["openai"]?["itemId"]?.stringValue == expectedMessageID)

    #expect(finishReason == "stop")
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == "resp_049350089f7281c400698f717727d08191a446ae1621ed9503")
    #expect(finishProviderMetadata["openai"]?["serviceTier"]?.stringValue == "default")
    #expect(finishUsage?.inputTokens == 1501)
    #expect(finishUsage?.inputTokensCacheRead == 1024)
    #expect(finishUsage?.outputTokens == 314)
    #expect(finishUsage?.outputReasoningTokens == 100)
    #expect(finishUsage?.totalTokens == 1815)
}

