import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAICompatibleGenerateTextCarriesResponseMetadata() async throws {
    let raw = #"""
    {"id":"chatcmpl-1","created":1710000000,"model":"gpt-4.1-mini","choices":[{"message":{"content":"hello"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}
    """#
    let transport = RecordingTransport(response: jsonResponse(raw, headers: ["test-header": "test-value"]))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.chatModel("gpt-4.1-mini")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(result.responseMetadata.id == "chatcmpl-1")
    #expect(result.responseMetadata.modelID == "gpt-4.1-mini")
    #expect(result.responseMetadata.timestamp == Date(timeIntervalSince1970: 1_710_000_000))
    #expect(result.responseMetadata.headers["test-header"] == "test-value")
    #expect(result.responseMetadata.body?["id"]?.stringValue == "chatcmpl-1")
}

@Test func openAICompatibleStreamsCarryResponseMetadataEvent() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"choices":[{"delta":{"content":"hel"}}]}

    data: {"choices":[{"delta":{"content":"lo"},"finish_reason":"stop"}]}

    data: [DONE]

    """, headers: ["test-header": "stream-value"]))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.chatModel("gpt-4.1-mini")

    var responseMetadata: AIResponseMetadata?
    var text = ""
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .textDelta(delta):
            text += delta
        default:
            break
        }
    }

    #expect(text == "hello")
    #expect(responseMetadata?.modelID == "gpt-4.1-mini")
    #expect(responseMetadata?.headers["test-header"] == "stream-value")
}

@Test func openAICompatibleEmbeddingAndImageCarryResponseMetadata() async throws {
    let embeddingTransport = RecordingTransport(response: jsonResponse(#"{"model":"text-embedding-3-small","data":[{"embedding":[0.1,0.2]}],"usage":{"total_tokens":2}}"#, headers: ["embedding-header": "value"]))
    let embeddingProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: embeddingTransport))
    let embeddingModel = try embeddingProvider.embeddingModel("text-embedding-3-small")

    let embedding = try await embeddingModel.embed(EmbeddingRequest(values: ["hi"]))

    #expect(embedding.responseMetadata.modelID == "text-embedding-3-small")
    #expect(embedding.responseMetadata.headers["embedding-header"] == "value")
    #expect(embedding.responseMetadata.body?["data"]?[0]?["embedding"]?[0]?.doubleValue == 0.1)

    let imageTransport = RecordingTransport(response: jsonResponse(#"{"created":1710000001,"data":[{"b64_json":"image-data"}]}"#, headers: ["image-header": "value"]))
    let imageProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("gpt-image-1")

    let image = try await imageModel.generateImage(ImageGenerationRequest(prompt: "logo"))

    #expect(image.responseMetadata.modelID == "gpt-image-1")
    #expect(image.responseMetadata.timestamp == Date(timeIntervalSince1970: 1_710_000_001))
    #expect(image.responseMetadata.headers["image-header"] == "value")
    #expect(image.responseMetadata.body?["data"]?[0]?["b64_json"]?.stringValue == "image-data")
}

@Test func openAICompatibleAudioResultsCarryResponseMetadata() async throws {
    let transcriptTransport = RecordingTransport(response: jsonResponse(#"{"text":"transcribed"}"#, headers: ["transcription-header": "value"]))
    let transcriptProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transcriptTransport))
    let transcriptionModel = try transcriptProvider.transcriptionModel("whisper-1")

    let transcript = try await transcriptionModel.transcribe(AudioTranscriptionRequest(audio: Data("abc".utf8), mimeType: "audio/wav"))

    #expect(transcript.responseMetadata.modelID == "whisper-1")
    #expect(transcript.responseMetadata.headers["transcription-header"] == "value")
    #expect(transcript.responseMetadata.body?["text"]?.stringValue == "transcribed")

    let speechTransport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["speech-header": "value", "content-type": "audio/mpeg"], body: Data("mp3".utf8)))
    let speechProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: speechTransport))
    let speechModel = try speechProvider.speechModel("tts-1")

    let speech = try await speechModel.speak(SpeechRequest(text: "Hi"))

    #expect(speech.responseMetadata.modelID == "tts-1")
    #expect(speech.responseMetadata.headers["speech-header"] == "value")
    #expect(speech.responseMetadata.body == nil)
}
