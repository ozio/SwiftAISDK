import Foundation

struct OpenAIResponsesStreamingToolCalls {
    let providerID: String
    private var buffers: [Int: OpenAICompatibleToolCallBuffer] = [:]
    private var hostedToolSearchCallIDs: [String] = []

    init(providerID: String) {
        self.providerID = providerID
    }

    mutating func apply(event raw: JSONValue) -> [LanguageStreamPart] {
        guard let type = raw["type"]?.stringValue else { return [] }
        switch type {
        case "response.output_item.added":
            guard let item = raw["item"], let index = raw["output_index"]?.intValue else { return [] }
            switch item["type"]?.stringValue {
            case "web_search_call":
                return handleImmediateHostedToolAdded(item: item, index: index, emitInputLifecycle: true)
            case "file_search_call", "image_generation_call":
                return handleImmediateHostedToolAdded(item: item, index: index, emitInputLifecycle: false)
            case "computer_call":
                return handleComputerUseAdded(item: item, index: index)
            case "code_interpreter_call":
                return handleCodeInterpreterAdded(item: item, index: index)
            case "apply_patch_call":
                return handleApplyPatchAdded(item: item, index: index)
            case "tool_search_call":
                return handleToolSearchAdded(item: item, index: index)
            case "tool_search_output", "mcp_call", "mcp_list_tools", "mcp_approval_request":
                return []
            default:
                break
            }
            guard let toolCall = openAIResponsesToolCall(from: item, providerID: providerID) else { return [] }
            buffers[index] = OpenAICompatibleToolCallBuffer(
                id: toolCall.id,
                name: toolCall.name,
                arguments: "",
                inputStarted: true,
                rawValue: item
            )
            return [
                .toolInputStart(id: toolCall.id, name: toolCall.name, providerExecuted: toolCall.providerExecuted, dynamic: toolCall.dynamic, providerMetadata: toolCall.providerMetadata),
                .toolCallDelta(id: toolCall.id, name: toolCall.name, argumentsDelta: "", index: index)
            ]
        case "response.function_call_arguments.delta", "response.custom_tool_call_input.delta":
            guard let index = raw["output_index"]?.intValue else { return [] }
            var buffer = buffers[index] ?? OpenAICompatibleToolCallBuffer()
            let delta = raw["delta"]?.stringValue ?? ""
            buffer.arguments += delta
            buffers[index] = buffer
            let id = buffer.id ?? "tool-call-\(index)"
            var parts: [LanguageStreamPart] = [.toolCallDelta(id: buffer.id, name: buffer.name, argumentsDelta: delta, index: index)]
            if !delta.isEmpty {
                parts.append(.toolInputDelta(id: id, delta: delta))
            }
            return parts
        case "response.code_interpreter_call_code.delta":
            guard let index = raw["output_index"]?.intValue,
                  let buffer = buffers[index],
                  let id = buffer.id else { return [] }
            return [.toolInputDelta(id: id, delta: openAIResponsesEscapeJSONStringFragment(raw["delta"]?.stringValue ?? ""))]
        case "response.code_interpreter_call_code.done":
            guard let index = raw["output_index"]?.intValue,
                  let buffer = buffers[index],
                  let id = buffer.id,
                  let containerID = buffer.codeInterpreterContainerID else { return [] }
            let code = raw["code"]?.stringValue ?? ""
            return [
                .toolInputDelta(id: id, delta: "\"}"),
                .toolInputEnd(id: id),
                .toolCall(AIToolCall(
                    id: id,
                    name: "code_interpreter",
                    arguments: openAIResponsesJSONString(.object([
                        "code": .string(code),
                        "containerId": .string(containerID)
                    ])) ?? "{}",
                    providerExecuted: true,
                    rawValue: raw
                ))
            ]
        case "response.image_generation_call.partial_image":
            guard let itemID = raw["item_id"]?.stringValue,
                  let image = raw["partial_image_b64"] else { return [] }
            return [
                .toolResult(AIToolResult(
                    toolCallID: itemID,
                    toolName: "image_generation",
                    result: .object(["result": image]),
                    preliminary: true
                ))
            ]
        case "response.apply_patch_call_operation_diff.delta":
            guard let index = raw["output_index"]?.intValue,
                  var buffer = buffers[index],
                  let id = buffer.id else { return [] }
            buffer.applyPatchHasDiff = true
            buffers[index] = buffer
            return [.toolInputDelta(id: id, delta: openAIResponsesEscapeJSONStringFragment(raw["delta"]?.stringValue ?? ""))]
        case "response.apply_patch_call_operation_diff.done":
            guard let index = raw["output_index"]?.intValue,
                  var buffer = buffers[index],
                  let id = buffer.id,
                  buffer.applyPatchEndEmitted == false else { return [] }
            var parts: [LanguageStreamPart] = []
            if !buffer.applyPatchHasDiff {
                parts.append(.toolInputDelta(id: id, delta: openAIResponsesEscapeJSONStringFragment(raw["diff"]?.stringValue ?? "")))
                buffer.applyPatchHasDiff = true
            }
            parts.append(.toolInputDelta(id: id, delta: "\"}}"))
            parts.append(.toolInputEnd(id: id))
            buffer.applyPatchEndEmitted = true
            buffers[index] = buffer
            return parts
        case "response.output_item.done":
            guard let item = raw["item"], let index = raw["output_index"]?.intValue else { return [] }
            switch item["type"]?.stringValue {
            case "web_search_call", "file_search_call", "image_generation_call", "code_interpreter_call":
                buffers[index] = nil
                return openAIResponsesToolResult(from: item, providerID: providerID).map { [.toolResult($0)] } ?? []
            case "apply_patch_call":
                return handleApplyPatchDone(item: item, index: index)
            case "computer_call":
                return handleComputerUseDone(item: item, index: index)
            case "tool_search_call":
                return handleToolSearchDone(item: item, index: index)
            case "tool_search_output":
                return handleToolSearchOutputDone(item: item, index: index)
            case "mcp_call":
                buffers[index] = nil
                guard let toolCall = openAIResponsesToolCall(from: item, providerID: providerID) else { return [] }
                var parts: [LanguageStreamPart] = [.toolCall(toolCall)]
                if let toolResult = openAIResponsesToolResult(from: item, providerID: providerID) {
                    parts.append(.toolResult(toolResult))
                }
                return parts
            case "mcp_list_tools":
                buffers[index] = nil
                return []
            default:
                break
            }
            buffers[index] = nil
            guard let toolCall = openAIResponsesToolCall(from: item, providerID: providerID) else { return [] }
            var parts: [LanguageStreamPart] = [
                .toolInputEnd(id: toolCall.id),
                .toolCall(toolCall)
            ]
            if let toolResult = openAIResponsesToolResult(from: item, providerID: providerID) {
                parts.append(.toolResult(toolResult))
            }
            if let approvalRequest = openAIResponsesToolApprovalRequest(from: item, providerID: providerID) {
                parts.append(.toolApprovalRequest(approvalRequest))
            }
            return parts
        default:
            return []
        }
    }

    private mutating func handleToolSearchAdded(item: JSONValue, index: Int) -> [LanguageStreamPart] {
        let toolCallID = item["id"]?.stringValue ?? item["call_id"]?.stringValue ?? "tool-search-call"
        let isHosted = item["execution"]?.stringValue == "server"
        buffers[index] = OpenAICompatibleToolCallBuffer(
            id: toolCallID,
            name: "tool_search",
            arguments: "",
            inputStarted: isHosted,
            rawValue: item
        )
        guard isHosted else { return [] }
        return [
            .toolInputStart(id: toolCallID, name: "tool_search", providerExecuted: true)
        ]
    }

    private mutating func handleImmediateHostedToolAdded(item: JSONValue, index: Int, emitInputLifecycle: Bool) -> [LanguageStreamPart] {
        guard let toolCall = openAIResponsesToolCall(from: item, providerID: providerID) else { return [] }
        buffers[index] = OpenAICompatibleToolCallBuffer(
            id: toolCall.id,
            name: toolCall.name,
            arguments: toolCall.arguments,
            inputStarted: emitInputLifecycle,
            rawValue: item
        )
        var parts: [LanguageStreamPart] = []
        if emitInputLifecycle {
            parts.append(.toolInputStart(id: toolCall.id, name: toolCall.name, providerExecuted: toolCall.providerExecuted, dynamic: toolCall.dynamic, providerMetadata: toolCall.providerMetadata))
            parts.append(.toolInputEnd(id: toolCall.id))
        }
        parts.append(.toolCall(toolCall))
        return parts
    }

    private mutating func handleComputerUseAdded(item: JSONValue, index: Int) -> [LanguageStreamPart] {
        guard let toolCall = openAIResponsesToolCall(from: item, providerID: providerID) else { return [] }
        buffers[index] = OpenAICompatibleToolCallBuffer(
            id: toolCall.id,
            name: toolCall.name,
            arguments: toolCall.arguments,
            inputStarted: true,
            rawValue: item
        )
        return [
            .toolInputStart(id: toolCall.id, name: toolCall.name, providerExecuted: true)
        ]
    }

    private mutating func handleComputerUseDone(item: JSONValue, index: Int) -> [LanguageStreamPart] {
        buffers[index] = nil
        guard let toolCall = openAIResponsesToolCall(from: item, providerID: providerID) else { return [] }
        var parts: [LanguageStreamPart] = [
            .toolInputEnd(id: toolCall.id),
            .toolCall(toolCall)
        ]
        if let toolResult = openAIResponsesToolResult(from: item, providerID: providerID) {
            parts.append(.toolResult(toolResult))
        }
        return parts
    }

    private mutating func handleCodeInterpreterAdded(item: JSONValue, index: Int) -> [LanguageStreamPart] {
        guard let toolCall = openAIResponsesToolCall(from: item, providerID: providerID) else { return [] }
        let containerID = item["container_id"]?.stringValue ?? ""
        buffers[index] = OpenAICompatibleToolCallBuffer(
            id: toolCall.id,
            name: toolCall.name,
            arguments: "",
            inputStarted: true,
            codeInterpreterContainerID: containerID,
            rawValue: item
        )
        return [
            .toolInputStart(id: toolCall.id, name: toolCall.name, providerExecuted: true),
            .toolInputDelta(
                id: toolCall.id,
                delta: "{\"containerId\":\"\(openAIResponsesEscapeJSONStringFragment(containerID))\",\"code\":\""
            )
        ]
    }

    private mutating func handleApplyPatchAdded(item: JSONValue, index: Int) -> [LanguageStreamPart] {
        guard let toolCall = openAIResponsesToolCall(from: item, providerID: providerID) else { return [] }
        let operation = item["operation"] ?? .object([:])
        let operationType = operation["type"]?.stringValue ?? ""
        let deleteFile = operationType == "delete_file"
        buffers[index] = OpenAICompatibleToolCallBuffer(
            id: toolCall.id,
            name: toolCall.name,
            arguments: "",
            inputStarted: true,
            applyPatchHasDiff: deleteFile,
            applyPatchEndEmitted: deleteFile,
            rawValue: item
        )
        var parts: [LanguageStreamPart] = [
            .toolInputStart(id: toolCall.id, name: toolCall.name)
        ]
        if deleteFile {
            parts.append(.toolInputDelta(id: toolCall.id, delta: toolCall.arguments))
            parts.append(.toolInputEnd(id: toolCall.id))
        } else {
            parts.append(.toolInputDelta(id: toolCall.id, delta: openAIResponsesApplyPatchInputPrefix(callID: toolCall.id, operation: operation)))
        }
        return parts
    }

    private mutating func handleApplyPatchDone(item: JSONValue, index: Int) -> [LanguageStreamPart] {
        var buffer = buffers[index]
        let toolCall = openAIResponsesToolCall(from: item, providerID: providerID)
        let toolCallID = toolCall?.id ?? buffer?.id ?? item["call_id"]?.stringValue ?? "apply-patch-call"
        var parts: [LanguageStreamPart] = []
        if var currentBuffer = buffer,
           currentBuffer.applyPatchEndEmitted == false,
           item["operation"]?["type"]?.stringValue != "delete_file" {
            if !currentBuffer.applyPatchHasDiff {
                parts.append(.toolInputDelta(
                    id: toolCallID,
                    delta: openAIResponsesEscapeJSONStringFragment(item["operation"]?["diff"]?.stringValue ?? "")
                ))
                currentBuffer.applyPatchHasDiff = true
            }
            parts.append(.toolInputDelta(id: toolCallID, delta: "\"}}"))
            parts.append(.toolInputEnd(id: toolCallID))
            currentBuffer.applyPatchEndEmitted = true
            buffer = currentBuffer
        }
        if item["status"]?.stringValue == "completed", let toolCall {
            parts.append(.toolCall(toolCall))
        }
        buffers[index] = nil
        return parts
    }

    private mutating func handleToolSearchDone(item: JSONValue, index: Int) -> [LanguageStreamPart] {
        let buffer = buffers[index]
        let isHosted = item["execution"]?.stringValue == "server"
        let toolCallID = isHosted
            ? (buffer?.id ?? item["id"]?.stringValue ?? item["call_id"]?.stringValue ?? "tool-search-call")
            : (item["call_id"]?.stringValue ?? item["id"]?.stringValue ?? buffer?.id ?? "tool-search-call")
        if isHosted {
            hostedToolSearchCallIDs.append(toolCallID)
        }
        buffers[index] = nil

        var parts: [LanguageStreamPart] = []
        if !isHosted {
            parts.append(.toolInputStart(id: toolCallID, name: "tool_search"))
        }
        parts.append(.toolInputEnd(id: toolCallID))
        parts.append(.toolCall(openAIResponsesToolSearchCall(from: item, id: toolCallID, providerID: providerID, providerExecuted: isHosted)))
        return parts
    }

    private mutating func handleToolSearchOutputDone(item: JSONValue, index: Int) -> [LanguageStreamPart] {
        buffers[index] = nil
        let toolCallID = item["call_id"]?.stringValue ?? (hostedToolSearchCallIDs.isEmpty ? nil : hostedToolSearchCallIDs.removeFirst()) ?? item["id"]?.stringValue
        guard let toolResult = openAIResponsesToolResult(from: item, providerID: providerID, toolCallIDOverride: toolCallID) else {
            return []
        }
        return [.toolResult(toolResult)]
    }
}

