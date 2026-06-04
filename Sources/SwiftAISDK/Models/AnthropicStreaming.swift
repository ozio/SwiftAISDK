import Foundation

struct AnthropicToolCallBuffer {
    var id: String
    var name: String
    var arguments: String
    var providerExecuted: Bool
    var rawValue: JSONValue
}

enum AnthropicStreamingContentBlock {
    case text(providerMetadata: [String: JSONValue] = [:])
    case reasoning(providerMetadata: [String: JSONValue] = [:])
}

struct AnthropicStreamingContentBlocks {
    private var blocks: [Int: AnthropicStreamingContentBlock] = [:]
    private let providerID: String

    init(providerID: String) {
        self.providerID = providerID
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
            case "text":
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
                guard let text = delta?["text"]?.stringValue else { return [] }
                return [.textDelta(text), .textDeltaPart(id: id, delta: text)]
            case "thinking_delta":
                guard let thinking = delta?["thinking"]?.stringValue else { return [] }
                return [.reasoningDelta(thinking), .reasoningDeltaPart(id: id, delta: thinking)]
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
                return [.textDelta(content), .textDeltaPart(id: id, delta: content)]
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
        case "message_delta":
            return [.finish(
                reason: anthropicFinishReason(raw["delta"]?["stop_reason"]?.stringValue),
                usage: TokenUsage(
                    inputTokens: raw["usage"]?["input_tokens"]?.intValue,
                    outputTokens: raw["usage"]?["output_tokens"]?.intValue
                )
            )]
        default:
            return []
        }
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

    mutating func apply(event raw: JSONValue) -> [LanguageStreamPart] {
        switch raw["type"]?.stringValue {
        case "content_block_start":
            guard let index = raw["index"]?.intValue,
                  let block = raw["content_block"],
                  let toolCall = anthropicToolCall(from: block) else {
                return []
            }
            let initialArguments = toolCall.arguments == "{}" ? "" : toolCall.arguments
            buffers[index] = AnthropicToolCallBuffer(
                id: toolCall.id,
                name: toolCall.name,
                arguments: initialArguments,
                providerExecuted: toolCall.providerExecuted,
                rawValue: block
            )
            var parts: [LanguageStreamPart] = [
                .toolInputStart(id: toolCall.id, name: toolCall.name, providerExecuted: toolCall.providerExecuted)
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
            buffer.arguments += delta
            buffers[index] = buffer
            var parts: [LanguageStreamPart] = [.toolCallDelta(id: buffer.id, name: buffer.name, argumentsDelta: delta, index: index)]
            if !delta.isEmpty {
                parts.append(.toolInputDelta(id: buffer.id, delta: delta))
            }
            return parts
        case "content_block_stop":
            guard let index = raw["index"]?.intValue, let buffer = buffers.removeValue(forKey: index) else {
                return []
            }
            return [
                .toolInputEnd(id: buffer.id),
                .toolCall(AIToolCall(
                    id: buffer.id,
                    name: buffer.name,
                    arguments: buffer.arguments.isEmpty ? "{}" : buffer.arguments,
                    providerExecuted: buffer.providerExecuted,
                    rawValue: buffer.rawValue
                ))
            ]
        default:
            return []
        }
    }
}

