import Foundation
import Testing
@testable import SwiftAISDK

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
        AIError.httpStatus(provider: "mock", statusCode: 500, body: "temporary")
    ], result: TextGenerationResult(text: "recovered", rawValue: .object([:])))

    let result = try await AI.generateText(
        model: model,
        prompt: "Retry",
        retryPolicy: AIRetryPolicy(maxRetries: 2, initialDelayNanoseconds: 0)
    )

    #expect(result.text == "recovered")
    #expect(model.requests.count == 2)
}

@Test func aiGenerateTextDoesNotRetryNonRetryableErrors() async throws {
    let model = FlakyLanguageModel(failures: [
        AIError.httpStatus(provider: "mock", statusCode: 400, body: "bad request")
    ], result: TextGenerationResult(text: "unused", rawValue: .object([:])))

    do {
        _ = try await AI.generateText(
            model: model,
            prompt: "No retry",
            retryPolicy: AIRetryPolicy(maxRetries: 2, initialDelayNanoseconds: 0)
        )
        Issue.record("Expected non-retryable HTTP error.")
    } catch let error as AIError {
        #expect(error == AIError.httpStatus(provider: "mock", statusCode: 400, body: "bad request"))
    }

    #expect(model.requests.count == 1)
}

@Test func aiGenerateTextWrapsWhenMaxRetriesExceeded() async throws {
    let model = FlakyLanguageModel(failures: [
        AIError.httpStatus(provider: "mock", statusCode: 503, body: "one"),
        AIError.httpStatus(provider: "mock", statusCode: 503, body: "two")
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

@Test func aiStreamTextForwardsRequestToModel() async throws {
    let parts: [LanguageStreamPart] = [
        .streamStart(warnings: []),
        .textDelta("hi"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 1))
    ]
    let model = MockLanguageModel(result: TextGenerationResult(text: "", rawValue: .object([:])), streamParts: parts)

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(model: model, prompt: "Stream", includeRawChunks: true) {
        streamed.append(part)
    }

    #expect(streamed == parts)
    #expect(model.streamRequests.count == 1)
    #expect(model.streamRequests.first?.messages == [.user("Stream")])
    #expect(model.streamRequests.first?.includeRawChunks == true)
}

@Test func aiStreamTextExecutesTypedToolsAndContinuesUntilFinalStream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"query":"weather"}"#)
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .streamStart(warnings: []),
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .textDelta("It "),
                .textDelta("is sunny."),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 8))
            ]
        ]
    )
    let capture = ToolCapture()
    let lookup = AITool(
        name: "lookup",
        description: "Look up a value.",
        parameters: ["type": "object", "properties": ["query": ["type": "string"]]]
    ) { arguments in
        await capture.record(arguments)
        return ["forecast": "sunny"]
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 3
    ) {
        streamed.append(part)
    }

    #expect(streamed == [
        .streamStart(warnings: []),
        .toolCall(toolCall),
        .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3)),
        .toolResult(AIToolResult(toolCallID: "call-1", toolName: "lookup", result: ["forecast": "sunny"])),
        .textDelta("It "),
        .textDelta("is sunny."),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 8))
    ])
    #expect(await capture.value()?["query"]?.stringValue == "weather")
    #expect(model.streamRequests.count == 2)
    #expect(model.streamRequests[0].tools["lookup"]?["description"]?.stringValue == "Look up a value.")
    #expect(model.streamRequests[1].messages.count == 3)
    #expect(model.streamRequests[1].messages[1].content == [.toolCall(toolCall)])
    guard case let .toolResult(toolResult) = model.streamRequests[1].messages[2].content.first else {
        Issue.record("Expected a tool result message.")
        return
    }
    #expect(toolResult.toolName == "lookup")
    #expect(toolResult.result["forecast"]?.stringValue == "sunny")
}

@Test func aiStreamTextStopsWhenToolLoopConditionMatches() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"query":"weather"}"#)
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .textDelta("This should not stream."),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 5))
            ]
        ]
    )
    let lookup = AITool(
        name: "lookup",
        parameters: ["type": "object", "properties": ["query": ["type": "string"]]]
    ) { arguments in
        ["forecast": "sunny", "query": arguments["query"] ?? .string("")]
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 3,
        stopWhen: [.isStepCount(1)]
    ) {
        streamed.append(part)
    }

    #expect(model.streamRequests.count == 1)
    #expect(streamed == [
        .toolCall(toolCall),
        .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3)),
        .toolResult(AIToolResult(toolCallID: "call-1", toolName: "lookup", result: ["forecast": "sunny", "query": "weather"]))
    ])
}

@Test func aiStreamTextPrepareStepOverridesRequestAndReceivesResponseMessages() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"query":"weather"}"#)
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamSequences: [
            [
                .toolCall(toolCall),
                .finish(reason: "tool-calls", usage: TokenUsage(totalTokens: 3))
            ],
            [
                .textDelta("prepared stream"),
                .finish(reason: "stop", usage: TokenUsage(totalTokens: 8))
            ]
        ]
    )
    let capture = PrepareStepCapture()
    let lookup = AITool(
        name: "lookup",
        parameters: ["type": "object", "properties": ["query": ["type": "string"]]]
    ) { _ in
        ["forecast": "sunny"]
    }

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 3,
        prepareStep: { context in
            await capture.record(context)
            guard context.stepNumber == 1 else { return nil }
            var request = context.request
            request.messages.append(.user("prepared follow-up"))
            request.providerOptions["test"] = ["step": 2]
            return AIPrepareStepResult(request: request)
        }
    ) {
        streamed.append(part)
    }

    #expect(streamed.contains(.textDelta("prepared stream")))
    #expect(model.streamRequests.count == 2)
    #expect(model.streamRequests[1].messages.last == .user("prepared follow-up"))
    #expect(model.streamRequests[1].providerOptions["test"]?["step"]?.intValue == 2)
    #expect(await capture.stepNumbers() == [0, 1])
    #expect(await capture.stepCounts() == [0, 1])
    #expect(await capture.responseMessageCounts() == [0, 2])
}

@Test func aiStreamObjectRequestsSchemaAndEmitsFinalObject() async throws {
    let schema: JSONValue = [
        "type": "object",
        "properties": [
            "value": ["type": "string"],
            "count": ["type": "integer"]
        ],
        "required": ["value", "count"]
    ]
    let warning = AIWarning(type: "unsupported", feature: "seed")
    let responseMetadata = AIResponseMetadata(id: "stream-resp")
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .streamStart(warnings: [warning]),
            .textDelta(#"{"value":"strea"#),
            .textDelta(#"med","count":3}"#),
            .responseMetadata(responseMetadata),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 9))
        ]
    )

    var text = ""
    var object: ObjectGenerationResult<FacadeObjectAnswer>?
    var finish: (reason: String?, usage: TokenUsage?)?
    var warnings: [AIWarning] = []
    var partials: [JSONValue] = []
    for try await part in AI.streamObject(
        model: model,
        prompt: "Stream JSON.",
        as: FacadeObjectAnswer.self,
        schema: schema,
        schemaName: "answer"
    ) {
        switch part {
        case let .textDelta(delta):
            text += delta
        case let .warning(warning):
            warnings.append(warning)
        case let .partialObject(partial):
            partials.append(partial)
        case let .object(result):
            object = result
        case let .finish(reason, usage):
            finish = (reason, usage)
        default:
            break
        }
    }

    #expect(text == #"{"value":"streamed","count":3}"#)
    #expect(warnings == [warning])
    #expect(partials == [
        .object(["value": .string("strea")]),
        .object(["value": .string("streamed"), "count": .number(3)])
    ])
    #expect(object?.object == FacadeObjectAnswer(value: "streamed", count: 3))
    #expect(object?.text == #"{"value":"streamed","count":3}"#)
    #expect(object?.rawObject["count"]?.intValue == 3)
    #expect(object?.finishReason == "stop")
    #expect(object?.usage?.totalTokens == 9)
    #expect(object?.warnings == [warning])
    #expect(object?.responseMetadata == responseMetadata)
    #expect(finish?.reason == "stop")
    #expect(finish?.usage?.totalTokens == 9)

    let request = try #require(model.streamRequests.first)
    #expect(request.messages == [.user("Stream JSON.")])
    #expect(request.responseFormat == .json(schema: schema, name: "answer"))
    #expect(request.extraBody["responseFormat"]?["schema"]?["properties"]?["value"]?["type"]?.stringValue == "string")
    #expect(request.extraBody["responseFormat"]?["name"]?.stringValue == "answer")
}

@Test func aiStreamObjectEmitsBestEffortPartialObjects() async throws {
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta("{"),
            .textDelta(#""value":"partial str"#),
            .textDelta(#"","count":42"#),
            .textDelta("}"),
            .finish(reason: "stop", usage: nil)
        ]
    )

    var partials: [JSONValue] = []
    var object: ObjectGenerationResult<FacadeObjectAnswer>?
    for try await part in AI.streamObject(
        model: model,
        prompt: "Stream partial JSON.",
        as: FacadeObjectAnswer.self
    ) {
        switch part {
        case let .partialObject(partial):
            partials.append(partial)
        case let .object(result):
            object = result
        default:
            break
        }
    }

    #expect(partials == [
        .object([:]),
        .object(["value": .string("partial str")]),
        .object(["value": .string("partial str"), "count": .number(42)])
    ])
    #expect(object?.object == FacadeObjectAnswer(value: "partial str", count: 42))
}

@Test func aiStreamObjectCanRepairFinalText() async throws {
    let model = MockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta("value: repaired"),
            .finish(reason: "stop", usage: nil)
        ]
    )

    let stream = AI.streamObject(
        model: model,
        prompt: "Stream repaired JSON.",
        as: FacadeObjectAnswer.self
    ) { context in
        #expect(context.text == "value: repaired")
        return #"{"value":"repaired","count":4}"#
    }

    var object: ObjectGenerationResult<FacadeObjectAnswer>?
    for try await part in stream {
        if case let .object(result) = part {
            object = result
        }
    }

    #expect(object?.object == FacadeObjectAnswer(value: "repaired", count: 4))
    #expect(object?.text == #"{"value":"repaired","count":4}"#)
}

@Test func aiGenerateTextExecutesTypedToolsAndContinuesUntilFinalText() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"query":"weather"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [toolCall], rawValue: .object(["step": 1])),
        TextGenerationResult(text: "It is sunny.", finishReason: "stop", rawValue: .object(["step": 2]))
    ])
    let capture = ToolCapture()
    let lookup = AITool(
        name: "lookup",
        description: "Look up a value.",
        parameters: ["type": "object", "properties": ["query": ["type": "string"]]]
    ) { arguments in
        await capture.record(arguments)
        return ["forecast": "sunny"]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 3
    )

    #expect(result.text == "It is sunny.")
    let executedArguments = await capture.value()
    #expect(executedArguments?["query"]?.stringValue == "weather")
    #expect(result.toolResults.count == 1)
    #expect(result.toolResults[0].toolCallID == "call-1")
    #expect(result.toolResults[0].result["forecast"]?.stringValue == "sunny")
    #expect(result.steps.count == 2)
    #expect(result.steps[0].toolCalls == [toolCall])
    #expect(result.steps[0].toolResults.count == 1)
    #expect(result.steps[1].text == "It is sunny.")

    #expect(model.requests.count == 2)
    #expect(model.requests[0].tools["lookup"]?["description"]?.stringValue == "Look up a value.")
    #expect(model.requests[1].messages.count == 3)
    #expect(model.requests[1].messages[1].content == [.toolCall(toolCall)])
    guard case let .toolResult(toolResult) = model.requests[1].messages[2].content.first else {
        Issue.record("Expected a tool result message.")
        return
    }
    #expect(toolResult.toolName == "lookup")
    #expect(toolResult.result["forecast"]?.stringValue == "sunny")
}

@Test func aiGenerateTextStopsWhenToolLoopConditionMatches() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "finalAnswer", arguments: #"{"value":"done"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [toolCall], rawValue: .object(["step": 1])),
        TextGenerationResult(text: "This should not be requested.", finishReason: "stop", rawValue: .object(["step": 2]))
    ])
    let finalAnswer = AITool(
        name: "finalAnswer",
        parameters: ["type": "object", "properties": ["value": ["type": "string"]]]
    ) { arguments in
        ["value": arguments["value"] ?? .string("missing")]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Stop after final answer tool.",
        executableTools: [finalAnswer],
        maxSteps: 3,
        stopWhen: [.hasToolCall("finalAnswer")]
    )

    #expect(model.requests.count == 1)
    #expect(result.text == "")
    #expect(result.toolResults == [
        AIToolResult(toolCallID: "call-1", toolName: "finalAnswer", result: ["value": "done"])
    ])
    #expect(result.steps.count == 1)
    #expect(result.steps[0].toolCalls == [toolCall])
    #expect(result.steps[0].toolResults.count == 1)
}

@Test func aiGenerateTextPrepareStepOverridesRequestAndReceivesResponseMessages() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "lookup", arguments: #"{"query":"weather"}"#)
    let model = MockLanguageModel(results: [
        TextGenerationResult(text: "", finishReason: "tool-calls", toolCalls: [toolCall], rawValue: .object(["step": 1])),
        TextGenerationResult(text: "prepared answer", finishReason: "stop", rawValue: .object(["step": 2]))
    ])
    let capture = PrepareStepCapture()
    let lookup = AITool(
        name: "lookup",
        parameters: ["type": "object", "properties": ["query": ["type": "string"]]]
    ) { _ in
        ["forecast": "sunny"]
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "Weather?",
        executableTools: [lookup],
        maxSteps: 3,
        prepareStep: { context in
            await capture.record(context)
            guard context.stepNumber == 1 else { return nil }
            var request = context.request
            request.messages.append(.user("prepared follow-up"))
            request.toolChoice = ["type": "tool", "toolName": "lookup"]
            request.providerOptions["test"] = ["step": 2]
            return AIPrepareStepResult(request: request)
        }
    )

    #expect(result.text == "prepared answer")
    #expect(model.requests.count == 2)
    #expect(model.requests[1].messages.last == .user("prepared follow-up"))
    #expect(model.requests[1].toolChoice?["toolName"]?.stringValue == "lookup")
    #expect(model.requests[1].providerOptions["test"]?["step"]?.intValue == 2)
    #expect(await capture.stepNumbers() == [0, 1])
    #expect(await capture.stepCounts() == [0, 1])
    #expect(await capture.responseMessageCounts() == [0, 2])
}

@Test func aiStopConditionsMatchUpstreamStepHelpers() async throws {
    let searchStep = AIToolStep(
        index: 0,
        text: "",
        toolCalls: [AIToolCall(id: "call-1", name: "search", arguments: "{}")]
    )
    let finalStep = AIToolStep(
        index: 1,
        text: "",
        toolCalls: [AIToolCall(id: "call-2", name: "finalAnswer", arguments: "{}")]
    )
    let context = AIStopConditionContext(steps: [searchStep, finalStep])

    #expect(try await AIStopCondition.isStepCount(2).evaluate(context))
    #expect(try await !AIStopCondition.isStepCount(1).evaluate(context))
    #expect(try await !AIStopCondition.isLoopFinished().evaluate(context))
    #expect(try await AIStopCondition.hasToolCall("finalAnswer").evaluate(context))
    #expect(try await AIStopCondition.hasToolCall("search", "finalAnswer").evaluate(context))
    #expect(try await !AIStopCondition.hasToolCall("search").evaluate(context))
}

@Test func aiGenerateObjectDecodesJSONAndRequestsSchemaResponseFormat() async throws {
    let model = MockLanguageModel(result: TextGenerationResult(
        text: """
        ```json
        {"value":"test-value","count":2}
        ```
        """,
        finishReason: "stop",
        usage: TokenUsage(totalTokens: 7),
        rawValue: .object(["id": "raw-1"]),
        responseMetadata: AIResponseMetadata(id: "resp-1")
    ))
    let schema: JSONValue = [
        "type": "object",
        "properties": [
            "value": ["type": "string"],
            "count": ["type": "integer"]
        ],
        "required": ["value", "count"]
    ]

    let result = try await AI.generateObject(
        model: model,
        prompt: "Return an object.",
        as: FacadeObjectAnswer.self,
        schema: schema,
        schemaName: "answer",
        schemaDescription: "A typed answer."
    )

    #expect(result.object == FacadeObjectAnswer(value: "test-value", count: 2))
    #expect(result.rawObject["value"]?.stringValue == "test-value")
    #expect(result.finishReason == "stop")
    #expect(result.usage?.totalTokens == 7)
    #expect(result.responseMetadata.id == "resp-1")

    let request = try #require(model.requests.first)
    #expect(request.responseFormat == .json(schema: schema, name: "answer", description: "A typed answer."))
    #expect(request.extraBody["responseFormat"]?["type"]?.stringValue == "json")
    #expect(request.extraBody["responseFormat"]?["schema"]?["properties"]?["value"]?["type"]?.stringValue == "string")
    #expect(request.extraBody["responseFormat"]?["name"]?.stringValue == "answer")
    #expect(request.extraBody["responseFormat"]?["description"]?.stringValue == "A typed answer.")
}

@Test func aiGenerateObjectCanRepairInvalidJSONText() async throws {
    let model = MockLanguageModel(result: TextGenerationResult(text: "value: repaired", rawValue: .object([:])))

    let result = try await AI.generateObject(
        model: model,
        prompt: "Return JSON.",
        as: FacadeObjectAnswer.self
    ) { context in
        #expect(context.text == "value: repaired")
        return #"{"value":"repaired","count":1}"#
    }

    #expect(result.object == FacadeObjectAnswer(value: "repaired", count: 1))
    #expect(result.text == #"{"value":"repaired","count":1}"#)
}

private struct FacadeObjectAnswer: Codable, Equatable, Sendable {
    var value: String
    var count: Int
}

private actor ToolCapture {
    private var arguments: JSONValue?

    func record(_ arguments: JSONValue) {
        self.arguments = arguments
    }

    func value() -> JSONValue? {
        arguments
    }
}

private actor PrepareStepCapture {
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

@Test func aiEmbedManyChunksAndAggregatesResults() async throws {
    let model = MockEmbeddingModel(results: [
        EmbeddingResult(
            embeddings: [[0.1], [0.2]],
            usage: TokenUsage(inputTokens: 2, totalTokens: 2),
            rawValue: .object(["chunk": .number(1)]),
            warnings: [AIWarning(type: "unsupported", feature: "seed")],
            providerMetadata: ["provider": .object(["first": .bool(true)])],
            responseMetadata: AIResponseMetadata(id: "resp-1")
        ),
        EmbeddingResult(
            embeddings: [[0.3]],
            usage: TokenUsage(inputTokens: 1, totalTokens: 1),
            rawValue: .object(["chunk": .number(2)]),
            providerMetadata: ["provider": .object(["second": .bool(true)])]
        )
    ])

    let result = try await AI.embedMany(
        model: model,
        values: ["a", "b", "c"],
        dimensions: 64,
        chunkSize: 2,
        providerOptions: ["test": .object(["flag": .bool(true)])]
    )

    #expect(model.requests.map(\.values) == [["a", "b"], ["c"]])
    #expect(model.requests.allSatisfy { $0.dimensions == 64 })
    #expect(model.requests.allSatisfy { $0.providerOptions["test"]?["flag"]?.boolValue == true })
    #expect(result.embeddings == [[0.1], [0.2], [0.3]])
    #expect(result.usage == TokenUsage(inputTokens: 3, totalTokens: 3))
    #expect(result.rawValue[0]?["chunk"]?.intValue == 1)
    #expect(result.rawValue[1]?["chunk"]?.intValue == 2)
    #expect(result.warnings == [AIWarning(type: "unsupported", feature: "seed")])
    #expect(result.providerMetadata["provider"]?["second"]?.boolValue == true)
    #expect(result.responseMetadata.id == "resp-1")
}

@Test func aiFacadeForwardsMediaRerankAndUploadRequests() async throws {
    let imageModel = MockImageModel(result: ImageGenerationResult(urls: ["https://example.com/image.png"], rawValue: .object([:])))
    let image = try await AI.generateImage(model: imageModel, prompt: "cat", size: "1024x1024", providerOptions: ["image": .object(["quality": .string("high")])])
    #expect(image.urls == ["https://example.com/image.png"])
    #expect(imageModel.requests.first?.prompt == "cat")
    #expect(imageModel.requests.first?.providerOptions["image"]?["quality"]?.stringValue == "high")

    let transcriptionModel = MockTranscriptionModel(result: TranscriptionResult(text: "hello", rawValue: .object([:])))
    let transcription = try await AI.transcribe(model: transcriptionModel, request: AudioTranscriptionRequest(audio: Data("wav".utf8), language: "en"))
    #expect(transcription.text == "hello")
    #expect(transcriptionModel.requests.first?.language == "en")

    let speechModel = MockSpeechModel(result: SpeechResult(audio: Data("audio".utf8)))
    let speech = try await AI.generateSpeech(model: speechModel, request: SpeechRequest(text: "hello", voice: "alloy"))
    #expect(String(data: speech.audio, encoding: .utf8) == "audio")
    #expect(speechModel.requests.first?.voice == "alloy")

    let videoModel = MockVideoModel(result: VideoGenerationResult(urls: ["https://example.com/video.mp4"], rawValue: .object([:])))
    let video = try await AI.generateVideo(model: videoModel, request: VideoGenerationRequest(prompt: "clip"))
    #expect(video.urls == ["https://example.com/video.mp4"])
    #expect(videoModel.requests.first?.prompt == "clip")

    let rerankingModel = MockRerankingModel(result: RerankingResult(results: [RerankedDocument(index: 1, score: 0.9)], rawValue: .object([:])))
    let ranking = try await AI.rerank(model: rerankingModel, request: RerankingRequest(query: "q", documents: ["a", "b"], topK: 1))
    #expect(ranking.results.first?.index == 1)
    #expect(rerankingModel.requests.first?.topK == 1)

    let fileClient = MockFileClient(result: FileUploadResult(providerReference: ["file": "file-1"], rawValue: .object([:])))
    let file = try await AI.uploadFile(client: fileClient, request: FileUploadRequest(data: Data("file".utf8), mediaType: "text/plain", filename: "a.txt"))
    #expect(file.providerReference["file"] == "file-1")
    #expect(fileClient.requests.first?.filename == "a.txt")

    let skillClient = MockSkillsClient(result: SkillUploadResult(providerReference: ["skill": "skill-1"], rawValue: .object([:])))
    let skill = try await AI.uploadSkill(client: skillClient, request: SkillUploadRequest(files: [SkillUploadFile(path: "skill.md", data: Data("skill".utf8))]))
    #expect(skill.providerReference["skill"] == "skill-1")
    #expect(skillClient.requests.first?.files.first?.path == "skill.md")
}

private final class MockLanguageModel: LanguageModel, @unchecked Sendable {
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

private final class FlakyLanguageModel: LanguageModel, @unchecked Sendable {
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

private final class MockEmbeddingModel: EmbeddingModel, @unchecked Sendable {
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

private final class MockImageModel: ImageModel, @unchecked Sendable {
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

private final class MockTranscriptionModel: TranscriptionModel, @unchecked Sendable {
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

private final class MockSpeechModel: SpeechModel, @unchecked Sendable {
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

private final class MockVideoModel: VideoModel, @unchecked Sendable {
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

private final class MockRerankingModel: RerankingModel, @unchecked Sendable {
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

private final class MockFileClient: AIFileClient, @unchecked Sendable {
    let providerID = "mock.files"
    var requests: [FileUploadRequest] = []
    let result: FileUploadResult

    init(result: FileUploadResult) { self.result = result }

    func uploadFile(_ request: FileUploadRequest) async throws -> FileUploadResult {
        requests.append(request)
        return result
    }
}

private final class MockSkillsClient: AISkillsClient, @unchecked Sendable {
    let providerID = "mock.skills"
    var requests: [SkillUploadRequest] = []
    let result: SkillUploadResult

    init(result: SkillUploadResult) { self.result = result }

    func uploadSkill(_ request: SkillUploadRequest) async throws -> SkillUploadResult {
        requests.append(request)
        return result
    }
}
