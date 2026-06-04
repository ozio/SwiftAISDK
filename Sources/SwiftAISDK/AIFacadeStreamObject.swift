import Foundation

extension AI {
    public static func streamObject<Object: Decodable & Sendable>(
        model: any LanguageModel,
        request: LanguageModelRequest,
        as type: Object.Type = Object.self,
        schema: JSONValue? = nil,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: Telemetry.Options? = nil,
        callbacks: AIObjectGenerationCallbacks<Object>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) -> AsyncThrowingStream<ObjectStreamPart<Object>, Error> {
        let objectRequest = objectRequest(
            from: request,
            schema: schema,
            schemaName: schemaName,
            schemaDescription: schemaDescription,
            jsonInstruction: jsonInstruction
        )
        let streamRequest = objectRequest

        if let timeoutNanoseconds, timeoutNanoseconds <= 0 {
            return objectStreamWithTelemetry(
                makeStream: {
                    failingPartStream(AIError.invalidArgument(
                        argument: "timeoutNanoseconds",
                        message: "timeoutNanoseconds must be greater than zero."
                    ))
                },
                operationID: "ai.streamObject",
                providerID: model.providerID,
                modelID: model.modelID,
                request: streamRequest,
                input: objectGenerationTelemetryInput(
                    streamRequest,
                    outputKind: "object",
                    schema: schema,
                    schemaName: schemaName,
                    schemaDescription: schemaDescription
                ),
                retryPolicy: retryPolicy,
                telemetry: telemetry,
                callbacks: callbacks
            )
        }

        let makeStream: @Sendable () -> AsyncThrowingStream<ObjectStreamPart<Object>, Error> = {
            AsyncThrowingStream<ObjectStreamPart<Object>, Error> { continuation in
            let task = Task {
                var text = ""
                var reasoning = ""
                var finishReason: String?
                var usage: TokenUsage?
                var warnings: [AIWarning] = []
                var sources: [AISource] = []
                var providerMetadata: [String: JSONValue] = [:]
                var responseMetadata = AIResponseMetadata()
                var rawValues: [JSONValue] = []
                var lastPartialObject: JSONValue?

                do {
                    for try await part in streamText(model: model, request: streamRequest, retryPolicy: .none) {
                        try Task.checkCancellation()
                        switch part {
                        case let .streamStart(partWarnings):
                            warnings.append(contentsOf: partWarnings)
                            for warning in partWarnings {
                                continuation.yield(.warning(warning))
                            }
                        case let .textDelta(delta):
                            text += delta
                            continuation.yield(.textDelta(delta))
                            if let partial = partialObject(from: text), partial != lastPartialObject {
                                lastPartialObject = partial
                                continuation.yield(.partialObject(partial))
                                if let typedPartial = typedPartialObject(Object.self, from: partial) {
                                    continuation.yield(.partial(typedPartial))
                                }
                            }
                        case let .textDeltaPart(_, delta, _):
                            text += delta
                            continuation.yield(.textDelta(delta))
                            if let partial = partialObject(from: text), partial != lastPartialObject {
                                lastPartialObject = partial
                                continuation.yield(.partialObject(partial))
                                if let typedPartial = typedPartialObject(Object.self, from: partial) {
                                    continuation.yield(.partial(typedPartial))
                                }
                            }
                        case let .reasoningDelta(delta):
                            reasoning += delta
                            continuation.yield(.raw(part))
                        case let .reasoningDeltaPart(_, delta, _):
                            reasoning += delta
                            continuation.yield(.raw(part))
                        case let .source(source):
                            sources.append(source)
                            continuation.yield(.source(source))
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

                    let parsed = try await parseObject(
                        Object.self,
                        from: text,
                        schema: schema,
                        repairText: repairText,
                        providerID: model.providerID
                    )
                    let textResult = TextGenerationResult(
                        text: parsed.text,
                        reasoning: reasoning,
                        finishReason: finishReason,
                        usage: usage,
                        sources: sources,
                        providerMetadata: providerMetadata,
                        rawValue: rawValues.isEmpty ? parsed.rawObject : .array(rawValues),
                        warnings: warnings,
                        requestMetadata: AIRequestMetadata(body: languageRequestMetadataBody(streamRequest), headers: streamRequest.headers),
                        responseMetadata: responseMetadata
                    )
                    let objectResult = ObjectGenerationResult(
                        object: parsed.object,
                        text: parsed.text,
                        rawObject: parsed.rawObject,
                        reasoning: reasoning,
                        finishReason: finishReason,
                        usage: usage,
                        warnings: warnings,
                        providerMetadata: providerMetadata,
                        responseMetadata: responseMetadata,
                        textResult: textResult
                    )
                    continuation.yield(.object(objectResult))
                    continuation.yield(.finish(reason: finishReason, usage: usage))
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
        return objectStreamWithTelemetry(
            makeStream: {
                streamWithTimeout(
                    streamWithAbortSignal(makeStream(), abortSignal: streamRequest.abortSignal),
                    timeoutNanoseconds: timeoutNanoseconds ?? retryPolicy.timeoutNanoseconds
                )
            },
            operationID: "ai.streamObject",
            providerID: model.providerID,
            modelID: model.modelID,
            request: streamRequest,
            input: objectGenerationTelemetryInput(
                streamRequest,
                outputKind: "object",
                schema: schema,
                schemaName: schemaName,
                schemaDescription: schemaDescription
            ),
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks
        )
    }
}
