import Foundation

extension AI {
    static func streamText(
        model: any LanguageModel,
        request: LanguageModelRequest,
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: Telemetry.Options? = nil,
        logWarnings: Bool
    ) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        let preparedRequest: LanguageModelRequest
        do {
            preparedRequest = try prepareLanguageModelCallOptions(request)
        } catch {
            return streamTextWithTelemetry(
                makeStream: { failingPartStream(error) },
                operationID: "ai.streamText",
                providerID: model.providerID,
                modelID: model.modelID,
                input: languageRequestTelemetryInput(request),
                retryPolicy: retryPolicy,
                telemetry: telemetry,
                abortSignal: request.abortSignal,
                logWarnings: logWarnings
            )
        }
        if let timeoutNanoseconds, timeoutNanoseconds <= 0 {
            return streamTextWithTelemetry(
                makeStream: {
                    failingPartStream(AIError.invalidArgument(
                        argument: "timeoutNanoseconds",
                        message: "timeoutNanoseconds must be greater than zero."
                    ))
                },
                operationID: "ai.streamText",
                providerID: model.providerID,
                modelID: model.modelID,
                input: languageRequestTelemetryInput(preparedRequest),
                retryPolicy: retryPolicy,
                telemetry: telemetry,
                abortSignal: preparedRequest.abortSignal,
                logWarnings: logWarnings
            )
        }
        return streamTextWithTelemetry(
            makeStream: {
                let stream = streamWithAbortSignal(
                    model.stream(preparedRequest),
                    abortSignal: preparedRequest.abortSignal
                )
                return streamWithTimeout(
                    forwardedLanguageStream(stream, request: preparedRequest),
                    timeoutNanoseconds: timeoutNanoseconds ?? retryPolicy.timeoutNanoseconds
                )
            },
            operationID: "ai.streamText",
            providerID: model.providerID,
            modelID: model.modelID,
            input: languageRequestTelemetryInput(preparedRequest),
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            abortSignal: preparedRequest.abortSignal,
            logWarnings: logWarnings
        )
    }

    public static func streamText(
        model: any LanguageModel,
        request: LanguageModelRequest,
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: Telemetry.Options? = nil
    ) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamText(
            model: model,
            request: request,
            timeoutNanoseconds: timeoutNanoseconds,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            logWarnings: true
        )
    }

    public static func streamText(
        model: any LanguageModel,
        request: LanguageModelRequest,
        executableTools: [AITool],
        maxSteps: Int = 5,
        stopWhen: [AIStopCondition] = [],
        prepareStep: AIPrepareStep? = nil,
        toolApproval: AIToolApproval? = nil,
        repairToolCall: AIToolCallRepair? = nil,
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: Telemetry.Options? = nil
    ) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        let stream = AsyncThrowingStream<LanguageStreamPart, Error> { continuation in
            let task = Task {
                do {
                    guard !executableTools.isEmpty || prepareStep != nil else {
                        let request = try prepareLanguageModelCallOptions(request)
                        var innerRetryPolicy = retryPolicy
                        innerRetryPolicy.timeoutNanoseconds = nil
                        for try await part in streamText(
                            model: model,
                            request: request,
                            timeoutNanoseconds: nil,
                            retryPolicy: innerRetryPolicy,
                            telemetry: nil
                        ) {
                            continuation.yield(part)
                        }
                        continuation.finish()
                        return
                    }
                    guard maxSteps > 0 else {
                        throw AIError.invalidArgument(argument: "maxSteps", message: "maxSteps must be greater than zero.")
                    }

                    let initialRequest = request
                    var currentRequest = request
                    currentRequest.tools.merge(toolsDictionary(from: executableTools)) { _, typed in typed }
                    var steps: [AIToolStep] = []
                    var responseMessages: [AIMessage] = []
                    var pendingProviderExecutedToolCallIDs: Set<String> = []
                    let toolTelemetry = AIToolLoopTelemetryContext(
                        operationID: "ai.streamText",
                        providerID: model.providerID,
                        modelID: model.modelID,
                        telemetry: telemetry
                    )

                    for index in 0..<maxSteps {
                        let historicalApprovalExecution = try await executeHistoricalToolApprovals(
                            request: currentRequest,
                            toolsByName: try toolsByName(from: executableTools),
                            toolApproval: toolApproval,
                            telemetry: toolTelemetry,
                            stepIndex: index
                        )
                        if !historicalApprovalExecution.responseMessages.isEmpty {
                            responseMessages.append(contentsOf: historicalApprovalExecution.responseMessages)
                            currentRequest.messages.append(contentsOf: historicalApprovalExecution.responseMessages)
                            for approvalResponse in historicalApprovalExecution.approvalResponses {
                                continuation.yield(.toolApprovalResponse(approvalResponse))
                            }
                            for toolResult in historicalApprovalExecution.toolResults {
                                continuation.yield(.toolResult(toolResult))
                            }
                        }

                        let prepared = try await prepareStep?(AIPrepareStepContext(
                            model: model,
                            stepNumber: index,
                            steps: steps,
                            request: currentRequest,
                            initialRequest: initialRequest,
                            responseMessages: responseMessages
                        ))
                        let stepModel = prepared?.model ?? model
                        let stepTools = prepared?.executableTools ?? executableTools
                        let toolsByName = try toolsByName(from: stepTools)
                        var stepRequest = try prepareLanguageModelCallOptions(prepared?.request ?? currentRequest)
                        if prepared?.executableTools != nil {
                            stepRequest.tools = toolsDictionary(from: stepTools)
                        } else {
                            stepRequest.tools.merge(toolsDictionary(from: stepTools)) { _, typed in typed }
                        }

                        await toolTelemetry.recordStepStart(
                            index: index,
                            maxSteps: maxSteps,
                            model: stepModel,
                            request: stepRequest,
                            tools: stepTools
                        )
                        let step = try await forwardLanguageStream(
                            streamText(model: stepModel, request: stepRequest, retryPolicy: retryPolicy),
                            to: continuation,
                            toolsByName: toolsByName,
                            request: stepRequest,
                            repairToolCall: repairToolCall
                        )
                        let executableCalls = step.toolCalls.filter { !$0.providerExecuted }
                        let providerExecutedToolCallIDs = Set(step.toolCalls.filter(\.providerExecuted).map(\.id))
                        pendingProviderExecutedToolCallIDs.formUnion(providerExecutedToolCallIDs)
                        let providerExecutedToolResultIDs = Set(step.streamedToolResults.compactMap { result -> String? in
                            if result.providerExecuted
                                || providerExecutedToolCallIDs.contains(result.toolCallID)
                                || pendingProviderExecutedToolCallIDs.contains(result.toolCallID) {
                                return result.toolCallID
                            }
                            return nil
                        })
                        pendingProviderExecutedToolCallIDs.subtract(providerExecutedToolResultIDs)

                        guard !executableCalls.isEmpty else {
                            let completedStep = step.toolStep(
                                index: index,
                                toolResults: [],
                                approvalRequests: [],
                                approvalResponses: []
                            )
                            steps.append(completedStep)
                            await toolTelemetry.recordStepEnd(completedStep)
                            if try await isStopConditionMet(stopWhen, steps: steps) {
                                continuation.finish()
                                return
                            }
                            let stepResponseMessages = try await toResponseMessages(
                                content: completedStep.content.compactMap(\.responseMessagePart),
                                toolsByName: toolsByName
                            )
                            responseMessages.append(contentsOf: stepResponseMessages)
                            currentRequest = stepRequest
                            currentRequest.messages.append(contentsOf: stepResponseMessages)
                            guard !pendingProviderExecutedToolCallIDs.isEmpty, index < maxSteps - 1 else {
                                continuation.finish()
                                return
                            }
                            continue
                        }

                        let toolExecution = try await executeToolCalls(
                            executableCalls,
                            toolsByName: toolsByName,
                            request: stepRequest,
                            toolApproval: toolApproval,
                            repairToolCall: repairToolCall,
                            telemetry: toolTelemetry,
                            stepIndex: index,
                            convertToolErrorsToResults: true,
                            invokeInputAvailableCallbacks: false
                        )
                        for approvalRequest in toolExecution.approvalRequests {
                            continuation.yield(.toolApprovalRequest(approvalRequest))
                        }
                        for approvalResponse in toolExecution.approvalResponses {
                            continuation.yield(.toolApprovalResponse(approvalResponse))
                        }
                        for toolResult in toolExecution.results {
                            continuation.yield(.toolResult(toolResult))
                        }

                        let completedStep = step.toolStep(
                            index: index,
                            toolResults: toolExecution.results,
                            approvalRequests: toolExecution.approvalRequests,
                            approvalResponses: toolExecution.approvalResponses
                        )
                        steps.append(completedStep)
                        await toolTelemetry.recordStepEnd(completedStep)
                        if toolExecution.needsUserApproval {
                            continuation.finish()
                            return
                        }
                        if try await isStopConditionMet(stopWhen, steps: steps) {
                            continuation.finish()
                            return
                        }
                        let stepResponseMessages = try await toResponseMessages(
                            content: completedStep.content.compactMap(\.responseMessagePart),
                            toolsByName: toolsByName
                        )
                        responseMessages.append(contentsOf: stepResponseMessages)
                        currentRequest = stepRequest
                        currentRequest.messages.append(contentsOf: stepResponseMessages)
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
        return streamTextWithTelemetry(
            makeStream: {
                streamWithTimeout(
                    stream,
                    timeoutNanoseconds: timeoutNanoseconds ?? retryPolicy.timeoutNanoseconds
                )
            },
            operationID: "ai.streamText",
            providerID: model.providerID,
            modelID: model.modelID,
            input: languageRequestTelemetryInput(request),
            retryPolicy: .none,
            telemetry: telemetry,
            abortSignal: request.abortSignal,
            logWarnings: false
        )
    }

    public static func streamText(
        model: any LanguageModel,
        prompt: String,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        seed: Int? = nil,
        maxOutputTokens: Int? = nil,
        stopSequences: [String] = [],
        responseFormat: AIResponseFormat? = nil,
        reasoning: String? = nil,
        tools: [String: JSONValue] = [:],
        executableTools: [AITool] = [],
        maxSteps: Int = 5,
        stopWhen: [AIStopCondition] = [],
        prepareStep: AIPrepareStep? = nil,
        toolApproval: AIToolApproval? = nil,
        repairToolCall: AIToolCallRepair? = nil,
        toolChoice: JSONValue? = nil,
        includeRawChunks: Bool = false,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil,
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: Telemetry.Options? = nil
    ) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        let request = LanguageModelRequest(
            messages: [.user(prompt)],
            temperature: temperature,
            topP: topP,
            topK: topK,
            presencePenalty: presencePenalty,
            frequencyPenalty: frequencyPenalty,
            seed: seed,
            maxOutputTokens: maxOutputTokens,
            stopSequences: stopSequences,
            responseFormat: responseFormat,
            reasoning: reasoning,
            tools: tools,
            toolChoice: toolChoice,
            includeRawChunks: includeRawChunks,
            providerOptions: providerOptions,
            extraBody: extraBody,
            headers: headers,
            abortSignal: abortSignal
        )

        if executableTools.isEmpty && prepareStep == nil {
            return streamText(
                model: model,
                request: request,
                timeoutNanoseconds: timeoutNanoseconds,
                retryPolicy: retryPolicy,
                telemetry: telemetry
            )
        }

        return streamText(
            model: model,
            request: request,
            executableTools: executableTools,
            maxSteps: maxSteps,
            stopWhen: stopWhen,
            prepareStep: prepareStep,
            toolApproval: toolApproval,
            repairToolCall: repairToolCall,
            timeoutNanoseconds: timeoutNanoseconds,
            retryPolicy: retryPolicy,
            telemetry: telemetry
        )
    }

    public static func streamText<FinalOutput: Sendable, PartialOutput: Sendable>(
        model: any LanguageModel,
        request: LanguageModelRequest,
        output: AIOutput<FinalOutput, PartialOutput>,
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: Telemetry.Options? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) -> AsyncThrowingStream<AIOutputStreamPart<FinalOutput, PartialOutput>, Error> {
        output.streamFromRequest(
            model,
            request,
            timeoutNanoseconds,
            retryPolicy,
            telemetry,
            jsonInstruction,
            repairText
        )
    }

    public static func streamText<FinalOutput: Sendable, PartialOutput: Sendable>(
        model: any LanguageModel,
        prompt: String,
        output: AIOutput<FinalOutput, PartialOutput>,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        seed: Int? = nil,
        maxOutputTokens: Int? = nil,
        stopSequences: [String] = [],
        reasoning: String? = nil,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil,
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: Telemetry.Options? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) -> AsyncThrowingStream<AIOutputStreamPart<FinalOutput, PartialOutput>, Error> {
        streamText(
            model: model,
            request: LanguageModelRequest(
                messages: [.user(prompt)],
                temperature: temperature,
                topP: topP,
                topK: topK,
                presencePenalty: presencePenalty,
                frequencyPenalty: frequencyPenalty,
                seed: seed,
                maxOutputTokens: maxOutputTokens,
                stopSequences: stopSequences,
                reasoning: reasoning,
                providerOptions: providerOptions,
                extraBody: extraBody,
                headers: headers,
                abortSignal: abortSignal
            ),
            output: output,
            timeoutNanoseconds: timeoutNanoseconds,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            jsonInstruction: jsonInstruction,
            repairText: repairText
        )
    }

}
