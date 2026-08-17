import Foundation

struct AnthropicToolCallBuffer {
    var id: String
    var name: String
    var arguments: String
    var providerExecuted: Bool
    var providerMetadata: [String: JSONValue]
    var rawValue: JSONValue
    var firstDelta: Bool = true
    var providerToolInputType: String?
}

enum AnthropicStreamingContentBlock {
    case text(providerMetadata: [String: JSONValue] = [:])
    case reasoning(providerMetadata: [String: JSONValue] = [:])
}

struct AnthropicStreamingContentBlocks {
    private var blocks: [Int: AnthropicStreamingContentBlock] = [:]
    private let providerID: String
    private let ignoresTextBlocks: Bool

    init(providerID: String, ignoresTextBlocks: Bool = false) {
        self.providerID = providerID
        self.ignoresTextBlocks = ignoresTextBlocks
    }

    mutating func apply(event raw: JSONValue) -> [LanguageStreamPart] {
        switch raw["type"]?.stringValue {
        case "content_block_start":
            guard let index = raw["index"]?.intValue,
                  let block = raw["content_block"],
                  let type = block["type"]?.stringValue else {
                return []
            }
            let id = String(index)
            switch type {
            case "fallback":
                return []
            case "text":
                guard !ignoresTextBlocks else { return [] }
                blocks[index] = .text()
                return [.textStart(id: id)]
            case "thinking":
                blocks[index] = .reasoning()
                return [.reasoningStart(id: id)]
            case "redacted_thinking":
                let metadata = anthropicContentBlockProviderMetadata([
                    "redactedData": block["data"] ?? .null
                ], providerID: providerID)
                blocks[index] = .reasoning(providerMetadata: metadata)
                return [.reasoningStart(id: id, providerMetadata: metadata)]
            case "compaction":
                let metadata = anthropicContentBlockProviderMetadata([
                    "type": .string("compaction")
                ], providerID: providerID)
                blocks[index] = .text(providerMetadata: metadata)
                return [.textStart(id: id, providerMetadata: metadata)]
            default:
                return []
            }
        case "content_block_delta":
            let index = raw["index"]?.intValue ?? 0
            let id = String(index)
            let delta = raw["delta"]
            switch delta?["type"]?.stringValue {
            case "text_delta":
                guard !ignoresTextBlocks else { return [] }
                let needsStart = blocks[index] == nil
                if let block = blocks[index] {
                    guard case .text = block else { return [] }
                } else {
                    blocks[index] = .text()
                }
                guard let text = delta?["text"]?.stringValue else { return [] }
                var parts: [LanguageStreamPart] = []
                if needsStart {
                    parts.append(.textStart(id: id))
                }
                parts.append(.textDeltaPart(id: id, delta: text))
                return parts
            case "thinking_delta":
                guard let thinking = delta?["thinking"]?.stringValue else { return [] }
                let needsStart = blocks[index] == nil
                if needsStart {
                    blocks[index] = .reasoning()
                }
                return (needsStart ? [.reasoningStart(id: id)] : []) + [
                    .reasoningDeltaPart(id: id, delta: thinking)
                ]
            case "signature_delta":
                guard case .reasoning = blocks[index],
                      let signature = delta?["signature"] else {
                    return []
                }
                return [.reasoningDeltaPart(
                    id: id,
                    delta: "",
                    providerMetadata: anthropicContentBlockProviderMetadata(["signature": signature], providerID: providerID)
                )]
            case "compaction_delta":
                guard let content = delta?["content"]?.stringValue else { return [] }
                let needsStart = blocks[index] == nil
                if needsStart {
                    blocks[index] = .text(providerMetadata: anthropicContentBlockProviderMetadata([
                        "type": .string("compaction")
                    ], providerID: providerID))
                }
                let metadata = anthropicContentBlockProviderMetadata([
                    "type": .string("compaction")
                ], providerID: providerID)
                return (needsStart ? [.textStart(id: id, providerMetadata: metadata)] : []) + [
                    .textDeltaPart(id: id, delta: content)
                ]
            default:
                return []
            }
        case "content_block_stop":
            guard let index = raw["index"]?.intValue,
                  let block = blocks.removeValue(forKey: index) else {
                return []
            }
            let id = String(index)
            switch block {
            case let .text(metadata):
                return [.textEnd(id: id, providerMetadata: metadata)]
            case let .reasoning(metadata):
                return [.reasoningEnd(id: id, providerMetadata: metadata)]
            }
        default:
            return []
        }
    }

    mutating func finishParts() -> [LanguageStreamPart] {
        let parts = blocks.keys.sorted().compactMap { index -> LanguageStreamPart? in
            guard let block = blocks[index] else { return nil }
            let id = String(index)
            switch block {
            case let .text(metadata):
                return .textEnd(id: id, providerMetadata: metadata)
            case let .reasoning(metadata):
                return .reasoningEnd(id: id, providerMetadata: metadata)
            }
        }
        blocks.removeAll()
        return parts
    }

}

struct AnthropicStreamingJSONToolText {
    private var indexes: Set<Int> = []

    mutating func apply(event raw: JSONValue) -> [LanguageStreamPart] {
        switch raw["type"]?.stringValue {
        case "content_block_start":
            guard let index = raw["index"]?.intValue,
                  let block = raw["content_block"],
                  block["type"]?.stringValue == "tool_use",
                  block["name"]?.stringValue == "json" else {
                return []
            }
            indexes.insert(index)
            return [.textStart(id: String(index))]
        case "content_block_delta":
            guard let index = raw["index"]?.intValue,
                  indexes.contains(index),
                  raw["delta"]?["type"]?.stringValue == "input_json_delta" else {
                return []
            }
            let delta = raw["delta"]?["partial_json"]?.stringValue ?? ""
            guard !delta.isEmpty else { return [] }
            let id = String(index)
            return [.textDeltaPart(id: id, delta: delta)]
        case "content_block_stop":
            guard let index = raw["index"]?.intValue,
                  indexes.remove(index) != nil else {
                return []
            }
            return [.textEnd(id: String(index))]
        default:
            return []
        }
    }

    mutating func finishParts() -> [LanguageStreamPart] {
        let parts = indexes.sorted().map { LanguageStreamPart.textEnd(id: String($0)) }
        indexes.removeAll()
        return parts
    }
}

func anthropicContentBlockProviderMetadata(_ metadata: [String: JSONValue?], providerID: String) -> [String: JSONValue] {
    [anthropicProviderMetadataKey(from: providerID): .object(metadata)]
}

struct AnthropicStreamingProviderToolResults {
    private var serverToolNames: [String: String] = [:]
    private var mcpToolNames: [String: String] = [:]
    private var mcpToolMetadata: [String: [String: JSONValue]] = [:]
    private let providerID: String

    init(providerID: String) {
        self.providerID = providerID
    }

    mutating func apply(event raw: JSONValue) -> [LanguageStreamPart] {
        guard raw["type"]?.stringValue == "content_block_start",
              let block = raw["content_block"] else {
            return []
        }
        recordToolUse(block)
        return anthropicToolResult(
            from: block,
            providerID: providerID,
            serverToolNames: serverToolNames,
            mcpToolNames: mcpToolNames,
            mcpToolMetadata: mcpToolMetadata
        ).map { [.toolResult($0)] } ?? []
    }

    private mutating func recordToolUse(_ block: JSONValue) {
        guard let type = block["type"]?.stringValue,
              let id = block["id"]?.stringValue else {
            return
        }
        switch type {
        case "server_tool_use":
            if let name = block["name"]?.stringValue {
                serverToolNames[id] = name
            }
        case "mcp_tool_use":
            if let name = block["name"]?.stringValue {
                mcpToolNames[id] = name
            }
            mcpToolMetadata[id] = anthropicContentBlockProviderMetadata([
                "type": .string("mcp-tool-use"),
                "serverName": block["server_name"] ?? .null
            ], providerID: providerID)
        default:
            break
        }
    }
}

struct AnthropicStreamingToolCalls {
    private var buffers: [Int: AnthropicToolCallBuffer] = [:]
    private let providerID: String

    init(providerID: String) {
        self.providerID = providerID
    }

    mutating func apply(event raw: JSONValue) -> [LanguageStreamPart] {
        switch raw["type"]?.stringValue {
        case "content_block_start":
            guard let index = raw["index"]?.intValue,
                  let block = raw["content_block"],
                  let toolCall = anthropicToolCall(from: block, providerID: providerID) else {
                return []
            }
            let initialArguments = toolCall.arguments == "{}" ? "" : toolCall.arguments
            buffers[index] = AnthropicToolCallBuffer(
                id: toolCall.id,
                name: toolCall.name,
                arguments: initialArguments,
                providerExecuted: toolCall.providerExecuted,
                providerMetadata: toolCall.providerMetadata,
                rawValue: block,
                firstDelta: initialArguments.isEmpty,
                providerToolInputType: anthropicProviderToolInputType(from: block)
            )
            var parts: [LanguageStreamPart] = [
                .toolInputStart(
                    id: toolCall.id,
                    name: toolCall.name,
                    providerExecuted: toolCall.providerExecuted,
                    providerMetadata: toolCall.providerMetadata
                )
            ]
            parts.append(.toolCallDelta(id: toolCall.id, name: toolCall.name, argumentsDelta: initialArguments, index: index))
            if !initialArguments.isEmpty {
                parts.append(.toolInputDelta(id: toolCall.id, delta: initialArguments))
            }
            return parts
        case "content_block_delta":
            guard raw["delta"]?["type"]?.stringValue == "input_json_delta",
                  let index = raw["index"]?.intValue,
                  var buffer = buffers[index] else {
                return []
            }
            let delta = raw["delta"]?["partial_json"]?.stringValue ?? ""
            let patchedDelta = buffer.firstDelta ? anthropicPatchProviderToolInputDelta(delta, inputType: buffer.providerToolInputType) : delta
            buffer.arguments += patchedDelta
            if !delta.isEmpty {
                buffer.firstDelta = false
            }
            buffers[index] = buffer
            var parts: [LanguageStreamPart] = [.toolCallDelta(id: buffer.id, name: buffer.name, argumentsDelta: patchedDelta, index: index)]
            if !patchedDelta.isEmpty {
                parts.append(.toolInputDelta(id: buffer.id, delta: patchedDelta))
            }
            return parts
        case "content_block_stop":
            guard let index = raw["index"]?.intValue, let buffer = buffers.removeValue(forKey: index) else {
                return []
            }
            return [
                .toolInputEnd(id: buffer.id, providerMetadata: buffer.providerMetadata),
                .toolCall(AIToolCall(
                    id: buffer.id,
                    name: buffer.name,
                    arguments: buffer.arguments.isEmpty ? "{}" : buffer.arguments,
                    providerExecuted: buffer.providerExecuted,
                    providerMetadata: buffer.providerMetadata,
                    rawValue: buffer.rawValue
                ))
            ]
        default:
            return []
        }
    }
}

func anthropicProviderToolInputType(from block: JSONValue) -> String? {
    guard block["type"]?.stringValue == "server_tool_use",
          let name = block["name"]?.stringValue else {
        return nil
    }
    switch name {
    case "text_editor_code_execution", "bash_code_execution":
        return name
    case "code_execution":
        return "programmatic-tool-call"
    default:
        return nil
    }
}

func anthropicPatchProviderToolInputDelta(_ delta: String, inputType: String?) -> String {
    guard !delta.isEmpty, let inputType else { return delta }
    guard delta.first == "{" else { return delta }
    return #"{"type":"\#(inputType)",\#(delta.dropFirst())"#
}
