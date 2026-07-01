import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiStreamObjectCallbackOnStartRunsBeforeModelCallLikeUpstream() async throws {
    let recorder = StreamObjectCallbackUpstreamRecorder()
    let model = StreamObjectCallbackLanguageModel(recorder: recorder)

    for try await _ in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: StreamObjectContent.self,
        schema: streamObjectContentSchema(),
        callbacks: AIObjectGenerationCallbacks(
            onStart: { _ in recorder.record("onStart") }
        )
    ) {}

    #expect(recorder.names() == ["onStart", "doStream"])
}

@Test func aiStreamObjectCallbackOnStartSendsCorrectInformationLikeUpstream() async throws {
    let recorder = StreamObjectCallbackUpstreamRecorder()
    let schema = streamObjectContentSchema()
    let model = StreamObjectCallbackLanguageModel(providerID: "test-provider", modelID: "test-model")

    for try await _ in AI.streamObject(
        model: model,
        prompt: "test-prompt",
        as: StreamObjectContent.self,
        schema: schema,
        schemaName: "test-schema",
        schemaDescription: "A test schema",
        temperature: 0.5,
        maxOutputTokens: 100,
        telemetry: Telemetry.Options(functionID: "test-function"),
        callbacks: AIObjectGenerationCallbacks(
            onStart: { event in recorder.recordStart(event) }
        )
    ) {}

    let event = try #require(recorder.startEvent())
    #expect(event.operationID == "ai.streamObject")
    #expect(event.providerID == "test-provider")
    #expect(event.modelID == "test-model")
    #expect(event.outputKind == "object")
    #expect(event.request.messages == [.user("test-prompt")])
    #expect(event.request.temperature == 0.5)
    #expect(event.request.maxOutputTokens == 100)
    #expect(event.schema == schema)
    #expect(event.schemaName == "test-schema")
    #expect(event.schemaDescription == "A test schema")
    #expect(event.maxRetries == AIRetryPolicy.default.maxRetries)
    #expect(!event.callID.isEmpty)
}

@Test func aiStreamObjectCallbackOnStepStartRunsBeforeModelCallLikeUpstream() async throws {
    let recorder = StreamObjectCallbackUpstreamRecorder()
    let model = StreamObjectCallbackLanguageModel(recorder: recorder)

    for try await _ in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: StreamObjectContent.self,
        schema: streamObjectContentSchema(),
        callbacks: AIObjectGenerationCallbacks(
            onStepStart: { _ in recorder.record("onStepStart") }
        )
    ) {}

    #expect(recorder.names() == ["onStepStart", "doStream"])
}

@Test func aiStreamObjectCallbackOnStepStartProvidesStepAndModelInfoLikeUpstream() async throws {
    let recorder = StreamObjectCallbackUpstreamRecorder()
    let model = StreamObjectCallbackLanguageModel(providerID: "test-provider", modelID: "test-model")

    for try await _ in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: StreamObjectContent.self,
        schema: streamObjectContentSchema(),
        callbacks: AIObjectGenerationCallbacks(
            onStepStart: { event in recorder.recordStepStart(event) }
        )
    ) {}

    let event = try #require(recorder.stepStartEvent())
    #expect(event.stepNumber == 0)
    #expect(event.providerID == "test-provider")
    #expect(event.modelID == "test-model")
    #expect(event.request.messages == [.user("prompt")])
    #expect(!event.callID.isEmpty)
}

@Test func aiStreamObjectCallbackOnStepFinishRunsAfterStreamingCompletesLikeUpstream() async throws {
    let recorder = StreamObjectCallbackUpstreamRecorder()
    let model = StreamObjectCallbackLanguageModel(recorder: recorder)

    for try await _ in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: StreamObjectContent.self,
        schema: streamObjectContentSchema(),
        callbacks: AIObjectGenerationCallbacks(
            onStepFinish: { _ in recorder.record("onStepFinish") }
        )
    ) {}

    #expect(recorder.names() == ["doStream", "onStepFinish"])
}

@Test func aiStreamObjectCallbackOnStepFinishProvidesObjectTextAndUsageLikeUpstream() async throws {
    let recorder = StreamObjectCallbackUpstreamRecorder()
    let model = StreamObjectCallbackLanguageModel(providerID: "test-provider", modelID: "test-model")

    for try await _ in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: StreamObjectContent.self,
        schema: streamObjectContentSchema(),
        callbacks: AIObjectGenerationCallbacks(
            onStepFinish: { event in recorder.recordStepFinish(event) }
        )
    ) {}

    let event = try #require(recorder.stepFinishEvent())
    #expect(event.stepNumber == 0)
    #expect(event.providerID == "test-provider")
    #expect(event.modelID == "test-model")
    #expect(event.text == #"{ "content": "Hello, world!" }"#)
    #expect(event.finishReason == "stop")
    #expect(event.usage == TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13))
    #expect(!event.callID.isEmpty)
}

@Test func aiStreamObjectCallbacksFireInOrderLikeUpstream() async throws {
    let recorder = StreamObjectCallbackUpstreamRecorder()
    let model = StreamObjectCallbackLanguageModel(recorder: recorder)

    for try await _ in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: StreamObjectContent.self,
        schema: streamObjectContentSchema(),
        callbacks: AIObjectGenerationCallbacks(
            onStart: { _ in recorder.record("onStart") },
            onStepStart: { _ in recorder.record("onStepStart") },
            onStepFinish: { _ in recorder.record("onStepFinish") },
            onFinish: { _ in recorder.record("onFinish") }
        )
    ) {}

    #expect(recorder.names() == [
        "onStart",
        "onStepStart",
        "doStream",
        "onStepFinish",
        "onFinish"
    ])
}

@Test func aiStreamObjectCallbacksCorrelateEventsWithSameCallIDLikeUpstream() async throws {
    let recorder = StreamObjectCallbackUpstreamRecorder()
    let model = StreamObjectCallbackLanguageModel()

    for try await _ in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: StreamObjectContent.self,
        schema: streamObjectContentSchema(),
        callbacks: AIObjectGenerationCallbacks(
            onStart: { event in recorder.recordStart(event) },
            onStepStart: { event in recorder.recordStepStart(event) },
            onStepFinish: { event in recorder.recordStepFinish(event) },
            onFinish: { event in recorder.recordFinish(event) }
        )
    ) {}

    let callIDs = recorder.callIDs()
    #expect(callIDs.count == 4)
    #expect(Set(callIDs).count == 1)
    #expect(callIDs.first?.isEmpty == false)
}
