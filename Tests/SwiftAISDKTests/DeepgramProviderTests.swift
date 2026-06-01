import Foundation
import Testing
@testable import SwiftAISDK

@Test func deepgramTranscriptionUsesProviderOptionsNamespaceAndMapsUpstreamOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"results":{"channels":[{"alternatives":[{"transcript":"hej","words":[{"word":"hej","start":0,"end":0.5}]}],"detected_language":"sv"}]},"metadata":{"duration":0.5}}
    """))
    let provider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transport))
    let model = try provider.transcriptionModel("nova-3")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("wav".utf8),
        mimeType: "audio/wav",
        language: "en",
        providerOptions: [
            "deepgram": .object([
                "language": .string("sv"),
                "detectLanguage": .bool(true),
                "diarize": .bool(false),
                "paragraphs": .bool(true),
                "intents": .bool(true),
                "sentiment": .bool(true),
                "replace": .string("redacted"),
                "keyterm": .string("SwiftAISDK"),
                "smartFormat": .bool(true)
            ])
        ]
    ))

    #expect(result.text == "hej")
    #expect(result.language == "sv")
    #expect(result.durationInSeconds == 0.5)
    #expect(result.segments == [TranscriptionSegment(text: "hej", startSecond: 0, endSecond: 0.5)])

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.deepgram.com/v1/listen?detect_language=true&diarize=false&intents=true&keyterm=SwiftAISDK&language=sv&model=nova-3&paragraphs=true&replace=redacted&sentiment=true&smart_format=true")
    #expect(request.headers["content-type"] == "audio/wav")
    #expect(request.body == Data("wav".utf8))
}

@Test func deepgramSpeechUsesProviderOptionsWarningsAndAbortSignal() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        headers: ["content-type": "audio/mpeg", "deepgram-header": "speech"],
        body: Data("deepgram-audio".utf8)
    ))
    let provider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transport))
    let model = try provider.speechModel("aura-2-helena-en")
    let controller = AIAbortController()

    let result = try await model.speak(SpeechRequest(
        text: "Hello",
        voice: "different-voice",
        format: "linear16_16000",
        providerOptions: [
            "deepgram": .object([
                "encoding": .string("mp3"),
                "container": .string("wav"),
                "sampleRate": .number(16000),
                "bitRate": .number(48000),
                "callback": .string("https://example.com/callback"),
                "callbackMethod": .string("POST"),
                "mipOptOut": .bool(true),
                "tag": .array([.string("tag1"), .string("tag2")])
            ])
        ],
        abortSignal: controller.signal
    ))

    #expect(result.audio == Data("deepgram-audio".utf8))
    #expect(result.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "providerOptions",
            message: "Encoding \"mp3\" does not support container parameter. Container \"wav\" was ignored."
        ),
        AIWarning(
            type: "unsupported",
            feature: "providerOptions",
            message: "Encoding \"mp3\" has a fixed sample rate and does not support sample_rate parameter. Sample rate 16000 was ignored."
        ),
        AIWarning(
            type: "unsupported",
            feature: "voice",
            message: "Deepgram TTS models embed the voice in the model ID. The voice parameter \"different-voice\" was ignored. Use the model ID to select a voice (e.g., \"aura-2-helena-en\")."
        )
    ])

    let request = try #require(await transport.requests().first)
    #expect(request.abortSignal === controller.signal)
    #expect(request.url.absoluteString == "https://api.deepgram.com/v1/speak?bit_rate=48000&callback=https%3A%2F%2Fexample.com%2Fcallback&callback_method=POST&encoding=mp3&mip_opt_out=true&model=aura-2-helena-en&tag=tag1%2Ctag2")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["text"]?.stringValue == "Hello")
}

@Test func deepgramSpeechCleansIncompatibleParametersWhenContainerChangesEncoding() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/ogg"], body: Data("ogg".utf8)))
    let provider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transport))
    let model = try provider.speechModel("aura-2-helena-en")

    _ = try await model.speak(SpeechRequest(
        text: "Hello",
        format: "linear16_16000",
        providerOptions: ["deepgram": .object(["container": .string("ogg")])]
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.deepgram.com/v1/speak?container=ogg&encoding=opus&model=aura-2-helena-en")
}
