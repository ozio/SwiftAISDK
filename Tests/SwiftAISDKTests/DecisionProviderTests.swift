import Foundation
import Testing
@testable import SwiftAISDK

@Suite("DecisionProviderTests")
struct DecisionProviderTests {
    @Test func languageAdapterUsesPortableSchemaAndOrderedEvidence() async throws {
        let language = DecisionTestLanguageModel(result: TextGenerationResult(text: #"{"q0":"c1","q1":0.3,"q2":1.25}"#, finishReason: "stop", usage: .init(inputTokens: 10, outputTokens: 5), rawValue: .null))
        let model = DecisionLanguageModel(model: language)
        let state: [AIDecisionStatePart] = [.text("Inspect"), .json([1, .null]), .file(mediaType: "image/png", data: .data(Data([0x89, 0x50, 0x4e, 0x47])), filename: "image.png")]
        let result = try await model.doDecide(.init(state: state, questions: decisionTestQuestions, headers: ["custom": "header"], providerOptions: ["test": ["effort": "high"]]))
        // Sorted native keys: choice, flag, score.
        #expect(result.answers == ["choice": .choice(choice: "b"), "flag": .boolean(probability: 0.3), "score": .score(score: 1.25)])
        let request = try #require(language.lastRequest)
        guard case let .json(schema, name, _) = request.responseFormat else { Issue.record("Expected JSON schema"); return }
        #expect(name == "decision")
        #expect(schema?["required"] == ["q0", "q1", "q2"])
        #expect(schema?["properties"]?["q0"]?["enum"] == ["c0", "c1"])
        #expect(schema?["additionalProperties"] == false)
        #expect(request.reasoning == "none")
        #expect(request.providerOptions == ["test": ["effort": "high"]])
        #expect(request.headers == ["custom": "header"])
        let content = try #require(request.messages.last?.content)
        #expect(content.count == 5)
        guard case let .text(rubrics, _) = content[0] else { Issue.record("Expected rubric text"); return }
        let rubric = try decodeJSONBody(Data(rubrics.utf8))
        #expect(rubric["state"] == nil)
        #expect(rubric["questions"]?["q0"]?["criteria"]?["c1"]?["label"] == "b")
        #expect(content[1] == .text("Shared state:"))
        #expect(content[2] == .text("Inspect"))
        #expect(content[3] == .text("[1,null]"))
        #expect(content[4] == .file(mimeType: "image/png", data: Data([0x89, 0x50, 0x4e, 0x47]), filename: "image.png"))
    }

    @Test func languageAdapterPreservesUsageMetadataAndOnlyUsesTextOutput() async throws {
        let language = DecisionTestLanguageModel(result: TextGenerationResult(text: "", content: [.reasoning("ignore"), .text(#"{"q0":"#), .text(#"0.3}"#)], finishReason: "stop", usage: .init(inputTokens: 0, outputTokens: 0), providerMetadata: ["test": ["raw": true]], rawValue: .null, warnings: [.init(type: "other", message: "notice")], responseMetadata: .init(id: "response", modelID: "resolved")))
        let result = try await DecisionLanguageModel(model: language).doDecide(.init(state: [.text("state")], questions: ["flag": .boolean(instructions: "True?")]))
        #expect(result.answers == ["flag": .boolean(probability: 0.3)])
        #expect(result.usage == .init(inputTokens: 0, outputTokens: 0))
        #expect(result.response?.id == "response")
        #expect(result.providerMetadata == ["test": ["raw": true]])
        #expect(result.warnings.count == 1)
    }

    @Test(arguments: ["length", "tool-calls", "unknown"])
    func languageAdapterRejectsIncompleteGeneration(reason: String) async {
        let language = DecisionTestLanguageModel(result: TextGenerationResult(text: #"{"q0":0.3}"#, finishReason: reason, rawValue: .null))
        await #expect(throws: AIError.self) {
            try await DecisionLanguageModel(model: language).doDecide(.init(state: [], questions: ["flag": .boolean(instructions: "True?")]))
        }
    }

    @Test(arguments: ["not json", "[]", "{}", #"{"q0":true}"#, #"{"q0":1.1}"#, #"{"q0":0.5,"extra":0}"#])
    func languageAdapterRejectsInvalidOutput(text: String) async {
        let language = DecisionTestLanguageModel(result: TextGenerationResult(text: text, finishReason: "stop", rawValue: .null))
        await #expect(throws: AIError.self) {
            try await DecisionLanguageModel(model: language).doDecide(.init(state: [], questions: ["flag": .boolean(instructions: "True?")]))
        }
    }

    @Test func languageAdapterRejectsUnsupportedMediaBeforeGenerationAndStrictlyUsesCodes() async {
        let language = DecisionTestLanguageModel(result: TextGenerationResult(text: #"{"q0":"a"}"#, finishReason: "stop", rawValue: .null))
        let model = DecisionLanguageModel(model: language)
        await #expect(throws: AIDecisionUnsupportedFunctionalityError.self) {
            try await model.doDecide(.init(state: [.file(mediaType: "audio/wav", data: .base64("AAAA"))], questions: decisionTestQuestions))
        }
        #expect(language.callCount == 0)
        // Published provider-utils@5.0.58 rejects exact labels; a newer monorepo fixture differs.
        await #expect(throws: AIError.self) {
            try await model.doDecide(.init(state: [], questions: ["choice": .choice(instructions: "Pick", criteria: ["a": .null])]))
        }
    }

    @Test func gatewayDecisionUsesNewRouteHeadersPartsAndRefusals() async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"model":"resolved","answers":{"flag":{"type":"refusal"}},"providerMetadata":{"gateway":{"cost":"0.01"}}}"#, headers: ["x-test": "id"]))
        let provider = try GatewayProvider(settings: .init(apiKey: "key", baseURL: "https://example.com", headers: ["ai-o11y-region": "iad1"], transport: transport))
        let model = try provider.decisionModel("test-model")
        let result = try await model.doDecide(.init(state: [.file(mediaType: "image/png", data: .data(Data([0x89, 0x50, 0x4e, 0x47])))], questions: ["flag": .boolean(instructions: "True?")], headers: ["call": "value"]))
        #expect(result.answers == ["flag": .refusal])
        #expect(result.usage == nil)
        #expect(result.rounding == nil)
        #expect(result.warnings == [])
        #expect(result.response?.modelID == "resolved")
        #expect(result.response?.headers["x-test"] == "id")
        let request = try #require(await transport.requests().first)
        #expect(request.url.absoluteString == "https://example.com/decision-model")
        #expect(request.headers["ai-decision-model-specification-version"] == "4")
        #expect(request.headers["ai-evaluation-model-specification-version"] == nil)
        #expect(request.headers["ai-model-id"] == "test-model")
        #expect(request.headers["ai-o11y-region"] == "iad1")
        #expect(request.headers["call"] == "value")
        let body = try decodeJSONBody(try #require(request.body))
        #expect(body["state"] == nil)
        #expect(body["stateParts"] == [["type": "file", "mediaType": "image/png", "data": ["type": "data", "data": "iVBORw=="]]])
    }

    @Test func gatewayRefusedEvaluationAliasThrowsBeforePartialResult() async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"answers":{"flag":{"type":"refusal"}}}"#))
        let provider = try GatewayProvider(settings: .init(apiKey: "key", transport: transport))
        await #expect(throws: AIDecisionRefusalError.self) {
            try await provider.evaluationModel("model").doEvaluate(.init(state: "state", questions: ["flag": .boolean(instructions: "True?")]))
        }
        #expect(await transport.requests().count == 1)
    }

    @Test func gatewayRejectsURLDataBeforeHTTP() async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"answers":{}}"#))
        let model = try GatewayProvider(settings: .init(apiKey: "key", transport: transport)).decisionModel("model")
        await #expect(throws: AIDecisionUnsupportedFunctionalityError.self) {
            try await model.doDecide(.init(state: [.file(mediaType: "image/png", data: .url(try #require(URL(string: "https://example.com/image.png"))))], questions: decisionTestQuestions))
        }
        #expect(await transport.requests().isEmpty)
    }

    @Test func typesafeJoinsOrderedTextJSONAndPreservesSingleJSON() async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"answers":{"flag":{"type":"noul","noul":0.7}},"usage":{"input_tokens":0,"output_tokens":null}}"#))
        let provider = TypeSafeAIProvider(settings: .init(apiKey: "key", baseURL: "https://example.com/", transport: transport))
        let model = try provider.decisionModel("future-model")
        let questions: [String: AIDecisionQuestion] = ["flag": .boolean(instructions: "True?")]
        let result = try await model.doDecide(.init(state: [.text("Inspect."), .json([1, .null])], questions: questions, providerOptions: ["typesafe": ["effort": "high"]]))
        #expect(result.answers == ["flag": .boolean(probability: 0.7)])
        #expect(result.usage == .init(inputTokens: 0))
        #expect(result.rounding == .init(probabilityDecimals: 2, scoreDecimals: 2))
        #expect(result.warnings == [.init(type: "unsupported", feature: "providerOptions.typesafe.effort")])
        let request = try #require(await transport.requests().first)
        #expect(request.url.absoluteString == "https://example.com/systemone")
        let body = try decodeJSONBody(try #require(request.body))
        #expect(body["state"] == "Inspect.\n[1,null]")
        #expect(body["questions"]?["flag"]?["type"] == "noul")
        _ = try await model.doDecide(.init(state: [.json([1, .null])], questions: questions))
        #expect(try decodeJSONBody(try #require(await transport.requests().last?.body))["state"] == [1, .null])
    }

    @Test func typesafeRejectsImagesBeforeHTTP() async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"answers":{}}"#))
        let provider = TypeSafeAIProvider(settings: .init(apiKey: "key", transport: transport))
        await #expect(throws: AIDecisionUnsupportedFunctionalityError.self) {
            try await provider.decisionModel("model").doDecide(.init(state: [.file(mediaType: "image/png", data: .base64("AAAA"))], questions: decisionTestQuestions))
        }
        #expect(await transport.requests().isEmpty)
    }
}

final class DecisionTestLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "test.language"
    let modelID = "test-model"
    private let lock = NSLock()
    private var calls: [LanguageModelRequest] = []
    private let result: TextGenerationResult
    var lastRequest: LanguageModelRequest? { lock.withLock { calls.last } }
    var callCount: Int { lock.withLock { calls.count } }
    init(result: TextGenerationResult) { self.result = result }
    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        lock.withLock { calls.append(request) }
        return result
    }
}
