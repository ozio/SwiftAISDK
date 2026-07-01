import Foundation

public enum AIOutputKind: String, Equatable, Sendable {
    case text
    case object
    case array
    case choice
    case json
}

public struct AIOutputGenerationResult<Output: Sendable>: Sendable {
    public var output: Output
    public var text: String
    public var rawOutput: JSONValue
    public var reasoning: String
    public var finishReason: String?
    public var usage: TokenUsage?
    public var warnings: [AIWarning]
    public var providerMetadata: [String: JSONValue]
    public var responseMetadata: AIResponseMetadata
    public var textResult: TextGenerationResult

    public init(
        output: Output,
        text: String,
        rawOutput: JSONValue,
        reasoning: String = "",
        finishReason: String? = nil,
        usage: TokenUsage? = nil,
        warnings: [AIWarning] = [],
        providerMetadata: [String: JSONValue] = [:],
        responseMetadata: AIResponseMetadata = AIResponseMetadata(),
        textResult: TextGenerationResult
    ) {
        self.output = output
        self.text = text
        self.rawOutput = rawOutput
        self.reasoning = reasoning
        self.finishReason = finishReason
        self.usage = usage
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.responseMetadata = responseMetadata
        self.textResult = textResult
    }
}

public enum AIOutputStreamPart<Output: Sendable, Partial: Sendable>: Sendable {
    case textDelta(String)
    case partialOutput(Partial)
    case output(AIOutputGenerationResult<Output>)
    case warning(AIWarning)
    case source(AISource)
    case metadata([String: JSONValue])
    case responseMetadata(AIResponseMetadata)
    case raw(LanguageStreamPart)
    case finish(reason: String?, usage: TokenUsage?)
}

public struct AIOutput<FinalOutput: Sendable, PartialOutput: Sendable>: Sendable {
    public var kind: AIOutputKind
    public var schema: JSONValue?
    public var name: String?
    public var description: String?

    internal var generateFromRequest: @Sendable (
        _ model: any LanguageModel,
        _ request: LanguageModelRequest,
        _ retryPolicy: AIRetryPolicy,
        _ telemetry: Telemetry.Options?,
        _ jsonInstruction: AIJSONInstruction?,
        _ repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)?
    ) async throws -> AIOutputGenerationResult<FinalOutput>

    internal var streamFromRequest: @Sendable (
        _ model: any LanguageModel,
        _ request: LanguageModelRequest,
        _ timeoutNanoseconds: UInt64?,
        _ retryPolicy: AIRetryPolicy,
        _ telemetry: Telemetry.Options?,
        _ jsonInstruction: AIJSONInstruction?,
        _ repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)?
    ) -> AsyncThrowingStream<AIOutputStreamPart<FinalOutput, PartialOutput>, Error>

    internal var requestForOutput: @Sendable (
        _ request: LanguageModelRequest,
        _ jsonInstruction: AIJSONInstruction?
    ) -> LanguageModelRequest

    internal var optionalResultFromTextResult: @Sendable (
        _ result: TextGenerationResult,
        _ providerID: String,
        _ repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)?
    ) async throws -> AIOutputGenerationResult<FinalOutput?>

    internal init(
        kind: AIOutputKind,
        schema: JSONValue? = nil,
        name: String? = nil,
        description: String? = nil,
        generateFromRequest: @escaping @Sendable (
            _ model: any LanguageModel,
            _ request: LanguageModelRequest,
            _ retryPolicy: AIRetryPolicy,
            _ telemetry: Telemetry.Options?,
            _ jsonInstruction: AIJSONInstruction?,
            _ repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)?
        ) async throws -> AIOutputGenerationResult<FinalOutput>,
        streamFromRequest: @escaping @Sendable (
            _ model: any LanguageModel,
            _ request: LanguageModelRequest,
            _ timeoutNanoseconds: UInt64?,
            _ retryPolicy: AIRetryPolicy,
            _ telemetry: Telemetry.Options?,
            _ jsonInstruction: AIJSONInstruction?,
            _ repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)?
        ) -> AsyncThrowingStream<AIOutputStreamPart<FinalOutput, PartialOutput>, Error>,
        requestForOutput: @escaping @Sendable (
            _ request: LanguageModelRequest,
            _ jsonInstruction: AIJSONInstruction?
        ) -> LanguageModelRequest,
        optionalResultFromTextResult: @escaping @Sendable (
            _ result: TextGenerationResult,
            _ providerID: String,
            _ repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)?
        ) async throws -> AIOutputGenerationResult<FinalOutput?>
    ) {
        self.kind = kind
        self.schema = schema
        self.name = name
        self.description = description
        self.generateFromRequest = generateFromRequest
        self.streamFromRequest = streamFromRequest
        self.requestForOutput = requestForOutput
        self.optionalResultFromTextResult = optionalResultFromTextResult
    }
}

public enum Output {
    public static func text() -> AIOutput<String, String> {
        AIOutput<String, String>(
            kind: .text,
            generateFromRequest: { model, request, retryPolicy, telemetry, _, _ in
                var request = request
                request.responseFormat = request.responseFormat ?? .text
                return try await AIOutputGenerationResult(
                    textResult: AI.generateText(
                        model: model,
                        request: request,
                        retryPolicy: retryPolicy,
                        telemetry: telemetry
                    )
                )
            },
            streamFromRequest: { model, request, timeoutNanoseconds, retryPolicy, telemetry, _, _ in
                var request = request
                request.responseFormat = request.responseFormat ?? .text
                return mapLanguageStreamToOutputStream(
                    AI.streamText(
                        model: model,
                        request: request,
                        timeoutNanoseconds: timeoutNanoseconds,
                        retryPolicy: retryPolicy,
                        telemetry: telemetry
                    )
                )
            },
            requestForOutput: { request, _ in
                var request = request
                request.responseFormat = request.responseFormat ?? .text
                return request
            },
            optionalResultFromTextResult: { result, _, _ in
                guard shouldParseOutput(from: result) else {
                    return optionalOutputResult(output: nil, rawOutput: .null, textResult: result)
                }
                return optionalOutputResult(output: result.text, rawOutput: .string(result.text), textResult: result)
            }
        )
    }

    public static func object<Object: Decodable & Sendable>(
        schema: JSONValue? = nil,
        name: String? = nil,
        description: String? = nil,
        as type: Object.Type = Object.self
    ) -> AIOutput<Object, JSONValue> {
        AIOutput<Object, JSONValue>(
            kind: .object,
            schema: schema,
            name: name,
            description: description,
            generateFromRequest: { model, request, retryPolicy, telemetry, jsonInstruction, repairText in
                try await AIOutputGenerationResult(
                    objectResult: AI.generateObject(
                        model: model,
                        request: request,
                        as: Object.self,
                        schema: schema,
                        schemaName: name,
                        schemaDescription: description,
                        retryPolicy: retryPolicy,
                        telemetry: telemetry,
                        jsonInstruction: jsonInstruction,
                        repairText: repairText
                    )
                )
            },
            streamFromRequest: { model, request, timeoutNanoseconds, retryPolicy, telemetry, jsonInstruction, repairText in
                mapObjectStreamToOutputStream(
                    AI.streamObject(
                        model: model,
                        request: request,
                        as: Object.self,
                        schema: schema,
                        schemaName: name,
                        schemaDescription: description,
                        timeoutNanoseconds: timeoutNanoseconds,
                        retryPolicy: retryPolicy,
                        telemetry: telemetry,
                        jsonInstruction: jsonInstruction,
                        repairText: repairText
                    ),
                    outputKind: .object
                )
            },
            requestForOutput: { request, jsonInstruction in
                objectRequest(
                    from: request,
                    schema: schema,
                    schemaName: name,
                    schemaDescription: description,
                    jsonInstruction: jsonInstruction
                )
            },
            optionalResultFromTextResult: { result, providerID, repairText in
                guard shouldParseOutput(from: result) else {
                    return optionalOutputResult(output: nil, rawOutput: .null, textResult: result)
                }
                let parsed = try await parseObject(
                    Object.self,
                    from: result.text,
                    schema: schema,
                    repairText: repairText,
                    providerID: providerID
                )
                return optionalOutputResult(
                    output: parsed.object,
                    rawOutput: parsed.rawObject,
                    text: parsed.text,
                    textResult: result
                )
            }
        )
    }

    public static func object<Schema: AIObjectSchema>(
        schema: Schema,
        name: String? = nil,
        description: String? = nil
    ) -> AIOutput<Schema.Output, JSONValue> {
        object(
            schema: schema.jsonSchema,
            name: name ?? schema.name,
            description: description ?? schema.description,
            as: Schema.Output.self
        )
    }

    public static func array<Element: Decodable & Sendable>(
        element: JSONValue,
        name: String? = nil,
        description: String? = nil,
        as type: Element.Type = Element.self
    ) -> AIOutput<[Element], [Element]> {
        AIOutput<[Element], [Element]>(
            kind: .array,
            schema: element,
            name: name,
            description: description,
            generateFromRequest: { model, request, retryPolicy, telemetry, jsonInstruction, repairText in
                try await AIOutputGenerationResult(
                    objectResult: AI.generateObjectArray(
                        model: model,
                        request: request,
                        as: Element.self,
                        elementSchema: element,
                        schemaName: name,
                        schemaDescription: description,
                        retryPolicy: retryPolicy,
                        telemetry: telemetry,
                        jsonInstruction: jsonInstruction,
                        repairText: repairText
                    )
                )
            },
            streamFromRequest: { model, request, timeoutNanoseconds, retryPolicy, telemetry, jsonInstruction, repairText in
                mapObjectStreamToOutputStream(
                    AI.streamObjectArray(
                        model: model,
                        request: request,
                        as: Element.self,
                        elementSchema: element,
                        schemaName: name,
                        schemaDescription: description,
                        timeoutNanoseconds: timeoutNanoseconds,
                        retryPolicy: retryPolicy,
                        telemetry: telemetry,
                        jsonInstruction: jsonInstruction,
                        repairText: repairText
                    ),
                    outputKind: .array,
                    partial: { $0 }
                )
            },
            requestForOutput: { request, jsonInstruction in
                objectRequest(
                    from: request,
                    schema: arrayOutputSchema(elementSchema: element),
                    schemaName: name,
                    schemaDescription: description,
                    jsonInstruction: jsonInstruction
                )
            },
            optionalResultFromTextResult: { result, providerID, repairText in
                guard shouldParseOutput(from: result) else {
                    return optionalOutputResult(output: nil, rawOutput: .null, textResult: result)
                }
                let parsed = try await parseObjectArray(
                    Element.self,
                    from: result.text,
                    elementSchema: element,
                    repairText: repairText,
                    providerID: providerID
                )
                return optionalOutputResult(
                    output: parsed.object,
                    rawOutput: parsed.rawObject,
                    text: parsed.text,
                    textResult: result
                )
            }
        )
    }

    public static func array<ElementSchema: AIObjectSchema>(
        element: ElementSchema,
        name: String? = nil,
        description: String? = nil
    ) -> AIOutput<[ElementSchema.Output], [ElementSchema.Output]> {
        array(
            element: element.jsonSchema,
            name: name ?? element.name,
            description: description ?? element.description,
            as: ElementSchema.Output.self
        )
    }

    public static func choice(
        options: [String],
        name: String? = nil,
        description: String? = nil
    ) -> AIOutput<String, String> {
        AIOutput<String, String>(
            kind: .choice,
            name: name,
            description: description,
            generateFromRequest: { model, request, retryPolicy, telemetry, jsonInstruction, repairText in
                try await AIOutputGenerationResult(
                    objectResult: AI.generateEnum(
                        model: model,
                        request: request,
                        values: options,
                        schemaName: name,
                        schemaDescription: description,
                        retryPolicy: retryPolicy,
                        telemetry: telemetry,
                        jsonInstruction: jsonInstruction,
                        repairText: repairText
                    )
                )
            },
            streamFromRequest: { model, request, timeoutNanoseconds, retryPolicy, telemetry, jsonInstruction, repairText in
                mapObjectStreamToOutputStream(
                    AI.streamEnum(
                        model: model,
                        request: request,
                        values: options,
                        schemaName: name,
                        schemaDescription: description,
                        timeoutNanoseconds: timeoutNanoseconds,
                        retryPolicy: retryPolicy,
                        telemetry: telemetry,
                        jsonInstruction: jsonInstruction,
                        repairText: repairText
                    ),
                    outputKind: .choice,
                    partial: { $0 }
                )
            },
            requestForOutput: { request, jsonInstruction in
                objectRequest(
                    from: request,
                    schema: enumOutputSchema(values: options),
                    schemaName: name,
                    schemaDescription: description,
                    jsonInstruction: jsonInstruction
                )
            },
            optionalResultFromTextResult: { result, providerID, repairText in
                guard shouldParseOutput(from: result) else {
                    return optionalOutputResult(output: nil, rawOutput: .null, textResult: result)
                }
                let parsed = try await parseEnum(
                    from: result.text,
                    values: options,
                    repairText: repairText,
                    providerID: providerID
                )
                return optionalOutputResult(
                    output: parsed.object,
                    rawOutput: parsed.rawObject,
                    text: parsed.text,
                    textResult: result
                )
            }
        )
    }

    public static func json(
        name: String? = nil,
        description: String? = nil
    ) -> AIOutput<JSONValue, JSONValue> {
        AIOutput<JSONValue, JSONValue>(
            kind: .json,
            name: name,
            description: description,
            generateFromRequest: { model, request, retryPolicy, telemetry, jsonInstruction, repairText in
                try await AIOutputGenerationResult(
                    objectResult: AI.generateJSON(
                        model: model,
                        request: request,
                        schemaName: name,
                        schemaDescription: description,
                        retryPolicy: retryPolicy,
                        telemetry: telemetry,
                        jsonInstruction: jsonInstruction,
                        repairText: repairText
                    )
                )
            },
            streamFromRequest: { model, request, timeoutNanoseconds, retryPolicy, telemetry, jsonInstruction, repairText in
                mapObjectStreamToOutputStream(
                    AI.streamJSON(
                        model: model,
                        request: request,
                        schemaName: name,
                        schemaDescription: description,
                        timeoutNanoseconds: timeoutNanoseconds,
                        retryPolicy: retryPolicy,
                        telemetry: telemetry,
                        jsonInstruction: jsonInstruction,
                        repairText: repairText
                    ),
                    outputKind: .json,
                    partial: { $0 }
                )
            },
            requestForOutput: { request, jsonInstruction in
                objectRequest(
                    from: request,
                    schema: nil,
                    schemaName: name,
                    schemaDescription: description,
                    jsonInstruction: jsonInstruction
                )
            },
            optionalResultFromTextResult: { result, providerID, repairText in
                guard shouldParseOutput(from: result) else {
                    return optionalOutputResult(output: nil, rawOutput: .null, textResult: result)
                }
                let parsed = try await parseJSONValueObject(
                    from: result.text,
                    repairText: repairText,
                    providerID: providerID
                )
                return optionalOutputResult(
                    output: parsed.object,
                    rawOutput: parsed.rawObject,
                    text: parsed.text,
                    textResult: result
                )
            }
        )
    }
}

private func shouldParseOutput(from result: TextGenerationResult) -> Bool {
    !(result.finishReason == "tool-calls" && result.text.isEmpty)
}

private func optionalOutputResult<Output: Sendable>(
    output: Output?,
    rawOutput: JSONValue,
    text: String? = nil,
    textResult: TextGenerationResult
) -> AIOutputGenerationResult<Output?> {
    AIOutputGenerationResult<Output?>(
        output: output,
        text: text ?? textResult.text,
        rawOutput: rawOutput,
        reasoning: textResult.reasoning,
        finishReason: textResult.finishReason,
        usage: textResult.usage,
        warnings: textResult.warnings,
        providerMetadata: textResult.providerMetadata,
        responseMetadata: textResult.responseMetadata,
        textResult: textResult
    )
}

public extension AIOutputGenerationResult where Output == String {
    init(textResult: TextGenerationResult) {
        self.init(
            output: textResult.text,
            text: textResult.text,
            rawOutput: .string(textResult.text),
            reasoning: textResult.reasoning,
            finishReason: textResult.finishReason,
            usage: textResult.usage,
            warnings: textResult.warnings,
            providerMetadata: textResult.providerMetadata,
            responseMetadata: textResult.responseMetadata,
            textResult: textResult
        )
    }
}

public extension AIOutputGenerationResult {
    init(objectResult: ObjectGenerationResult<Output>) {
        self.init(
            output: objectResult.object,
            text: objectResult.text,
            rawOutput: objectResult.rawObject,
            reasoning: objectResult.reasoning,
            finishReason: objectResult.finishReason,
            usage: objectResult.usage,
            warnings: objectResult.warnings,
            providerMetadata: objectResult.providerMetadata,
            responseMetadata: objectResult.responseMetadata,
            textResult: objectResult.textResult
        )
    }
}

private func mapLanguageStreamToOutputStream(
    _ stream: AsyncThrowingStream<LanguageStreamPart, Error>
) -> AsyncThrowingStream<AIOutputStreamPart<String, String>, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            var text = ""
            var reasoning = ""
            var finishReason: String?
            var usage: TokenUsage?
            var warnings: [AIWarning] = []
            var sources: [AISource] = []
            var files: [AIStreamFile] = []
            var providerMetadata: [String: JSONValue] = [:]
            var responseMetadata = AIResponseMetadata()
            var rawValues: [JSONValue] = []

            do {
                for try await part in stream {
                    try Task.checkCancellation()
                    switch part {
                    case let .streamStart(partWarnings):
                        warnings.append(contentsOf: partWarnings)
                        for warning in partWarnings {
                            continuation.yield(.warning(warning))
                        }
                    case let .textDelta(delta):
                        guard !delta.isEmpty else { continue }
                        text += delta
                        continuation.yield(.textDelta(delta))
                        continuation.yield(.partialOutput(text))
                    case let .textDeltaPart(_, delta, _):
                        guard !delta.isEmpty else { continue }
                        text += delta
                        continuation.yield(.textDelta(delta))
                        continuation.yield(.partialOutput(text))
                    case let .reasoningDelta(delta):
                        reasoning += delta
                        continuation.yield(.raw(part))
                    case let .reasoningDeltaPart(_, delta, _):
                        reasoning += delta
                        continuation.yield(.raw(part))
                    case let .source(source):
                        sources.append(source)
                        continuation.yield(.source(source))
                    case let .file(file):
                        files.append(file)
                        continuation.yield(.raw(part))
                    case let .metadata(metadata):
                        continuation.yield(.metadata(metadata))
                    case let .responseMetadata(metadata):
                        responseMetadata = metadata
                        continuation.yield(.responseMetadata(metadata))
                    case let .raw(raw):
                        rawValues.append(raw)
                        continuation.yield(.raw(part))
                    case let .finish(reason, partUsage):
                        finishReason = reason
                        usage = partUsage
                    case let .finishMetadata(reason, partUsage, metadata):
                        finishReason = reason
                        usage = partUsage
                        providerMetadata.merge(metadata) { _, new in new }
                    default:
                        continuation.yield(.raw(part))
                    }
                }

                let textResult = TextGenerationResult(
                    text: text,
                    reasoning: reasoning,
                    finishReason: finishReason,
                    usage: usage,
                    files: files,
                    sources: sources,
                    providerMetadata: providerMetadata,
                    rawValue: rawValues.isEmpty ? .string(text) : .array(rawValues),
                    warnings: warnings,
                    responseMetadata: responseMetadata
                )
                continuation.yield(.output(AIOutputGenerationResult(textResult: textResult)))
                continuation.yield(.finish(reason: finishReason, usage: usage))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { _ in task.cancel() }
    }
}

private func mapObjectStreamToOutputStream<FinalOutput: Sendable, PartialOutput: Sendable>(
    _ stream: AsyncThrowingStream<ObjectStreamPart<FinalOutput>, Error>,
    outputKind: AIOutputKind? = nil,
    partial transformPartial: (@Sendable (FinalOutput) -> PartialOutput)? = nil
) -> AsyncThrowingStream<AIOutputStreamPart<FinalOutput, PartialOutput>, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            var didYieldOutput = false
            do {
                for try await part in stream {
                    try Task.checkCancellation()
                    switch part {
                    case let .textDelta(delta):
                        continuation.yield(.textDelta(delta))
                    case let .partialObject(partial):
                        if let partialOutput = partial as? PartialOutput {
                            continuation.yield(.partialOutput(partialOutput))
                        } else {
                            continuation.yield(.raw(.raw(partial)))
                        }
                    case let .partial(partial):
                        if let transformPartial {
                            continuation.yield(.partialOutput(transformPartial(partial)))
                        }
                    case let .object(result):
                        didYieldOutput = true
                        continuation.yield(.output(AIOutputGenerationResult(objectResult: result)))
                    case let .warning(warning):
                        continuation.yield(.warning(warning))
                    case let .source(source):
                        continuation.yield(.source(source))
                    case let .metadata(metadata):
                        continuation.yield(.metadata(metadata))
                    case let .responseMetadata(metadata):
                        continuation.yield(.responseMetadata(metadata))
                    case let .raw(raw):
                        continuation.yield(.raw(raw))
                    case let .finish(reason, usage):
                        continuation.yield(.finish(reason: reason, usage: usage))
                    }
                }
                guard didYieldOutput else {
                    throw AINoOutputError(structuredOutputKind: outputKind)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { _ in task.cancel() }
    }
}
