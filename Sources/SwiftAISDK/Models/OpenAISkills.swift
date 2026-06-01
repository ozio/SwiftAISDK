import Foundation

public final class OpenAISkillsClient: AISkillsClient, @unchecked Sendable {
    public let providerID: String
    private let providerReferenceKey: String
    private let config: ModelHTTPConfig

    init(providerID: String, providerReferenceKey: String, config: ModelHTTPConfig) {
        self.providerID = providerID
        self.providerReferenceKey = providerReferenceKey
        self.config = config
    }

    public func uploadSkill(_ request: SkillUploadRequest) async throws -> SkillUploadResult {
        var form = MultipartFormData()
        for file in request.files {
            form.appendFile(name: "files[]", fileName: file.path, mimeType: file.mediaType, data: file.data)
        }

        let response = try await config.transport.send(config.rawRequest(
            path: "/skills",
            modelID: "",
            body: form.finalize(),
            contentType: "multipart/form-data; boundary=\(form.boundary)",
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }

        let raw = try response.jsonValue()
        var openAIMetadata: [String: JSONValue] = [:]
        if let defaultVersion = raw["default_version"] {
            openAIMetadata["defaultVersion"] = defaultVersion
        }
        if let createdAt = raw["created_at"] {
            openAIMetadata["createdAt"] = createdAt
        }
        if let updatedAt = raw["updated_at"] {
            openAIMetadata["updatedAt"] = updatedAt
        }

        var warnings: [AIWarning] = []
        if request.displayTitle != nil {
            warnings.append(AIWarning(type: "unsupported", feature: "displayTitle"))
        }

        return SkillUploadResult(
            providerReference: [providerReferenceKey: raw["id"]?.stringValue ?? ""],
            name: raw["name"]?.stringValue,
            description: raw["description"]?.stringValue,
            latestVersion: raw["latest_version"]?.stringValue,
            providerMetadata: openAIMetadata.isEmpty ? [:] : [providerReferenceKey: .object(openAIMetadata)],
            requestMetadata: skillUploadRequestMetadata(request, includeDisplayTitle: false),
            responseMetadata: aiResponseMetadata(from: raw, response: response),
            warnings: warnings,
            rawValue: raw
        )
    }
}

public final class AnthropicSkillsClient: AISkillsClient, @unchecked Sendable {
    public let providerID: String
    private let providerReferenceKey: String
    private let config: ModelHTTPConfig

    init(providerID: String, providerReferenceKey: String, config: ModelHTTPConfig) {
        self.providerID = providerID
        self.providerReferenceKey = providerReferenceKey
        self.config = config
    }

    public func uploadSkill(_ request: SkillUploadRequest) async throws -> SkillUploadResult {
        var form = MultipartFormData()
        if let displayTitle = request.displayTitle {
            form.appendField(name: "display_title", value: displayTitle)
        }
        for file in request.files {
            form.appendFile(name: "files[]", fileName: file.path, mimeType: file.mediaType, data: file.data)
        }

        let headers = request.headers.mergingHeaders(["anthropic-beta": "skills-2025-10-02"])
        let response = try await config.transport.send(config.rawRequest(
            path: "/skills",
            modelID: "",
            body: form.finalize(),
            contentType: "multipart/form-data; boundary=\(form.boundary)",
            headers: headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }

        let raw = try response.jsonValue()
        let versionMetadata = try await fetchVersionMetadata(
            skillID: raw["id"]?.stringValue,
            version: raw["latest_version"]?.stringValue,
            headers: headers,
            abortSignal: request.abortSignal
        )
        let metadata = anthropicSkillMetadata(from: raw)

        return SkillUploadResult(
            providerReference: [providerReferenceKey: raw["id"]?.stringValue ?? ""],
            displayTitle: raw["display_title"]?.stringValue,
            name: versionMetadata.name ?? raw["name"]?.stringValue,
            description: versionMetadata.description ?? raw["description"]?.stringValue,
            latestVersion: raw["latest_version"]?.stringValue,
            providerMetadata: metadata.isEmpty ? [:] : [providerReferenceKey: .object(metadata)],
            requestMetadata: skillUploadRequestMetadata(request, includeDisplayTitle: true),
            responseMetadata: aiResponseMetadata(from: raw, response: response),
            warnings: [],
            rawValue: raw
        )
    }

    private func fetchVersionMetadata(skillID: String?, version: String?, headers: [String: String], abortSignal: AIAbortSignal?) async throws -> (name: String?, description: String?) {
        guard let skillID, let version else {
            return (nil, nil)
        }
        let response = try await config.transport.send(AIHTTPRequest(
            method: "GET",
            url: try requireURL("\(withoutTrailingSlash(config.baseURL))/skills/\(skillID)/versions/\(version)"),
            headers: config.headers.mergingHeaders(headers),
            body: nil,
            abortSignal: abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        return (raw["name"]?.stringValue, raw["description"]?.stringValue)
    }
}

private func anthropicSkillMetadata(from raw: JSONValue) -> [String: JSONValue] {
    var metadata: [String: JSONValue] = [:]
    if let source = raw["source"] {
        metadata["source"] = source
    }
    if let createdAt = raw["created_at"] {
        metadata["createdAt"] = createdAt
    }
    if let updatedAt = raw["updated_at"] {
        metadata["updatedAt"] = updatedAt
    }
    return metadata
}

private func skillUploadRequestMetadata(_ request: SkillUploadRequest, includeDisplayTitle: Bool) -> AIRequestMetadata {
    var body: [String: JSONValue] = [
        "files": .array(request.files.map { file in
            .object([
                "path": .string(file.path),
                "mediaType": .string(file.mediaType),
                "byteLength": .number(Double(file.data.count))
            ])
        })
    ]
    if includeDisplayTitle, let displayTitle = request.displayTitle {
        body["displayTitle"] = .string(displayTitle)
    }
    return AIRequestMetadata(body: .object(body), headers: request.headers)
}
