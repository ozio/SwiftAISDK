import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesStreamsCodeInterpreterResultsWithAnnotationsLikeUpstream() async throws {
    let fixtureName = "openai-code-interpreter-tool.1.chunks.txt"
    let fixtureEvents = try openAIResponsesChunksFixtureEvents(fixtureName)
    let completed = try #require(fixtureEvents.first { $0["type"]?.stringValue == "response.completed" })
    let expectedMessage = try #require(completed["response"]?["output"]?.arrayValue?.first { $0["type"]?.stringValue == "message" })
    let expectedText = try #require(expectedMessage["content"]?[0]?["text"]?.stringValue)

    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse(fixtureName))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var reasoningStarts: [(String, [String: JSONValue])] = []
    var reasoningEnds: [(String, [String: JSONValue])] = []
    var toolLifecycle: [String] = []
    var toolInputDeltas: [String: String] = [:]
    var toolCalls: [AIToolCall] = []
    var toolResults: [AIToolResult] = []
    var textStarts: [(String, [String: JSONValue])] = []
    var textDeltas: [String] = []
    var textEnds: [(String, [String: JSONValue])] = []
    var sources: [AISource] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishProviderMetadata: [String: JSONValue] = [:]

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesStreamingCodeInterpreterTool()
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
        case let .toolInputStart(id, name, providerExecuted, _, _, _):
            toolLifecycle.append("start:\(id):\(name):\(providerExecuted)")
        case let .toolInputDelta(id, delta, _):
            toolLifecycle.append("delta:\(id)")
            toolInputDeltas[id, default: ""] += delta
        case let .toolInputEnd(id, _):
            toolLifecycle.append("end:\(id)")
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
        case let .source(source):
            sources.append(source)
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
    #expect(responseMetadata?.id == "resp_68c2e6efa238819383d5f52a2c2a3baa02d3a5742c7ddae9")
    #expect(responseMetadata?.modelID == "gpt-5-nano-2025-08-07")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_757_603_567))

    #expect(reasoningStarts.map { $0.0 } == [
        "rs_68c2e6f40ba48193a1c27abf31130e7e02d3a5742c7ddae9:0",
        "rs_68c2e6fcb52881938f21c45741216ac002d3a5742c7ddae9:0",
        "rs_68c2e6fff1808193a78d43410a1feb4802d3a5742c7ddae9:0",
        "rs_68c2e703d114819383c5da260649c7ce02d3a5742c7ddae9:0"
    ])
    #expect(reasoningEnds.map { $0.0 } == reasoningStarts.map { $0.0 })
    #expect(reasoningStarts[0].1["openai"]?["itemId"]?.stringValue == "rs_68c2e6f40ba48193a1c27abf31130e7e02d3a5742c7ddae9")
    #expect(reasoningStarts[0].1["openai"]?["reasoningEncryptedContent"] == .null)

    #expect(toolCalls.map(\.id) == [
        "ci_68c2e6f7b72c8193ba1f552552c8dc9202d3a5742c7ddae9",
        "ci_68c2e6fd57948193aa93df6bdb00a86d02d3a5742c7ddae9",
        "ci_68c2e701a23081939c93b6fb5bb952d302d3a5742c7ddae9"
    ])
    #expect(toolCalls.map(\.name) == Array(repeating: "codeExecution", count: 3))
    #expect(toolResults.map(\.toolName) == Array(repeating: "codeExecution", count: 3))
    #expect(toolCalls.allSatisfy { $0.providerExecuted })
    #expect(toolResults.map(\.toolCallID) == toolCalls.map(\.id))
    #expect(toolLifecycle.first == "start:ci_68c2e6f7b72c8193ba1f552552c8dc9202d3a5742c7ddae9:codeExecution:true")
    #expect(toolLifecycle.contains("end:ci_68c2e6f7b72c8193ba1f552552c8dc9202d3a5742c7ddae9"))
    #expect(toolLifecycle.contains("end:ci_68c2e6fd57948193aa93df6bdb00a86d02d3a5742c7ddae9"))
    #expect(toolLifecycle.contains("end:ci_68c2e701a23081939c93b6fb5bb952d302d3a5742c7ddae9"))

    let firstInput = try decodeJSONBody(Data(try #require(toolInputDeltas[toolCalls[0].id]).utf8))
    #expect(firstInput["containerId"]?.stringValue == "cntr_68c2e6f380d881908a57a82d394434ff02f484f5344062e9")
    #expect(firstInput["code"]?.stringValue?.hasPrefix("import random, math\nN=10000") == true)
    let secondInput = try decodeJSONBody(Data(try #require(toolInputDeltas[toolCalls[1].id]).utf8))
    #expect(secondInput["code"]?.stringValue?.contains("roll2dice_sums_10000.csv") == true)
    let thirdInput = try decodeJSONBody(Data(try #require(toolInputDeltas[toolCalls[2].id]).utf8))
    #expect(thirdInput["code"]?.stringValue == "sums[:20]\n")

    #expect(toolResults[0].result["outputs"]?[0]?["logs"]?.stringValue == "(2, 12, 69868, 6.9868)")
    #expect(toolResults[1].result["outputs"]?[0]?["logs"]?.stringValue == "(PosixPath('/mnt/data/roll2dice_sums_10000.csv'), True, 10000)")
    #expect(toolResults[2].result["outputs"]?[0]?["logs"]?.stringValue == "[6, 7, 2, 5, 5, 11, 4, 8, 10, 7, 5, 8, 8, 7, 10, 8, 9, 5, 4, 7]")

    #expect(textStarts.map { $0.0 } == ["msg_68c2e7054ae481938354ab3e4e77abad02d3a5742c7ddae9"])
    #expect(textDeltas.joined() == expectedText)
    #expect(textEnds.map { $0.0 } == ["msg_68c2e7054ae481938354ab3e4e77abad02d3a5742c7ddae9"])
    #expect(textEnds[0].1["openai"]?["annotations"]?[0]?["type"]?.stringValue == "container_file_citation")

    #expect(sources.count == 1)
    let source = try #require(sources.first)
    #expect(source.id == "id-0")
    #expect(source.sourceType == "document")
    #expect(source.title == "roll2dice_sums_10000.csv")
    #expect(source.filename == "roll2dice_sums_10000.csv")
    #expect(source.mediaType == "text/plain")
    #expect(source.providerMetadata["openai"]?["type"]?.stringValue == "container_file_citation")
    #expect(source.providerMetadata["openai"]?["fileId"]?.stringValue == "cfile_68c2e7084ab48191a67824aa1f4c90f1")
    #expect(source.providerMetadata["openai"]?["containerId"]?.stringValue == "cntr_68c2e6f380d881908a57a82d394434ff02f484f5344062e9")

    #expect(finishReason == "stop")
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == "resp_68c2e6efa238819383d5f52a2c2a3baa02d3a5742c7ddae9")
    #expect(finishProviderMetadata["openai"]?["serviceTier"]?.stringValue == "default")
    #expect(finishUsage?.inputTokens == 6_047)
    #expect(finishUsage?.inputTokensCacheRead == 2_944)
    #expect(finishUsage?.outputTokens == 1_623)
    #expect(finishUsage?.outputReasoningTokens == 1_408)
    #expect(finishUsage?.totalTokens == 7_670)
}

@Test func openAIResponsesStreamsImageGenerationResultsLikeUpstream() async throws {
    let fixtureName = "openai-image-generation-tool.1.chunks.txt"
    let fixtureEvents = try openAIResponsesChunksFixtureEvents(fixtureName)
    let completed = try #require(fixtureEvents.first { $0["type"]?.stringValue == "response.completed" })
    let expectedImage = try #require(completed["response"]?["output"]?.arrayValue?.first { $0["type"]?.stringValue == "image_generation_call" }?["result"]?.stringValue)

    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse(fixtureName))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var reasoningStarts: [(String, [String: JSONValue])] = []
    var reasoningEnds: [(String, [String: JSONValue])] = []
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
        tools: openAIResponsesStreamingImageGenerationTool()
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
        case let .toolCall(call) where call.name == "generateImage":
            toolCall = call
        case let .toolResult(result) where result.toolName == "generateImage":
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
    #expect(responseMetadata?.id == "resp_0df93c0bb83a72f20068c979db26ac819e8b5a444fad3f0d7f")
    #expect(responseMetadata?.modelID == "gpt-5-2025-08-07")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_758_034_395))

    #expect(reasoningStarts.map { $0.0 } == ["rs_0df93c0bb83a72f20068c979db90b4819e94cedbfda2d49af6:0"])
    #expect(reasoningEnds.map { $0.0 } == reasoningStarts.map { $0.0 })
    #expect(reasoningStarts[0].1["openai"]?["itemId"]?.stringValue == "rs_0df93c0bb83a72f20068c979db90b4819e94cedbfda2d49af6")
    #expect(reasoningStarts[0].1["openai"]?["reasoningEncryptedContent"] == .null)

    #expect(sawInputLifecycle == false)
    #expect(toolCall?.id == "ig_0df93c0bb83a72f20068c979f589c0819e9f0fc2d1a27aa1b8")
    #expect(toolCall?.name == "generateImage")
    #expect(toolCall?.arguments == "{}")
    #expect(toolCall?.providerExecuted == true)
    #expect(toolResults.count == 2)
    #expect(toolResults.map(\.toolCallID) == Array(repeating: "ig_0df93c0bb83a72f20068c979f589c0819e9f0fc2d1a27aa1b8", count: 2))
    #expect(toolResults.map(\.toolName) == Array(repeating: "generateImage", count: 2))
    #expect(toolResults[0].preliminary == true)
    #expect(toolResults[0].result["result"]?.stringValue == expectedImage)
    #expect(toolResults[1].preliminary == false)
    #expect(toolResults[1].result["result"]?.stringValue == expectedImage)

    #expect(textStarts.map { $0.0 } == ["msg_0df93c0bb83a72f20068c97a0b36f4819ea5906451007f95e2"])
    #expect(textStarts[0].1["openai"]?["itemId"]?.stringValue == "msg_0df93c0bb83a72f20068c97a0b36f4819ea5906451007f95e2")
    #expect(textDeltas.isEmpty)
    #expect(textEnds.map { $0.0 } == ["msg_0df93c0bb83a72f20068c97a0b36f4819ea5906451007f95e2"])
    #expect(textEnds[0].1["openai"]?["itemId"]?.stringValue == "msg_0df93c0bb83a72f20068c97a0b36f4819ea5906451007f95e2")

    #expect(finishReason == "stop")
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == "resp_0df93c0bb83a72f20068c979db26ac819e8b5a444fad3f0d7f")
    #expect(finishProviderMetadata["openai"]?["serviceTier"]?.stringValue == "default")
    #expect(finishUsage?.inputTokens == 2_941)
    #expect(finishUsage?.inputTokensCacheRead == 1_920)
    #expect(finishUsage?.outputTokens == 1_249)
    #expect(finishUsage?.outputReasoningTokens == 1_024)
    #expect(finishUsage?.totalTokens == 4_190)
}

