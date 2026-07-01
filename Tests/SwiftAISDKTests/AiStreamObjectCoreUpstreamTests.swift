import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiStreamObjectObjectStreamSendsObjectDeltasLikeUpstream() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: streamObjectContentLanguageParts()
    )

    var partials: [JSONValue] = []
    for try await part in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: StreamObjectContent.self,
        schema: streamObjectContentSchema()
    ) {
        if case let .partialObject(partial) = part {
            partials.append(partial)
        }
    }

    #expect(partials == streamObjectContentPartials())
    #expect(model.streamRequests.first?.messages == [.user("prompt")])
    #expect(model.streamRequests.first?.responseFormat == .json(schema: streamObjectContentSchema()))
    #expect(model.streamRequests.first?.extraBody["responseFormat"]?["type"]?.stringValue == "json")
    #expect(model.streamRequests.first?.extraBody["responseFormat"]?["schema"] == streamObjectContentSchema())
}

@Test func aiStreamObjectObjectStreamUsesNameAndDescriptionLikeUpstream() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: streamObjectContentLanguageParts()
    )

    var partials: [JSONValue] = []
    for try await part in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: StreamObjectContent.self,
        schema: streamObjectContentSchema(),
        schemaName: "test-name",
        schemaDescription: "test description"
    ) {
        if case let .partialObject(partial) = part {
            partials.append(partial)
        }
    }

    #expect(partials == streamObjectContentPartials())
    #expect(model.streamRequests.first?.responseFormat == .json(
        schema: streamObjectContentSchema(),
        name: "test-name",
        description: "test description"
    ))
    #expect(model.streamRequests.first?.extraBody["responseFormat"]?["name"]?.stringValue == "test-name")
    #expect(model.streamRequests.first?.extraBody["responseFormat"]?["description"]?.stringValue == "test description")
}

@Test func aiStreamObjectFullStreamSendsDataLikeUpstream() async throws {
    let usage = TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13)
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: streamObjectContentLanguageParts(finish: .finish(reason: "stop", usage: usage))
    )

    var textDeltas: [String] = []
    var partials: [JSONValue] = []
    var object: ObjectGenerationResult<StreamObjectContent>?
    var finish: (reason: String?, usage: TokenUsage?)?
    for try await part in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: StreamObjectContent.self,
        schema: streamObjectContentSchema()
    ) {
        switch part {
        case let .textDelta(delta):
            textDeltas.append(delta)
        case let .partialObject(partial):
            partials.append(partial)
        case let .object(result):
            object = result
        case let .finish(reason, partUsage):
            finish = (reason, partUsage)
        default:
            break
        }
    }

    #expect(textDeltas == streamObjectContentTextDeltas())
    #expect(partials == streamObjectContentPartials())
    #expect(object?.object == StreamObjectContent(content: "Hello, world!"))
    #expect(object?.rawObject == ["content": "Hello, world!"])
    #expect(object?.text == #"{ "content": "Hello, world!" }"#)
    #expect(finish?.reason == "stop")
    #expect(finish?.usage == usage)
}

@Test func aiStreamObjectTextStreamSendsTextDeltasLikeUpstream() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: streamObjectContentLanguageParts()
    )

    var textDeltas: [String] = []
    for try await part in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: StreamObjectContent.self,
        schema: streamObjectContentSchema()
    ) {
        if case let .textDelta(delta) = part {
            textDeltas.append(delta)
        }
    }

    #expect(textDeltas == streamObjectContentTextDeltas())
}

@Test func aiStreamObjectResolvesResultFieldsLikeUpstream() async throws {
    let providerMetadata: [String: JSONValue] = [
        "testProvider": [
            "testKey": "testValue"
        ]
    ]
    let responseMetadata = AIResponseMetadata(
        id: "test-id",
        timestamp: Date(timeIntervalSince1970: 0),
        modelID: "response-model"
    )
    let usage = TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13)
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: streamObjectContentLanguageParts(
            metadata: [.responseMetadata(responseMetadata)],
            finish: .finishMetadata(
                reason: "stop",
                usage: usage,
                providerMetadata: providerMetadata
            )
        )
    )

    var object: ObjectGenerationResult<StreamObjectContent>?
    var finish: (reason: String?, usage: TokenUsage?)?
    for try await part in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: StreamObjectContent.self,
        schema: streamObjectContentSchema()
    ) {
        switch part {
        case let .object(result):
            object = result
        case let .finish(reason, partUsage):
            finish = (reason, partUsage)
        default:
            break
        }
    }

    #expect(object?.object == StreamObjectContent(content: "Hello, world!"))
    #expect(object?.rawObject == ["content": "Hello, world!"])
    #expect(object?.text == #"{ "content": "Hello, world!" }"#)
    #expect(object?.finishReason == "stop")
    #expect(object?.usage == usage)
    #expect(object?.providerMetadata == providerMetadata)
    #expect(object?.responseMetadata == responseMetadata)
    #expect(finish?.reason == "stop")
    #expect(finish?.usage == usage)
    #expect(model.streamRequests.first?.messages == [.user("prompt")])
}

@Test func aiStreamObjectOnFinishReturnsValidObjectLikeUpstream() async throws {
    let recorder = StreamObjectCallbackUpstreamRecorder()
    let providerMetadata: [String: JSONValue] = [
        "testProvider": [
            "testKey": "testValue"
        ]
    ]
    let responseMetadata = AIResponseMetadata(
        id: "test-id",
        timestamp: Date(timeIntervalSince1970: 0),
        modelID: "response-model"
    )
    let usage = TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13)
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: streamObjectContentLanguageParts(
            metadata: [.responseMetadata(responseMetadata)],
            finish: .finishMetadata(
                reason: "stop",
                usage: usage,
                providerMetadata: providerMetadata
            )
        )
    )

    for try await _ in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: StreamObjectContent.self,
        schema: streamObjectContentSchema(),
        callbacks: AIObjectGenerationCallbacks(
            onFinish: { event in recorder.recordFinish(event) }
        )
    ) {}

    let event = try #require(recorder.finishEvent())
    #expect(event.object == StreamObjectContent(content: "Hello, world!"))
    #expect(event.text == #"{ "content": "Hello, world!" }"#)
    #expect(event.rawObject == ["content": "Hello, world!"])
    #expect(event.finishReason == "stop")
    #expect(event.usage == usage)
    #expect(event.providerMetadata == providerMetadata)
    #expect(event.responseMetadata == responseMetadata)
}

@Test func aiStreamObjectOnErrorInvokedWhenModelStreamFailsLikeUpstream() async throws {
    let recorder = ObjectCallbackRecorder<StreamObjectContent>()
    let model = ObjectFacadeFlakyStreamingLanguageModel(outcomes: [
        .failure(StreamObjectStartFailure())
    ])

    do {
        for try await _ in AI.streamObject(
            model: model,
            prompt: "prompt",
            as: StreamObjectContent.self,
            schema: streamObjectContentSchema(),
            retryPolicy: .none,
            callbacks: AIObjectGenerationCallbacks(
                onError: { event in await recorder.recordError(event) }
            )
        ) {}
        Issue.record("Expected streamObject to throw the model stream failure.")
    } catch is StreamObjectStartFailure {}

    let events = await recorder.events()
    #expect(events.names == ["error"])
    #expect(events.error?.providerID == "mock")
    #expect(events.error?.modelID == "flaky-object-language")
    #expect(events.error?.text == "")
    #expect(events.error?.errorDescription == "StreamObjectStartFailure()")
}

@Test func aiStreamObjectResolvesProviderMetadataLikeUpstream() async throws {
    let providerMetadata: [String: JSONValue] = [
        "testProvider": [
            "testKey": "testValue"
        ]
    ]
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: #"{ "value": "Hello, world!", "count": 1 }"#),
            .textEnd(id: "1"),
            .finishMetadata(
                reason: "stop",
                usage: TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13),
                providerMetadata: providerMetadata
            )
        ]
    )

    var object: ObjectGenerationResult<ObjectFacadeAnswer>?
    var finish: (reason: String?, usage: TokenUsage?)?
    for try await part in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: ObjectFacadeAnswer.self,
        schema: objectFacadeAnswerSchema()
    ) {
        switch part {
        case let .object(result):
            object = result
        case let .finish(reason, usage):
            finish = (reason, usage)
        default:
            break
        }
    }

    #expect(object?.object == ObjectFacadeAnswer(value: "Hello, world!", count: 1))
    #expect(object?.providerMetadata == providerMetadata)
    #expect(object?.finishReason == "stop")
    #expect(object?.usage == TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13))
    #expect(finish?.reason == "stop")
    #expect(finish?.usage == TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13))
}

@Test func aiStreamObjectRejectsWhenStreamedObjectDoesNotMatchSchemaLikeUpstream() async throws {
    let responseMetadata = AIResponseMetadata(
        id: "id-1",
        timestamp: Date(timeIntervalSince1970: 0.123),
        modelID: "model-1"
    )
    let usage = TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13)
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: #"{ "#),
            .textDeltaPart(id: "1", delta: #""invalid": "#),
            .textDeltaPart(id: "1", delta: #""Hello, "#),
            .textDeltaPart(id: "1", delta: "world"),
            .textDeltaPart(id: "1", delta: #"!""#),
            .textDeltaPart(id: "1", delta: #" }"#),
            .textEnd(id: "1"),
            .responseMetadata(responseMetadata),
            .finish(
                reason: "stop",
                usage: usage
            )
        ]
    )

    var object: ObjectGenerationResult<ObjectFacadeAnswer>?
    do {
        for try await part in AI.streamObject(
            model: model,
            prompt: "prompt",
            as: ObjectFacadeAnswer.self,
            schema: objectFacadeAnswerSchema()
        ) {
            if case let .object(result) = part {
                object = result
            }
        }
        Issue.record("Expected streamed object to fail schema validation.")
    } catch let error as AIObjectGenerationError {
        #expect(object == nil)
        #expect(error.provider == "mock")
        #expect(error.strategy == .object)
        #expect(error.kind == .schemaValidation)
        #expect(error.path == "$.value")
        #expect(error.text == #"{ "invalid": "Hello, world!" }"#)
        #expect(!error.repairAttempted)
        #expect(error.finishReason == "stop")
        #expect(error.usage == usage)
        #expect(error.responseMetadata == responseMetadata)
    }
}

@Test func aiStreamObjectPassesHeadersToModelLikeUpstream() async throws {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: #"{ "value": "headers test", "count": 2 }"#),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 3))
        ]
    )

    var partials: [JSONValue] = []
    for try await part in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: ObjectFacadeAnswer.self,
        schema: objectFacadeAnswerSchema(),
        headers: ["custom-request-header": "request-header-value"]
    ) {
        if case let .partialObject(partial) = part {
            partials.append(partial)
        }
    }

    #expect(partials == [
        ["value": "headers test", "count": 2]
    ])
    #expect(model.streamRequests.first?.headers == [
        "custom-request-header": "request-header-value"
    ])
}

@Test func aiStreamObjectPassesProviderOptionsToModelLikeUpstream() async throws {
    let providerOptions: [String: JSONValue] = [
        "aProvider": [
            "someKey": "someValue"
        ]
    ]
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: #"{ "value": "provider metadata test", "count": 3 }"#),
            .textEnd(id: "1"),
            .finish(reason: "stop", usage: TokenUsage(totalTokens: 4))
        ]
    )

    var partials: [JSONValue] = []
    for try await part in AI.streamObject(
        model: model,
        prompt: "prompt",
        as: ObjectFacadeAnswer.self,
        schema: objectFacadeAnswerSchema(),
        providerOptions: providerOptions
    ) {
        if case let .partialObject(partial) = part {
            partials.append(partial)
        }
    }

    #expect(partials == [
        ["value": "provider metadata test", "count": 3]
    ])
    #expect(model.streamRequests.first?.providerOptions == providerOptions)
}

@Test func aiStreamObjectThrowsWhenParsingFailsLikeUpstream() async throws {
    let responseMetadata = AIResponseMetadata(
        id: "id-1",
        timestamp: Date(timeIntervalSince1970: 0.123),
        modelID: "model-1"
    )
    let usage = TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13)
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textStart(id: "1"),
            .textDeltaPart(id: "1", delta: "{ broken json"),
            .textEnd(id: "1"),
            .responseMetadata(responseMetadata),
            .finish(reason: "stop", usage: usage)
        ]
    )

    do {
        for try await _ in AI.streamObject(
            model: model,
            prompt: "prompt",
            as: ObjectFacadeAnswer.self,
            schema: objectFacadeAnswerSchema()
        ) {}
        Issue.record("Expected streamed object parsing to fail.")
    } catch let error as AIObjectGenerationError {
        #expect(error.provider == "mock")
        #expect(error.strategy == .object)
        #expect(error.kind == .noJSON)
        #expect(error.text == "{ broken json")
        #expect(error.finishReason == "stop")
        #expect(error.usage == usage)
        #expect(error.responseMetadata == responseMetadata)
    }
}

@Test func aiStreamObjectThrowsWhenNoTextIsGeneratedLikeUpstream() async throws {
    let responseMetadata = AIResponseMetadata(
        id: "id-1",
        timestamp: Date(timeIntervalSince1970: 0.123),
        modelID: "model-1"
    )
    let usage = TokenUsage(inputTokens: 3, outputTokens: 10, totalTokens: 13)
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .responseMetadata(responseMetadata),
            .finish(reason: "stop", usage: usage)
        ]
    )

    do {
        for try await _ in AI.streamObject(
            model: model,
            prompt: "prompt",
            as: ObjectFacadeAnswer.self,
            schema: objectFacadeAnswerSchema()
        ) {}
        Issue.record("Expected empty streamed object to fail.")
    } catch let error as AIObjectGenerationError {
        #expect(error.provider == "mock")
        #expect(error.strategy == .object)
        #expect(error.kind == .noJSON)
        #expect(error.text == "")
        #expect(error.finishReason == "stop")
        #expect(error.usage == usage)
        #expect(error.responseMetadata == responseMetadata)
    }
}
