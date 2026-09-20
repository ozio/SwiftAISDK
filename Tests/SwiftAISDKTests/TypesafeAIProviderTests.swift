import Foundation
import Testing
@testable import SwiftAISDK

@Suite("TypesafeAI", .serialized)
struct TypesafeAIProviderTests {
    @Test func exposesEvaluationV4AndRejectsUnsupportedFactories() throws {
        let provider = createTypeSafeAI(settings: ProviderSettings(environment: [:]))
        let upstreamCasedProvider = createTypeSafeAi(settings: ProviderSettings(environment: [:]))
        let model = try provider.evaluationModel("jev-latest")

        #expect(typeSafeAIProviderVersion == "3.0.4")
        #expect(typeSafeAI.providerID == "typesafe")
        #expect(typeSafeAi.providerID == "typesafe")
        #expect(upstreamCasedProvider.providerID == "typesafe")
        #expect(provider.providerID == "typesafe")
        #expect(provider.supportedCapabilities == [.evaluation])
        #expect(model.specificationVersion == "v4")
        #expect(model.providerID == "typesafe.evaluation")
        #expect(model.modelID == "jev-latest")
        #expect(model.supportedQuestionTypes == [.choice, .score, .boolean])

        #expect(throws: AIError.unsupportedModel(provider: "typesafe", capability: .language, modelID: "unknown")) {
            _ = try provider.languageModel("unknown")
        }
        #expect(throws: AIError.unsupportedModel(provider: "typesafe", capability: .embedding, modelID: "unknown")) {
            _ = try provider.embeddingModel("unknown")
        }
        #expect(throws: AIError.unsupportedModel(provider: "typesafe", capability: .image, modelID: "unknown")) {
            _ = try provider.imageModel("unknown")
        }
    }

    @Test func sendsNativeQuestionsAndPreservesAnswersMetadataAndUsage() async throws {
        let responseBody = typesafeNativeResponse()
        let transport = RecordingTransport(response: jsonResponse(
            responseBody,
            headers: ["x-request-id": "request-1"]
        ))
        let provider = createTypeSafeAI(settings: ProviderSettings(
            apiKey: "test-api-key",
            transport: transport
        ))
        let model = try provider.evaluationModel("jev-latest")
        let abortController = AIAbortController()

        let result = try await model.doEvaluate(AIEvaluationModelV4CallOptions(
            state: typesafeState(),
            questions: typesafeQuestions(),
            abortSignal: abortController.signal
        ))

        #expect(result.answers == [
            "department": .choice(
                choice: "billing",
                probabilities: ["technical": 0, "other": 0, "billing": 1]
            ),
            "severity": .score(
                score: 0.97,
                probabilities: ["0": 0.13, "1": 0.76, "2": 0.11]
            ),
            "requestsRefund": .boolean(probability: 0.99)
        ])
        #expect(result.rounding == AIEvaluationRounding(probabilityDecimals: 2, scoreDecimals: 2))
        #expect(result.usage == AIEvaluationModelUsage(inputTokens: 471, outputTokens: 71))
        #expect(result.warnings.isEmpty)
        #expect(result.providerMetadata == [
            "typesafe": ["confidence": ["department": 1, "severity": 0.64]]
        ])
        #expect(result.response?.modelID == "jev-1.13.0")
        #expect(result.response?.headers["x-request-id"] == "request-1")
        let expectedResponseBody = try decodeJSONBody(Data(responseBody.utf8))
        #expect(result.response?.body == expectedResponseBody)

        let request = try #require(await transport.requests().first)
        #expect(request.url.absoluteString == "https://api.typesafe.ai/v1/systemone")
        #expect(request.abortSignal === abortController.signal)
        #expect(request.headers["authorization"] == "Bearer test-api-key")
        #expect(request.headers["content-type"] == "application/json")
        #expect(request.headers["user-agent"] == "ai-sdk/typesafe-ai/3.0.4")
        let requestBody = try decodeJSONBody(try #require(request.body))
        #expect(requestBody["model"] == "jev-latest")
        #expect(requestBody["state"] == typesafeState())
        #expect(requestBody["questions"]?["department"]?["type"] == "choice")
        #expect(requestBody["questions"]?["department"]?["criteria"]?["other"] == .null)
        #expect(requestBody["questions"]?["severity"]?["type"] == "score")
        #expect(requestBody["questions"]?["severity"]?["criteria"]?[2] == "Blocking; no workaround")
        #expect(requestBody["questions"]?["requestsRefund"]?["type"] == "noul")
        #expect(requestBody["questions"]?["requestsRefund"]?["criteria"]?["false"] == .null)
    }

    @Test func supportsCustomBaseHeadersTransportAndFutureModelIDs() async throws {
        let transport = RecordingTransport(response: jsonResponse(
            typesafeNativeResponse(),
            headers: ["x-request-id": "custom-request"]
        ))
        let provider = createTypeSafeAI(settings: ProviderSettings(
            apiKey: "custom-key",
            baseURL: "https://custom.example/v1/",
            headers: [
                "Authorization": "Bearer header-key",
                "Custom": "provider",
                "Shared": "provider",
                "User-Agent": "Example/1.0"
            ],
            transport: transport
        ))

        let result = try await provider.evaluationModel("jev-future").doEvaluate(
            AIEvaluationModelV4CallOptions(
                state: typesafeState(),
                questions: typesafeQuestions(),
                headers: ["Shared": "call"]
            )
        )

        let request = try #require(await transport.requests().first)
        #expect(request.url.absoluteString == "https://custom.example/v1/systemone")
        #expect(request.headers["authorization"] == "Bearer header-key")
        #expect(request.headers["custom"] == "provider")
        #expect(request.headers["shared"] == "call")
        #expect(request.headers["user-agent"] == "Example/1.0 ai-sdk/typesafe-ai/3.0.4")
        #expect(try decodeJSONBody(try #require(request.body))["model"] == "jev-future")
        #expect(result.response?.headers["x-request-id"] == "custom-request")
    }

    @Test func resolvesEnvironmentAuthenticationLazily() async throws {
        let transport = RecordingTransport(response: jsonResponse(typesafeNativeResponse()))
        let provider = createTypeSafeAI(settings: ProviderSettings(
            environment: ["TYPESAFE_AI_API_KEY": "environment-key"],
            transport: transport
        ))
        let model = try provider.evaluationModel("jev-latest")

        _ = try await model.doEvaluate(typesafeOptions())

        #expect(await transport.requests().first?.headers["authorization"] == "Bearer environment-key")

        let missingProvider = createTypeSafeAI(settings: ProviderSettings(
            environment: [:],
            transport: transport
        ))
        let missingModel = try missingProvider.evaluationModel("jev-latest")
        await #expect(throws: AIError.missingAPIKey(
            provider: "typesafe",
            environmentVariables: ["TYPESAFE_AI_API_KEY"]
        )) {
            _ = try await missingModel.doEvaluate(typesafeOptions())
        }
        #expect(await transport.requests().count == 1)
    }

    @Test func warnsForProviderOptionsWithoutSendingThem() async throws {
        let transport = RecordingTransport(response: jsonResponse(typesafeNativeResponse()))
        let model = try createTypeSafeAI(settings: ProviderSettings(
            apiKey: "key",
            transport: transport
        )).evaluationModel("jev-latest")

        let result = try await model.doEvaluate(AIEvaluationModelV4CallOptions(
            state: typesafeState(),
            questions: typesafeQuestions(),
            providerOptions: [
                "typesafe": ["temperature": 0, "effort": "high"],
                "other": ["keep": true]
            ]
        ))

        #expect(result.warnings == [
            AIWarning(type: "unsupported", feature: "providerOptions.typesafe.effort"),
            AIWarning(type: "unsupported", feature: "providerOptions.typesafe.temperature")
        ])
        let requestBody = try decodeJSONBody(try #require(await transport.requests().first?.body))
        #expect(requestBody["providerOptions"] == nil)
    }

    @Test func rejectsProviderLimitsBeforeHTTP() async throws {
        let transport = RecordingTransport(response: jsonResponse(typesafeNativeResponse()))
        let model = try createTypeSafeAI(settings: ProviderSettings(
            apiKey: "key",
            transport: transport
        )).evaluationModel("jev-latest")
        let tooManyChoices = Dictionary(uniqueKeysWithValues: (0..<256).map { (String($0), JSONValue.null) })

        await #expect(throws: AIError.invalidArgument(
            argument: "questions.choice.criteria",
            message: "TypeSafe Choice questions support at most 255 options."
        )) {
            _ = try await model.doEvaluate(AIEvaluationModelV4CallOptions(
                state: "state",
                questions: ["choice": .choice(instructions: "Pick", criteria: tooManyChoices)]
            ))
        }
        await #expect(throws: AIError.invalidArgument(
            argument: "questions.score.criteria",
            message: "TypeSafe Score questions support at most 10 levels."
        )) {
            _ = try await model.doEvaluate(AIEvaluationModelV4CallOptions(
                state: "state",
                questions: [
                    "score": .score(
                        instructions: "Rate",
                        criteria: (0..<11).map { JSONValue.string("Level \($0)") }
                    )
                ]
            ))
        }

        #expect(await transport.requests().isEmpty)
    }

    @Test(arguments: [401, 422, 429, 529])
    func preservesHTTPStatusMessageAndRetryability(status: Int) async throws {
        let transport = RecordingTransport(response: AIHTTPResponse(
            statusCode: status,
            headers: ["content-type": "application/json", "x-request-id": "failed"],
            body: Data(#"{"detail":"Provider error"}"#.utf8)
        ))
        let model = try createTypeSafeAI(settings: ProviderSettings(
            apiKey: "key",
            transport: transport
        )).evaluationModel("jev-latest")

        do {
            _ = try await model.doEvaluate(typesafeOptions())
            Issue.record("Expected an API call error.")
        } catch let error as AIError {
            let apiError = try #require(error.apiCallError)
            #expect(apiError.provider == "typesafe.evaluation")
            #expect(apiError.statusCode == status)
            #expect(apiError.responseBody == "Provider error")
            #expect(apiError.responseHeaders["x-request-id"] == "failed")
            #expect(apiError.isRetryable == (status == 429 || status == 529))
            #expect(apiError.url == "https://api.typesafe.ai/v1/systemone")
            #expect(apiError.requestBody?["model"] == "jev-latest")
        }
    }

    @Test func mapsProviderErrorEnvelopePrecedence() async throws {
        let cases: [(String, String)] = [
            (#"{"detail":[{"loc":["body","questions"],"msg":"Invalid question"}]}"#, #"[{"loc":["body","questions"],"msg":"Invalid question"}]"#),
            (#"{"error":{"message":"Nested error"}}"#, "Nested error"),
            (#"{"error":"String error"}"#, "String error"),
            (#"{"message":"Prose error","error_type":"max_tokens_exceeded"}"#, "Prose error"),
            (#"{"detail":null,"error_type":"max_tokens_exceeded"}"#, "null"),
            (#"{"error_type":"max_tokens_exceeded"}"#, "max_tokens_exceeded"),
            (#"{"unrecognised":"shape"}"#, "TypeSafe request failed")
        ]

        for (body, expectedMessage) in cases {
            let transport = RecordingTransport(response: AIHTTPResponse(
                statusCode: 422,
                headers: ["content-type": "application/json"],
                body: Data(body.utf8)
            ))
            let model = try createTypeSafeAI(settings: ProviderSettings(
                apiKey: "key",
                transport: transport
            )).evaluationModel("jev-latest")
            do {
                _ = try await model.doEvaluate(typesafeOptions())
                Issue.record("Expected an API call error for \(body).")
            } catch let error as AIError {
                #expect(error.apiCallError?.responseBody == expectedMessage)
            }
        }
    }

    @Test func rejectsMalformedSuccessfulResponsesAsAPICallErrors() async throws {
        let malformedBodies = [
            #"{"answers":{"test":{"type":"noul"}}}"#,
            #"{"answers":{"test":{"type":"choice","choice":"a"}}}"#,
            #"{"answers":{"test":{"type":"unknown"}}}"#,
            #"{"answers":[],"usage":null}"#
        ]

        for body in malformedBodies {
            let transport = RecordingTransport(response: jsonResponse(body))
            let model = try createTypeSafeAI(settings: ProviderSettings(
                apiKey: "key",
                transport: transport
            )).evaluationModel("jev-latest")
            do {
                _ = try await model.doEvaluate(typesafeOptions())
                Issue.record("Expected malformed response failure for \(body).")
            } catch let error as AIError {
                let apiError = try #require(error.apiCallError)
                #expect(apiError.statusCode == 200)
                #expect(!apiError.isRetryable)
            }
        }
    }

    @Test func acceptsNullOptionalMetadataWithoutInventingConfidence() async throws {
        let transport = RecordingTransport(response: jsonResponse("""
        {
          "model": null,
          "usage": null,
          "answers": {
            "topic": {
              "type": "choice",
              "choice": "a",
              "probabilities": {"a": 1},
              "confidence": null
            }
          }
        }
        """))
        let model = try createTypeSafeAI(settings: ProviderSettings(
            apiKey: "key",
            transport: transport
        )).evaluationModel("jev-latest")

        let result = try await model.doEvaluate(typesafeOptions())

        #expect(result.usage == AIEvaluationModelUsage(inputTokens: nil, outputTokens: nil))
        #expect(result.response?.modelID == "jev-latest")
        #expect(result.providerMetadata == ["typesafe": ["confidence": [:]]])
    }
}

private func typesafeOptions() -> AIEvaluationModelV4CallOptions {
    AIEvaluationModelV4CallOptions(
        state: typesafeState(),
        questions: typesafeQuestions()
    )
}

private func typesafeState() -> JSONValue {
    [
        "message": "I was charged twice. Please refund the duplicate.",
        "order": ["amount": 49]
    ]
}

private func typesafeQuestions() -> [String: AIEvaluationQuestion] {
    [
        "department": .choice(
            instructions: ["question": "Which team should handle this?"],
            criteria: [
                "billing": ["includes": ["Charges", "Invoices", "Refunds"]],
                "technical": ["Bugs", "Outages"],
                "other": .null
            ]
        ),
        "severity": .score(
            instructions: ["How severe is the issue?"],
            criteria: [
                ["meaning": "Cosmetic; functionality works"],
                "Functionality impaired; workaround exists",
                "Blocking; no workaround"
            ]
        ),
        "requestsRefund": .boolean(
            instructions: "Is the customer requesting a refund?",
            criteria: [
                "true": ["meaning": "Explicit request for money back"],
                "false": .null
            ]
        )
    ]
}

private func typesafeNativeResponse() -> String {
    """
    {
      "model": "jev-1.13.0",
      "answers": {
        "department": {
          "type": "choice",
          "choice": "billing",
          "confidence": 1.0,
          "probabilities": {"technical": 0.0, "other": 0.0, "billing": 1.0}
        },
        "severity": {
          "type": "score",
          "score": 0.97,
          "confidence": 0.64,
          "legend": {"0": {"meaning": "Cosmetic; functionality works"}},
          "probabilities": {"0": 0.13, "1": 0.76, "2": 0.11}
        },
        "requestsRefund": {"type": "noul", "noul": 0.99}
      },
      "usage": {"input_tokens": 471, "output_tokens": 71}
    }
    """
}
