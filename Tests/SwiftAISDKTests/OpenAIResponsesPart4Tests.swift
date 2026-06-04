import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesStreamsReasoningLifecycleProviderMetadataLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"rs_reasoning","type":"reasoning","encrypted_content":"encrypted_reasoning_data_initial"}}

    data: {"type":"response.reasoning_summary_part.added","item_id":"rs_reasoning","summary_index":0}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_reasoning","summary_index":0,"delta":"first thought"}

    data: {"type":"response.reasoning_summary_part.done","item_id":"rs_reasoning","summary_index":0}

    data: {"type":"response.reasoning_summary_part.added","item_id":"rs_reasoning","summary_index":1}

    data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_reasoning","summary_index":1,"delta":"second thought"}

    data: {"type":"response.reasoning_summary_part.done","item_id":"rs_reasoning","summary_index":1}

    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"rs_reasoning","type":"reasoning","encrypted_content":"encrypted_reasoning_data_final"}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("o3-mini")

    var reasoningStarts: [(String, [String: JSONValue])] = []
    var reasoningDeltas: [(String, String, [String: JSONValue])] = []
    var reasoningEnds: [(String, [String: JSONValue])] = []
    var legacyReasoning: [String] = []
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: ["store": false]
    )) {
        switch part {
        case let .reasoningStart(id, metadata):
            reasoningStarts.append((id, metadata))
        case let .reasoningDelta(delta):
            legacyReasoning.append(delta)
        case let .reasoningDeltaPart(id, delta, metadata):
            reasoningDeltas.append((id, delta, metadata))
        case let .reasoningEnd(id, metadata):
            reasoningEnds.append((id, metadata))
        default:
            break
        }
    }

    #expect(legacyReasoning == ["first thought", "second thought"])
    #expect(reasoningStarts.map { $0.0 } == ["rs_reasoning:0", "rs_reasoning:1"])
    #expect(reasoningDeltas.map { $0.0 } == ["rs_reasoning:0", "rs_reasoning:1"])
    #expect(reasoningDeltas.map { $0.1 } == ["first thought", "second thought"])
    #expect(reasoningEnds.map { $0.0 } == ["rs_reasoning:0", "rs_reasoning:1"])
    #expect(reasoningStarts[0].1["openai"]?["itemId"]?.stringValue == "rs_reasoning")
    #expect(reasoningStarts[0].1["openai"]?["reasoningEncryptedContent"]?.stringValue == "encrypted_reasoning_data_initial")
    #expect(reasoningDeltas[0].2["openai"]?["itemId"]?.stringValue == "rs_reasoning")
    #expect(reasoningDeltas[0].2["openai"]?["reasoningEncryptedContent"] == nil)
    #expect(reasoningEnds[0].1["openai"]?["itemId"]?.stringValue == "rs_reasoning")
    #expect(reasoningEnds[0].1["openai"]?["reasoningEncryptedContent"] == nil)
    #expect(reasoningStarts[1].1["openai"]?["reasoningEncryptedContent"]?.stringValue == "encrypted_reasoning_data_initial")
    #expect(reasoningEnds[1].1["openai"]?["reasoningEncryptedContent"]?.stringValue == "encrypted_reasoning_data_final")
}
@Test func openAIResponsesStreamsAnnotationSourcesAndTextMetadataLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"msg_annotations","type":"message","status":"in_progress","content":[],"role":"assistant"}}

    data: {"type":"response.output_text.annotation.added","item_id":"msg_annotations","output_index":0,"content_index":0,"annotation_index":0,"annotation":{"type":"url_citation","url":"https://example.com","title":"Example URL","start_index":0,"end_index":10}}

    data: {"type":"response.output_text.annotation.added","item_id":"msg_annotations","output_index":0,"content_index":0,"annotation_index":1,"annotation":{"type":"file_citation","file_id":"file-abc123","filename":"resource1.json","index":123}}

    data: {"type":"response.output_text.annotation.added","item_id":"msg_annotations","output_index":0,"content_index":0,"annotation_index":2,"annotation":{"type":"container_file_citation","container_id":"cntr-1","file_id":"cfile-1","filename":"rolls.csv","start_index":42,"end_index":51}}

    data: {"type":"response.output_text.annotation.added","item_id":"msg_annotations","output_index":0,"content_index":0,"annotation_index":3,"annotation":{"type":"file_path","file_id":"cfile-path","index":7}}

    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"msg_annotations","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Based on sources.","annotations":[]}]}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    var sources: [AISource] = []
    var textEndMetadata: [String: JSONValue] = [:]
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .source(source):
            sources.append(source)
        case let .textEnd(id, metadata) where id == "msg_annotations":
            textEndMetadata = metadata
        default:
            break
        }
    }

    #expect(sources.map(\.sourceType) == ["url", "document", "document", "document"])
    #expect(sources[0].url == "https://example.com")
    #expect(sources[1].filename == "resource1.json")
    #expect(sources[1].providerMetadata["openai"]?["type"]?.stringValue == "file_citation")
    #expect(sources[1].providerMetadata["openai"]?["fileId"]?.stringValue == "file-abc123")
    #expect(sources[1].providerMetadata["openai"]?["index"]?.intValue == 123)
    #expect(sources[2].providerMetadata["openai"]?["containerId"]?.stringValue == "cntr-1")
    #expect(sources[3].mediaType == "application/octet-stream")
    #expect(sources[3].filename == "cfile-path")
    let annotations = try #require(textEndMetadata["openai"]?["annotations"]?.arrayValue)
    #expect(textEndMetadata["openai"]?["itemId"]?.stringValue == "msg_annotations")
    #expect(annotations.count == 4)
    #expect(annotations[0]["type"]?.stringValue == "url_citation")
    #expect(annotations[1]["type"]?.stringValue == "file_citation")
    #expect(annotations[2]["type"]?.stringValue == "container_file_citation")
    #expect(annotations[3]["type"]?.stringValue == "file_path")
}
@Test func openAIResponsesStreamsCompactionCustomPartLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"cmp_123","type":"compaction","encrypted_content":"encrypted_compaction"}}

    data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2")

    var customParts: [(JSONValue, [String: JSONValue])] = []
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Compact context.")])) {
        if case let .custom(value, metadata) = part {
            customParts.append((value, metadata))
        }
    }

    let custom = try #require(customParts.first)
    #expect(custom.0["kind"]?.stringValue == "openai.compaction")
    #expect(custom.1["openai"]?["type"]?.stringValue == "compaction")
    #expect(custom.1["openai"]?["itemId"]?.stringValue == "cmp_123")
    #expect(custom.1["openai"]?["encryptedContent"]?.stringValue == "encrypted_compaction")
}
@Test func openAIResponsesStreamMapsIncompleteFinishReason() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_text.delta","delta":"partial"}

    data: {"type":"response.incomplete","response":{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    var text: [String] = []
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textDelta(delta):
            text.append(delta)
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(text == ["partial"])
    #expect(finishReason == "length")
    #expect(totalTokens == 3)
}
