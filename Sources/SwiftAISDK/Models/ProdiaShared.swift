import Foundation

struct ProdiaLanguageGeneration {
    var result: TextGenerationResult
    var files: [AIStreamFile]
}

func prodiaJSONJobRequestBody(_ body: JSONValue) throws -> JSONValue {
    let contentData = try encodeJSONBody(body)
    let content = String(data: contentData, encoding: .utf8) ?? ""
    return .object([
        "content": .string(content),
        "values": body
    ])
}

func prodiaHTTPStatusError(provider: String, response: AIHTTPResponse) -> AIError {
    let body = prodiaErrorMessage(from: response.body) ?? response.bodyText
    guard !response.headers.isEmpty else {
        return .apiCall(provider: provider, statusCode: response.statusCode, body: body)
    }
    return .apiCall(provider: provider, statusCode: response.statusCode, body: body, headers: response.headers)
}

func prodiaErrorMessage(from data: Data) -> String? {
    guard let json = try? decodeJSONBody(data) else { return nil }
    if let detail = json["detail"] {
        if let message = detail.stringValue {
            return message
        }
        if let encoded = try? encodeJSONBody(detail),
           let text = String(data: encoded, encoding: .utf8) {
            return text
        }
    }
    return json["error"]?.stringValue ?? json["message"]?.stringValue ?? "Unknown Prodia error"
}

func prodiaJobResult(from parts: [MultipartResponsePart]) -> JSONValue? {
    parts.first { $0.name == "job" }?.json
}

func prodiaProviderMetadata(from jobResult: JSONValue?) -> JSONValue {
    guard let jobResult else { return .object([:]) }
    var metadata: [String: JSONValue] = [:]
    if let jobID = jobResult["id"]?.stringValue {
        metadata["jobId"] = .string(jobID)
    }
    if let seed = jobResult["config"]?["seed"] {
        metadata["seed"] = seed
    }
    if let elapsed = jobResult["metrics"]?["elapsed"] {
        metadata["elapsed"] = elapsed
    }
    if let ips = jobResult["metrics"]?["ips"] {
        metadata["iterationsPerSecond"] = ips
    }
    if let createdAt = jobResult["created_at"]?.stringValue {
        metadata["createdAt"] = .string(createdAt)
    }
    if let updatedAt = jobResult["updated_at"]?.stringValue {
        metadata["updatedAt"] = .string(updatedAt)
    }
    if let dollars = jobResult["price"]?["dollars"] {
        metadata["dollars"] = dollars
    }
    return .object(metadata)
}

func prodiaLanguageFiles(from parts: [MultipartResponsePart]) -> [AIStreamFile] {
    parts.compactMap { part in
        guard part.name == "output", let contentType = part.contentType, contentType.hasPrefix("image/") else {
            return nil
        }
        return AIStreamFile(
            mediaType: contentType,
            data: part.body,
            filename: part.fileName,
            rawValue: .object([
                "name": part.name.map(JSONValue.string),
                "fileName": part.fileName.map(JSONValue.string),
                "contentType": .string(contentType),
                "base64": .string(part.body.base64EncodedString())
            ])
        )
    }
}
