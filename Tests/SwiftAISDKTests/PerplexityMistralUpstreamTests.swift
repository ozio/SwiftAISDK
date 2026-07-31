import Foundation
import Testing
@testable import SwiftAISDK

@Test func perplexityEmbeddingDecodesSignedInt8AndMapsMetadata() async throws {
    let transport = RecordingTransport(response: jsonResponse(
        #"{"data":[{"embedding":"/wB/gA=="}],"usage":{"prompt_tokens":4,"cost":{"input_cost":0.01,"total_cost":0.02,"currency":"USD"}}}"#,
        headers: ["x-request-id": "pplx-embed-1"]
    ))
    let provider = try AIProviders.perplexity(settings: ProviderSettings(apiKey: "pplx-key", transport: transport))
    let model = try provider.embedding("pplx-embed-v1-0.6b")

    let result = try await model.embed(EmbeddingRequest(
        values: ["hello"],
        providerOptions: ["perplexity": ["dimensions": 256]]
    ))

    #expect(model.providerID == "perplexity.embedding")
    #expect(result.embeddings == [[-1, 0, 127, -128]])
    #expect(result.usage?.inputTokens == 4)
    #expect(result.providerMetadata["perplexity"]?["cost"]?["inputCost"]?.doubleValue == 0.01)
    #expect(result.providerMetadata["perplexity"]?["cost"]?["totalCost"]?.doubleValue == 0.02)
    #expect(result.providerMetadata["perplexity"]?["cost"]?["currency"]?.stringValue == "USD")
    #expect(result.responseMetadata.headers["x-request-id"] == "pplx-embed-1")

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.perplexity.ai/v1/embeddings")
    #expect(request.headers["authorization"] == "Bearer pplx-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "pplx-embed-v1-0.6b")
    #expect(body["input"]?[0]?.stringValue == "hello")
    #expect(body["dimensions"]?.intValue == 256)
    #expect(body["encoding_format"]?.stringValue == "base64_int8")
}

@Test func perplexityEmbeddingDecodesBinaryAndValidatesLimits() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"data":[{"embedding":"/wB/gA=="}]}"#))
    let provider = try AIProviders.perplexity(settings: ProviderSettings(apiKey: "pplx-key", transport: transport))
    let model = try provider.embeddingModel("pplx-embed-v1-4b")

    let result = try await model.embed(EmbeddingRequest(
        values: ["hello"],
        providerOptions: ["perplexity": ["encodingFormat": "base64_binary"]]
    ))
    #expect(result.embeddings == [[255, 0, 127, 128]])

    await #expect(throws: AITooManyEmbeddingValuesForCallError.self) {
        _ = try await model.embed(EmbeddingRequest(values: Array(repeating: "x", count: 513)))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.perplexity.dimensions", message: "Perplexity dimensions must be a positive integer.")) {
        _ = try await model.embed(EmbeddingRequest(values: ["x"], providerOptions: ["perplexity": ["dimensions": 0]]))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.perplexity.encodingFormat", message: "Perplexity encodingFormat must be base64_int8 or base64_binary.")) {
        _ = try await model.embed(EmbeddingRequest(values: ["x"], providerOptions: ["perplexity": ["encodingFormat": "float"]]))
    }
}

@Test func mistralAssistantReasoningUsesThinkingContentBlocks() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}]}"#))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.languageModel("mistral-small-latest")

    _ = try await model.generate(LanguageModelRequest(messages: [
        .user("question"),
        AIMessage(role: .assistant, content: [.reasoning("consider"), .text("answer")])
    ]))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let assistant = try #require(body["messages"]?[1])
    #expect(assistant["content"]?[0]?["type"]?.stringValue == "thinking")
    #expect(assistant["content"]?[0]?["thinking"]?[0]?["text"]?.stringValue == "consider")
    #expect(assistant["content"]?[0]?["closed"]?.boolValue == true)
    #expect(assistant["content"]?[1]?["type"]?.stringValue == "text")
    #expect(assistant["content"]?[1]?["text"]?.stringValue == "answer")
}

@Test func mistralVoxtralTranscriptionMapsOptionsAndRichMetadata() async throws {
    let transport = RecordingTransport(response: jsonResponse(
        #"{"model":"voxtral-mini-latest","text":"hello","language":"en","segments":[{"type":"transcription_segment","text":"hello","start":0,"end":1.5,"score":0.9,"speaker_id":"speaker-1"}],"usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5,"prompt_audio_seconds":1.6,"request_count":1}}"#
    ))
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
    let model = try provider.transcription("voxtral-mini-latest")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        mimeType: "audio/mpeg",
        providerOptions: ["mistral": [
            "temperature": 0.2,
            "timestampGranularities": ["segment", "word"],
            "diarize": true,
            "contextBias": ["SwiftAISDK", "Voxtral"]
        ]]
    ))

    #expect(model.providerID == "mistral.transcription")
    #expect(result.text == "hello")
    #expect(result.segments == [TranscriptionSegment(text: "hello", startSecond: 0, endSecond: 1.5)])
    #expect(result.durationInSeconds == 1.6)
    #expect(result.providerMetadata["mistral"]?["usage"]?["totalTokens"]?.intValue == 5)
    #expect(result.providerMetadata["mistral"]?["segments"]?[0]?["speakerId"]?.stringValue == "speaker-1")

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.mistral.ai/v1/audio/transcriptions")
    let body = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(body.contains("name=\"timestamp_granularities\""))
    #expect(body.contains("segment"))
    #expect(body.contains("word"))
    #expect(body.contains("name=\"context_bias\""))
    #expect(body.contains("SwiftAISDK"))
}

@Test func mistralVoxtralValidatesIncompatibleAndInvalidOptions() async throws {
    let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: RecordingTransport(responses: [])))
    let model = try provider.transcriptionModel("voxtral-mini-latest")

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions", message: "providerOptions.mistral.language cannot be combined with providerOptions.mistral.timestampGranularities")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data(),
            providerOptions: ["mistral": ["language": "en", "timestampGranularities": ["segment"]]]
        ))
    }
    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.mistral.contextBias", message: "Mistral contextBias must contain at most 100 non-empty strings without commas or whitespace.")) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data(),
            providerOptions: ["mistral": ["contextBias": ["two words"]]]
        ))
    }
}

@Test func mistralVoxtralRejectsMalformedResponseFields() async throws {
    let malformedResponses = [
        #"{"model":"voxtral-mini-latest","text":"hello","language":7}"#,
        #"{"model":"voxtral-mini-latest","text":"hello","segments":[{"type":"word","text":"hello","start":0,"end":1}]}"#,
        #"{"model":"voxtral-mini-latest","text":"hello","segments":[{"text":"hello","start":0,"end":1,"score":"high"}]}"#,
        #"{"model":"voxtral-mini-latest","text":"hello","segments":[{"text":"hello","start":0,"end":1,"speaker_id":4}]}"#,
        #"{"model":"voxtral-mini-latest","text":"hello","usage":{"prompt_tokens":"two"}}"#
    ]

    for responseBody in malformedResponses {
        let transport = RecordingTransport(response: jsonResponse(responseBody))
        let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "mistral-key", transport: transport))
        let model = try provider.transcriptionModel("voxtral-mini-latest")

        await #expect(throws: AIError.invalidResponse(
            provider: "mistral.transcription",
            message: "Mistral transcription response is invalid."
        )) {
            _ = try await model.transcribe(AudioTranscriptionRequest(audio: Data()))
        }
    }
}
