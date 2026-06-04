import Foundation

func mcpToolModelOutput(from result: JSONValue) -> JSONValue {
    guard let content = result["content"]?.arrayValue else {
        return .object([
            "type": .string("json"),
            "value": result
        ])
    }

    return .object([
        "type": .string("content"),
        "value": .array(content.map(mcpToolModelOutputPart))
    ])
}

func mcpToolModelOutputPart(_ part: JSONValue) -> JSONValue {
    if part["type"]?.stringValue == "text", let text = part["text"]?.stringValue {
        return .object([
            "type": .string("text"),
            "text": .string(text)
        ])
    }
    if part["type"]?.stringValue == "image",
       let data = part["data"]?.stringValue,
       let mimeType = part["mimeType"]?.stringValue {
        return .object([
            "type": .string("file"),
            "mediaType": .string(mimeType),
            "data": .object([
                "type": .string("data"),
                "data": .string(data)
            ])
        ])
    }
    return .object([
        "type": .string("text"),
        "text": .string(mcpJSONString(part) ?? "")
    ])
}

func mcpJSONString(_ value: JSONValue) -> String? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

func mcpOAuthResourceMetadataURL(from headers: [String: String]) -> URL? {
    guard let header = headers.first(where: { $0.key.caseInsensitiveCompare("www-authenticate") == .orderedSame })?.value else {
        return nil
    }
    let parts = header.split(separator: " ", maxSplits: 1).map(String.init)
    guard parts.first?.lowercased() == "bearer", parts.count == 2 else {
        return nil
    }
    guard let range = parts[1].range(of: #"resource_metadata="([^"]*)""#, options: .regularExpression) else {
        return nil
    }
    let value = parts[1][range]
        .dropFirst("resource_metadata=\"".count)
        .dropLast()
    return URL(string: String(value))
}

func mcpJSONRPCResultResponse(id: JSONValue?, result: JSONValue) -> JSONValue {
    .object([
        "jsonrpc": .string("2.0"),
        "id": id,
        "result": result
    ])
}

func mcpJSONRPCErrorResponse(id: JSONValue?, code: Int, message: String, data: JSONValue? = nil) -> JSONValue {
    .object([
        "jsonrpc": .string("2.0"),
        "id": id,
        "error": .object([
            "code": .number(Double(code)),
            "message": .string(message),
            "data": data
        ])
    ])
}

extension MCPToolDefinition {
    var jsonValue: JSONValue {
        .object([
            "name": .string(name),
            "title": title.map(JSONValue.string),
            "description": description.map(JSONValue.string),
            "inputSchema": inputSchema,
            "outputSchema": outputSchema,
            "annotations": annotations,
            "_meta": metadata
        ])
    }
}
