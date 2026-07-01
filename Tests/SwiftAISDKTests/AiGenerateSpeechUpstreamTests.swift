import Foundation
import Testing
@testable import SwiftAISDK

private let generateSpeechSampleText = "This is a sample text to convert to speech."
private let generateSpeechSampleAudio = Data([1, 2, 3, 4])

@Test func aiGenerateSpeechSendsArgsToModelLikeUpstream() async throws {
    let abortController = AIAbortController()
    let providerOptions: [String: JSONValue] = [
        "testProvider": [
            "testKey": "testValue"
        ]
    ]
    let model = MockSpeechModel(result: SpeechResult(audio: generateSpeechSampleAudio))

    _ = try await AI.generateSpeech(
        model: model,
        request: SpeechRequest(
            text: generateSpeechSampleText,
            voice: "test-voice",
            format: "mp3",
            speed: 1.25,
            language: "en",
            instructions: "Speak clearly.",
            providerOptions: providerOptions,
            headers: [
                "custom-request-header": "request-header-value"
            ],
            abortSignal: abortController.signal
        )
    )

    let request = try #require(model.requests.first)
    #expect(request.text == generateSpeechSampleText)
    #expect(request.voice == "test-voice")
    #expect(request.format == "mp3")
    #expect(request.speed == 1.25)
    #expect(request.language == "en")
    #expect(request.instructions == "Speak clearly.")
    #expect(request.providerOptions == providerOptions)
    #expect(request.headers == ["custom-request-header": "request-header-value"])
    #expect(request.abortSignal === abortController.signal)
}

@Test func aiGenerateSpeechReturnsWarningsAndProviderMetadataLikeUpstream() async throws {
    let warning = AIWarning(type: "other", message: "Setting is not supported")
    let providerMetadata: [String: JSONValue] = [
        "test-provider": [
            "test-key": "test-value"
        ]
    ]
    let model = MockSpeechModel(result: SpeechResult(
        audio: generateSpeechSampleAudio,
        warnings: [warning],
        providerMetadata: providerMetadata
    ))

    let result = try await AI.generateSpeech(
        model: model,
        request: SpeechRequest(text: generateSpeechSampleText)
    )

    #expect(result.warnings == [warning])
    #expect(result.providerMetadata == providerMetadata)
}

@Test func aiGenerateSpeechLogsWarningsLikeUpstream() async throws {
    let expectedWarnings = [
        AIWarning(type: "other", message: "Setting is not supported"),
        AIWarning(
            type: "unsupported",
            feature: "voice",
            message: "Voice parameter not supported"
        )
    ]
    let recorder = GenerateSpeechWarningLogRecorder()
    let model = MockSpeechModel(result: SpeechResult(
        audio: generateSpeechSampleAudio,
        warnings: expectedWarnings
    ))

    try await AIWarningLogging.withLogger(recorder) {
        _ = try await AI.generateSpeech(
            model: model,
            request: SpeechRequest(text: generateSpeechSampleText)
        )
    }

    #expect(await recorder.events() == [
        AIWarningLogEvent(warnings: expectedWarnings, providerID: "mock", modelID: "mock-speech")
    ])
}

@Test func aiGenerateSpeechLogsEmptyWarningsLikeUpstream() async throws {
    let recorder = GenerateSpeechWarningLogRecorder()
    let model = MockSpeechModel(result: SpeechResult(
        audio: generateSpeechSampleAudio,
        warnings: []
    ))

    try await AIWarningLogging.withLogger(recorder) {
        _ = try await AI.generateSpeech(
            model: model,
            request: SpeechRequest(text: generateSpeechSampleText)
        )
    }

    #expect(await recorder.events() == [
        AIWarningLogEvent(warnings: [], providerID: "mock", modelID: "mock-speech")
    ])
}

@Test func aiGenerateSpeechReturnsAudioDataLikeUpstream() async throws {
    let model = MockSpeechModel(result: SpeechResult(audio: generateSpeechSampleAudio))

    let result = try await AI.generateSpeech(
        model: model,
        request: SpeechRequest(text: generateSpeechSampleText)
    )

    #expect(result.audio == generateSpeechSampleAudio)
    #expect(result.warnings == [])
    #expect(result.providerMetadata == [:])
}

@Test func aiGenerateSpeechThrowsNoSpeechGeneratedWhenNoAudioLikeUpstream() async throws {
    let responseMetadata = AIResponseMetadata(
        timestamp: Date(timeIntervalSince1970: 1_704_067_200),
        modelID: "test-model-id"
    )
    let model = MockSpeechModel(result: SpeechResult(
        audio: Data(),
        responseMetadata: responseMetadata
    ))

    await #expect(throws: AINoOutputError(kind: .speech, responses: [responseMetadata])) {
        _ = try await AI.generateSpeech(
            model: model,
            request: SpeechRequest(text: generateSpeechSampleText)
        )
    }
}

@Test func aiGenerateSpeechIncludesResponseHeadersInNoAudioErrorLikeUpstream() async throws {
    let responseMetadata = AIResponseMetadata(
        timestamp: Date(timeIntervalSince1970: 1_704_067_200),
        modelID: "test-model-id",
        headers: [
            "custom-response-header": "response-header-value"
        ]
    )
    let model = MockSpeechModel(result: SpeechResult(
        audio: Data(),
        responseMetadata: responseMetadata
    ))

    await #expect(throws: AINoOutputError(kind: .speech, responses: [responseMetadata])) {
        _ = try await AI.generateSpeech(
            model: model,
            request: SpeechRequest(text: generateSpeechSampleText)
        )
    }
}

@Test func aiGenerateSpeechReturnsResponseMetadataLikeUpstream() async throws {
    let responseMetadata = AIResponseMetadata(
        timestamp: Date(timeIntervalSince1970: 1_704_067_200),
        modelID: "test-model",
        headers: [
            "x-test": "value"
        ]
    )
    let model = MockSpeechModel(result: SpeechResult(
        audio: generateSpeechSampleAudio,
        responseMetadata: responseMetadata
    ))

    let result = try await AI.generateSpeech(
        model: model,
        request: SpeechRequest(text: generateSpeechSampleText)
    )

    #expect(result.responseMetadata == responseMetadata)
}

private actor GenerateSpeechWarningLogRecorder: AIWarningLogger {
    private var recordedEvents: [AIWarningLogEvent] = []

    func logWarnings(_ event: AIWarningLogEvent) {
        recordedEvents.append(event)
    }

    func events() -> [AIWarningLogEvent] {
        recordedEvents
    }
}
