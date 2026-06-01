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

@Test func openAICompatibleLanguageResultsCarryProviderMetadata() async throws {
    let chatTransport = RecordingTransport(response: jsonResponse("""
    {"id":"chatcmpl-1","created":1710000000,"model":"gpt-4.1-mini","choices":[{"message":{"content":"hello"},"finish_reason":"stop","logprobs":{"content":[{"token":"hello","logprob":-0.1}]}}],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3,"completion_tokens_details":{"accepted_prediction_tokens":5,"rejected_prediction_tokens":1}}}
    """))
    let chatProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: chatTransport))
    let chat = try await chatProvider.chatModel("gpt-4.1-mini").generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(chat.providerMetadata["openai"]?["acceptedPredictionTokens"]?.intValue == 5)
    #expect(chat.providerMetadata["openai"]?["rejectedPredictionTokens"]?.intValue == 1)
    #expect(chat.providerMetadata["openai"]?["logprobs"]?[0]?["token"]?.stringValue == "hello")

    let completionTransport = RecordingTransport(response: jsonResponse("""
    {"id":"cmpl-1","model":"gpt-3.5-turbo-instruct","choices":[{"text":"done","finish_reason":"stop","logprobs":{"tokens":["done"],"token_logprobs":[-0.2]}}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
    """))
    let completionProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: completionTransport))
    let completion = try await completionProvider.completionModel("gpt-3.5-turbo-instruct").generate(LanguageModelRequest(messages: [.user("Finish")]))

    #expect(completion.providerMetadata["openai"]?["logprobs"]?["tokens"]?[0]?.stringValue == "done")

    let responsesTransport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_1","model":"gpt-5-mini","created":1710000001,"status":"completed","service_tier":"flex","output":[{"type":"message","id":"msg_1","content":[{"type":"output_text","text":"ok","logprobs":[{"token":"ok","logprob":-0.3}]}]}],"usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2}}
    """))
    let responsesProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: responsesTransport))
    let responses = try await responsesProvider.responses("gpt-5-mini").generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(responses.providerMetadata["openai"]?["responseId"]?.stringValue == "resp_1")
    #expect(responses.providerMetadata["openai"]?["serviceTier"]?.stringValue == "flex")
    #expect(responses.providerMetadata["openai"]?["logprobs"]?[0]?[0]?["token"]?.stringValue == "ok")

    let azureTransport = RecordingTransport(response: jsonResponse("""
    {"choices":[{"message":{"content":"azure"},"finish_reason":"stop"}],"usage":{"completion_tokens_details":{"accepted_prediction_tokens":2,"rejected_prediction_tokens":0}}}
    """))
    let azureProvider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: azureTransport))
    let azure = try await azureProvider.chatModel("chat-deployment").generate(LanguageModelRequest(messages: [.user("Hi")]))

    #expect(azure.providerMetadata["azure"]?["acceptedPredictionTokens"]?.intValue == 2)
    #expect(azure.providerMetadata["openai"] == nil)
}

@Test func openAICompatibleStreamsCarryProviderMetadataOnFinish() async throws {
    let chatTransport = RecordingTransport(response: sseResponse("""
    data: {"choices":[{"delta":{"content":"hi"},"logprobs":{"content":[{"token":"hi","logprob":-0.1}]}}],"usage":{"completion_tokens_details":{"accepted_prediction_tokens":3}}}

    data: {"choices":[{"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2,"completion_tokens_details":{"rejected_prediction_tokens":1}}}

    data: [DONE]

    """))
    let chatProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: chatTransport))
    let chatModel = try chatProvider.chatModel("gpt-4.1-mini")

    var chatMetadata: [String: JSONValue] = [:]
    for try await part in chatModel.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        if case let .finishMetadata(_, _, metadata) = part {
            chatMetadata = metadata
        }
    }

    #expect(chatMetadata["openai"]?["acceptedPredictionTokens"]?.intValue == 3)
    #expect(chatMetadata["openai"]?["rejectedPredictionTokens"]?.intValue == 1)
    #expect(chatMetadata["openai"]?["logprobs"]?[0]?["token"]?.stringValue == "hi")

    let completionTransport = RecordingTransport(response: sseResponse("""
    data: {"choices":[{"text":"done","finish_reason":"stop","logprobs":{"tokens":["done"],"token_logprobs":[-0.2]}}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}

    data: [DONE]

    """))
    let completionProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: completionTransport))
    let completionModel = try completionProvider.completionModel("gpt-3.5-turbo-instruct")

    var completionMetadata: [String: JSONValue] = [:]
    for try await part in completionModel.stream(LanguageModelRequest(messages: [.user("Finish")])) {
        if case let .finishMetadata(_, _, metadata) = part {
            completionMetadata = metadata
        }
    }

    #expect(completionMetadata["openai"]?["logprobs"]?["tokens"]?[0]?.stringValue == "done")

    let responsesTransport = RecordingTransport(response: sseResponse("""
    data: {"type":"response.output_text.delta","delta":"ok"}

    data: {"type":"response.completed","response":{"id":"resp_stream","status":"completed","service_tier":"priority","usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2}}}

    data: [DONE]

    """))
    let responsesProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: responsesTransport))
    let responsesModel = try responsesProvider.responses("gpt-5-mini")

    var responsesMetadata: [String: JSONValue] = [:]
    for try await part in responsesModel.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        if case let .finishMetadata(_, _, metadata) = part {
            responsesMetadata = metadata
        }
    }

    #expect(responsesMetadata["openai"]?["responseId"]?.stringValue == "resp_stream")
    #expect(responsesMetadata["openai"]?["serviceTier"]?.stringValue == "priority")
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

    let embedding = try await embeddingModel.embed(EmbeddingRequest(values: ["hi"], dimensions: 64, headers: ["x-client": "swift"]))

    #expect(embedding.requestMetadata.body?["input"]?[0]?.stringValue == "hi")
    #expect(embedding.requestMetadata.body?["dimensions"]?.intValue == 64)
    #expect(embedding.requestMetadata.headers["x-client"] == "swift")
    #expect(embedding.requestMetadata.headers["Authorization"] == nil)
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
