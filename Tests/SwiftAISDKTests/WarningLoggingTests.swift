import Foundation
import Testing
@testable import SwiftAISDK

@Test func warningLoggingRecordsFacadeStreamWarningsAndDisableState() async throws {
    let warning = AIWarning(type: "unsupported", feature: "seed", message: "Use providerOptions instead.")
    let recorder = WarningLogRecorder()

    try await AIWarningLogging.withLogger(recorder) {
        let result = try await AI.generateText(
            model: WarningLanguageModel(result: TextGenerationResult(text: "done", rawValue: .object([:]), warnings: [warning])),
            prompt: "Hello",
            retryPolicy: .none
        )

        #expect(result.warnings == [warning])
        #expect(await recorder.events() == [
            AIWarningLogEvent(warnings: [warning], providerID: "warning-test", modelID: "language")
        ])

        let streamWarning = AIWarning(type: "other", message: "stream warning")

        let stream = AI.streamText(
            model: WarningLanguageModel(
                result: TextGenerationResult(text: "", rawValue: .object([:])),
                streamParts: [
                    .streamStart(warnings: [streamWarning]),
                    .textDelta("hello"),
                    .finish(reason: "stop", usage: nil)
                ]
            ),
            request: LanguageModelRequest(messages: [.user("Hello")]),
            retryPolicy: .none
        )

        for try await _ in stream {}

        #expect(await recorder.events() == [
            AIWarningLogEvent(warnings: [warning], providerID: "warning-test", modelID: "language"),
            AIWarningLogEvent(warnings: [streamWarning], providerID: "warning-test", modelID: "language")
        ])

        try await AIWarningLogging.withLoggingDisabled {
            _ = try await AI.generateText(
                model: WarningLanguageModel(result: TextGenerationResult(
                    text: "done",
                    rawValue: .object([:]),
                    warnings: [AIWarning(type: "deprecated", setting: "oldSetting", message: "Use newSetting.")]
                )),
                prompt: "Hello",
                retryPolicy: .none
            )
        }

        #expect(await recorder.events().count == 2)
    }
}

@Test func warningLoggingRecordsStreamWarningsOncePerToolLoopStepLikeUpstream() async throws {
    let warning1 = AIWarning(type: "other", message: "Warning from step 1")
    let warning2 = AIWarning(type: "other", message: "Warning from step 2")
    let toolCall = AIToolCall(
        id: "call-1",
        name: "testTool",
        arguments: #"{ "value": "test" }"#
    )
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .streamStart(warnings: [warning1]),
                .responseMetadata(AIResponseMetadata(id: "id-0", timestamp: Date(timeIntervalSince1970: 0), modelID: "mock-model-id")),
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .streamStart(warnings: [warning2]),
                .responseMetadata(AIResponseMetadata(id: "id-1", timestamp: Date(timeIntervalSince1970: 10), modelID: "mock-model-id")),
                .textStart(id: "1"),
                .textDeltaPart(id: "1", delta: "Final response"),
                .textEnd(id: "1"),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
            ]
        ]
    )
    let tool = AITool(
        name: "testTool",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { _ in
        .string("result")
    }
    let recorder = WarningLogRecorder()

    try await AIWarningLogging.withLogger(recorder) {
        for try await _ in AI.streamText(
            model: model,
            prompt: "test-input",
            executableTools: [tool],
            maxSteps: 3,
            retryPolicy: .none
        ) {}
    }

    #expect(await recorder.events() == [
        AIWarningLogEvent(warnings: [warning1], providerID: "mock", modelID: "mock-language"),
        AIWarningLogEvent(warnings: [warning2], providerID: "mock", modelID: "mock-language")
    ])
}

@Test func warningLoggingRecordsGenerateWarningsOncePerToolLoopStepLikeUpstream() async throws {
    let warning1 = AIWarning(type: "other", message: "Warning from step 1")
    let warning2 = AIWarning(type: "other", message: "Warning from step 2")
    let toolCall = AIToolCall(
        id: "call-1",
        name: "testTool",
        arguments: #"{ "value": "test" }"#
    )
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            finishReason: "tool-calls",
            toolCalls: [toolCall],
            rawValue: .object([:]),
            warnings: [warning1]
        ),
        TextGenerationResult(
            text: "Final response",
            finishReason: "stop",
            rawValue: .object([:]),
            warnings: [warning2]
        )
    ])
    let tool = AITool(
        name: "testTool",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { _ in
        .string("result")
    }
    let recorder = WarningLogRecorder()

    try await AIWarningLogging.withLogger(recorder) {
        _ = try await AI.generateText(
            model: model,
            prompt: "test-input",
            executableTools: [tool],
            maxSteps: 3,
            retryPolicy: .none
        )
    }

    #expect(await recorder.events() == [
        AIWarningLogEvent(warnings: [warning1], providerID: "mock", modelID: "mock-language"),
        AIWarningLogEvent(warnings: [warning2], providerID: "mock", modelID: "mock-language")
    ])
}

@Test func warningLoggingFormatsKnownWarningTypes() {
    #expect(AIWarningLogging.formattedMessage(
        for: AIWarning(type: "deprecated", setting: "foo", message: "Use bar."),
        providerID: "provider",
        modelID: "model"
    ) == "AI SDK Warning (provider / model): Deprecated: \"foo\". Use bar.")
    #expect(AIWarningLogging.formattedMessage(
        for: AIWarning(type: "unsupported", feature: "seed")
    ) == "AI SDK Warning: The feature \"seed\" is not supported.")
}

@Test func warningLoggingPassesEmptyWarningsLikeUpstream() async throws {
    let recorder = WarningLogRecorder()

    await AIWarningLogging.withLogger(recorder) {
        await AIWarningLogging.logWarnings([], providerID: "prov", modelID: "model")
    }

    #expect(await recorder.events() == [
        AIWarningLogEvent(warnings: [], providerID: "prov", modelID: "model")
    ])
}

@Test func warningLoggingPassesMultipleWarningsToCustomLoggerLikeUpstream() async throws {
    let warnings = [
        AIWarning(type: "unsupported", feature: "temperature", message: "Temperature not supported."),
        AIWarning(type: "other", message: "Another warning")
    ]
    let recorder = WarningLogRecorder()

    await AIWarningLogging.withLogger(recorder) {
        await AIWarningLogging.logWarnings(warnings, providerID: "provider", modelID: "model")
    }

    #expect(await recorder.events() == [
        AIWarningLogEvent(warnings: warnings, providerID: "provider", modelID: "model")
    ])
}

@Test func warningLoggingFormatsUpstreamWarningMessagesWithProviderAndModel() {
    let messages = [
        AIWarningLogging.formattedMessage(
            for: AIWarning(type: "unsupported", feature: "mediaType", message: "detail"),
            providerID: "zzz",
            modelID: "MMM"
        ),
        AIWarningLogging.formattedMessage(
            for: AIWarning(type: "unsupported", feature: "voice", message: "detail2"),
            providerID: "zzz",
            modelID: "MMM"
        ),
        AIWarningLogging.formattedMessage(
            for: AIWarning(type: "deprecated", setting: "providerOptions key 'old-key'", message: "Use 'oldKey' instead."),
            providerID: "zzz",
            modelID: "MMM"
        ),
        AIWarningLogging.formattedMessage(
            for: AIWarning(type: "other", message: "other msg"),
            providerID: "zzz",
            modelID: "MMM"
        ),
        AIWarningLogging.formattedMessage(
            for: AIWarning(type: "other", message: "messx"),
            providerID: "unknown provider",
            modelID: "unknown model"
        )
    ]

    #expect(messages == [
        "AI SDK Warning (zzz / MMM): The feature \"mediaType\" is not supported. detail",
        "AI SDK Warning (zzz / MMM): The feature \"voice\" is not supported. detail2",
        "AI SDK Warning (zzz / MMM): Deprecated: \"providerOptions key 'old-key'\". Use 'oldKey' instead.",
        "AI SDK Warning (zzz / MMM): other msg",
        "AI SDK Warning (unknown provider / unknown model): messx"
    ])
}

private actor WarningLogRecorder: AIWarningLogger {
    private var recordedEvents: [AIWarningLogEvent] = []

    func logWarnings(_ event: AIWarningLogEvent) {
        recordedEvents.append(event)
    }

    func events() -> [AIWarningLogEvent] {
        recordedEvents
    }
}

private final class WarningLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "warning-test"
    let modelID = "language"
    private let result: TextGenerationResult
    private let streamParts: [LanguageStreamPart]

    init(result: TextGenerationResult, streamParts: [LanguageStreamPart] = []) {
        self.result = result
        self.streamParts = streamParts
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        result
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            for part in streamParts {
                continuation.yield(part)
            }
            continuation.finish()
        }
    }
}
