import Foundation
import Testing
@testable import SwiftAISDK

@Suite("WeeklyCore20261011Tests")
struct WeeklyCore20261011Tests {
    @Test(arguments: [0, -1, -1024]) func invalidDimensionsFailBeforeSingleOrEmptyBatchProviderCall(_ dimensions: Int) async {
        let model = MockEmbeddingModel(results: [.init(embeddings: [[1]], rawValue: [:])])
        await #expect(throws: AIError.self) { _ = try await AI.embed(model: model, value: "one", dimensions: dimensions, retryPolicy: .none) }
        await #expect(throws: AIError.self) { _ = try await AI.embedMany(model: model, values: [], dimensions: dimensions, retryPolicy: .none) }
        #expect(model.requests.isEmpty)
    }

    @Test func dimensionsAreForwardedThroughEveryEmbeddingBatch() async throws {
        let model = MockEmbeddingModel(results: [.init(embeddings: [[1]], rawValue: [:])], maxEmbeddingsPerCall: 1)
        _ = try await AI.embedMany(model: model, values: ["one", "two"], dimensions: 768, retryPolicy: .none)
        #expect(model.requests.count == 2)
        #expect(model.requests.allSatisfy { $0.dimensions == 768 })
    }

    @Test func rawUsageSurvivesSingleStepAndEmptyOperandsButNotTwoPopulatedSteps() {
        let usage = TokenUsage(inputTokens: 10, outputTokens: 5, totalTokens: 15, rawValue: ["vendor": 15])
        #expect(sumTokenUsage(nil, usage) == usage)
        #expect(sumTokenUsage(TokenUsage(), usage) == usage)
        #expect(sumTokenUsage(usage, TokenUsage()) == usage)
        let total = sumTokenUsage(usage, usage)
        #expect(total?.inputTokens == 20 && total?.totalTokens == 30)
        #expect(total?.rawValue == nil)
        #expect(sumTokenUsage(usage, TokenUsage(rawValue: ["vendor": 0]))?.rawValue == nil)
    }

    @Test func emptyToolMessageMetadataMergesWithFollowingToolMessage() throws {
        let call = AIToolCall(id: "call", name: "lookup", arguments: "{}")
        let messages = try convertToLanguageModelPrompt(StandardizedPrompt(instructions: nil, messages: [
            .assistant(text: "", toolCalls: [call]),
            .init(role: .tool, content: [], providerMetadata: ["vendor": ["first": 1, "shared": "old"]]),
            .init(role: .tool, content: [.toolResult(.init(toolCallID: "call", toolName: "lookup", result: "done"))], providerMetadata: ["vendor": ["second": 2, "shared": "new"]])
        ]))
        #expect(messages.count == 2)
        #expect(messages.last?.providerMetadata == ["vendor": ["first": 1, "second": 2, "shared": "new"]])
    }

    @Test(arguments: ["", " \n"]) func namedEmptyAliasRetainsIncompleteToolCall(_ arguments: String) throws {
        var tracker = AIStreamingToolCallTracker()
        _ = try tracker.processDelta(.init(index: 0, id: "call_1", functionName: "weather", arguments: "{\"city\":"))
        let alias = try tracker.processDelta(.init(index: 0, id: "alias", functionName: "weather", arguments: arguments))
        #expect(!alias.contains { if case .toolInputStart = $0 { return true }; return false })
        _ = try tracker.processDelta(.init(index: 0, id: "alias", arguments: "\"Berlin\"}"))
        let calls = tracker.flush().compactMap { if case let .toolCall(call) = $0 { return call }; return nil }
        #expect(calls.count == 1)
        #expect(calls.first?.id == "call_1")
        #expect(calls.first?.arguments == "{\"city\":" + arguments + "\"Berlin\"}")
    }

    @Test func unlabeledToolContinuationOnlyAttachesToUniqueIncompleteStructuredCall() throws {
        var tracker = AIStreamingToolCallTracker()
        _ = try tracker.processDelta(.init(index: 0, id: "complete", functionName: "first", arguments: "{}"))
        _ = try tracker.processDelta(.init(index: 1, id: "incomplete", functionName: "second", arguments: "{\"value\":"))
        #expect(try tracker.processDelta(.init(arguments: "1}")) == [.toolInputDelta(id: "incomplete", delta: "1}")])
        let calls = tracker.flush().compactMap { if case let .toolCall(call) = $0 { return call }; return nil }
        #expect(calls.map(\.id) == ["complete", "incomplete"])
        #expect(calls.last?.arguments == "{\"value\":1}")
        var ambiguous = AIStreamingToolCallTracker()
        _ = try ambiguous.processDelta(.init(index: 0, id: "a", functionName: "f", arguments: "{"))
        _ = try ambiguous.processDelta(.init(index: 1, id: "b", functionName: "g", arguments: "{"))
        #expect(try ambiguous.processDelta(.init(arguments: "}")) == [])
    }

    @Test func literalReasoningDelimitersHandleFragmentsAndRegularExpressionCharacters() async throws {
        let delimiters = AIReasoningDelimiters(opening: "[THINK+(", closing: ")+END]")
        let model = MockLanguageModel(result: .init(text: "before[THINK+(reason)+END]after", rawValue: [:]), streamParts: [
            .textDelta("before[TH"), .textDelta("INK+(rea"), .textDelta("son)+E"), .textDelta("ND]after"), .finish(reason: "stop", usage: nil)
        ])
        let wrapped = wrapLanguageModel(model, middleware: try extractReasoningMiddleware(delimiters: delimiters, separator: "|"))
        let generated = try await wrapped.generate(.init(messages: [.user("test")]))
        #expect(generated.text == "before|after" && generated.reasoning == "reason")
        var text = "", reasoning = ""
        for try await part in wrapped.stream(.init(messages: [.user("test")])) {
            switch part {
            case let .textDelta(delta), let .textDeltaPart(_, delta, _): text += delta
            case let .reasoningDelta(delta), let .reasoningDeltaPart(_, delta, _): reasoning += delta
            default: break
            }
        }
        #expect(text == "before|after" && reasoning == "reason")
        #expect(throws: AIError.self) { _ = try extractReasoningMiddleware(delimiters: .init(opening: "", closing: "end")) }
        #expect(throws: AIError.self) { _ = try extractReasoningMiddleware(delimiters: .init(opening: "start", closing: "")) }
    }

    @Test func waitForIdleIncludesWorkEnqueuedInsideFailedJob() async {
        let executor = AISerialJobExecutor()
        let log = WeeklyCoreLog()
        let entered = AIDelayedPromise<Void>(), release = AIDelayedPromise<Void>()
        let job = executor.run {
            entered.resolve(())
            try await release.value()
            _ = executor.run { await log.append("nested") }
            throw WeeklyCoreError.expected
        }
        _ = try? await entered.value()
        let idle = Task { await executor.waitForIdle(); await log.append("idle") }
        release.resolve(())
        _ = try? await job.value
        await idle.value
        #expect(await log.values() == ["nested", "idle"])
        await executor.waitForIdle()
    }

    @Test func outputTimeoutStopsAtProviderFinishBeforeSlowPostProcessing() async throws {
        let stream = AsyncThrowingStream<LanguageStreamPart, Error> { continuation in
            let task = Task {
                continuation.yield(.textDelta("done"))
                continuation.yield(.finish(reason: "stop", usage: nil))
                try await Task.sleep(nanoseconds: 80_000_000)
                continuation.yield(.metadata(["postProcessing": true]))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        var parts: [LanguageStreamPart] = []
        for try await part in streamWithSemanticOutputTimeouts(stream, firstChunkNanoseconds: 30_000_000, chunkNanoseconds: 30_000_000) { parts.append(part) }
        #expect(parts.count == 3)
        #expect(parts.last == .metadata(["postProcessing": true]))
    }

    @Test func abortImmediatelySettlesReaderAndPreservesTypedReason() async throws {
        let source = AsyncThrowingStream<Int, Error>.makeStream()
        let controller = AIAbortController()
        let stream = streamWithAbortSignal(source.stream, abortSignal: controller.signal)
        controller.abort(reason: "manual", reasonName: "CustomAbort")
        do {
            for try await _ in stream {}
            Issue.record("Expected abort")
        } catch let error as AIAbortError {
            #expect(error.reason == "manual" && error.reasonName == "CustomAbort")
        }
        source.continuation.finish()
    }

    @Test func defaultAgentLimitWarnsOnlyForContinuableLoopAndCustomStopsAreQuiet() async throws {
        let call = AIToolCall(id: "call", name: "lookup", arguments: "{}")
        let tool = AITool(name: "lookup", parameters: ["type": "object"], execute: { _ in "done" })
        let toolStep = TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [call], rawValue: [:])
        let logger = WeeklyCoreWarningRecorder()
        let model = MockLanguageModel(result: toolStep)
        let result = try await AIWarningLogging.withLogger(logger) {
            try await AIToolLoopAgent(model: model, executableTools: [tool]).generate(prompt: "loop")
        }
        #expect(result.steps.count == 20 && model.requests.count == 20)
        let warnings = await logger.events().flatMap(\.warnings)
        #expect(warnings.filter { $0.message?.contains("default stopWhen") == true }.count == 1)
        let naturalLogger = WeeklyCoreWarningRecorder()
        let natural = MockLanguageModel(results: Array(repeating: toolStep, count: 19) + [.init(text: "done", finishReason: "stop", rawValue: [:])])
        _ = try await AIWarningLogging.withLogger(naturalLogger) {
            try await AIToolLoopAgent(model: natural, executableTools: [tool]).generate(prompt: "loop")
        }
        #expect(await naturalLogger.events().flatMap(\.warnings).isEmpty)
        let customLogger = WeeklyCoreWarningRecorder()
        _ = try await AIWarningLogging.withLogger(customLogger) {
            try await AIToolLoopAgent(model: MockLanguageModel(result: toolStep), executableTools: [tool], stopWhen: [.isStepCount(1)]).generate(prompt: "loop")
        }
        #expect(await customLogger.events().flatMap(\.warnings).isEmpty)
    }

    @Test func deprecationCodesAreStableCollisionFreeAndDefaultStateDeduplicates() {
        #expect(aiDeprecationCode(setting: "generateObject") == "AISDK_DEP_GENERATE_OBJECT")
        #expect(aiDeprecationCode(setting: "\"tool-result\" content of type \"image-file-reference\"") == "AISDK_DEP_TOOL_RESULT_IMAGE_FILE_REFERENCE")
        #expect(aiDeprecationCode(setting: "a_b", provider: "Test.Provider") == "AISDK_DEP_PROVIDER_Test_002EProvider__a_005Fb")
        #expect(aiDeprecationCode(setting: "😀") == "AISDK_DEP_SETTING__D83D_DE00")
        #expect(aiDeprecationCode(setting: "a_b") != aiDeprecationCode(setting: "a-b"))
        let state = AIDeprecationEmissionState()
        #expect(state.insert("one")); #expect(!state.insert("one")); #expect(state.insert("two"))
        state.reset(); #expect(state.insert("one"))
    }

    @Test func objectAliasesWarnEveryCustomCallButUnifiedOutputDoesNot() async throws {
        let logger = WeeklyCoreWarningRecorder()
        let model = MockLanguageModel(result: .init(text: "{\"ok\":true}", rawValue: [:]), streamParts: [.textDelta("{\"ok\":true}"), .finish(reason: "stop", usage: nil)])
        try await AIWarningLogging.withLogger(logger) {
            _ = try await AI.generateObject(model: model, prompt: "one", as: JSONValue.self, retryPolicy: .none)
            _ = try await AI.generateObject(model: model, prompt: "two", as: JSONValue.self, retryPolicy: .none)
            _ = try await AI.generateText(model: model, prompt: "three", output: Output.json(), retryPolicy: .none)
            for try await _ in AI.streamText(model: model, prompt: "four", output: Output.json(), retryPolicy: .none) {}
        }
        let warnings = await logger.events().flatMap(\.warnings).filter { $0.type == "deprecated" }
        #expect(warnings.map(\.setting) == ["generateObject", "generateObject"])
    }

    @Test func maxReasoningMapsToPortableBudgetAndUnsupportedValueWarns() {
        var warnings: [AIWarning] = []
        #expect(mapReasoningToProviderBudget(reasoning: "max", maxOutputTokens: 10_000, maxReasoningBudget: 20_000, warnings: &warnings) == 9_500)
        #expect(warnings.isEmpty)
        #expect(mapReasoningToProviderBudget(reasoning: "unknown", maxOutputTokens: 10_000, maxReasoningBudget: 20_000, warnings: &warnings) == nil)
        #expect(warnings.count == 1)
    }
}

private enum WeeklyCoreError: Error { case expected }
private actor WeeklyCoreLog {
    var items: [String] = []
    func append(_ value: String) { items.append(value) }
    func values() -> [String] { items }
}
private actor WeeklyCoreWarningRecorder: AIWarningLogger {
    var items: [AIWarningLogEvent] = []
    func logWarnings(_ event: AIWarningLogEvent) { items.append(event) }
    func events() -> [AIWarningLogEvent] { items }
}
