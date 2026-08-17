import Foundation
import Testing
@testable import SwiftAISDK

@Test func cartesiaBatchTranscriptionSendsMultipartAndParsesDetails() async throws {
    let controller = AIAbortController()
    let transport = RecordingTransport(response: jsonResponse(
        """
        {
          "text": "Hello from SwiftAISDK.",
          "language": "en",
          "duration": 2.479,
          "words": [
            {"word": "Hello", "start": 0.199, "end": 0.479},
            {"word": "SwiftAISDK.", "start": 0.5, "end": 2.479}
          ]
        }
        """,
        headers: ["x-request-id": "transcription-request"]
    ))
    let provider = try AIProviders.cartesia(settings: CartesiaProviderSettings(
        apiKey: "cartesia-key",
        headers: ["Custom-Provider-Header": "provider-value"],
        environment: [:],
        transport: transport
    ))
    let model = try provider.transcriptionModel("ink-whisper")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        fileName: "ignored-name.wav",
        mimeType: "audio/wav",
        language: "fr",
        providerOptions: [
            "cartesia": [
                "language": "en",
                "timestampGranularities": ["word"]
            ]
        ],
        headers: ["Custom-Request-Header": "request-value"],
        abortSignal: controller.signal
    ))

    #expect(result.text == "Hello from SwiftAISDK.")
    #expect(result.language == "en")
    #expect(result.durationInSeconds == 2.479)
    #expect(result.segments == [
        TranscriptionSegment(text: "Hello", startSecond: 0.199, endSecond: 0.479),
        TranscriptionSegment(text: "SwiftAISDK.", startSecond: 0.5, endSecond: 2.479)
    ])
    #expect(result.rawValue["words"]?.arrayValue?.count == 2)
    #expect(result.responseMetadata.modelID == "ink-whisper")
    #expect(result.responseMetadata.headers["x-request-id"] == "transcription-request")
    #expect(result.requestMetadata.body == [
        "model": "ink-whisper",
        "file": [
            "filename": "audio.wav",
            "mimeType": "audio/wav",
            "byteLength": 5
        ],
        "language": "en",
        "timestampGranularities": ["word"]
    ])

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.cartesia.ai/stt")
    #expect(request.headers["authorization"] == "Bearer cartesia-key")
    #expect(request.headers["cartesia-version"] == "2026-03-01")
    #expect(request.headers["custom-provider-header"] == "provider-value")
    #expect(request.headers["Custom-Request-Header"] == "request-value")
    #expect(request.headers["user-agent"] == "ai-sdk/cartesia/3.0.22")
    #expect(request.headers["content-type"]?.hasPrefix("multipart/form-data; boundary=SwiftAISDK-") == true)
    #expect(request.abortSignal === controller.signal)

    let body = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(body.contains("name=\"model\""))
    #expect(body.contains("ink-whisper"))
    #expect(body.contains("name=\"file\"; filename=\"audio.wav\""))
    #expect(body.contains("Content-Type: audio/wav"))
    #expect(body.contains("name=\"language\""))
    #expect(body.contains("en"))
    #expect(body.contains("name=\"timestamp_granularities[]\""))
    #expect(body.contains("word"))
    #expect(!body.contains("ignored-name.wav"))
    #expect(!body.contains("\r\nfr\r\n"))
}

@Test func cartesiaBatchTranscriptionWarnsForStreamingOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(
        #"{"text":"batch","language":null,"duration":null,"words":null}"#
    ))
    let provider = try AIProviders.cartesia(settings: CartesiaProviderSettings(
        apiKey: "cartesia-key",
        environment: [:],
        transport: transport
    ))
    let model = try provider.transcriptionModel("ink-whisper")

    let result = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        providerOptions: [
            "cartesia": [
                "streaming": [
                    "turnDetection": false
                ]
            ]
        ]
    ))

    #expect(result.text == "batch")
    #expect(result.language == nil)
    #expect(result.durationInSeconds == nil)
    #expect(result.segments.isEmpty)
    #expect(result.warnings == [
        AIWarning(
            type: "unsupported",
            feature: "providerOptions.cartesia.streaming",
            message: "Cartesia batch transcription does not support streaming options."
        )
    ])
}

@Test func cartesiaBatchTranscriptionRejectsInk2WithoutRESTCall() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"unused"}"#))
    let provider = try AIProviders.cartesia(settings: CartesiaProviderSettings(
        apiKey: "cartesia-key",
        environment: [:],
        transport: transport
    ))

    for modelID in ["ink-2", "ink-2-2026-03"] {
        let model = try provider.transcriptionModel(modelID)
        await #expect(throws: AIError.invalidArgument(
            argument: "modelID",
            message: "Cartesia \(modelID) supports streaming transcription, which SwiftAISDK does not currently expose."
        )) {
            _ = try await model.transcribe(AudioTranscriptionRequest(
                audio: Data("audio".utf8)
            ))
        }
    }
    #expect(await transport.requests().isEmpty)
}

@Test func cartesiaBatchTranscriptionValidatesOptionsAndResponseSchema() async throws {
    let validTransport = RecordingTransport(response: jsonResponse(#"{"text":"unused"}"#))
    let provider = try AIProviders.cartesia(settings: CartesiaProviderSettings(
        apiKey: "cartesia-key",
        environment: [:],
        transport: validTransport
    ))
    let model = try provider.transcriptionModel("ink-whisper")

    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.cartesia.timestampGranularities",
        message: "Cartesia timestampGranularities only supports word."
    )) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: [
                "cartesia": [
                    "timestampGranularities": ["segment"]
                ]
            ]
        ))
    }

    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.cartesia.streaming",
        message: "Cartesia streaming options must be an object."
    )) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: [
                "cartesia": [
                    "streaming": .null
                ]
            ]
        ))
    }

    await #expect(throws: AIError.invalidArgument(
        argument: "providerOptions.cartesia.streaming.turnDetection",
        message: "Cartesia turnDetection must be a boolean."
    )) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8),
            providerOptions: [
                "cartesia": [
                    "streaming": [
                        "turnDetection": .null
                    ]
                ]
            ]
        ))
    }

    let invalidProvider = try AIProviders.cartesia(settings: CartesiaProviderSettings(
        apiKey: "cartesia-key",
        environment: [:],
        transport: RecordingTransport(response: jsonResponse(
            #"{"text":"invalid","words":[{"word":"bad","start":"zero","end":1}]}"#
        ))
    ))
    let invalidModel = try invalidProvider.transcriptionModel("ink-whisper")
    await #expect(throws: AIError.invalidResponse(
        provider: "cartesia.transcription",
        message: "Cartesia transcription response words[0] is invalid."
    )) {
        _ = try await invalidModel.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8)
        ))
    }
}

@Test func cartesiaBatchTranscriptionMapsGenericLanguage() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"text":"bonjour"}"#))
    let provider = try AIProviders.cartesia(settings: CartesiaProviderSettings(
        apiKey: "cartesia-key",
        environment: [:],
        transport: transport
    ))
    let model = try provider.transcriptionModel("ink-whisper")

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        mimeType: "audio/mpeg",
        language: "fr"
    ))

    let body = String(
        data: try #require(await transport.requests().first?.body),
        encoding: .utf8
    ) ?? ""
    #expect(body.contains("name=\"language\""))
    #expect(body.contains("\r\nfr\r\n"))
    #expect(body.contains("filename=\"audio.mp3\""))
}

@Test func cartesiaBatchTranscriptionUsesStructuredErrorMessage() async throws {
    let headers = ["content-type": "application/json", "x-request-id": "error"]
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 429,
        headers: headers,
        body: Data("""
        {"error_code":"rate_limited","title":"Rate limited","message":"Try again.","request_id":"request-id"}
        """.utf8)
    ))
    let provider = try AIProviders.cartesia(settings: CartesiaProviderSettings(
        apiKey: "cartesia-key",
        environment: [:],
        transport: transport
    ))
    let model = try provider.transcriptionModel("ink-whisper")

    await #expect(throws: AIError.apiCall(
        provider: "cartesia.transcription",
        statusCode: 429,
        body: "Rate limited: Try again.",
        headers: headers
    )) {
        _ = try await model.transcribe(AudioTranscriptionRequest(
            audio: Data("audio".utf8)
        ))
    }
}
