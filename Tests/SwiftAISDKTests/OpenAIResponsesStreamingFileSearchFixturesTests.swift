import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesStreamsFileSearchResultsWithoutResultsIncludeLikeUpstream() async throws {
    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse("openai-file-search-tool.1.chunks.txt"))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var reasoningStarts: [(String, [String: JSONValue])] = []
    var reasoningEnds: [(String, [String: JSONValue])] = []
    var toolCall: AIToolCall?
    var toolResult: AIToolResult?
    var textDeltas: [String] = []
    var sources: [AISource] = []
    var finishReason: String?
    var finishUsage: TokenUsage?

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesStreamingFileSearchTool()
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
        case let .toolCall(call) where call.name == "fileSearch":
            toolCall = call
        case let .toolResult(result) where result.toolName == "fileSearch":
            toolResult = result
        case let .textDeltaPart(_, delta, _):
            textDeltas.append(delta)
        case let .source(source):
            sources.append(source)
        case let .finish(reason, usage):
            finishReason = reason
            finishUsage = usage
        case let .finishMetadata(reason, usage, _):
            finishReason = reason
            finishUsage = usage
        default:
            break
        }
    }

    #expect(streamStarted)
    #expect(responseMetadata?.id == "resp_0459517ad68504ad0068cabfba22b88192836339640e9a765a")
    #expect(responseMetadata?.modelID == "gpt-5-mini-2025-08-07")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_758_117_818))
    #expect(reasoningStarts.map { $0.0 } == [
        "rs_0459517ad68504ad0068cabfba951881929654a05214361b35:0",
        "rs_0459517ad68504ad0068cabfbf337881929cf5266be7a008a9:0"
    ])
    #expect(reasoningEnds.map { $0.0 } == reasoningStarts.map { $0.0 })
    let firstReasoningStart = try #require(reasoningStarts.first)
    #expect(firstReasoningStart.1["openai"]?["itemId"]?.stringValue == "rs_0459517ad68504ad0068cabfba951881929654a05214361b35")
    #expect(toolCall?.id == "fs_0459517ad68504ad0068cabfbd76888192a5dc4475fadabf8a")
    #expect(toolCall?.name == "fileSearch")
    #expect(toolCall?.arguments == "{}")
    #expect(toolCall?.providerExecuted == true)
    #expect(toolResult?.toolCallID == "fs_0459517ad68504ad0068cabfbd76888192a5dc4475fadabf8a")
    #expect(toolResult?.toolName == "fileSearch")
    #expect(toolResult?.result["queries"]?[0]?.stringValue == "What is an embedding model according to this document?")
    #expect(toolResult?.result["queries"]?[2]?.stringValue == "definition of embedding model")
    #expect(toolResult?.result["results"] == .null)
    #expect(textDeltas.joined().contains("embedding model converts complex data"))
    #expect(sources.map(\.id) == ["id-0", "id-1"])
    let firstSource = try #require(sources.first)
    let secondSource = try #require(sources.dropFirst().first)
    #expect(firstSource.sourceType == "document")
    #expect(firstSource.title == "ai.pdf")
    #expect(firstSource.filename == "ai.pdf")
    #expect(firstSource.mediaType == "text/plain")
    #expect(firstSource.providerMetadata["openai"]?["fileId"]?.stringValue == "file-Ebzhf8H4DPGPr9pUhr7n7v")
    #expect(firstSource.providerMetadata["openai"]?["index"]?.intValue == 154)
    #expect(secondSource.providerMetadata["openai"]?["index"]?.intValue == 382)
    #expect(finishReason == "stop")
    #expect(finishUsage?.inputTokens == 3_737)
    #expect(finishUsage?.inputTokensCacheRead == 2_304)
    #expect(finishUsage?.outputTokens == 621)
    #expect(finishUsage?.outputReasoningTokens == 512)
    #expect(finishUsage?.totalTokens == 4_358)
}

@Test func openAIResponsesStreamsFileSearchResultsWithResultsIncludeLikeUpstream() async throws {
    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse("openai-file-search-tool.2.chunks.txt"))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    var responseMetadata: AIResponseMetadata?
    var toolCall: AIToolCall?
    var toolResult: AIToolResult?
    var textDeltas: [String] = []
    var sources: [AISource] = []
    var finishUsage: TokenUsage?

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesStreamingFileSearchTool(),
        providerOptions: ["openai": ["include": ["file_search_call.results"]]]
    )) {
        switch part {
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .toolCall(call) where call.name == "fileSearch":
            toolCall = call
        case let .toolResult(result) where result.toolName == "fileSearch":
            toolResult = result
        case let .textDeltaPart(_, delta, _):
            textDeltas.append(delta)
        case let .source(source):
            sources.append(source)
        case let .finish(_, usage):
            finishUsage = usage
        case let .finishMetadata(_, usage, _):
            finishUsage = usage
        default:
            break
        }
    }

    #expect(responseMetadata?.id == "resp_06456cb9918b63780068cacd710b0881a1b00b5fca56e7100b")
    #expect(responseMetadata?.modelID == "gpt-5-mini-2025-08-07")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_758_121_329))
    #expect(toolCall?.id == "fs_06456cb9918b63780068cacd74a1dc81a1bf68dd57f140b4b6")
    #expect(toolCall?.name == "fileSearch")
    #expect(toolCall?.arguments == "{}")
    #expect(toolCall?.providerExecuted == true)
    #expect(toolResult?.toolCallID == "fs_06456cb9918b63780068cacd74a1dc81a1bf68dd57f140b4b6")
    #expect(toolResult?.toolName == "fileSearch")
    #expect(toolResult?.result["queries"]?[0]?.stringValue == "What is an embedding model according to this document?")
    #expect(toolResult?.result["queries"]?[2]?.stringValue == "How does the document define an embedding model?")
    #expect(toolResult?.result["results"]?[0]?["attributes"]?.objectValue?.isEmpty == true)
    #expect(toolResult?.result["results"]?[0]?["fileId"]?.stringValue == "file-Ebzhf8H4DPGPr9pUhr7n7v")
    #expect(toolResult?.result["results"]?[0]?["filename"]?.stringValue == "ai.pdf")
    #expect(toolResult?.result["results"]?[0]?["score"]?.doubleValue == 0.9312)
    #expect(textDeltas.joined().contains("The document defines an embedding model"))
    #expect(sources.count == 1)
    let source = try #require(sources.first)
    #expect(source.id == "id-0")
    #expect(source.sourceType == "document")
    #expect(source.title == "ai.pdf")
    #expect(source.providerMetadata["openai"]?["fileId"]?.stringValue == "file-Ebzhf8H4DPGPr9pUhr7n7v")
    #expect(source.providerMetadata["openai"]?["index"]?.intValue == 379)
    #expect(finishUsage?.inputTokens == 3_748)
    #expect(finishUsage?.inputTokensCacheRead == 2_304)
    #expect(finishUsage?.outputTokens == 543)
    #expect(finishUsage?.outputReasoningTokens == 448)
    #expect(finishUsage?.totalTokens == 4_291)
}

