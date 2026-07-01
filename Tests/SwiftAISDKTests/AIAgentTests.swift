import Foundation
import Testing
@testable import SwiftAISDK

@Test func toolLoopAgentWrapsGenerateCallsLikeAISDKAgent() async throws {
    let model = AgentRecordingLanguageModel(result: TextGenerationResult(text: "done", rawValue: .object([:])))
    let abortController = AIAbortController()
    let agent = AIToolLoopAgent(
        id: "agent-1",
        model: model,
        instructions: "Be precise.",
        requestOptions: AIChatRequestOptions(
            temperature: 0.3,
            topP: 0.9,
            topK: 40,
            presencePenalty: 0.1,
            frequencyPenalty: 0.2,
            seed: 42,
            maxOutputTokens: 256,
            stopSequences: ["STOP", "END"],
            includeRawChunks: true,
            providerOptions: ["default": .object(["value": .string("base")])],
            headers: ["x-default": "1"]
        )
    )

    let result = try await agent.generate(
        prompt: "Hello",
        options: AIAgentCallOptions(
            requestOptions: AIChatRequestOptions(
                temperature: 0.8,
                providerOptions: ["call": .object(["value": .string("override")])],
                headers: ["x-call": "2"]
            ),
            abortSignal: abortController.signal
        )
    )

    #expect(result.text == "done")
    #expect(agent.version == "agent-v1")
    #expect(agent.id == "agent-1")
    #expect(agent.maxSteps == 20)

    let request = try #require(model.generateRequests.first)
    #expect(request.messages == [.system("Be precise."), .user("Hello")])
    #expect(request.temperature == 0.8)
    #expect(request.topP == 0.9)
    #expect(request.topK == 40)
    #expect(request.presencePenalty == 0.1)
    #expect(request.frequencyPenalty == 0.2)
    #expect(request.seed == 42)
    #expect(request.maxOutputTokens == 256)
    #expect(request.stopSequences == ["STOP", "END"])
    #expect(request.includeRawChunks)
    #expect(request.providerOptions["default"]?["value"]?.stringValue == "base")
    #expect(request.providerOptions["call"]?["value"]?.stringValue == "override")
    #expect(request.headers["x-default"] == "1")
    #expect(request.headers["x-call"] == "2")
    #expect(request.abortSignal === abortController.signal)
}

@Test func toolLoopAgentAppliesGenerateTimeoutLikeUpstream() async throws {
    let model = SlowLanguageModel(delayNanoseconds: 80_000_000)
    let agent = AIToolLoopAgent(model: model, retryPolicy: .none)

    do {
        _ = try await agent.generate(
            prompt: "Too slow",
            options: AIAgentCallOptions(timeoutNanoseconds: 1_000_000, retryPolicy: AIRetryPolicy.none)
        )
        Issue.record("Expected agent generate timeout.")
    } catch let error as AIError {
        #expect(error == .timeout(durationNanoseconds: 1_000_000))
    }

    #expect(model.requests.count == 1)
}

@Test func toolLoopAgentRejectsSystemMessagesByDefaultLikeUpstream() async throws {
    let model = AgentRecordingLanguageModel(result: TextGenerationResult(text: "done", rawValue: .object([:])))
    let agent = AIToolLoopAgent(model: model, retryPolicy: .none)
    let messages: [AIMessage] = [.system("SYSTEM INSTRUCTIONS")]

    await #expect(throws: AIError.invalidArgument(
        argument: "messages",
        message: "System messages are not allowed in the prompt or messages fields. Use the instructions option instead."
    )) {
        _ = try await agent.generate(messages: messages)
    }

    #expect(model.generateRequests.isEmpty)
}

@Test func toolLoopAgentAllowsSystemMessagesWhenEnabledLikeUpstream() async throws {
    let model = AgentRecordingLanguageModel(result: TextGenerationResult(text: "done", rawValue: .object([:])))
    let agent = AIToolLoopAgent(model: model, allowSystemInMessages: true, retryPolicy: .none)
    let messages: [AIMessage] = [.system("SYSTEM INSTRUCTIONS")]

    _ = try await agent.generate(messages: messages)

    let request = try #require(model.generateRequests.first)
    #expect(request.messages == messages)
}

@Test func toolLoopAgentAppliesStreamTimeoutAndTelemetryLikeUpstream() async throws {
    let recorder = TelemetryRecorder()
    let model = SlowStreamingLanguageModel(delayNanoseconds: 80_000_000)
    let agent = AIToolLoopAgent(model: model, retryPolicy: .none)

    do {
        for try await _ in agent.stream(
            prompt: "Too slow",
            options: AIAgentCallOptions(
                timeoutNanoseconds: 1_000_000,
                retryPolicy: AIRetryPolicy.none,
                telemetry: Telemetry.Options(integrations: [recorder])
            )
        ) {}
        Issue.record("Expected agent stream timeout.")
    } catch let error as AIError {
        #expect(error == .timeout(durationNanoseconds: 1_000_000))
    }

    let events = await recorder.events()
    #expect(model.streamRequests.count == 1)
    #expect(events.map(\.kind) == [.start, .error])
    #expect(events.first?.operationID == "ai.streamText")
}

@Test func toolLoopAgentRejectsStreamSystemMessagesByDefaultLikeUpstream() async throws {
    let model = AgentRecordingLanguageModel(streamParts: [.streamStart(warnings: []), .finish(reason: "stop", usage: nil)])
    let agent = AIToolLoopAgent(model: model, retryPolicy: .none)
    let messages: [AIMessage] = [.system("SYSTEM INSTRUCTIONS")]

    do {
        for try await _ in agent.stream(messages: messages) {}
        Issue.record("Expected system messages to be rejected.")
    } catch let error as AIError {
        #expect(error == .invalidArgument(
            argument: "messages",
            message: "System messages are not allowed in the prompt or messages fields. Use the instructions option instead."
        ))
    }

    #expect(model.streamRequests.isEmpty)
}

@Test func toolLoopAgentAllowsStreamSystemMessagesWhenEnabledLikeUpstream() async throws {
    let model = AgentRecordingLanguageModel(streamParts: [.streamStart(warnings: []), .finish(reason: "stop", usage: nil)])
    let agent = AIToolLoopAgent(model: model, allowSystemInMessages: true, retryPolicy: .none)
    let messages: [AIMessage] = [.system("SYSTEM INSTRUCTIONS")]

    for try await _ in agent.stream(messages: messages) {}

    let request = try #require(model.streamRequests.first)
    #expect(request.messages == messages)
}

@Test func createAgentUIStreamConvertsUIMessagesAndStreamsSnapshots() async throws {
    let model = AgentRecordingLanguageModel(streamParts: [
        .streamStart(warnings: []),
        .textStart(id: "text-1"),
        .textDeltaPart(id: "text-1", delta: "Hel"),
        .textDeltaPart(id: "text-1", delta: "lo"),
        .textEnd(id: "text-1"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
    ])
    let agent = AIToolLoopAgent(model: model, instructions: "Answer shortly.")

    var snapshots: [AIUIMessage] = []
    let stream = try createAgentUIStream(
        agent: agent,
        uiMessages: [.user("Hi", id: "user-1")],
        messageID: "assistant-1"
    )
    for try await snapshot in stream {
        snapshots.append(snapshot)
    }

    let request = try #require(model.streamRequests.first)
    #expect(request.messages == [.system("Answer shortly."), .user("Hi")])

    let finalMessage = try #require(snapshots.last)
    #expect(finalMessage.id == "assistant-1")
    #expect(finalMessage.role == .assistant)
    #expect(finalMessage.text == "Hello")
    #expect(finalMessage.metadata["finishReason"]?.stringValue == "stop")
    #expect(finalMessage.metadata["usage"]?["totalTokens"]?.intValue == 5)
}

private final class AgentRecordingLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "agent-test"
    let modelID = "language"
    var generateRequests: [LanguageModelRequest] = []
    var streamRequests: [LanguageModelRequest] = []
    private let result: TextGenerationResult
    private let streamParts: [LanguageStreamPart]

    init(
        result: TextGenerationResult = TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [LanguageStreamPart] = []
    ) {
        self.result = result
        self.streamParts = streamParts
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        generateRequests.append(request)
        return result
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamRequests.append(request)
        let parts = streamParts
        return AsyncThrowingStream { continuation in
            for part in parts {
                continuation.yield(part)
            }
            continuation.finish()
        }
    }
}
