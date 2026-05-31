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
            headers: request.headers
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
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
            warnings: warnings,
            rawValue: raw
        )
    }
}

public final class AnthropicSkillsClient: AISkillsClient, @unchecked Sendable {
    public let providerID: String
    private let config: ModelHTTPConfig

    init(providerID: String, config: ModelHTTPConfig) {
        self.providerID = providerID
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
            headers: headers
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
        }

        let raw = try response.jsonValue()
        let versionMetadata = try await fetchVersionMetadata(skillID: raw["id"]?.stringValue, version: raw["latest_version"]?.stringValue, headers: headers)
        let metadata = anthropicSkillMetadata(from: raw)

        return SkillUploadResult(
            providerReference: ["anthropic": raw["id"]?.stringValue ?? ""],
            displayTitle: raw["display_title"]?.stringValue,
            name: versionMetadata.name ?? raw["name"]?.stringValue,
            description: versionMetadata.description ?? raw["description"]?.stringValue,
            latestVersion: raw["latest_version"]?.stringValue,
            providerMetadata: metadata.isEmpty ? [:] : ["anthropic": .object(metadata)],
            warnings: [],
            rawValue: raw
        )
    }

    private func fetchVersionMetadata(skillID: String?, version: String?, headers: [String: String]) async throws -> (name: String?, description: String?) {
        guard let skillID, let version else {
            return (nil, nil)
        }
        let response = try await config.transport.send(AIHTTPRequest(
            method: "GET",
            url: try requireURL("\(withoutTrailingSlash(config.baseURL))/skills/\(skillID)/versions/\(version)"),
            headers: config.headers.mergingHeaders(headers),
            body: nil
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw AIError.httpStatus(provider: providerID, statusCode: response.statusCode, body: response.bodyText)
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
