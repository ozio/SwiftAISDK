import Foundation

struct MistralConversationPreparedCall {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
}

func mistralConversationPreparedCall(_ request: LanguageModelRequest, modelID: String, stream: Bool) throws -> MistralConversationPreparedCall {
    var options = try mistralProviderOptions(from: request)
    let format = mistralResolvedResponseFormat(request: request, options: &options)
    let messages = mistralMessages(request.messages, responseFormat: format, structuredOutputs: options["structuredOutputs"]?.boolValue ?? true)
    var warnings = mistralWarnings(for: request, modelID: modelID)
    let preparedTools = mistralConversationPrepareTools(request.tools, choice: request.toolChoice ?? options["toolChoice"])
    var completion: [String: JSONValue] = [:]
    if let maxTokens = request.maxOutputTokens { completion["max_tokens"] = .number(Double(maxTokens)) }
    if let temperature = request.temperature { completion["temperature"] = .number(temperature) }
    if let topP = request.topP { completion["top_p"] = .number(topP) }
    if let frequencyPenalty = request.frequencyPenalty { completion["frequency_penalty"] = .number(frequencyPenalty) }
    if let presencePenalty = request.presencePenalty { completion["presence_penalty"] = .number(presencePenalty) }
    if !request.stopSequences.isEmpty { completion["stop"] = .array(request.stopSequences) }
    if let seed = request.seed { completion["random_seed"] = .number(Double(seed)) }
    if let format { completion["response_format"] = mistralResponseFormat(from: format, options: options) }
    if mistralSupportsReasoningEffort(modelID) { completion["reasoning_effort"] = options["reasoningEffort"] ?? mistralReasoningEffort(request.reasoning, warnings: &warnings) }
    completion["tool_choice"] = preparedTools.choice
    for key in ["safePrompt", "documentImageLimit", "documentPageLimit", "promptCacheKey", "parallelToolCalls"] where options[key] != nil && options[key] != .null {
        warnings.append(AIWarning(type: "unsupported", feature: key, message: "Not supported by the Mistral Conversations API."))
    }
    let converted = try mistralConversationInputs(messages, mapping: MistralConversationToolMapping(tools: request.tools))
    var body: [String: JSONValue] = ["model": .string(modelID), "store": false, "inputs": .array(converted.inputs), "completion_args": .object(completion)]
    body["instructions"] = converted.instructions.map(JSONValue.string)
    if !request.tools.isEmpty { body["tools"] = .array(preparedTools.tools) }
    if stream { body["stream"] = true }
    return MistralConversationPreparedCall(body: body, warnings: warnings + preparedTools.warnings)
}

func mistralConversationInputs(_ messages: [AIMessage], mapping: MistralConversationToolMapping) throws -> (inputs: [JSONValue], instructions: String?) {
    var inputs: [JSONValue] = []
    var instructions: [String] = []
    var executions: Set<String> = []
    func appendResult(_ result: AIToolResult) {
        let output: String
        if executions.contains(result.toolCallID) {
            var value = result.modelOutput ?? result.result
            if value["type"] == "json" { value = value["value"] ?? .null }
            let info = value["info"]
            let replay = info?.objectValue != nil ? (info?["result"] == nil || info?["result"] == .null ? info! : info!["result"]!) : .null
            output = replay.stringValue ?? mistralJSONString(replay) ?? "null"
        } else { output = mistralToolResultContent(result) }
        inputs.append(.object(["type": "function.result", "tool_call_id": .string(result.toolCallID), "result": .string(output)]))
    }
    for message in messages {
        switch message.role {
        case .system: instructions.append(message.combinedText)
        case .user:
            inputs.append(.object(["type": "message.input", "role": "user", "content": .array(try message.content.map(mistralContentPartJSON))]))
        case .assistant:
            var content: [JSONValue] = []
            func flush() {
                if !content.isEmpty { inputs.append(.object(["type": "message.input", "role": "assistant", "content": .array(content)])); content.removeAll() }
            }
            if let reasoning = message.reasoning, !reasoning.isEmpty { content.append(.object(["type": "thinking", "thinking": [.object(["type": "text", "text": .string(reasoning)])], "closed": true])) }
            for part in message.content {
                switch part {
                case let .text(text, _): content.append(.object(["type": "text", "text": .string(text)]))
                case let .reasoning(text, _): content.append(.object(["type": "thinking", "thinking": [.object(["type": "text", "text": .string(text)])], "closed": true]))
                case let .toolCall(call):
                    flush()
                    var name = call.name
                    var arguments = call.arguments
                    if call.providerExecuted {
                        name = call.providerMetadata["mistral"]?["function"]?.stringValue ?? call.providerMetadata["mistral"]?["name"]?.stringValue ?? mapping.toProvider(call.name)
                        arguments = (try? decodeJSONBody(Data(call.arguments.utf8)))?["arguments"]?.stringValue ?? call.arguments
                        executions.insert(call.id)
                    }
                    inputs.append(.object(["type": "function.call", "tool_call_id": .string(call.id), "name": .string(name), "arguments": .string(arguments)]))
                case let .toolResult(result): flush(); appendResult(result)
                default: throw AIError.invalidArgument(argument: "messages", message: "Unsupported assistant content in Mistral Conversations.")
                }
            }
            flush()
        case .tool:
            for part in message.content {
                switch part {
                case let .toolResult(result): appendResult(result)
                case .toolApprovalResponse: continue
                default: throw AIError.invalidArgument(argument: "messages", message: "Mistral Conversations tool messages require tool results.")
                }
            }
        }
    }
    return (inputs, instructions.isEmpty ? nil : instructions.joined(separator: "\n\n"))
}
