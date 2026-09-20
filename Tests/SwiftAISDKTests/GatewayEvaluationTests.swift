import Foundation
import Testing
@testable import SwiftAISDK

@Suite("GatewayEvaluationTests")
struct GatewayEvaluationTests {
    @Test func sendsEvaluationV4RequestAndParsesCompleteResult() async throws {
        let raw = """
        {
          "answers": {
            "correct": {"type":"boolean","probability":0.97},
            "tone": {"type":"choice","choice":"neutral","probabilities":{"neutral":0.9,"playful":0.1}},
            "quality": {"type":"score","score":1.8,"probabilities":{"0":0.05,"1":0.1,"2":0.85}}
          },
          "rounding": {"probabilityDecimals":2,"scoreDecimals":2},
          "usage": {"inputTokens":42,"outputTokens":7},
          "warnings": [{"type":"unsupported","feature":"providerOptions.typesafe.effort","details":"ignored"}],
          "providerMetadata": {"gateway":{"cost":"0.002"}}
        }
        """
        let transport = RecordingTransport(response: jsonResponse(
            raw,
            headers: ["x-request-id": "req-123"]
        ))
        let provider = try AIProviders.gateway(settings: ProviderSettings(
            apiKey: "gateway-key",
            baseURL: "https://api.test.com",
            transport: transport
        ))
        let model = try provider.evaluationModel("typesafe-ai/jev-latest")
        let abortController = AIAbortController()

        let result = try await model.doEvaluate(AIEvaluationModelV4CallOptions(
            state: "The capital of France is Paris.",
            questions: gatewayEvaluationQuestions(),
            abortSignal: abortController.signal,
            headers: ["Custom-Header": "test-value"],
            providerOptions: ["typesafe": ["effort": "high"]]
        ))

        #expect(model.providerID == "gateway")
        #expect(model.modelID == "typesafe-ai/jev-latest")
        #expect(model.supportedQuestionTypes == [.choice, .score, .boolean])
        #expect(result.answers == [
            "correct": .boolean(probability: 0.97),
            "tone": .choice(choice: "neutral", probabilities: ["neutral": 0.9, "playful": 0.1]),
            "quality": .score(score: 1.8, probabilities: ["0": 0.05, "1": 0.1, "2": 0.85])
        ])
        #expect(result.rounding == AIEvaluationRounding(probabilityDecimals: 2, scoreDecimals: 2))
        #expect(result.usage == AIEvaluationModelUsage(inputTokens: 42, outputTokens: 7))
        #expect(result.warnings == [AIWarning(
            type: "unsupported",
            feature: "providerOptions.typesafe.effort",
            message: "ignored"
        )])
        #expect(result.providerMetadata == ["gateway": ["cost": "0.002"]])
        #expect(result.response?.modelID == "typesafe-ai/jev-latest")
        #expect(result.response?.headers["x-request-id"] == "req-123")
        let expectedResponseBody = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
        #expect(result.response?.body == expectedResponseBody)

        let request = try #require(await transport.requests().first)
        #expect(request.url.absoluteString == "https://api.test.com/evaluation-model")
        #expect(request.abortSignal === abortController.signal)
        #expect(request.headers["authorization"] == "Bearer gateway-key")
        #expect(request.headers["Custom-Header"] == "test-value")
        #expect(request.headers["ai-evaluation-model-specification-version"] == "4")
        #expect(request.headers["ai-model-id"] == "typesafe-ai/jev-latest")
        let requestBody = try decodeJSONBody(try #require(request.body))
        #expect(requestBody["state"] == "The capital of France is Paris.")
        #expect(requestBody["questions"]?["correct"]?["type"] == "boolean")
        #expect(requestBody["questions"]?["correct"]?["criteria"] == nil)
        #expect(requestBody["questions"]?["tone"]?["criteria"]?["playful"] == .null)
        #expect(requestBody["questions"]?["quality"]?["criteria"] == ["Poor.", "Acceptable.", "Excellent."])
        #expect(requestBody["providerOptions"] == ["typesafe": ["effort": "high"]])
    }

    @Test func omitsOptionalFieldsAndDefaultsWarningsAndMetadata() async throws {
        let transport = RecordingTransport(response: jsonResponse("""
        {"answers":{"correct":{"type":"boolean","probability":0.5}}}
        """))
        let provider = try AIProviders.gateway(settings: ProviderSettings(
            apiKey: "gateway-key",
            transport: transport
        ))
        let result = try await provider.evaluation("model").doEvaluate(
            AIEvaluationModelV4CallOptions(
                state: "state",
                questions: ["correct": .boolean(instructions: "Correct?")]
            )
        )

        #expect(result.rounding == nil)
        #expect(result.usage == nil)
        #expect(result.warnings.isEmpty)
        #expect(result.providerMetadata.isEmpty)
        let body = try decodeJSONBody(try #require(await transport.requests().first?.body))
        #expect(body["providerOptions"] == nil)
    }

    @Test func mapsHTTPAndMalformedResponsesToGatewayErrors() async throws {
        let errorResponses = [
            AIHTTPResponse(
                statusCode: 400,
                headers: ["content-type": "application/json"],
                body: Data(#"{"error":{"message":"Invalid questions format","type":"invalid_request_error"}}"#.utf8)
            ),
            AIHTTPResponse(
                statusCode: 500,
                headers: ["content-type": "application/json"],
                body: Data(#"{"error":{"message":"Internal server error","type":"internal_server_error"}}"#.utf8)
            ),
            jsonResponse(#"{"answers":{"broken":{"type":"choice"}}}"#)
        ]

        for (index, response) in errorResponses.enumerated() {
            let transport = RecordingTransport(response: response)
            let provider = try AIProviders.gateway(settings: ProviderSettings(
                apiKey: "gateway-key",
                transport: transport
            ))
            do {
                _ = try await provider.evaluationModel("model").doEvaluate(
                    AIEvaluationModelV4CallOptions(
                        state: "state",
                        questions: ["broken": .choice(instructions: "Pick", criteria: ["a": .null])]
                    )
                )
                Issue.record("Expected Gateway evaluation error for case \(index).")
            } catch let error as GatewayError {
                #expect(error.statusCode == [400, 500, 200][index])
                #expect(error.type == [.invalidRequestError, .internalServerError, .responseError][index])
            } catch let error as AIError {
                guard case let .gateway(gatewayError) = error else {
                    Issue.record("Expected Gateway error, got \(error).")
                    continue
                }
                #expect(gatewayError.statusCode == [400, 500, 200][index])
                #expect(gatewayError.type == [.invalidRequestError, .internalServerError, .responseError][index])
            }
        }
    }

    @Test func exposesProviderEvaluationAdaptersAndRejectsGenericProviders() throws {
        let openAI = try AIProviders.openAI(settings: ProviderSettings(apiKey: "key"))
        let anthropic = try AIProviders.anthropic(settings: ProviderSettings(
            apiKey: "key", name: "custom.messages"
        ))
        let google = try AIProviders.google(settings: ProviderSettings(
            apiKey: "key", name: "custom.generative-ai"
        ))

        let openAIModel = try openAI.evaluationModel("gpt-5")
        let anthropicModel = try anthropic.evaluationModel("claude-sonnet-4-6")
        let googleModel = try google.evaluationModel("gemini-3.6-flash")

        #expect(openAI.supportedCapabilities.contains(.evaluation))
        #expect(openAIModel.providerID == "openai.evaluation")
        #expect(openAIModel.modelID == "gpt-5")
        #expect(anthropic.supportedCapabilities.contains(.evaluation))
        #expect(anthropicModel.providerID == "custom.evaluation")
        #expect(anthropicModel.modelID == "claude-sonnet-4-6")
        #expect(google.providerID == "custom.generative-ai")
        #expect(google.supportedCapabilities.contains(.evaluation))
        #expect(googleModel.providerID == "custom.evaluation")
        #expect(googleModel.modelID == "gemini-3.6-flash")

        let generic = try AIProviders.deepSeek(settings: ProviderSettings(apiKey: "key"))
        #expect(!generic.supportedCapabilities.contains(.evaluation))
        #expect(throws: AIEvaluationModelResolutionError.noSuchModel(modelID: "chat")) {
            _ = try generic.evaluationModel("chat")
        }
    }

    @Test func preservesEvaluationEntriesFromGatewayModelCatalog() async throws {
        let transport = RecordingTransport(response: jsonResponse("""
        {
          "models": [{
            "id": "typesafe-ai/jev-latest",
            "name": "Jev",
            "modelType": "evaluation",
            "specification": {
              "provider": "typesafe-ai",
              "modelId": "jev-latest"
            }
          }]
        }
        """))
        let provider = try AIProviders.gateway(settings: ProviderSettings(
            apiKey: "gateway-key",
            baseURL: "https://api.test.com",
            transport: transport
        ))

        let entry = try #require(try await provider.getAvailableModels().first)
        #expect(entry == GatewayModelEntry(
            id: "typesafe-ai/jev-latest", name: "Jev", modelType: "evaluation",
            provider: "typesafe-ai", modelID: "jev-latest"
        ))
        #expect(await transport.requests().first?.url.absoluteString == "https://api.test.com/config")
    }
}

private func gatewayEvaluationQuestions() -> [String: AIEvaluationQuestion] {
    [
        "correct": .boolean(instructions: "Is the statement factually correct?"),
        "tone": .choice(
            instructions: "What is the tone?",
            criteria: ["neutral": "Plain and factual.", "playful": .null]
        ),
        "quality": .score(
            instructions: "Rate the quality.",
            criteria: ["Poor.", "Acceptable.", "Excellent."]
        )
    ]
}
