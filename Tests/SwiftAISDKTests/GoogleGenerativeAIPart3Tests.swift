import Foundation
import Testing
@testable import SwiftAISDK

@Test func googleVideoMapsStandardImageAndProviderOptionsLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"name":"operations/video-2","done":false}"#),
        jsonResponse(#"{"name":"operations/video-2","done":true,"response":{"generateVideoResponse":{"generatedSamples":[{"video":{"uri":"https://generativelanguage.googleapis.com/files/video-456.mp4?alt=media"}}]}}}"#)
    ])
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.videoModel("veo-3.1-generate-preview")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        image: ImageInputFile(data: Data("frame".utf8), mediaType: "image/png"),
        resolution: "1280x720",
        seed: 7,
        providerOptions: [
            "google": [
                "referenceImages": [
                    ["bytesBase64Encoded": "reference-image"],
                    ["gcsUri": "gs://bucket/reference.png"]
                ],
                "personGeneration": "allow_adult",
                "negativePrompt": "rain",
                "pollIntervalMs": 0
            ]
        ]
    ))

    #expect(result.urls == ["https://generativelanguage.googleapis.com/files/video-456.mp4?alt=media&key=gemini-key"])
    #expect(result.providerMetadata["google"]?["videos"]?[0]?["uri"]?.stringValue == "https://generativelanguage.googleapis.com/files/video-456.mp4?alt=media")
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["instances"]?[0]?["image"]?["inlineData"]?["data"]?.stringValue == Data("frame".utf8).base64EncodedString())
    #expect(body["instances"]?[0]?["referenceImages"]?[0]?["inlineData"]?["data"]?.stringValue == "reference-image")
    #expect(body["instances"]?[0]?["referenceImages"]?[1]?["gcsUri"]?.stringValue == "gs://bucket/reference.png")
    #expect(body["parameters"]?["resolution"]?.stringValue == "720p")
    #expect(body["parameters"]?["seed"]?.intValue == 7)
    #expect(body["parameters"]?["personGeneration"]?.stringValue == "allow_adult")
    #expect(body["parameters"]?["negativePrompt"]?.stringValue == "rain")
    #expect(body["parameters"]?["pollIntervalMs"] == nil)
}
@Test func googleVideoWarnsAndIgnoresURLImageLikeUpstream() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"name":"operations/video-url","done":true,"response":{"generateVideoResponse":{"generatedSamples":[{"video":{"uri":"https://generativelanguage.googleapis.com/files/video-url.mp4?alt=media"}}]}}}"#)
    ])
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.videoModel("veo-3.1-generate-preview")

    let result = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        image: ImageInputFile(url: "https://example.com/frame.png")
    ))

    #expect(result.warnings.contains { $0.type == "unsupported" && $0.feature == "URL-based image input" })
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["instances"]?[0]?["image"] == nil)
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
@Test func googleInteractionsMapsStandardStructuredResponseFormat() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"interaction-1","status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":"{\\"name\\":\\"Ada\\",\\"age\\":36}"}]}]}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = provider.interactionsModel("gemini-2.5-flash")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Person?")],
        responseFormat: .json(schema: [
            "$schema": "http://json-schema.org/draft-07/schema#",
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "Full name."],
                "age": ["type": "number", "description": "Age in years."]
            ],
            "required": ["name", "age"],
            "additionalProperties": false
        ])
    ))

    #expect(result.text == "{\"name\":\"Ada\",\"age\":36}")
    #expect(result.warnings.isEmpty)
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["response_format"]?[0]?["type"]?.stringValue == "text")
    #expect(body["response_format"]?[0]?["mime_type"]?.stringValue == "application/json")
    #expect(body["response_format"]?[0]?["schema"]?["$schema"]?.stringValue == "http://json-schema.org/draft-07/schema#")
    #expect(body["response_format"]?[0]?["schema"]?["additionalProperties"]?.boolValue == false)
    #expect(body["response_format"]?[0]?["schema"]?["properties"]?["name"]?["description"]?.stringValue == "Full name.")
    #expect(body["responseFormat"] == nil)
}
@Test func googleInteractionsCombinesCallAndProviderResponseFormats() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"interaction-1","status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":"{\\"ok\\":true}"}]}]}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = provider.interactionsModel("gemini-2.5-flash")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("JSON and image.")],
        responseFormat: .json(),
        extraBody: [
            "google": [
                "responseFormat": [
                    ["type": "image", "mimeType": "image/png", "aspectRatio": "1:1"]
                ]
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["response_format"]?[0]?["type"]?.stringValue == "text")
    #expect(body["response_format"]?[0]?["mime_type"]?.stringValue == "application/json")
    #expect(body["response_format"]?[0]?["schema"] == nil)
    #expect(body["response_format"]?[1]?["type"]?.stringValue == "image")
    #expect(body["response_format"]?[1]?["mime_type"]?.stringValue == "image/png")
    #expect(body["response_format"]?[1]?["aspect_ratio"]?.stringValue == "1:1")
    #expect(body["google"] == nil)
}
@Test func googleInteractionsAgentDropsStandardResponseFormatWithWarning() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"agent-interaction","status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":"agent done"}]}]}"#)
    ])
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = provider.interactionsAgent("deep-research")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Research.")],
        responseFormat: .json(schema: ["type": "object"])
    ))

    #expect(result.text == "agent done")
    #expect(result.warnings == [
        AIWarning(
            type: "other",
            message: "google.interactions: structured output (responseFormat) is not supported when an agent is set; responseFormat will be ignored."
        )
    ])
    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["agent"]?.stringValue == "deep-research")
    #expect(body["response_format"] == nil)
}
@Test func googleInteractionsResolvesTopLevelInlineMediaType() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"interaction-1","status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":"saw image"}]}]}
    """))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = provider.interactionsModel("gemini-2.5-flash")
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [.data(mimeType: "image", data: png)])
    ]))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "image")
    #expect(body["input"]?[0]?["content"]?[0]?["mime_type"]?.stringValue == "image/png")
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
    var inputLifecycle: [String] = []
    var finalCall: AIToolCall?
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Weather?")])) {
        switch part {
        case let .toolInputStart(id, name, _, _, _, _):
            inputLifecycle.append("start:\(id):\(name)")
        case let .toolInputDelta(id, delta, _):
            inputLifecycle.append("delta:\(id):\(delta)")
        case let .toolInputEnd(id, _):
            inputLifecycle.append("end:\(id)")
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
    #expect(inputLifecycle == [
        "start:61nzpsv4:getWeather",
        #"delta:61nzpsv4:{"location":"San Francisco"}"#,
        "end:61nzpsv4"
    ])
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
