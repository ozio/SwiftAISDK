import Foundation
import Testing
@testable import SwiftAISDK

private struct NativeAPISummary: Decodable, Sendable, Equatable {
    var title: String
}

@Test func swiftNativeGenerateTextConvenienceBuildsOptionsAndRunsTools() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "weather", arguments: #"{"city":"Tokyo"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [toolCall], rawValue: .object([:])),
        TextGenerationResult(text: "Bring a light jacket.", rawValue: .object([:]))
    ])
    let weather = AITool(
        name: "weather",
        description: "Get the weather.",
        parameters: [
            "type": "object",
            "properties": ["city": ["type": "string"]],
            "required": ["city"]
        ]
    ) { arguments in
        ["city": arguments["city"] ?? .string("missing"), "forecast": "cool"]
    }

    let result = try await model.generateText(
        "What should I wear?",
        options: LanguageGenerationOptions(
            temperature: 0.4,
            maxOutputTokens: 120,
            providerOptions: ["openai": ["store": false]],
            retryPolicy: .none
        ),
        tools: LanguageToolOptions([weather], maxSteps: 2)
    )

    #expect(result.text == "Bring a light jacket.")
    #expect(model.requests.count == 2)
    let firstRequest = try #require(model.requests.first)
    #expect(firstRequest.messages == [.user("What should I wear?")])
    #expect(firstRequest.temperature == 0.4)
    #expect(firstRequest.maxOutputTokens == 120)
    #expect(firstRequest.providerOptions["openai"]?["store"]?.boolValue == false)
    #expect(firstRequest.tools["weather"]?["description"]?.stringValue == "Get the weather.")
}

@Test func swiftNativeGenerateObjectConvenienceRequestsSchemaAndDecodes() async throws {
    let model = MockLanguageModel(result: TextGenerationResult(text: #"{"title":"Done"}"#, rawValue: .object([:])))
    let schema = AIJSONSchema<NativeAPISummary>(
        [
            "type": "object",
            "properties": ["title": ["type": "string"]],
            "required": ["title"]
        ],
        name: "summary"
    )

    let result = try await model.generateObject("Summarize this.", schema: schema)

    #expect(result.object == NativeAPISummary(title: "Done"))
    let request = try #require(model.requests.first)
    #expect(request.messages == [.user("Summarize this.")])
    #expect(request.responseFormat == .json(schema: schema.jsonSchema, name: "summary"))
}

@Test func swiftNativeMediaConveniencesUseModalVerbNames() async throws {
    let embeddingModel = MockEmbeddingModel(results: [
        EmbeddingResult(embeddings: [[0.1, 0.2]], rawValue: .object([:]))
    ])
    let embedding = try await embeddingModel.embed("hello", dimensions: 2)
    #expect(embedding.embeddings == [[0.1, 0.2]])
    #expect(embeddingModel.requests.first?.values == ["hello"])
    #expect(embeddingModel.requests.first?.dimensions == 2)

    let imageModel = MockImageModel(result: ImageGenerationResult(urls: ["https://example.com/image.png"], rawValue: .object([:])))
    let image = try await imageModel.generateImage("cat", size: "1024x1024", count: 1)
    #expect(image.urls == ["https://example.com/image.png"])
    #expect(imageModel.requests.first?.prompt == "cat")
    #expect(imageModel.requests.first?.size == "1024x1024")
    #expect(imageModel.requests.first?.count == 1)

    let transcriptionModel = MockTranscriptionModel(result: TranscriptionResult(text: "hello", rawValue: .object([:])))
    let transcription = try await transcriptionModel.transcribe(audio: Data("wav".utf8), language: "en", prompt: "Names are proper nouns.")
    #expect(transcription.text == "hello")
    #expect(transcriptionModel.requests.first?.audio == Data("wav".utf8))
    #expect(transcriptionModel.requests.first?.language == "en")
    #expect(transcriptionModel.requests.first?.prompt == "Names are proper nouns.")

    let speechModel = MockSpeechModel(result: SpeechResult(audio: Data("audio".utf8)))
    let speech = try await speechModel.generateSpeech("hello", voice: "alloy", speed: 1.1, language: "en")
    #expect(String(data: speech.audio, encoding: .utf8) == "audio")
    #expect(speechModel.requests.first?.text == "hello")
    #expect(speechModel.requests.first?.voice == "alloy")
    #expect(speechModel.requests.first?.speed == 1.1)
    #expect(speechModel.requests.first?.language == "en")

    let videoModel = MockVideoModel(result: VideoGenerationResult(urls: ["https://example.com/video.mp4"], rawValue: .object([:])))
    let video = try await AI.generateVideo("clip", using: videoModel, durationSeconds: 4, count: 2)
    #expect(video.urls == ["https://example.com/video.mp4"])
    #expect(videoModel.requests.first?.prompt == "clip")
    #expect(videoModel.requests.first?.durationSeconds == 4)
    #expect(videoModel.requests.first?.count == 2)
}

@Test func aiGenerateTextPromptBuildsLanguageRequest() async throws {
    let model = MockLanguageModel(result: TextGenerationResult(text: "done", rawValue: .object([:])))

    let result = try await AI.generateText(
        model: model,
        prompt: "Hello",
        temperature: 0.2,
        topK: 20,
        seed: 7,
        responseFormat: .json(name: "Answer"),
        reasoning: "low",
        providerOptions: ["openai": .object(["parallelToolCalls": .bool(false)])],
        extraBody: ["user": .string("user-1")]
    )

    #expect(result.text == "done")
    #expect(result.requestMetadata.body?["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
    #expect(result.requestMetadata.body?["temperature"]?.doubleValue == 0.2)
    #expect(result.requestMetadata.body?["topK"]?.intValue == 20)
    #expect(result.requestMetadata.body?["responseFormat"]?["name"]?.stringValue == "Answer")
    #expect(result.requestMetadata.body?["providerOptions"]?["openai"]?["parallelToolCalls"]?.boolValue == false)
    #expect(result.requestMetadata.body?["extraBody"]?["user"]?.stringValue == "user-1")
    #expect(model.requests.count == 1)
    let request = try #require(model.requests.first)
    #expect(request.messages == [.user("Hello")])
    #expect(request.temperature == 0.2)
    #expect(request.topK == 20)
    #expect(request.seed == 7)
    #expect(request.responseFormat == .json(name: "Answer"))
    #expect(request.reasoning == "low")
    #expect(request.providerOptions["openai"]?["parallelToolCalls"]?.boolValue == false)
    #expect(request.extraBody["user"]?.stringValue == "user-1")
}
@Test func aiGenerateTextRetriesRetryableErrors() async throws {
    let model = FlakyLanguageModel(failures: [
        AIError.apiCall(provider: "mock", statusCode: 500, body: "temporary")
    ], result: TextGenerationResult(text: "recovered", rawValue: .object([:])))

    let result = try await AI.generateText(
        model: model,
        prompt: "Retry",
        retryPolicy: AIRetryPolicy(maxRetries: 2, initialDelayNanoseconds: 0)
    )

    #expect(result.text == "recovered")
    #expect(model.requests.count == 2)
}
@Test func aiGenerateTextHonorsRetryAfterHeader() async throws {
    let model = FlakyLanguageModel(failures: [
        AIError.apiCall(
            provider: "mock",
            statusCode: 429,
            body: "rate limited",
            headers: ["Retry-After": "0"]
        )
    ], result: TextGenerationResult(text: "recovered", rawValue: .object([:])))

    let started = DispatchTime.now().uptimeNanoseconds
    let result = try await AI.generateText(
        model: model,
        prompt: "Retry after",
        retryPolicy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: 2_000_000_000)
    )
    let elapsed = DispatchTime.now().uptimeNanoseconds - started

    #expect(result.text == "recovered")
    #expect(model.requests.count == 2)
    #expect(elapsed < 1_000_000_000)
}
@Test func aiGenerateTextEmitsTelemetryLifecycleAndRetryEvents() async throws {
    let recorder = TelemetryRecorder()
    let model = FlakyLanguageModel(failures: [
        AIError.apiCall(provider: "mock", statusCode: 503, body: "try again")
    ], result: TextGenerationResult(
        text: "recovered",
        finishReason: "stop",
        usage: TokenUsage(inputTokens: 1, outputTokens: 2, totalTokens: 3),
        rawValue: .object(["ok": .bool(true)])
    ))

    let result = try await AI.generateText(
        model: model,
        prompt: "Telemetry",
        retryPolicy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: 0),
        telemetry: Telemetry.Options(
            functionID: "unit.generateText",
            metadata: ["tenant": .string("test")],
            integrations: [recorder]
        )
    )

    let events = await recorder.events()
    #expect(result.text == "recovered")
    #expect(events.map(\.kind) == [.start, .retry, .end])
    #expect(Set(events.map(\.callID)).count == 1)
    #expect(events.allSatisfy { $0.operationID == "ai.generateText" })
    #expect(events.allSatisfy { $0.providerID == "mock" })
    #expect(events.allSatisfy { $0.modelID == "flaky-language" })
    #expect(events.allSatisfy { $0.functionID == "unit.generateText" })
    #expect(events.allSatisfy { $0.metadata["tenant"] == .string("test") })
    #expect(events[0].input?["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Telemetry")
    #expect(events[1].attempt == 1)
    #expect(events[1].maxRetries == 1)
    #expect(events[1].delayNanoseconds == 0)
    #expect(events[1].errorDescription?.contains("HTTP 503") == true)
    #expect(events[2].output?["text"]?.stringValue == "recovered")
    #expect(events[2].output?["requestMetadata"]?["body"]?["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Telemetry")
    #expect(events[2].usage == TokenUsage(inputTokens: 1, outputTokens: 2, totalTokens: 3))
}

@Test func registeredTelemetryRequiresPerCallOptIn() async throws {
    Telemetry.removeAllIntegrations()
    let recorder = TelemetryRecorder()
    Telemetry.register(recorder)
    defer { Telemetry.removeAllIntegrations() }

    let model = MockLanguageModel(result: TextGenerationResult(text: "ok", rawValue: .object([:])))

    _ = try await AI.generateText(
        model: model,
        prompt: "Do not record by default."
    )
    #expect(await recorder.events().isEmpty)

    _ = try await AI.generateText(
        model: model,
        prompt: "Record with explicit options.",
        telemetry: Telemetry.Options()
    )
    #expect(await recorder.events().map(\.kind) == [.start, .end])
}

@Test func aiGenerateTextTelemetryRecordsErrorsAndRespectsOutputFlag() async throws {
    let recorder = TelemetryRecorder()
    let model = FlakyLanguageModel(failures: [
        AIError.apiCall(provider: "mock", statusCode: 400, body: "bad request")
    ], result: TextGenerationResult(text: "unused", rawValue: .object([:])))

    do {
        _ = try await AI.generateText(
            model: model,
            prompt: "Telemetry error",
            retryPolicy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: 0),
            telemetry: Telemetry.Options(includesOutput: false, integrations: [recorder])
        )
        Issue.record("Expected telemetry error path.")
    } catch {
        let events = await recorder.events()
        #expect(events.map(\.kind) == [.start, .error])
        #expect(events[0].input?["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Telemetry error")
        #expect(events[1].output == nil)
        #expect(events[1].errorDescription?.contains("HTTP 400") == true)
    }
}
@Test func aiGenerateTextAbortsBeforeModelCallWhenSignalIsAborted() async throws {
    let recorder = TelemetryRecorder()
    let controller = AIAbortController()
    controller.abort(reason: "user cancelled")
    let model = MockLanguageModel(result: TextGenerationResult(text: "unused", rawValue: .object([:])))

    do {
        _ = try await AI.generateText(
            model: model,
            prompt: "Abort me",
            abortSignal: controller.signal,
            telemetry: Telemetry.Options(integrations: [recorder])
        )
        Issue.record("Expected aborted generateText call.")
    } catch let error as AIAbortError {
        let events = await recorder.events()

        #expect(error.reason == "user cancelled")
        #expect(model.requests.isEmpty)
        #expect(events.map(\.kind) == [.start, .abort])
        #expect(events[1].operationID == "ai.generateText")
        #expect(events[1].errorDescription?.contains("user cancelled") == true)
    }
}
@Test func aiTelemetryExecuteLanguageModelCallWrapsModelCallsInIntegrationOrder() async throws {
    let log = ExecutionWrapperLog()
    let model = MockLanguageModel(result: TextGenerationResult(text: "wrapped", rawValue: .object([:])))

    let result = try await AI.generateText(
        model: model,
        prompt: "Wrap",
        retryPolicy: .none,
        telemetry: Telemetry.Options(integrations: [
            ExecutionWrappingTelemetry(name: "first", log: log),
            ExecutionWrappingTelemetry(name: "second", log: log)
        ])
    )

    #expect(result.text == "wrapped")
    #expect(await log.entries() == [
        "second-language-start:ai.generateText:mock-language",
        "first-language-start:ai.generateText:mock-language",
        "first-language-end",
        "second-language-end"
    ])
}
@Test func aiGenerateTextEmitsStepAndToolTelemetryEvents() async throws {
    let recorder = TelemetryRecorder()
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"city":"Kyoto"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            finishReason: "tool-calls",
            usage: TokenUsage(totalTokens: 3),
            toolCalls: [toolCall],
            rawValue: .object([:])
        ),
        TextGenerationResult(
            text: "Sunny",
            finishReason: "stop",
            usage: TokenUsage(totalTokens: 5),
            rawValue: .object([:])
        )
    ])
    let lookup = AITool(
        name: "lookup",
        parameters: [
            "type": "object",
            "properties": ["city": ["type": "string"]],
            "required": ["city"]
        ]
    ) { arguments in
        ["city": arguments["city"] ?? .string("missing"), "forecast": "sunny"]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 2,
        telemetry: Telemetry.Options(functionID: "unit.toolLoop", integrations: [recorder])
    )
    let events = await recorder.events()
    let stepEvents = events.filter { $0.operationID == "ai.generateText.step" }
    let toolEvents = events.filter { $0.operationID == "ai.generateText.tool" }

    #expect(result.text == "Sunny")
    #expect(stepEvents.map(\.kind) == [.stepStart, .stepEnd, .stepStart, .stepEnd])
    #expect(Set(stepEvents.map(\.callID)).count == 1)
    #expect(stepEvents.allSatisfy { $0.functionID == "unit.toolLoop" })
    #expect(stepEvents[0].input?["stepNumber"]?.intValue == 0)
    #expect(stepEvents[0].input?["request"]?["messages"]?[0]?["content"]?[0]?["text"]?.stringValue == "Weather?")
    #expect(stepEvents[1].output?["toolCalls"]?[0]?["name"]?.stringValue == "lookup")
    #expect(stepEvents[2].input?["stepNumber"]?.intValue == 1)
    #expect(stepEvents[3].output?["text"]?.stringValue == "Sunny")
    #expect(stepEvents[3].usage?.totalTokens == 5)

    #expect(toolEvents.map(\.kind) == [.toolStart, .toolEnd])
    #expect(Set(toolEvents.map(\.callID)).count == 1)
    #expect(toolEvents[0].input?["toolCall"]?["name"]?.stringValue == "lookup")
    #expect(toolEvents[0].input?["tool"]?["parameters"]?["required"]?[0]?.stringValue == "city")
    #expect(toolEvents[1].output?["status"]?.stringValue == "executed")
    #expect(toolEvents[1].output?["arguments"]?["city"]?.stringValue == "Kyoto")
    #expect(toolEvents[1].output?["result"]?["result"]?["forecast"]?.stringValue == "sunny")
}
@Test func aiTelemetryExecuteToolWrapsToolExecution() async throws {
    let log = ExecutionWrapperLog()
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"city":"Kyoto"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [toolCall], rawValue: .object([:])),
        TextGenerationResult(text: "Done", finishReason: "stop", rawValue: .object([:]))
    ])
    let lookup = AITool(
        name: "lookup",
        parameters: ["type": "object", "properties": ["city": ["type": "string"]]]
    ) { arguments in
        await log.append("tool-body:\(arguments["city"]?.stringValue ?? "missing")")
        return ["forecast": "sunny"]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 2,
        retryPolicy: .none,
        telemetry: Telemetry.Options(integrations: [ExecutionWrappingTelemetry(name: "wrapper", log: log)])
    )

    #expect(result.toolResults.first?.result["forecast"]?.stringValue == "sunny")
    let entries = await log.entries()
    #expect(entries.contains("wrapper-tool-start:call-1:lookup"))
    #expect(entries.contains("tool-body:Kyoto"))
    #expect(entries.contains("wrapper-tool-end"))
    #expect(entries.firstIndex(of: "wrapper-tool-start:call-1:lookup")! < entries.firstIndex(of: "tool-body:Kyoto")!)
    #expect(entries.firstIndex(of: "tool-body:Kyoto")! < entries.firstIndex(of: "wrapper-tool-end")!)
}
@Test func aiGenerateTextStoresToolModelOutput() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"city":"Kyoto"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(
            text: "",
            finishReason: "tool-calls",
            toolCalls: [toolCall],
            rawValue: .object([:])
        ),
        TextGenerationResult(text: "Done", finishReason: "stop", rawValue: .object([:]))
    ])
    let lookup = AITool(
        name: "lookup",
        parameters: ["type": "object", "properties": ["city": ["type": "string"]]],
        toModelOutput: { context in
            [
                "type": "content",
                "value": [
                    [
                        "type": "text",
                        "text": .string("model output for \(context.input["city"]?.stringValue ?? "unknown")")
                    ]
                ]
            ]
        }
    ) { arguments in
        ["raw": arguments["city"] ?? .string("missing")]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 2
    )

    #expect(result.toolResults.first?.result["raw"]?.stringValue == "Kyoto")
    #expect(result.toolResults.first?.modelOutput?["type"]?.stringValue == "content")
    #expect(result.toolResults.first?.modelOutput?["value"]?[0]?["text"]?.stringValue == "model output for Kyoto")
    #expect(result.steps.first?.toolResults.first?.modelOutput?["value"]?[0]?["type"]?.stringValue == "text")
}
@Test func aiStreamTextEmitsStepAndToolTelemetryEvents() async throws {
    let recorder = TelemetryRecorder()
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"city":"Kyoto"}"#)
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .textDelta("Sunny"),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
            ]
        ]
    )
    let lookup = AITool(
        name: "lookup",
        parameters: ["type": "object", "properties": ["city": ["type": "string"]]]
    ) { arguments in
        ["city": arguments["city"] ?? .string("missing")]
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 2,
        telemetry: Telemetry.Options(functionID: "unit.streamToolLoop", integrations: [recorder])
    ) {
        streamed.append(part)
    }
    let events = await recorder.events()
    let stepEvents = events.filter { $0.operationID == "ai.streamText.step" }
    let toolEvents = events.filter { $0.operationID == "ai.streamText.tool" }

    #expect(streamed.contains(.textDelta("Sunny")))
    #expect(stepEvents.map(\.kind) == [.stepStart, .stepEnd, .stepStart, .stepEnd])
    #expect(stepEvents[1].output?["finishReason"]?.stringValue == "tool-calls")
    #expect(stepEvents[3].output?["text"]?.stringValue == "Sunny")
    #expect(toolEvents.map(\.kind) == [.toolStart, .toolEnd])
    #expect(toolEvents.allSatisfy { $0.functionID == "unit.streamToolLoop" })
    #expect(toolEvents[1].output?["result"]?["toolName"]?.stringValue == "lookup")
    #expect(toolEvents[1].output?["result"]?["result"]?["city"]?.stringValue == "Kyoto")
}
@Test func apiCallErrorPreservesResponseHeaders() throws {
    let response = AIHTTPResponse(
        statusCode: 429,
        headers: ["Retry-After": "0"],
        body: Data("rate limited".utf8)
    )

    #expect(apiCallError(provider: "mock", response: response) == .apiCall(
        provider: "mock",
        statusCode: 429,
        body: "rate limited",
        headers: ["Retry-After": "0"]
    ))
    let apiError = try #require(apiCallError(provider: "mock", response: response).apiCallError)
    #expect(apiError.provider == "mock")
    #expect(apiError.statusCode == 429)
    #expect(apiError.responseHeaders["Retry-After"] == "0")
    #expect(apiError.responseBody == "rate limited")
    #expect(apiError.isRetryable)
}
@Test func aiGenerateTextDoesNotRetryNonRetryableErrors() async throws {
    let model = FlakyLanguageModel(failures: [
        AIError.apiCall(provider: "mock", statusCode: 400, body: "bad request")
    ], result: TextGenerationResult(text: "unused", rawValue: .object([:])))

    do {
        _ = try await AI.generateText(
            model: model,
            prompt: "No retry",
            retryPolicy: AIRetryPolicy(maxRetries: 2, initialDelayNanoseconds: 0)
        )
        Issue.record("Expected non-retryable HTTP error.")
    } catch let error as AIError {
        #expect(error == AIError.apiCall(provider: "mock", statusCode: 400, body: "bad request"))
    }

    #expect(model.requests.count == 1)
}
@Test func aiGenerateTextWrapsWhenMaxRetriesExceeded() async throws {
    let model = FlakyLanguageModel(failures: [
        AIError.apiCall(provider: "mock", statusCode: 503, body: "one"),
        AIError.apiCall(provider: "mock", statusCode: 503, body: "two")
    ], result: TextGenerationResult(text: "unused", rawValue: .object([:])))

    do {
        _ = try await AI.generateText(
            model: model,
            prompt: "Retry once",
            retryPolicy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: 0)
        )
        Issue.record("Expected retry exhaustion.")
    } catch let error as AIRetryError {
        #expect(error.reason == .maxRetriesExceeded)
        #expect(error.attempts == 2)
    }

    #expect(model.requests.count == 2)
}
@Test func aiGenerateTextTimesOutThroughRetryPolicy() async throws {
    let model = SlowLanguageModel(delayNanoseconds: 80_000_000)

    do {
        _ = try await AI.generateText(
            model: model,
            prompt: "Too slow",
            retryPolicy: AIRetryPolicy(
                maxRetries: 2,
                initialDelayNanoseconds: 0,
                timeoutNanoseconds: 1_000_000
            )
        )
        Issue.record("Expected timeout.")
    } catch let error as AIError {
        #expect(error == .timeout(durationNanoseconds: 1_000_000))
    }

    #expect(model.requests.count == 1)
}
@Test func aiFacadeTimeoutAppliesToNonLanguageCalls() async throws {
    let model = SlowEmbeddingModel(delayNanoseconds: 80_000_000)

    do {
        _ = try await AI.embed(
            model: model,
            value: "slow",
            retryPolicy: AIRetryPolicy(timeoutNanoseconds: 1_000_000)
        )
        Issue.record("Expected timeout.")
    } catch let error as AIError {
        #expect(error == .timeout(durationNanoseconds: 1_000_000))
    }

    #expect(model.requests.count == 1)
}
