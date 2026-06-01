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
