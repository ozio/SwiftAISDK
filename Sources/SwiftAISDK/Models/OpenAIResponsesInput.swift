import Foundation

struct OpenAICompatibleResponsesPreparedRequest {
    var body: [String: JSONValue]
    var warnings: [AIWarning]
}

struct OpenResponsesPreparedInput {
    var input: JSONValue
    var instructions: String?
    var warnings: [AIWarning]
}

func openResponsesInput(from messages: [AIMessage], toolNamespaces: [String: JSONValue] = [:]) -> OpenResponsesPreparedInput {
    var input: [JSONValue] = []
    var systemMessages: [String] = []
    var warnings: [AIWarning] = []

    for message in messages {
        switch message.role {
        case .system:
            systemMessages.append(message.combinedText)
        case .user:
            input.append(.object([
                "type": .string("message"),
                "role": .string("user"),
                "content": .array(message.content.enumerated().compactMap(openResponsesInputContentPart))
            ]))
        case .assistant:
            let outputText = message.content.compactMap { part -> JSONValue? in
                guard case let .text(text) = part else { return nil }
                return .object(["type": .string("output_text"), "text": .string(text)])
            }
            if !outputText.isEmpty {
                input.append(.object([
                    "type": .string("message"),
                    "role": .string("assistant"),
                    "content": .array(outputText)
                ]))
            }
            for part in message.content {
                guard case let .toolCall(call) = part else { continue }
                var callObject: [String: JSONValue] = [
                    "type": .string("function_call"),
                    "call_id": .string(call.id),
                    "name": .string(call.name),
                    "arguments": .string(call.arguments)
                ]
                if let namespace = openAIResponsesNamespace(for: call, toolNamespaces: toolNamespaces) {
                    callObject["namespace"] = namespace
                }
                input.append(.object(callObject))
            }
        case .tool:
            for part in message.content {
                guard case let .toolResult(result) = part else { continue }
                input.append(.object([
                    "type": .string("function_call_output"),
                    "call_id": .string(result.toolCallID),
                    "output": openResponsesToolResultOutput(result, warnings: &warnings)
                ]))
            }
        }
    }

    return OpenResponsesPreparedInput(
        input: .array(input),
        instructions: systemMessages.isEmpty ? nil : systemMessages.joined(separator: "\n"),
        warnings: warnings
    )
}

func openResponsesInputContentPart(_ indexAndPart: EnumeratedSequence<[AIContentPart]>.Element) -> JSONValue? {
    let (_, part) = indexAndPart
    switch part {
    case let .text(text):
        return .object(["type": .string("input_text"), "text": .string(text)])
    case let .imageURL(url):
        return .object(["type": .string("input_image"), "image_url": .string(url)])
    case let .data(mimeType, data):
        let dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
        if mimeType.lowercased().hasPrefix("image/") {
            return .object(["type": .string("input_image"), "image_url": .string(dataURL)])
        }
        return .object([
            "type": .string("input_file"),
            "filename": .string("data"),
            "file_data": .string(dataURL)
        ])
    case let .file(mimeType, data, filename):
        let dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
        if mimeType.lowercased().hasPrefix("image/") {
            return .object(["type": .string("input_image"), "image_url": .string(dataURL)])
        }
        return .object([
            "type": .string("input_file"),
            "filename": .string(filename ?? "data"),
            "file_data": .string(dataURL)
        ])
    case .providerReference, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
        return nil
    }
}


func openResponsesToolResultOutput(_ result: AIToolResult, warnings: inout [AIWarning]) -> JSONValue {
    if let text = result.modelOutput?.stringValue ?? result.result.stringValue {
        return .string(text)
    }
    if let object = (result.modelOutput ?? result.result).objectValue,
       let type = object["type"]?.stringValue {
        if type == "execution-denied" {
            return .string(object["reason"]?.stringValue ?? "Tool execution denied.")
        }
        if type == "content" {
            let content = object["value"]?.arrayValue ?? []
            return .array(content.compactMap { item in
                openResponsesToolResultContentPart(item, warnings: &warnings)
            })
        }
    }
    return .string(openAIResponsesJSONString(result.modelOutput ?? result.result) ?? "")
}

func openResponsesToolResultContentPart(_ item: JSONValue, warnings: inout [AIWarning]) -> JSONValue? {
    switch item["type"]?.stringValue {
    case "text":
        return .object([
            "type": .string("input_text"),
            "text": item["text"] ?? .string("")
        ])
    case "image-data":
        return .object([
            "type": .string("input_image"),
            "image_url": .string("data:\(item["mediaType"]?.stringValue ?? "image/jpeg");base64,\(item["data"]?.stringValue ?? "")")
        ])
    case "image-url":
        return .object([
            "type": .string("input_image"),
            "image_url": item["url"] ?? .string("")
        ])
    case "file-data":
        return .object([
            "type": .string("input_file"),
            "filename": item["filename"] ?? .string("data"),
            "file_data": .string("data:\(item["mediaType"]?.stringValue ?? "application/octet-stream");base64,\(item["data"]?.stringValue ?? "")")
        ])
    default:
        warnings.append(AIWarning(type: "other", message: "unsupported tool content part type: \(item["type"]?.stringValue ?? "unknown")"))
        return nil
    }
}
