import Foundation

/// Topaz Proteus and Starlight video enhancement through serializable V4
/// start/status operations. Use `AI.generateVideo` for shared polling.
public final class TopazVideoModel: AsyncVideoModel, Sendable {
    public let providerID = "topaz.video"
    public let modelID: String
    public let supportsUnaryVideoGeneration = false
    public let maxVideosPerCall = 1
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func startVideoGeneration(_ operationRequest: VideoGenerationOperationStartRequest) async throws -> VideoGenerationOperationStartResult {
        let request = operationRequest.request
        try Task.checkCancellation()
        try request.abortSignal?.throwIfAborted()
        let timestamp = Date()
        let options = try topazOptions(providerOptions: request.providerOptions, extraBody: request.extraBody, video: true)
        var warnings = topazVideoWarnings(request)
        guard let input = request.inputReferences.first(where: topazIsVideo) else {
            if request.image != nil {
                throw AIError.invalidArgument(argument: "image", message: "Topaz enhances an existing video, not a still image. Pass it via inputReferences.")
            }
            throw AIError.invalidArgument(argument: "inputReferences", message: "Topaz video models require an input video. Pass it via inputReferences with a video mediaType or recognized URL extension.")
        }
        if request.inputReferences.count > 1 {
            warnings.append(topazWarning("inputReferences", "Topaz enhances one video; only the first video reference was used."))
        }
        let container = try topazInputContainer(input, declared: options["source"]?["container"]?.stringValue)
        var source = try topazVideoSource(options["source"]?.objectValue ?? [:], container: container)
        let output = try topazVideoOutput(options["output"]?.objectValue ?? [:], source: source, request: request)
        var filter: [String: JSONValue] = ["model": .string(["proteus": "prob-4", "starlight-precise-2.6": "slp-2.6"][modelID] ?? modelID)]
        filter.merge(options.filter { !["source", "output", "filter", "additionalFilters"].contains($0.key) }) { _, new in new }
        filter.merge(options["filter"]?.objectValue ?? [:]) { _, new in new }
        if let url = input.url {
            source["external"] = ["provider": "s3", "presignedUrl": .string(url)]
        } else if let data = input.data {
            source["size"] = .number(Double(data.count))
        } else {
            throw AIError.invalidArgument(argument: "inputReferences", message: "Topaz input video must contain data or a URL.")
        }
        let body: JSONValue = [
            "source": .object(source), "output": .object(output),
            "filters": .array([.object(filter)] + (options["additionalFilters"]?.arrayValue ?? []))
        ]
        var requestID: String?
        do {
            let response = try await config.transport.send(config.request(
                path: "/video/express", modelID: modelID, body: body, headers: normalizeHeaders(request.headers), abortSignal: request.abortSignal
            ))
            let created = try topazResponseJSON(response, provider: providerID)
            try topazValidateVideoResponse(created, provider: providerID, status: false)
            guard let id = created["requestId"]?.stringValue else {
                throw AIError.invalidResponse(provider: providerID, message: "Topaz did not return a requestId for the video request.")
            }
            requestID = id
            if input.url == nil, let bytes = input.data {
                guard let url = created["uploadUrls"]?[0]?.stringValue else {
                    throw AIError.invalidResponse(provider: providerID, message: "Topaz returned no upload URL for request \(id).")
                }
                let uploadURL: URL
                if isSameOrigin(url, config.baseURL), let trusted = URL(string: url) {
                    uploadURL = trusted
                } else {
                    uploadURL = try validateDownloadURL(url)
                }
                try request.abortSignal?.throwIfAborted()
                // The presigned upload carries its own credentials. Do not
                // attach custom provider/call headers, even on the same origin.
                let upload = try await config.transport.send(AIHTTPRequest(
                    method: "PUT", url: uploadURL,
                    headers: withUserAgentSuffix(["content-type": topazContainerMediaTypes[container] ?? "application/octet-stream"], "ai-sdk-topaz/3.0.0"),
                    body: bytes, abortSignal: request.abortSignal, followRedirects: false
                ))
                guard (200..<300).contains(upload.statusCode) else {
                    throw topazHTTPError(provider: providerID, response: upload, message: "Uploading the input video failed with status \(upload.statusCode).")
                }
            }
            try Task.checkCancellation()
            try request.abortSignal?.throwIfAborted()
            var metadata: [String: JSONValue] = ["requestId": .string(id)]
            metadata["estimatedCredits"] = topazNonNull(created["estimates"]?["cost"])
            return VideoGenerationOperationStartResult(
                operation: ["requestId": .string(id), "outputContainer": output["container"] ?? "mp4"],
                warnings: warnings, providerMetadata: ["topaz": .object(metadata)],
                responseMetadata: AIResponseMetadata(timestamp: timestamp, modelID: modelID, headers: response.headers)
            )
        } catch {
            if let requestID {
                await topazCancelQuietly(config: config, modelID: modelID, path: "/video/\(topazPathComponent(requestID))", headers: request.headers)
            }
            throw error
        }
    }

    public func videoGenerationStatus(_ request: VideoGenerationOperationStatusRequest) async throws -> VideoGenerationOperationStatusResult {
        try Task.checkCancellation()
        try request.abortSignal?.throwIfAborted()
        let timestamp = Date()
        guard let id = request.operation["requestId"]?.stringValue else {
            throw AIError.invalidArgument(argument: "operation", message: "Topaz video operation must contain requestId.")
        }
        let response = try await config.transport.send(AIHTTPRequest(
            method: "GET", url: config.url(modelID, "/video/\(topazPathComponent(id))/status"),
            headers: topazHeaders(config, request.headers), abortSignal: request.abortSignal
        ))
        let raw = try topazResponseJSON(response, provider: providerID)
        try topazValidateVideoResponse(raw, provider: providerID, status: true)
        let responseMetadata = AIResponseMetadata(timestamp: timestamp, modelID: modelID, headers: response.headers, body: raw)
        var metadata: [String: JSONValue] = ["requestId": .string(id)]
        if raw["status"]?.stringValue == "complete" {
            guard let url = raw["download"]?["url"]?.stringValue else {
                throw AIError.invalidResponse(provider: providerID, message: "Topaz reported request \(id) complete but returned no download URL.")
            }
            let costs = raw["estimates"]?["cost"]?.arrayValue?.compactMap(\.doubleValue) ?? []
            metadata["credits"] = costs.min().map(JSONValue.number)
            metadata["estimatedCredits"] = topazNonNull(raw["estimates"]?["cost"])
            metadata["outputSize"] = topazNonNull(raw["outputSize"])
            metadata["expiresAt"] = topazNonNull(raw["download"]?["expiresAt"])
            return .completed(VideoGenerationResult(
                urls: [url], operationID: id,
                mediaType: topazContainerMediaTypes[request.operation["outputContainer"]?.stringValue ?? "mp4"] ?? "video/mp4",
                rawValue: raw, providerMetadata: ["topaz": .object(metadata)], responseMetadata: responseMetadata
            ))
        }
        if let status = raw["status"]?.stringValue, ["failed", "canceled"].contains(status) {
            metadata["errorCode"] = topazNonNull(raw["errorCode"])
            let code = raw["errorCode"]?.stringValue.map { " (\($0))" } ?? ""
            let detail = raw["message"]?.stringValue.map { ": \($0)" } ?? "."
            return .failed(message: "Topaz video request \(id) \(status)\(code)\(detail)", providerMetadata: ["topaz": .object(metadata)], responseMetadata: responseMetadata)
        }
        return .pending(responseMetadata: responseMetadata)
    }
}

private let topazMediaTypeContainers = [
    "video/mp4": "mp4", "video/quicktime": "mov", "video/mov": "mov", "video/x-matroska": "mkv",
    "video/matroska": "mkv", "video/webm": "webm", "video/x-msvideo": "avi", "video/avi": "avi",
    "video/mpeg": "mpeg", "video/mp2t": "ts", "video/x-ms-wmv": "wmv", "video/x-flv": "flv",
    "video/3gpp": "3gp", "video/x-m4v": "m4v", "application/mxf": "mxf"
]
private let topazContainerMediaTypes = [
    "mp4": "video/mp4", "m4v": "video/mp4", "mov": "video/quicktime", "mkv": "video/x-matroska",
    "webm": "video/webm", "avi": "video/x-msvideo", "mpeg": "video/mpeg", "mpg": "video/mpeg",
    "ts": "video/mp2t", "wmv": "video/x-ms-wmv", "flv": "video/x-flv", "3gp": "video/3gpp", "mxf": "application/mxf"
]

private func topazContainerFromURL(_ url: String) -> String? {
    let path = url.components(separatedBy: CharacterSet(charactersIn: "?#"))[0]
    let ext = path.components(separatedBy: ".").last?.lowercased() ?? ""
    return ext == "qt" ? "mov" : (topazSourceContainers.contains(ext) ? ext : nil)
}

private func topazIsVideo(_ input: ImageInputFile) -> Bool {
    if let type = input.mediaType { return type.lowercased().hasPrefix("video/") }
    return input.url.flatMap(topazContainerFromURL) != nil
}

private func topazInputContainer(_ input: ImageInputFile, declared: String?) throws -> String {
    if let declared { return declared }
    if let mapped = input.mediaType.flatMap({ topazMediaTypeContainers[$0.lowercased()] }) { return mapped }
    if let url = input.url, let mapped = topazContainerFromURL(url) { return mapped }
    let detail = input.url.map { "Could not determine the container of the input video at \"\($0)\"." }
        ?? "Could not map the media type \"\(input.mediaType ?? "unknown")\" onto a Topaz container."
    throw AIError.invalidArgument(argument: "inputReferences", message: "\(detail) Set source.container explicitly.")
}

private func topazVideoSource(_ options: [String: JSONValue], container: String) throws -> [String: JSONValue] {
    var source: [String: JSONValue] = ["container": .string(container)]
    let required = ["width", "height", "duration", "frameRate"]
    guard (required + ["frameCount"]).contains(where: { options[$0] != nil }) else { return source }
    let missing = required.filter { options[$0] == nil }
    guard missing.isEmpty else {
        throw AIError.invalidArgument(argument: "providerOptions.topaz.source", message: "Source metadata must be complete. Missing: \(missing.map { "source.\($0)" }.joined(separator: ", ")).")
    }
    let frames = ((options["duration"]?.doubleValue ?? 0) * (options["frameRate"]?.doubleValue ?? 0)).rounded()
    guard options["frameCount"] != nil || frames.isFinite else {
        throw AIError.invalidArgument(argument: "providerOptions.topaz.source.frameCount", message: "Derived Topaz frameCount exceeds the supported range.")
    }
    source["duration"] = options["duration"]
    source["frameRate"] = options["frameRate"]
    source["frameCount"] = options["frameCount"] ?? .number(frames)
    source["resolution"] = .object(options.filter { ["width", "height"].contains($0.key) })
    return source
}

private func topazVideoOutput(_ options: [String: JSONValue], source: [String: JSONValue], request: VideoGenerationRequest) throws -> [String: JSONValue] {
    let dimensions = try topazDimensions(request.resolution, argument: "resolution")
    guard let width = options["width"] ?? dimensions.width ?? source["resolution"]?["width"],
          let height = options["height"] ?? dimensions.height ?? source["resolution"]?["height"] else {
        throw AIError.invalidArgument(argument: "resolution", message: "Topaz needs the output resolution. Set resolution or output.width/output.height.")
    }
    var output = options.filter { !["width", "height"].contains($0.key) }
    output["resolution"] = ["width": width, "height": height]
    output["frameRate"] = options["frameRate"] ?? request.fps.map(JSONValue.number) ?? source["frameRate"]
    output["audioTransfer"] = options["audioTransfer"] ?? "Copy"
    if output["audioTransfer"] != "None" { output["audioCodec"] = options["audioCodec"] ?? "AAC" }
    let sourceContainer = source["container"]?.stringValue ?? "mp4"
    switch options["videoEncoder"]?.stringValue {
    case "ProRes": output["container"] = "mov"
    case "AV1", "VP9": output["container"] = "mp4"
    default: output["container"] = options["container"] ?? .string(["mov", "mkv"].contains(sourceContainer) ? sourceContainer : "mp4")
    }
    return output
}

private func topazVideoWarnings(_ request: VideoGenerationRequest) -> [AIWarning] {
    var warnings: [AIWarning] = []
    if !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { warnings.append(topazWarning("prompt", "Topaz enhances an existing video; the text prompt was ignored.")) }
    if request.aspectRatio != nil { warnings.append(topazWarning("aspectRatio", "Use resolution or output dimensions for Topaz videos.")) }
    if request.seed != nil { warnings.append(topazWarning("seed", "Topaz video models do not support seed.")) }
    if request.durationSeconds != nil { warnings.append(topazWarning("duration", "Topaz enhances the whole input; set source.duration for its metadata.")) }
    if request.generateAudio != nil { warnings.append(topazWarning("generateAudio", "Topaz does not generate audio; use output.audioTransfer to retain or remove input audio.")) }
    if !request.frameImages.isEmpty { warnings.append(topazWarning("frameImages", "Topaz does not support first/last frame generation.")) }
    if (request.count ?? 1) > 1 { warnings.append(topazWarning("n", "Topaz enhances one video per call.")) }
    return warnings
}

private func topazValidateVideoResponse(_ raw: JSONValue, provider: String, status: Bool) throws {
    try topazResponseFields(raw, provider: provider, strings: status ? ["status", "message", "errorCode"] : ["requestId"])
    func invalid(_ field: String) -> AIError { .invalidResponse(provider: provider, message: "Invalid Topaz response field \(field).") }
    if !status, let urls = topazNonNull(raw["uploadUrls"]), urls.arrayValue?.allSatisfy({ $0.stringValue != nil }) != true { throw invalid("uploadUrls") }
    if let estimates = topazNonNull(raw["estimates"]) {
        guard estimates.objectValue != nil else { throw invalid("estimates") }
        for key in ["cost", "time"] {
            if let numbers = topazNonNull(estimates[key]), numbers.arrayValue?.allSatisfy({ $0.doubleValue?.isFinite == true }) != true { throw invalid("estimates.\(key)") }
        }
    }
    if status {
        if let size = topazNonNull(raw["outputSize"]), size.stringValue == nil && size.doubleValue == nil { throw invalid("outputSize") }
        if let download = topazNonNull(raw["download"]) {
            guard download.objectValue != nil else { throw invalid("download") }
            try topazResponseFields(download, provider: provider, strings: ["url"])
            if let expiry = topazNonNull(download["expiresAt"]), expiry.stringValue == nil && expiry.doubleValue == nil { throw invalid("download.expiresAt") }
        }
    }
}
