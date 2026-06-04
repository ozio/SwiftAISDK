import Foundation
import Testing
@testable import SwiftAISDK

actor ToolCapture {
    private var arguments: JSONValue?

    func record(_ arguments: JSONValue) {
        self.arguments = arguments
    }

    func value() -> JSONValue? {
        arguments
    }
}
actor ToolExecutionContextCapture {
    private var recordedArguments: JSONValue?
    private var recordedContext: AIToolExecutionContext?

    func record(arguments: JSONValue, context: AIToolExecutionContext) {
        recordedArguments = arguments
        recordedContext = context
    }

    func snapshot() -> (arguments: JSONValue?, context: AIToolExecutionContext?) {
        (recordedArguments, recordedContext)
    }
}
actor PrepareStepCapture {
    private var numbers: [Int] = []
    private var steps: [Int] = []
    private var responseMessages: [Int] = []

    func record(_ context: AIPrepareStepContext) {
        numbers.append(context.stepNumber)
        steps.append(context.steps.count)
        responseMessages.append(context.responseMessages.count)
    }

    func stepNumbers() -> [Int] {
        numbers
    }

    func stepCounts() -> [Int] {
        steps
    }

    func responseMessageCounts() -> [Int] {
        responseMessages
    }
}
final class MockLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-language"
    var requests: [LanguageModelRequest] = []
    var streamRequests: [LanguageModelRequest] = []
    private var results: [TextGenerationResult]
    private var streamSequences: [[LanguageStreamPart]]

    init(result: TextGenerationResult, streamParts: [LanguageStreamPart] = []) {
        self.results = [result]
        self.streamSequences = [streamParts]
    }

    init(results: [TextGenerationResult], streamParts: [LanguageStreamPart] = []) {
        self.results = results
        self.streamSequences = [streamParts]
    }

    init(result: TextGenerationResult, streamSequences: [[LanguageStreamPart]]) {
        self.results = [result]
        self.streamSequences = streamSequences
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        requests.append(request)
        return results.count > 1 ? results.removeFirst() : results[0]
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamRequests.append(request)
        let parts = streamSequences.count > 1 ? streamSequences.removeFirst() : streamSequences[0]
        return AsyncThrowingStream { continuation in
            for part in parts {
                continuation.yield(part)
            }
            continuation.finish()
        }
    }
}
final class FlakyLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "flaky-language"
    var requests: [LanguageModelRequest] = []
    private var failures: [Error]
    private let result: TextGenerationResult

    init(failures: [Error], result: TextGenerationResult) {
        self.failures = failures
        self.result = result
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        requests.append(request)
        if !failures.isEmpty {
            throw failures.removeFirst()
        }
        return result
    }
}
actor TelemetryRecorder: Telemetry.Integration {
    private var recordedEvents: [Telemetry.Event] = []

    func record(_ event: Telemetry.Event) {
        recordedEvents.append(event)
    }

    func events() -> [Telemetry.Event] {
        recordedEvents
    }
}
actor ExecutionWrapperLog {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func entries() -> [String] {
        values
    }
}
struct ExecutionWrappingTelemetry: Telemetry.Integration {
    var name: String
    var log: ExecutionWrapperLog

    func record(_ event: Telemetry.Event) {}

    func executeLanguageModelCall<Output: Sendable>(_ context: Telemetry.LanguageModelCallContext<Output>) async throws -> Output {
        await log.append("\(name)-language-start:\(context.operationID):\(context.modelID ?? "unknown")")
        let result = try await context.execute()
        await log.append("\(name)-language-end")
        return result
    }

    func executeTool<Output: Sendable>(_ context: Telemetry.ToolExecutionContext<Output>) async throws -> Output {
        await log.append("\(name)-tool-start:\(context.toolCallID):\(context.toolName)")
        let result = try await context.execute()
        await log.append("\(name)-tool-end")
        return result
    }
}
final class SlowLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "slow-language"
    var requests: [LanguageModelRequest] = []
    let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        requests.append(request)
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return TextGenerationResult(text: "late", rawValue: .object([:]))
    }
}
final class SlowStreamingLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "slow-stream-language"
    var requests: [LanguageModelRequest] = []
    var streamRequests: [LanguageModelRequest] = []
    let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        requests.append(request)
        return TextGenerationResult(text: "", rawValue: .object([:]))
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamRequests.append(request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                    continuation.yield(.textDelta("late"))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
final class HangingStreamingLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "hanging-stream-language"
    var streamRequests: [LanguageModelRequest] = []

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        TextGenerationResult(text: "", rawValue: .object([:]))
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamRequests.append(request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.textDelta("first"))
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    continuation.yield(.textDelta("late"))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
enum StreamingOutcome {
    case failure(Error)
    case parts([LanguageStreamPart])
    case partsThenFailure([LanguageStreamPart], Error)
}
final class FlakyStreamingLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "flaky-stream-language"
    var requests: [LanguageModelRequest] = []
    var streamRequests: [LanguageModelRequest] = []
    private var outcomes: [StreamingOutcome]

    init(outcomes: [StreamingOutcome]) {
        self.outcomes = outcomes
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        requests.append(request)
        return TextGenerationResult(text: "", rawValue: .object([:]))
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamRequests.append(request)
        let outcome = outcomes.count > 1 ? outcomes.removeFirst() : outcomes[0]
        return AsyncThrowingStream { continuation in
            switch outcome {
            case let .failure(error):
                continuation.finish(throwing: error)
            case let .parts(parts):
                for part in parts {
                    continuation.yield(part)
                }
                continuation.finish()
            case let .partsThenFailure(parts, error):
                for part in parts {
                    continuation.yield(part)
                }
                continuation.finish(throwing: error)
            }
        }
    }
}
final class MockEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-embedding"
    var requests: [EmbeddingRequest] = []
    private var results: [EmbeddingResult]

    init(results: [EmbeddingResult]) {
        self.results = results
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        requests.append(request)
        return results.count > 1 ? results.removeFirst() : results[0]
    }
}
final class SlowEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "slow-embedding"
    var requests: [EmbeddingRequest] = []
    let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        requests.append(request)
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return EmbeddingResult(embeddings: [[0.1]], rawValue: .object([:]))
    }
}
final class MockImageModel: ImageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-image"
    var requests: [ImageGenerationRequest] = []
    let result: ImageGenerationResult

    init(result: ImageGenerationResult) { self.result = result }

    func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        requests.append(request)
        return result
    }
}
final class MockTranscriptionModel: TranscriptionModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-transcription"
    var requests: [AudioTranscriptionRequest] = []
    let result: TranscriptionResult

    init(result: TranscriptionResult) { self.result = result }

    func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        requests.append(request)
        return result
    }
}
final class MockSpeechModel: SpeechModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-speech"
    var requests: [SpeechRequest] = []
    let result: SpeechResult

    init(result: SpeechResult) { self.result = result }

    func speak(_ request: SpeechRequest) async throws -> SpeechResult {
        requests.append(request)
        return result
    }
}
final class MockVideoModel: VideoModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-video"
    var requests: [VideoGenerationRequest] = []
    let result: VideoGenerationResult

    init(result: VideoGenerationResult) { self.result = result }

    func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        requests.append(request)
        return result
    }
}
final class MockRerankingModel: RerankingModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-reranking"
    var requests: [RerankingRequest] = []
    let result: RerankingResult

    init(result: RerankingResult) { self.result = result }

    func rerank(_ request: RerankingRequest) async throws -> RerankingResult {
        requests.append(request)
        return result
    }
}
final class MockFileClient: AIFileClient, @unchecked Sendable {
    let providerID = "mock.files"
    var requests: [FileUploadRequest] = []
    let result: FileUploadResult

    init(result: FileUploadResult) { self.result = result }

    func uploadFile(_ request: FileUploadRequest) async throws -> FileUploadResult {
        requests.append(request)
        return result
    }
}
final class MockSkillsClient: AISkillsClient, @unchecked Sendable {
    let providerID = "mock.skills"
    var requests: [SkillUploadRequest] = []
    let result: SkillUploadResult

    init(result: SkillUploadResult) { self.result = result }

    func uploadSkill(_ request: SkillUploadRequest) async throws -> SkillUploadResult {
        requests.append(request)
        return result
    }
}
