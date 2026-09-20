import Foundation
import Testing
@testable import SwiftAISDK

@Suite("WeeklyCoreMCP20260920Tests")
struct WeeklyCoreMCP20260920Tests {
    @Test func released17CoreSignaturesDelegateWithNeutralToolCallerDefaults() async throws {
        let tool = AITool(
            name: "legacy",
            parameters: ["type": "object", "properties": [:]],
            execute: { _ in "unused" }
        )
        let dynamicTool = AITool.dynamic(
            name: "legacy-dynamic",
            parameters: ["type": "object", "properties": [:]],
            execute: { $0 }
        )
        let step = AIToolStep(index: 0, content: [], text: "legacy")
        let transport = DirectAIChatTransport(
            model: MockLanguageModel(result: TextGenerationResult(text: "transport", rawValue: [:])),
            executableTools: [tool],
            maxSteps: 1
        )

        #expect(tool.deferLoading == false)
        #expect(tool.toolCaller == nil)
        #expect(dynamicTool.deferLoading == false)
        #expect(dynamicTool.toolCaller == nil)
        #expect(step.providerID == nil)
        #expect(step.modelID == nil)
        #expect(transport.toolCallers.isEmpty)

        let requestResult = try await AI.generateText(
            model: MockLanguageModel(result: TextGenerationResult(text: "request", finishReason: "stop", rawValue: [:])),
            request: LanguageModelRequest(messages: [.user("legacy")]),
            executableTools: [tool],
            maxSteps: 1
        )
        let promptResult = try await AI.generateText(
            model: MockLanguageModel(result: TextGenerationResult(text: "prompt", finishReason: "stop", rawValue: [:])),
            prompt: "legacy",
            executableTools: [tool],
            maxSteps: 1
        )
        let requestOutput = try await AI.generateText(
            model: MockLanguageModel(result: TextGenerationResult(text: "request-output", finishReason: "stop", rawValue: [:])),
            request: LanguageModelRequest(messages: [.user("legacy")]),
            output: Output.text(),
            executableTools: [tool],
            maxSteps: 1
        )
        let promptOutput = try await AI.generateText(
            model: MockLanguageModel(result: TextGenerationResult(text: "prompt-output", finishReason: "stop", rawValue: [:])),
            prompt: "legacy",
            output: Output.text(),
            executableTools: [tool],
            maxSteps: 1
        )

        #expect(requestResult.text == "request")
        #expect(promptResult.text == "prompt")
        #expect(requestOutput.output == "request-output")
        #expect(promptOutput.output == "prompt-output")

        let requestStreamModel = MockLanguageModel(
            result: TextGenerationResult(text: "", rawValue: [:]),
            streamParts: [
                .textStart(id: "1"),
                .textDeltaPart(id: "1", delta: "request-stream"),
                .textEnd(id: "1"),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 1))
            ]
        )
        let promptStreamModel = MockLanguageModel(
            result: TextGenerationResult(text: "", rawValue: [:]),
            streamParts: [
                .textStart(id: "1"),
                .textDeltaPart(id: "1", delta: "prompt-stream"),
                .textEnd(id: "1"),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 1))
            ]
        )
        var requestParts: [LanguageStreamPart] = []
        for try await part in AI.streamText(
            model: requestStreamModel,
            request: LanguageModelRequest(messages: [.user("legacy")]),
            executableTools: [tool],
            maxSteps: 1
        ) {
            requestParts.append(part)
        }
        var promptParts: [LanguageStreamPart] = []
        for try await part in AI.streamText(
            model: promptStreamModel,
            prompt: "legacy",
            executableTools: [tool],
            maxSteps: 1
        ) {
            promptParts.append(part)
        }

        #expect(requestParts.contains(.textDeltaPart(id: "1", delta: "request-stream")))
        #expect(promptParts.contains(.textDeltaPart(id: "1", delta: "prompt-stream")))
    }

    @Test func dataURLTextHonorsDeclaredCharsetAndKeepsLegacyByteStrings() throws {
        let utf8 = try getTextFromDataURL("data:text/plain;charset=utf-8;base64,Y2Fmw6k=")
        let latin1 = try getTextFromDataURL("data:text/plain;charset=iso-8859-1;base64,Y2Fm6Q==")
        let legacyByteString = try getTextFromDataURL("data:text/plain;base64,Y2Fm6Q==")

        #expect(utf8 == "café")
        #expect(latin1 == "café")
        #expect(legacyByteString == "café")
    }

    @Test func rawSpeechUsesDetectedAACMediaType() async throws {
        let model = MockSpeechModel(result: SpeechResult(audio: Data([0xFF, 0xF1, 0x50, 0x40])))

        let result = try await AI.generateSpeech(
            model: model,
            request: SpeechRequest(text: "hello")
        )

        #expect(result.contentType == "audio/aac")
    }

    @Test func simulatedStreamingCarriesTextProviderMetadata() async throws {
        let metadata: [String: JSONValue] = ["openai": ["itemId": "message-1"]]
        let model = MockLanguageModel(result: TextGenerationResult(
            text: "hello",
            content: [.text("hello", providerMetadata: metadata)],
            finishReason: "stop",
            rawValue: [:]
        ))
        let wrapped = wrapLanguageModel(model, middleware: simulateStreamingMiddleware())

        var parts: [LanguageStreamPart] = []
        for try await part in wrapped.stream(LanguageModelRequest(messages: [.user("hi")])) {
            parts.append(part)
        }

        #expect(parts.contains(.textStart(id: "0", providerMetadata: metadata)))
    }

    @Test func JSONFenceExtractionAcceptsLongTrailingWhitespace() {
        let whitespace = String(repeating: " \n", count: 20)
        #expect(defaultExtractJSONTransform("```json\n{\"ok\":true}\n```\(whitespace)") == #"{"ok":true}"#)
    }

    @Test func invalidToolContextStopsInputAvailableBeforeCallback() async throws {
        let callback = WeeklyBooleanCapture()
        let tool = AITool(
            name: "lookup",
            parameters: ["type": "object", "properties": [:]],
            contextSchema: [
                "type": "object",
                "properties": ["prefix": ["type": "string"]],
                "required": ["prefix"]
            ],
            onInputAvailable: { _ in await callback.setTrue() },
            execute: { _ in "unused" }
        )

        do {
            _ = try await executeToolCalls(
                [AIToolCall(id: "call-1", name: "lookup", arguments: "{}")],
                toolsByName: ["lookup": tool],
                request: LanguageModelRequest(
                    messages: [.user("look up")],
                    toolContexts: ["lookup": ["prefix": 42]]
                ),
                toolApproval: nil
            )
            Issue.record("Expected invalid tool context to fail before callbacks.")
        } catch is AITypeValidationError {
            // Expected.
        }

        #expect(await callback.value() == false)
    }

    @Test func streamingToolCallbacksReuseValidatedPerToolContext() async throws {
        let capture = WeeklyToolContextCapture()
        let context: JSONValue = ["prefix": "step-context"]
        let tool = AITool(
            name: "lookup",
            parameters: [
                "type": "object",
                "properties": ["value": ["type": "string"]],
                "required": ["value"]
            ],
            contextSchema: [
                "type": "object",
                "properties": ["prefix": ["type": "string"]],
                "required": ["prefix"]
            ],
            onInputStart: { callback in
                await capture.record(callback.toolContext)
            },
            onInputDelta: { callback in
                await capture.record(callback.toolContext)
            },
            onInputAvailable: { callback in
                await capture.record(callback.toolContext)
            },
            execute: { _ in "unused" }
        )
        let chunks: [LanguageStreamPart] = [
            .toolInputStart(id: "call-1", name: "lookup"),
            .toolInputDelta(id: "call-1", delta: #"{"value":"ok"}"#),
            .toolInputEnd(id: "call-1"),
            .toolCall(AIToolCall(
                id: "call-1",
                name: "lookup",
                arguments: #"{"value":"ok"}"#
            ))
        ]

        let forwarded = try await weeklyForwardToolCallbackStream(
            chunks,
            toolsByName: ["lookup": tool],
            request: LanguageModelRequest(
                messages: [.user("look up")],
                toolContexts: ["lookup": context]
            )
        )

        #expect(forwarded == chunks)
        #expect(await capture.values() == [context, context, context])
    }

    @Test func promptAssetDownloadChecksAbortBeforeTransport() async throws {
        let transport = WeeklyCountingTransport()
        let controller = AIAbortController()
        controller.abort(reason: "cancel image", reasonName: "AbortError")
        let request = LanguageModelRequest(
            messages: [AIMessage(role: .user, content: [.imageURL("https://example.com/image.png")])],
            abortSignal: controller.signal
        )

        do {
            _ = try await downloadUnsupportedPromptAssets(
                in: request,
                supportedURLs: [:],
                transport: transport
            )
            Issue.record("Expected prompt download to observe the aborted signal.")
        } catch let error as AIAbortError {
            #expect(error.reason == "cancel image")
        }

        #expect(await transport.count() == 0)
    }

    @Test func structuredGenerationParsesOnlyTheFinalToolLoopStep() async throws {
        let call = AIToolCall(id: "call-1", name: "lookup", arguments: "{}")
        let model = MockLanguageModel(results: [
            TextGenerationResult(
                text: "Checking the value.",
                finishReason: "tool-calls",
                toolCalls: [call],
                rawValue: ["step": 1]
            ),
            TextGenerationResult(
                text: #"{"value":"done"}"#,
                finishReason: "stop",
                rawValue: ["step": 2]
            )
        ])
        let tool = AITool(
            name: "lookup",
            parameters: ["type": "object", "properties": [:]],
            execute: { _ in "done" }
        )

        let result = try await AI.generateText(
            model: model,
            request: LanguageModelRequest(messages: [.user("look up")]),
            output: Output.object(schema: weeklyValueSchema, as: WeeklyValue.self),
            executableTools: [tool],
            maxSteps: 2
        )

        let output = try #require(result.output)
        #expect(output == WeeklyValue(value: "done"))
        #expect(result.text == #"{"value":"done"}"#)
        #expect(result.textResult.steps.count == 2)
    }

    @Test func structuredStreamResetsEarlierToolStepText() async throws {
        let call = AIToolCall(id: "call-1", name: "lookup", arguments: "{}")
        let model = MockLanguageModel(
            result: TextGenerationResult(text: "", rawValue: [:]),
            streamSequences: [
                [
                    .streamStart(warnings: []),
                    .textStart(id: "intro"),
                    .textDeltaPart(id: "intro", delta: "Checking the value."),
                    .textEnd(id: "intro"),
                    .toolCall(call),
                    .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 2))
                ],
                [
                    .streamStart(warnings: []),
                    .textStart(id: "answer"),
                    .textDeltaPart(id: "answer", delta: #"{"value":"done"}"#),
                    .textEnd(id: "answer"),
                    .finish(reason: "stop", usage: TokenUsage(totalTokens: 3))
                ]
            ]
        )
        let tool = AITool(
            name: "lookup",
            parameters: ["type": "object", "properties": [:]],
            execute: { _ in "done" }
        )
        var partials: [JSONValue] = []
        var output: WeeklyValue?

        for try await part in AI.streamText(
            model: model,
            request: LanguageModelRequest(messages: [.user("look up")]),
            output: Output.object(schema: weeklyValueSchema, as: WeeklyValue.self),
            executableTools: [tool],
            maxSteps: 2
        ) {
            switch part {
            case let .partialOutput(partial):
                partials.append(partial)
            case let .output(result):
                output = result.output
            default:
                break
            }
        }

        #expect(partials == [["value": "done"]])
        #expect(output == WeeklyValue(value: "done"))
    }

    @Test(arguments: [JSONValue.null, JSONValue.string("")])
    func structuredJSONStreamPublishesNullAndEmptyString(_ expected: JSONValue) async throws {
        let text = try #require(canonicalJSONText(expected))
        let model = MockLanguageModel(
            result: TextGenerationResult(text: "", rawValue: [:]),
            streamParts: [
                .textStart(id: "1"),
                .textDeltaPart(id: "1", delta: text),
                .textEnd(id: "1"),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 1))
            ]
        )
        var partials: [JSONValue] = []
        var output: JSONValue?

        for try await part in AI.streamText(
            model: model,
            prompt: "return JSON",
            output: Output.json()
        ) {
            switch part {
            case let .partialOutput(partial):
                partials.append(partial)
            case let .output(result):
                output = result.output
            default:
                break
            }
        }

        #expect(partials == [expected])
        #expect(output == expected)
    }

    @Test func prepareStepSelectedModelAppearsInStepsResponsesAndTelemetry() async throws {
        let call = AIToolCall(id: "call-1", name: "lookup", arguments: "{}")
        let primary = WeeklyLanguageModel(
            providerID: "primary-provider",
            modelID: "primary-model",
            results: [TextGenerationResult(
                text: "",
                finishReason: "tool-calls",
                toolCalls: [call],
                rawValue: [:]
            )]
        )
        let alternate = WeeklyLanguageModel(
            providerID: "alternate-provider",
            modelID: "alternate-model",
            results: [TextGenerationResult(
                text: "done",
                finishReason: "stop",
                rawValue: [:]
            )]
        )
        let recorder = TelemetryRecorder()
        let tool = AITool(
            name: "lookup",
            parameters: ["type": "object", "properties": [:]],
            execute: { _ in "done" }
        )

        let result = try await AI.generateText(
            model: primary,
            request: LanguageModelRequest(messages: [.user("look up")]),
            executableTools: [tool],
            maxSteps: 2,
            prepareStep: { context in
                context.stepNumber == 1 ? AIPrepareStepResult(model: alternate) : nil
            },
            telemetry: Telemetry.Options(integrations: [recorder])
        )

        let stepProviderIDs = result.steps.compactMap { $0.providerID }
        let stepModelIDs = result.steps.compactMap { $0.modelID }
        #expect(stepProviderIDs == ["primary-provider", "alternate-provider"])
        #expect(stepModelIDs == ["primary-model", "alternate-model"])
        #expect(result.finalStep?.responseMetadata.modelID == "alternate-model")
        let stepEnds = await recorder.events().filter { $0.kind == .stepEnd }
        #expect(stepEnds.map(\.providerID) == ["primary-provider", "alternate-provider"])
        #expect(stepEnds.compactMap(\.modelID) == ["primary-model", "alternate-model"])
    }

    @Test func deferredToolSearchExposesMatchesOnTheNextPreparationOnly() async throws {
        let state = AIToolDiscoveryState()
        let search = toolSearch()
        let weather = AITool(
            name: "getWeather",
            description: "Weather forecast.",
            parameters: ["type": "object", "properties": [:]],
            deferLoading: true,
            execute: { _ in "sunny" }
        )

        let first = try await state.prepare(tools: [search, weather], routing: [:])
        #expect(first.modelTools.map(\.name) == ["toolSearch"])
        let boundSearch = try #require(first.executionTools.first { $0.name == "toolSearch" })
        let searchResult = try await boundSearch.execute(["query": "WEATHER"])
        #expect(searchResult == ["tools": [["name": "getWeather", "description": "Weather forecast."]]])
        #expect(first.modelTools.map(\.name) == ["toolSearch"])

        for query in ["unrelated", "   ", ".*"] {
            let noMatches = try await boundSearch.execute(["query": .string(query)])
            #expect(noMatches == ["tools": []])
        }

        let second = try await state.prepare(tools: [search, weather], routing: [:])
        #expect(second.modelTools.map(\.name) == ["toolSearch", "getWeather"])
    }

    @Test func localAndProviderToolCallersPreserveRoutingAndAnnouncements() async throws {
        let localCaller = experimentalToolCaller(
            AITool(
                name: "code",
                parameters: ["type": "object", "properties": [:]],
                execute: { _ in "unbound" }
            ),
            definition: .local(
                bind: { tools in
                    AITool(
                        name: "code",
                        parameters: ["type": "object", "properties": [:]],
                        execute: { _ in .array(tools.keys.sorted().map(JSONValue.string)) }
                    )
                },
                prepareModelMessage: { tools in "catalog:\(tools.keys.sorted().joined(separator: ","))" }
            )
        )
        let providerCaller = experimentalToolCaller(
            AITool(
                name: "providerCaller",
                parameters: ["type": "object", "properties": [:]],
                execute: { _ in "unused" }
            ),
            definition: .provider { options in
                var options = options
                options["routed"] = true
                return options
            }
        )
        let localOnly = AITool(
            name: "localOnly",
            parameters: ["type": "object", "properties": [:]],
            execute: { _ in "local" }
        )
        let providerOnly = AITool(
            name: "providerOnly",
            parameters: ["type": "object", "properties": [:]],
            execute: { _ in "provider" }
        )

        let prepared = try await AIToolDiscoveryState().prepare(
            tools: [localCaller, providerCaller, localOnly, providerOnly],
            routing: [
                "localOnly": ["code"],
                "providerOnly": ["providerCaller"]
            ]
        )

        #expect(prepared.executionTools.map(\.name) == ["code", "providerCaller", "localOnly", "providerOnly"])
        #expect(prepared.modelTools.map(\.name) == ["code", "providerCaller", "providerOnly"])
        #expect(prepared.modelTools.first { $0.name == "providerOnly" }?.providerOptions["routed"]?.boolValue == true)
        #expect(prepared.callerMessages == [.user("catalog:localOnly")])
        let boundCaller = try #require(prepared.executionTools.first { $0.name == "code" })
        let boundCallerOutput = try await boundCaller.execute([:])
        #expect(boundCallerOutput == ["localOnly"])
    }

    @Test func callerAnnouncementsCompareAgainstOnlyTheLatestUserText() {
        let messages: [AIMessage] = [
            .user("catalog"),
            .assistant("acknowledged"),
            .user("new question")
        ]

        #expect(appendToolCallerMessages(messages, additions: [.user("catalog")]) == messages + [.user("catalog")])
        #expect(appendToolCallerMessages(messages, additions: [.user("new question")]) == messages)
    }

    @Test func pruneMessagesRetainsOriginForPendingApproval() {
        let fixture: [AIMessage] = [
            .user("Echo hello."),
            AIMessage(role: .assistant, content: [
                .toolCall(AIToolCall(id: "call-1", name: "echo", arguments: #"{"value":"hello"}"#)),
                .toolApprovalRequest(AIToolApprovalRequest(
                    id: "approval-1",
                    toolName: "echo",
                    arguments: #"{"value":"hello"}"#,
                    toolCallID: "call-1"
                ))
            ]),
            .toolResponses(approvalResponses: [AIToolApprovalResponse(id: "approval-1", approved: true)])
        ]

        #expect(pruneMessages(fixture, toolCalls: [.beforeLastMessage()]) == fixture)
        #expect(pruneMessages(fixture, toolCalls: [.beforeLastMessage(tools: ["echo"])]) == fixture)
    }

    @MainActor
    @Test func preliminaryToolOutputDoesNotTriggerAutomaticChatSend() {
        let transport = WeeklyChatTransport()
        let session = AIChatSession(
            transport: transport,
            messages: [.assistant(id: "assistant-1")],
            generateMessageID: { "tool-message" },
            sendAutomaticallyWhen: { _ in true }
        )

        session.addToolOutput(AIToolResult(
            toolCallID: "call-1",
            toolName: "lookup",
            result: "checking",
            preliminary: true
        ))

        #expect(transport.requests.isEmpty)
        #expect(session.messages.last?.parts.contains(where: {
            guard case let .toolResult(result) = $0 else { return false }
            return result.preliminary
        }) == true)
    }

    @Test func inFlightVideoStatusCannotOutlivePollTimeout() async throws {
        let model = WeeklySlowStatusVideoModel()
        let started = DispatchTime.now().uptimeNanoseconds

        do {
            _ = try await AI.generateVideo(
                model: model,
                request: VideoGenerationRequest(prompt: "slow status"),
                retryPolicy: .none,
                poll: VideoGenerationPollOptions(
                    intervalMilliseconds: 0,
                    timeoutMilliseconds: 20,
                    delay: { _, _ in }
                )
            )
            Issue.record("Expected the in-flight status request to time out.")
        } catch let error as VideoGenerationOperationError {
            #expect(error == .timedOut(milliseconds: 20))
        }

        let elapsedMilliseconds = (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        #expect(elapsedMilliseconds < 150)
    }
}

private struct WeeklyValue: Codable, Equatable, Sendable {
    var value: String
}

private let weeklyValueSchema: JSONValue = [
    "type": "object",
    "properties": ["value": ["type": "string"]],
    "required": ["value"],
    "additionalProperties": false
]

private actor WeeklyBooleanCapture {
    private var flag = false
    func setTrue() { flag = true }
    func value() -> Bool { flag }
}

private actor WeeklyToolContextCapture {
    private var contexts: [JSONValue?] = []
    func record(_ context: JSONValue?) { contexts.append(context) }
    func values() -> [JSONValue?] { contexts }
}

private actor WeeklyCountingTransport: AITransport {
    private var calls = 0

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        calls += 1
        return AIHTTPResponse(statusCode: 200, body: Data([1]))
    }

    func count() -> Int { calls }
}

private final class WeeklyLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID: String
    let modelID: String
    private var results: [TextGenerationResult]

    init(providerID: String, modelID: String, results: [TextGenerationResult]) {
        self.providerID = providerID
        self.modelID = modelID
        self.results = results
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        guard !results.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No scripted response.")
        }
        return results.removeFirst()
    }
}

private func weeklyForwardToolCallbackStream(
    _ parts: [LanguageStreamPart],
    toolsByName: [String: AITool],
    request: LanguageModelRequest
) async throws -> [LanguageStreamPart] {
    let input = AsyncThrowingStream<LanguageStreamPart, Error> { continuation in
        for part in parts {
            continuation.yield(part)
        }
        continuation.finish()
    }
    let output = AsyncThrowingStream<LanguageStreamPart, Error> { continuation in
        let task = Task {
            do {
                _ = try await forwardLanguageStream(
                    input,
                    to: continuation,
                    toolsByName: toolsByName,
                    request: request
                )
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }

    var forwarded: [LanguageStreamPart] = []
    for try await part in output {
        forwarded.append(part)
    }
    return forwarded
}

private final class WeeklyChatTransport: AIChatTransport, @unchecked Sendable {
    var requests: [AIChatTransportRequest] = []

    func sendMessages(_ request: AIChatTransportRequest) throws -> AsyncThrowingStream<AIUIMessage, Error> {
        requests.append(request)
        return AsyncThrowingStream { $0.finish() }
    }
}

private final class WeeklySlowStatusVideoModel: AsyncVideoModel, @unchecked Sendable {
    let providerID = "weekly.video"
    let modelID = "slow-status"
    let supportsUnaryVideoGeneration = false

    func startVideoGeneration(
        _ request: VideoGenerationOperationStartRequest
    ) async throws -> VideoGenerationOperationStartResult {
        VideoGenerationOperationStartResult(operation: ["id": "operation-1"])
    }

    func videoGenerationStatus(
        _ request: VideoGenerationOperationStatusRequest
    ) async throws -> VideoGenerationOperationStatusResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                continuation.resume()
            }
        }
        return .pending()
    }
}
