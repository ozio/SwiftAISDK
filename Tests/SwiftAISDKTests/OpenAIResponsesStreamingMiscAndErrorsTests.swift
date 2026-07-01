import Foundation
import Testing
@testable import SwiftAISDK

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
@Test func openAIResponsesSendsFinishReasonForIncompleteResponseLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.created","response":{"id":"resp_67c9a81b6a048190a9ee441c5755a4e8","object":"response","created_at":1741269019,"status":"in_progress","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-4o-2024-07-18","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0.3,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data: {"type":"response.in_progress","response":{"id":"resp_67c9a81b6a048190a9ee441c5755a4e8","object":"response","created_at":1741269019,"status":"in_progress","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-4o-2024-07-18","output":[],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0.3,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":null,"user":null,"metadata":{}}}

    data: {"type":"response.output_item.added","output_index":0,"item":{"id":"msg_67c9a81dea8c8190b79651a2b3adf91e","type":"message","status":"in_progress","role":"assistant","content":[]}}

    data: {"type":"response.content_part.added","item_id":"msg_67c9a81dea8c8190b79651a2b3adf91e","output_index":0,"content_index":0,"part":{"type":"output_text","text":"","annotations":[]}}

    data: {"type":"response.output_text.delta","item_id":"msg_67c9a81dea8c8190b79651a2b3adf91e","output_index":0,"content_index":0,"delta":"Hello,"}

    data: {"type":"response.output_text.done","item_id":"msg_67c9a8787f4c8190b49c858d4c1cf20c","output_index":0,"content_index":0,"text":"Hello,!"}

    data: {"type":"response.content_part.done","item_id":"msg_67c9a8787f4c8190b49c858d4c1cf20c","output_index":0,"content_index":0,"part":{"type":"output_text","text":"Hello,","annotations":[]}}

    data: {"type":"response.output_item.done","output_index":0,"item":{"id":"msg_67c9a8787f4c8190b49c858d4c1cf20c","type":"message","status":"incomplete","role":"assistant","content":[{"type":"output_text","text":"Hello,","annotations":[]}]}}

    data: {"type":"response.incomplete","response":{"id":"resp_67cadb40a0708190ac2763c0b6960f6f","object":"response","created_at":1741347648,"status":"incomplete","error":null,"incomplete_details":{"reason":"max_output_tokens"},"instructions":null,"max_output_tokens":100,"model":"gpt-4o-2024-07-18","output":[{"type":"message","id":"msg_67cadb410ccc81909fe1d8f427b9cf02","status":"incomplete","role":"assistant","content":[{"type":"output_text","text":"Hello,","annotations":[]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":0,"input_tokens_details":{"cached_tokens":0},"output_tokens":0,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":0},"user":null,"metadata":{}}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    var streamStarted = false
    var responseMetadata: AIResponseMetadata?
    var textStarts: [(String, [String: JSONValue])] = []
    var textDeltas: [(String, String)] = []
    var textEnds: [(String, [String: JSONValue])] = []
    var finishReason: String?
    var finishUsage: TokenUsage?
    var finishProviderMetadata: [String: JSONValue] = [:]
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case .streamStart:
            streamStarted = true
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .textStart(id, metadata):
            textStarts.append((id, metadata))
        case let .textDeltaPart(id, delta, _):
            textDeltas.append((id, delta))
        case let .textEnd(id, metadata):
            textEnds.append((id, metadata))
        case let .finishMetadata(reason, usage, providerMetadata):
            finishReason = reason
            finishUsage = usage
            finishProviderMetadata = providerMetadata
        default:
            break
        }
    }

    #expect(streamStarted)
    #expect(responseMetadata?.id == "resp_67c9a81b6a048190a9ee441c5755a4e8")
    #expect(responseMetadata?.modelID == "gpt-4o-2024-07-18")
    #expect(responseMetadata?.timestamp == Date(timeIntervalSince1970: 1_741_269_019))
    #expect(textStarts.count == 1)
    #expect(textStarts[0].0 == "msg_67c9a81dea8c8190b79651a2b3adf91e")
    #expect(textStarts[0].1["openai"]?["itemId"]?.stringValue == "msg_67c9a81dea8c8190b79651a2b3adf91e")
    #expect(textDeltas.map { $0.0 } == ["msg_67c9a81dea8c8190b79651a2b3adf91e"])
    #expect(textDeltas.map { $0.1 } == ["Hello,"])
    #expect(textEnds.count == 1)
    #expect(textEnds[0].0 == "msg_67c9a8787f4c8190b49c858d4c1cf20c")
    #expect(textEnds[0].1["openai"]?["itemId"]?.stringValue == "msg_67c9a8787f4c8190b49c858d4c1cf20c")
    #expect(finishReason == "length")
    #expect(finishProviderMetadata["openai"]?["responseId"]?.stringValue == "resp_67c9a81b6a048190a9ee441c5755a4e8")
    #expect(finishUsage?.inputTokens == 0)
    #expect(finishUsage?.inputTokensCacheRead == 0)
    #expect(finishUsage?.inputTokensNoCache == 0)
    #expect(finishUsage?.outputTokens == 0)
    #expect(finishUsage?.outputReasoningTokens == 0)
    #expect(finishUsage?.outputTextTokens == 0)
    #expect(finishUsage?.totalTokens == 0)
}

@Test func openAIResponsesStreamExposesLateFailedIncompleteReasonLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.created","sequence_number":0,"response":{"id":"resp_failed_with_reason","created_at":1741269019,"model":"gpt-4o-2024-07-18","service_tier":null}}

    data: {"type":"response.output_item.added","sequence_number":1,"output_index":0,"item":{"id":"msg_failed_with_reason","type":"message"}}

    data: {"type":"error","sequence_number":2,"error":{"type":"server_error","code":"server_error","message":"response failed","param":null}}

    data: {"type":"response.failed","sequence_number":3,"response":{"error":{"code":"server_error","message":"response failed"},"incomplete_details":{"reason":"max_output_tokens"},"usage":null,"service_tier":null}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o-mini")

    var textStartID: String?
    var errorMessage: String?
    var errorRaw: JSONValue?
    var finishReason: String?
    var finishMetadata: [String: JSONValue] = [:]
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textStart(id, _):
            textStartID = id
        case let .error(message, rawValue):
            errorMessage = message
            errorRaw = rawValue
        case let .finish(reason, _):
            finishReason = reason
        case let .finishMetadata(reason, _, providerMetadata):
            finishReason = reason
            finishMetadata = providerMetadata
        default:
            break
        }
    }

    #expect(textStartID == "msg_failed_with_reason")
    #expect(errorMessage == "response failed")
    #expect(errorRaw?["error"]?["code"]?.stringValue == "server_error")
    #expect(finishReason == "length")
    #expect(finishMetadata["openai"]?["responseId"]?.stringValue == "resp_failed_with_reason")
}

@Test func openAIResponsesStreamThrowsAPIErrorFromFixtureBeforeOutputLikeUpstream() async throws {
    let fixtureName = "openai-error.1.chunks.txt"
    let events = try openAIResponsesChunksFixtureEvents(fixtureName)
    let expectedMessage = try #require(events.first { $0["type"]?.stringValue == "error" }?["error"]?["message"]?.stringValue)
    let transport = RecordingTransport(response: try openAIResponsesChunksFixtureResponse(fixtureName))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o-mini")

    do {
        for try await _ in model.stream(LanguageModelRequest(messages: [.user("Hello")])) {}
        Issue.record("Expected upstream fixture stream to throw before output starts.")
    } catch let error as AIError {
        let apiError = try #require(error.apiCallError)
        #expect(apiError.statusCode == 429)
        #expect(apiError.responseBody == expectedMessage)
        #expect(apiError.isRetryable)
    }
}

@Test func openAIResponsesStreamThrowsWhenFailedArrivesBeforeOutputLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.created","sequence_number":0,"response":{"id":"resp_failed_before_output","created_at":1741269019,"model":"gpt-4o-2024-07-18","service_tier":null}}

    data: {"type":"response.failed","sequence_number":1,"response":{"error":{"code":"server_error","message":"response failed"},"incomplete_details":null,"usage":null,"service_tier":null}}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o-mini")

    do {
        for try await _ in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {}
        Issue.record("Expected stream to throw before output starts.")
    } catch let error as AIError {
        let apiError = try #require(error.apiCallError)
        #expect(apiError.statusCode == 500)
        #expect(apiError.responseBody == "response failed")
        #expect(apiError.isRetryable)
    }
}

@Test func openAIResponsesStreamThrowsTopLevelErrorBeforeOutputLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.created","sequence_number":0,"response":{"id":"resp_error_top_level","created_at":1741269019,"model":"gpt-4o-2024-07-18","service_tier":null}}

    data: {"type":"error","sequence_number":1,"code":"rate_limit_exceeded","message":"Rate limit reached","param":null}

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o-mini")

    do {
        for try await _ in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {}
        Issue.record("Expected stream to throw before output starts.")
    } catch let error as AIError {
        let apiError = try #require(error.apiCallError)
        #expect(apiError.statusCode == 429)
        #expect(apiError.responseBody == "Rate limit reached")
        #expect(apiError.isRetryable)
    }
}

@Test func openAIResponsesStreamReportsChatCompletionsMismatchLikeUpstream() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"choices":[],"created":0,"id":"","model":"","object":"","prompt_filter_results":[{"prompt_index":0,"content_filter_results":{}}]}

    data: [DONE]

    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    var errors: [(String, JSONValue?)] = []
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        if case let .error(message, rawValue) = part {
            errors.append((message, rawValue))
        }
    }

    let error = try #require(errors.first)
    #expect(error.0 == openAIResponsesChatCompletionsMismatchMessage)
    #expect(error.1?["choices"]?.arrayValue == [])
    #expect(error.1?["prompt_filter_results"]?[0]?["prompt_index"]?.intValue == 0)
}
