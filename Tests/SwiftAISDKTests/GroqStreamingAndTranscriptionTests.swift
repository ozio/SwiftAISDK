import Foundation
import Testing
@testable import SwiftAISDK

@Test func groqLanguageStreamsFragmentedToolCalls() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"id":"groq-1","model":"llama-3.3-70b-versatile","choices":[{"index":0,"delta":{"role":"assistant","content":null},"finish_reason":null}]}

    data: {"id":"groq-1","model":"llama-3.3-70b-versatile","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"test_tool","arguments":"{\\""}}]},"finish_reason":null}]}

    data: {"id":"groq-1","model":"llama-3.3-70b-versatile","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"value"}}]},"finish_reason":null}]}

    data: {"id":"groq-1","model":"llama-3.3-70b-versatile","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\":\\"Sparkle Day\\"}"}}]},"finish_reason":null}]}

    data: {"id":"groq-1","model":"llama-3.3-70b-versatile","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}],"x_groq":{"usage":{"prompt_tokens":210,"completion_tokens":15,"total_tokens":225}}}

    data: [DONE]

    """))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.languageModel("llama-3.3-70b-versatile")

    var deltas: [String] = []
    var inputLifecycle: [String] = []
    var toolCall: AIToolCall?
    var finishReason: String?
    var totalTokens: Int?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Use a tool.")],
        tools: ["test_tool": ["type": "object", "properties": ["value": ["type": "string"]]]]
    )) {
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
            toolCall = call
        case let .finish(reason, usage):
            finishReason = reason
            totalTokens = usage?.totalTokens
        default:
            break
        }
    }

    let finalToolCall = try #require(toolCall)
    #expect(deltas == ["{\"", "value", "\":\"Sparkle Day\"}"])
    #expect(inputLifecycle == [
        "start:call_1:test_tool",
        "delta:call_1:{\"",
        "delta:call_1:value",
        "delta:call_1:\":\"Sparkle Day\"}",
        "end:call_1"
    ])
    #expect(finalToolCall.id == "call_1")
    #expect(finalToolCall.name == "test_tool")
    #expect(try decodeJSONBody(Data(finalToolCall.arguments.utf8))["value"]?.stringValue == "Sparkle Day")
    #expect(finishReason == "tool-calls")
    #expect(totalTokens == 225)
}
@Test func groqBrowserSearchToolIsSkippedForUnsupportedModels() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"groq-1","model":"gemma2-9b-it","choices":[{"message":{"content":"answer"},"finish_reason":"stop"}]}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.languageModel("gemma2-9b-it")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Search.")],
        tools: [
            "groq.browser_search": GroqTools.browserSearch()
        ],
        extraBody: ["toolChoice": "required"]
    ))

    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "provider-defined tool groq.browser_search")
    ])
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["tools"] == nil)
    #expect(body["tool_choice"] == nil)
}
@Test func groqTranscriptionMapsProviderOptionsToMultipartFields() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"groq transcript","x_groq":{"id":"req-1"},"language":"en","duration":1.2}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.transcriptionModel("whisper-large-v3")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("mp3".utf8),
        fileName: "clip.mp3",
        mimeType: "audio/mpeg",
        language: "en",
        prompt: "Names",
        extraBody: [
            "responseFormat": "verbose_json",
            "temperature": 0,
            "timestampGranularities": ["word", "segment"]
        ]
    ))

    #expect(result.text == "groq transcript")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.groq.com/openai/v1/audio/transcriptions")
    #expect(request.headers["authorization"] == "Bearer groq-key")
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"model\""))
    #expect(bodyText.contains("whisper-large-v3"))
    #expect(bodyText.contains("name=\"file\"; filename=\"audio.mp3\""))
    #expect(bodyText.contains("name=\"language\""))
    #expect(bodyText.contains("en"))
    #expect(bodyText.contains("name=\"prompt\""))
    #expect(bodyText.contains("Names"))
    #expect(bodyText.contains("name=\"response_format\""))
    #expect(bodyText.contains("verbose_json"))
    #expect(bodyText.contains("name=\"temperature\""))
    #expect(bodyText.contains("0"))
    #expect(bodyText.contains("name=\"timestamp_granularities[]\""))
    #expect(bodyText.contains("word"))
    #expect(bodyText.contains("segment"))
}
@Test func groqTranscriptionMapsNestedProviderOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"nested transcript","x_groq":{"id":"req-nested"}}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.transcriptionModel("whisper-large-v3-turbo")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("mp3".utf8),
        fileName: "clip.mp3",
        mimeType: "audio/mpeg",
        extraBody: [
            "temperature": 0.7,
            "groq": [
                "responseFormat": "verbose_json",
                "timestampGranularities": ["word"],
                "temperature": 0
            ]
        ]
    ))

    let request = try #require(await transport.requests().first)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(!bodyText.contains("name=\"groq\""))
    #expect(bodyText.contains("name=\"response_format\""))
    #expect(bodyText.contains("verbose_json"))
    #expect(bodyText.contains("name=\"timestamp_granularities[]\""))
    #expect(bodyText.contains("word"))
    #expect(bodyText.contains("name=\"temperature\""))
    #expect(bodyText.contains("\r\n0\r\n"))
}
@Test func groqTranscriptionMapsProviderOptionsNamespace() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"provider options transcript","x_groq":{"id":"req-provider"},"language":"fr","duration":0.8}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.transcriptionModel("whisper-large-v3-turbo")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("mp3".utf8),
        fileName: "clip.mp3",
        mimeType: "audio/mpeg",
        providerOptions: [
            "groq": [
                "language": "fr",
                "prompt": "Noms propres",
                "responseFormat": "verbose_json",
                "temperature": 0.25,
                "timestampGranularities": ["segment"]
            ]
        ]
    ))

    #expect(result.text == "provider options transcript")
    #expect(result.requestMetadata.body?["language"]?.stringValue == "fr")
    #expect(result.requestMetadata.body?["prompt"]?.stringValue == "Noms propres")
    #expect(result.requestMetadata.body?["response_format"]?.stringValue == "verbose_json")
    #expect(result.requestMetadata.body?["timestamp_granularities"]?[0]?.stringValue == "segment")

    let request = try #require(await transport.requests().first)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(!bodyText.contains("name=\"groq\""))
    #expect(bodyText.contains("name=\"language\""))
    #expect(bodyText.contains("fr"))
    #expect(bodyText.contains("name=\"prompt\""))
    #expect(bodyText.contains("Noms propres"))
    #expect(bodyText.contains("name=\"response_format\""))
    #expect(bodyText.contains("verbose_json"))
    #expect(bodyText.contains("name=\"timestamp_granularities[]\""))
    #expect(bodyText.contains("segment"))
}
@Test func groqTranscriptionProviderOptionsNullishFieldsClearExtraBodyDefaults() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"nullish transcript","x_groq":{"id":"req-nullish"}}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.transcriptionModel("whisper-large-v3-turbo")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("mp3".utf8),
        fileName: "clip.mp3",
        mimeType: "audio/mpeg",
        providerOptions: [
            "groq": .object([
                "language": .null,
                "prompt": .null,
                "responseFormat": .null,
                "temperature": .null,
                "timestampGranularities": .null
            ])
        ],
        extraBody: [
            "groq": [
                "language": "ja",
                "prompt": "legacy prompt",
                "responseFormat": "verbose_json",
                "temperature": 0.4,
                "timestampGranularities": ["word"]
            ]
        ]
    ))

    let request = try #require(await transport.requests().first)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(!bodyText.contains("name=\"language\""))
    #expect(!bodyText.contains("name=\"prompt\""))
    #expect(!bodyText.contains("name=\"response_format\""))
    #expect(!bodyText.contains("name=\"temperature\""))
    #expect(!bodyText.contains("name=\"timestamp_granularities[]\""))
}
@Test func groqTranscriptionTreatsNullProviderOptionsNamespaceAsNoop() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"null namespace transcript","x_groq":{"id":"req-null-namespace"}}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.transcriptionModel("whisper-large-v3-turbo")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("mp3".utf8),
        mimeType: "audio/mpeg",
        providerOptions: ["groq": .null],
        extraBody: [
            "groq": [
                "responseFormat": "verbose_json",
                "timestampGranularities": ["segment"],
                "temperature": 0.2
            ]
        ]
    ))

    let request = try #require(await transport.requests().first)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"response_format\""))
    #expect(bodyText.contains("verbose_json"))
    #expect(bodyText.contains("name=\"timestamp_granularities[]\""))
    #expect(bodyText.contains("segment"))
    #expect(bodyText.contains("name=\"temperature\""))
    #expect(bodyText.contains("0.2"))
}
@Test func groqTranscriptionRejectsMissingXGroqIDLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"missing id"}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.transcriptionModel("whisper-large-v3")

    await #expect(throws: AIError.invalidResponse(provider: "groq.transcription", message: "Groq transcription response is invalid.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(audio: Data("mp3".utf8), mimeType: "audio/mpeg"))
    }
}
@Test func groqTranscriptionRejectsInvalidVerboseSegmentsLikeUpstreamSchema() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"bad segments","x_groq":{"id":"req-bad"},"segments":[{"text":"missing required fields","start":0,"end":1}]}"#))
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: transport))
    let model = try provider.transcriptionModel("whisper-large-v3")

    await #expect(throws: AIError.invalidResponse(provider: "groq.transcription", message: "Groq transcription response is invalid.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(audio: Data("mp3".utf8), mimeType: "audio/mpeg"))
    }
}
@Test func groqTranscriptionProviderOptionsRejectInvalidSchemaFields() async throws {
    let provider = try AIProviders.groq(settings: ProviderSettings(apiKey: "groq-key", transport: RecordingTransport(responses: [])))
    let model = try provider.transcriptionModel("whisper-large-v3")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.groq", message: "Groq provider options must be an object.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("mp3".utf8),
            providerOptions: ["groq": "not-an-object"]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.groq.language", message: "Groq language must be a string.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("mp3".utf8),
            providerOptions: ["groq": .object(["language": true])]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.groq.temperature", message: "Groq temperature must be a number between 0 and 1.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("mp3".utf8),
            providerOptions: ["groq": .object(["temperature": 1.2])]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.groq.timestampGranularities", message: "Groq providerOptions.groq.timestampGranularities values must be strings.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("mp3".utf8),
            providerOptions: ["groq": .object(["timestampGranularities": ["word", 42]])]
        ))
    }
}
