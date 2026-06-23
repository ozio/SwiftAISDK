import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAILanguageDefaultsToResponsesAndMapsMultimodalInput() async throws {
    let pdf = Data("%PDF".utf8)
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"response text","usage":{"input_tokens":3,"output_tokens":4,"total_tokens":7}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        headers: ["OpenAI-Organization": "org-123", "OpenAI-Project": "proj-123"],
        transport: transport
    ))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [
            .system("Be precise."),
            AIMessage(role: .user, content: [
                .text("Inspect this"),
                .imageURL("https://example.com/image.png"),
                .data(mimeType: "application/pdf", data: pdf)
            ])
        ],
        temperature: 0.4,
        topP: 0.9,
        maxOutputTokens: 256,
        extraBody: [
            "reasoningEffort": "medium",
            "reasoningSummary": "auto",
            "previousResponseId": "resp-old",
            "parallelToolCalls": false,
            "serviceTier": "flex"
        ]
    ))

    #expect(result.text == "response text")
    #expect(result.finishReason == "stop")
    #expect(result.usage?.totalTokens == 7)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/responses")
    #expect(request.headers["authorization"] == "Bearer test-key")
    #expect(request.headers["openai-organization"] == "org-123")
    #expect(request.headers["openai-project"] == "proj-123")
    #expect(request.headers["user-agent"] == "ai-sdk/openai/3.0.74")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "gpt-4.1")
    #expect(body["temperature"]?.doubleValue == 0.4)
    #expect(body["top_p"]?.doubleValue == 0.9)
    #expect(body["max_output_tokens"]?.intValue == 256)
    #expect(body["previous_response_id"]?.stringValue == "resp-old")
    #expect(body["parallel_tool_calls"]?.boolValue == false)
    #expect(body["service_tier"]?.stringValue == "flex")
    #expect(body["reasoning"]?["effort"]?.stringValue == "medium")
    #expect(body["reasoning"]?["summary"]?.stringValue == "auto")
    #expect(body["input"]?[0]?["role"]?.stringValue == "system")
    #expect(body["input"]?[0]?["content"]?.stringValue == "Be precise.")
    #expect(body["input"]?[1]?["role"]?.stringValue == "user")
    #expect(body["input"]?[1]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[1]?["content"]?[0]?["text"]?.stringValue == "Inspect this")
    #expect(body["input"]?[1]?["content"]?[1]?["type"]?.stringValue == "input_image")
    #expect(body["input"]?[1]?["content"]?[1]?["image_url"]?.stringValue == "https://example.com/image.png")
    #expect(body["input"]?[1]?["content"]?[2]?["type"]?.stringValue == "input_file")
    #expect(body["input"]?[1]?["content"]?[2]?["filename"]?.stringValue == "part-2.pdf")
    #expect(body["input"]?[1]?["content"]?[2]?["file_data"]?.stringValue == "data:application/pdf;base64,\(pdf.base64EncodedString())")
}
@Test func openAIProviderSettingsMapBaseURLOrganizationAndProject() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"configured","usage":{"total_tokens":2}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        baseURL: "https://proxy.example.com/openai/v1/",
        organization: "org-123",
        project: "proj-456",
        headers: ["OpenAI-Project": "proj-header"],
        transport: transport
    ))
    let model = try provider.languageModel("gpt-5-mini")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.text == "configured")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://proxy.example.com/openai/v1/responses")
    #expect(request.headers["authorization"] == "Bearer test-key")
    #expect(request.headers["openai-organization"] == "org-123")
    #expect(request.headers["openai-project"] == "proj-header")
    #expect(request.headers["user-agent"] == "ai-sdk/openai/3.0.74")
}
@Test func openAIProviderAliasesRouteToUpstreamEndpoints() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"responses alias"}"#),
        jsonResponse(#"{"choices":[{"message":{"content":"chat alias"},"finish_reason":"stop"}]}"#),
        jsonResponse(#"{"choices":[{"text":"completion alias","finish_reason":"stop"}]}"#)
    ])
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))

    let languageModel = try provider.languageModel("gpt-4.1")
    let responsesModel = try provider.responses("gpt-4.1")
    let chatModel = try provider.chat("gpt-4.1-mini")
    let completionModel = try provider.completion("gpt-3.5-turbo-instruct")
    let embeddingModel = try provider.embeddingModel("text-embedding-3-small")
    let imageModel = try provider.imageModel("gpt-image-1")
    let transcriptionModel = try provider.transcriptionModel("gpt-4o-transcribe")
    let speechModel = try provider.speechModel("gpt-4o-mini-tts")
    let files = provider.files()
    let skills = try provider.skills()

    #expect(provider.providerID == "openai")
    #expect(languageModel.providerID == "openai.responses")
    #expect(responsesModel.providerID == "openai.responses")
    #expect(chatModel.providerID == "openai.chat")
    #expect(completionModel.providerID == "openai.completion")
    #expect(embeddingModel.providerID == "openai.embedding")
    #expect(imageModel.providerID == "openai.image")
    #expect(transcriptionModel.providerID == "openai.transcription")
    #expect(speechModel.providerID == "openai.speech")
    #expect(files.providerID == "openai.files")
    #expect(skills.providerID == "openai.skills")

    let responsesResult = try await responsesModel.generate(LanguageModelRequest(messages: [.user("Hi")]))
    let chatResult = try await chatModel.generate(LanguageModelRequest(messages: [.user("Hi")]))
    let completionResult = try await completionModel.generate(LanguageModelRequest(messages: [.user("Finish")]))

    #expect(responsesResult.text == "responses alias")
    #expect(chatResult.text == "chat alias")
    #expect(completionResult.text == "completion alias")
    let requests = await transport.requests()
    #expect(requests[0].url.absoluteString == "https://api.openai.com/v1/responses")
    #expect(requests[1].url.absoluteString == "https://api.openai.com/v1/chat/completions")
    #expect(requests[2].url.absoluteString == "https://api.openai.com/v1/completions")
}
@Test func openAIProviderNameOverrideMatchesUpstreamSurfaceIDsAndOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"named","usage":{"total_tokens":1}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport, name: "branded"))

    let languageModel = try provider.languageModel("gpt-4.1")
    let responsesModel = try provider.responses("gpt-4.1")
    let chatModel = try provider.chat("gpt-4.1-mini")
    let completionModel = try provider.completion("gpt-3.5-turbo-instruct")
    let embeddingModel = try provider.embeddingModel("text-embedding-3-small")
    let imageModel = try provider.imageModel("gpt-image-1")
    let transcriptionModel = try provider.transcriptionModel("gpt-4o-transcribe")
    let speechModel = try provider.speechModel("gpt-4o-mini-tts")
    let files = provider.files()
    let skills = try provider.skills()

    #expect(provider.providerID == "branded")
    #expect(languageModel.providerID == "branded.responses")
    #expect(responsesModel.providerID == "branded.responses")
    #expect(chatModel.providerID == "branded.chat")
    #expect(completionModel.providerID == "branded.completion")
    #expect(embeddingModel.providerID == "branded.embedding")
    #expect(imageModel.providerID == "branded.image")
    #expect(transcriptionModel.providerID == "branded.transcription")
    #expect(speechModel.providerID == "branded.speech")
    #expect(files.providerID == "branded.files")
    #expect(skills.providerID == "branded.skills")

    let result = try await languageModel.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: [
            "openai": .object([
                "store": .bool(false),
                "parallelToolCalls": .bool(true)
            ]),
            "branded": .object([
                "previousResponseId": .string("resp-old"),
                "reasoningEffort": .string("low"),
                "parallelToolCalls": .bool(false)
            ]),
            "branded.responses": .object([
                "serviceTier": .string("flex")
            ])
        ]
    ))

    #expect(result.text == "named")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/responses")
    #expect(request.headers["user-agent"] == "ai-sdk/openai/3.0.74")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["store"]?.boolValue == false)
    #expect(body["previous_response_id"]?.stringValue == "resp-old")
    #expect(body["parallel_tool_calls"]?.boolValue == false)
    #expect(body["reasoning"]?["effort"]?.stringValue == "low")
    #expect(body["service_tier"]?.stringValue == "flex")
    #expect(body["openai"] == nil)
    #expect(body["branded"] == nil)
    #expect(body["branded.responses"] == nil)
    #expect(body["previousResponseId"] == nil)
    #expect(body["parallelToolCalls"] == nil)
    #expect(body["reasoningEffort"] == nil)
    #expect(body["serviceTier"] == nil)
}
@Test func openAIAppendsVersionedUserAgentToCustomHeader() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"custom","usage":{"total_tokens":1}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        headers: ["User-Agent": "CustomApp/1.0"],
        transport: transport,
        name: "branded"
    ))
    let model = try provider.languageModel("gpt-4.1")

    _ = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    let request = try #require(await transport.requests().first)
    #expect(provider.providerID == "branded")
    #expect(model.providerID == "branded.responses")
    #expect(request.headers["authorization"] == "Bearer test-key")
    #expect(request.headers["user-agent"] == "CustomApp/1.0 ai-sdk/openai/3.0.74")
}
@Test func openAIResponsesMapsNestedProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done","usage":{"total_tokens":3}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hi")],
        extraBody: [
            "openai": .object([
                "store": .bool(false),
                "previousResponseId": .string("resp-old"),
                "parallelToolCalls": .bool(false),
                "reasoningEffort": .string("low"),
                "reasoningSummary": .string("auto")
            ])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["store"]?.boolValue == false)
    #expect(body["previous_response_id"]?.stringValue == "resp-old")
    #expect(body["parallel_tool_calls"]?.boolValue == false)
    #expect(body["reasoning"]?["effort"]?.stringValue == "low")
    #expect(body["reasoning"]?["summary"]?.stringValue == "auto")
    #expect(body["openai"] == nil)
    #expect(body["previousResponseId"] == nil)
    #expect(body["parallelToolCalls"] == nil)
    #expect(body["reasoningEffort"] == nil)
    #expect(body["reasoningSummary"] == nil)
}
@Test func openAIResponsesMapsTypedProviderOptionsAndAutomaticIncludesLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done","usage":{"total_tokens":3}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Use tools and structured output.")],
        responseFormat: .json(schema: ["type": "object"], name: "answer", description: "Answer schema"),
        tools: [
            "lookup": [
                "type": "object",
                "description": "Look up a value.",
                "properties": ["query": ["type": "string"]]
            ],
            "web_search": OpenAITools.webSearch(),
            "code_interpreter": OpenAITools.codeInterpreter()
        ],
        providerOptions: [
            "openai": [
                "store": false,
                "logprobs": 3,
                "textVerbosity": "high",
                "strictJsonSchema": false,
                "allowedTools": ["toolNames": ["lookup"], "mode": "required"],
                "promptCacheKey": "cache-key",
                "promptCacheRetention": "24h",
                "safetyIdentifier": "safe-user",
                "conversation": "conv-1",
                "previousResponseId": "resp-old",
                "truncation": "disabled"
            ]
        ],
        extraBody: ["toolChoice": ["type": "tool", "toolName": "web_search"]]
    ))

    #expect(result.text == "done")
    #expect(result.warnings.contains { $0.feature == "conversation" })
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["store"]?.boolValue == false)
    #expect(body["conversation"]?.stringValue == "conv-1")
    #expect(body["previous_response_id"]?.stringValue == "resp-old")
    #expect(body["prompt_cache_key"]?.stringValue == "cache-key")
    #expect(body["prompt_cache_retention"]?.stringValue == "24h")
    #expect(body["safety_identifier"]?.stringValue == "safe-user")
    #expect(body["truncation"]?.stringValue == "disabled")
    #expect(body["top_logprobs"]?.intValue == 3)
    let includeValues = try #require(body["include"]?.arrayValue)
    let include = includeValues.compactMap(\.stringValue)
    #expect(include.contains("message.output_text.logprobs"))
    #expect(include.contains("web_search_call.action.sources"))
    #expect(include.contains("code_interpreter_call.outputs"))
    #expect(include.contains("reasoning.encrypted_content"))
    #expect(body["text"]?["verbosity"]?.stringValue == "high")
    #expect(body["text"]?["format"]?["type"]?.stringValue == "json_schema")
    #expect(body["text"]?["format"]?["name"]?.stringValue == "answer")
    #expect(body["text"]?["format"]?["description"]?.stringValue == "Answer schema")
    #expect(body["text"]?["format"]?["strict"]?.boolValue == false)
    #expect(body["tool_choice"]?["type"]?.stringValue == "allowed_tools")
    #expect(body["tool_choice"]?["mode"]?.stringValue == "required")
    #expect(body["tool_choice"]?["tools"]?[0]?["name"]?.stringValue == "lookup")
    #expect(body["toolChoice"] == nil)
    #expect(body["allowedTools"] == nil)
    #expect(body["strictJsonSchema"] == nil)
    #expect(body["logprobs"] == nil)
    #expect(body["textVerbosity"] == nil)
    #expect(body["openai"] == nil)
}
@Test func openAIResponsesGenerateMapsIncompleteFinishReason() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output_text":"partial","usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.text == "partial")
    #expect(result.finishReason == "length")
    #expect(result.usage?.totalTokens == 3)
}
@Test func openAIResponsesGenerateMapsAnnotationSourcesLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"""
    {
      "id": "resp-annotations",
      "status": "completed",
      "output_text": "Based on web search and file content.",
      "output": [
        {
          "id": "msg-annotations",
          "type": "message",
          "status": "completed",
          "role": "assistant",
          "content": [
            {
              "type": "output_text",
              "text": "Based on web search and file content.",
              "annotations": [
                {"type":"url_citation","url":"https://example.com","title":"Example URL","start_index":0,"end_index":10},
                {"type":"file_citation","file_id":"file-abc123","filename":"resource1.json","index":123},
                {"type":"container_file_citation","container_id":"cntr-1","file_id":"cfile-1","filename":"rolls.csv","start_index":42,"end_index":51},
                {"type":"file_path","file_id":"cfile-path","index":7}
              ]
            }
          ]
        }
      ],
      "usage": {"input_tokens":1,"output_tokens":2,"total_tokens":3}
    }
    """#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4.1")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.sources.map(\.sourceType) == ["url", "document", "document", "document"])
    #expect(result.sources[0].url == "https://example.com")
    #expect(result.sources[0].title == "Example URL")
    #expect(result.sources[1].mediaType == "text/plain")
    #expect(result.sources[1].filename == "resource1.json")
    #expect(result.sources[1].providerMetadata["openai"]?["type"]?.stringValue == "file_citation")
    #expect(result.sources[1].providerMetadata["openai"]?["fileId"]?.stringValue == "file-abc123")
    #expect(result.sources[1].providerMetadata["openai"]?["index"]?.intValue == 123)
    #expect(result.sources[2].providerMetadata["openai"]?["type"]?.stringValue == "container_file_citation")
    #expect(result.sources[2].providerMetadata["openai"]?["containerId"]?.stringValue == "cntr-1")
    #expect(result.sources[3].mediaType == "application/octet-stream")
    #expect(result.sources[3].filename == "cfile-path")
    #expect(result.sources[3].providerMetadata["openai"]?["type"]?.stringValue == "file_path")
}
