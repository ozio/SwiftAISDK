import Foundation
import Testing
@testable import SwiftAISDK

@Suite("WeeklyEvaluation20261011Tests")
struct WeeklyEvaluation20261011Tests {
    @Test func openAINativeDecisionBodyMetadataUsageAndOrdering() async throws {
        let transport = RecordingTransport(response: jsonResponse(openAIDecisionFixture, headers: ["x-request-id": "req"]))
        let model = nativeDecisionModel(transport: transport)
        let questions: [String: AIDecisionQuestion] = [
            "flag": .boolean(instructions: ["task": "True?"], criteria: ["true": ["meaning": "yes"], "false": .null]),
            "choice": .choice(instructions: "Pick", criteria: ["a": .null, "b": ["meaning": "Other"]]),
            "score": .score(instructions: ["Rate"], criteria: ["Low", .null, ["meaning": "High"]])
        ]
        let result = try await model.doDecide(.init(
            state: [.text("Inspect."), .json([1, .null]), .file(mediaType: "image", data: .data(Data([0x89, 0x50, 0x4e, 0x47])), providerOptions: ["openai": ["imageDetail": "original"]]), .text("Look for cracks.")],
            questions: questions,
            headers: ["shared": "call"],
            providerOptions: ["openai": ["safetyIdentifier": "", "reasoningEffort": "high"]]
        ))
        #expect(result.answers == decisionTestAnswers)
        #expect(result.usage == .init(inputTokens: 30, outputTokens: 4))
        #expect(result.rounding == .init(probabilityDecimals: 2, scoreDecimals: 2))
        #expect(result.response?.modelID == "resolved")
        #expect(result.response?.headers["x-request-id"] == "req")
        #expect(result.providerMetadata["openai"]?["confidence"] == ["choice": 0.8, "score": 0.9])
        #expect(result.providerMetadata["openai"]?["usage"]?["input_tokens_details"]?["cached_tokens"] == 7)
        #expect(result.providerMetadata["openai"]?["usage"]?["output_tokens_details"]?["reasoning_tokens"] == 2)
        #expect(result.warnings == [.init(type: "unsupported", feature: "providerOptions.openai.reasoningEffort")])
        let request = try #require(await transport.requests().first)
        #expect(request.url.absoluteString == "https://example.com/v1/decisions")
        #expect(request.headers["authorization"] == "Bearer key")
        #expect(request.headers["shared"] == "call")
        let body = try decodeJSONBody(try #require(request.body))
        #expect(body["safety_identifier"] == "")
        #expect(body["reasoningEffort"] == nil)
        #expect(body["input"]?[0]?["content"] == [
            ["type": "input_text", "text": "Inspect."],
            ["type": "input_text", "text": "[1,null]"],
            ["type": "input_image", "image_url": "data:image/png;base64,iVBORw==", "detail": "original"],
            ["type": "input_text", "text": "Look for cracks."]
        ])
        let nativeQuestions = try #require(body["questions"]?.arrayValue)
        let flag = try #require(nativeQuestions.first { $0["name"] == "flag" })
        #expect(flag["type"] == "predicate")
        let expectedFlagInstructions = #"{"task":"True?"}"# + "\n\nCriteria for true:\n" + #"{"meaning":"yes"}"#
        #expect(flag["instructions"]?.stringValue == expectedFlagInstructions)
        let choice = try #require(nativeQuestions.first { $0["name"] == "choice" })
        #expect(choice["choices"]?[0]?["description"] == nil)
        #expect(choice["choices"]?[1]?["description"] == #"{"meaning":"Other"}"#)
        let score = try #require(nativeQuestions.first { $0["name"] == "score" })
        #expect(score["levels"]?[1]?["description"] == nil)
        #expect(score["levels"]?[2]?["label"] == "2")
    }

    @Test(arguments: [JSONValue.number(123), .null, .string(String(repeating: "x", count: 129))])
    func openAIRejectsInvalidSafetyIdentifierBeforeIO(value: JSONValue) async {
        let transport = RecordingTransport(response: jsonResponse(openAIDecisionFixture))
        let model = nativeDecisionModel(transport: transport)
        await #expect(throws: AIError.self) {
            try await model.doDecide(.init(state: [], questions: decisionTestQuestions, providerOptions: ["openai": ["safetyIdentifier": value]]))
        }
        #expect(await transport.requests().isEmpty)
    }

    @Test func openAIValidatesDuplicateDistributionsNamesAndUnnamedRefusal() async throws {
        let fixture = try decodeJSONBody(Data(openAIDecisionFixture.utf8))
        let baseAnswers = try #require(fixture["answers"]?.arrayValue)
        var duplicateDistribution = baseAnswers
        duplicateDistribution[1] = ["type": "choice", "name": "choice", "choice": "a", "probabilities": [["value": "a", "probability": 0.7], ["value": "a", "probability": 0.3]]]
        let variants: [[JSONValue]] = [
            Array(baseAnswers.dropLast()),
            baseAnswers + [baseAnswers[0]],
            baseAnswers.dropLast() + [["type": "predicate", "name": "unknown", "probability": 0.8]],
            baseAnswers.dropLast() + [["type": "refusal", "name": .null]],
            duplicateDistribution
        ]
        for answers in variants {
            let body: JSONValue = .object(["answers": .array(answers)])
            let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: [:], body: try encodeJSONBody(body)))
            await #expect(throws: AIError.self) {
                try await nativeDecisionModel(transport: transport).doDecide(.init(state: [], questions: decisionTestQuestions))
            }
        }
    }

    @Test func openAIRawRefusalPreservedAndCoreRejectsWithoutRetry() async throws {
        var fixture = try #require(try decodeJSONBody(Data(openAIDecisionFixture.utf8)).objectValue)
        var answers = try #require(fixture["answers"]?.arrayValue)
        answers[0] = ["type": "refusal", "name": "score"]
        fixture["answers"] = .array(answers)
        let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: [:], body: try encodeJSONBody(.object(fixture))))
        let model = nativeDecisionModel(transport: transport)
        let result = try await model.doDecide(.init(state: [], questions: decisionTestQuestions))
        #expect(result.answers["score"] == .refusal)
        #expect(result.providerMetadata["openai"]?["confidence"]?["score"] == nil)
        await #expect(throws: AIDecisionRefusalError.self) {
            try await AI.experimentalDecide(model: model, state: "", questions: decisionTestQuestions)
        }
        #expect(await transport.requests().count == 2)
    }

    @Test(arguments: ["audio/wav", "image/svg+xml"])
    func openAIRejectsUnsupportedMediaBeforeIO(mediaType: String) async {
        let transport = RecordingTransport(response: jsonResponse(openAIDecisionFixture))
        await #expect(throws: AIDecisionUnsupportedFunctionalityError.self) {
            try await nativeDecisionModel(transport: transport).doDecide(.init(state: [.file(mediaType: mediaType, data: .base64("AAAA"))], questions: decisionTestQuestions))
        }
        #expect(await transport.requests().isEmpty)
    }

    @Test func openAIPartialUsageKeepsZeroAndNativeDetails() async throws {
        let fixture = try decodeJSONBody(Data(openAIDecisionFixture.utf8))
        for usage: JSONValue in [.null, ["input_tokens": 0, "output_tokens": .null], ["input_tokens": .null, "output_tokens": 0]] {
            let body: JSONValue = ["answers": try #require(fixture["answers"]), "usage": usage]
            let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: [:], body: try encodeJSONBody(body)))
            let result = try await nativeDecisionModel(transport: transport).doDecide(.init(state: [], questions: decisionTestQuestions))
            if usage == .null {
                #expect(result.usage == nil)
                #expect(result.providerMetadata["openai"]?["usage"] == nil)
            } else {
                #expect(result.usage?.inputTokens == usage["input_tokens"]?.intValue)
                #expect(result.usage?.outputTokens == usage["output_tokens"]?.intValue)
                #expect(result.providerMetadata["openai"]?["usage"] == usage)
            }
        }
    }

    @Test func evaluationAliasesPreserveJSONArraysAndAcceptNewOrderedParts() async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"answers":{"flag":{"type":"noul","noul":0.3}}}"#))
        let model = try TypeSafeAIProvider(settings: .init(apiKey: "key", transport: transport)).evaluationModel("jev-latest")
        let questions: [String: AIEvaluationQuestion] = ["flag": .boolean(instructions: "True?")]
        let legacy = try await AI.experimentalEvaluate(model: model, state: [1, .null], questions: questions)
        #expect(legacy.answers == ["flag": .boolean(probability: 0.3)])
        #expect(try decodeJSONBody(try #require(await transport.requests().first?.body))["state"] == [1, .null])
        let ordered = try await AI.experimentalEvaluate(model: model, stateParts: [.text("Evidence"), .json([1, .null])], questions: questions)
        #expect(ordered.answers == legacy.answers)
        #expect(try decodeJSONBody(try #require(await transport.requests().last?.body))["state"] == "Evidence\n[1,null]")
    }
}

private func nativeDecisionModel(transport: any AITransport) -> OpenAIDecisionModel {
    OpenAIDecisionModel(modelID: "gpt-6-luna", config: ModelHTTPConfig(providerID: "openai.decision", baseURL: "https://example.com/v1", headers: ["authorization": "Bearer key", "shared": "provider"], transport: transport, failedResponseHandling: .openAICompatible))
}

private let openAIDecisionFixture = #"""
{"model":"resolved","answers":[
 {"type":"score","name":"score","score":1.8,"confidence":0.9,"probabilities":[{"value":0,"probability":0.05},{"value":1,"probability":0.1},{"value":2,"probability":0.85}]},
 {"type":"choice","name":"choice","choice":"a","confidence":0.8,"probabilities":[{"value":"a","probability":0.7},{"value":"b","probability":0.3}]},
 {"type":"predicate","name":"flag","probability":0.85}],
 "usage":{"input_tokens":30,"input_tokens_details":{"cached_tokens":7,"cache_write_tokens":3},"output_tokens":4,"output_tokens_details":{"reasoning_tokens":2},"total_tokens":34}}
"""#
