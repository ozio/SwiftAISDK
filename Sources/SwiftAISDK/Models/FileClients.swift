import Foundation

public final class MultipartFileClient: AIFileClient, @unchecked Sendable {
    public let providerID: String
    private let providerReferenceKey: String
    private let config: ModelHTTPConfig
    private let betaHeader: (String, String)?
    private let includePurpose: Bool

    init(providerID: String, providerReferenceKey: String, config: ModelHTTPConfig, betaHeader: (String, String)? = nil, includePurpose: Bool = false) {
        self.providerID = providerID
        self.providerReferenceKey = providerReferenceKey
        self.config = config
        self.betaHeader = betaHeader
        self.includePurpose = includePurpose
    }

    public func uploadFile(_ request: FileUploadRequest) async throws -> FileUploadResult {
        var form = MultipartFormData()
        form.appendFile(name: "file", fileName: request.filename ?? "file", mimeType: request.mediaType, data: request.data)
        if includePurpose {
            form.appendField(name: "purpose", value: request.purpose ?? "assistants")
        }
        for (key, value) in request.extraBody {
            if let scalar = jsonScalarString(value) {
                form.appendField(name: key, value: scalar)
            }
        }
        var headers = request.headers
        if let betaHeader {
            headers[betaHeader.0] = headers[betaHeader.0] ?? betaHeader.1
        }
        let response = try await config.transport.send(config.rawRequest(
            path: "/files",
            modelID: "",
            body: form.finalize(),
            contentType: "multipart/form-data; boundary=\(form.boundary)",
            headers: headers
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        let id = raw["id"]?.stringValue ?? raw["file"]?["id"]?.stringValue ?? ""
        return FileUploadResult(
            providerReference: [providerReferenceKey: id],
            filename: raw["filename"]?.stringValue ?? request.filename,
            mediaType: raw["mime_type"]?.stringValue ?? request.mediaType,
            metadata: fileMetadata(from: raw),
            rawValue: raw
        )
    }
}

public final class GoogleFileClient: AIFileClient, @unchecked Sendable {
    public let providerID: String
    private let config: ModelHTTPConfig

    init(providerID: String, config: ModelHTTPConfig) {
        self.providerID = providerID
        self.config = config
    }

    public func uploadFile(_ request: FileUploadRequest) async throws -> FileUploadResult {
        let origin = config.baseURL.hasSuffix("/v1beta") ? String(config.baseURL.dropLast("/v1beta".count)) : config.baseURL
        var startHeaders = config.headers.mergingHeaders(request.headers)
        startHeaders["X-Goog-Upload-Protocol"] = "resumable"
        startHeaders["X-Goog-Upload-Command"] = "start"
        startHeaders["X-Goog-Upload-Header-Content-Length"] = String(request.data.count)
        startHeaders["X-Goog-Upload-Header-Content-Type"] = request.mediaType
        startHeaders["Content-Type"] = "application/json"

        let initBody: JSONValue = .object([
            "file": .object(request.displayName.map { ["display_name": .string($0)] } ?? [:])
        ])
        let startResponse = try await config.transport.send(AIHTTPRequest(
            method: "POST",
            url: try requireURL("\(origin)/upload/v1beta/files"),
            headers: startHeaders,
            body: try encodeJSONBody(initBody)
        ))
        guard (200..<300).contains(startResponse.statusCode) else {
            throw httpStatusError(provider: providerID, response: startResponse)
        }
        guard let uploadURL = headerValue(startResponse.headers, "x-goog-upload-url") else {
            throw AIError.invalidResponse(provider: providerID, message: "No x-goog-upload-url returned from resumable upload start.")
        }

        let uploadResponse = try await config.transport.send(AIHTTPRequest(
            method: "POST",
            url: try requireURL(uploadURL),
            headers: [
                "Content-Length": String(request.data.count),
                "X-Goog-Upload-Offset": "0",
                "X-Goog-Upload-Command": "upload, finalize"
            ],
            body: request.data
        ))
        guard (200..<300).contains(uploadResponse.statusCode) else {
            throw httpStatusError(provider: providerID, response: uploadResponse)
        }
        var raw = try uploadResponse.jsonValue()
        var file = raw["file"] ?? raw

        let started = DispatchTime.now().uptimeNanoseconds
        while file["state"]?.stringValue == "PROCESSING" {
            if DispatchTime.now().uptimeNanoseconds - started > request.pollTimeoutNanoseconds {
                throw AIError.invalidResponse(provider: providerID, message: "Google file processing timed out for \(file["name"]?.stringValue ?? "unknown file").")
            }
            try await Task.sleep(nanoseconds: request.pollIntervalNanoseconds)
            guard let name = file["name"]?.stringValue else { break }
            let statusResponse = try await config.transport.send(AIHTTPRequest(
                method: "GET",
                url: try requireURL("\(config.baseURL)/\(name)"),
                headers: config.headers.mergingHeaders(request.headers)
            ))
            guard (200..<300).contains(statusResponse.statusCode) else {
                throw httpStatusError(provider: providerID, response: statusResponse)
            }
            file = try statusResponse.jsonValue()
            raw = file
        }
        if file["state"]?.stringValue == "FAILED" {
            throw AIError.invalidResponse(provider: providerID, message: "Google file processing failed for \(file["name"]?.stringValue ?? "unknown file").")
        }

        return FileUploadResult(
            providerReference: ["google": file["uri"]?.stringValue ?? ""],
            filename: request.filename,
            mediaType: file["mimeType"]?.stringValue ?? request.mediaType,
            metadata: fileMetadata(from: file),
            rawValue: raw
        )
    }
}

public final class XAIFileClient: AIFileClient, @unchecked Sendable {
    public let providerID = "xai.files"
    private let config: ModelHTTPConfig

    init(config: ModelHTTPConfig) {
        self.config = config
    }

    public func uploadFile(_ request: FileUploadRequest) async throws -> FileUploadResult {
        let options = xaiFileOptions(from: request.extraBody)
        var form = MultipartFormData()
        form.appendFile(name: "file", fileName: request.filename ?? "blob", mimeType: request.mediaType, data: request.data)
        if let teamID = options["teamId"]?.stringValue ?? options["team_id"]?.stringValue {
            form.appendField(name: "team_id", value: teamID)
        }

        let response = try await config.transport.send(config.rawRequest(
            path: "/files",
            modelID: "",
            body: form.finalize(),
            contentType: "multipart/form-data; boundary=\(form.boundary)",
            headers: request.headers
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        let raw = try response.jsonValue()
        var metadata: [String: JSONValue] = [:]
        if let filename = raw["filename"] { metadata["filename"] = filename }
        if let bytes = raw["bytes"] { metadata["bytes"] = bytes }
        if let createdAt = raw["created_at"] { metadata["createdAt"] = createdAt }
        return FileUploadResult(
            providerReference: ["xai": raw["id"]?.stringValue ?? ""],
            filename: raw["filename"]?.stringValue ?? request.filename,
            mediaType: request.mediaType,
            metadata: ["xai": .object(metadata)],
            rawValue: raw
        )
    }
}

private func xaiFileOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    if let nested = extraBody["xai"]?.objectValue {
        return nested
    }
    var output = extraBody
    output.removeValue(forKey: "xai")
    return output
}

private func fileMetadata(from raw: JSONValue) -> [String: JSONValue] {
    guard case let .object(object) = raw else { return [:] }
    return object
}

private func headerValue(_ headers: [String: String], _ name: String) -> String? {
    headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
}
