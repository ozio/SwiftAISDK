import Foundation
import Testing
@testable import SwiftAISDK

@Test func googleRequestUsesGenerateContentShape() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"gemini"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":2,"totalTokenCount":3}}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")

    #expect(model.providerID == "google.generative-ai")
    let result = try await model.generate(LanguageModelRequest(messages: [.user("Ping")]))

    #expect(result.text == "gemini")
    #expect(result.usage?.totalTokens == 3)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")
    #expect(request.headers["x-goog-api-key"] == "gemini-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["contents"]?[0]?["role"]?.stringValue == "user")
}

@Test func googleLanguageMapsFunctionToolsAndToolChoice() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"tool-ready"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Use lookup.")],
        tools: [
            "lookup": [
                "type": "object",
                "description": "Look up a value.",
                "properties": ["query": ["type": "string"]],
                "required": ["query"],
                "additionalProperties": false,
                "$schema": "http://json-schema.org/draft-07/schema#"
            ]
        ],
        extraBody: ["toolChoice": ["type": "tool", "toolName": "lookup"]]
    ))

    #expect(result.text == "tool-ready")
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let declaration = try #require(body["tools"]?[0]?["functionDeclarations"]?[0])
    #expect(declaration["name"]?.stringValue == "lookup")
    #expect(declaration["description"]?.stringValue == "Look up a value.")
    #expect(declaration["parameters"]?["properties"]?["query"]?["type"]?.stringValue == "string")
    #expect(declaration["parameters"]?["required"]?[0]?.stringValue == "query")
    #expect(declaration["parameters"]?["additionalProperties"] == nil)
    #expect(declaration["parameters"]?["$schema"] == nil)
    #expect(body["toolConfig"]?["functionCallingConfig"]?["mode"]?.stringValue == "ANY")
    #expect(body["toolConfig"]?["functionCallingConfig"]?["allowedFunctionNames"]?[0]?.stringValue == "lookup")
    #expect(body["toolChoice"] == nil)
}

@Test func googleLanguageMapsProviderDefinedTools() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"grounded"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Search.")],
        tools: [
            "google.google_search": GoogleTools.googleSearch(searchTypes: ["imageSearch": [:]]),
            "google.code_execution": GoogleTools.codeExecution()
        ],
        extraBody: ["toolChoice": "auto"]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tools = try #require(body["tools"]?.arrayValue)
    #expect(tools.contains { $0["googleSearch"]?["searchTypes"]?["imageSearch"] != nil })
    #expect(tools.contains { $0["codeExecution"]?.objectValue?.isEmpty == true })
    #expect(body["toolConfig"] == nil)
    #expect(body["toolChoice"] == nil)
}

@Test func googleToolsHelpersMirrorProviderExecutedToolFactories() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"grounded"}]},"finishReason":"STOP"}]}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use Google tools.")],
        tools: [
            "google.google_search": GoogleTools.googleSearch(
                searchTypes: ["webSearch": [:], "imageSearch": [:]],
                timeRangeFilter: ["startTime": "2025-01-01T00:00:00Z", "endTime": "2025-02-01T00:00:00Z"]
            ),
            "google.enterprise_web_search": GoogleTools.enterpriseWebSearch(),
            "google.google_maps": GoogleTools.googleMaps(),
            "google.url_context": GoogleTools.urlContext(),
            "google.file_search": GoogleTools.fileSearch(
                fileSearchStoreNames: ["fileSearchStores/store-1"],
                metadataFilter: #"author="Ada""#,
                topK: 4
            ),
            "google.code_execution": GoogleTools.codeExecution()
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tools = try #require(body["tools"]?.arrayValue)
    let googleSearch = try #require(tools.first { $0["googleSearch"] != nil })
    #expect(googleSearch["googleSearch"]?["searchTypes"]?["webSearch"] != nil)
    #expect(googleSearch["googleSearch"]?["timeRangeFilter"]?["startTime"]?.stringValue == "2025-01-01T00:00:00Z")
    #expect(tools.contains { $0["enterpriseWebSearch"]?.objectValue?.isEmpty == true })
    #expect(tools.contains { $0["googleMaps"]?.objectValue?.isEmpty == true })
    #expect(tools.contains { $0["urlContext"]?.objectValue?.isEmpty == true })
    let fileSearch = try #require(tools.first { $0["fileSearch"] != nil })
    #expect(fileSearch["fileSearch"]?["fileSearchStoreNames"]?[0]?.stringValue == "fileSearchStores/store-1")
    #expect(fileSearch["fileSearch"]?["metadataFilter"]?.stringValue == #"author="Ada""#)
    #expect(fileSearch["fileSearch"]?["topK"]?.intValue == 4)
    #expect(tools.contains { $0["codeExecution"]?.objectValue?.isEmpty == true })
}

@Test func googleLanguageParsesFunctionCalls() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"functionCall":{"name":"weather","args":{"location":"San Francisco"}}}],"role":"model"},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":29,"candidatesTokenCount":15,"totalTokenCount":44}}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Weather?")]))

    #expect(result.text == "")
    #expect(result.finishReason == "tool-calls")
    #expect(result.usage?.totalTokens == 44)
    #expect(result.toolCalls.count == 1)
    #expect(result.toolCalls[0].id == "tool-call-0")
    #expect(result.toolCalls[0].name == "weather")
    #expect(try decodeJSONBody(Data(result.toolCalls[0].arguments.utf8))["location"]?.stringValue == "San Francisco")
}

@Test func googleLanguageExtractsGroundingSources() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"grounded"}]},"finishReason":"STOP","groundingMetadata":{"groundingChunks":[{"web":{"uri":"https://source.example.com","title":"Source Title"}},{"retrievedContext":{"uri":"gs://rag-corpus/document.pdf","title":"RAG Document","text":"Retrieved context"}},{"retrievedContext":{"fileSearchStore":"fileSearchStores/test-store-xyz","title":"Test Document"}},{"maps":{"uri":"https://maps.google.com/maps?cid=12345","title":"Best Restaurant"}},{"image":{"sourceUri":"https://example.com/article","imageUri":"https://example.com/image.jpg","title":"Image Result"}}]}}]}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Ground it.")]))

    #expect(result.text == "grounded")
    #expect(result.sources.count == 5)
    #expect(result.sources[0].id == "grounding-0")
    #expect(result.sources[0].sourceType == "url")
    #expect(result.sources[0].url == "https://source.example.com")
    #expect(result.sources[0].title == "Source Title")
    #expect(result.sources[1].sourceType == "document")
    #expect(result.sources[1].title == "RAG Document")
    #expect(result.sources[1].mediaType == "application/pdf")
    #expect(result.sources[1].filename == "document.pdf")
    #expect(result.sources[2].sourceType == "document")
    #expect(result.sources[2].title == "Test Document")
    #expect(result.sources[2].mediaType == "application/octet-stream")
    #expect(result.sources[2].filename == "test-store-xyz")
    #expect(result.sources[3].sourceType == "url")
    #expect(result.sources[3].url == "https://maps.google.com/maps?cid=12345")
    #expect(result.sources[3].title == "Best Restaurant")
    #expect(result.sources[4].sourceType == "url")
    #expect(result.sources[4].url == "https://example.com/article")
    #expect(result.sources[4].title == "Image Result")
    #expect(result.sources[4].rawValue?["image"]?["imageUri"]?.stringValue == "https://example.com/image.jpg")
}

@Test func googleImagenUsesPredictInstancesAndParameters() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"predictions":[{"bytesBase64Encoded":"image-1"},{"bytesBase64Encoded":"image-2"}]}"#))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.imageModel("imagen-4.0-generate-001")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "16:9",
        count: 2,
        extraBody: ["negativePrompt": "blur", "personGeneration": "allow_adult"]
    ))

    #expect(result.base64Images == ["image-1", "image-2"])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/imagen-4.0-generate-001:predict")
    #expect(request.headers["x-goog-api-key"] == "gemini-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["instances"]?[0]?["prompt"]?.stringValue == "cat")
    #expect(body["parameters"]?["sampleCount"]?.intValue == 2)
    #expect(body["parameters"]?["aspectRatio"]?.stringValue == "16:9")
    #expect(body["parameters"]?["negativePrompt"]?.stringValue == "blur")
    #expect(body["parameters"]?["personGeneration"]?.stringValue == "allow_adult")
}

@Test func googleGeminiImageUsesGenerateContentImageModality() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"gemini-image"}}]}}]}"#))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.imageModel("gemini-2.5-flash-image")

    #expect(model.providerID == "google.generative-ai")
    let result = try await model.generateImage(ImageGenerationRequest(prompt: "cat", size: "1:1"))

    #expect(result.base64Images == ["gemini-image"])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["contents"]?[0]?["parts"]?[0]?["text"]?.stringValue == "cat")
    #expect(body["generationConfig"]?["responseModalities"]?[0]?.stringValue == "IMAGE")
    #expect(body["generationConfig"]?["imageConfig"]?["aspectRatio"]?.stringValue == "1:1")
}

@Test func googleVeoCreatesLongRunningOperationAndPollsVideoURL() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"name":"operations/video-1","done":false}"#),
        jsonResponse(#"{"name":"operations/video-1","done":true,"response":{"generateVideoResponse":{"generatedSamples":[{"video":{"uri":"https://generativelanguage.googleapis.com/files/video-123.mp4?alt=media"}}]}}}"#)
    ])
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.videoModel("veo-3.1-generate-preview")

    #expect(model.providerID == "google.generative-ai")
    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        aspectRatio: "16:9",
        durationSeconds: 5,
        extraBody: ["sampleCount": 1, "resolution": "1920x1080", "seed": 42, "negativePrompt": "rain", "pollIntervalMs": 0]
    ))

    #expect(result.urls == ["https://generativelanguage.googleapis.com/files/video-123.mp4?alt=media&key=gemini-key"])
    #expect(result.operationID == "operations/video-1")
    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/veo-3.1-generate-preview:predictLongRunning")
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["instances"]?[0]?["prompt"]?.stringValue == "cat running")
    #expect(body["parameters"]?["sampleCount"]?.intValue == 1)
    #expect(body["parameters"]?["aspectRatio"]?.stringValue == "16:9")
    #expect(body["parameters"]?["durationSeconds"]?.intValue == 5)
    #expect(body["parameters"]?["resolution"]?.stringValue == "1080p")
    #expect(body["parameters"]?["seed"]?.intValue == 42)
    #expect(body["parameters"]?["negativePrompt"]?.stringValue == "rain")
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/operations/video-1")
}

@Test func googleInteractionsUsesInteractionsEndpointAndInputShape() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"interaction-1","status":"completed","service_tier":"standard","model":"gemini-2.5-flash","usage":{"total_tokens":58,"total_input_tokens":7,"total_output_tokens":19,"total_thought_tokens":32,"total_cached_tokens":0},"steps":[{"type":"thought","summary":[{"type":"text","text":"thinking"}]},{"type":"model_output","content":[{"type":"text","text":"Hello from interactions"}]}]}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = provider.interactionsModel("gemini-2.5-flash")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.system("Be helpful."), .user("Hello")],
        temperature: 0.3,
        topP: 0.8,
        maxOutputTokens: 64,
        extraBody: [
            "previousInteractionId": "interaction-old",
            "serviceTier": "flex",
            "store": false,
            "responseModalities": ["text", "image"],
            "responseFormat": [
                ["type": "image", "mimeType": "image/png", "aspectRatio": "1:1", "imageSize": "1K"]
            ],
            "thinkingLevel": "high",
            "thinkingSummaries": true
        ]
    ))

    #expect(result.text == "Hello from interactions")
    #expect(result.finishReason == "stop")
    #expect(result.usage?.inputTokens == 7)
    #expect(result.usage?.outputTokens == 51)
    #expect(result.usage?.totalTokens == 58)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/interactions")
    #expect(request.headers["x-goog-api-key"] == "gemini-key")
    #expect(request.headers["Api-Revision"] == "2026-05-20")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "gemini-2.5-flash")
    #expect(body["system_instruction"]?.stringValue == "Be helpful.")
    #expect(body["input"]?[0]?["type"]?.stringValue == "user_input")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
    #expect(body["generation_config"]?["temperature"]?.doubleValue == 0.3)
    #expect(body["generation_config"]?["top_p"]?.doubleValue == 0.8)
    #expect(body["generation_config"]?["max_output_tokens"]?.intValue == 64)
    #expect(body["generation_config"]?["thinking_level"]?.stringValue == "high")
    #expect(body["generation_config"]?["thinking_summaries"]?.boolValue == true)
    #expect(body["previous_interaction_id"]?.stringValue == "interaction-old")
    #expect(body["service_tier"]?.stringValue == "flex")
    #expect(body["store"]?.boolValue == false)
    #expect(body["response_modalities"]?[0]?.stringValue == "text")
    #expect(body["response_format"]?[0]?["mime_type"]?.stringValue == "image/png")
    #expect(body["response_format"]?[0]?["aspect_ratio"]?.stringValue == "1:1")
    #expect(body["response_format"]?[0]?["image_size"]?.stringValue == "1K")
}

@Test func googleInteractionsExtractsSourcesAndProviderMetadata() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"interaction-1","status":"completed","service_tier":"standard","usage":{"total_tokens":12,"total_input_tokens":3,"total_output_tokens":4},"steps":[{"type":"model_output","content":[{"type":"text","text":"Grounded answer","annotations":[{"type":"url_citation","url":"https://example.com/article","title":"Example Article"},{"type":"file_citation","document_uri":"gs://bucket/path/report.pdf","file_name":"report.pdf"},{"type":"place_citation","url":"https://maps.google.com/?q=foo","name":"Foo Place"}]}]},{"type":"url_context_result","call_id":"url-1","result":[{"url":"https://context.example.com/a","status":"success"},{"url":"https://context.example.com/b","status":"error"}]},{"type":"google_search_result","call_id":"search-1","result":[{"url":"https://news.example.com/1","title":"Article 1"},{"search_suggestions":"<html/>"}]},{"type":"file_search_result","call_id":"file-1","result":[{"file_name":"notes.md","source":"fileSearchStores/x/notes.md"},{"document_uri":"https://storage.example.com/file.txt"}]},{"type":"google_maps_result","call_id":"maps-1","result":[{"places":[{"name":"Bar Cafe","url":"https://maps.google.com/?q=bar"},{"name":"No URL"}]}]}]}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = provider.interactionsModel("gemini-2.5-flash")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Ground it.")]))

    #expect(result.text == "Grounded answer")
    #expect(result.providerMetadata["google"]?["interactionId"]?.stringValue == "interaction-1")
    #expect(result.providerMetadata["google"]?["serviceTier"]?.stringValue == "standard")
    #expect(result.sources.count == 8)
    #expect(result.sources[0].sourceType == "url")
    #expect(result.sources[0].url == "https://example.com/article")
    #expect(result.sources[0].title == "Example Article")
    #expect(result.sources[1].sourceType == "document")
    #expect(result.sources[1].title == "report.pdf")
    #expect(result.sources[1].mediaType == "application/pdf")
    #expect(result.sources[1].filename == "report.pdf")
    #expect(result.sources[2].sourceType == "url")
    #expect(result.sources[2].url == "https://maps.google.com/?q=foo")
    #expect(result.sources[2].title == "Foo Place")
    #expect(result.sources[3].url == "https://context.example.com/a")
    #expect(result.sources[4].url == "https://news.example.com/1")
    #expect(result.sources[4].title == "Article 1")
    #expect(result.sources[5].sourceType == "document")
    #expect(result.sources[5].title == "notes.md")
    #expect(result.sources[5].mediaType == "text/markdown")
    #expect(result.sources[5].filename == "notes.md")
    #expect(result.sources[6].sourceType == "url")
    #expect(result.sources[6].url == "https://storage.example.com/file.txt")
    #expect(result.sources[7].sourceType == "url")
    #expect(result.sources[7].url == "https://maps.google.com/?q=bar")
    #expect(result.sources[7].title == "Bar Cafe")
}

@Test func googleInteractionsStreamsTextAndFinishUsage() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"interaction":{"id":"interaction-1","status":"in_progress"},"event_type":"interaction.created"}

    data: {"index":0,"step":{"type":"model_output"},"event_type":"step.start"}

    data: {"index":0,"delta":{"type":"text","text":"hello "},"event_type":"step.delta"}

    data: {"index":0,"delta":{"type":"text","text":"world"},"event_type":"step.delta"}

    data: {"interaction":{"id":"interaction-1","status":"completed","usage":{"total_tokens":12,"total_input_tokens":3,"total_output_tokens":4,"total_thought_tokens":5}},"event_type":"interaction.completed"}

    data: [DONE]

    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = provider.interactionsModel("gemini-2.5-flash")

    var deltas: [String] = []
    var finishReason: String?
    var totalTokens: Int?
    var outputTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hello")])) {
        switch part {
        case let .textDelta(delta):
            deltas.append(delta)
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
            outputTokens = usage?.outputTokens
        default:
            break
        }
    }

    #expect(deltas == ["hello ", "world"])
    #expect(finishReason == "stop")
    #expect(totalTokens == 12)
    #expect(outputTokens == 9)
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
    #expect(body["model"]?.stringValue == "gemini-2.5-flash")
}

@Test func googleInteractionsStreamsSourcesAndMetadata() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"interaction":{"id":"interaction-1","status":"in_progress","service_tier":"standard"},"event_type":"interaction.created"}

    data: {"index":0,"step":{"type":"model_output","content":[{"type":"text","text":"","annotations":[{"type":"url_citation","url":"https://example.com/article","title":"Example Article"}]}]},"event_type":"step.start"}

    data: {"index":0,"delta":{"type":"text","text":"hello"},"event_type":"step.delta"}

    data: {"index":0,"delta":{"type":"text_annotation","annotations":[{"type":"url_citation","url":"https://example.com/article","title":"Example Article"},{"type":"file_citation","document_uri":"gs://bucket/report.pdf","file_name":"report.pdf"}]},"event_type":"step.delta"}

    data: {"index":1,"step":{"type":"google_search_result","call_id":"search-1","result":[{"url":"https://news.example.com/1","title":"Article 1"}]},"event_type":"step.start"}

    data: {"interaction":{"id":"interaction-1","status":"completed","service_tier":"priority","usage":{"total_tokens":12,"total_input_tokens":3,"total_output_tokens":4,"total_thought_tokens":5}},"event_type":"interaction.completed"}

    data: [DONE]

    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = provider.interactionsModel("gemini-2.5-flash")

    var text: [String] = []
    var sources: [AISource] = []
    var metadata: [[String: JSONValue]] = []
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hello")])) {
        switch part {
        case let .textDelta(delta):
            text.append(delta)
        case let .source(source):
            sources.append(source)
        case let .metadata(value):
            metadata.append(value)
        case let .finish(_, usage):
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    #expect(text == ["hello"])
    #expect(sources.count == 3)
    #expect(sources[0].url == "https://example.com/article")
    #expect(sources[0].title == "Example Article")
    #expect(sources[1].sourceType == "document")
    #expect(sources[1].mediaType == "application/pdf")
    #expect(sources[1].filename == "report.pdf")
    #expect(sources[2].url == "https://news.example.com/1")
    #expect(sources[2].title == "Article 1")
    #expect(metadata.first?["google"]?["interactionId"]?.stringValue == "interaction-1")
    #expect(metadata.first?["google"]?["serviceTier"]?.stringValue == "standard")
    #expect(metadata.last?["google"]?["serviceTier"]?.stringValue == "priority")
    #expect(totalTokens == 12)
}

@Test func googleInteractionsParsesFunctionCallSteps() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"interaction-1","status":"requires_action","usage":{"total_tokens":109,"total_input_tokens":53,"total_output_tokens":15,"total_thought_tokens":41},"steps":[{"type":"thought","signature":"sig"},{"id":"zggxzq8r","type":"function_call","name":"getWeather","arguments":{"location":"San Francisco"}}],"model":"gemini-2.5-flash"}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = provider.interactionsModel("gemini-2.5-flash")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Weather?")]))

    #expect(result.text == "")
    #expect(result.finishReason == "tool-calls")
    #expect(result.usage?.totalTokens == 109)
    #expect(result.toolCalls.count == 1)
    #expect(result.toolCalls[0].id == "zggxzq8r")
    #expect(result.toolCalls[0].name == "getWeather")
    #expect(try decodeJSONBody(Data(result.toolCalls[0].arguments.utf8))["location"]?.stringValue == "San Francisco")
}

@Test func googleInteractionsStreamsFunctionCallSteps() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"interaction":{"id":"interaction-1","status":"in_progress"},"event_type":"interaction.created"}

    data: {"index":1,"step":{"id":"61nzpsv4","signature":"","type":"function_call","name":"getWeather","arguments":{}},"event_type":"step.start"}

    data: {"index":1,"delta":{"arguments":"{\\"location\\":\\"San Francisco\\"}","type":"arguments_delta"},"event_type":"step.delta"}

    data: {"index":1,"event_type":"step.stop"}

    data: {"interaction":{"id":"interaction-1","status":"requires_action","usage":{"total_tokens":133,"total_input_tokens":53,"total_output_tokens":15,"total_thought_tokens":65}},"event_type":"interaction.completed"}

    data: [DONE]

    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = provider.interactionsModel("gemini-2.5-flash")

    var deltas: [String] = []
    var finalCall: AIToolCall?
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Weather?")])) {
        switch part {
        case let .toolCallDelta(_, _, argumentsDelta, _):
            deltas.append(argumentsDelta)
        case let .toolCall(call):
            finalCall = call
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    let call = try #require(finalCall)
    #expect(deltas == [#"{"location":"San Francisco"}"#])
    #expect(call.id == "61nzpsv4")
    #expect(call.name == "getWeather")
    #expect(try decodeJSONBody(Data(call.arguments.utf8))["location"]?.stringValue == "San Francisco")
    #expect(finishReason == "tool-calls")
    #expect(totalTokens == 133)
}

@Test func googleInteractionsAgentUsesAgentAndBackgroundBody() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"agent-interaction","status":"in_progress"}"#),
        jsonResponse(#"{"id":"agent-interaction","status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":"agent done"}]}],"usage":{"total_tokens":4,"total_input_tokens":1,"total_output_tokens":3}}"#)
    ])
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = provider.interactionsAgent("deep-research")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Research")],
        extraBody: [
            "background": true,
            "agentConfig": ["type": "deep-research", "thinkingSummaries": true, "collaborativePlanning": false],
            "environment": ["type": "remote"]
        ]
    ))

    #expect(result.text == "agent done")
    let requests = await transport.requests()
    #expect(requests.count == 2)
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["agent"]?.stringValue == "deep-research")
    #expect(body["model"] == nil)
    #expect(body["background"]?.boolValue == true)
    #expect(body["agent_config"]?["type"]?.stringValue == "deep-research")
    #expect(body["agent_config"]?["thinking_summaries"]?.boolValue == true)
    #expect(body["agent_config"]?["collaborative_planning"]?.boolValue == false)
    #expect(body["environment"]?["type"]?.stringValue == "remote")
    #expect(body["generation_config"] == nil)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/interactions/agent-interaction")
}

@Test func googleFilesUploadUsesResumableUploadFlow() async throws {
    let transport = RecordingTransport(responses: [
        AIHTTPResponse(statusCode: 200, headers: ["x-goog-upload-url": "https://upload.example.com/session"], body: Data()),
        jsonResponse("""
        {"file":{"name":"files/abc","displayName":"Clip","mimeType":"video/mp4","uri":"https://generativelanguage.googleapis.com/v1beta/files/abc","state":"ACTIVE"}}
        """)
    ])
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let imageModel = try provider.imageModel("imagen-3.0-generate-002")
    #expect(imageModel.providerID == "google.generative-ai")
    let files = provider.files()
    #expect(files.providerID == "google.generative-ai")
    let result = try await files.uploadFile(FileUploadRequest(data: Data("video".utf8), mediaType: "video/mp4", displayName: "Clip"))

    #expect(result.providerReference["google"] == "https://generativelanguage.googleapis.com/v1beta/files/abc")
    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].url.absoluteString == "https://generativelanguage.googleapis.com/upload/v1beta/files")
    #expect(requests[0].headers["X-Goog-Upload-Protocol"] == "resumable")
    #expect(requests[0].headers["X-Goog-Upload-Header-Content-Length"] == "5")
    let startBody = try decodeJSONBody(try #require(requests[0].body))
    #expect(startBody["file"]?["display_name"]?.stringValue == "Clip")
    #expect(requests[1].url.absoluteString == "https://upload.example.com/session")
    #expect(requests[1].headers["X-Goog-Upload-Command"] == "upload, finalize")
    #expect(requests[1].body == Data("video".utf8))
}

@Test func googleLanguageStreamsGenerateContentEvents() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"candidates":[{"content":{"parts":[{"text":"gem"}],"role":"model"},"index":0,"groundingMetadata":{"groundingChunks":[{"web":{"uri":"https://source.example.com","title":"Source Title"}}]}}]}

    data: {"candidates":[{"content":{"parts":[{"text":"ini"}],"role":"model"},"finishReason":"STOP","index":0,"groundingMetadata":{"groundingChunks":[{"web":{"uri":"https://source.example.com","title":"Source Title"}}]}}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":2,"totalTokenCount":3}}

    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")

    var deltas: [String] = []
    var sources: [AISource] = []
    var usage: TokenUsage?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Ping")])) {
        switch part {
        case let .textDelta(delta):
            deltas.append(delta)
        case let .source(source):
            sources.append(source)
        case let .finish(_, value):
            usage = value
        default:
            break
        }
    }

    #expect(deltas == ["gem", "ini"])
    #expect(sources.count == 1)
    #expect(sources[0].id == "grounding-0")
    #expect(sources[0].url == "https://source.example.com")
    #expect(sources[0].title == "Source Title")
    #expect(usage?.totalTokens == 3)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse")
    #expect(request.headers["x-goog-api-key"] == "gemini-key")
}

@Test func googleLanguageStreamsFunctionCallPartialArguments() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"weather","willContinue":true}}]},"index":0}]}

    data: {"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"partialArgs":[{"jsonPath":"$.location","stringValue":"San ","willContinue":true}],"willContinue":true}}]},"index":0}]}

    data: {"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"partialArgs":[{"jsonPath":"$.location","stringValue":"Francisco","willContinue":true}],"willContinue":true}}]},"finishReason":"STOP","index":0}],"usageMetadata":{"promptTokenCount":29,"candidatesTokenCount":15,"totalTokenCount":44}}

    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-2.5-flash")

    var finalCall: AIToolCall?
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Weather?")])) {
        switch part {
        case let .toolCall(call):
            finalCall = call
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    let call = try #require(finalCall)
    #expect(call.id == "tool-call-0")
    #expect(call.name == "weather")
    #expect(try decodeJSONBody(Data(call.arguments.utf8))["location"]?.stringValue == "San Francisco")
    #expect(finishReason == "tool-calls")
    #expect(totalTokens == 44)
}
