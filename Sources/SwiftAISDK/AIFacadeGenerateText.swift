import Foundation

extension AI {
    public static func generateText(
        model: any LanguageModel,
        request: LanguageModelRequest,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil
    ) async throws -> TextGenerationResult {
        try await withTelemetry(
            operationID: "ai.generateText",
            providerID: model.providerID,
            modelID: model.modelID,
            input: languageRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            abortSignal: request.abortSignal,
            output: textGenerationTelemetryOutput,
            usage: { $0.usage },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata },
            wrapLanguageModelCall: true
        ) {
            var result = try await model.generate(request)
            if result.requestMetadata == AIRequestMetadata() {
                result.requestMetadata = AIRequestMetadata(body: languageRequestMetadataBody(request), headers: request.headers)
            }
            return result
        }
    }

    public static func generateText(
        model: any LanguageModel,
        request: LanguageModelRequest,
        executableTools: [AITool],
        maxSteps: Int = 5,
        stopWhen: [AIStopCondition] = [],
        prepareStep: AIPrepareStep? = nil,
        toolApproval: AIToolApproval? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil
    ) async throws -> TextGenerationResult {
        guard !executableTools.isEmpty || prepareStep != nil else {
            return try await generateText(model: model, request: request, retryPolicy: retryPolicy, telemetry: telemetry)
        }
        guard maxSteps > 0 else {
            throw AIError.invalidArgument(argument: "maxSteps", message: "maxSteps must be greater than zero.")
        }

        let initialRequest = request
        var currentRequest = request
        currentRequest.tools.merge(toolsDictionary(from: executableTools)) { _, typed in typed }

        var steps: [AIToolStep] = []
        var allToolResults: [AIToolResult] = []
        var allApprovalRequests: [AIToolApprovalRequest] = []
        var allApprovalResponses: [AIToolApprovalResponse] = []
        var responseMessages: [AIMessage] = []
        var lastResult: TextGenerationResult?
        let toolTelemetry = AIToolLoopTelemetryContext(
            operationID: "ai.generateText",
            providerID: model.providerID,
            modelID: model.modelID,
            telemetry: telemetry
        )

        for index in 0..<maxSteps {
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
            var stepRequest = prepared?.request ?? currentRequest
            stepRequest.tools.merge(toolsDictionary(from: stepTools)) { _, typed in typed }

            await toolTelemetry.recordStepStart(
                index: index,
                maxSteps: maxSteps,
                model: stepModel,
                request: stepRequest,
                tools: stepTools
            )
            var result = try await generateText(model: stepModel, request: stepRequest, retryPolicy: retryPolicy, telemetry: telemetry)
            result.toolCalls = annotateToolCalls(result.toolCalls, toolsByName: toolsByName)
            let executableCalls = result.toolCalls.filter { !$0.providerExecuted }

            if executableCalls.isEmpty {
                let finalStep = AIToolStep(
                    index: index,
                    text: result.text,
                    reasoning: result.reasoning,
                    finishReason: result.finishReason,
                    usage: result.usage,
                    toolCalls: result.toolCalls,
                    toolApprovalRequests: result.toolApprovalRequests,
                    toolApprovalResponses: result.toolApprovalResponses,
                    providerMetadata: result.providerMetadata,
                    responseMetadata: result.responseMetadata
                )
                result.toolResults = allToolResults
                result.toolApprovalRequests = allApprovalRequests
                result.toolApprovalResponses = allApprovalResponses
                result.steps = steps + [finalStep]
                await toolTelemetry.recordStepEnd(finalStep)
                return result
            }

            let toolExecution = try await executeToolCalls(
                executableCalls,
                toolsByName: toolsByName,
                request: stepRequest,
                toolApproval: toolApproval,
                telemetry: toolTelemetry,
                stepIndex: index
            )
            allApprovalRequests.append(contentsOf: toolExecution.approvalRequests)
            allApprovalResponses.append(contentsOf: toolExecution.approvalResponses)
            allToolResults.append(contentsOf: toolExecution.results)
            let step = AIToolStep(
                index: index,
                text: result.text,
                reasoning: result.reasoning,
                finishReason: result.finishReason,
                usage: result.usage,
                toolCalls: result.toolCalls,
                toolResults: toolExecution.results,
                toolApprovalRequests: toolExecution.approvalRequests,
                toolApprovalResponses: toolExecution.approvalResponses,
                providerMetadata: result.providerMetadata,
                responseMetadata: result.responseMetadata
            )
            steps.append(step)
            await toolTelemetry.recordStepEnd(step)

            result.toolResults = allToolResults
            result.toolApprovalRequests = allApprovalRequests
            result.toolApprovalResponses = allApprovalResponses
            result.steps = steps
            lastResult = result
            if toolExecution.needsUserApproval {
                return result
            }
            if try await isStopConditionMet(stopWhen, steps: steps) {
                return result
            }
            let assistantMessage = AIMessage.assistant(
                text: result.text,
                toolCalls: result.toolCalls,
                toolApprovalRequests: toolExecution.approvalRequests
            )
            let toolResultMessages = toolResponseMessages(
                approvalResponses: toolExecution.approvalResponses,
                toolResults: toolExecution.results
            )
            responseMessages.append(assistantMessage)
            responseMessages.append(contentsOf: toolResultMessages)
            currentRequest = stepRequest
            currentRequest.messages.append(assistantMessage)
            currentRequest.messages.append(contentsOf: toolResultMessages)
        }

        guard var result = lastResult else {
            return try await generateText(model: model, request: currentRequest, retryPolicy: retryPolicy, telemetry: telemetry)
        }
        result.toolResults = allToolResults
        result.toolApprovalRequests = allApprovalRequests
        result.toolApprovalResponses = allApprovalResponses
        result.steps = steps
        return result
    }

    public static func generateText(
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
        retryPolicy: AIRetryPolicy = .default,
        toolChoice: JSONValue? = nil,
        includeRawChunks: Bool = false,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        abortSignal: AIAbortSignal? = nil,
        telemetry: AITelemetryOptions? = nil
    ) async throws -> TextGenerationResult {
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
            return try await generateText(model: model, request: request, retryPolicy: retryPolicy, telemetry: telemetry)
        }

        return try await generateText(
            model: model,
            request: request,
            executableTools: executableTools,
            maxSteps: maxSteps,
            stopWhen: stopWhen,
            prepareStep: prepareStep,
            toolApproval: toolApproval,
            retryPolicy: retryPolicy,
            telemetry: telemetry
        )
    }

    public static func generateText<FinalOutput: Sendable, PartialOutput: Sendable>(
        model: any LanguageModel,
        request: LanguageModelRequest,
        output: AIOutput<FinalOutput, PartialOutput>,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) async throws -> AIOutputGenerationResult<FinalOutput> {
        try await output.generateFromRequest(
            model,
            request,
            retryPolicy,
            telemetry,
            jsonInstruction,
            repairText
        )
    }

    public static func generateText<FinalOutput: Sendable, PartialOutput: Sendable>(
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
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) async throws -> AIOutputGenerationResult<FinalOutput> {
        try await generateText(
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
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            jsonInstruction: jsonInstruction,
            repairText: repairText
        )
    }

}
