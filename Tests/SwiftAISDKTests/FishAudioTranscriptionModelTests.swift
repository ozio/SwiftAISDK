import Foundation
import Testing
@testable import SwiftAISDK

@Test func fishAudioTranscriptionSendsMultipartAndMapsResponse() async throws {
    let controller = AIAbortController()
    let transport = RecordingTransport(response: jsonResponse(
        """
        {
          "language": "English",
          "language_code": "en",
          "text": "Hello, world!",
          "duration": 2.5,
          "segments": [
            {"text":"Hello,","start":0,"end":1.2},
            {"text":"world!","start":1.2,"end":2.5}
          ]
        }
        """,
        headers: ["x-request-id": "fish-transcription-request"]
    ))
    let model = try createFishAudio(settings: ProviderSettings(
        apiKey: "fish-key",
        environment: [:],
        transport: transport
    )).transcription()

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data([0, 1, 2, 3, 4]),
        fileName: "ignored.mp3",
        mimeType: "audio/mpeg",
        providerOptions: [
            "fishAudio": [
                "language": "ja",
                "ignoreTimestamps": false
            ]
        ],
        headers: ["X-Request": "request-value"],
        abortSignal: controller.signal
    ))

    #expect(result.text == "Hello, world!")
    #expect(result.language == "en")
    #expect(result.durationInSeconds == 2.5)
    #expect(result.segments == [
        TranscriptionSegment(text: "Hello,", startSecond: 0, endSecond: 1.2),
        TranscriptionSegment(text: "world!", startSecond: 1.2, endSecond: 2.5)
    ])
    #expect(result.warnings.isEmpty)
    #expect(result.providerMetadata == [
        "fishAudio": ["language": "English"]
    ])
    #expect(result.responseMetadata.modelID == "transcribe-1")
    #expect(result.responseMetadata.headers["x-request-id"] == "fish-transcription-request")
    #expect(result.responseMetadata.body == result.rawValue)
    #expect(result.requestMetadata.body == [
        "audio": [
            "filename": "audio.mp3",
            "mimeType": "audio/mpeg",
            "byteLength": 5
        ],
        "language": "ja",
        "ignore_timestamps": false
    ])

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.fish.audio/v1/asr")
    #expect(request.headers["authorization"] == "Bearer fish-key")
    #expect(request.headers["user-agent"] == "ai-sdk/fish-audio/3.0.12")
    #expect(request.headers["model"] == nil)
    #expect(request.headers["content-type"]?.hasPrefix(
        "multipart/form-data; boundary=SwiftAISDK-"
    ) == true)
    #expect(request.headers["X-Request"] == "request-value")
    #expect(request.abortSignal === controller.signal)

    let body = String(decoding: try #require(request.body), as: UTF8.self)
    #expect(body.contains("name=\"audio\"; filename=\"audio.mp3\""))
    #expect(body.contains("Content-Type: audio/mpeg"))
    #expect(body.contains("name=\"language\""))
    #expect(body.contains("\r\nja\r\n"))
    #expect(body.contains("name=\"ignore_timestamps\""))
    #expect(body.contains("\r\nfalse\r\n"))
    #expect(!body.contains("ignored.mp3"))
    #expect(!body.contains("transcribe-1"))
}

@Test func fishAudioTranscriptionDefaultsTimestampsAndAllowsOptOut() async throws {
    let response = jsonResponse(#"{"text":"Hello","segments":[]}"#)
    let transport = RecordingTransport(responses: [response, response])
    let model = try createFishAudio(settings: ProviderSettings(
        apiKey: "fish-key",
        environment: [:],
        transport: transport
    )).transcriptionModel("custom-route")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("one".utf8),
        mimeType: "audio/wav"
    ))
    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("two".utf8),
        mimeType: "audio/wav",
        providerOptions: [
            "fishAudio": ["ignoreTimestamps": true]
        ]
    ))

    let requests = await transport.requests()
    let first = String(decoding: try #require(requests[0].body), as: UTF8.self)
    let second = String(decoding: try #require(requests[1].body), as: UTF8.self)
    #expect(first.contains("\r\nfalse\r\n"))
    #expect(second.contains("\r\ntrue\r\n"))
    #expect(requests.allSatisfy { $0.headers["model"] == nil })
}

@Test func fishAudioTranscriptionHandlesOptionalResponseFields() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"text":"No details"}"#),
        jsonResponse(#"{"text":"Null details","language":null,"language_code":null,"duration":null,"segments":null}"#)
    ])
    let model = try createFishAudio(settings: ProviderSettings(
        apiKey: "fish-key",
        environment: [:],
        transport: transport
    )).transcription()

    for expectedText in ["No details", "Null details"] {
        let result = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8)
        ))
        #expect(result.text == expectedText)
        #expect(result.language == nil)
        #expect(result.durationInSeconds == nil)
        #expect(result.segments.isEmpty)
        #expect(result.providerMetadata.isEmpty)
    }
}

@Test func fishAudioTranscriptionValidatesOptionsAndResponseSchema() async throws {
    let validTransport = RecordingTransport(response: jsonResponse(
        #"{"text":"unused"}"#
    ))
    let validModel = try createFishAudio(settings: ProviderSettings(
        apiKey: "fish-key",
        environment: [:],
        transport: validTransport
    )).transcription()

    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.fishAudio.ignoreTimestamps",
        message: "Fish Audio ignoreTimestamps must be a boolean."
    )) {
        _ = try await validModel.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: [
                "fishAudio": ["ignoreTimestamps": "yes"]
            ]
        ))
    }
    #expect(await validTransport.requests().isEmpty)

    let invalidTransport = RecordingTransport(response: jsonResponse(
        #"{"text":"invalid","segments":[{"text":"bad","start":"zero","end":1}]}"#
    ))
    let invalidModel = try createFishAudio(settings: ProviderSettings(
        apiKey: "fish-key",
        environment: [:],
        transport: invalidTransport
    )).transcription()
    await #expect(throws: AIError.invalidResponse(
        provider: "fish-audio.transcription",
        message: "Fish Audio transcription response segments[0] is invalid."
    )) {
        _ = try await invalidModel.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8)
        ))
    }
}

@Test func fishAudioTranscriptionSupportsExtraMultipartFields() async throws {
    let transport = RecordingTransport(response: jsonResponse(
        #"{"text":"Hello","segments":[]}"#
    ))
    let model = try createFishAudio(settings: ProviderSettings(
        apiKey: "fish-key",
        environment: [:],
        transport: transport
    )).transcription()

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        providerOptions: [
            "fishAudio": ["unknownOption": "stripped"]
        ],
        extraBody: [
            "ignore_timestamps": true,
            "custom_flag": "enabled"
        ]
    ))

    #expect(result.requestMetadata.body?["ignore_timestamps"] == true)
    #expect(result.requestMetadata.body?["custom_flag"] == "enabled")
    let request = try #require(await transport.requests().first)
    let body = String(decoding: try #require(request.body), as: UTF8.self)
    #expect(body.contains("\r\ntrue\r\n"))
    #expect(body.contains("name=\"custom_flag\""))
    #expect(body.contains("\r\nenabled\r\n"))
    #expect(!body.contains("unknownOption"))
}

@Test func fishAudioTranscriptionSurfacesStructuredAPIErrors() async throws {
    let responses = [
        AIHTTPResponse(
            statusCode: 401,
            body: Data(#"{"status":401,"message":"No permission -- see authorization schemes"}"#.utf8)
        ),
        AIHTTPResponse(
            statusCode: 402,
            body: Data(#"{"status":402}"#.utf8)
        )
    ]
    let transport = RecordingTransport(responses: responses)
    let model = try createFishAudio(settings: ProviderSettings(
        apiKey: "fish-key",
        environment: [:],
        transport: transport
    )).transcription()

    do {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8)
        ))
        Issue.record("Expected Fish Audio authorization error")
    } catch let AIError.apiCall(error) {
        #expect(error.provider == "fish-audio.transcription")
        #expect(error.statusCode == 401)
        #expect(error.responseBody == "No permission -- see authorization schemes")
    }

    do {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8)
        ))
        Issue.record("Expected Fish Audio payment error")
    } catch let AIError.apiCall(error) {
        #expect(error.statusCode == 402)
        #expect(error.responseBody == "Unknown Fish Audio error")
    }
}
