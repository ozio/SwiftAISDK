import Foundation
import Testing
@testable import SwiftAISDK

@Test func deepgramTranscriptionPostsRawAudioToListenEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"results":{"channels":[{"alternatives":[{"transcript":"hello world","words":[]}],"detected_language":"en"}]},"metadata":{"duration":1.2}}
    """))
    let provider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transport))
    let model = try provider.transcriptionModel("nova-3")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("wav".utf8),
        fileName: "clip.wav",
        mimeType: "audio/wav",
        language: "en",
        extraBody: [
            "detectLanguage": .bool(false),
            "detectEntities": .bool(true),
            "fillerWords": .bool(true),
            "smartFormat": .bool(true),
            "summarize": .string("v2"),
            "topics": .bool(true),
            "utterances": .bool(true),
            "uttSplit": .number(0.8),
            "redact": .array([.string("ssn"), .string("pci")]),
            "search": .string("Codex")
        ]
    ))

    #expect(result.text == "hello world")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.deepgram.com/v1/listen?detect_entities=true&detect_language=false&diarize=true&filler_words=true&language=en&model=nova-3&redact=ssn%2Cpci&search=Codex&smart_format=true&summarize=v2&topics=true&utt_split=0.8&utterances=true")
    #expect(request.headers["authorization"] == "Token deepgram-key")
    #expect(request.headers["content-type"] == "audio/wav")
    #expect(request.body == Data("wav".utf8))
}

@Test func deepgramSpeechUsesSpeakEndpointWithFormatQuery() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/wav"], body: Data("audio".utf8)))
    let provider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transport))
    let model = try provider.speechModel("aura-2-helena-en")

    let result = try await model.speak(SpeechRequest(
        text: "Hello",
        voice: "ignored-voice",
        format: "wav_24000",
        extraBody: [
            "callback": .string("https://example.com/hook"),
            "callbackMethod": .string("PUT"),
            "mipOptOut": .bool(true),
            "tag": .array([.string("test"), .string("swift")])
        ]
    ))

    #expect(result.audio == Data("audio".utf8))
    #expect(result.contentType == "audio/wav")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.deepgram.com/v1/speak?callback=https%3A%2F%2Fexample.com%2Fhook&callback_method=PUT&container=wav&encoding=linear16&mip_opt_out=true&model=aura-2-helena-en&sample_rate=24000&tag=test%2Cswift")
    #expect(request.headers["authorization"] == "Token deepgram-key")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["text"]?.stringValue == "Hello")
}

@Test func deepgramAudioModelsMapNestedProviderOptions() async throws {
    let transcriptionTransport = RecordingTransport(response: jsonResponse("""
    {"results":{"channels":[{"alternatives":[{"transcript":"nested","words":[]}],"detected_language":"ja"}]}}
    """))
    let transcriptionProvider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transcriptionTransport))
    let transcriptionModel = try transcriptionProvider.transcriptionModel("nova-3")

    _ = try await transcriptionModel.transcribe(AudioTranscriptionRequest(
        audio: Data("wav".utf8),
        mimeType: "audio/wav",
        language: "en",
        extraBody: [
            "deepgram": .object([
                "language": .string("ja"),
                "detectLanguage": .bool(true),
                "diarize": .bool(false),
                "smartFormat": .bool(true)
            ])
        ]
    ))

    let transcriptionRequest = try #require(await transcriptionTransport.requests().first)
    #expect(transcriptionRequest.url.absoluteString == "https://api.deepgram.com/v1/listen?detect_language=true&diarize=false&language=ja&model=nova-3&smart_format=true")

    let speechTransport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("audio".utf8)))
    let speechProvider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: speechTransport))
    let speechModel = try speechProvider.speechModel("aura-2-helena-en")

    _ = try await speechModel.speak(SpeechRequest(
        text: "Hello",
        format: "wav_24000",
        extraBody: [
            "deepgram": .object([
                "encoding": .string("mp3"),
                "bitRate": .number(48000),
                "sampleRate": .number(16000),
                "callbackMethod": .string("POST"),
                "mipOptOut": .bool(true)
            ])
        ]
    ))

    let speechRequest = try #require(await speechTransport.requests().first)
    #expect(speechRequest.url.absoluteString == "https://api.deepgram.com/v1/speak?bit_rate=48000&callback_method=POST&encoding=mp3&mip_opt_out=true&model=aura-2-helena-en")
}
