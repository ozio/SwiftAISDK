import Foundation
import Testing
@testable import SwiftAISDK

private struct GenerateObjectContent: Codable, Equatable, Sendable {
    var content: String
}

private func generateObjectContentSchema() -> JSONValue {
    [
        "type": "object",
        "properties": [
            "content": ["type": "string"]
        ],
        "required": ["content"],
        "additionalProperties": false
    ]
}

@Test func aiGenerateObjectReturnsObjectAndForwardsSchemaLikeUpstream() async throws {
    let responseMetadata = AIResponseMetadata(
        id: "test-id-from-model",
        timestamp: Date(timeIntervalSince1970: 10),
        modelID: "test-response-model-id",
        headers: [
            "custom-response-header": "response-header-value"
        ],
        body: "test body"
    )
    let warning = AIWarning(type: "other", message: "Setting is not supported")
    let schema = objectFacadeAnswerSchema(additionalProperties: false)
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{ "value": "Hello, world!", "count": 13 }"#,
        finishReason: "stop",
        usage: TokenUsage(inputTokens: 10, outputTokens: 20, totalTokens: 30),
        providerMetadata: [
            "exampleProvider": [
                "a": 10,
                "b": 20
            ]
        ],
        rawValue: ["raw": true],
        warnings: [warning],
        responseMetadata: responseMetadata
    ))

    let result = try await AI.generateObject(
        model: model,
        prompt: "prompt",
        as: ObjectFacadeAnswer.self,
        schema: schema,
        schemaName: "test-name",
        schemaDescription: "test description",
        headers: [
            "custom-request-header": "request-header-value"
        ]
    )

    #expect(result.object == ObjectFacadeAnswer(value: "Hello, world!", count: 13))
    #expect(result.rawObject["value"]?.stringValue == "Hello, world!")
    #expect(result.rawObject["count"]?.intValue == 13)
    #expect(result.text == #"{ "value": "Hello, world!", "count": 13 }"#)
    #expect(result.finishReason == "stop")
    #expect(result.usage == TokenUsage(inputTokens: 10, outputTokens: 20, totalTokens: 30))
    #expect(result.warnings == [warning])
    #expect(result.providerMetadata["exampleProvider"]?["a"]?.intValue == 10)
    #expect(result.providerMetadata["exampleProvider"]?["b"]?.intValue == 20)
    #expect(result.responseMetadata == responseMetadata)

    let request = try #require(model.requests.first)
    #expect(request.messages == [.user("prompt")])
    #expect(request.headers["custom-request-header"] == "request-header-value")
    #expect(request.responseFormat == .json(
        schema: schema,
        name: "test-name",
        description: "test description"
    ))
    #expect(request.extraBody["responseFormat"]?["type"]?.stringValue == "json")
    #expect(request.extraBody["responseFormat"]?["name"]?.stringValue == "test-name")
    #expect(request.extraBody["responseFormat"]?["description"]?.stringValue == "test description")
    #expect(request.extraBody["responseFormat"]?["schema"]?["properties"]?["value"]?["type"]?.stringValue == "string")
    #expect(request.extraBody["responseFormat"]?["schema"]?["additionalProperties"]?.boolValue == false)
}

@Test func aiGenerateObjectReturnsWarningsLikeUpstream() async throws {
    let expectedWarnings = [
        AIWarning(type: "other", message: "Setting is not supported")
    ]
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{ "content": "Hello, world!" }"#,
        rawValue: .object([:]),
        warnings: expectedWarnings
    ))

    let result = try await AI.generateObject(
        model: model,
        prompt: "prompt",
        as: GenerateObjectContent.self,
        schema: generateObjectContentSchema()
    )

    #expect(result.object == GenerateObjectContent(content: "Hello, world!"))
    #expect(result.warnings == expectedWarnings)
}

@Test func aiGenerateObjectLogsWarningsLikeUpstream() async throws {
    let expectedWarnings = [
        AIWarning(type: "other", message: "Setting is not supported"),
        AIWarning(
            type: "unsupported",
            feature: "temperature",
            message: "Temperature parameter not supported"
        )
    ]
    let recorder = GenerateObjectWarningLogRecorder()
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{ "content": "Hello, world!" }"#,
        rawValue: .object([:]),
        warnings: expectedWarnings
    ))

    try await AIWarningLogging.withLogger(recorder) {
        _ = try await AI.generateObject(
            model: model,
            prompt: "prompt",
            as: GenerateObjectContent.self,
            schema: generateObjectContentSchema()
        )
    }

    #expect(await recorder.events() == [
        AIWarningLogEvent(warnings: expectedWarnings, providerID: "mock", modelID: "mock-language")
    ])
}

@Test func aiGenerateObjectLogsEmptyWarningsLikeUpstream() async throws {
    let recorder = GenerateObjectWarningLogRecorder()
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{ "content": "Hello, world!" }"#,
        rawValue: .object([:]),
        warnings: []
    ))

    try await AIWarningLogging.withLogger(recorder) {
        _ = try await AI.generateObject(
            model: model,
            prompt: "prompt",
            as: GenerateObjectContent.self,
            schema: generateObjectContentSchema()
        )
    }

    #expect(await recorder.events() == [
        AIWarningLogEvent(warnings: [], providerID: "mock", modelID: "mock-language")
    ])
}

@Test func aiGenerateObjectResolvesRequestAndResponseMetadataLikeUpstream() async throws {
    let requestMetadata = AIRequestMetadata(
        body: "test body",
        headers: ["custom-request-header": "request-header-value"]
    )
    let responseMetadata = AIResponseMetadata(
        id: "test-id-from-model",
        timestamp: Date(timeIntervalSince1970: 10),
        modelID: "test-response-model-id",
        headers: [
            "custom-response-header": "response-header-value"
        ],
        body: "test body"
    )
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{ "content": "Hello, world!" }"#,
        rawValue: .object([:]),
        requestMetadata: requestMetadata,
        responseMetadata: responseMetadata
    ))

    let result = try await AI.generateObject(
        model: model,
        prompt: "prompt",
        as: GenerateObjectContent.self,
        schema: generateObjectContentSchema()
    )

    #expect(result.object == GenerateObjectContent(content: "Hello, world!"))
    #expect(result.textResult.requestMetadata == requestMetadata)
    #expect(result.responseMetadata == responseMetadata)
}

@Test func aiGenerateObjectCustomSchemaGeneratesObjectLikeUpstream() async throws {
    let schema = generateObjectContentSchema()
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{ "content": "Hello, world!" }"#,
        rawValue: .object([:])
    ))

    let result = try await AI.generateObject(
        model: model,
        prompt: "prompt",
        as: GenerateObjectContent.self,
        schema: schema
    )

    #expect(result.object == GenerateObjectContent(content: "Hello, world!"))
    #expect(model.requests.first?.messages == [.user("prompt")])
    #expect(model.requests.first?.responseFormat == .json(schema: schema))
    #expect(model.requests.first?.extraBody["responseFormat"]?["type"]?.stringValue == "json")
    #expect(model.requests.first?.extraBody["responseFormat"]?["schema"] == schema)
}

@Test func aiGenerateObjectPassesProviderOptionsLikeUpstream() async throws {
    let providerOptions: [String: JSONValue] = [
        "aProvider": [
            "someKey": "someValue"
        ]
    ]
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{ "content": "provider metadata test" }"#,
        rawValue: .object([:])
    ))

    let result = try await AI.generateObject(
        model: model,
        prompt: "prompt",
        as: GenerateObjectContent.self,
        schema: generateObjectContentSchema(),
        providerOptions: providerOptions
    )

    #expect(result.object == GenerateObjectContent(content: "provider metadata test"))
    #expect(model.requests.first?.providerOptions == providerOptions)
}

@Test func aiGenerateObjectArrayGeneratesElementsLikeUpstream() async throws {
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{"elements":[{"content":"element 1"},{"content":"element 2"},{"content":"element 3"}]}"#,
        rawValue: .object([:])
    ))

    let result = try await AI.generateObjectArray(
        model: model,
        prompt: "prompt",
        as: GenerateObjectContent.self,
        elementSchema: generateObjectContentSchema()
    )

    #expect(result.object == [
        GenerateObjectContent(content: "element 1"),
        GenerateObjectContent(content: "element 2"),
        GenerateObjectContent(content: "element 3")
    ])
    #expect(model.requests.first?.messages == [.user("prompt")])
    #expect(model.requests.first?.responseFormat == .json(
        schema: arrayOutputSchemaForTest(elementSchema: generateObjectContentSchema())
    ))
    #expect(model.requests.first?.extraBody["responseFormat"]?["schema"]?["properties"]?["elements"]?["items"]?["properties"]?["content"]?["type"]?.stringValue == "string")
}

@Test func aiGenerateObjectEnumGeneratesValueLikeUpstream() async throws {
    let values = ["sunny", "rainy", "snowy"]
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{"result":"sunny"}"#,
        rawValue: .object([:])
    ))

    let result = try await AI.generateEnum(
        model: model,
        prompt: "prompt",
        values: values
    )

    #expect(result.object == "sunny")
    #expect(model.requests.first?.messages == [.user("prompt")])
    #expect(model.requests.first?.responseFormat == .json(schema: enumOutputSchemaForTest(values: values)))
    #expect(model.requests.first?.extraBody["responseFormat"]?["schema"]?["properties"]?["result"]?["enum"]?[0]?.stringValue == "sunny")
    #expect(model.requests.first?.extraBody["responseFormat"]?["schema"]?["properties"]?["result"]?["enum"]?[1]?.stringValue == "rainy")
    #expect(model.requests.first?.extraBody["responseFormat"]?["schema"]?["properties"]?["result"]?["enum"]?[2]?.stringValue == "snowy")
}

@Test func aiGenerateObjectNoSchemaGeneratesObjectLikeUpstream() async throws {
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{ "content": "Hello, world!" }"#,
        rawValue: .object([:])
    ))

    let result = try await AI.generateJSON(
        model: model,
        prompt: "prompt"
    )

    #expect(result.object == ["content": "Hello, world!"])
    #expect(model.requests.first?.messages == [.user("prompt")])
    #expect(model.requests.first?.responseFormat == .json())
    #expect(model.requests.first?.extraBody["responseFormat"]?["type"]?.stringValue == "json")
    #expect(model.requests.first?.extraBody["responseFormat"]?["schema"] == nil)
    #expect(model.requests.first?.extraBody["responseFormat"]?["name"] == nil)
    #expect(model.requests.first?.extraBody["responseFormat"]?["description"] == nil)
}

@Test func aiGenerateObjectThrowsWhenSchemaValidationFailsLikeUpstream() async throws {
    let responseMetadata = generateObjectDummyResponseMetadata()
    let usage = generateObjectDummyUsage()
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{ "content": 123 }"#,
        finishReason: "stop",
        usage: usage,
        rawValue: .object([:]),
        responseMetadata: responseMetadata
    ))

    do {
        _ = try await AI.generateObject(
            model: model,
            prompt: "prompt",
            as: GenerateObjectContent.self,
            schema: generateObjectContentSchema()
        )
        Issue.record("Expected generateObject to fail schema validation.")
    } catch let error as AIObjectGenerationError {
        #expect(error.provider == "mock")
        #expect(error.strategy == .object)
        #expect(error.kind == .schemaValidation)
        #expect(error.path == "$.content")
        #expect(error.text == #"{ "content": 123 }"#)
        #expect(!error.repairAttempted)
        #expect(error.finishReason == "stop")
        #expect(error.usage == usage)
        #expect(error.responseMetadata == responseMetadata)
    }
}

@Test func aiGenerateObjectThrowsWhenParsingFailsLikeUpstream() async throws {
    let responseMetadata = generateObjectDummyResponseMetadata()
    let usage = generateObjectDummyUsage()
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: "{ broken json",
        finishReason: "stop",
        usage: usage,
        rawValue: .object([:]),
        responseMetadata: responseMetadata
    ))

    do {
        _ = try await AI.generateObject(
            model: model,
            prompt: "prompt",
            as: GenerateObjectContent.self,
            schema: generateObjectContentSchema()
        )
        Issue.record("Expected generateObject parsing to fail.")
    } catch let error as AIObjectGenerationError {
        #expect(error.provider == "mock")
        #expect(error.strategy == .object)
        #expect(error.kind == .noJSON)
        #expect(error.text == "{ broken json")
        #expect(!error.repairAttempted)
        #expect(error.finishReason == "stop")
        #expect(error.usage == usage)
        #expect(error.responseMetadata == responseMetadata)
    }
}

@Test func aiGenerateObjectThrowsWhenRepairStillFailsLikeUpstream() async throws {
    let responseMetadata = generateObjectDummyResponseMetadata()
    let usage = generateObjectDummyUsage()
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: "{ broken json",
        finishReason: "stop",
        usage: usage,
        rawValue: .object([:]),
        responseMetadata: responseMetadata
    ))

    do {
        _ = try await AI.generateObject(
            model: model,
            prompt: "prompt",
            as: GenerateObjectContent.self,
            schema: generateObjectContentSchema()
        ) { context in
            #expect(context.text == "{ broken json")
            return context.text + "{"
        }
        Issue.record("Expected generateObject repaired parsing to fail.")
    } catch let error as AIObjectGenerationError {
        #expect(error.provider == "mock")
        #expect(error.strategy == .object)
        #expect(error.kind == .noJSON)
        #expect(error.text == "{ broken json{")
        #expect(error.repairAttempted)
        #expect(error.finishReason == "stop")
        #expect(error.usage == usage)
        #expect(error.responseMetadata == responseMetadata)
    }
}

@Test func aiGenerateObjectThrowsWhenNoTextIsAvailableLikeUpstream() async throws {
    let responseMetadata = generateObjectDummyResponseMetadata()
    let usage = generateObjectDummyUsage()
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: "",
        finishReason: "stop",
        usage: usage,
        rawValue: .object([:]),
        responseMetadata: responseMetadata
    ))

    do {
        _ = try await AI.generateObject(
            model: model,
            prompt: "prompt",
            as: GenerateObjectContent.self,
            schema: generateObjectContentSchema()
        )
        Issue.record("Expected generateObject with no text to fail.")
    } catch let error as AIObjectGenerationError {
        #expect(error.provider == "mock")
        #expect(error.strategy == .object)
        #expect(error.kind == .noJSON)
        #expect(error.text == "")
        #expect(!error.repairAttempted)
        #expect(error.finishReason == "stop")
        #expect(error.usage == usage)
        #expect(error.responseMetadata == responseMetadata)
    }
}

@Test func aiGenerateObjectIncludesReasoningInResultLikeUpstream() async throws {
    let model = ObjectFacadeMockLanguageModel(result: TextGenerationResult(
        text: #"{ "value": "Hello, world!", "count": 1 }"#,
        reasoning: "This is a test reasoning.\nThis is another test reasoning.",
        rawValue: .object([:])
    ))

    let result = try await AI.generateObject(
        model: model,
        prompt: "prompt",
        as: ObjectFacadeAnswer.self,
        schema: objectFacadeAnswerSchema()
    )

    #expect(result.reasoning == "This is a test reasoning.\nThis is another test reasoning.")
    #expect(result.object == ObjectFacadeAnswer(value: "Hello, world!", count: 1))
}

private func generateObjectDummyUsage() -> TokenUsage {
    TokenUsage(inputTokens: 10, outputTokens: 20, totalTokens: 30)
}

private func generateObjectDummyResponseMetadata() -> AIResponseMetadata {
    AIResponseMetadata(
        id: "id-1",
        timestamp: Date(timeIntervalSince1970: 0.123),
        modelID: "m-1"
    )
}

private actor GenerateObjectWarningLogRecorder: AIWarningLogger {
    private var recordedEvents: [AIWarningLogEvent] = []

    func logWarnings(_ event: AIWarningLogEvent) {
        recordedEvents.append(event)
    }

    func events() -> [AIWarningLogEvent] {
        recordedEvents
    }
}
