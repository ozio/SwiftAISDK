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

func openResponsesInput(
    from messages: [AIMessage],
    providerID: String,
    providerOptionsName: String? = nil,
    toolNamespaces: [String: JSONValue] = [:]
) -> OpenResponsesPreparedInput {
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
            let metadataNamespace = providerOptionsName
                ?? openAICompatibleProviderMetadataNamespace(providerID)
            var assistantContent: [JSONValue] = []
            var assistantMessageID: String?

            func flushAssistantContent() {
                guard !assistantContent.isEmpty else { return }
                var item: [String: JSONValue] = [
                    "type": .string("message"),
                    "role": .string("assistant"),
                    "content": .array(assistantContent)
                ]
                if let assistantMessageID {
                    item["id"] = .string(assistantMessageID)
                }
                input.append(.object(item))
                assistantContent = []
                assistantMessageID = nil
            }

            for part in message.content {
                switch part {
                case let .reasoning(text, providerMetadata):
                    flushAssistantContent()
                    let providerData = providerMetadata[metadataNamespace]?.objectValue
                    let itemID = providerData?["itemId"]?.stringValue
                    let reasoningSummary = openResponsesReasoningArray(
                        providerData?["reasoningSummary"],
                        expectedType: "summary_text"
                    ) ?? []
                    let reasoningContent = openResponsesReasoningArray(
                        providerData?["reasoningContent"],
                        expectedType: "reasoning_text"
                    )
                    let hasReasoningContent = providerData?.keys.contains("reasoningContent") == true

                    var reasoningItem: [String: JSONValue] = [
                        "type": .string("reasoning"),
                        "summary": .array(reasoningSummary)
                    ]
                    if let itemID {
                        reasoningItem["id"] = .string(itemID)
                    }
                    if let reasoningContent {
                        reasoningItem["content"] = .array(reasoningContent)
                    } else if !hasReasoningContent, !text.isEmpty {
                        reasoningItem["content"] = .array([.object([
                            "type": .string("reasoning_text"),
                            "text": .string(text)
                        ])])
                    }
                    if let encryptedContent = providerData?["reasoningEncryptedContent"]?.stringValue {
                        reasoningItem["encrypted_content"] = .string(encryptedContent)
                    }

                    if let itemID,
                       var previous = input.last?.objectValue,
                       previous["type"]?.stringValue == "reasoning",
                       previous["id"]?.stringValue == itemID,
                       let reasoningContent = reasoningItem["content"]?.arrayValue {
                        previous["content"] = .array(
                            (previous["content"]?.arrayValue ?? []) + reasoningContent
                        )
                        input[input.count - 1] = .object(previous)
                    } else {
                        input.append(.object(reasoningItem))
                    }
                case let .text(text, providerMetadata):
                    let providerData = providerMetadata[metadataNamespace]?.objectValue
                    let itemID = providerData?["itemId"]?.stringValue
                    if !assistantContent.isEmpty, assistantMessageID != itemID {
                        flushAssistantContent()
                    }
                    assistantMessageID = itemID
                    var outputText: [String: JSONValue] = [
                        "type": .string("output_text"),
                        "text": .string(text)
                    ]
                    if let annotations = openResponsesOutputTextAnnotations(
                        providerData?["annotations"]
                    ) {
                        outputText["annotations"] = .array(annotations)
                    }
                    assistantContent.append(.object(outputText))
                case let .toolCall(call):
                    flushAssistantContent()
                    let providerData = call.providerMetadata[metadataNamespace]?.objectValue
                    var callObject: [String: JSONValue] = [
                        "type": .string("function_call"),
                        "call_id": .string(call.id),
                        "name": .string(call.name),
                        "arguments": .string(openAIResponsesSerializedToolCallArguments(call.arguments))
                    ]
                    if let itemID = providerData?["itemId"]?.stringValue {
                        callObject["id"] = .string(itemID)
                    }
                    if let namespace = openAIResponsesNamespace(for: call, toolNamespaces: toolNamespaces) {
                        callObject["namespace"] = namespace
                    }
                    input.append(.object(callObject))
                default:
                    continue
                }
            }
            flushAssistantContent()
        case .tool:
            for part in message.content {
                guard case let .toolResult(result) = part else { continue }
                input.append(.object([
                    "type": .string("function_call_output"),
                    "call_id": .string(result.toolCallID),
                    "output": openResponsesToolResultOutput(result, providerID: providerID, warnings: &warnings)
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

private func openResponsesReasoningArray(_ value: JSONValue?, expectedType: String) -> [JSONValue]? {
    guard let values = value?.arrayValue,
          values.allSatisfy({
              $0["type"]?.stringValue == expectedType && $0["text"]?.stringValue != nil
          }) else {
        return nil
    }
    return values.map { value in
        .object([
            "type": .string(expectedType),
            "text": .string(value["text"]?.stringValue ?? "")
        ])
    }
}

private func openResponsesOutputTextAnnotations(_ value: JSONValue?) -> [JSONValue]? {
    guard let annotations = value?.arrayValue,
          annotations.allSatisfy({ annotation in
              annotation["type"]?.stringValue == "url_citation"
                  && annotation["start_index"]?.intValue != nil
                  && annotation["end_index"]?.intValue != nil
                  && annotation["url"]?.stringValue != nil
                  && annotation["title"]?.stringValue != nil
          }) else {
        return nil
    }
    return annotations.map { annotation in
        .object([
            "type": .string("url_citation"),
            "start_index": .number(Double(annotation["start_index"]?.intValue ?? 0)),
            "end_index": .number(Double(annotation["end_index"]?.intValue ?? 0)),
            "url": .string(annotation["url"]?.stringValue ?? ""),
            "title": .string(annotation["title"]?.stringValue ?? "")
        ])
    }
}

func openResponsesInputContentPart(_ indexAndPart: EnumeratedSequence<[AIContentPart]>.Element) -> JSONValue? {
    let (_, part) = indexAndPart
    switch part {
    case let .text(text, _):
        return .object(["type": .string("input_text"), "text": .string(text)])
    case let .reasoning(text, _):
        return .object(["type": .string("input_text"), "text": .string(text)])
    case let .imageURL(url, _):
        return .object(["type": .string("input_image"), "image_url": .string(url)])
    case let .data(mimeType, data, _):
        let dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
        if mimeType.lowercased().hasPrefix("image/") {
            return .object(["type": .string("input_image"), "image_url": .string(dataURL)])
        }
        return .object([
            "type": .string("input_file"),
            "filename": .string("data"),
            "file_data": .string(dataURL)
        ])
    case let .file(mimeType, data, filename, _):
        let dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
        if mimeType.lowercased().hasPrefix("image/") {
            return .object(["type": .string("input_image"), "image_url": .string(dataURL)])
        }
        return .object([
            "type": .string("input_file"),
            "filename": .string(filename ?? "data"),
            "file_data": .string(dataURL)
        ])
    case .reasoningFile, .custom, .providerReference, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
        return nil
    }
}


func openResponsesToolResultOutput(
    _ result: AIToolResult,
    providerID: String,
    jsonEncodeText: Bool = false,
    warnings: inout [AIWarning]
) -> JSONValue {
    if let text = result.modelOutput?.stringValue ?? result.result.stringValue {
        return openResponsesTextToolResultOutput(text, jsonEncodeText: jsonEncodeText)
    }
    if let object = (result.modelOutput ?? result.result).objectValue,
       let type = object["type"]?.stringValue {
        switch type {
        case "text", "error-text":
            return openResponsesTextToolResultOutput(
                object["value"]?.stringValue ?? "",
                jsonEncodeText: jsonEncodeText
            )
        case "execution-denied":
            return openResponsesTextToolResultOutput(
                object["reason"]?.stringValue ?? "Tool call execution denied.",
                jsonEncodeText: jsonEncodeText
            )
        case "json", "error-json":
            return .string(openAIResponsesJSONString(object["value"] ?? .object([:])) ?? "")
        case "content":
            let content = object["value"]?.arrayValue ?? []
            return .array(content.compactMap { item in
                openResponsesToolResultContentPart(item, providerID: providerID, warnings: &warnings)
            })
        default:
            break
        }
    }
    return .string(openAIResponsesJSONString(result.modelOutput ?? result.result) ?? "")
}

private func openResponsesTextToolResultOutput(_ text: String, jsonEncodeText: Bool) -> JSONValue {
    .string(jsonEncodeText ? (openAIResponsesJSONString(.string(text)) ?? "\"\"") : text)
}

func openResponsesToolResultContentPart(_ item: JSONValue, providerID: String, warnings: inout [AIWarning]) -> JSONValue? {
    switch item["type"]?.stringValue {
    case "text":
        return .object([
            "type": .string("input_text"),
            "text": item["text"] ?? .string("")
        ])
    case "image-data":
        var image: [String: JSONValue] = [
            "type": .string("input_image"),
            "image_url": .string("data:\(item["mediaType"]?.stringValue ?? "image/jpeg");base64,\(item["data"]?.stringValue ?? "")")
        ]
        if let detail = openResponsesImageDetail(from: item, providerID: providerID) {
            image["detail"] = detail
        }
        return .object(image)
    case "image-url":
        var image: [String: JSONValue] = [
            "type": .string("input_image"),
            "image_url": item["url"] ?? .string("")
        ]
        if let detail = openResponsesImageDetail(from: item, providerID: providerID) {
            image["detail"] = detail
        }
        return .object(image)
    case "file-data":
        return .object([
            "type": .string("input_file"),
            "filename": item["filename"] ?? .string("data"),
            "file_data": .string("data:\(item["mediaType"]?.stringValue ?? "application/octet-stream");base64,\(item["data"]?.stringValue ?? "")")
        ])
    case "file":
        return openResponsesToolResultFilePart(item, providerID: providerID, warnings: &warnings)
    default:
        warnings.append(AIWarning(type: "other", message: "unsupported tool content part type: \(item["type"]?.stringValue ?? "unknown")"))
        return nil
    }
}

private func openResponsesToolResultFilePart(
    _ item: JSONValue,
    providerID: String,
    warnings: inout [AIWarning]
) -> JSONValue? {
    let mediaType = item["mediaType"]?.stringValue ?? "application/octet-stream"
    let filename = item["filename"] ?? .string("data")
    let data = item["data"]
    switch data?["type"]?.stringValue {
    case "data":
        let payload = data?["data"]?.stringValue ?? ""
        if mediaType.lowercased().hasPrefix("image/") {
            var image: [String: JSONValue] = [
                "type": .string("input_image"),
                "image_url": .string("data:\(mediaType);base64,\(payload)")
            ]
            if let detail = openResponsesImageDetail(from: item, providerID: providerID) {
                image["detail"] = detail
            }
            return .object(image)
        }
        return .object([
            "type": .string("input_file"),
            "filename": filename,
            "file_data": .string("data:\(mediaType);base64,\(payload)")
        ])
    case "url":
        if mediaType.lowercased().hasPrefix("image/") {
            var image: [String: JSONValue] = [
                "type": .string("input_image"),
                "image_url": data?["url"] ?? .string("")
            ]
            if let detail = openResponsesImageDetail(from: item, providerID: providerID) {
                image["detail"] = detail
            }
            return .object(image)
        }
        return .object([
            "type": .string("input_file"),
            "file_url": data?["url"] ?? .string("")
        ])
    case "reference":
        guard let fileID = openResponsesProviderReferenceID(data?["reference"], providerID: providerID) else {
            warnings.append(AIWarning(type: "other", message: "unsupported tool content part type: file with missing provider reference"))
            return nil
        }
        return .object([
            "type": .string("input_file"),
            "filename": filename,
            "file_id": .string(fileID)
        ])
    case "text":
        let text = data?["text"]?.stringValue ?? ""
        return .object([
            "type": .string("input_file"),
            "filename": filename,
            "file_data": .string("data:\(mediaType);base64,\(Data(text.utf8).base64EncodedString())")
        ])
    default:
        warnings.append(AIWarning(
            type: "other",
            message: "unsupported tool content part type: file with data type: \(data?["type"]?.stringValue ?? "unknown")"
        ))
        return nil
    }
}

private func openResponsesImageDetail(from item: JSONValue, providerID: String) -> JSONValue? {
    let providerRoot = openAICompatibleProviderRoot(providerID)
    return item["providerOptions"]?[providerRoot]?["imageDetail"]
        ?? item["providerOptions"]?["openai"]?["imageDetail"]
        ?? item[providerRoot]?["imageDetail"]
        ?? item["openai"]?["imageDetail"]
}

private func openResponsesProviderReferenceID(_ value: JSONValue?, providerID: String) -> String? {
    guard let reference = value?.objectValue else { return nil }
    let providerRoot = openAICompatibleProviderRoot(providerID)
    return reference[providerRoot]?.stringValue
        ?? reference["openai"]?.stringValue
        ?? reference.values.compactMap(\.stringValue).first
}
