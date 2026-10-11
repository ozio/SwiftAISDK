import Foundation

/// OpenAI's native Decisions API, including distributions, refusals and image evidence.
public final class OpenAIDecisionModel: AIDecisionModelV4, AIEvaluationModelV4, @unchecked Sendable {
    public let specificationVersion = "v4"
    public let supportedQuestionTypes: [AIDecisionQuestionType] = [.choice, .score, .boolean]
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.providerID = config.providerID
        self.config = config
    }

    public func doDecide(_ options: AIDecisionModelV4CallOptions) async throws -> AIDecisionModelV4Result {
        let providerOptions: [String: JSONValue]
        if let value = options.providerOptions["openai"] {
            guard let object = value.objectValue else {
                throw AIError.invalidArgument(argument: "providerOptions.openai", message: "must be an object")
            }
            providerOptions = object
        } else {
            providerOptions = [:]
        }
        let safetyIdentifier: String?
        if let value = providerOptions["safetyIdentifier"] {
            guard let text = value.stringValue, text.utf16.count <= 128 else {
                throw AIError.invalidArgument(argument: "providerOptions.openai.safetyIdentifier", message: "must be a string containing at most 128 characters")
            }
            safetyIdentifier = text
        } else {
            safetyIdentifier = nil
        }
        let body: JSONValue = .object([
            "model": .string(modelID),
            "safety_identifier": safetyIdentifier.map(JSONValue.string),
            "input": .array([.object([
                "role": .string("user"),
                "content": .array(try options.state.map(openAIDecisionContent))
            ])]),
            "questions": .array(try options.questions.sorted { $0.key < $1.key }.map { name, question in
                try openAIDecisionQuestion(name: name, question: question)
            })
        ])
        let result: (json: JSONValue, response: AIHTTPResponse)
        do {
            result = try await config.sendJSONResponse(
                path: "/decisions",
                modelID: modelID,
                body: body,
                headers: options.headers,
                abortSignal: options.abortSignal
            )
        } catch is DecodingError {
            throw invalid("Decisions response was not valid JSON.")
        }
        let raw = result.json
        guard let values = raw["answers"]?.arrayValue else {
            throw invalid("Decisions response must contain an answer array.")
        }
        var answers: [String: AIDecisionAnswer] = [:]
        var confidence: [String: JSONValue] = [:]
        for value in values {
            guard let type = value["type"]?.stringValue else {
                throw invalid("Decisions returned an invalid answer.")
            }
            if type == "refusal", value["name"] == .null {
                throw invalid("OpenAI Decisions refused an unnamed question.")
            }
            guard let name = value["name"]?.stringValue,
                  options.questions[name] != nil,
                  answers[name] == nil else {
                throw invalid("Decisions must return exactly one answer for every question.")
            }
            switch type {
            case "refusal": answers[name] = .refusal
            case "predicate":
                answers[name] = .boolean(probability: try probability(value["probability"], field: "probability"))
            case "choice", "score":
                guard let distribution = value["probabilities"]?.arrayValue else {
                    throw invalid("Decisions returned an invalid probability distribution.")
                }
                var probabilities: [String: Double] = [:]
                for entry in distribution {
                    let key: String
                    if type == "choice" {
                        guard let text = entry["value"]?.stringValue else {
                            throw invalid("Decisions choice probability values must be strings.")
                        }
                        key = text
                    } else {
                        guard let number = entry["value"]?.doubleValue,
                              number.isFinite,
                              number >= 0,
                              let integer = Int(exactly: number) else {
                            throw invalid("Decisions score probability values must be nonnegative integers.")
                        }
                        key = String(integer)
                    }
                    guard probabilities[key] == nil else {
                        throw invalid("Decisions returned duplicate probability values.")
                    }
                    probabilities[key] = try probability(entry["probability"], field: "probabilities")
                }
                if type == "choice" {
                    guard let choice = value["choice"]?.stringValue else {
                        throw invalid("Decisions choice answer is missing choice.")
                    }
                    answers[name] = .choice(choice: choice, probabilities: probabilities)
                } else {
                    guard let score = value["score"]?.doubleValue, score.isFinite else {
                        throw invalid("Decisions score answer is missing a finite score.")
                    }
                    answers[name] = .score(score: score, probabilities: probabilities)
                }
                if let rawConfidence = value["confidence"], rawConfidence != .null {
                    confidence[name] = .number(try probability(rawConfidence, field: "confidence"))
                }
            default: throw invalid("Decisions returned unknown answer type '\(type)'.")
            }
        }
        guard answers.count == options.questions.count else {
            throw invalid("Decisions must return exactly one answer for every question.")
        }
        let returnedModel: String?
        if let value = raw["model"], value != .null {
            guard let text = value.stringValue else { throw invalid("Decisions model must be a string or null.") }
            returnedModel = text
        } else {
            returnedModel = nil
        }
        let usage: AIDecisionModelUsage?
        var metadata: [String: JSONValue] = ["confidence": .object(confidence)]
        if let rawUsage = raw["usage"], rawUsage != .null {
            guard let object = rawUsage.objectValue else { throw invalid("Decisions usage must be an object or null.") }
            usage = AIDecisionModelUsage(
                inputTokens: try tokenCount(object["input_tokens"], field: "input_tokens"),
                outputTokens: try tokenCount(object["output_tokens"], field: "output_tokens")
            )
            _ = try tokenCount(object["total_tokens"], field: "total_tokens")
            for (key, fields) in [
                ("input_tokens_details", ["cached_tokens", "cache_write_tokens"]),
                ("output_tokens_details", ["reasoning_tokens"])
            ] {
                if let detail = object[key], detail != .null {
                    guard let details = detail.objectValue else { throw invalid("Decisions \(key) must be an object or null.") }
                    for field in fields { _ = try tokenCount(details[field], field: field) }
                }
            }
            metadata["usage"] = rawUsage
        } else {
            usage = nil
        }
        return AIDecisionModelV4Result(
            answers: answers,
            rounding: AIDecisionRounding(probabilityDecimals: 2, scoreDecimals: 2),
            usage: usage,
            warnings: providerOptions.keys.sorted().filter { $0 != "safetyIdentifier" }.map {
                AIWarning(type: "unsupported", feature: "providerOptions.openai.\($0)")
            },
            providerMetadata: ["openai": .object(metadata)],
            response: AIResponseMetadata(modelID: returnedModel ?? modelID, headers: result.response.headers, body: raw)
        )
    }

    private func invalid(_ message: String) -> AIError { .invalidResponse(provider: providerID, message: message) }

    private func probability(_ value: JSONValue?, field: String) throws -> Double {
        guard let number = value?.doubleValue, number.isFinite, (0...1).contains(number) else {
            throw invalid("Decisions \(field) must be a finite probability in [0, 1].")
        }
        return number
    }

    private func tokenCount(_ value: JSONValue?, field: String) throws -> Int? {
        guard let value, value != .null else { return nil }
        guard let number = value.doubleValue, number.isFinite, let integer = Int(exactly: number) else {
            throw invalid("Decisions \(field) must be an integer or null.")
        }
        return integer
    }
}

private func openAIDecisionContent(_ part: AIDecisionStatePart) throws -> JSONValue {
    switch part {
    case let .text(text): return .object(["type": .string("input_text"), "text": .string(text)])
    case let .json(value): return .object(["type": .string("input_text"), "text": .string(try decisionJSONText(value))])
    case let .file(mediaType, data, _, providerOptions):
        let base64: String
        let detected: String?
        switch data {
        case let .data(bytes):
            base64 = bytes.base64EncodedString()
            detected = detectMediaType(data: bytes, topLevelType: "image")
        case let .base64(value):
            base64 = value
            detected = detectMediaType(base64: value, topLevelType: "image")
        case .url, .reference:
            throw AIDecisionUnsupportedFunctionalityError(functionality: "OpenAI decision file input requires inline data")
        }
        let resolvedMediaType = isFullMediaType(mediaType) ? mediaType : detected
        guard let resolvedMediaType, ["image/png", "image/jpeg", "image/webp", "image/gif"].contains(resolvedMediaType) else {
            throw AIDecisionUnsupportedFunctionalityError(functionality: "OpenAI decision image media type: \(mediaType)")
        }
        return .object([
            "type": .string("input_image"),
            "image_url": .string("data:\(resolvedMediaType);base64,\(base64)"),
            "detail": providerOptions["openai"]?["imageDetail"].flatMap { $0 == .null ? nil : $0 }
        ])
    }
}

private func openAIDecisionQuestion(name: String, question: AIDecisionQuestion) throws -> JSONValue {
    let instructions = try decisionInputText(question.instructions)
    switch question {
    case let .boolean(_, criteria):
        var text = [instructions]
        for key in ["true", "false"] {
            if let value = criteria?[key], value != .null {
                text.append("Criteria for \(key):\n\(try decisionInputText(value))")
            }
        }
        return .object(["type": .string("predicate"), "name": .string(name), "instructions": .string(text.joined(separator: "\n\n"))])
    case let .choice(_, criteria):
        return .object([
            "type": .string("choice"), "name": .string(name), "instructions": .string(instructions),
            "choices": .array(try criteria.keys.sorted().map { key in
                .object(["value": .string(key), "description": try criteria[key].flatMap { value in value == .null ? nil : .string(try decisionInputText(value)) }])
            })
        ])
    case let .score(_, criteria):
        return .object([
            "type": .string("score"), "name": .string(name), "instructions": .string(instructions),
            "levels": .array(try criteria.enumerated().map { index, value in
                var level: [String: JSONValue] = ["label": .string(String(index))]
                if value != .null { level["description"] = .string(try decisionInputText(value)) }
                return .object(level)
            })
        ])
    }
}

private func decisionInputText(_ value: JSONValue) throws -> String {
    if let text = value.stringValue { return text }
    return try decisionJSONText(value)
}

public extension OpenAIDecisionModel {
    /// Compatibility alias for the published Evaluation-to-Decision rename.
    func doEvaluate(_ options: AIDecisionModelV4CallOptions) async throws -> AIDecisionModelV4Result {
        try await doDecide(options)
    }
}

public extension OpenAIDecisionModel {
    /// Retains the original Evaluation call options while using native Decisions.
    func doEvaluate(_ options: AIEvaluationModelV4CallOptions) async throws -> AIEvaluationModelV4Result {
        let result = try await doDecide(options.decisionOptions)
        return try evaluationResult(from: result, providerID: providerID, modelID: modelID)
    }
}
