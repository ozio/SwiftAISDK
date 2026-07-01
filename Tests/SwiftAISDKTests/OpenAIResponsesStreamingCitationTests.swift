import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesStreamsMixedURLAndFileCitationAnnotationsLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data:{"type":"response.content_part.added","item_id":"msg_123","output_index":0,"content_index":0,"part":{"type":"output_text","text":"","annotations":[]}}

    data:{"type":"response.output_text.annotation.added","item_id":"msg_123","output_index":0,"content_index":0,"annotation_index":0,"annotation":{"type":"url_citation","url":"https://example.com","title":"Example URL","start_index":123,"end_index":234}}

    data:{"type":"response.output_text.annotation.added","item_id":"msg_123","output_index":0,"content_index":0,"annotation_index":1,"annotation":{"type":"file_citation","index":123,"file_id":"file-abc123","filename":"resource1.json"}}

    data:{"type":"response.content_part.done","item_id":"msg_123","output_index":0,"content_index":0,"part":{"type":"output_text","text":"Based on web search and file content.","annotations":[{"type":"url_citation","start_index":0,"end_index":10,"url":"https://example.com","title":"Example URL"},{"type":"file_citation","index":123,"file_id":"file-abc123","filename":"resource1.json"}]}}

    data:{"type":"response.output_item.done","output_index":0,"item":{"id":"msg_123","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Based on web search and file content.","annotations":[{"type":"url_citation","start_index":0,"end_index":10,"url":"https://example.com","title":"Example URL"},{"type":"file_citation","index":123,"file_id":"file-abc123","filename":"resource1.json"}]}]}}

    data:{"type":"response.completed","response":{"id":"resp_123","object":"response","created_at":1234567890,"status":"completed","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-4o","output":[{"id":"msg_123","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Based on web search and file content.","annotations":[{"type":"url_citation","start_index":0,"end_index":10,"url":"https://example.com","title":"Example URL"},{"type":"file_citation","index":123,"file_id":"file-abc123","filename":"resource1.json"}]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":100,"input_tokens_details":{"cached_tokens":0},"output_tokens":50,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":150},"user":null,"metadata":{}}}

    data: [DONE]

    """))

    let capture = try await openAIResponsesCollectCitationStream(
        transport: transport,
        modelID: "gpt-4o"
    )

    #expect(capture.streamStarted)
    #expect(capture.textStarts.isEmpty)
    #expect(capture.textDeltas.isEmpty)
    #expect(capture.sources.count == 2)
    #expect(capture.sources[0].id == "id-0")
    #expect(capture.sources[0].sourceType == "url")
    #expect(capture.sources[0].title == "Example URL")
    #expect(capture.sources[0].url == "https://example.com")
    #expect(capture.sources[1].id == "id-1")
    #expect(capture.sources[1].sourceType == "document")
    #expect(capture.sources[1].title == "resource1.json")
    #expect(capture.sources[1].filename == "resource1.json")
    #expect(capture.sources[1].mediaType == "text/plain")
    #expect(capture.sources[1].providerMetadata["openai"]?["type"]?.stringValue == "file_citation")
    #expect(capture.sources[1].providerMetadata["openai"]?["fileId"]?.stringValue == "file-abc123")
    #expect(capture.sources[1].providerMetadata["openai"]?["index"]?.intValue == 123)

    let textEnd = try #require(capture.textEnds.first)
    #expect(textEnd.0 == "msg_123")
    #expect(textEnd.1["openai"]?["itemId"]?.stringValue == "msg_123")
    #expect(textEnd.1["openai"]?["annotations"]?[0]?["end_index"]?.intValue == 234)
    #expect(textEnd.1["openai"]?["annotations"]?[0]?["start_index"]?.intValue == 123)
    #expect(textEnd.1["openai"]?["annotations"]?[0]?["title"]?.stringValue == "Example URL")
    #expect(textEnd.1["openai"]?["annotations"]?[0]?["type"]?.stringValue == "url_citation")
    #expect(textEnd.1["openai"]?["annotations"]?[0]?["url"]?.stringValue == "https://example.com")
    #expect(textEnd.1["openai"]?["annotations"]?[1]?["file_id"]?.stringValue == "file-abc123")
    #expect(textEnd.1["openai"]?["annotations"]?[1]?["filename"]?.stringValue == "resource1.json")
    #expect(textEnd.1["openai"]?["annotations"]?[1]?["index"]?.intValue == 123)
    #expect(textEnd.1["openai"]?["annotations"]?[1]?["type"]?.stringValue == "file_citation")

    #expect(capture.finishReason == "stop")
    #expect(capture.finishUsage?.inputTokens == 100)
    #expect(capture.finishUsage?.inputTokensCacheRead == 0)
    #expect(capture.finishUsage?.inputTokensNoCache == 100)
    #expect(capture.finishUsage?.outputTokens == 50)
    #expect(capture.finishUsage?.outputReasoningTokens == 0)
    #expect(capture.finishUsage?.outputTextTokens == 50)
    #expect(capture.finishUsage?.totalTokens == 150)
}

@Test func openAIResponsesStreamsFileCitationAnnotationsWithoutOptionalFieldsLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data:{"type":"response.content_part.added","item_id":"msg_456","output_index":0,"content_index":0,"part":{"type":"output_text","text":"","annotations":[]}}

    data:{"type":"response.output_text.annotation.added","item_id":"msg_456","output_index":0,"content_index":0,"annotation_index":0,"annotation":{"type":"file_citation","file_id":"file-YRcoCqn3Fo2K4JgraG","filename":"resource1.json","index":145}}

    data:{"type":"response.output_text.annotation.added","item_id":"msg_456","output_index":0,"content_index":0,"annotation_index":1,"annotation":{"type":"file_citation","file_id":"file-YRcoCqn3Fo2K4JgraG","filename":"resource1.json","index":192}}

    data:{"type":"response.content_part.done","item_id":"msg_456","output_index":0,"content_index":0,"part":{"type":"output_text","text":"Answer for the specified years....","annotations":[{"type":"file_citation","file_id":"file-YRcoCqn3Fo2K4JgraG","filename":"resource1.json","index":145},{"type":"file_citation","file_id":"file-YRcoCqn3Fo2K4JgraG","filename":"resource1.json","index":192}]}}

    data:{"type":"response.output_item.done","output_index":0,"item":{"id":"msg_456","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Answer for the specified years....","annotations":[{"type":"file_citation","file_id":"file-YRcoCqn3Fo2K4JgraG","filename":"resource1.json","index":145},{"type":"file_citation","file_id":"file-YRcoCqn3Fo2K4JgraG","filename":"resource1.json","index":192}]}]}}

    data:{"type":"response.completed","response":{"id":"resp_456","object":"response","created_at":1234567890,"status":"completed","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-5","output":[{"id":"msg_456","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Answer for the specified years....","annotations":[{"type":"file_citation","file_id":"file-YRcoCqn3Fo2K4JgraG","filename":"resource1.json","index":145},{"type":"file_citation","file_id":"file-YRcoCqn3Fo2K4JgraG","filename":"resource1.json","index":192}]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":50,"input_tokens_details":{"cached_tokens":0},"output_tokens":25,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":75},"user":null,"metadata":{}}}

    data: [DONE]

    """))

    let capture = try await openAIResponsesCollectCitationStream(
        transport: transport,
        modelID: "gpt-5"
    )

    #expect(capture.streamStarted)
    #expect(capture.textStarts.isEmpty)
    #expect(capture.textDeltas.isEmpty)
    #expect(capture.sources.count == 2)
    #expect(capture.sources.map(\.id) == ["id-0", "id-1"])
    #expect(capture.sources.map(\.sourceType) == ["document", "document"])
    #expect(capture.sources.map(\.title) == ["resource1.json", "resource1.json"])
    #expect(capture.sources.map(\.filename) == ["resource1.json", "resource1.json"])
    #expect(capture.sources.map(\.mediaType) == ["text/plain", "text/plain"])
    #expect(capture.sources[0].providerMetadata["openai"]?["fileId"]?.stringValue == "file-YRcoCqn3Fo2K4JgraG")
    #expect(capture.sources[0].providerMetadata["openai"]?["index"]?.intValue == 145)
    #expect(capture.sources[1].providerMetadata["openai"]?["fileId"]?.stringValue == "file-YRcoCqn3Fo2K4JgraG")
    #expect(capture.sources[1].providerMetadata["openai"]?["index"]?.intValue == 192)

    let textEnd = try #require(capture.textEnds.first)
    #expect(textEnd.0 == "msg_456")
    #expect(textEnd.1["openai"]?["itemId"]?.stringValue == "msg_456")
    #expect(textEnd.1["openai"]?["annotations"]?[0]?["file_id"]?.stringValue == "file-YRcoCqn3Fo2K4JgraG")
    #expect(textEnd.1["openai"]?["annotations"]?[0]?["filename"]?.stringValue == "resource1.json")
    #expect(textEnd.1["openai"]?["annotations"]?[0]?["index"]?.intValue == 145)
    #expect(textEnd.1["openai"]?["annotations"]?[0]?["type"]?.stringValue == "file_citation")
    #expect(textEnd.1["openai"]?["annotations"]?[1]?["file_id"]?.stringValue == "file-YRcoCqn3Fo2K4JgraG")
    #expect(textEnd.1["openai"]?["annotations"]?[1]?["filename"]?.stringValue == "resource1.json")
    #expect(textEnd.1["openai"]?["annotations"]?[1]?["index"]?.intValue == 192)
    #expect(textEnd.1["openai"]?["annotations"]?[1]?["type"]?.stringValue == "file_citation")

    #expect(capture.finishReason == "stop")
    #expect(capture.finishUsage?.inputTokens == 50)
    #expect(capture.finishUsage?.inputTokensCacheRead == 0)
    #expect(capture.finishUsage?.inputTokensNoCache == 50)
    #expect(capture.finishUsage?.outputTokens == 25)
    #expect(capture.finishUsage?.outputReasoningTokens == 0)
    #expect(capture.finishUsage?.outputTextTokens == 25)
    #expect(capture.finishUsage?.totalTokens == 75)
}

@Test func openAIResponsesStreamsContainerFileCitationAnnotationsLikeUpstream() async throws {
    let messageID = "msg_68c2e7054ae481938354ab3e4e77abad02d3a5742c7ddae9"
    let containerID = "cntr_68c2e6f380d881908a57a82d394434ff02f484f5344062e9"
    let fileID = "cfile_68c2e7084ab48191a67824aa1f4c90f1"
    let filename = "roll2dice_sums_10000.csv"
    let outputText = "Heres a simulation of rolling two fair six-sided dice 10,000 times."

    let transport = RecordingTransport(response: sseResponse("""
    data:{"type":"response.content_part.added","item_id":"\(messageID)","output_index":0,"content_index":0,"part":{"type":"output_text","text":"","annotations":[]}}

    data:{"type":"response.output_text.annotation.added","item_id":"\(messageID)","output_index":0,"content_index":0,"annotation_index":0,"annotation":{"type":"container_file_citation","container_id":"\(containerID)","end_index":465,"file_id":"\(fileID)","filename":"\(filename)","start_index":423}}

    data:{"type":"response.content_part.done","item_id":"\(messageID)","output_index":0,"content_index":0,"part":{"type":"output_text","annotations":[{"type":"container_file_citation","container_id":"\(containerID)","end_index":465,"file_id":"\(fileID)","filename":"\(filename)","start_index":423}],"logprobs":[],"text":"\(outputText)"}}

    data:{"type":"response.output_item.done","output_index":0,"item":{"id":"\(messageID)","type":"message","status":"completed","content":[{"type":"output_text","annotations":[{"type":"container_file_citation","container_id":"\(containerID)","end_index":465,"file_id":"\(fileID)","filename":"\(filename)","start_index":423}],"logprobs":[],"text":"\(outputText)"}],"role":"assistant"}}

    data:{"type":"response.completed","response":{"id":"resp_68c2e6efa238819383d5f52a2c2a3baa02d3a5742c7ddae9","object":"response","created_at":1757603567,"status":"completed","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-5-nano-2025-08-07","output":[{"id":"\(messageID)","type":"message","status":"completed","content":[{"type":"output_text","annotations":[{"type":"container_file_citation","container_id":"\(containerID)","end_index":465,"file_id":"\(fileID)","filename":"\(filename)","start_index":423}],"logprobs":[],"text":"\(outputText)"}],"role":"assistant"}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":20,"input_tokens_details":{"cached_tokens":0},"output_tokens":30,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":50},"user":null,"metadata":{}}}

    data: [DONE]

    """))

    let capture = try await openAIResponsesCollectCitationStream(
        transport: transport,
        modelID: "gpt-5-nano-2025-08-07"
    )

    #expect(capture.streamStarted)
    #expect(capture.textStarts.isEmpty)
    #expect(capture.textDeltas.isEmpty)
    let source = try #require(capture.sources.first)
    #expect(source.id == "id-0")
    #expect(source.sourceType == "document")
    #expect(source.title == filename)
    #expect(source.filename == filename)
    #expect(source.mediaType == "text/plain")
    #expect(source.providerMetadata["openai"]?["type"]?.stringValue == "container_file_citation")
    #expect(source.providerMetadata["openai"]?["containerId"]?.stringValue == containerID)
    #expect(source.providerMetadata["openai"]?["fileId"]?.stringValue == fileID)
    #expect(source.providerMetadata["openai"]?["index"] == nil)

    let textEnd = try #require(capture.textEnds.first)
    #expect(textEnd.0 == messageID)
    #expect(textEnd.1["openai"]?["itemId"]?.stringValue == messageID)
    #expect(textEnd.1["openai"]?["annotations"]?[0]?["type"]?.stringValue == "container_file_citation")
    #expect(textEnd.1["openai"]?["annotations"]?[0]?["container_id"]?.stringValue == containerID)
    #expect(textEnd.1["openai"]?["annotations"]?[0]?["file_id"]?.stringValue == fileID)
    #expect(textEnd.1["openai"]?["annotations"]?[0]?["filename"]?.stringValue == filename)
    #expect(textEnd.1["openai"]?["annotations"]?[0]?["start_index"]?.intValue == 423)
    #expect(textEnd.1["openai"]?["annotations"]?[0]?["end_index"]?.intValue == 465)

    #expect(capture.finishReason == "stop")
    #expect(capture.finishUsage?.inputTokens == 20)
    #expect(capture.finishUsage?.inputTokensCacheRead == 0)
    #expect(capture.finishUsage?.inputTokensNoCache == 20)
    #expect(capture.finishUsage?.outputTokens == 30)
    #expect(capture.finishUsage?.outputReasoningTokens == 0)
    #expect(capture.finishUsage?.outputTextTokens == 30)
    #expect(capture.finishUsage?.totalTokens == 50)
}

@Test func openAIResponsesStreamsFilePathAnnotationsLikeUpstream() async throws {
    let messageID = "msg_68c2e7054ae481938354ab3e4e77abad02d3a5742c7ddae9"
    let fileID = "cfile_68c2e7084ab48191a67824aa1f4c90f1"
    let outputText = "Heres a simulation of rolling two fair six-sided dice 10,000 times."

    let transport = RecordingTransport(response: sseResponse("""
    data:{"type":"response.content_part.added","item_id":"\(messageID)","output_index":0,"content_index":0,"part":{"type":"output_text","text":"","annotations":[]}}

    data:{"type":"response.output_text.annotation.added","item_id":"\(messageID)","output_index":0,"content_index":0,"annotation_index":0,"annotation":{"type":"file_path","file_id":"\(fileID)","index":123}}

    data:{"type":"response.content_part.done","item_id":"\(messageID)","output_index":0,"content_index":0,"part":{"type":"output_text","annotations":[{"type":"file_path","file_id":"\(fileID)","index":123}],"logprobs":[],"text":"\(outputText)"}}

    data:{"type":"response.output_item.done","output_index":0,"item":{"id":"\(messageID)","type":"message","status":"completed","content":[{"type":"output_text","annotations":[{"type":"file_path","file_id":"\(fileID)"}],"logprobs":[],"text":"\(outputText)"}],"role":"assistant"}}

    data:{"type":"response.completed","response":{"id":"resp_68c2e6efa238819383d5f52a2c2a3baa02d3a5742c7ddae9","object":"response","created_at":1757603567,"status":"completed","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-5-nano-2025-08-07","output":[{"id":"\(messageID)","type":"message","status":"completed","content":[{"type":"output_text","annotations":[{"type":"file_path","file_id":"\(fileID)"}],"logprobs":[],"text":"\(outputText)"}],"role":"assistant"}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":20,"input_tokens_details":{"cached_tokens":0},"output_tokens":30,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":50},"user":null,"metadata":{}}}

    data: [DONE]

    """))

    let capture = try await openAIResponsesCollectCitationStream(
        transport: transport,
        modelID: "gpt-5"
    )

    #expect(capture.streamStarted)
    #expect(capture.textStarts.isEmpty)
    #expect(capture.textDeltas.isEmpty)
    let source = try #require(capture.sources.first)
    #expect(source.id == "id-0")
    #expect(source.sourceType == "document")
    #expect(source.title == fileID)
    #expect(source.filename == fileID)
    #expect(source.mediaType == "application/octet-stream")
    #expect(source.providerMetadata["openai"]?["type"]?.stringValue == "file_path")
    #expect(source.providerMetadata["openai"]?["fileId"]?.stringValue == fileID)
    #expect(source.providerMetadata["openai"]?["index"]?.intValue == 123)

    let textEnd = try #require(capture.textEnds.first)
    #expect(textEnd.0 == messageID)
    #expect(textEnd.1["openai"]?["itemId"]?.stringValue == messageID)
    #expect(textEnd.1["openai"]?["annotations"]?[0]?["type"]?.stringValue == "file_path")
    #expect(textEnd.1["openai"]?["annotations"]?[0]?["file_id"]?.stringValue == fileID)
    #expect(textEnd.1["openai"]?["annotations"]?[0]?["index"]?.intValue == 123)

    #expect(capture.finishReason == "stop")
    #expect(capture.finishUsage?.inputTokens == 20)
    #expect(capture.finishUsage?.inputTokensCacheRead == 0)
    #expect(capture.finishUsage?.inputTokensNoCache == 20)
    #expect(capture.finishUsage?.outputTokens == 30)
    #expect(capture.finishUsage?.outputReasoningTokens == 0)
    #expect(capture.finishUsage?.outputTextTokens == 30)
    #expect(capture.finishUsage?.totalTokens == 50)
}

private struct OpenAIResponsesCitationStreamCapture {
    var streamStarted = false
    var textStarts: [(String, [String: JSONValue])] = []
    var textDeltas: [(String, String)] = []
    var textEnds: [(String, [String: JSONValue])] = []
    var sources: [AISource] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
}

private func openAIResponsesCollectCitationStream(
    transport: RecordingTransport,
    modelID: String
) async throws -> OpenAIResponsesCitationStreamCapture {
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel(modelID)
    var capture = OpenAIResponsesCitationStreamCapture()

    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hello")],
        includeRawChunks: false
    )) {
        switch part {
        case .streamStart:
            capture.streamStarted = true
        case let .textStart(id, metadata):
            capture.textStarts.append((id, metadata))
        case let .textDeltaPart(id, delta, _):
            capture.textDeltas.append((id, delta))
        case let .textEnd(id, metadata):
            capture.textEnds.append((id, metadata))
        case let .source(source):
            capture.sources.append(source)
        case let .finish(reason, usage):
            capture.finishReason = reason
            capture.finishUsage = usage
        case let .finishMetadata(reason, usage, _):
            capture.finishReason = reason
            capture.finishUsage = usage
        default:
            break
        }
    }

    return capture
}
