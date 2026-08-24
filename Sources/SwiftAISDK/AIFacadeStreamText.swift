import Foundation

extension AI {
    static func streamText(
        model: any LanguageModel,
        request: LanguageModelRequest,
        timeoutNanoseconds: UInt64? = nil,
        timeout: AIStreamTimeoutConfiguration? = nil,
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
        if let validationError = validateStreamTimeoutConfiguration(timeout) {
            return streamTextWithTelemetry(
                makeStream: { failingPartStream(validationError) },
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
        let totalTimeoutNanoseconds = minimumTimeoutNanoseconds(
            timeout?.totalNanoseconds,
            timeoutNanoseconds
        )
        let stepTimeoutNanoseconds = timeout?.stepNanoseconds
        let totalTimeoutController = totalTimeoutNanoseconds.map { _ in AIAbortController() }
        let stepTimeoutController = stepTimeoutNanoseconds.map { _ in AIAbortController() }
        let semanticTimeoutController = timeout?.firstChunkNanoseconds != nil
            || timeout?.chunkNanoseconds != nil
            ? AIAbortController()
            : nil
        var requestWithTimeoutSignals = preparedRequest
        requestWithTimeoutSignals.abortSignal = mergeAbortSignals(
            preparedRequest.abortSignal,
            totalTimeoutController?.signal,
            stepTimeoutController?.signal,
            semanticTimeoutController?.signal
        )
        let operationRequest = requestWithTimeoutSignals

        let retriedStream = streamTextWithTelemetry(
            makeStream: {
                let attemptTimeoutController = retryPolicy.timeoutNanoseconds.map { _ in
                    AIAbortController()
                }
                var attemptRequest = operationRequest
                attemptRequest.abortSignal = mergeAbortSignals(
                    operationRequest.abortSignal,
                    attemptTimeoutController?.signal
                )
                let stream = streamWithAbortSignal(
                    model.stream(attemptRequest),
                    abortSignal: attemptRequest.abortSignal
                )
                let canonicalStream = canonicalLanguageStream(
                    stream,
                    providerID: model.providerID
                )
                let outputTimedStream = streamWithSemanticOutputTimeouts(
                    forwardedLanguageStream(canonicalStream, request: attemptRequest),
                    firstChunkNanoseconds: timeout?.firstChunkNanoseconds,
                    chunkNanoseconds: timeout?.chunkNanoseconds,
                    abortController: semanticTimeoutController
                )
                return streamWithTimeout(
                    outputTimedStream,
                    timeoutNanoseconds: retryPolicy.timeoutNanoseconds,
                    abortController: attemptTimeoutController,
                    timeoutLabel: "Retry attempt"
                )
            },
            operationID: "ai.streamText",
            providerID: model.providerID,
            modelID: model.modelID,
            input: languageRequestTelemetryInput(operationRequest),
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            abortSignal: operationRequest.abortSignal,
            logWarnings: logWarnings
        )
        let stepTimedStream = streamWithTimeout(
            retriedStream,
            timeoutNanoseconds: stepTimeoutNanoseconds,
            abortController: stepTimeoutController,
            timeoutLabel: "Step"
        )
        return streamWithTimeout(
            stepTimedStream,
            timeoutNanoseconds: totalTimeoutNanoseconds,
            abortController: totalTimeoutController,
            timeoutLabel: "Total"
        )
    }

    public static func streamText(
        model: any LanguageModel,
        request: LanguageModelRequest,
        timeoutNanoseconds: UInt64? = nil,
        timeout: AIStreamTimeoutConfiguration? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: Telemetry.Options? = nil
    ) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamText(
            model: model,
            request: request,
            timeoutNanoseconds: timeoutNanoseconds,
            timeout: timeout,
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
        timeout: AIStreamTimeoutConfiguration? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: Telemetry.Options? = nil
    ) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        guard !executableTools.isEmpty || prepareStep != nil else {
            return streamText(
                model: model,
                request: request,
                timeoutNanoseconds: timeoutNanoseconds,
                timeout: timeout,
                retryPolicy: retryPolicy,
                telemetry: telemetry
            )
        }
        if let validationError = validateStreamTimeoutConfiguration(timeout) {
            return streamTextWithTelemetry(
                makeStream: { failingPartStream(validationError) },
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

        let explicitTotalTimeoutNanoseconds = minimumTimeoutNanoseconds(
            timeout?.totalNanoseconds,
            timeoutNanoseconds
        )
        let totalTimeoutNanoseconds = explicitTotalTimeoutNanoseconds
            ?? retryPolicy.timeoutNanoseconds
        let totalTimeoutController = totalTimeoutNanoseconds.map { _ in AIAbortController() }
        var requestWithTimeoutSignals = request
        requestWithTimeoutSignals.abortSignal = mergeAbortSignals(
            request.abortSignal,
            totalTimeoutController?.signal
        )
        let operationRequest = requestWithTimeoutSignals

        let stream = AsyncThrowingStream<LanguageStreamPart, Error> { continuation in
            let task = Task {
                do {
                    if let validationError = validateStreamTimeoutConfiguration(timeout) {
                        throw validationError
                    }
                    guard maxSteps > 0 else {
                        throw AIError.invalidArgument(argument: "maxSteps", message: "maxSteps must be greater than zero.")
                    }

                    let initialRequest = operationRequest
                    var currentRequest = operationRequest
                    currentRequest.tools.merge(toolsDictionary(from: executableTools)) { _, typed in typed }
                    var steps: [AIToolStep] = []
                    var responseMessages: [AIMessage] = []
                    var pendingProviderExecutedToolCallIDs: Set<String> = []
                    let partIDReserver = LanguageStreamPartIDReserver()
                    let toolTelemetry = AIToolLoopTelemetryContext(
                        operationID: "ai.streamText",
                        providerID: model.providerID,
                        modelID: model.modelID,
                        telemetry: telemetry
                    )

                    for index in 0..<maxSteps {
                        let stepDeadline = AIStreamTimeoutDeadline(
                            durationNanoseconds: timeout?.stepNanoseconds,
                            label: "Step"
                        )
                        stepDeadline.start()
                        defer { stepDeadline.cancel() }
                        do {
                        var stepCurrentRequest = currentRequest
                        stepCurrentRequest.abortSignal = mergeAbortSignals(
                            currentRequest.abortSignal,
                            stepDeadline.signal
                        )
                        let historicalApprovalExecution = try await executeHistoricalToolApprovals(
                            request: stepCurrentRequest,
                            toolsByName: try toolsByName(from: executableTools),
                            toolApproval: toolApproval,
                            telemetry: toolTelemetry,
                            stepIndex: index
                        )
                        try stepDeadline.throwIfTimedOut()
                        if !historicalApprovalExecution.responseMessages.isEmpty {
                            responseMessages.append(contentsOf: historicalApprovalExecution.responseMessages)
                            stepCurrentRequest.messages.append(contentsOf: historicalApprovalExecution.responseMessages)
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
                            request: stepCurrentRequest,
                            initialRequest: initialRequest,
                            responseMessages: responseMessages
                        ))
                        try stepDeadline.throwIfTimedOut()
                        let stepModel = prepared?.model ?? model
                        let stepTools = prepared?.executableTools ?? executableTools
                        let toolsByName = try toolsByName(from: stepTools)
                        var stepRequest = try prepareLanguageModelCallOptions(
                            prepared?.request ?? stepCurrentRequest
                        )
                        if stepRequest.abortSignal === operationRequest.abortSignal {
                            stepRequest.abortSignal = mergeAbortSignals(
                                stepRequest.abortSignal,
                                stepDeadline.signal
                            )
                        } else {
                            stepRequest.abortSignal = mergeAbortSignals(
                                stepRequest.abortSignal,
                                operationRequest.abortSignal,
                                stepDeadline.signal
                            )
                        }
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
                        try stepDeadline.throwIfTimedOut()
                        let step = try await forwardLanguageStream(
                            streamText(
                                model: stepModel,
                                request: stepRequest,
                                timeout: timeout.map {
                                    AIStreamTimeoutConfiguration(
                                        firstChunkNanoseconds: $0.firstChunkNanoseconds,
                                        chunkNanoseconds: $0.chunkNanoseconds
                                    )
                                },
                                retryPolicy: retryPolicy
                            ),
                            to: continuation,
                            toolsByName: toolsByName,
                            request: stepRequest,
                            repairToolCall: repairToolCall,
                            partIDReserver: partIDReserver
                        )
                        try stepDeadline.throwIfTimedOut()
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

                        if !isAutomaticToolExecutionAllowed(finishReason: step.finishReason) {
                            let completedStep = step.toolStep(
                                index: index,
                                toolResults: [],
                                approvalRequests: [],
                                approvalResponses: []
                            )
                            steps.append(completedStep)
                            await toolTelemetry.recordStepEnd(completedStep)
                            try stepDeadline.throwIfTimedOut()
                            continuation.finish()
                            return
                        }

                        guard !executableCalls.isEmpty else {
                            let completedStep = step.toolStep(
                                index: index,
                                toolResults: [],
                                approvalRequests: [],
                                approvalResponses: []
                            )
                            steps.append(completedStep)
                            await toolTelemetry.recordStepEnd(completedStep)
                            try stepDeadline.throwIfTimedOut()
                            if try await isStopConditionMet(stopWhen, steps: steps) {
                                try stepDeadline.throwIfTimedOut()
                                continuation.finish()
                                return
                            }
                            let stepResponseMessages = try await toResponseMessages(
                                content: completedStep.content.compactMap(\.responseMessagePart),
                                toolsByName: toolsByName
                            )
                            responseMessages.append(contentsOf: stepResponseMessages)
                            currentRequest = stepRequest
                            currentRequest.abortSignal = operationRequest.abortSignal
                            currentRequest.messages.append(contentsOf: stepResponseMessages)
                            guard !pendingProviderExecutedToolCallIDs.isEmpty, index < maxSteps - 1 else {
                                try stepDeadline.throwIfTimedOut()
                                continuation.finish()
                                return
                            }
                            try stepDeadline.throwIfTimedOut()
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
                        try stepDeadline.throwIfTimedOut()
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
                        try stepDeadline.throwIfTimedOut()
                        if toolExecution.needsUserApproval {
                            continuation.finish()
                            return
                        }
                        if try await isStopConditionMet(stopWhen, steps: steps) {
                            try stepDeadline.throwIfTimedOut()
                            continuation.finish()
                            return
                        }
                        let stepResponseMessages = try await toResponseMessages(
                            content: completedStep.content.compactMap(\.responseMessagePart),
                            toolsByName: toolsByName
                        )
                        responseMessages.append(contentsOf: stepResponseMessages)
                        currentRequest = stepRequest
                        currentRequest.abortSignal = operationRequest.abortSignal
                        currentRequest.messages.append(contentsOf: stepResponseMessages)
                        try stepDeadline.throwIfTimedOut()
                        } catch {
                            if stepDeadline.hasTimedOut,
                               let durationNanoseconds = stepDeadline.durationNanoseconds {
                                throw AIError.timeout(durationNanoseconds: durationNanoseconds)
                            }
                            throw error
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
        let telemeteredStream = streamTextWithTelemetry(
            makeStream: { stream },
            operationID: "ai.streamText",
            providerID: model.providerID,
            modelID: model.modelID,
            input: languageRequestTelemetryInput(operationRequest),
            retryPolicy: .none,
            telemetry: telemetry,
            abortSignal: operationRequest.abortSignal,
            logWarnings: false
        )
        return streamWithTimeout(
            telemeteredStream,
            timeoutNanoseconds: totalTimeoutNanoseconds,
            abortController: totalTimeoutController,
            timeoutLabel: "Total"
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
        timeout: AIStreamTimeoutConfiguration? = nil,
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
                timeout: timeout,
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
            timeout: timeout,
            retryPolicy: retryPolicy,
            telemetry: telemetry
        )
    }

    public static func streamText<FinalOutput: Sendable, PartialOutput: Sendable>(
        model: any LanguageModel,
        request: LanguageModelRequest,
        output: AIOutput<FinalOutput, PartialOutput>,
        timeoutNanoseconds: UInt64? = nil,
        timeout: AIStreamTimeoutConfiguration? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: Telemetry.Options? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) -> AsyncThrowingStream<AIOutputStreamPart<FinalOutput, PartialOutput>, Error> {
        if let timeoutNanoseconds, timeoutNanoseconds == 0 {
            return failingPartStream(AIError.invalidArgument(
                argument: "timeoutNanoseconds",
                message: "timeoutNanoseconds must be greater than zero."
            ))
        }
        if let validationError = validateStreamTimeoutConfiguration(timeout) {
            return failingPartStream(validationError)
        }

        let totalTimeoutNanoseconds = minimumTimeoutNanoseconds(
            timeout?.totalNanoseconds,
            timeoutNanoseconds
        )
        let stepTimeoutNanoseconds = timeout?.stepNanoseconds
        let totalTimeoutController = totalTimeoutNanoseconds.map { _ in AIAbortController() }
        let stepTimeoutController = stepTimeoutNanoseconds.map { _ in AIAbortController() }
        let semanticTimeoutController = timeout?.firstChunkNanoseconds != nil
            || timeout?.chunkNanoseconds != nil
            ? AIAbortController()
            : nil
        var requestWithTimeoutSignals = request
        requestWithTimeoutSignals.abortSignal = mergeAbortSignals(
            request.abortSignal,
            totalTimeoutController?.signal,
            stepTimeoutController?.signal,
            semanticTimeoutController?.signal
        )
        let operationRequest = requestWithTimeoutSignals
        let outputStream = output.streamFromRequest(
            model,
            operationRequest,
            nil,
            retryPolicy,
            telemetry,
            jsonInstruction,
            repairText
        )
        let semanticTimedStream = streamWithSemanticOutputTimeouts(
            outputStream,
            firstChunkNanoseconds: timeout?.firstChunkNanoseconds,
            chunkNanoseconds: timeout?.chunkNanoseconds,
            abortController: semanticTimeoutController
        )
        let stepTimedStream = streamWithTimeout(
            semanticTimedStream,
            timeoutNanoseconds: stepTimeoutNanoseconds,
            abortController: stepTimeoutController,
            timeoutLabel: "Step"
        )
        return streamWithTimeout(
            stepTimedStream,
            timeoutNanoseconds: totalTimeoutNanoseconds,
            abortController: totalTimeoutController,
            timeoutLabel: "Total"
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
        timeout: AIStreamTimeoutConfiguration? = nil,
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
            timeout: timeout,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            jsonInstruction: jsonInstruction,
            repairText: repairText
        )
    }

}
