import Foundation

/// Enhances one supplied image using Topaz Wonder. Text-to-image and masks are
/// unsupported. Use `providerOptions["topaz"]` for enhancement and polling options.
public final class TopazImageModel: ImageModel, Sendable {
    public let providerID = "topaz.image"
    public let modelID: String
    public let supportsFileInputs: Bool? = true
    public let supportsMaskInputs: Bool? = false
    public let maxImagesPerCall = 1
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        try Task.checkCancellation()
        try request.abortSignal?.throwIfAborted()
        let timestamp = Date()
        let options = try topazOptions(providerOptions: request.providerOptions, extraBody: request.extraBody, video: false)
        var warnings: [AIWarning] = []
        // Swift's shared image request requires a String; empty means no prompt.
        if !request.prompt.isEmpty { warnings.append(topazWarning("prompt", "Topaz enhances an existing image; the text prompt was ignored.")) }
        if request.aspectRatio != nil { warnings.append(topazWarning("aspectRatio", "Use size or outputWidth/outputHeight for Topaz output dimensions.")) }
        if request.seed != nil { warnings.append(topazWarning("seed", "Topaz image models do not support seed.")) }
        if request.mask != nil { warnings.append(topazWarning("mask", "Topaz image models do not support masks.")) }
        if (request.count ?? 1) > 1 { warnings.append(topazWarning("n", "Topaz enhances one image per call; only one image will be returned.")) }
        guard let input = request.files.first else {
            throw AIError.invalidArgument(argument: "files", message: "Topaz image models enhance an existing image. Pass the input image via files.")
        }
        if request.files.count > 1 { warnings.append(topazWarning("files", "Topaz enhances one image per call; only the first file was used.")) }

        var form = MultipartFormData()
        form.appendField(name: "model", value: modelID == "wonder-3.5" ? "Wonder 3.5" : modelID)
        if let url = input.url {
            form.appendField(name: "source_url", value: url)
        } else if let bytes = input.data {
            let mediaType = input.mediaType ?? "image/png"
            let ext = mediaTypeToExtension(mediaType)
            form.appendFile(name: "image", fileName: "image.\(ext)", mimeType: mediaType, data: bytes)
        } else {
            throw AIError.invalidArgument(argument: "files", message: "Topaz input image must contain data or a URL.")
        }
        let dimensions = try topazDimensions(request.size, argument: "size")
        var fields = options.filter { !["pollIntervalMillis", "pollTimeoutMillis"].contains($0.key) }
        fields["outputWidth"] = options["outputWidth"] ?? dimensions.width
        fields["outputHeight"] = options["outputHeight"] ?? dimensions.height
        let wireNames = ["outputWidth": "output_width", "outputHeight": "output_height", "outputFormat": "output_format", "cropToFill": "crop_to_fill", "webhookUrl": "webhook_url"]
        for key in fields.keys.sorted() {
            guard let value = fields[key] else { continue }
            let text: String
            switch value {
            case let .string(string): text = string
            case let .bool(bool): text = String(bool)
            case let .number(number): text = Int(exactly: number).map(String.init) ?? String(number)
            default: continue
            }
            form.appendField(name: wireNames[key] ?? key, value: text)
        }
        let submitResponse = try await config.transport.send(config.rawRequest(
            path: "/image/v1/enhance-gen/async", modelID: modelID, body: form.finalize(),
            contentType: "multipart/form-data; boundary=\(form.boundary)", headers: normalizeHeaders(request.headers), abortSignal: request.abortSignal
        ))
        let submit = try topazResponseJSON(submitResponse, provider: providerID)
        guard let processID = submit["process_id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Topaz did not return a process_id for the enhance request.")
        }
        let status = try await poll(processID: processID, options: options, request: request)
        let downloadResponse = try await get("/image/v1/download/\(topazPathComponent(processID))", request: request)
        let download = try topazResponseJSON(downloadResponse, provider: providerID)
        guard let url = download["download_url"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Topaz did not return a download URL for process \(processID).")
        }
        let image = try await downloadURL(
            url, transport: config.transport, headers: topazHeaders(config, request.headers),
            abortSignal: request.abortSignal, trustedOrigin: config.baseURL, credentialedOrigin: config.baseURL
        )
        guard (200..<300).contains(image.statusCode) else { throw topazHTTPError(provider: providerID, response: image) }
        var metadata: [String: JSONValue] = ["processId": .string(processID)]
        for (wire, key) in [("credits", "credits"), ("output_width", "width"), ("output_height", "height"), ("output_format", "format")] {
            metadata[key] = topazNonNull(status[wire])
        }
        return ImageGenerationResult(
            urls: [url], base64Images: [image.body.base64EncodedString()], rawValue: status, warnings: warnings,
            providerMetadata: ["topaz": ["images": .array([.object(metadata)])]],
            requestMetadata: imageGenerationRequestMetadata(request),
            responseMetadata: AIResponseMetadata(timestamp: timestamp, modelID: modelID, headers: image.headers)
        )
    }

    private func get(_ path: String, request: ImageGenerationRequest) async throws -> AIHTTPResponse {
        try request.abortSignal?.throwIfAborted()
        return try await config.transport.send(AIHTTPRequest(
            method: "GET", url: config.url(modelID, path),
            headers: topazHeaders(config, request.headers), abortSignal: request.abortSignal
        ))
    }

    private func poll(processID: String, options: [String: JSONValue], request: ImageGenerationRequest) async throws -> JSONValue {
        let interval = options["pollIntervalMillis"]?.doubleValue ?? 2_000
        let timeout = options["pollTimeoutMillis"]?.doubleValue ?? 600_000
        guard let timeoutMillis = Int(exactly: timeout), let intervalMillis = Int(exactly: interval) else {
            throw AIError.invalidArgument(argument: "providerOptions.topaz", message: "Topaz polling durations exceed the supported integer range.")
        }
        let controller = AIAbortController()
        let timer = setAbortTimeout(abortController: controller, label: "Topaz image enhancement", timeoutMilliseconds: timeoutMillis)
        defer { timer?.cancel() }
        let signal = mergeAbortSignals(request.abortSignal, controller.signal) ?? controller.signal
        var pollingRequest = request
        pollingRequest.abortSignal = signal
        let resolvedRequest = pollingRequest
        let started = DispatchTime.now().uptimeNanoseconds
        var lastStatus = "unknown"
        do {
            while true {
                try Task.checkCancellation()
                let response = try await raceAbortSignal(signal) {
                    try await self.get("/image/v1/status/\(topazPathComponent(processID))", request: resolvedRequest)
                }
                let raw = try topazResponseJSON(response, provider: providerID)
                try topazResponseFields(raw, provider: providerID, strings: ["status", "output_format"], numbers: ["credits", "output_width", "output_height"])
                lastStatus = raw["status"]?.stringValue ?? "unknown"
                if lastStatus == "Completed" { return raw }
                if ["Failed", "Cancelled"].contains(lastStatus) {
                    throw AIError.invalidResponse(provider: providerID, message: "Topaz image enhancement \(lastStatus.lowercased()) for process \(processID).")
                }
                let elapsedMillis = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
                if elapsedMillis + interval > timeout {
                    controller.abort(reason: "Topaz image enhancement timeout", reasonName: "TimeoutError")
                    try controller.signal.throwIfAborted()
                }
                try await delay(intervalMillis, abortSignal: signal)
            }
        } catch {
            if controller.signal.isAborted || request.abortSignal?.isAborted == true || Task.isCancelled {
                await topazCancelQuietly(config: config, modelID: modelID, path: "/image/v1/cancel/\(topazPathComponent(processID))", headers: request.headers)
            }
            if controller.signal.isAborted {
                throw AIError.invalidResponse(provider: providerID, message: "Topaz image enhancement did not finish within \(timeoutMillis)ms (process \(processID), last status \(lastStatus)). Increase pollTimeoutMillis if the job needs longer.")
            }
            throw error
        }
    }
}
