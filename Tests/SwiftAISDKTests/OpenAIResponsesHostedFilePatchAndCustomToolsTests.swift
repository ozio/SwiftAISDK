import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesSendsFileSearchRequestBodyLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesFileSearchWithoutResultsFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesFileSearchTool()
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "gpt-5-nano")
    #expect(body["include"] == nil)
    #expect(body["input"]?[0]?["role"]?.stringValue == "user")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
    let tool = try #require(body["tools"]?[0])
    #expect(tool["type"]?.stringValue == "file_search")
    #expect(tool["vector_store_ids"]?[0]?.stringValue == "vs_68caad8bd5d88191ab766cf043d89a18")
    #expect(tool["max_num_results"]?.intValue == 5)
    #expect(tool["filters"]?["key"]?.stringValue == "author")
    #expect(tool["filters"]?["type"]?.stringValue == "eq")
    #expect(tool["filters"]?["value"]?.stringValue == "Jane Smith")
    #expect(tool["ranking_options"]?["ranker"]?.stringValue == "auto")
    #expect(tool["ranking_options"]?["score_threshold"]?.doubleValue == 0.5)
}

@Test func openAIResponsesIncludesFileSearchContentWithoutResultsLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesFileSearchWithoutResultsFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesFileSearchTool()
    ))

    #expect(result.content.count == 6)
    guard case let .reasoning(firstReasoning, firstReasoningMetadata) = result.content[0],
          case let .toolCall(toolCall) = result.content[1],
          case let .toolResult(toolResult) = result.content[2],
          case let .reasoning(secondReasoning, secondReasoningMetadata) = result.content[3],
          case let .text(text, textMetadata) = result.content[4],
          case let .source(source) = result.content[5] else {
        Issue.record("Expected upstream file search content without included results")
        return
    }

    #expect(firstReasoning == "")
    #expect(firstReasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_0a098396a8feca410068caae3b47208196957fe59419daad70")
    #expect(toolCall.id == "fs_0a098396a8feca410068caae3cab5c8196a54fd00498464e62")
    #expect(toolCall.name == "fileSearch")
    #expect(toolCall.arguments == "{}")
    #expect(toolCall.providerExecuted == true)
    #expect(toolResult.toolCallID == toolCall.id)
    #expect(toolResult.toolName == "fileSearch")
    #expect(toolResult.result["queries"]?[0]?.stringValue == "What is an embedding model according to this document?")
    #expect(toolResult.result["queries"]?[3]?.stringValue == "embedding model description")
    #expect(toolResult.result["results"] == .null)
    #expect(secondReasoning == "")
    #expect(secondReasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_0a098396a8feca410068caae3e21a081968e7ac588401c4a6a")
    #expect(text.contains("an embedding model is used to convert complex data"))
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_0a098396a8feca410068caae457c508196b2fcd079d1d3ec74")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["type"]?.stringValue == "file_citation")
    #expect(source.id == "id-0")
    #expect(source.sourceType == "document")
    #expect(source.title == "ai.pdf")
    #expect(source.mediaType == "text/plain")
    #expect(source.filename == "ai.pdf")
    #expect(source.providerMetadata["openai"]?["fileId"]?.stringValue == "file-Ebzhf8H4DPGPr9pUhr7n7v")
    #expect(source.providerMetadata["openai"]?["index"]?.intValue == 438)
}

@Test func openAIResponsesSendsFileSearchWithResultsIncludeRequestBodyLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesFileSearchWithResultsFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesFileSearchTool(),
        providerOptions: ["openai": ["include": ["file_search_call.results"]]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "gpt-5-nano")
    #expect(body["include"]?[0]?.stringValue == "file_search_call.results")
    #expect(body["input"]?[0]?["role"]?.stringValue == "user")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
    let tool = try #require(body["tools"]?[0])
    #expect(tool["type"]?.stringValue == "file_search")
    #expect(tool["vector_store_ids"]?[0]?.stringValue == "vs_68caad8bd5d88191ab766cf043d89a18")
    #expect(tool["max_num_results"]?.intValue == 5)
    #expect(tool["filters"]?["key"]?.stringValue == "author")
    #expect(tool["ranking_options"]?["score_threshold"]?.doubleValue == 0.5)
}

@Test func openAIResponsesIncludesFileSearchContentWithResultsLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesFileSearchWithResultsFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesFileSearchTool(),
        providerOptions: ["openai": ["include": ["file_search_call.results"]]]
    ))

    #expect(result.content.count == 6)
    guard case let .reasoning(firstReasoning, firstReasoningMetadata) = result.content[0],
          case let .toolCall(toolCall) = result.content[1],
          case let .toolResult(toolResult) = result.content[2],
          case let .reasoning(secondReasoning, secondReasoningMetadata) = result.content[3],
          case let .text(text, textMetadata) = result.content[4],
          case let .source(source) = result.content[5] else {
        Issue.record("Expected upstream file search content with included results")
        return
    }

    #expect(firstReasoning == "")
    #expect(firstReasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_0365d26c32c64c650068cabb03bcc48194bfbd973152bca8f6")
    #expect(toolCall.id == "fs_0365d26c32c64c650068cabb04aa388194b53c59de50a3951e")
    #expect(toolCall.name == "fileSearch")
    #expect(toolCall.arguments == "{}")
    #expect(toolCall.providerExecuted == true)
    #expect(toolResult.toolCallID == toolCall.id)
    #expect(toolResult.toolName == "fileSearch")
    #expect(toolResult.result["queries"]?[0]?.stringValue == "What is an embedding model according to this document?")
    #expect(toolResult.result["queries"]?[3]?.stringValue == "embedding model explanation 'embedding model'")
    #expect(toolResult.result["results"]?[0]?["attributes"]?.objectValue?.isEmpty == true)
    #expect(toolResult.result["results"]?[0]?["fileId"]?.stringValue == "file-Ebzhf8H4DPGPr9pUhr7n7v")
    #expect(toolResult.result["results"]?[0]?["filename"]?.stringValue == "ai.pdf")
    #expect(toolResult.result["results"]?[0]?["score"]?.doubleValue == 0.9311)
    #expect(toolResult.result["results"]?[0]?["text"]?.stringValue?.contains("An embedding model is used to convert complex data") == true)
    #expect(secondReasoning == "")
    #expect(secondReasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_0365d26c32c64c650068cabb061740819491324d349d0f07ca")
    #expect(text.contains("called an embedding"))
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_0365d26c32c64c650068cabb0e66b081949f66f61dacef39f3")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["index"]?.intValue == 350)
    #expect(source.id == "id-0")
    #expect(source.sourceType == "document")
    #expect(source.title == "ai.pdf")
    #expect(source.mediaType == "text/plain")
    #expect(source.filename == "ai.pdf")
    #expect(source.providerMetadata["openai"]?["fileId"]?.stringValue == "file-Ebzhf8H4DPGPr9pUhr7n7v")
    #expect(source.providerMetadata["openai"]?["index"]?.intValue == 350)
}

@Test func openAIResponsesSendsApplyPatchRequestBodyLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesApplyPatchFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1-2025-11-13")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "apply_patch": [
                "type": "provider",
                "id": "openai.apply_patch",
                "name": "apply_patch",
                "args": [:]
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "gpt-5.1-2025-11-13")
    #expect(body["input"]?[0]?["role"]?.stringValue == "user")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
    #expect(body["tools"]?[0]?["type"]?.stringValue == "apply_patch")
}

@Test func openAIResponsesIncludesApplyPatchContentLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesApplyPatchFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1-2025-11-13")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "apply_patch": [
                "type": "provider",
                "id": "openai.apply_patch",
                "name": "apply_patch",
                "args": [:]
            ]
        ]
    ))

    #expect(result.content.count == 1)
    guard case let .toolCall(toolCall) = result.content[0] else {
        Issue.record("Expected upstream apply_patch tool-call content")
        return
    }

    #expect(toolCall.id == "call_CdXiGtcRl49Q6Ek20tG9lYOr")
    #expect(toolCall.name == "apply_patch")
    #expect(toolCall.providerExecuted == false)
    #expect(toolCall.providerMetadata["openai"]?["itemId"]?.stringValue == "apc_0b04c5f8dfc43af500692749bd60908197b0e453c38f30191a")
    let input = try decodeJSONBody(Data(toolCall.arguments.utf8))
    #expect(input["callId"]?.stringValue == "call_CdXiGtcRl49Q6Ek20tG9lYOr")
    #expect(input["operation"]?["type"]?.stringValue == "create_file")
    #expect(input["operation"]?["path"]?.stringValue == "shopping-checklist.md")
    #expect(input["operation"]?["diff"]?.stringValue == "+## Shopping Checklist\n+\n+- [ ] Milk\n+- [ ] Bread\n+- [ ] Eggs\n+- [ ] Apples\n+- [ ] Coffee\n+\n")
}

@Test func openAIResponsesSendsCustomToolRequestBodyLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesCustomToolFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2-codex")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "write_sql": OpenAITools.customTool(
                name: "write_sql",
                description: "Write a SQL SELECT query to answer the user question.",
                format: ["type": "grammar", "syntax": "regex", "definition": "SELECT .+"]
            )
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "gpt-5.2-codex")
    #expect(body["input"]?[0]?["role"]?.stringValue == "user")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
    #expect(body["tools"]?[0]?["type"]?.stringValue == "custom")
    #expect(body["tools"]?[0]?["name"]?.stringValue == "write_sql")
    #expect(body["tools"]?[0]?["description"]?.stringValue == "Write a SQL SELECT query to answer the user question.")
    #expect(body["tools"]?[0]?["format"]?["type"]?.stringValue == "grammar")
    #expect(body["tools"]?[0]?["format"]?["syntax"]?.stringValue == "regex")
    #expect(body["tools"]?[0]?["format"]?["definition"]?.stringValue == "SELECT .+")
}

@Test func openAIResponsesGeneratesCustomToolCallLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesCustomToolFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2-codex")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "write_sql": OpenAITools.customTool(
                name: "write_sql",
                description: "Write a SQL SELECT query to answer the user question.",
                format: ["type": "grammar", "syntax": "regex", "definition": "SELECT .+"]
            )
        ]
    ))

    #expect(result.content.count == 1)
    guard case let .toolCall(toolCall) = result.content[0] else {
        Issue.record("Expected upstream custom tool-call content")
        return
    }

    #expect(toolCall.id == "call_custom_sql_001")
    #expect(toolCall.name == "write_sql")
    #expect(toolCall.arguments == "\"SELECT * FROM users WHERE age > 25\"")
    #expect(toolCall.providerMetadata["openai"]?["itemId"]?.stringValue == "ct_abc123def456")
}

@Test func openAIResponsesHasCustomToolCallsFinishReasonLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesCustomToolFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2-codex")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "write_sql": OpenAITools.customTool(
                name: "write_sql",
                description: "Write a SQL SELECT query to answer the user question.",
                format: ["type": "grammar", "syntax": "regex", "definition": "SELECT .+"]
            )
        ]
    ))

    #expect(result.finishReason == "tool-calls")
}

