import Foundation

struct OpenAIResponsesParallelToolCallMetadata: Equatable {
    var itemID: String
    var toolCallID: String
    var toolName: String
    var input: String
    var index: Int
    var count: Int
}

struct OpenAIResponsesParallelToolResultGroup {
    var metadata: OpenAIResponsesParallelToolCallMetadata
    var results: [AIToolResult]
}

private func openAIResponsesSameParallelToolCall(
    _ lhs: OpenAIResponsesParallelToolCallMetadata,
    _ rhs: OpenAIResponsesParallelToolCallMetadata
) -> Bool {
    lhs.itemID == rhs.itemID
        && lhs.toolCallID == rhs.toolCallID
        && lhs.toolName == rhs.toolName
        && lhs.input == rhs.input
        && lhs.count == rhs.count
}

func openAIResponsesFunctionToolNames(from tools: [String: JSONValue]) -> Set<String> {
    Set(tools.compactMap { name, schema in
        let object = schema.objectValue
        let providerToolID = object?["id"]?.stringValue
        guard object?["type"]?.stringValue != "provider",
              providerToolID?.hasPrefix("openai.") != true,
              providerToolID?.hasPrefix("xai.") != true else {
            return nil
        }
        return name
    })
}

func openAIResponsesIsUndeclaredParallelToolCall(
    name: String,
    functionToolNames: Set<String>
) -> Bool {
    name == "parallel" && !functionToolNames.contains("parallel")
}

func openAIResponsesExpandedParallelToolCalls(
    from toolCall: AIToolCall,
    itemID: String,
    providerID: String,
    functionToolNames: Set<String>
) -> [AIToolCall]? {
    guard openAIResponsesIsUndeclaredParallelToolCall(
        name: toolCall.name,
        functionToolNames: functionToolNames
    ),
    let parsed = try? decodeJSONBody(Data(toolCall.arguments.utf8)),
    parsed.objectValue != nil,
    let toolUses = parsed["tool_uses"]?.arrayValue,
    !toolUses.isEmpty else {
        return nil
    }

    var expanded: [AIToolCall] = []
    let providerOptionsName = openAICompatibleProviderMetadataNamespace(providerID)
    for (index, toolUse) in toolUses.enumerated() {
        guard toolUse.objectValue != nil,
              let recipient = toolUse["recipient_name"]?.stringValue,
              recipient.hasPrefix("functions."),
              let parameters = toolUse["parameters"],
              parameters.objectValue != nil else {
            return nil
        }
        let name = String(recipient.dropFirst("functions.".count))
        guard !name.isEmpty, functionToolNames.contains(name) else {
            return nil
        }
        expanded.append(AIToolCall(
            id: "\(toolCall.id)_\(index)",
            name: name,
            arguments: openAIResponsesJSONString(parameters) ?? "{}",
            providerMetadata: [
                providerOptionsName: .object([
                    "parallelToolCall": .object([
                        "itemId": .string(itemID),
                        "toolCallId": .string(toolCall.id),
                        "toolName": .string(toolCall.name),
                        "input": .string(toolCall.arguments),
                        "index": .number(Double(index)),
                        "count": .number(Double(toolUses.count))
                    ])
                ])
            ]
        ))
    }
    return expanded
}

func openAIResponsesParallelToolCallMetadata(
    from providerMetadata: [String: JSONValue],
    providerID: String
) -> OpenAIResponsesParallelToolCallMetadata? {
    let preferredNamespace = openAICompatibleProviderMetadataNamespace(providerID)
    let namespaces = [preferredNamespace, "openai"] + providerMetadata.keys.sorted()
    let value = namespaces.lazy.compactMap { providerMetadata[$0]?["parallelToolCall"] }.first
    guard let value,
          let itemID = value["itemId"]?.stringValue,
          let toolCallID = value["toolCallId"]?.stringValue,
          let toolName = value["toolName"]?.stringValue,
          let input = value["input"]?.stringValue,
          let index = value["index"]?.intValue,
          let count = value["count"]?.intValue,
          index >= 0,
          count > index else {
        return nil
    }
    return OpenAIResponsesParallelToolCallMetadata(
        itemID: itemID,
        toolCallID: toolCallID,
        toolName: toolName,
        input: input,
        index: index,
        count: count
    )
}

func openAIResponsesCompleteParallelToolResultGroups(
    from messages: [AIMessage],
    providerID: String
) -> [String: OpenAIResponsesParallelToolResultGroup] {
    struct PendingGroup {
        var metadata: OpenAIResponsesParallelToolCallMetadata
        var results: [Int: AIToolResult]
        var invalid: Bool
    }
    var pending: [String: PendingGroup] = [:]
    for message in messages where message.role == .tool {
        for part in message.content {
            guard case let .toolResult(result) = part,
                  let metadata = openAIResponsesParallelToolCallMetadata(
                      from: result.providerMetadata,
                      providerID: providerID
                  ) else {
                continue
            }
            if var group = pending[metadata.toolCallID] {
                if !openAIResponsesSameParallelToolCall(group.metadata, metadata)
                    || group.results[metadata.index] != nil {
                    group.invalid = true
                } else {
                    group.results[metadata.index] = result
                }
                pending[metadata.toolCallID] = group
            } else {
                pending[metadata.toolCallID] = PendingGroup(
                    metadata: metadata,
                    results: [metadata.index: result],
                    invalid: false
                )
            }
        }
    }

    var complete: [String: OpenAIResponsesParallelToolResultGroup] = [:]
    for (toolCallID, group) in pending where !group.invalid && group.results.count == group.metadata.count {
        let ordered = (0..<group.metadata.count).compactMap { group.results[$0] }
        guard ordered.count == group.metadata.count else { continue }
        complete[toolCallID] = OpenAIResponsesParallelToolResultGroup(
            metadata: group.metadata,
            results: ordered
        )
    }
    return complete
}

func openAIResponsesMessagesByCollapsingParallelToolResults(
    _ messages: [AIMessage],
    providerID: String,
    hasConversation: Bool,
    hasPreviousResponseID: Bool,
    outputSchemaToolNames: Set<String>,
    warnings: inout [AIWarning]
) -> [AIMessage] {
    guard hasConversation || hasPreviousResponseID else { return messages }
    let groups = openAIResponsesCompleteParallelToolResultGroups(
        from: messages,
        providerID: providerID
    )
    guard !groups.isEmpty else { return messages }

    var emittedCalls: Set<String> = []
    var emittedResults: Set<String> = []
    return messages.map { message in
        var message = message
        var content: [AIContentPart] = []
        for part in message.content {
            switch part {
            case let .toolCall(call):
                guard let metadata = openAIResponsesParallelToolCallMetadata(
                    from: call.providerMetadata,
                    providerID: providerID
                ),
                let group = groups[metadata.toolCallID],
                openAIResponsesSameParallelToolCall(group.metadata, metadata) else {
                    content.append(part)
                    continue
                }
                if emittedCalls.insert(metadata.toolCallID).inserted, !hasConversation {
                    content.append(.toolCall(AIToolCall(
                        id: metadata.toolCallID,
                        name: metadata.toolName,
                        arguments: metadata.input
                    )))
                }
            case let .toolResult(result):
                guard let metadata = openAIResponsesParallelToolCallMetadata(
                    from: result.providerMetadata,
                    providerID: providerID
                ),
                let group = groups[metadata.toolCallID],
                openAIResponsesSameParallelToolCall(group.metadata, metadata) else {
                    content.append(part)
                    continue
                }
                if emittedResults.insert(metadata.toolCallID).inserted {
                    let outputs = group.results.map { child -> String in
                        let output = openResponsesToolResultOutput(
                            child,
                            providerID: providerID,
                            jsonEncodeText: outputSchemaToolNames.contains(child.toolName),
                            warnings: &warnings
                        )
                        return output.stringValue ?? openAIResponsesJSONString(output) ?? ""
                    }
                    content.append(.toolResult(AIToolResult(
                        toolCallID: metadata.toolCallID,
                        toolName: metadata.toolName,
                        result: .string(outputs.joined(separator: "\n"))
                    )))
                }
            default:
                content.append(part)
            }
        }
        message.content = content
        return message
    }
}
