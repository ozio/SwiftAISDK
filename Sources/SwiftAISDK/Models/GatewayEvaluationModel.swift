import Foundation

/// Gateway's native Evaluation Model V4 endpoint.
public final class GatewayEvaluationModel: AIEvaluationModelV4, @unchecked Sendable {
    public let specificationVersion = "v4"
    public let supportedQuestionTypes: [AIEvaluationQuestionType] = [.choice, .score, .boolean]
    public let providerID: String
    public let modelID: String

    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func doEvaluate(
        _ options: AIEvaluationModelV4CallOptions
    ) async throws -> AIEvaluationModelV4Result {
        try validateGatewayEvaluationProviderOptions(options.providerOptions)

        var body: [String: JSONValue] = [
            "state": options.state,
            "questions": .object(options.questions.mapValues(gatewayEvaluationQuestion))
        ]
        if !options.providerOptions.isEmpty {
            body["providerOptions"] = .object(options.providerOptions)
        }

        let request = try config.request(
            path: "/evaluation-model",
            modelID: modelID,
            body: .object(body),
            headers: options.headers.mergingHeaders([
                "ai-evaluation-model-specification-version": "4",
                "ai-model-id": modelID
            ]),
            abortSignal: options.abortSignal
        )

        let response: AIHTTPResponse
        do {
            response = try await config.transport.send(request)
        } catch let error as AIAbortError {
            throw error
        } catch let error as GatewayError {
            throw error
        } catch {
            throw GatewayError(
                type: .internalServerError,
                message: String(describing: error),
                statusCode: 500
            )
        }

        guard (200..<300).contains(response.statusCode) else {
            throw gatewayErrorFromHTTPStatus(
                statusCode: response.statusCode,
                body: response.bodyText,
                headers: response.headers
            )
        }

        let raw: JSONValue
        do {
            raw = try response.jsonValue()
        } catch {
            throw gatewayEvaluationResponseError(
                message: "Gateway evaluation response was not valid JSON.",
                response: response
            )
        }

        guard let rawAnswers = raw["answers"]?.objectValue else {
            throw gatewayEvaluationResponseError(
                message: "Gateway evaluation response is missing answers.",
                response: response,
                raw: raw
            )
        }

        let responseModelID: String
        if let returnedModel = raw["model"] {
            guard let returnedModel = returnedModel.stringValue else {
                throw gatewayEvaluationResponseError(
                    message: "Gateway evaluation response model is invalid.",
                    response: response,
                    raw: raw
                )
            }
            responseModelID = returnedModel
        } else {
            responseModelID = modelID
        }

        var answers: [String: AIEvaluationAnswer] = [:]
        answers.reserveCapacity(rawAnswers.count)
        for (questionID, value) in rawAnswers {
            answers[questionID] = try gatewayEvaluationAnswer(
                value,
                questionID: questionID,
                response: response,
                raw: raw
            )
        }

        return AIEvaluationModelV4Result(
            answers: answers,
            rounding: try gatewayEvaluationRounding(raw["rounding"], response: response, raw: raw),
            usage: try gatewayEvaluationUsage(raw["usage"], response: response, raw: raw),
            warnings: try gatewayEvaluationWarnings(raw["warnings"], response: response, raw: raw),
            providerMetadata: try gatewayEvaluationProviderMetadata(
                raw["providerMetadata"] ?? raw["provider_metadata"],
                response: response,
                raw: raw
            ),
            response: AIResponseMetadata(
                modelID: responseModelID,
                headers: response.headers,
                body: raw
            )
        )
    }
}

private let gatewayEvaluationFallbackMaxConditionDepth = 5
private let gatewayEvaluationFallbackMaxConditionsPerList = 20
private let gatewayEvaluationFallbackMaxQuestionLength = 256
private let gatewayEvaluationFallbackMaxModelLength = 256

private func validateGatewayEvaluationProviderOptions(
    _ providerOptions: [String: JSONValue]
) throws {
    guard let value = providerOptions["gateway"] else { return }
    guard let gatewayOptions = value.objectValue else {
        throw gatewayEvaluationProviderOptionsError("Gateway evaluation provider options must be an object.")
    }
    guard let modelsValue = gatewayOptions["models"] else { return }
    guard let models = modelsValue.arrayValue else {
        throw gatewayEvaluationProviderOptionsError("Gateway evaluation models must be an array.")
    }

    var conditionalCount = 0
    for (index, entry) in models.enumerated() {
        if entry.stringValue != nil { continue }
        guard let fallback = entry.objectValue,
              Set(fallback.keys) == Set(["model", "when"]),
              let model = fallback["model"]?.stringValue,
              !model.isEmpty,
              model.utf16.count <= gatewayEvaluationFallbackMaxModelLength,
              let condition = fallback["when"] else {
            throw gatewayEvaluationProviderOptionsError("Gateway conditional model fallbacks are invalid.")
        }
        conditionalCount += 1
        guard conditionalCount == 1 else {
            throw gatewayEvaluationProviderOptionsError("Gateway models support at most one conditional evaluation fallback.")
        }
        guard index == 0 else {
            throw gatewayEvaluationProviderOptionsError("A conditional Gateway evaluation fallback must be the first models entry.")
        }
        try validateGatewayEvaluationFallbackCondition(condition, depth: 1)
    }
}

private func validateGatewayEvaluationFallbackCondition(
    _ value: JSONValue,
    depth: Int
) throws {
    guard let condition = value.objectValue else {
        throw gatewayEvaluationProviderOptionsError("Gateway evaluation fallback conditions must be objects.")
    }

    if Set(condition.keys) == Set(["question", "confidenceBelow"]) {
        try validateGatewayEvaluationQuestionID(condition["question"])
        try validateGatewayEvaluationProbability(
            condition["confidenceBelow"],
            message: "Gateway confidenceBelow must be a finite number from 0 through 1."
        )
        return
    }

    if Set(condition.keys) == Set(["question", "probabilityBetween"]) {
        try validateGatewayEvaluationQuestionID(condition["question"])
        guard let bounds = condition["probabilityBetween"]?.arrayValue,
              bounds.count == 2 else {
            throw gatewayEvaluationProviderOptionsError("Gateway probabilityBetween must contain exactly two probabilities.")
        }
        try validateGatewayEvaluationProbability(
            bounds[0],
            message: "Gateway probabilityBetween values must be finite numbers from 0 through 1."
        )
        try validateGatewayEvaluationProbability(
            bounds[1],
            message: "Gateway probabilityBetween values must be finite numbers from 0 through 1."
        )
        guard let minimum = bounds[0].doubleValue,
              let maximum = bounds[1].doubleValue,
              minimum <= maximum else {
            throw gatewayEvaluationProviderOptionsError("Gateway probabilityBetween minimum must not exceed its maximum.")
        }
        return
    }

    guard depth < gatewayEvaluationFallbackMaxConditionDepth else {
        throw gatewayEvaluationProviderOptionsError(
            "Gateway evaluation fallback conditions can be nested at most \(gatewayEvaluationFallbackMaxConditionDepth) levels deep."
        )
    }

    if Set(condition.keys) == Set(["any"]) {
        try validateGatewayEvaluationConditionList(condition["any"], depth: depth + 1)
        return
    }
    if Set(condition.keys) == Set(["all"]) {
        try validateGatewayEvaluationConditionList(condition["all"], depth: depth + 1)
        return
    }
    if Set(condition.keys) == Set(["atLeast"]),
       let atLeast = condition["atLeast"]?.objectValue,
       Set(atLeast.keys) == Set(["count", "conditions"]),
       let countValue = atLeast["count"]?.doubleValue,
       countValue.isFinite,
       countValue.rounded(.towardZero) == countValue,
       let count = Int(exactly: countValue),
       let conditions = atLeast["conditions"]?.arrayValue,
       count >= 1,
       count <= conditions.count {
        try validateGatewayEvaluationConditionList(.array(conditions), depth: depth + 1)
        return
    }

    throw gatewayEvaluationProviderOptionsError("Gateway evaluation fallback condition is invalid.")
}

private func validateGatewayEvaluationConditionList(
    _ value: JSONValue?,
    depth: Int
) throws {
    guard let conditions = value?.arrayValue,
          !conditions.isEmpty,
          conditions.count <= gatewayEvaluationFallbackMaxConditionsPerList else {
        throw gatewayEvaluationProviderOptionsError(
            "Gateway evaluation condition lists must contain 1 through \(gatewayEvaluationFallbackMaxConditionsPerList) conditions."
        )
    }
    for condition in conditions {
        try validateGatewayEvaluationFallbackCondition(condition, depth: depth)
    }
}

private func validateGatewayEvaluationQuestionID(_ value: JSONValue?) throws {
    guard let question = value?.stringValue,
          !question.isEmpty,
          question.utf16.count <= gatewayEvaluationFallbackMaxQuestionLength else {
        throw gatewayEvaluationProviderOptionsError(
            "Gateway evaluation fallback question IDs must contain 1 through \(gatewayEvaluationFallbackMaxQuestionLength) characters."
        )
    }
}

private func validateGatewayEvaluationProbability(
    _ value: JSONValue?,
    message: String
) throws {
    guard let probability = value?.doubleValue,
          probability.isFinite,
          (0...1).contains(probability) else {
        throw gatewayEvaluationProviderOptionsError(message)
    }
}

private func gatewayEvaluationProviderOptionsError(_ message: String) -> AIError {
    .invalidArgument(argument: "providerOptions.gateway.models", message: message)
}

private func gatewayEvaluationQuestion(_ question: AIEvaluationQuestion) -> JSONValue {
    switch question {
    case let .choice(instructions, criteria):
        return .object([
            "type": .string("choice"),
            "instructions": instructions,
            "criteria": .object(criteria)
        ])
    case let .score(instructions, criteria):
        return .object([
            "type": .string("score"),
            "instructions": instructions,
            "criteria": .array(criteria)
        ])
    case let .boolean(instructions, criteria):
        return .object([
            "type": .string("boolean"),
            "instructions": instructions,
            "criteria": criteria.map(JSONValue.object)
        ])
    }
}

private func gatewayEvaluationAnswer(
    _ value: JSONValue,
    questionID: String,
    response: AIHTTPResponse,
    raw: JSONValue
) throws -> AIEvaluationAnswer {
    guard let object = value.objectValue, let type = object["type"]?.stringValue else {
        throw gatewayEvaluationResponseError(
            message: "Gateway evaluation answer \"\(questionID)\" is invalid.",
            response: response,
            raw: raw
        )
    }
    switch type {
    case "choice":
        guard let choice = object["choice"]?.stringValue else {
            throw gatewayEvaluationResponseError(
                message: "Gateway evaluation choice answer \"\(questionID)\" is missing choice.",
                response: response,
                raw: raw
            )
        }
        return .choice(
            choice: choice,
            probabilities: try gatewayEvaluationProbabilities(
                object["probabilities"],
                questionID: questionID,
                response: response,
                raw: raw
            )
        )
    case "score":
        guard let score = object["score"]?.doubleValue, score.isFinite else {
            throw gatewayEvaluationResponseError(
                message: "Gateway evaluation score answer \"\(questionID)\" is missing a finite score.",
                response: response,
                raw: raw
            )
        }
        return .score(
            score: score,
            probabilities: try gatewayEvaluationProbabilities(
                object["probabilities"],
                questionID: questionID,
                response: response,
                raw: raw
            )
        )
    case "boolean":
        guard let probability = object["probability"]?.doubleValue,
              probability.isFinite else {
            throw gatewayEvaluationResponseError(
                message: "Gateway evaluation boolean answer \"\(questionID)\" is missing a finite probability.",
                response: response,
                raw: raw
            )
        }
        return .boolean(probability: probability)
    default:
        throw gatewayEvaluationResponseError(
            message: "Gateway evaluation answer \"\(questionID)\" has unknown type \"\(type)\".",
            response: response,
            raw: raw
        )
    }
}

private func gatewayEvaluationProbabilities(
    _ value: JSONValue?,
    questionID: String,
    response: AIHTTPResponse,
    raw: JSONValue
) throws -> [String: Double]? {
    guard let value else { return nil }
    guard let object = value.objectValue else {
        throw gatewayEvaluationResponseError(
            message: "Gateway evaluation answer \"\(questionID)\" has invalid probabilities.",
            response: response,
            raw: raw
        )
    }
    var result: [String: Double] = [:]
    for (key, item) in object {
        guard let number = item.doubleValue, number.isFinite else {
            throw gatewayEvaluationResponseError(
                message: "Gateway evaluation answer \"\(questionID)\" has invalid probabilities.",
                response: response,
                raw: raw
            )
        }
        result[key] = number
    }
    return result
}

private func gatewayEvaluationRounding(
    _ value: JSONValue?,
    response: AIHTTPResponse,
    raw: JSONValue
) throws -> AIEvaluationRounding? {
    guard let value else { return nil }
    guard let object = value.objectValue else {
        throw gatewayEvaluationResponseError(message: "Gateway evaluation rounding is invalid.", response: response, raw: raw)
    }
    return AIEvaluationRounding(
        probabilityDecimals: try gatewayEvaluationInteger(
            object["probabilityDecimals"],
            field: "rounding.probabilityDecimals",
            response: response,
            raw: raw
        ),
        scoreDecimals: try gatewayEvaluationInteger(
            object["scoreDecimals"],
            field: "rounding.scoreDecimals",
            response: response,
            raw: raw
        )
    )
}

private func gatewayEvaluationUsage(
    _ value: JSONValue?,
    response: AIHTTPResponse,
    raw: JSONValue
) throws -> AIEvaluationModelUsage? {
    guard let value else { return nil }
    guard let object = value.objectValue else {
        throw gatewayEvaluationResponseError(message: "Gateway evaluation usage is invalid.", response: response, raw: raw)
    }
    return AIEvaluationModelUsage(
        inputTokens: try gatewayEvaluationInteger(
            object["inputTokens"],
            field: "usage.inputTokens",
            response: response,
            raw: raw
        ),
        outputTokens: try gatewayEvaluationInteger(
            object["outputTokens"],
            field: "usage.outputTokens",
            response: response,
            raw: raw
        )
    )
}

private func gatewayEvaluationInteger(
    _ value: JSONValue?,
    field: String,
    response: AIHTTPResponse,
    raw: JSONValue
) throws -> Int? {
    guard let value else { return nil }
    guard let number = value.doubleValue,
          number.isFinite,
          number.rounded(.towardZero) == number,
          let integer = Int(exactly: number) else {
        throw gatewayEvaluationResponseError(
            message: "Gateway evaluation \(field) must be an integer.",
            response: response,
            raw: raw
        )
    }
    return integer
}

private func gatewayEvaluationWarnings(
    _ value: JSONValue?,
    response: AIHTTPResponse,
    raw: JSONValue
) throws -> [AIWarning] {
    guard let value else { return [] }
    guard let values = value.arrayValue else {
        throw gatewayEvaluationResponseError(message: "Gateway evaluation warnings are invalid.", response: response, raw: raw)
    }
    return try values.map { warning in
        guard let object = warning.objectValue,
              let type = object["type"]?.stringValue else {
            throw gatewayEvaluationResponseError(message: "Gateway evaluation warning is invalid.", response: response, raw: raw)
        }
        switch type {
        case "unsupported", "compatibility":
            guard let feature = object["feature"]?.stringValue else {
                throw gatewayEvaluationResponseError(message: "Gateway evaluation warning is missing feature.", response: response, raw: raw)
            }
            return AIWarning(
                type: type,
                feature: feature,
                message: object["details"]?.stringValue
            )
        case "deprecated":
            guard let setting = object["setting"]?.stringValue,
                  let message = object["message"]?.stringValue else {
                throw gatewayEvaluationResponseError(message: "Gateway evaluation deprecation warning is invalid.", response: response, raw: raw)
            }
            return AIWarning(type: type, setting: setting, message: message)
        case "other":
            guard let message = object["message"]?.stringValue else {
                throw gatewayEvaluationResponseError(message: "Gateway evaluation warning is missing message.", response: response, raw: raw)
            }
            return AIWarning(type: type, message: message)
        default:
            throw gatewayEvaluationResponseError(message: "Gateway evaluation warning has unknown type \"\(type)\".", response: response, raw: raw)
        }
    }
}

private func gatewayEvaluationProviderMetadata(
    _ value: JSONValue?,
    response: AIHTTPResponse,
    raw: JSONValue
) throws -> [String: JSONValue] {
    guard let value else { return [:] }
    guard let metadata = value.objectValue,
          metadata.values.allSatisfy({ $0.objectValue != nil }) else {
        throw gatewayEvaluationResponseError(message: "Gateway evaluation provider metadata is invalid.", response: response, raw: raw)
    }
    return metadata
}

private func gatewayEvaluationResponseError(
    message: String,
    response: AIHTTPResponse,
    raw: JSONValue? = nil
) -> GatewayError {
    GatewayError(
        type: .responseError,
        message: message,
        statusCode: response.statusCode,
        response: raw,
        headers: response.headers,
        cause: AIAPICallError(
            provider: "gateway",
            statusCode: response.statusCode,
            responseHeaders: response.headers,
            responseBody: response.bodyText
        )
    )
}
