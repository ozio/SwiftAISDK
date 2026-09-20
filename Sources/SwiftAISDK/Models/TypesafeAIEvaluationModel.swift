import Foundation

struct TypeSafeAIEvaluationModelConfiguration: @unchecked Sendable {
    var providerID: String
    var baseURL: String
    var apiKey: String?
    var headers: [String: String]
    var environment: [String: String]?
    var transport: any AITransport

    func resolvedAPIKey() throws -> String {
        if let apiKey {
            return apiKey
        }
        let environmentKey: String?
        if let environment {
            environmentKey = environment["TYPESAFE_AI_API_KEY"]
        } else {
            environmentKey = environmentValue(["TYPESAFE_AI_API_KEY"])
        }
        guard let environmentKey else {
            throw AIError.missingAPIKey(
                provider: "typesafe",
                environmentVariables: ["TYPESAFE_AI_API_KEY"]
            )
        }
        return environmentKey
    }
}

/// TypeSafe System One's native Evaluation Model V4 implementation.
public final class TypeSafeAIEvaluationModel: AIEvaluationModelV4, @unchecked Sendable {
    public let specificationVersion = "v4"
    public let supportedQuestionTypes: [AIEvaluationQuestionType] = [.choice, .score, .boolean]
    public let providerID: String
    public let modelID: String

    private let configuration: TypeSafeAIEvaluationModelConfiguration

    init(modelID: String, configuration: TypeSafeAIEvaluationModelConfiguration) {
        self.modelID = modelID
        self.providerID = configuration.providerID
        self.configuration = configuration
    }

    public func doEvaluate(
        _ options: AIEvaluationModelV4CallOptions
    ) async throws -> AIEvaluationModelV4Result {
        try validateTypesafeLimits(options.questions)

        let providerOptions = options.providerOptions["typesafe"]?.objectValue ?? [:]
        let warnings = providerOptions.keys.sorted().map {
            AIWarning(type: "unsupported", feature: "providerOptions.typesafe.\($0)")
        }

        let body: JSONValue = .object([
            "model": .string(modelID),
            "state": options.state,
            "questions": .object(options.questions.mapValues(typesafeQuestion))
        ])

        let apiKey = try configuration.resolvedAPIKey()
        var modelHeaders = normalizeHeaders(configuration.headers)
        modelHeaders["authorization"] = modelHeaders["authorization"] ?? "Bearer \(apiKey)"
        modelHeaders = withUserAgentSuffix(
            modelHeaders,
            "ai-sdk/typesafe-ai/\(typeSafeAIProviderVersion)"
        )
        let headers = combineHeaders(modelHeaders, normalizeHeaders(options.headers))
        let request = AIHTTPRequest(
            method: "POST",
            url: try requireURL("\(configuration.baseURL)/systemone"),
            headers: headers.mergingHeaders([
                "content-type": headers["content-type"] ?? "application/json"
            ]),
            body: try encodeJSONBody(body),
            abortSignal: options.abortSignal
        )

        let response = try await configuration.transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw typesafeHTTPError(request: request, requestBody: body, response: response)
        }

        let raw: JSONValue
        do {
            raw = try response.jsonValue()
        } catch {
            throw typesafeInvalidResponse(
                request: request,
                requestBody: body,
                response: response,
                message: "TypeSafe AI evaluation response was not valid JSON."
            )
        }

        let parsed: TypeSafeParsedEvaluationResponse
        do {
            parsed = try parseTypesafeResponse(raw)
        } catch let error as TypeSafeResponseValidationError {
            throw typesafeInvalidResponse(
                request: request,
                requestBody: body,
                response: response,
                message: error.message
            )
        }

        return AIEvaluationModelV4Result(
            answers: parsed.answers,
            rounding: AIEvaluationRounding(probabilityDecimals: 2, scoreDecimals: 2),
            usage: parsed.usage,
            warnings: warnings,
            providerMetadata: [
                "typesafe": .object([
                    "confidence": .object(parsed.confidence.mapValues(JSONValue.number))
                ])
            ],
            response: AIResponseMetadata(
                modelID: parsed.modelID ?? modelID,
                headers: response.headers,
                body: raw
            )
        )
    }
}

private struct TypeSafeParsedEvaluationResponse {
    var modelID: String?
    var answers: [String: AIEvaluationAnswer]
    var confidence: [String: Double]
    var usage: AIEvaluationModelUsage
}

private struct TypeSafeResponseValidationError: Error {
    var message: String
}

private func validateTypesafeLimits(
    _ questions: [String: AIEvaluationQuestion]
) throws {
    for (id, question) in questions {
        switch question {
        case let .choice(_, criteria) where criteria.count > 255:
            throw AIError.invalidArgument(
                argument: "questions.\(id).criteria",
                message: "TypeSafe Choice questions support at most 255 options."
            )
        case let .score(_, criteria) where criteria.count > 10:
            throw AIError.invalidArgument(
                argument: "questions.\(id).criteria",
                message: "TypeSafe Score questions support at most 10 levels."
            )
        default:
            continue
        }
    }
}

private func typesafeQuestion(_ question: AIEvaluationQuestion) -> JSONValue {
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
            "type": .string("noul"),
            "instructions": instructions,
            "criteria": criteria.map(JSONValue.object)
        ])
    }
}

private func parseTypesafeResponse(
    _ raw: JSONValue
) throws -> TypeSafeParsedEvaluationResponse {
    guard let object = raw.objectValue else {
        throw TypeSafeResponseValidationError(message: "TypeSafe AI evaluation response must be an object.")
    }

    let modelID: String?
    switch object["model"] {
    case nil, .some(.null):
        modelID = nil
    case let .some(.string(value)):
        modelID = value
    default:
        throw TypeSafeResponseValidationError(message: "TypeSafe AI evaluation response model must be a string or null.")
    }

    guard let rawAnswers = object["answers"]?.objectValue else {
        throw TypeSafeResponseValidationError(message: "TypeSafe AI evaluation response is missing answers.")
    }

    var answers: [String: AIEvaluationAnswer] = [:]
    var confidence: [String: Double] = [:]
    answers.reserveCapacity(rawAnswers.count)

    for (id, rawAnswer) in rawAnswers {
        guard let answer = rawAnswer.objectValue,
              let type = answer["type"]?.stringValue else {
            throw TypeSafeResponseValidationError(message: "TypeSafe AI answer \"\(id)\" is invalid.")
        }
        switch type {
        case "choice":
            guard let choice = answer["choice"]?.stringValue else {
                throw TypeSafeResponseValidationError(message: "TypeSafe AI choice answer \"\(id)\" is missing choice.")
            }
            answers[id] = .choice(
                choice: choice,
                probabilities: try typesafeProbabilities(answer["probabilities"], answerID: id)
            )
            if let value = try typesafeOptionalNumber(answer["confidence"], field: "answers.\(id).confidence") {
                confidence[id] = value
            }
        case "score":
            guard let score = typesafeFiniteNumber(answer["score"]) else {
                throw TypeSafeResponseValidationError(message: "TypeSafe AI score answer \"\(id)\" is missing score.")
            }
            answers[id] = .score(
                score: score,
                probabilities: try typesafeProbabilities(answer["probabilities"], answerID: id)
            )
            if let value = try typesafeOptionalNumber(answer["confidence"], field: "answers.\(id).confidence") {
                confidence[id] = value
            }
        case "noul":
            guard let probability = typesafeFiniteNumber(answer["noul"]) else {
                throw TypeSafeResponseValidationError(message: "TypeSafe AI noul answer \"\(id)\" is missing noul.")
            }
            answers[id] = .boolean(probability: probability)
        default:
            throw TypeSafeResponseValidationError(
                message: "TypeSafe AI answer \"\(id)\" has unknown type \"\(type)\"."
            )
        }
    }

    let usage = try typesafeUsage(object["usage"])
    return TypeSafeParsedEvaluationResponse(
        modelID: modelID,
        answers: answers,
        confidence: confidence,
        usage: usage
    )
}

private func typesafeProbabilities(
    _ value: JSONValue?,
    answerID: String
) throws -> [String: Double] {
    guard let object = value?.objectValue else {
        throw TypeSafeResponseValidationError(
            message: "TypeSafe AI answer \"\(answerID)\" is missing probabilities."
        )
    }
    var probabilities: [String: Double] = [:]
    probabilities.reserveCapacity(object.count)
    for (key, rawProbability) in object {
        guard let probability = typesafeFiniteNumber(rawProbability) else {
            throw TypeSafeResponseValidationError(
                message: "TypeSafe AI answer \"\(answerID)\" has invalid probabilities."
            )
        }
        probabilities[key] = probability
    }
    return probabilities
}

private func typesafeOptionalNumber(
    _ value: JSONValue?,
    field: String
) throws -> Double? {
    switch value {
    case nil, .some(.null):
        return nil
    default:
        guard let number = typesafeFiniteNumber(value) else {
            throw TypeSafeResponseValidationError(message: "TypeSafe AI \(field) must be a number or null.")
        }
        return number
    }
}

private func typesafeFiniteNumber(_ value: JSONValue?) -> Double? {
    guard let number = value?.doubleValue, number.isFinite else { return nil }
    return number
}

private func typesafeUsage(_ value: JSONValue?) throws -> AIEvaluationModelUsage {
    let object: [String: JSONValue]
    switch value {
    case nil, .some(.null):
        object = [:]
    case let .some(.object(fields)):
        object = fields
    default:
        throw TypeSafeResponseValidationError(message: "TypeSafe AI evaluation usage must be an object or null.")
    }
    return AIEvaluationModelUsage(
        inputTokens: try typesafeOptionalTokenCount(object["input_tokens"], field: "usage.input_tokens"),
        outputTokens: try typesafeOptionalTokenCount(object["output_tokens"], field: "usage.output_tokens")
    )
}

private func typesafeOptionalTokenCount(
    _ value: JSONValue?,
    field: String
) throws -> Int? {
    switch value {
    case nil, .some(.null):
        return nil
    default:
        guard let number = typesafeFiniteNumber(value),
              number.rounded(.towardZero) == number,
              let integer = Int(exactly: number) else {
            throw TypeSafeResponseValidationError(message: "TypeSafe AI \(field) must be an integer or null.")
        }
        return integer
    }
}

private func typesafeHTTPError(
    request: AIHTTPRequest,
    requestBody: JSONValue,
    response: AIHTTPResponse
) -> AIError {
    let raw = try? response.jsonValue()
    let message = typesafeErrorMessage(raw) ?? "TypeSafe request failed"
    return .apiCall(AIAPICallError(
        provider: "typesafe.evaluation",
        url: request.url.absoluteString,
        requestBody: requestBody,
        statusCode: response.statusCode,
        responseHeaders: response.headers,
        responseBody: message
    ))
}

private func typesafeErrorMessage(_ raw: JSONValue?) -> String? {
    guard let object = raw?.objectValue else { return nil }
    if let message = object["message"]?.stringValue {
        return message
    }
    if let error = object["error"] {
        if let message = error.stringValue {
            return message
        }
        if let message = error["message"]?.stringValue {
            return message
        }
    }
    if let detail = object["detail"] {
        if let message = detail.stringValue {
            return message
        }
        return getErrorMessage(detail)
    }
    return object["error_type"]?.stringValue
}

private func typesafeInvalidResponse(
    request: AIHTTPRequest,
    requestBody: JSONValue,
    response: AIHTTPResponse,
    message: String
) -> AIError {
    .apiCall(AIAPICallError(
        provider: "typesafe.evaluation",
        url: request.url.absoluteString,
        requestBody: requestBody,
        statusCode: response.statusCode,
        responseHeaders: response.headers,
        responseBody: message,
        isRetryable: false
    ))
}
