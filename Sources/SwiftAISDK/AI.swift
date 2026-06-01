import Foundation

public enum AI {
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
            output: textGenerationTelemetryOutput,
            usage: { $0.usage },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata },
            wrapLanguageModelCall: true
        ) {
            try await model.generate(request)
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
            let executableCalls = result.toolCalls.filter { !$0.providerExecuted && toolsByName[$0.name] != nil }

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
            headers: headers
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

    public static func generateObject<Object: Decodable & Sendable>(
        model: any LanguageModel,
        request: LanguageModelRequest,
        as type: Object.Type = Object.self,
        schema: JSONValue? = nil,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<Object>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) async throws -> ObjectGenerationResult<Object> {
        let objectRequest = objectRequest(
            from: request,
            schema: schema,
            schemaName: schemaName,
            schemaDescription: schemaDescription,
            jsonInstruction: jsonInstruction
        )

        return try await generateObjectResult(
            model: model,
            request: objectRequest,
            outputKind: "object",
            schema: schema,
            schemaName: schemaName,
            schemaDescription: schemaDescription,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks
        ) { text, providerID in
            try await parseObject(
                Object.self,
                from: text,
                schema: schema,
                repairText: repairText,
                providerID: providerID
            )
        }
    }

    public static func generateObject<Object: Decodable & Sendable>(
        model: any LanguageModel,
        prompt: String,
        as type: Object.Type = Object.self,
        schema: JSONValue? = nil,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
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
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<Object>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) async throws -> ObjectGenerationResult<Object> {
        try await generateObject(
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
                responseFormat: .json(schema: schema, name: schemaName, description: schemaDescription),
                reasoning: reasoning,
                providerOptions: providerOptions,
                extraBody: extraBody,
                headers: headers
            ),
            as: Object.self,
            schema: schema,
            schemaName: schemaName,
            schemaDescription: schemaDescription,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks,
            jsonInstruction: jsonInstruction,
            repairText: repairText
        )
    }

    public static func generateObject<Schema: AIObjectSchema>(
        model: any LanguageModel,
        request: LanguageModelRequest,
        schema: Schema,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<Schema.Output>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) async throws -> ObjectGenerationResult<Schema.Output> {
        try await generateObject(
            model: model,
            request: request,
            as: Schema.Output.self,
            schema: schema.jsonSchema,
            schemaName: schemaName ?? schema.name,
            schemaDescription: schemaDescription ?? schema.description,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks,
            jsonInstruction: jsonInstruction,
            repairText: repairText
        )
    }

    public static func generateObject<Schema: AIObjectSchema>(
        model: any LanguageModel,
        prompt: String,
        schema: Schema,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
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
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<Schema.Output>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) async throws -> ObjectGenerationResult<Schema.Output> {
        try await generateObject(
            model: model,
            prompt: prompt,
            as: Schema.Output.self,
            schema: schema.jsonSchema,
            schemaName: schemaName ?? schema.name,
            schemaDescription: schemaDescription ?? schema.description,
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
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks,
            jsonInstruction: jsonInstruction,
            repairText: repairText
        )
    }

    public static func generateObjectArray<Element: Decodable & Sendable>(
        model: any LanguageModel,
        request: LanguageModelRequest,
        as type: Element.Type = Element.self,
        elementSchema: JSONValue,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<[Element]>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) async throws -> ObjectGenerationResult<[Element]> {
        let schema = arrayOutputSchema(elementSchema: elementSchema)
        let objectRequest = objectRequest(
            from: request,
            schema: schema,
            schemaName: schemaName,
            schemaDescription: schemaDescription,
            jsonInstruction: jsonInstruction
        )

        return try await generateObjectResult(
            model: model,
            request: objectRequest,
            outputKind: "array",
            schema: schema,
            schemaName: schemaName,
            schemaDescription: schemaDescription,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks
        ) { text, providerID in
            try await parseObjectArray(
                Element.self,
                from: text,
                elementSchema: elementSchema,
                repairText: repairText,
                providerID: providerID
            )
        }
    }

    public static func generateObjectArray<Element: Decodable & Sendable>(
        model: any LanguageModel,
        prompt: String,
        as type: Element.Type = Element.self,
        elementSchema: JSONValue,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
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
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<[Element]>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) async throws -> ObjectGenerationResult<[Element]> {
        try await generateObjectArray(
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
                responseFormat: .json(schema: arrayOutputSchema(elementSchema: elementSchema), name: schemaName, description: schemaDescription),
                reasoning: reasoning,
                providerOptions: providerOptions,
                extraBody: extraBody,
                headers: headers
            ),
            as: Element.self,
            elementSchema: elementSchema,
            schemaName: schemaName,
            schemaDescription: schemaDescription,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks,
            jsonInstruction: jsonInstruction,
            repairText: repairText
        )
    }

    public static func generateObjectArray<ElementSchema: AIObjectSchema>(
        model: any LanguageModel,
        request: LanguageModelRequest,
        elementSchema: ElementSchema,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<[ElementSchema.Output]>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) async throws -> ObjectGenerationResult<[ElementSchema.Output]> {
        try await generateObjectArray(
            model: model,
            request: request,
            as: ElementSchema.Output.self,
            elementSchema: elementSchema.jsonSchema,
            schemaName: schemaName ?? elementSchema.name,
            schemaDescription: schemaDescription ?? elementSchema.description,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks,
            jsonInstruction: jsonInstruction,
            repairText: repairText
        )
    }

    public static func generateObjectArray<ElementSchema: AIObjectSchema>(
        model: any LanguageModel,
        prompt: String,
        elementSchema: ElementSchema,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
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
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<[ElementSchema.Output]>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) async throws -> ObjectGenerationResult<[ElementSchema.Output]> {
        try await generateObjectArray(
            model: model,
            prompt: prompt,
            as: ElementSchema.Output.self,
            elementSchema: elementSchema.jsonSchema,
            schemaName: schemaName ?? elementSchema.name,
            schemaDescription: schemaDescription ?? elementSchema.description,
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
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks,
            jsonInstruction: jsonInstruction,
            repairText: repairText
        )
    }

    public static func generateEnum(
        model: any LanguageModel,
        request: LanguageModelRequest,
        values: [String],
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<String>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) async throws -> ObjectGenerationResult<String> {
        guard !values.isEmpty else {
            throw AIError.invalidArgument(argument: "values", message: "Enum values are required.")
        }
        let schema = enumOutputSchema(values: values)
        let objectRequest = objectRequest(
            from: request,
            schema: schema,
            schemaName: nil,
            schemaDescription: nil,
            jsonInstruction: jsonInstruction
        )

        return try await generateObjectResult(
            model: model,
            request: objectRequest,
            outputKind: "enum",
            schema: schema,
            schemaName: nil,
            schemaDescription: nil,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks
        ) { text, providerID in
            try await parseEnum(
                from: text,
                values: values,
                repairText: repairText,
                providerID: providerID
            )
        }
    }

    public static func generateEnum(
        model: any LanguageModel,
        prompt: String,
        values: [String],
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
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<String>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) async throws -> ObjectGenerationResult<String> {
        try await generateEnum(
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
                responseFormat: .json(schema: enumOutputSchema(values: values)),
                reasoning: reasoning,
                providerOptions: providerOptions,
                extraBody: extraBody,
                headers: headers
            ),
            values: values,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks,
            jsonInstruction: jsonInstruction,
            repairText: repairText
        )
    }

    public static func generateJSON(
        model: any LanguageModel,
        request: LanguageModelRequest,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<JSONValue>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) async throws -> ObjectGenerationResult<JSONValue> {
        let objectRequest = objectRequest(
            from: request,
            schema: nil,
            schemaName: nil,
            schemaDescription: nil,
            jsonInstruction: jsonInstruction
        )

        return try await generateObjectResult(
            model: model,
            request: objectRequest,
            outputKind: "no-schema",
            schema: nil,
            schemaName: nil,
            schemaDescription: nil,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks
        ) { text, providerID in
            try await parseJSONValueObject(
                from: text,
                repairText: repairText,
                providerID: providerID
            )
        }
    }

    public static func generateJSON(
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
        reasoning: String? = nil,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<JSONValue>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) async throws -> ObjectGenerationResult<JSONValue> {
        try await generateJSON(
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
                responseFormat: .json(),
                reasoning: reasoning,
                providerOptions: providerOptions,
                extraBody: extraBody,
                headers: headers
            ),
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks,
            jsonInstruction: jsonInstruction,
            repairText: repairText
        )
    }

    public static func streamText(
        model: any LanguageModel,
        request: LanguageModelRequest,
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil
    ) -> AsyncThrowingStream<LanguageStreamPart, Error> {
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
                input: languageRequestTelemetryInput(request),
                retryPolicy: retryPolicy,
                telemetry: telemetry
            )
        }
        return streamTextWithTelemetry(
            makeStream: {
                streamWithTimeout(
                    model.stream(request),
                    timeoutNanoseconds: timeoutNanoseconds ?? retryPolicy.timeoutNanoseconds
                )
            },
            operationID: "ai.streamText",
            providerID: model.providerID,
            modelID: model.modelID,
            input: languageRequestTelemetryInput(request),
            retryPolicy: retryPolicy,
            telemetry: telemetry
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
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil
    ) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        let stream = AsyncThrowingStream<LanguageStreamPart, Error> { continuation in
            let task = Task {
                do {
                    guard !executableTools.isEmpty || prepareStep != nil else {
                        for try await part in streamText(
                            model: model,
                            request: request,
                            timeoutNanoseconds: nil,
                            retryPolicy: retryPolicy
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
                    let toolTelemetry = AIToolLoopTelemetryContext(
                        operationID: "ai.streamText",
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
                        let step = try await forwardLanguageStream(
                            streamText(model: stepModel, request: stepRequest, retryPolicy: retryPolicy),
                            to: continuation,
                            toolsByName: toolsByName
                        )
                        let executableCalls = step.toolCalls.filter { !$0.providerExecuted && toolsByName[$0.name] != nil }

                        guard !executableCalls.isEmpty else {
                            let completedStep = step.toolStep(
                                index: index,
                                toolResults: [],
                                approvalRequests: [],
                                approvalResponses: []
                            )
                            await toolTelemetry.recordStepEnd(completedStep)
                            continuation.finish()
                            return
                        }

                        let toolExecution = try await executeToolCalls(
                            executableCalls,
                            toolsByName: toolsByName,
                            request: stepRequest,
                            toolApproval: toolApproval,
                            telemetry: toolTelemetry,
                            stepIndex: index
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
                        let assistantMessage = AIMessage.assistant(
                            text: step.text,
                            toolCalls: step.toolCalls,
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
            telemetry: telemetry
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
        toolChoice: JSONValue? = nil,
        includeRawChunks: Bool = false,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil
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
            headers: headers
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
            timeoutNanoseconds: timeoutNanoseconds,
            retryPolicy: retryPolicy,
            telemetry: telemetry
        )
    }

    public static func streamObject<Object: Decodable & Sendable>(
        model: any LanguageModel,
        request: LanguageModelRequest,
        as type: Object.Type = Object.self,
        schema: JSONValue? = nil,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
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
                    makeStream(),
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

    public static func streamObject<Object: Decodable & Sendable>(
        model: any LanguageModel,
        prompt: String,
        as type: Object.Type = Object.self,
        schema: JSONValue? = nil,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
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
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<Object>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) -> AsyncThrowingStream<ObjectStreamPart<Object>, Error> {
        streamObject(
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
                responseFormat: .json(schema: schema, name: schemaName, description: schemaDescription),
                reasoning: reasoning,
                providerOptions: providerOptions,
                extraBody: extraBody,
                headers: headers
            ),
            as: Object.self,
            schema: schema,
            schemaName: schemaName,
            schemaDescription: schemaDescription,
            timeoutNanoseconds: timeoutNanoseconds,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks,
            jsonInstruction: jsonInstruction,
            repairText: repairText
        )
    }

    public static func streamObject<Schema: AIObjectSchema>(
        model: any LanguageModel,
        request: LanguageModelRequest,
        schema: Schema,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<Schema.Output>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) -> AsyncThrowingStream<ObjectStreamPart<Schema.Output>, Error> {
        streamObject(
            model: model,
            request: request,
            as: Schema.Output.self,
            schema: schema.jsonSchema,
            schemaName: schemaName ?? schema.name,
            schemaDescription: schemaDescription ?? schema.description,
            timeoutNanoseconds: timeoutNanoseconds,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks,
            jsonInstruction: jsonInstruction,
            repairText: repairText
        )
    }

    public static func streamObject<Schema: AIObjectSchema>(
        model: any LanguageModel,
        prompt: String,
        schema: Schema,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
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
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<Schema.Output>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) -> AsyncThrowingStream<ObjectStreamPart<Schema.Output>, Error> {
        streamObject(
            model: model,
            prompt: prompt,
            as: Schema.Output.self,
            schema: schema.jsonSchema,
            schemaName: schemaName ?? schema.name,
            schemaDescription: schemaDescription ?? schema.description,
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
            timeoutNanoseconds: timeoutNanoseconds,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks,
            jsonInstruction: jsonInstruction,
            repairText: repairText
        )
    }

    public static func streamObjectArray<Element: Decodable & Sendable>(
        model: any LanguageModel,
        request: LanguageModelRequest,
        as type: Element.Type = Element.self,
        elementSchema: JSONValue,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<[Element]>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) -> AsyncThrowingStream<ObjectStreamPart<[Element]>, Error> {
        let schema = arrayOutputSchema(elementSchema: elementSchema)
        return mapObjectStream(
            streamObject(
                model: model,
                request: request,
                as: AIObjectArrayEnvelope<Element>.self,
                schema: schema,
                schemaName: schemaName,
                schemaDescription: schemaDescription,
                timeoutNanoseconds: timeoutNanoseconds,
                retryPolicy: retryPolicy,
                telemetry: telemetry,
                callbacks: arrayEnvelopeCallbacks(callbacks),
                jsonInstruction: jsonInstruction,
                repairText: repairText
            ),
            transform: arrayStreamPart
        )
    }

    public static func streamObjectArray<Element: Decodable & Sendable>(
        model: any LanguageModel,
        prompt: String,
        as type: Element.Type = Element.self,
        elementSchema: JSONValue,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
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
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<[Element]>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) -> AsyncThrowingStream<ObjectStreamPart<[Element]>, Error> {
        streamObjectArray(
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
                responseFormat: .json(schema: arrayOutputSchema(elementSchema: elementSchema), name: schemaName, description: schemaDescription),
                reasoning: reasoning,
                providerOptions: providerOptions,
                extraBody: extraBody,
                headers: headers
            ),
            as: Element.self,
            elementSchema: elementSchema,
            schemaName: schemaName,
            schemaDescription: schemaDescription,
            timeoutNanoseconds: timeoutNanoseconds,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks,
            jsonInstruction: jsonInstruction,
            repairText: repairText
        )
    }

    public static func streamObjectArray<ElementSchema: AIObjectSchema>(
        model: any LanguageModel,
        request: LanguageModelRequest,
        elementSchema: ElementSchema,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<[ElementSchema.Output]>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) -> AsyncThrowingStream<ObjectStreamPart<[ElementSchema.Output]>, Error> {
        streamObjectArray(
            model: model,
            request: request,
            as: ElementSchema.Output.self,
            elementSchema: elementSchema.jsonSchema,
            schemaName: schemaName ?? elementSchema.name,
            schemaDescription: schemaDescription ?? elementSchema.description,
            timeoutNanoseconds: timeoutNanoseconds,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks,
            jsonInstruction: jsonInstruction,
            repairText: repairText
        )
    }

    public static func streamObjectArray<ElementSchema: AIObjectSchema>(
        model: any LanguageModel,
        prompt: String,
        elementSchema: ElementSchema,
        schemaName: String? = nil,
        schemaDescription: String? = nil,
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
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<[ElementSchema.Output]>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) -> AsyncThrowingStream<ObjectStreamPart<[ElementSchema.Output]>, Error> {
        streamObjectArray(
            model: model,
            prompt: prompt,
            as: ElementSchema.Output.self,
            elementSchema: elementSchema.jsonSchema,
            schemaName: schemaName ?? elementSchema.name,
            schemaDescription: schemaDescription ?? elementSchema.description,
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
            timeoutNanoseconds: timeoutNanoseconds,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks,
            jsonInstruction: jsonInstruction,
            repairText: repairText
        )
    }

    public static func streamEnum(
        model: any LanguageModel,
        request: LanguageModelRequest,
        values: [String],
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<String>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) -> AsyncThrowingStream<ObjectStreamPart<String>, Error> {
        guard !values.isEmpty else {
            return failingPartStream(AIError.invalidArgument(argument: "values", message: "Enum values are required."))
        }
        let schema = enumOutputSchema(values: values)
        return mapObjectStream(
            streamObject(
                model: model,
                request: request,
                as: AIEnumEnvelope.self,
                schema: schema,
                timeoutNanoseconds: timeoutNanoseconds,
                retryPolicy: retryPolicy,
                telemetry: telemetry,
                callbacks: enumEnvelopeCallbacks(callbacks),
                jsonInstruction: jsonInstruction,
                repairText: repairText
            ),
            transform: enumStreamPart
        )
    }

    public static func streamEnum(
        model: any LanguageModel,
        prompt: String,
        values: [String],
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
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<String>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) -> AsyncThrowingStream<ObjectStreamPart<String>, Error> {
        streamEnum(
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
                responseFormat: .json(schema: enumOutputSchema(values: values)),
                reasoning: reasoning,
                providerOptions: providerOptions,
                extraBody: extraBody,
                headers: headers
            ),
            values: values,
            timeoutNanoseconds: timeoutNanoseconds,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks,
            jsonInstruction: jsonInstruction,
            repairText: repairText
        )
    }

    public static func streamJSON(
        model: any LanguageModel,
        request: LanguageModelRequest,
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<JSONValue>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) -> AsyncThrowingStream<ObjectStreamPart<JSONValue>, Error> {
        streamObject(
            model: model,
            request: request,
            as: JSONValue.self,
            timeoutNanoseconds: timeoutNanoseconds,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks,
            jsonInstruction: jsonInstruction,
            repairText: repairText
        )
    }

    public static func streamJSON(
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
        reasoning: String? = nil,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        timeoutNanoseconds: UInt64? = nil,
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil,
        callbacks: AIObjectGenerationCallbacks<JSONValue>? = nil,
        jsonInstruction: AIJSONInstruction? = nil,
        repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)? = nil
    ) -> AsyncThrowingStream<ObjectStreamPart<JSONValue>, Error> {
        streamJSON(
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
                responseFormat: .json(),
                reasoning: reasoning,
                providerOptions: providerOptions,
                extraBody: extraBody,
                headers: headers
            ),
            timeoutNanoseconds: timeoutNanoseconds,
            retryPolicy: retryPolicy,
            telemetry: telemetry,
            callbacks: callbacks,
            jsonInstruction: jsonInstruction,
            repairText: repairText
        )
    }

    public static func embed(model: any EmbeddingModel, value: String, dimensions: Int? = nil, providerOptions: [String: JSONValue] = [:], extraBody: [String: JSONValue] = [:], headers: [String: String] = [:], retryPolicy: AIRetryPolicy = .default, telemetry: AITelemetryOptions? = nil) async throws -> EmbeddingResult {
        try await embed(model: model, request: EmbeddingRequest(values: [value], dimensions: dimensions, providerOptions: providerOptions, extraBody: extraBody, headers: headers), retryPolicy: retryPolicy, telemetry: telemetry)
    }

    public static func embed(model: any EmbeddingModel, request: EmbeddingRequest, retryPolicy: AIRetryPolicy = .default, telemetry: AITelemetryOptions? = nil) async throws -> EmbeddingResult {
        try await withTelemetry(
            operationID: request.values.count == 1 ? "ai.embed" : "ai.embedMany",
            providerID: model.providerID,
            modelID: model.modelID,
            input: embeddingRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            output: embeddingTelemetryOutput,
            usage: { $0.usage },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata }
        ) {
            try await model.embed(request)
        }
    }

    public static func embedMany(
        model: any EmbeddingModel,
        values: [String],
        dimensions: Int? = nil,
        chunkSize: Int? = nil,
        providerOptions: [String: JSONValue] = [:],
        extraBody: [String: JSONValue] = [:],
        headers: [String: String] = [:],
        retryPolicy: AIRetryPolicy = .default,
        telemetry: AITelemetryOptions? = nil
    ) async throws -> EmbeddingResult {
        guard let chunkSize, chunkSize > 0, values.count > chunkSize else {
            return try await embed(model: model, request: EmbeddingRequest(values: values, dimensions: dimensions, providerOptions: providerOptions, extraBody: extraBody, headers: headers), retryPolicy: retryPolicy, telemetry: telemetry)
        }

        let request = EmbeddingRequest(values: values, dimensions: dimensions, providerOptions: providerOptions, extraBody: extraBody, headers: headers)
        return try await withTelemetry(
            operationID: "ai.embedMany",
            providerID: model.providerID,
            modelID: model.modelID,
            input: embeddingRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            output: embeddingTelemetryOutput,
            usage: { $0.usage },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata }
        ) {
            var embeddings: [[Double]] = []
            var usage: TokenUsage?
            var rawValues: [JSONValue] = []
            var warnings: [AIWarning] = []
            var providerMetadata: [String: JSONValue] = [:]
            var responseMetadata = AIResponseMetadata()

            for chunk in values.chunked(size: chunkSize) {
                let result = try await withRetry(policy: retryPolicy) {
                    try await model.embed(EmbeddingRequest(values: chunk, dimensions: dimensions, providerOptions: providerOptions, extraBody: extraBody, headers: headers))
                }
                embeddings.append(contentsOf: result.embeddings)
                usage = sumTokenUsage(usage, result.usage)
                rawValues.append(result.rawValue)
                warnings.append(contentsOf: result.warnings)
                providerMetadata.merge(result.providerMetadata) { _, new in new }
                if responseMetadata == AIResponseMetadata() {
                    responseMetadata = result.responseMetadata
                }
            }

            return EmbeddingResult(
                embeddings: embeddings,
                usage: usage,
                rawValue: .array(rawValues),
                warnings: warnings,
                providerMetadata: providerMetadata,
                responseMetadata: responseMetadata
            )
        }
    }

    public static func generateImage(model: any ImageModel, request: ImageGenerationRequest, retryPolicy: AIRetryPolicy = .default, telemetry: AITelemetryOptions? = nil) async throws -> ImageGenerationResult {
        try await withTelemetry(
            operationID: "ai.generateImage",
            providerID: model.providerID,
            modelID: model.modelID,
            input: imageRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            output: imageTelemetryOutput,
            usage: { $0.usage },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata }
        ) {
            try await model.generateImage(request)
        }
    }

    public static func generateImage(model: any ImageModel, prompt: String, size: String? = nil, aspectRatio: String? = nil, seed: Int? = nil, count: Int? = nil, files: [ImageInputFile] = [], mask: ImageInputFile? = nil, providerOptions: [String: JSONValue] = [:], extraBody: [String: JSONValue] = [:], headers: [String: String] = [:], retryPolicy: AIRetryPolicy = .default, telemetry: AITelemetryOptions? = nil) async throws -> ImageGenerationResult {
        try await generateImage(model: model, request: ImageGenerationRequest(prompt: prompt, size: size, aspectRatio: aspectRatio, seed: seed, count: count, files: files, mask: mask, providerOptions: providerOptions, extraBody: extraBody, headers: headers), retryPolicy: retryPolicy, telemetry: telemetry)
    }

    public static func transcribe(model: any TranscriptionModel, request: AudioTranscriptionRequest, retryPolicy: AIRetryPolicy = .default, telemetry: AITelemetryOptions? = nil) async throws -> TranscriptionResult {
        try await withTelemetry(
            operationID: "ai.transcribe",
            providerID: model.providerID,
            modelID: model.modelID,
            input: transcriptionRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            output: transcriptionTelemetryOutput,
            usage: { _ in nil },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata }
        ) {
            try await model.transcribe(request)
        }
    }

    public static func generateSpeech(model: any SpeechModel, request: SpeechRequest, retryPolicy: AIRetryPolicy = .default, telemetry: AITelemetryOptions? = nil) async throws -> SpeechResult {
        try await withTelemetry(
            operationID: "ai.generateSpeech",
            providerID: model.providerID,
            modelID: model.modelID,
            input: speechRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            output: speechTelemetryOutput,
            usage: { _ in nil },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata }
        ) {
            try await model.speak(request)
        }
    }

    public static func generateVideo(model: any VideoModel, request: VideoGenerationRequest, retryPolicy: AIRetryPolicy = .default, telemetry: AITelemetryOptions? = nil) async throws -> VideoGenerationResult {
        try await withTelemetry(
            operationID: "ai.generateVideo",
            providerID: model.providerID,
            modelID: model.modelID,
            input: videoRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            output: videoTelemetryOutput,
            usage: { _ in nil },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata }
        ) {
            try await model.generateVideo(request)
        }
    }

    public static func rerank(model: any RerankingModel, request: RerankingRequest, retryPolicy: AIRetryPolicy = .default, telemetry: AITelemetryOptions? = nil) async throws -> RerankingResult {
        try await withTelemetry(
            operationID: "ai.rerank",
            providerID: model.providerID,
            modelID: model.modelID,
            input: rerankingRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            output: rerankingTelemetryOutput,
            usage: { _ in nil },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata }
        ) {
            try await model.rerank(request)
        }
    }

    public static func uploadFile(client: any AIFileClient, request: FileUploadRequest, retryPolicy: AIRetryPolicy = .default, telemetry: AITelemetryOptions? = nil) async throws -> FileUploadResult {
        try await withTelemetry(
            operationID: "ai.uploadFile",
            providerID: client.providerID,
            modelID: nil,
            input: fileUploadRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            output: fileUploadTelemetryOutput,
            usage: { _ in nil },
            warnings: { _ in [] },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { $0.responseMetadata }
        ) {
            try await client.uploadFile(request)
        }
    }

    public static func uploadSkill(client: any AISkillsClient, request: SkillUploadRequest, retryPolicy: AIRetryPolicy = .default, telemetry: AITelemetryOptions? = nil) async throws -> SkillUploadResult {
        try await withTelemetry(
            operationID: "ai.uploadSkill",
            providerID: client.providerID,
            modelID: nil,
            input: skillUploadRequestTelemetryInput(request),
            telemetry: telemetry,
            retryPolicy: retryPolicy,
            output: skillUploadTelemetryOutput,
            usage: { _ in nil },
            warnings: { $0.warnings },
            providerMetadata: { $0.providerMetadata },
            responseMetadata: { _ in AIResponseMetadata() }
        ) {
            try await client.uploadSkill(request)
        }
    }
}

private func sumTokenUsage(_ lhs: TokenUsage?, _ rhs: TokenUsage?) -> TokenUsage? {
    guard lhs != nil || rhs != nil else { return nil }
    return TokenUsage(
        inputTokens: optionalSum(lhs?.inputTokens, rhs?.inputTokens),
        outputTokens: optionalSum(lhs?.outputTokens, rhs?.outputTokens),
        totalTokens: optionalSum(lhs?.totalTokens, rhs?.totalTokens)
    )
}

private func optionalSum(_ lhs: Int?, _ rhs: Int?) -> Int? {
    switch (lhs, rhs) {
    case let (lhs?, rhs?):
        return lhs + rhs
    case let (lhs?, nil):
        return lhs
    case let (nil, rhs?):
        return rhs
    case (nil, nil):
        return nil
    }
}

private func isCancellationTelemetryError(_ error: Error) -> Bool {
    if error is CancellationError {
        return true
    }
    if let retryError = error as? AIRetryError, retryError.reason == .cancelled {
        return true
    }
    return false
}

private struct LanguageStreamToolStep {
    var text = ""
    var reasoning = ""
    var finishReason: String?
    var usage: TokenUsage?
    var toolCalls: [AIToolCall] = []
    var approvalRequests: [AIToolApprovalRequest] = []
    var approvalResponses: [AIToolApprovalResponse] = []
    var warnings: [AIWarning] = []
    var providerMetadata: [String: JSONValue] = [:]
    var responseMetadata = AIResponseMetadata()

    mutating func record(_ part: LanguageStreamPart) {
        switch part {
        case let .streamStart(partWarnings):
            warnings.append(contentsOf: partWarnings)
        case let .textDelta(delta):
            text += delta
        case let .textDeltaPart(_, delta, _):
            text += delta
        case let .reasoningDelta(delta):
            reasoning += delta
        case let .reasoningDeltaPart(_, delta, _):
            reasoning += delta
        case let .toolCall(toolCall):
            toolCalls.append(toolCall)
        case let .toolApprovalRequest(approvalRequest):
            approvalRequests.append(approvalRequest)
        case let .toolApprovalResponse(approvalResponse):
            approvalResponses.append(approvalResponse)
        case let .metadata(metadata):
            providerMetadata.merge(metadata) { _, new in new }
        case let .responseMetadata(metadata):
            responseMetadata = metadata
        case let .finish(reason, partUsage):
            finishReason = reason
            usage = partUsage
        case let .finishMetadata(reason, partUsage, metadata):
            finishReason = reason
            usage = partUsage
            providerMetadata.merge(metadata) { _, new in new }
        default:
            break
        }
    }

    func toolStep(
        index: Int,
        toolResults: [AIToolResult],
        approvalRequests: [AIToolApprovalRequest],
        approvalResponses: [AIToolApprovalResponse]
    ) -> AIToolStep {
        AIToolStep(
            index: index,
            text: text,
            reasoning: reasoning,
            finishReason: finishReason,
            usage: usage,
            toolCalls: toolCalls,
            toolResults: toolResults,
            toolApprovalRequests: self.approvalRequests + approvalRequests,
            toolApprovalResponses: self.approvalResponses + approvalResponses,
            providerMetadata: providerMetadata,
            responseMetadata: responseMetadata
        )
    }
}

private func forwardLanguageStream(
    _ stream: AsyncThrowingStream<LanguageStreamPart, Error>,
    to continuation: AsyncThrowingStream<LanguageStreamPart, Error>.Continuation,
    toolsByName: [String: AITool] = [:]
) async throws -> LanguageStreamToolStep {
    var step = LanguageStreamToolStep()
    for try await part in stream {
        try Task.checkCancellation()
        let annotatedPart = annotateStreamPart(part, toolsByName: toolsByName)
        step.record(annotatedPart)
        continuation.yield(annotatedPart)
    }
    return step
}

private func isStopConditionMet(_ stopConditions: [AIStopCondition], steps: [AIToolStep]) async throws -> Bool {
    let context = AIStopConditionContext(steps: steps)
    for condition in stopConditions {
        if try await condition.evaluate(context) {
            return true
        }
    }
    return false
}

private struct AIRetryAttemptTelemetry: Sendable {
    var attempt: Int
    var maxRetries: Int
    var errorDescription: String
    var delayNanoseconds: UInt64
}

private struct AITelemetryDispatcher: Sendable {
    var options: AITelemetryOptions?
    var integrations: [any AITelemetryIntegration]

    init(options: AITelemetryOptions?) {
        self.options = options
        if options?.isEnabled == false {
            integrations = []
        } else {
            integrations = options?.integrations ?? AITelemetry.registeredIntegrations()
        }
    }

    var isEnabled: Bool {
        !integrations.isEmpty
    }

    func record(_ event: AITelemetryEvent) async {
        guard isEnabled else { return }
        for integration in integrations {
            await integration.record(event)
        }
    }

    func executeLanguageModelCall<Output: Sendable>(
        callID: String,
        operationID: String,
        providerID: String,
        modelID: String?,
        operation: @escaping @Sendable () async throws -> Output
    ) async throws -> Output {
        guard isEnabled else {
            return try await operation()
        }

        var execute = operation
        for integration in integrations {
            let innerExecute = execute
            execute = {
                try await integration.executeLanguageModelCall(AITelemetryLanguageModelCallContext(
                    callID: callID,
                    operationID: operationID,
                    providerID: providerID,
                    modelID: modelID,
                    execute: innerExecute
                ))
            }
        }
        return try await execute()
    }

    func executeTool<Output: Sendable>(
        callID: String,
        toolCallID: String,
        toolName: String,
        operation: @escaping @Sendable () async throws -> Output
    ) async throws -> Output {
        guard isEnabled else {
            return try await operation()
        }

        var execute = operation
        for integration in integrations {
            let innerExecute = execute
            execute = {
                try await integration.executeTool(AITelemetryToolExecutionContext(
                    callID: callID,
                    toolCallID: toolCallID,
                    toolName: toolName,
                    execute: innerExecute
                ))
            }
        }
        return try await execute()
    }
}

private actor AIStreamTerminalState {
    private var didRecordTerminalEvent = false

    func claimTerminalEvent() -> Bool {
        guard !didRecordTerminalEvent else { return false }
        didRecordTerminalEvent = true
        return true
    }
}

private struct AIToolLoopTelemetryContext: Sendable {
    var dispatcher: AITelemetryDispatcher
    var callID: String
    var operationID: String
    var providerID: String
    var modelID: String?
    var telemetry: AITelemetryOptions?
    var started: UInt64

    init(
        operationID: String,
        providerID: String,
        modelID: String?,
        telemetry: AITelemetryOptions?
    ) {
        self.dispatcher = AITelemetryDispatcher(options: telemetry)
        self.callID = UUID().uuidString
        self.operationID = operationID
        self.providerID = providerID
        self.modelID = modelID
        self.telemetry = telemetry
        self.started = DispatchTime.now().uptimeNanoseconds
    }

    func recordStepStart(
        index: Int,
        maxSteps: Int,
        model: any LanguageModel,
        request: LanguageModelRequest,
        tools: [AITool]
    ) async {
        await dispatcher.record(telemetryEvent(
            kind: .stepStart,
            callID: callID,
            operationID: "\(operationID).step",
            providerID: model.providerID,
            modelID: model.modelID,
            options: telemetry,
            durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
            input: stepTelemetryInput(index: index, maxSteps: maxSteps, request: request, tools: tools)
        ))
    }

    func recordStepEnd(_ step: AIToolStep) async {
        await dispatcher.record(telemetryEvent(
            kind: .stepEnd,
            callID: callID,
            operationID: "\(operationID).step",
            providerID: providerID,
            modelID: modelID,
            options: telemetry,
            durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
            output: toolStepTelemetryOutput(step),
            usage: step.usage,
            providerMetadata: step.providerMetadata,
            responseMetadata: step.responseMetadata
        ))
    }

    func recordToolStart(
        stepIndex: Int,
        call: AIToolCall,
        tool: AITool
    ) async {
        await dispatcher.record(telemetryEvent(
            kind: .toolStart,
            callID: callID,
            operationID: "\(operationID).tool",
            providerID: providerID,
            modelID: modelID,
            options: telemetry,
            durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
            input: toolExecutionTelemetryInput(stepIndex: stepIndex, call: call, tool: tool)
        ))
    }

    func recordToolEnd(
        stepIndex: Int,
        call: AIToolCall,
        status: String,
        arguments: JSONValue?,
        result: AIToolResult? = nil,
        approvalRequest: AIToolApprovalRequest? = nil,
        approvalResponse: AIToolApprovalResponse? = nil
    ) async {
        await dispatcher.record(telemetryEvent(
            kind: .toolEnd,
            callID: callID,
            operationID: "\(operationID).tool",
            providerID: providerID,
            modelID: modelID,
            options: telemetry,
            durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
            output: toolExecutionTelemetryOutput(
                stepIndex: stepIndex,
                call: call,
                status: status,
                arguments: arguments,
                result: result,
                approvalRequest: approvalRequest,
                approvalResponse: approvalResponse
            ),
            providerMetadata: result?.providerMetadata ?? call.providerMetadata
        ))
    }

    func recordToolError(
        stepIndex: Int,
        call: AIToolCall,
        error: Error
    ) async {
        await dispatcher.record(telemetryEvent(
            kind: .toolError,
            callID: callID,
            operationID: "\(operationID).tool",
            providerID: providerID,
            modelID: modelID,
            options: telemetry,
            durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
            input: .object([
                "stepNumber": .number(Double(stepIndex)),
                "toolCall": toolCallTelemetryJSON(call)
            ]),
            errorDescription: String(describing: error)
        ))
    }

    func executeTool<Output: Sendable>(
        call: AIToolCall,
        operation: @escaping @Sendable () async throws -> Output
    ) async throws -> Output {
        try await dispatcher.executeTool(
            callID: callID,
            toolCallID: call.id,
            toolName: call.name,
            operation: operation
        )
    }
}

private func withTelemetry<Output: Sendable>(
    operationID: String,
    providerID: String,
    modelID: String?,
    input: JSONValue?,
    telemetry: AITelemetryOptions?,
    retryPolicy: AIRetryPolicy,
    callID providedCallID: String? = nil,
    output: @escaping @Sendable (Output) -> JSONValue?,
    usage: @escaping @Sendable (Output) -> TokenUsage?,
    warnings: @escaping @Sendable (Output) -> [AIWarning],
    providerMetadata: @escaping @Sendable (Output) -> [String: JSONValue],
    responseMetadata: @escaping @Sendable (Output) -> AIResponseMetadata,
    wrapLanguageModelCall: Bool = false,
    operation: @escaping @Sendable () async throws -> Output
) async throws -> Output {
    let dispatcher = AITelemetryDispatcher(options: telemetry)
    guard dispatcher.isEnabled else {
        let result = try await withRetry(policy: retryPolicy, operation: operation)
        await AIWarningLogging.logWarnings(warnings(result), providerID: providerID, modelID: modelID)
        return result
    }

    let callID = providedCallID ?? UUID().uuidString
    let started = DispatchTime.now().uptimeNanoseconds
    await dispatcher.record(telemetryEvent(
        kind: .start,
        callID: callID,
        operationID: operationID,
        providerID: providerID,
        modelID: modelID,
        options: telemetry,
        maxRetries: retryPolicy.maxRetries,
        input: input
    ))

    do {
        let wrappedOperation: @Sendable () async throws -> Output = {
            if wrapLanguageModelCall {
                return try await dispatcher.executeLanguageModelCall(
                    callID: callID,
                    operationID: operationID,
                    providerID: providerID,
                    modelID: modelID,
                    operation: operation
                )
            }
            return try await operation()
        }
        let result = try await withRetry(policy: retryPolicy, onRetry: { retry in
            await dispatcher.record(telemetryEvent(
                kind: .retry,
                callID: callID,
                operationID: operationID,
                providerID: providerID,
                modelID: modelID,
                options: telemetry,
                attempt: retry.attempt,
                maxRetries: retry.maxRetries,
                delayNanoseconds: retry.delayNanoseconds,
                durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                errorDescription: retry.errorDescription
            ))
        }, operation: wrappedOperation)
        await dispatcher.record(telemetryEvent(
            kind: .end,
            callID: callID,
            operationID: operationID,
            providerID: providerID,
            modelID: modelID,
            options: telemetry,
            maxRetries: retryPolicy.maxRetries,
            durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
            output: output(result),
            usage: usage(result),
            warnings: warnings(result),
            providerMetadata: providerMetadata(result),
            responseMetadata: responseMetadata(result)
        ))
        await AIWarningLogging.logWarnings(warnings(result), providerID: providerID, modelID: modelID)
        return result
    } catch {
        await dispatcher.record(telemetryEvent(
            kind: .error,
            callID: callID,
            operationID: operationID,
            providerID: providerID,
            modelID: modelID,
            options: telemetry,
            maxRetries: retryPolicy.maxRetries,
            durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
            errorDescription: String(describing: error)
        ))
        throw error
    }
}

private func generateObjectResult<Output: Sendable>(
    model: any LanguageModel,
    request: LanguageModelRequest,
    outputKind: String,
    schema: JSONValue?,
    schemaName: String?,
    schemaDescription: String?,
    retryPolicy: AIRetryPolicy,
    telemetry: AITelemetryOptions?,
    callbacks: AIObjectGenerationCallbacks<Output>?,
    parse: @escaping @Sendable (String, String) async throws -> (object: Output, rawObject: JSONValue, text: String)
) async throws -> ObjectGenerationResult<Output> {
    let callID = UUID().uuidString
    await callbacks?.onStart?(AIObjectGenerationStartEvent(
        callID: callID,
        operationID: "ai.generateObject",
        providerID: model.providerID,
        modelID: model.modelID,
        outputKind: outputKind,
        request: request,
        schema: schema,
        schemaName: schemaName,
        schemaDescription: schemaDescription,
        maxRetries: retryPolicy.maxRetries
    ))
    await callbacks?.onStepStart?(AIObjectGenerationStepStartEvent(
        callID: callID,
        stepNumber: 0,
        providerID: model.providerID,
        modelID: model.modelID,
        request: request
    ))

    return try await withTelemetry(
        operationID: "ai.generateObject",
        providerID: model.providerID,
        modelID: model.modelID,
        input: objectGenerationTelemetryInput(
            request,
            outputKind: outputKind,
            schema: schema,
            schemaName: schemaName,
            schemaDescription: schemaDescription
        ),
        telemetry: telemetry,
        retryPolicy: retryPolicy,
        callID: callID,
        output: objectGenerationTelemetryOutput,
        usage: { $0.usage },
        warnings: { $0.warnings },
        providerMetadata: { $0.providerMetadata },
        responseMetadata: { $0.responseMetadata }
    ) {
        var textResult: TextGenerationResult?
        do {
            let generatedResult = try await AITelemetryDispatcher(options: telemetry).executeLanguageModelCall(
                callID: callID,
                operationID: "ai.generateObject",
                providerID: model.providerID,
                modelID: model.modelID
            ) {
                try await model.generate(request)
            }
            textResult = generatedResult
            await callbacks?.onStepFinish?(AIObjectGenerationStepFinishEvent(
                callID: callID,
                stepNumber: 0,
                providerID: model.providerID,
                modelID: model.modelID,
                text: generatedResult.text,
                reasoning: generatedResult.reasoning,
                finishReason: generatedResult.finishReason,
                usage: generatedResult.usage,
                warnings: generatedResult.warnings,
                providerMetadata: generatedResult.providerMetadata,
                responseMetadata: generatedResult.responseMetadata
            ))
            let parsed = try await parse(generatedResult.text, model.providerID)

            let result = ObjectGenerationResult(
                object: parsed.object,
                text: parsed.text,
                rawObject: parsed.rawObject,
                reasoning: generatedResult.reasoning,
                finishReason: generatedResult.finishReason,
                usage: generatedResult.usage,
                warnings: generatedResult.warnings,
                providerMetadata: generatedResult.providerMetadata,
                responseMetadata: generatedResult.responseMetadata,
                textResult: generatedResult
            )
            await callbacks?.onFinish?(AIObjectGenerationFinishEvent(
                callID: callID,
                object: result.object,
                text: result.text,
                rawObject: result.rawObject,
                reasoning: result.reasoning,
                finishReason: result.finishReason,
                usage: result.usage,
                warnings: result.warnings,
                providerMetadata: result.providerMetadata,
                responseMetadata: result.responseMetadata
            ))
            return result
        } catch {
            await callbacks?.onError?(AIObjectGenerationErrorEvent(
                callID: callID,
                providerID: model.providerID,
                modelID: model.modelID,
                text: textResult?.text ?? "",
                errorDescription: String(describing: error),
                finishReason: textResult?.finishReason,
                usage: textResult?.usage,
                warnings: textResult?.warnings ?? [],
                providerMetadata: textResult?.providerMetadata ?? [:],
                responseMetadata: textResult?.responseMetadata ?? AIResponseMetadata()
            ))
            throw error
        }
    }
}

private func streamTextWithTelemetry(
    makeStream: @escaping @Sendable () async throws -> AsyncThrowingStream<LanguageStreamPart, Error>,
    operationID: String,
    providerID: String,
    modelID: String?,
    input: JSONValue?,
    retryPolicy: AIRetryPolicy,
    telemetry: AITelemetryOptions?
) -> AsyncThrowingStream<LanguageStreamPart, Error> {
    let dispatcher = AITelemetryDispatcher(options: telemetry)
    let callID = UUID().uuidString
    let started = DispatchTime.now().uptimeNanoseconds
    let terminalState = AIStreamTerminalState()

    return AsyncThrowingStream { continuation in
        let task = Task {
            var step = LanguageStreamToolStep()

            do {
                await dispatcher.record(telemetryEvent(
                    kind: .start,
                    callID: callID,
                    operationID: operationID,
                    providerID: providerID,
                    modelID: modelID,
                    options: telemetry,
                    maxRetries: retryPolicy.maxRetries,
                    input: input
                ))
                try validateRetryPolicy(retryPolicy)

                var errors: [String] = []
                var delay = retryPolicy.initialDelayNanoseconds
                while true {
                    var yieldedPart = false
                    do {
                        let stream = try await dispatcher.executeLanguageModelCall(
                            callID: callID,
                            operationID: operationID,
                            providerID: providerID,
                            modelID: modelID,
                            operation: makeStream
                        )
                        for try await part in stream {
                            try Task.checkCancellation()
                            yieldedPart = true
                            step.record(part)
                            continuation.yield(part)
                        }
                        let result = TextGenerationResult(
                            text: step.text,
                            reasoning: step.reasoning,
                            finishReason: step.finishReason,
                            usage: step.usage,
                            toolCalls: step.toolCalls,
                            toolApprovalRequests: step.approvalRequests,
                            toolApprovalResponses: step.approvalResponses,
                            providerMetadata: step.providerMetadata,
                            rawValue: .object([:]),
                            warnings: step.warnings,
                            responseMetadata: step.responseMetadata
                        )
                        if await terminalState.claimTerminalEvent() {
                            await dispatcher.record(telemetryEvent(
                                kind: .end,
                                callID: callID,
                                operationID: operationID,
                                providerID: providerID,
                                modelID: modelID,
                                options: telemetry,
                                maxRetries: retryPolicy.maxRetries,
                                durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                                output: textGenerationTelemetryOutput(result),
                                usage: result.usage,
                                warnings: result.warnings,
                                providerMetadata: result.providerMetadata,
                                responseMetadata: result.responseMetadata
                            ))
                            await AIWarningLogging.logWarnings(result.warnings, providerID: providerID, modelID: modelID)
                        }
                        continuation.finish()
                        return
                    } catch is CancellationError {
                        throw AIRetryError(reason: .cancelled, attempts: errors.count + 1, errors: errors)
                    } catch {
                        if yieldedPart {
                            throw error
                        }
                        errors.append(String(describing: error))
                        let attempts = errors.count
                        guard retryPolicy.maxRetries > 0 else { throw error }
                        guard isRetryable(error) else {
                            if attempts == 1 { throw error }
                            throw AIRetryError(reason: .errorNotRetryable, attempts: attempts, errors: errors)
                        }
                        guard attempts <= retryPolicy.maxRetries else {
                            throw AIRetryError(reason: .maxRetriesExceeded, attempts: attempts, errors: errors)
                        }
                        let sleepDelay = retryAfterDelayNanoseconds(from: error) ?? delay
                        await dispatcher.record(telemetryEvent(
                            kind: .retry,
                            callID: callID,
                            operationID: operationID,
                            providerID: providerID,
                            modelID: modelID,
                            options: telemetry,
                            attempt: attempts,
                            maxRetries: retryPolicy.maxRetries,
                            delayNanoseconds: sleepDelay,
                            durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                            errorDescription: String(describing: error)
                        ))
                        if sleepDelay > 0 {
                            try await Task.sleep(nanoseconds: sleepDelay)
                        }
                        delay = nextDelay(current: delay, policy: retryPolicy)
                    }
                }
            } catch {
                if isCancellationTelemetryError(error) {
                    if await terminalState.claimTerminalEvent() {
                        await dispatcher.record(telemetryEvent(
                            kind: .abort,
                            callID: callID,
                            operationID: operationID,
                            providerID: providerID,
                            modelID: modelID,
                            options: telemetry,
                            maxRetries: retryPolicy.maxRetries,
                            durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                            errorDescription: String(describing: error)
                        ))
                    }
                    continuation.finish()
                } else {
                    if await terminalState.claimTerminalEvent() {
                        await dispatcher.record(telemetryEvent(
                            kind: .error,
                            callID: callID,
                            operationID: operationID,
                            providerID: providerID,
                            modelID: modelID,
                            options: telemetry,
                            maxRetries: retryPolicy.maxRetries,
                            durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                            errorDescription: String(describing: error)
                        ))
                    }
                    continuation.finish(throwing: error)
                }
            }
        }

        continuation.onTermination = { termination in
            if case .cancelled = termination {
                Task {
                    if await terminalState.claimTerminalEvent() {
                        await dispatcher.record(telemetryEvent(
                            kind: .abort,
                            callID: callID,
                            operationID: operationID,
                            providerID: providerID,
                            modelID: modelID,
                            options: telemetry,
                            maxRetries: retryPolicy.maxRetries,
                            durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                            errorDescription: "Stream cancelled."
                        ))
                    }
                }
            }
            task.cancel()
        }
    }
}

private func objectStreamWithTelemetry<Object: Sendable>(
    makeStream: @escaping @Sendable () async throws -> AsyncThrowingStream<ObjectStreamPart<Object>, Error>,
    operationID: String,
    providerID: String,
    modelID: String?,
    request: LanguageModelRequest? = nil,
    input: JSONValue?,
    retryPolicy: AIRetryPolicy,
    telemetry: AITelemetryOptions?,
    callbacks: AIObjectGenerationCallbacks<Object>? = nil
) -> AsyncThrowingStream<ObjectStreamPart<Object>, Error> {
    let dispatcher = AITelemetryDispatcher(options: telemetry)
    let callID = UUID().uuidString
    let started = DispatchTime.now().uptimeNanoseconds
    let terminalState = AIStreamTerminalState()

    return AsyncThrowingStream { continuation in
        let task = Task {
            var text = ""
            var partialCount = 0
            var objectResult: ObjectGenerationResult<Object>?
            var finishReason: String?
            var usage: TokenUsage?
            var warnings: [AIWarning] = []
            var providerMetadata: [String: JSONValue] = [:]
            var responseMetadata = AIResponseMetadata()
            do {
                let startInput = input?.objectValue
                await callbacks?.onStart?(AIObjectGenerationStartEvent(
                    callID: callID,
                    operationID: operationID,
                    providerID: providerID,
                    modelID: modelID,
                    outputKind: startInput?["output"]?.stringValue ?? "object",
                    request: request ?? LanguageModelRequest(messages: []),
                    schema: startInput?["schema"],
                    schemaName: startInput?["schemaName"]?.stringValue,
                    schemaDescription: startInput?["schemaDescription"]?.stringValue,
                    maxRetries: retryPolicy.maxRetries
                ))
                await callbacks?.onStepStart?(AIObjectGenerationStepStartEvent(
                    callID: callID,
                    stepNumber: 0,
                    providerID: providerID,
                    modelID: modelID,
                    request: request ?? LanguageModelRequest(messages: [])
                ))
                await dispatcher.record(telemetryEvent(
                    kind: .start,
                    callID: callID,
                    operationID: operationID,
                    providerID: providerID,
                    modelID: modelID,
                    options: telemetry,
                    maxRetries: retryPolicy.maxRetries,
                    input: input
                ))
                try validateRetryPolicy(retryPolicy)

                var errors: [String] = []
                var delay = retryPolicy.initialDelayNanoseconds
                while true {
                    var yieldedPart = false
                    do {
                        let stream = try await dispatcher.executeLanguageModelCall(
                            callID: callID,
                            operationID: operationID,
                            providerID: providerID,
                            modelID: modelID,
                            operation: makeStream
                        )
                        for try await part in stream {
                            try Task.checkCancellation()
                            yieldedPart = true
                            switch part {
                            case let .textDelta(delta):
                                text += delta
                            case .partialObject:
                                partialCount += 1
                            case let .object(result):
                                objectResult = result
                                warnings = result.warnings
                                providerMetadata = result.providerMetadata
                                responseMetadata = result.responseMetadata
                            case let .warning(warning):
                                warnings.append(warning)
                            case let .metadata(metadata):
                                providerMetadata.merge(metadata) { _, new in new }
                            case let .responseMetadata(metadata):
                                responseMetadata = metadata
                            case let .finish(reason, partUsage):
                                finishReason = reason
                                usage = partUsage
                            default:
                                break
                            }
                            continuation.yield(part)
                        }
                        let output = objectStreamTelemetryOutput(
                            text: objectResult?.text ?? text,
                            rawObject: objectResult?.rawObject,
                            partialCount: partialCount,
                            finishReason: objectResult?.finishReason ?? finishReason
                        )
                        if await terminalState.claimTerminalEvent() {
                            await callbacks?.onStepFinish?(AIObjectGenerationStepFinishEvent(
                                callID: callID,
                                stepNumber: 0,
                                providerID: providerID,
                                modelID: modelID,
                                text: objectResult?.text ?? text,
                                reasoning: objectResult?.reasoning ?? "",
                                finishReason: objectResult?.finishReason ?? finishReason,
                                usage: objectResult?.usage ?? usage,
                                warnings: warnings,
                                providerMetadata: providerMetadata,
                                responseMetadata: responseMetadata
                            ))
                            if let objectResult {
                                await callbacks?.onFinish?(AIObjectGenerationFinishEvent(
                                    callID: callID,
                                    object: objectResult.object,
                                    text: objectResult.text,
                                    rawObject: objectResult.rawObject,
                                    reasoning: objectResult.reasoning,
                                    finishReason: objectResult.finishReason,
                                    usage: objectResult.usage,
                                    warnings: objectResult.warnings,
                                    providerMetadata: objectResult.providerMetadata,
                                    responseMetadata: objectResult.responseMetadata
                                ))
                            }
                            await dispatcher.record(telemetryEvent(
                                kind: .end,
                                callID: callID,
                                operationID: operationID,
                                providerID: providerID,
                                modelID: modelID,
                                options: telemetry,
                                maxRetries: retryPolicy.maxRetries,
                                durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                                output: output,
                                usage: objectResult?.usage ?? usage,
                                warnings: warnings,
                                providerMetadata: providerMetadata,
                                responseMetadata: responseMetadata
                            ))
                            await AIWarningLogging.logWarnings(warnings, providerID: providerID, modelID: modelID)
                        }
                        continuation.finish()
                        return
                    } catch is CancellationError {
                        throw AIRetryError(reason: .cancelled, attempts: errors.count + 1, errors: errors)
                    } catch {
                        if yieldedPart {
                            throw error
                        }
                        errors.append(String(describing: error))
                        let attempts = errors.count
                        guard retryPolicy.maxRetries > 0 else { throw error }
                        guard isRetryable(error) else {
                            if attempts == 1 { throw error }
                            throw AIRetryError(reason: .errorNotRetryable, attempts: attempts, errors: errors)
                        }
                        guard attempts <= retryPolicy.maxRetries else {
                            throw AIRetryError(reason: .maxRetriesExceeded, attempts: attempts, errors: errors)
                        }
                        let sleepDelay = retryAfterDelayNanoseconds(from: error) ?? delay
                        await dispatcher.record(telemetryEvent(
                            kind: .retry,
                            callID: callID,
                            operationID: operationID,
                            providerID: providerID,
                            modelID: modelID,
                            options: telemetry,
                            attempt: attempts,
                            maxRetries: retryPolicy.maxRetries,
                            delayNanoseconds: sleepDelay,
                            durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                            errorDescription: String(describing: error)
                        ))
                        if sleepDelay > 0 {
                            try await Task.sleep(nanoseconds: sleepDelay)
                        }
                        delay = nextDelay(current: delay, policy: retryPolicy)
                    }
                }
            } catch {
                if isCancellationTelemetryError(error) {
                    if await terminalState.claimTerminalEvent() {
                        await dispatcher.record(telemetryEvent(
                            kind: .abort,
                            callID: callID,
                            operationID: operationID,
                            providerID: providerID,
                            modelID: modelID,
                            options: telemetry,
                            maxRetries: retryPolicy.maxRetries,
                            durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                            errorDescription: String(describing: error)
                        ))
                    }
                    continuation.finish()
                } else {
                    if await terminalState.claimTerminalEvent() {
                        await callbacks?.onError?(AIObjectGenerationErrorEvent(
                            callID: callID,
                            providerID: providerID,
                            modelID: modelID,
                            text: objectResult?.text ?? text,
                            errorDescription: String(describing: error),
                            finishReason: objectResult?.finishReason ?? finishReason,
                            usage: objectResult?.usage ?? usage,
                            warnings: warnings,
                            providerMetadata: providerMetadata,
                            responseMetadata: responseMetadata
                        ))
                        await dispatcher.record(telemetryEvent(
                            kind: .error,
                            callID: callID,
                            operationID: operationID,
                            providerID: providerID,
                            modelID: modelID,
                            options: telemetry,
                            maxRetries: retryPolicy.maxRetries,
                            durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                            errorDescription: String(describing: error)
                        ))
                    }
                    continuation.finish(throwing: error)
                }
            }
        }

        continuation.onTermination = { termination in
            if case .cancelled = termination {
                Task {
                    if await terminalState.claimTerminalEvent() {
                        await dispatcher.record(telemetryEvent(
                            kind: .abort,
                            callID: callID,
                            operationID: operationID,
                            providerID: providerID,
                            modelID: modelID,
                            options: telemetry,
                            maxRetries: retryPolicy.maxRetries,
                            durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                            errorDescription: "Stream cancelled."
                        ))
                    }
                }
            }
            task.cancel()
        }
    }
}

private func mapObjectStream<Input: Sendable, Output: Sendable>(
    _ stream: AsyncThrowingStream<ObjectStreamPart<Input>, Error>,
    transform: @escaping @Sendable (ObjectStreamPart<Input>) -> ObjectStreamPart<Output>
) -> AsyncThrowingStream<ObjectStreamPart<Output>, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                for try await part in stream {
                    try Task.checkCancellation()
                    continuation.yield(transform(part))
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

private func arrayEnvelopeCallbacks<Element: Decodable & Sendable>(
    _ callbacks: AIObjectGenerationCallbacks<[Element]>?
) -> AIObjectGenerationCallbacks<AIObjectArrayEnvelope<Element>>? {
    guard let callbacks else { return nil }
    return AIObjectGenerationCallbacks<AIObjectArrayEnvelope<Element>>(
        onStart: { event in
            await callbacks.onStart?(AIObjectGenerationStartEvent(
                callID: event.callID,
                operationID: event.operationID,
                providerID: event.providerID,
                modelID: event.modelID,
                outputKind: "array",
                request: event.request,
                schema: event.schema,
                schemaName: event.schemaName,
                schemaDescription: event.schemaDescription,
                maxRetries: event.maxRetries
            ))
        },
        onStepStart: callbacks.onStepStart,
        onStepFinish: callbacks.onStepFinish,
        onFinish: { event in
            await callbacks.onFinish?(AIObjectGenerationFinishEvent<[Element]>(
                callID: event.callID,
                object: event.object.elements,
                text: event.text,
                rawObject: event.rawObject,
                reasoning: event.reasoning,
                finishReason: event.finishReason,
                usage: event.usage,
                warnings: event.warnings,
                providerMetadata: event.providerMetadata,
                responseMetadata: event.responseMetadata
            ))
        },
        onError: callbacks.onError
    )
}

private func enumEnvelopeCallbacks(
    _ callbacks: AIObjectGenerationCallbacks<String>?
) -> AIObjectGenerationCallbacks<AIEnumEnvelope>? {
    guard let callbacks else { return nil }
    return AIObjectGenerationCallbacks<AIEnumEnvelope>(
        onStart: { event in
            await callbacks.onStart?(AIObjectGenerationStartEvent(
                callID: event.callID,
                operationID: event.operationID,
                providerID: event.providerID,
                modelID: event.modelID,
                outputKind: "enum",
                request: event.request,
                schema: event.schema,
                schemaName: event.schemaName,
                schemaDescription: event.schemaDescription,
                maxRetries: event.maxRetries
            ))
        },
        onStepStart: callbacks.onStepStart,
        onStepFinish: callbacks.onStepFinish,
        onFinish: { event in
            await callbacks.onFinish?(AIObjectGenerationFinishEvent<String>(
                callID: event.callID,
                object: event.object.result,
                text: event.text,
                rawObject: event.rawObject,
                reasoning: event.reasoning,
                finishReason: event.finishReason,
                usage: event.usage,
                warnings: event.warnings,
                providerMetadata: event.providerMetadata,
                responseMetadata: event.responseMetadata
            ))
        },
        onError: callbacks.onError
    )
}

private func telemetryEvent(
    kind: AITelemetryEventKind,
    callID: String,
    operationID: String,
    providerID: String,
    modelID: String?,
    options: AITelemetryOptions?,
    attempt: Int? = nil,
    maxRetries: Int? = nil,
    delayNanoseconds: UInt64? = nil,
    durationNanoseconds: UInt64? = nil,
    input: JSONValue? = nil,
    output: JSONValue? = nil,
    usage: TokenUsage? = nil,
    warnings: [AIWarning] = [],
    providerMetadata: [String: JSONValue] = [:],
    responseMetadata: AIResponseMetadata = AIResponseMetadata(),
    errorDescription: String? = nil
) -> AITelemetryEvent {
    let recordInputs = options?.recordInputs ?? true
    let recordOutputs = options?.recordOutputs ?? true
    return AITelemetryEvent(
        kind: kind,
        callID: callID,
        operationID: operationID,
        providerID: providerID,
        modelID: modelID,
        functionID: options?.functionID,
        attempt: attempt,
        maxRetries: maxRetries,
        delayNanoseconds: delayNanoseconds,
        durationNanoseconds: durationNanoseconds,
        input: recordInputs ? input : nil,
        output: recordOutputs ? output : nil,
        usage: usage,
        warnings: warnings,
        providerMetadata: providerMetadata,
        responseMetadata: responseMetadata,
        errorDescription: errorDescription,
        metadata: options?.metadata ?? [:],
        recordInputs: options?.recordInputs,
        recordOutputs: options?.recordOutputs
    )
}

private func withRetry<Output: Sendable>(
    policy: AIRetryPolicy,
    onRetry: @escaping @Sendable (AIRetryAttemptTelemetry) async -> Void = { _ in },
    operation: @escaping @Sendable () async throws -> Output
) async throws -> Output {
    try validateRetryPolicy(policy)

    var errors: [String] = []
    var delay = policy.initialDelayNanoseconds

    while true {
        try Task.checkCancellation()
        do {
            return try await withTimeout(policy.timeoutNanoseconds, operation: operation)
        } catch is CancellationError {
            throw AIRetryError(reason: .cancelled, attempts: errors.count + 1, errors: errors)
        } catch {
            errors.append(String(describing: error))
            let attempts = errors.count
            guard policy.maxRetries > 0 else { throw error }
            guard isRetryable(error) else {
                if attempts == 1 { throw error }
                throw AIRetryError(reason: .errorNotRetryable, attempts: attempts, errors: errors)
            }
            guard attempts <= policy.maxRetries else {
                throw AIRetryError(reason: .maxRetriesExceeded, attempts: attempts, errors: errors)
            }
            let sleepDelay = retryAfterDelayNanoseconds(from: error) ?? delay
            await onRetry(AIRetryAttemptTelemetry(
                attempt: attempts,
                maxRetries: policy.maxRetries,
                errorDescription: String(describing: error),
                delayNanoseconds: sleepDelay
            ))
            if sleepDelay > 0 {
                try await Task.sleep(nanoseconds: sleepDelay)
            }
            delay = nextDelay(current: delay, policy: policy)
        }
    }
}

private func validateRetryPolicy(_ policy: AIRetryPolicy) throws {
    guard policy.maxRetries >= 0 else {
        throw AIError.invalidArgument(argument: "maxRetries", message: "maxRetries must be >= 0.")
    }
    guard policy.backoffFactor >= 1 else {
        throw AIError.invalidArgument(argument: "backoffFactor", message: "backoffFactor must be >= 1.")
    }
    if let timeout = policy.timeoutNanoseconds {
        guard timeout > 0 else {
            throw AIError.invalidArgument(argument: "timeoutNanoseconds", message: "timeoutNanoseconds must be greater than zero.")
        }
    }
}

private func withTimeout<Output: Sendable>(
    _ timeoutNanoseconds: UInt64?,
    operation: @escaping @Sendable () async throws -> Output
) async throws -> Output {
    guard let timeoutNanoseconds else {
        return try await operation()
    }

    return try await withThrowingTaskGroup(of: Output.self) { group in
        defer { group.cancelAll() }

        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: timeoutNanoseconds)
            throw AIError.timeout(durationNanoseconds: timeoutNanoseconds)
        }

        guard let result = try await group.next() else {
            throw CancellationError()
        }
        return result
    }
}

private func streamWithTimeout<Part: Sendable>(
    _ stream: AsyncThrowingStream<Part, Error>,
    timeoutNanoseconds: UInt64?
) -> AsyncThrowingStream<Part, Error> {
    guard let timeoutNanoseconds else { return stream }
    guard timeoutNanoseconds > 0 else {
        return failingPartStream(AIError.invalidArgument(
            argument: "timeoutNanoseconds",
            message: "timeoutNanoseconds must be greater than zero."
        ))
    }

    return AsyncThrowingStream { continuation in
        let task = Task {
            await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for try await part in stream {
                        try Task.checkCancellation()
                        continuation.yield(part)
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    throw AIError.timeout(durationNanoseconds: timeoutNanoseconds)
                }

                do {
                    _ = try await group.next()
                    group.cancelAll()
                    continuation.finish()
                } catch {
                    group.cancelAll()
                    continuation.finish(throwing: error)
                }
            }
        }

        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}

private func failingPartStream<Part: Sendable>(_ error: Error) -> AsyncThrowingStream<Part, Error> {
    AsyncThrowingStream { continuation in
        continuation.finish(throwing: error)
    }
}

private func isRetryable(_ error: Error) -> Bool {
    if let error = error as? AIError {
        if case let .httpStatus(_, statusCode, _) = error {
            return isRetryableHTTPStatus(statusCode)
        }
        if case let .httpStatusWithHeaders(_, statusCode, _, _) = error {
            return isRetryableHTTPStatus(statusCode)
        }
        return false
    }
    if let error = error as? URLError {
        switch error.code {
        case .cancelled, .userCancelledAuthentication:
            return false
        default:
            return true
        }
    }
    return false
}

private func isRetryableHTTPStatus(_ statusCode: Int) -> Bool {
    statusCode == 408 || statusCode == 409 || statusCode == 429 || statusCode >= 500
}

private func retryAfterDelayNanoseconds(from error: Error) -> UInt64? {
    guard let headers = httpHeaders(from: error) else { return nil }
    guard let value = headerValue("retry-after", in: headers) else { return nil }
    return retryAfterDelayNanoseconds(from: value, now: Date())
}

private func httpHeaders(from error: Error) -> [String: String]? {
    if let error = error as? AIError {
        if case let .httpStatusWithHeaders(_, _, _, headers) = error {
            return headers
        }
    }
    return nil
}

private func headerValue(_ name: String, in headers: [String: String]) -> String? {
    if let value = headers[name] {
        return value
    }
    let lowercasedName = name.lowercased()
    return headers.first { key, _ in key.lowercased() == lowercasedName }?.value
}

private func retryAfterDelayNanoseconds(from value: String, now: Date) -> UInt64? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let seconds = Double(trimmed) {
        return nanoseconds(fromSeconds: seconds)
    }
    guard let date = httpDate(from: trimmed) else { return nil }
    return nanoseconds(fromSeconds: date.timeIntervalSince(now))
}

private func nanoseconds(fromSeconds seconds: Double) -> UInt64? {
    guard seconds.isFinite else { return nil }
    guard seconds > 0 else { return 0 }
    let nanoseconds = seconds * 1_000_000_000
    guard nanoseconds.isFinite else { return UInt64.max }
    if nanoseconds >= Double(UInt64.max) {
        return UInt64.max
    }
    return UInt64(nanoseconds.rounded(.up))
}

private func httpDate(from value: String) -> Date? {
    let formats = [
        "EEE',' dd MMM yyyy HH':'mm':'ss zzz",
        "EEEE',' dd'-'MMM'-'yy HH':'mm':'ss zzz",
        "EEE MMM d HH':'mm':'ss yyyy"
    ]
    for format in formats {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        if let date = formatter.date(from: value) {
            return date
        }
    }
    return nil
}

private func nextDelay(current: UInt64, policy: AIRetryPolicy) -> UInt64 {
    guard current > 0 else { return 0 }
    let next = Double(current) * policy.backoffFactor
    guard next.isFinite, next < Double(UInt64.max) else {
        return policy.maxDelayNanoseconds
    }
    return Swift.min(UInt64(next), policy.maxDelayNanoseconds)
}

private func languageRequestTelemetryInput(_ request: LanguageModelRequest) -> JSONValue {
    .object([
        "messages": .array(request.messages.map(messageTelemetryJSON)),
        "temperature": request.temperature.map(JSONValue.number),
        "topP": request.topP.map(JSONValue.number),
        "topK": request.topK.map { .number(Double($0)) },
        "presencePenalty": request.presencePenalty.map(JSONValue.number),
        "frequencyPenalty": request.frequencyPenalty.map(JSONValue.number),
        "seed": request.seed.map { .number(Double($0)) },
        "maxOutputTokens": request.maxOutputTokens.map { .number(Double($0)) },
        "stopSequences": .array(request.stopSequences.map(JSONValue.string)),
        "reasoning": request.reasoning.map(JSONValue.string),
        "tools": request.tools.isEmpty ? nil : .object(request.tools),
        "toolChoice": request.toolChoice,
        "includeRawChunks": .bool(request.includeRawChunks),
        "providerOptions": request.providerOptions.isEmpty ? nil : .object(request.providerOptions),
        "extraBody": request.extraBody.isEmpty ? nil : .object(request.extraBody),
        "headers": headersTelemetryJSON(request.headers)
    ])
}

private func objectGenerationTelemetryInput(
    _ request: LanguageModelRequest,
    outputKind: String,
    schema: JSONValue?,
    schemaName: String?,
    schemaDescription: String?
) -> JSONValue {
    var object = languageRequestTelemetryInput(request).objectValue ?? [:]
    object["output"] = .string(outputKind)
    object["schema"] = schema
    object["schemaName"] = schemaName.map(JSONValue.string)
    object["schemaDescription"] = schemaDescription.map(JSONValue.string)
    return .object(object)
}

private func messageTelemetryJSON(_ message: AIMessage) -> JSONValue {
    .object([
        "role": .string(message.role.rawValue),
        "content": .array(message.content.map(contentPartTelemetryJSON))
    ])
}

private func contentPartTelemetryJSON(_ part: AIContentPart) -> JSONValue {
    switch part {
    case let .text(text):
        return .object(["type": .string("text"), "text": .string(text)])
    case let .imageURL(url):
        return .object(["type": .string("image-url"), "url": .string(url)])
    case let .data(mimeType, data):
        return .object(["type": .string("data"), "mimeType": .string(mimeType), "byteLength": .number(Double(data.count))])
    case let .file(mimeType, data, filename):
        return .object(["type": .string("file"), "mimeType": .string(mimeType), "byteLength": .number(Double(data.count)), "filename": filename.map(JSONValue.string)])
    case let .toolCall(call):
        return .object(["type": .string("tool-call"), "id": .string(call.id), "name": .string(call.name), "arguments": .string(call.arguments)])
    case let .toolResult(result):
        return .object([
            "type": .string("tool-result"),
            "toolCallID": .string(result.toolCallID),
            "toolName": .string(result.toolName),
            "result": result.result,
            "modelOutput": result.modelOutput
        ])
    case let .toolApprovalRequest(request):
        return .object(["type": .string("tool-approval-request"), "id": .string(request.id), "toolName": .string(request.toolName), "arguments": .string(request.arguments)])
    case let .toolApprovalResponse(response):
        return .object(["type": .string("tool-approval-response"), "id": .string(response.id), "approved": .bool(response.approved)])
    }
}

private func embeddingRequestTelemetryInput(_ request: EmbeddingRequest) -> JSONValue {
    .object([
        "values": .array(request.values.map(JSONValue.string)),
        "dimensions": request.dimensions.map { .number(Double($0)) },
        "providerOptions": request.providerOptions.isEmpty ? nil : .object(request.providerOptions),
        "extraBody": request.extraBody.isEmpty ? nil : .object(request.extraBody),
        "headers": headersTelemetryJSON(request.headers)
    ])
}

private func imageRequestTelemetryInput(_ request: ImageGenerationRequest) -> JSONValue {
    .object([
        "prompt": .string(request.prompt),
        "size": request.size.map(JSONValue.string),
        "aspectRatio": request.aspectRatio.map(JSONValue.string),
        "seed": request.seed.map { .number(Double($0)) },
        "count": request.count.map { .number(Double($0)) },
        "files": .array(request.files.map(imageFileTelemetryJSON)),
        "mask": request.mask.map(imageFileTelemetryJSON),
        "providerOptions": request.providerOptions.isEmpty ? nil : .object(request.providerOptions),
        "extraBody": request.extraBody.isEmpty ? nil : .object(request.extraBody),
        "headers": headersTelemetryJSON(request.headers)
    ])
}

private func imageFileTelemetryJSON(_ file: ImageInputFile) -> JSONValue {
    .object([
        "type": file.url == nil ? .string("data") : .string("url"),
        "url": file.url.map(JSONValue.string),
        "mediaType": file.mediaType.map(JSONValue.string),
        "fileName": file.fileName.map(JSONValue.string),
        "byteLength": file.data.map { .number(Double($0.count)) }
    ])
}

private func transcriptionRequestTelemetryInput(_ request: AudioTranscriptionRequest) -> JSONValue {
    .object([
        "fileName": .string(request.fileName),
        "mimeType": .string(request.mimeType),
        "byteLength": .number(Double(request.audio.count)),
        "language": request.language.map(JSONValue.string),
        "prompt": request.prompt.map(JSONValue.string),
        "providerOptions": request.providerOptions.isEmpty ? nil : .object(request.providerOptions),
        "extraBody": request.extraBody.isEmpty ? nil : .object(request.extraBody),
        "headers": headersTelemetryJSON(request.headers)
    ])
}

private func speechRequestTelemetryInput(_ request: SpeechRequest) -> JSONValue {
    .object([
        "text": .string(request.text),
        "voice": request.voice.map(JSONValue.string),
        "format": request.format.map(JSONValue.string),
        "providerOptions": request.providerOptions.isEmpty ? nil : .object(request.providerOptions),
        "extraBody": request.extraBody.isEmpty ? nil : .object(request.extraBody),
        "headers": headersTelemetryJSON(request.headers)
    ])
}

private func videoRequestTelemetryInput(_ request: VideoGenerationRequest) -> JSONValue {
    .object([
        "prompt": .string(request.prompt),
        "aspectRatio": request.aspectRatio.map(JSONValue.string),
        "durationSeconds": request.durationSeconds.map(JSONValue.number),
        "providerOptions": request.providerOptions.isEmpty ? nil : .object(request.providerOptions),
        "extraBody": request.extraBody.isEmpty ? nil : .object(request.extraBody),
        "headers": headersTelemetryJSON(request.headers)
    ])
}

private func rerankingRequestTelemetryInput(_ request: RerankingRequest) -> JSONValue {
    .object([
        "query": .string(request.query),
        "documents": .array(request.documents.map(JSONValue.string)),
        "topK": request.topK.map { .number(Double($0)) },
        "providerOptions": request.providerOptions.isEmpty ? nil : .object(request.providerOptions),
        "extraBody": request.extraBody.isEmpty ? nil : .object(request.extraBody),
        "headers": headersTelemetryJSON(request.headers)
    ])
}

private func fileUploadRequestTelemetryInput(_ request: FileUploadRequest) -> JSONValue {
    .object([
        "mediaType": .string(request.mediaType),
        "filename": request.filename.map(JSONValue.string),
        "purpose": request.purpose.map(JSONValue.string),
        "displayName": request.displayName.map(JSONValue.string),
        "byteLength": .number(Double(request.data.count)),
        "providerOptions": request.providerOptions.isEmpty ? nil : .object(request.providerOptions),
        "extraBody": request.extraBody.isEmpty ? nil : .object(request.extraBody),
        "headers": headersTelemetryJSON(request.headers)
    ])
}

private func skillUploadRequestTelemetryInput(_ request: SkillUploadRequest) -> JSONValue {
    .object([
        "displayTitle": request.displayTitle.map(JSONValue.string),
        "files": .array(request.files.map { file in
            .object([
                "path": .string(file.path),
                "mediaType": .string(file.mediaType),
                "byteLength": .number(Double(file.data.count))
            ])
        }),
        "headers": headersTelemetryJSON(request.headers)
    ])
}

private func headersTelemetryJSON(_ headers: [String: String]) -> JSONValue? {
    headers.isEmpty ? nil : .object(headers.mapValues(JSONValue.string))
}

private func stepTelemetryInput(
    index: Int,
    maxSteps: Int,
    request: LanguageModelRequest,
    tools: [AITool]
) -> JSONValue {
    .object([
        "stepNumber": .number(Double(index)),
        "maxSteps": .number(Double(maxSteps)),
        "request": languageRequestTelemetryInput(request),
        "tools": .array(tools.map(toolTelemetryJSON))
    ])
}

private func toolStepTelemetryOutput(_ step: AIToolStep) -> JSONValue {
    .object([
        "stepNumber": .number(Double(step.index)),
        "text": .string(step.text),
        "reasoning": step.reasoning.isEmpty ? nil : .string(step.reasoning),
        "finishReason": step.finishReason.map(JSONValue.string),
        "toolCalls": .array(step.toolCalls.map(toolCallTelemetryJSON)),
        "toolResults": .array(step.toolResults.map(toolResultTelemetryJSON)),
        "toolApprovalRequests": .array(step.toolApprovalRequests.map(toolApprovalRequestTelemetryJSON)),
        "toolApprovalResponses": .array(step.toolApprovalResponses.map(toolApprovalResponseTelemetryJSON))
    ])
}

private func toolTelemetryJSON(_ tool: AITool) -> JSONValue {
    .object([
        "name": .string(tool.name),
        "description": tool.description.map(JSONValue.string),
        "parameters": tool.parameters,
        "dynamic": .bool(tool.dynamic),
        "providerMetadata": tool.providerMetadata.isEmpty ? nil : .object(tool.providerMetadata)
    ])
}

private func toolCallTelemetryJSON(_ call: AIToolCall) -> JSONValue {
    .object([
        "id": .string(call.id),
        "name": .string(call.name),
        "arguments": .string(call.arguments),
        "providerExecuted": .bool(call.providerExecuted),
        "dynamic": .bool(call.dynamic),
        "title": call.title.map(JSONValue.string),
        "providerMetadata": call.providerMetadata.isEmpty ? nil : .object(call.providerMetadata),
        "rawValue": call.rawValue
    ])
}

private func toolResultTelemetryJSON(_ result: AIToolResult) -> JSONValue {
    .object([
        "toolCallID": .string(result.toolCallID),
        "toolName": .string(result.toolName),
        "result": result.result,
        "modelOutput": result.modelOutput,
        "isError": .bool(result.isError),
        "preliminary": .bool(result.preliminary),
        "dynamic": .bool(result.dynamic),
        "providerMetadata": result.providerMetadata.isEmpty ? nil : .object(result.providerMetadata)
    ])
}

private func toolApprovalRequestTelemetryJSON(_ request: AIToolApprovalRequest) -> JSONValue {
    .object([
        "id": .string(request.id),
        "toolCallID": request.toolCallID.map(JSONValue.string),
        "toolName": .string(request.toolName),
        "arguments": .string(request.arguments),
        "isAutomatic": .bool(request.isAutomatic),
        "providerMetadata": request.providerMetadata.isEmpty ? nil : .object(request.providerMetadata)
    ])
}

private func toolApprovalResponseTelemetryJSON(_ response: AIToolApprovalResponse) -> JSONValue {
    .object([
        "id": .string(response.id),
        "approved": .bool(response.approved),
        "reason": response.reason.map(JSONValue.string),
        "providerExecuted": .bool(response.providerExecuted),
        "providerMetadata": response.providerMetadata.isEmpty ? nil : .object(response.providerMetadata)
    ])
}

private func toolExecutionTelemetryInput(stepIndex: Int, call: AIToolCall, tool: AITool) -> JSONValue {
    .object([
        "stepNumber": .number(Double(stepIndex)),
        "toolCall": toolCallTelemetryJSON(call),
        "tool": toolTelemetryJSON(tool)
    ])
}

private func toolExecutionTelemetryOutput(
    stepIndex: Int,
    call: AIToolCall,
    status: String,
    arguments: JSONValue?,
    result: AIToolResult?,
    approvalRequest: AIToolApprovalRequest?,
    approvalResponse: AIToolApprovalResponse?
) -> JSONValue {
    .object([
        "stepNumber": .number(Double(stepIndex)),
        "toolCall": toolCallTelemetryJSON(call),
        "status": .string(status),
        "arguments": arguments,
        "result": result.map(toolResultTelemetryJSON),
        "approvalRequest": approvalRequest.map(toolApprovalRequestTelemetryJSON),
        "approvalResponse": approvalResponse.map(toolApprovalResponseTelemetryJSON)
    ])
}

private func textGenerationTelemetryOutput(_ result: TextGenerationResult) -> JSONValue {
    .object([
        "text": .string(result.text),
        "reasoning": result.reasoning.isEmpty ? nil : .string(result.reasoning),
        "finishReason": result.finishReason.map(JSONValue.string),
        "toolCallCount": .number(Double(result.toolCalls.count)),
        "toolResultCount": .number(Double(result.toolResults.count)),
        "sourceCount": .number(Double(result.sources.count)),
        "rawValue": result.rawValue
    ])
}

private func objectGenerationTelemetryOutput<Object>(_ result: ObjectGenerationResult<Object>) -> JSONValue {
    .object([
        "text": .string(result.text),
        "rawObject": result.rawObject,
        "reasoning": result.reasoning.isEmpty ? nil : .string(result.reasoning),
        "finishReason": result.finishReason.map(JSONValue.string),
        "rawValue": result.textResult.rawValue
    ])
}

private func objectStreamTelemetryOutput(
    text: String,
    rawObject: JSONValue?,
    partialCount: Int,
    finishReason: String?
) -> JSONValue {
    .object([
        "text": .string(text),
        "rawObject": rawObject,
        "partialObjectCount": .number(Double(partialCount)),
        "finishReason": finishReason.map(JSONValue.string)
    ])
}

private func embeddingTelemetryOutput(_ result: EmbeddingResult) -> JSONValue {
    .object([
        "embeddings": .array(result.embeddings.map { .array($0.map(JSONValue.number)) }),
        "rawValue": result.rawValue
    ])
}

private func imageTelemetryOutput(_ result: ImageGenerationResult) -> JSONValue {
    .object([
        "urls": .array(result.urls.map(JSONValue.string)),
        "base64ImageCount": .number(Double(result.base64Images.count)),
        "rawValue": result.rawValue
    ])
}

private func transcriptionTelemetryOutput(_ result: TranscriptionResult) -> JSONValue {
    .object([
        "text": .string(result.text),
        "language": result.language.map(JSONValue.string),
        "durationInSeconds": result.durationInSeconds.map(JSONValue.number),
        "segmentCount": .number(Double(result.segments.count)),
        "rawValue": result.rawValue
    ])
}

private func speechTelemetryOutput(_ result: SpeechResult) -> JSONValue {
    .object([
        "byteLength": .number(Double(result.audio.count)),
        "contentType": result.contentType.map(JSONValue.string)
    ])
}

private func videoTelemetryOutput(_ result: VideoGenerationResult) -> JSONValue {
    .object([
        "urls": .array(result.urls.map(JSONValue.string)),
        "operationID": result.operationID.map(JSONValue.string),
        "rawValue": result.rawValue
    ])
}

private func rerankingTelemetryOutput(_ result: RerankingResult) -> JSONValue {
    .object([
        "results": .array(result.results.map { ranked in
            .object([
                "index": .number(Double(ranked.index)),
                "score": .number(ranked.score),
                "document": ranked.document.map(JSONValue.string)
            ])
        }),
        "rawValue": result.rawValue
    ])
}

private func fileUploadTelemetryOutput(_ result: FileUploadResult) -> JSONValue {
    .object([
        "providerReference": .object(result.providerReference.mapValues(JSONValue.string)),
        "filename": result.filename.map(JSONValue.string),
        "mediaType": result.mediaType.map(JSONValue.string),
        "metadata": result.metadata.isEmpty ? nil : .object(result.metadata),
        "rawValue": result.rawValue
    ])
}

private func skillUploadTelemetryOutput(_ result: SkillUploadResult) -> JSONValue {
    .object([
        "providerReference": .object(result.providerReference.mapValues(JSONValue.string)),
        "displayTitle": result.displayTitle.map(JSONValue.string),
        "name": result.name.map(JSONValue.string),
        "description": result.description.map(JSONValue.string),
        "latestVersion": result.latestVersion.map(JSONValue.string),
        "rawValue": result.rawValue
    ])
}

private func toolsDictionary(from tools: [AITool]) -> [String: JSONValue] {
    Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0.schema) })
}

private func toolsByName(from tools: [AITool]) throws -> [String: AITool] {
    var output: [String: AITool] = [:]
    for tool in tools {
        guard output[tool.name] == nil else {
            throw AIError.invalidArgument(argument: "executableTools", message: "Duplicate tool name '\(tool.name)'.")
        }
        output[tool.name] = tool
    }
    return output
}

private struct AIToolExecutionBatch: Sendable {
    var results: [AIToolResult] = []
    var approvalRequests: [AIToolApprovalRequest] = []
    var approvalResponses: [AIToolApprovalResponse] = []
    var needsUserApproval = false
}

private func toolResponseMessages(
    approvalResponses: [AIToolApprovalResponse],
    toolResults: [AIToolResult]
) -> [AIMessage] {
    guard !approvalResponses.isEmpty || !toolResults.isEmpty else { return [] }
    return [AIMessage.toolResponses(approvalResponses: approvalResponses, toolResults: toolResults)]
}

private func annotateToolCalls(_ calls: [AIToolCall], toolsByName: [String: AITool]) -> [AIToolCall] {
    calls.map { call in
        guard toolsByName[call.name]?.dynamic == true, !call.dynamic else { return call }
        var annotated = call
        annotated.dynamic = true
        return annotated
    }
}

private func annotateToolResult(_ result: AIToolResult, toolsByName: [String: AITool]) -> AIToolResult {
    guard toolsByName[result.toolName]?.dynamic == true, !result.dynamic else { return result }
    var annotated = result
    annotated.dynamic = true
    return annotated
}

private func annotateStreamPart(_ part: LanguageStreamPart, toolsByName: [String: AITool]) -> LanguageStreamPart {
    switch part {
    case let .toolInputStart(id, name, providerExecuted, dynamic, title, providerMetadata):
        guard toolsByName[name]?.dynamic == true, !dynamic else { return part }
        return .toolInputStart(
            id: id,
            name: name,
            providerExecuted: providerExecuted,
            dynamic: true,
            title: title,
            providerMetadata: providerMetadata
        )
    case let .toolCall(call):
        return .toolCall(annotateToolCalls([call], toolsByName: toolsByName)[0])
    case let .toolResult(result):
        return .toolResult(annotateToolResult(result, toolsByName: toolsByName))
    default:
        return part
    }
}

private func executeToolCalls(
    _ calls: [AIToolCall],
    toolsByName: [String: AITool],
    request: LanguageModelRequest,
    toolApproval: AIToolApproval?,
    telemetry: AIToolLoopTelemetryContext? = nil,
    stepIndex: Int = 0
) async throws -> AIToolExecutionBatch {
    var batch = AIToolExecutionBatch()
    for call in calls {
        guard let tool = toolsByName[call.name] else { continue }
        await telemetry?.recordToolStart(stepIndex: stepIndex, call: call, tool: tool)
        do {
            let arguments = try toolArguments(from: call)
            let refinedArguments = try await tool.refineArguments?(arguments) ?? arguments
            try validateToolArguments(refinedArguments, schema: tool.parameters, toolName: call.name)
            let approvalStatus = try await toolApproval?(AIToolApprovalContext(
                toolCall: call,
                arguments: refinedArguments,
                tool: tool,
                request: request
            )) ?? .notApplicable
            let approvalID = "approval-\(call.id)"
            var approvalRequest: AIToolApprovalRequest?
            var approvalResponse: AIToolApprovalResponse?
            switch approvalStatus {
            case .notApplicable:
                break
            case let .approved(reason):
                approvalRequest = AIToolApprovalRequest(
                    id: approvalID,
                    toolName: call.name,
                    arguments: call.arguments,
                    toolCallID: call.id,
                    isAutomatic: true,
                    providerMetadata: call.providerMetadata
                )
                approvalResponse = AIToolApprovalResponse(
                    id: approvalID,
                    approved: true,
                    reason: reason,
                    providerExecuted: call.providerExecuted,
                    providerMetadata: call.providerMetadata
                )
                batch.approvalRequests.append(approvalRequest!)
                batch.approvalResponses.append(approvalResponse!)
            case let .denied(reason):
                approvalRequest = AIToolApprovalRequest(
                    id: approvalID,
                    toolName: call.name,
                    arguments: call.arguments,
                    toolCallID: call.id,
                    isAutomatic: true,
                    providerMetadata: call.providerMetadata
                )
                approvalResponse = AIToolApprovalResponse(
                    id: approvalID,
                    approved: false,
                    reason: reason,
                    providerExecuted: call.providerExecuted,
                    providerMetadata: call.providerMetadata
                )
                batch.approvalRequests.append(approvalRequest!)
                batch.approvalResponses.append(approvalResponse!)
                let dynamic = call.dynamic || tool.dynamic
                let result = AIToolResult(
                    toolCallID: call.id,
                    toolName: call.name,
                    result: executionDeniedResult(reason: reason),
                    dynamic: dynamic,
                    providerMetadata: call.providerMetadata
                )
                batch.results.append(result)
                await telemetry?.recordToolEnd(
                    stepIndex: stepIndex,
                    call: call,
                    status: "denied",
                    arguments: refinedArguments,
                    result: result,
                    approvalRequest: approvalRequest,
                    approvalResponse: approvalResponse
                )
                continue
            case .userApproval:
                approvalRequest = AIToolApprovalRequest(
                    id: approvalID,
                    toolName: call.name,
                    arguments: call.arguments,
                    toolCallID: call.id,
                    providerMetadata: call.providerMetadata
                )
                batch.approvalRequests.append(approvalRequest!)
                batch.needsUserApproval = true
                await telemetry?.recordToolEnd(
                    stepIndex: stepIndex,
                    call: call,
                    status: "userApproval",
                    arguments: refinedArguments,
                    approvalRequest: approvalRequest
                )
                continue
            }
            let resultValue: JSONValue
            if let telemetry {
                resultValue = try await telemetry.executeTool(call: call) {
                    try await tool.execute(refinedArguments)
                }
            } else {
                resultValue = try await tool.execute(refinedArguments)
            }
            let modelOutput = try await tool.toModelOutput?(AIToolModelOutputContext(
                toolCallID: call.id,
                input: refinedArguments,
                output: resultValue
            ))
            let dynamic = call.dynamic || tool.dynamic
            let result = AIToolResult(
                toolCallID: call.id,
                toolName: call.name,
                result: resultValue,
                modelOutput: modelOutput,
                dynamic: dynamic,
                providerMetadata: call.providerMetadata
            )
            batch.results.append(result)
            await telemetry?.recordToolEnd(
                stepIndex: stepIndex,
                call: call,
                status: "executed",
                arguments: refinedArguments,
                result: result,
                approvalRequest: approvalRequest,
                approvalResponse: approvalResponse
            )
        } catch {
            await telemetry?.recordToolError(stepIndex: stepIndex, call: call, error: error)
            throw error
        }
    }
    return batch
}

private func executionDeniedResult(reason: String?) -> JSONValue {
    .object([
        "type": .string("execution-denied"),
        "reason": reason.map(JSONValue.string)
    ].compactMapValues { $0 })
}

private func toolArguments(from call: AIToolCall) throws -> JSONValue {
    let trimmed = call.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .object([:]) }
    do {
        return try decodeJSONBody(Data(trimmed.utf8))
    } catch {
        throw AIError.invalidArgument(argument: "toolCalls.\(call.name).arguments", message: "Tool call arguments must be valid JSON.")
    }
}

private func validateToolArguments(_ arguments: JSONValue, schema: JSONValue, toolName: String) throws {
    do {
        try AIJSONSchemaValidator.validate(arguments, schema: schema)
    } catch let issue as AIJSONSchemaValidationIssue {
        throw AIError.invalidArgument(
            argument: "toolCalls.\(toolName).arguments",
            message: "Tool call arguments do not match tool schema: \(issue.description)"
        )
    }
}

private func objectRequest(
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

private func responseFormatJSON(schema: JSONValue?, name: String?, description: String?) -> JSONValue {
    .object([
        "type": .string("json"),
        "schema": schema,
        "name": name.map(JSONValue.string),
        "description": description.map(JSONValue.string)
    ])
}

private func injectJSONInstruction(
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

private func jsonInstructionText(
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

private struct AIObjectArrayEnvelope<Element: Decodable & Sendable>: Decodable, Sendable {
    var elements: [Element]
}

private struct AIEnumEnvelope: Decodable, Sendable {
    var result: String
}

private func arrayStreamPart<Element: Decodable & Sendable>(
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

private func enumStreamPart(_ part: ObjectStreamPart<AIEnumEnvelope>) -> ObjectStreamPart<String> {
    switch part {
    case let .textDelta(delta):
        return .textDelta(delta)
    case let .partialObject(partial):
        return .partialObject(partial["result"] ?? partial)
    case let .partial(envelope):
        return .partial(envelope.result)
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

private func arrayObjectResult<Element: Decodable & Sendable>(
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

private func enumObjectResult(from result: ObjectGenerationResult<AIEnumEnvelope>) -> ObjectGenerationResult<String> {
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

private func canonicalJSONText(_ value: JSONValue) -> String? {
    guard let data = try? encodeJSONBody(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

private func arrayOutputSchema(elementSchema: JSONValue) -> JSONValue {
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

private func enumOutputSchema(values: [String]) -> JSONValue {
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

private func parseObject<Object: Decodable>(
    _ type: Object.Type,
    from text: String,
    schema: JSONValue? = nil,
    repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)?,
    providerID: String
) async throws -> (object: Object, rawObject: JSONValue, text: String) {
    do {
        return try decodeAndValidateObject(Object.self, from: text, schema: schema)
    } catch {
        let failure = objectGenerationError(
            error,
            providerID: providerID,
            strategy: .object,
            text: text
        )
        let message = failure.description
        guard let repairText else {
            throw failure
        }
        guard let repaired = try await repairText(AIObjectRepairContext(text: text, errorMessage: message)) else {
            throw failure
        }
        do {
            return try decodeAndValidateObject(Object.self, from: repaired, schema: schema)
        } catch {
            throw objectGenerationError(
                error,
                providerID: providerID,
                strategy: .object,
                text: repaired,
                repairAttempted: true
            )
        }
    }
}

private func parseObjectArray<Element: Decodable>(
    _ type: Element.Type,
    from text: String,
    elementSchema: JSONValue,
    repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)?,
    providerID: String
) async throws -> (object: [Element], rawObject: JSONValue, text: String) {
    let schema = arrayOutputSchema(elementSchema: elementSchema)
    do {
        return try decodeAndValidateObjectArray(Element.self, from: text, schema: schema)
    } catch {
        let failure = objectGenerationError(
            error,
            providerID: providerID,
            strategy: .array,
            text: text
        )
        let message = failure.description
        guard let repairText else {
            throw failure
        }
        guard let repaired = try await repairText(AIObjectRepairContext(text: text, errorMessage: message)) else {
            throw failure
        }
        do {
            return try decodeAndValidateObjectArray(Element.self, from: repaired, schema: schema)
        } catch {
            throw objectGenerationError(
                error,
                providerID: providerID,
                strategy: .array,
                text: repaired,
                repairAttempted: true
            )
        }
    }
}

private func parseEnum(
    from text: String,
    values: [String],
    repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)?,
    providerID: String
) async throws -> (object: String, rawObject: JSONValue, text: String) {
    let schema = enumOutputSchema(values: values)
    do {
        return try decodeAndValidateEnum(from: text, schema: schema)
    } catch {
        let failure = objectGenerationError(
            error,
            providerID: providerID,
            strategy: .enumeration,
            text: text
        )
        let message = failure.description
        guard let repairText else {
            throw failure
        }
        guard let repaired = try await repairText(AIObjectRepairContext(text: text, errorMessage: message)) else {
            throw failure
        }
        do {
            return try decodeAndValidateEnum(from: repaired, schema: schema)
        } catch {
            throw objectGenerationError(
                error,
                providerID: providerID,
                strategy: .enumeration,
                text: repaired,
                repairAttempted: true
            )
        }
    }
}

private func parseJSONValueObject(
    from text: String,
    repairText: (@Sendable (AIObjectRepairContext) async throws -> String?)?,
    providerID: String
) async throws -> (object: JSONValue, rawObject: JSONValue, text: String) {
    do {
        return try decodeJSONValueObject(from: text)
    } catch {
        let failure = objectGenerationError(
            error,
            providerID: providerID,
            strategy: .json,
            text: text
        )
        let message = failure.description
        guard let repairText else {
            throw failure
        }
        guard let repaired = try await repairText(AIObjectRepairContext(text: text, errorMessage: message)) else {
            throw failure
        }
        do {
            return try decodeJSONValueObject(from: repaired)
        } catch {
            throw objectGenerationError(
                error,
                providerID: providerID,
                strategy: .json,
                text: repaired,
                repairAttempted: true
            )
        }
    }
}

private func objectGenerationError(
    _ error: Error,
    providerID: String,
    strategy: AIObjectOutputStrategy,
    text: String,
    repairAttempted: Bool = false
) -> AIObjectGenerationError {
    if let error = error as? AIObjectGenerationError {
        var output = error
        output.repairAttempted = output.repairAttempted || repairAttempted
        return output
    }
    if let issue = error as? AIJSONSchemaValidationIssue {
        return AIObjectGenerationError(
            provider: providerID,
            strategy: strategy,
            kind: .schemaValidation,
            message: issue.message,
            path: issue.path,
            text: text,
            repairAttempted: repairAttempted
        )
    }
    if let error = error as? DecodingError {
        return AIObjectGenerationError(
            provider: providerID,
            strategy: strategy,
            kind: .decoding,
            message: String(describing: error),
            text: text,
            repairAttempted: repairAttempted
        )
    }
    if let error = error as? AIError, case let .invalidArgument(argument, message) = error, argument == "text" {
        return AIObjectGenerationError(
            provider: providerID,
            strategy: strategy,
            kind: .noJSON,
            message: message,
            text: text,
            repairAttempted: repairAttempted
        )
    }
    return AIObjectGenerationError(
        provider: providerID,
        strategy: strategy,
        kind: repairAttempted ? .repairFailed : .decoding,
        message: String(describing: error),
        text: text,
        repairAttempted: repairAttempted
    )
}

private func decodeAndValidateObject<Object: Decodable>(
    _ type: Object.Type,
    from text: String,
    schema: JSONValue?
) throws -> (object: Object, rawObject: JSONValue, text: String) {
    let parsed = try decodeObject(Object.self, from: text)
    if let schema {
        try AIJSONSchemaValidator.validate(parsed.rawObject, schema: schema)
    }
    return parsed
}

private func decodeAndValidateObjectArray<Element: Decodable>(
    _ type: Element.Type,
    from text: String,
    schema: JSONValue
) throws -> (object: [Element], rawObject: JSONValue, text: String) {
    let parsed = try decodeObject(JSONValue.self, from: text)
    try AIJSONSchemaValidator.validate(parsed.rawObject, schema: schema)
    guard let elements = parsed.rawObject["elements"]?.arrayValue else {
        throw AIJSONSchemaValidationIssue(path: "$.elements", message: "Expected JSON object with an elements array.")
    }
    let rawArray = JSONValue.array(elements)
    let data = try encodeJSONBody(rawArray)
    let arrayText = String(decoding: data, as: UTF8.self)
    return (try JSONDecoder().decode([Element].self, from: data), rawArray, arrayText)
}

private func decodeAndValidateEnum(
    from text: String,
    schema: JSONValue
) throws -> (object: String, rawObject: JSONValue, text: String) {
    let parsed = try decodeObject(JSONValue.self, from: text)
    try AIJSONSchemaValidator.validate(parsed.rawObject, schema: schema)
    guard let result = parsed.rawObject["result"]?.stringValue else {
        throw AIJSONSchemaValidationIssue(path: "$.result", message: "Expected JSON object with a result string.")
    }
    return (result, .string(result), result)
}

private func decodeJSONValueObject(from text: String) throws -> (object: JSONValue, rawObject: JSONValue, text: String) {
    let jsonText = try extractJSONObjectText(from: text)
    let rawObject = try decodeJSONBody(Data(jsonText.utf8))
    return (rawObject, rawObject, jsonText)
}

private func decodeObject<Object: Decodable>(_ type: Object.Type, from text: String) throws -> (object: Object, rawObject: JSONValue, text: String) {
    let jsonText = try extractJSONObjectText(from: text)
    let rawObject = try decodeJSONBody(Data(jsonText.utf8))
    let data = try encodeJSONBody(rawObject)
    return (try JSONDecoder().decode(Object.self, from: data), rawObject, jsonText)
}

private func partialObject(from text: String) -> JSONValue? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let value = try? decodeJSONBody(Data(trimmed.utf8)) {
        return value
    }
    let repaired = fixPartialJSON(trimmed)
    guard repaired != trimmed, !repaired.isEmpty else { return nil }
    return try? decodeJSONBody(Data(repaired.utf8))
}

private func typedPartialObject<Object: Decodable>(_ type: Object.Type, from partial: JSONValue) -> Object? {
    guard let data = try? encodeJSONBody(partial) else { return nil }
    return try? JSONDecoder().decode(Object.self, from: data)
}

private func extractJSONObjectText(from text: String) throws -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if (try? decodeJSONBody(Data(trimmed.utf8))) != nil {
        return trimmed
    }

    if let fenced = fencedJSONText(from: trimmed), (try? decodeJSONBody(Data(fenced.utf8))) != nil {
        return fenced
    }

    if let balanced = balancedJSONText(from: trimmed), (try? decodeJSONBody(Data(balanced.utf8))) != nil {
        return balanced
    }

    throw AIError.invalidArgument(argument: "text", message: "Expected JSON object or array text.")
}

private enum PartialJSONState {
    case root
    case finish
    case insideString
    case insideStringEscape
    case insideLiteral
    case insideNumber
    case insideObjectStart
    case insideObjectKey
    case insideObjectAfterKey
    case insideObjectBeforeValue
    case insideObjectAfterValue
    case insideObjectAfterComma
    case insideArrayStart
    case insideArrayAfterValue
    case insideArrayAfterComma
}

private func fixPartialJSON(_ input: String) -> String {
    let characters = Array(input)
    var stack: [PartialJSONState] = [.root]
    var lastValidIndex: Int?
    var literalStart: Int?

    func replaceTop(with states: PartialJSONState...) {
        _ = stack.popLast()
        stack.append(contentsOf: states)
    }

    func processValueStart(_ character: Character, index: Int, swapState: PartialJSONState) {
        switch character {
        case "\"":
            lastValidIndex = index
            replaceTop(with: swapState, .insideString)
        case "f", "t", "n":
            lastValidIndex = index
            literalStart = index
            replaceTop(with: swapState, .insideLiteral)
        case "-":
            replaceTop(with: swapState, .insideNumber)
        case "0"..."9":
            lastValidIndex = index
            replaceTop(with: swapState, .insideNumber)
        case "{":
            lastValidIndex = index
            replaceTop(with: swapState, .insideObjectStart)
        case "[":
            lastValidIndex = index
            replaceTop(with: swapState, .insideArrayStart)
        default:
            break
        }
    }

    func processAfterObjectValue(_ character: Character, index: Int) {
        switch character {
        case ",":
            _ = stack.popLast()
            stack.append(.insideObjectAfterComma)
        case "}":
            lastValidIndex = index
            _ = stack.popLast()
        default:
            break
        }
    }

    func processAfterArrayValue(_ character: Character, index: Int) {
        switch character {
        case ",":
            _ = stack.popLast()
            stack.append(.insideArrayAfterComma)
        case "]":
            lastValidIndex = index
            _ = stack.popLast()
        default:
            break
        }
    }

    for (index, character) in characters.enumerated() {
        guard let currentState = stack.last else { break }
        switch currentState {
        case .root:
            processValueStart(character, index: index, swapState: .finish)

        case .insideObjectStart:
            switch character {
            case "\"":
                _ = stack.popLast()
                stack.append(.insideObjectKey)
            case "}":
                lastValidIndex = index
                _ = stack.popLast()
            default:
                break
            }

        case .insideObjectAfterComma:
            if character == "\"" {
                _ = stack.popLast()
                stack.append(.insideObjectKey)
            }

        case .insideObjectKey:
            if character == "\"" {
                _ = stack.popLast()
                stack.append(.insideObjectAfterKey)
            }

        case .insideObjectAfterKey:
            if character == ":" {
                _ = stack.popLast()
                stack.append(.insideObjectBeforeValue)
            }

        case .insideObjectBeforeValue:
            processValueStart(character, index: index, swapState: .insideObjectAfterValue)

        case .insideObjectAfterValue:
            processAfterObjectValue(character, index: index)

        case .insideString:
            switch character {
            case "\"":
                _ = stack.popLast()
                lastValidIndex = index
            case "\\":
                stack.append(.insideStringEscape)
            default:
                lastValidIndex = index
            }

        case .insideArrayStart:
            if character == "]" {
                lastValidIndex = index
                _ = stack.popLast()
            } else {
                lastValidIndex = index
                processValueStart(character, index: index, swapState: .insideArrayAfterValue)
            }

        case .insideArrayAfterValue:
            switch character {
            case ",":
                _ = stack.popLast()
                stack.append(.insideArrayAfterComma)
            case "]":
                lastValidIndex = index
                _ = stack.popLast()
            default:
                lastValidIndex = index
            }

        case .insideArrayAfterComma:
            processValueStart(character, index: index, swapState: .insideArrayAfterValue)

        case .insideStringEscape:
            _ = stack.popLast()
            lastValidIndex = index

        case .insideNumber:
            switch character {
            case "0"..."9":
                lastValidIndex = index
            case "e", "E", "-", ".":
                break
            case ",":
                _ = stack.popLast()
                if stack.last == .insideArrayAfterValue {
                    processAfterArrayValue(character, index: index)
                }
                if stack.last == .insideObjectAfterValue {
                    processAfterObjectValue(character, index: index)
                }
            case "}":
                _ = stack.popLast()
                if stack.last == .insideObjectAfterValue {
                    processAfterObjectValue(character, index: index)
                }
            case "]":
                _ = stack.popLast()
                if stack.last == .insideArrayAfterValue {
                    processAfterArrayValue(character, index: index)
                }
            default:
                _ = stack.popLast()
            }

        case .insideLiteral:
            let start = literalStart ?? index
            let partialLiteral = String(characters[start...index])
            if !"false".hasPrefix(partialLiteral),
               !"true".hasPrefix(partialLiteral),
               !"null".hasPrefix(partialLiteral) {
                _ = stack.popLast()
                if stack.last == .insideObjectAfterValue {
                    processAfterObjectValue(character, index: index)
                } else if stack.last == .insideArrayAfterValue {
                    processAfterArrayValue(character, index: index)
                }
            } else {
                lastValidIndex = index
            }

        case .finish:
            break
        }
    }

    guard let lastValidIndex else { return "" }
    var result = String(characters[0...lastValidIndex])

    for state in stack.reversed() {
        switch state {
        case .insideString:
            result += "\""
        case .insideObjectKey,
             .insideObjectAfterKey,
             .insideObjectAfterComma,
             .insideObjectStart,
             .insideObjectBeforeValue,
             .insideObjectAfterValue:
            result += "}"
        case .insideArrayStart,
             .insideArrayAfterComma,
             .insideArrayAfterValue:
            result += "]"
        case .insideLiteral:
            let start = literalStart ?? characters.count
            let partialLiteral = start < characters.count ? String(characters[start..<characters.count]) : ""
            if "true".hasPrefix(partialLiteral) {
                result += String("true".dropFirst(partialLiteral.count))
            } else if "false".hasPrefix(partialLiteral) {
                result += String("false".dropFirst(partialLiteral.count))
            } else if "null".hasPrefix(partialLiteral) {
                result += String("null".dropFirst(partialLiteral.count))
            }
        case .root, .finish, .insideStringEscape, .insideNumber:
            break
        }
    }

    return result
}

private func fencedJSONText(from text: String) -> String? {
    guard let opening = text.range(of: "```") else { return nil }
    let afterOpening = text[opening.upperBound...]
    let contentStart = afterOpening.firstIndex(of: "\n").map { text.index(after: $0) } ?? afterOpening.startIndex
    guard let closing = text[contentStart...].range(of: "```") else { return nil }
    return String(text[contentStart..<closing.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func balancedJSONText(from text: String) -> String? {
    guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
    let opening = text[start]
    let closing: Character = opening == "{" ? "}" : "]"
    var depth = 0
    var inString = false
    var escaped = false
    var index = start

    while index < text.endIndex {
        let character = text[index]
        if inString {
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString = false
            }
        } else if character == "\"" {
            inString = true
        } else if character == opening {
            depth += 1
        } else if character == closing {
            depth -= 1
            if depth == 0 {
                return String(text[start...index])
            }
        }
        index = text.index(after: index)
    }

    return nil
}

private extension Array {
    func chunked(size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}
