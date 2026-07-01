import Foundation
import Testing
@testable import SwiftAISDK

private let transcribeAudioData = Data([1, 2, 3, 4])
private let transcribeSampleSegments = [
    TranscriptionSegment(text: "This is a", startSecond: 0, endSecond: 2.5),
    TranscriptionSegment(text: "sample transcript.", startSecond: 2.5, endSecond: 4.0)
]

@Test func aiTranscribeSendsArgsToModelLikeUpstream() async throws {
    let abortController = AIAbortController()
    let providerOptions: [String: JSONValue] = [
        "testProvider": [
            "testKey": "testValue"
        ]
    ]
    let model = MockTranscriptionModel(result: TranscriptionResult(
        text: "This is a sample transcript.",
        rawValue: .object([:])
    ))

    _ = try await AI.transcribe(
        model: model,
        request: AudioTranscriptionRequest(
            audio: transcribeAudioData,
            fileName: "sample.wav",
            mimeType: "audio/wav",
            language: "en",
            prompt: "Names are proper nouns.",
            providerOptions: providerOptions,
            headers: [
                "custom-request-header": "request-header-value"
            ],
            abortSignal: abortController.signal
        )
    )

    let request = try #require(model.requests.first)
    #expect(request.audio == transcribeAudioData)
    #expect(request.fileName == "sample.wav")
    #expect(request.mimeType == "audio/wav")
    #expect(request.language == "en")
    #expect(request.prompt == "Names are proper nouns.")
    #expect(request.providerOptions == providerOptions)
    #expect(request.headers == ["custom-request-header": "request-header-value"])
    #expect(request.abortSignal === abortController.signal)
}

@Test func aiTranscribeReturnsWarningsAndProviderMetadataLikeUpstream() async throws {
    let warning = AIWarning(type: "other", message: "Setting is not supported")
    let providerMetadata: [String: JSONValue] = [
        "test-provider": [
            "test-key": "test-value"
        ]
    ]
    let model = MockTranscriptionModel(result: TranscriptionResult(
        text: "This is a sample transcript.",
        rawValue: .object([:]),
        warnings: [warning],
        providerMetadata: providerMetadata
    ))

    let result = try await AIWarningLogging.withLoggingDisabled {
        try await AI.transcribe(
            model: model,
            request: AudioTranscriptionRequest(audio: transcribeAudioData)
        )
    }

    #expect(result.warnings == [warning])
    #expect(result.providerMetadata == providerMetadata)
}

@Test func aiTranscribeLogsWarningsLikeUpstream() async throws {
    let expectedWarnings = [
        AIWarning(type: "other", message: "Setting is not supported"),
        AIWarning(
            type: "unsupported",
            feature: "mediaType",
            message: "MediaType parameter not supported"
        )
    ]
    let recorder = TranscribeWarningLogRecorder()
    let model = MockTranscriptionModel(result: TranscriptionResult(
        text: "This is a sample transcript.",
        rawValue: .object([:]),
        warnings: expectedWarnings
    ))

    try await AIWarningLogging.withLogger(recorder) {
        _ = try await AI.transcribe(
            model: model,
            request: AudioTranscriptionRequest(audio: transcribeAudioData)
        )
    }

    #expect(await recorder.events() == [
        AIWarningLogEvent(warnings: expectedWarnings, providerID: "mock", modelID: "mock-transcription")
    ])
}

@Test func aiTranscribeLogsEmptyWarningsLikeUpstream() async throws {
    let recorder = TranscribeWarningLogRecorder()
    let model = MockTranscriptionModel(result: TranscriptionResult(
        text: "This is a sample transcript.",
        rawValue: .object([:]),
        warnings: []
    ))

    try await AIWarningLogging.withLogger(recorder) {
        _ = try await AI.transcribe(
            model: model,
            request: AudioTranscriptionRequest(audio: transcribeAudioData)
        )
    }

    #expect(await recorder.events() == [
        AIWarningLogEvent(warnings: [], providerID: "mock", modelID: "mock-transcription")
    ])
}

@Test func aiTranscribeReturnsTranscriptLikeUpstream() async throws {
    let model = MockTranscriptionModel(result: TranscriptionResult(
        text: "This is a sample transcript.",
        rawValue: .object([:]),
        segments: transcribeSampleSegments,
        language: "en",
        durationInSeconds: 4.0
    ))

    let result = try await AI.transcribe(
        model: model,
        request: AudioTranscriptionRequest(audio: transcribeAudioData)
    )

    #expect(result.text == "This is a sample transcript.")
    #expect(result.segments == transcribeSampleSegments)
    #expect(result.language == "en")
    #expect(result.durationInSeconds == 4.0)
    #expect(result.warnings == [])
    #expect(result.providerMetadata == [:])
}

@Test func aiTranscribeThrowsNoTranscriptGeneratedWhenNoTextLikeUpstream() async throws {
    let responseMetadata = AIResponseMetadata(
        timestamp: Date(timeIntervalSince1970: 1_704_067_200),
        modelID: "test-model-id"
    )
    let model = MockTranscriptionModel(result: TranscriptionResult(
        text: "",
        rawValue: .object([:]),
        segments: [],
        language: "en",
        durationInSeconds: 0,
        responseMetadata: responseMetadata
    ))

    await #expect(throws: AINoOutputError(kind: .transcript, responses: [responseMetadata])) {
        _ = try await AI.transcribe(
            model: model,
            request: AudioTranscriptionRequest(audio: transcribeAudioData)
        )
    }
}

@Test func aiTranscribeIncludesResponseHeadersInNoTranscriptErrorLikeUpstream() async throws {
    let responseMetadata = AIResponseMetadata(
        timestamp: Date(timeIntervalSince1970: 1_704_067_200),
        modelID: "test-model-id",
        headers: [
            "custom-response-header": "response-header-value",
            "user-agent": "ai/0.0.0-test"
        ]
    )
    let model = MockTranscriptionModel(result: TranscriptionResult(
        text: "",
        rawValue: .object([:]),
        segments: [],
        language: "en",
        durationInSeconds: 0,
        responseMetadata: responseMetadata
    ))

    await #expect(throws: AINoOutputError(kind: .transcript, responses: [responseMetadata])) {
        _ = try await AI.transcribe(
            model: model,
            request: AudioTranscriptionRequest(audio: transcribeAudioData)
        )
    }
}

@Test func aiTranscribeReturnsResponseMetadataLikeUpstream() async throws {
    let responseMetadata = AIResponseMetadata(
        timestamp: Date(timeIntervalSince1970: 1_704_067_200),
        modelID: "test-model",
        headers: [
            "x-test": "value"
        ]
    )
    let model = MockTranscriptionModel(result: TranscriptionResult(
        text: "This is a sample transcript.",
        rawValue: .object([:]),
        responseMetadata: responseMetadata
    ))

    let result = try await AI.transcribe(
        model: model,
        request: AudioTranscriptionRequest(audio: transcribeAudioData)
    )

    #expect(result.responseMetadata == responseMetadata)
}

@Test func aiTranscribeFillsRequestMetadataLikeUpstream() async throws {
    let model = MockTranscriptionModel(result: TranscriptionResult(
        text: "This is a sample transcript.",
        rawValue: .object([:])
    ))

    let result = try await AI.transcribe(
        model: model,
        request: AudioTranscriptionRequest(
            audio: transcribeAudioData,
            fileName: "sample.wav",
            mimeType: "audio/wav",
            language: "en",
            prompt: "Names are proper nouns.",
            providerOptions: [
                "testProvider": [
                    "testKey": "testValue"
                ]
            ],
            headers: [
                "custom-request-header": "request-header-value"
            ]
        )
    )

    #expect(result.requestMetadata.headers == ["custom-request-header": "request-header-value"])
    #expect(result.requestMetadata.body?["fileName"]?.stringValue == "sample.wav")
    #expect(result.requestMetadata.body?["mimeType"]?.stringValue == "audio/wav")
    #expect(result.requestMetadata.body?["byteLength"]?.intValue == 4)
    #expect(result.requestMetadata.body?["language"]?.stringValue == "en")
    #expect(result.requestMetadata.body?["prompt"]?.stringValue == "Names are proper nouns.")
    #expect(result.requestMetadata.body?["providerOptions"]?["testProvider"]?["testKey"]?.stringValue == "testValue")
}

private actor TranscribeWarningLogRecorder: AIWarningLogger {
    private var recordedEvents: [AIWarningLogEvent] = []

    func logWarnings(_ event: AIWarningLogEvent) {
        recordedEvents.append(event)
    }

    func events() -> [AIWarningLogEvent] {
        recordedEvents
    }
}
