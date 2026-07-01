import Foundation

func objectRequest(
    from request: LanguageModelRequest,
    schema: JSONValue?,
    schemaName: String?,
    schemaDescription: String?,
    jsonInstruction: AIJSONInstruction?
) -> LanguageModelRequest {
    var output = request
    let responseFormat = AIResponseFormat.json(schema: schema, name: schemaName, description: schemaDescription)
    output.responseFormat = output.responseFormat ?? responseFormat
    if output.extraBody["responseFormat"] == nil {
        output.extraBody["responseFormat"] = responseFormatJSON(schema: schema, name: schemaName, description: schemaDescription)
    }
    if let jsonInstruction, jsonInstruction.isEnabled {
        output.messages = injectJSONInstruction(
            into: output.messages,
            schema: schema,
            instruction: jsonInstruction
        )
    }
    return output
}

func responseFormatJSON(schema: JSONValue?, name: String?, description: String?) -> JSONValue {
    .object([
        "type": .string("json"),
        "schema": schema,
        "name": name.map(JSONValue.string),
        "description": description.map(JSONValue.string)
    ])
}

func injectJSONInstruction(
    into messages: [AIMessage],
    schema: JSONValue?,
    instruction: AIJSONInstruction
) -> [AIMessage] {
    let existingSystemText: String?
    let tail: ArraySlice<AIMessage>
    if let first = messages.first, first.role == .system {
        existingSystemText = first.combinedText
        tail = messages.dropFirst()
    } else {
        existingSystemText = nil
        tail = messages[...]
    }

    let injected = jsonInstructionText(
        prompt: existingSystemText,
        schema: schema,
        instruction: instruction
    )
    return [AIMessage.system(injected)] + Array(tail)
}

func jsonInstructionText(
    prompt: String?,
    schema: JSONValue?,
    instruction: AIJSONInstruction
) -> String {
    let schemaPrefix = instruction.schemaPrefix ?? (schema == nil ? nil : "JSON schema:")
    let schemaSuffix = instruction.schemaSuffix ?? (schema == nil
        ? "You MUST answer with JSON."
        : "You MUST answer with a JSON object that matches the JSON schema above.")
    let promptValue = prompt?.isEmpty == false ? prompt : nil
    let schemaText = schema.flatMap(canonicalJSONText)

    return [
        promptValue,
        promptValue == nil ? nil : "",
        schemaPrefix,
        schemaText,
        schemaSuffix
    ]
    .compactMap { $0 }
    .joined(separator: "\n")
}

struct AIObjectArrayEnvelope<Element: Decodable & Sendable>: Decodable, Sendable {
    var elements: [Element]
}

struct AIEnumEnvelope: Decodable, Sendable {
    var result: String
}

func arrayStreamPart<Element: Decodable & Sendable>(
    _ part: ObjectStreamPart<AIObjectArrayEnvelope<Element>>
) -> ObjectStreamPart<[Element]> {
    switch part {
    case let .textDelta(delta):
        return .textDelta(delta)
    case let .partialObject(partial):
        return .partialObject(partial["elements"] ?? partial)
    case let .partial(envelope):
        return .partial(envelope.elements)
    case let .object(result):
        return .object(arrayObjectResult(from: result))
    case let .warning(warning):
        return .warning(warning)
    case let .source(source):
        return .source(source)
    case let .metadata(metadata):
        return .metadata(metadata)
    case let .responseMetadata(metadata):
        return .responseMetadata(metadata)
    case let .raw(raw):
        return .raw(raw)
    case let .finish(reason, usage):
        return .finish(reason: reason, usage: usage)
    }
}

func enumStreamPart(_ part: ObjectStreamPart<AIEnumEnvelope>, values: [String]) -> ObjectStreamPart<String> {
    switch part {
    case let .textDelta(delta):
        return .textDelta(delta)
    case let .partialObject(partial):
        guard let value = partial["result"]?.stringValue else {
            return .partialObject(partial)
        }
        guard let resolved = enumPartialObjectValue(value, values: values) else {
            return .raw(.raw(["result": .string(value)]))
        }
        return .partialObject(.string(resolved))
    case let .partial(envelope):
        guard let resolved = resolvedEnumPartial(envelope.result, values: values) else {
            return .raw(.raw(["result": .string(envelope.result)]))
        }
        return .partial(resolved)
    case let .object(result):
        return .object(enumObjectResult(from: result))
    case let .warning(warning):
        return .warning(warning)
    case let .source(source):
        return .source(source)
    case let .metadata(metadata):
        return .metadata(metadata)
    case let .responseMetadata(metadata):
        return .responseMetadata(metadata)
    case let .raw(raw):
        return .raw(raw)
    case let .finish(reason, usage):
        return .finish(reason: reason, usage: usage)
    }
}

func resolvedEnumPartial(_ value: String, values: [String]) -> String? {
    if values.contains(value) {
        return value
    }
    let matches = values.filter { $0.hasPrefix(value) }
    return matches.count == 1 ? matches[0] : nil
}

func enumPartialObjectValue(_ value: String, values: [String]) -> String? {
    if values.contains(value) {
        return value
    }
    let matches = values.filter { $0.hasPrefix(value) }
    if matches.isEmpty {
        return nil
    }
    return matches.count == 1 ? matches[0] : value
}

func mapEnumObjectStream(
    _ stream: AsyncThrowingStream<ObjectStreamPart<AIEnumEnvelope>, Error>,
    values: [String]
) -> AsyncThrowingStream<ObjectStreamPart<String>, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            var lastPartial: String?
            var lastPartialObject: String?

            do {
                for try await part in stream {
                    try Task.checkCancellation()
                    let transformed = enumStreamPart(part, values: values)
                    if case let .partialObject(partial) = transformed, let value = partial.stringValue {
                        guard value != lastPartialObject else { continue }
                        lastPartialObject = value
                    }
                    if case let .partial(partial) = transformed {
                        guard partial != lastPartial else { continue }
                        lastPartial = partial
                    }
                    continuation.yield(transformed)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}

func mapArrayObjectStream<Element: Decodable & Sendable>(
    _ stream: AsyncThrowingStream<ObjectStreamPart<AIObjectArrayEnvelope<Element>>, Error>
) -> AsyncThrowingStream<ObjectStreamPart<[Element]>, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            var text = ""
            var lastPartialObject: JSONValue?
            var lastPartialElementCount: Int?

            func yieldPartial(_ elements: [Element]) {
                guard elements.count != lastPartialElementCount else {
                    return
                }
                lastPartialElementCount = elements.count
                continuation.yield(.partial(elements))
            }

            func yieldPartialIfAvailable() {
                guard let partial = arrayPartialElements(from: text),
                      partial != lastPartialObject else {
                    return
                }
                lastPartialObject = partial
                continuation.yield(.partialObject(partial))
                if let typedPartial = typedPartialArray(Element.self, from: partial) {
                    yieldPartial(typedPartial)
                }
            }

            do {
                for try await part in stream {
                    try Task.checkCancellation()
                    switch part {
                    case let .textDelta(delta):
                        text += delta
                        continuation.yield(.textDelta(delta))
                        yieldPartialIfAvailable()
                    case .partialObject:
                        yieldPartialIfAvailable()
                    case let .partial(envelope):
                        yieldPartial(envelope.elements)
                    default:
                        continuation.yield(arrayStreamPart(part))
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}

func arrayObjectResult<Element: Decodable & Sendable>(
    from result: ObjectGenerationResult<AIObjectArrayEnvelope<Element>>
) -> ObjectGenerationResult<[Element]> {
    let rawArray = result.rawObject["elements"] ?? .array([JSONValue]())
    let text = canonicalJSONText(rawArray) ?? result.text
    var textResult = result.textResult
    textResult.text = text
    textResult.rawValue = rawArray

    return ObjectGenerationResult(
        object: result.object.elements,
        text: text,
        rawObject: rawArray,
        reasoning: result.reasoning,
        finishReason: result.finishReason,
        usage: result.usage,
        warnings: result.warnings,
        providerMetadata: result.providerMetadata,
        responseMetadata: result.responseMetadata,
        textResult: textResult
    )
}

func enumObjectResult(from result: ObjectGenerationResult<AIEnumEnvelope>) -> ObjectGenerationResult<String> {
    let rawValue = JSONValue.string(result.object.result)
    var textResult = result.textResult
    textResult.text = result.object.result
    textResult.rawValue = rawValue

    return ObjectGenerationResult(
        object: result.object.result,
        text: result.object.result,
        rawObject: rawValue,
        reasoning: result.reasoning,
        finishReason: result.finishReason,
        usage: result.usage,
        warnings: result.warnings,
        providerMetadata: result.providerMetadata,
        responseMetadata: result.responseMetadata,
        textResult: textResult
    )
}

func canonicalJSONText(_ value: JSONValue) -> String? {
    guard let data = try? encodeJSONBody(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

func arrayOutputSchema(elementSchema: JSONValue) -> JSONValue {
    let itemSchema: JSONValue
    if var object = elementSchema.objectValue {
        object.removeValue(forKey: "$schema")
        itemSchema = .object(object)
    } else {
        itemSchema = elementSchema
    }
    return .object([
        "$schema": .string("http://json-schema.org/draft-07/schema#"),
        "type": .string("object"),
        "properties": .object([
            "elements": .object([
                "type": .string("array"),
                "items": itemSchema
            ])
        ]),
        "required": .array([.string("elements")]),
        "additionalProperties": .bool(false)
    ])
}

func enumOutputSchema(values: [String]) -> JSONValue {
    .object([
        "$schema": .string("http://json-schema.org/draft-07/schema#"),
        "type": .string("object"),
        "properties": .object([
            "result": .object([
                "type": .string("string"),
                "enum": .array(values.map(JSONValue.string))
            ])
        ]),
        "required": .array([.string("result")]),
        "additionalProperties": .bool(false)
    ])
}
