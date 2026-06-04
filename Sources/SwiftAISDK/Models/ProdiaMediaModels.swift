import Foundation

public final class ProdiaLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID = "prodia.language"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        try await prodiaGenerate(request).result
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let generated = try await prodiaGenerate(request)
                    let result = generated.result
                    continuation.yield(.streamStart(warnings: result.warnings))
                    continuation.yield(.responseMetadata(result.responseMetadata))
                    if !result.text.isEmpty {
                        let id = UUID().uuidString
                        continuation.yield(.textStart(id: id))
                        continuation.yield(.textDeltaPart(id: id, delta: result.text))
                        continuation.yield(.textEnd(id: id))
                    }
                    for file in generated.files {
                        continuation.yield(.file(file))
                    }
                    continuation.yield(.finishMetadata(reason: result.finishReason, usage: result.usage, providerMetadata: result.providerMetadata))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func prodiaGenerate(_ request: LanguageModelRequest) async throws -> ProdiaLanguageGeneration {
        let options = try prodiaProviderOptions(from: request)
        let warnings = prodiaLanguageWarnings(for: request)
        var jobConfig: [String: JSONValue] = [
            "prompt": .string(prodiaPrompt(from: request.messages)),
            "include_messages": .bool(true)
        ]
        if let aspectRatio = options["aspectRatio"]?.stringValue ?? options["aspect_ratio"]?.stringValue {
            jobConfig["aspect_ratio"] = .string(aspectRatio)
        }

        let body: JSONValue = .object([
            "type": .string(modelID),
            "config": .object(jobConfig)
        ])
        var form = MultipartFormData()
        form.appendFile(name: "job", fileName: "job.json", mimeType: "application/json", data: try encodeJSONBody(body))
        if let input = try await prodiaInputImage(from: request.messages, transport: config.transport, abortSignal: request.abortSignal) {
            form.appendFile(name: "input", fileName: "input\(mediaExtension(input.mimeType))", mimeType: input.mimeType, data: input.data)
        }
        let payload = form.finalize()
        var headers = request.headers.mergingHeaders([
            "Accept": "multipart/form-data",
            "Content-Type": "multipart/form-data; boundary=\(form.boundary)"
        ])
        headers = config.headers.mergingHeaders(headers)
        let response = try await config.transport.send(AIHTTPRequest(
            method: "POST",
            url: try requireURL("\(withoutTrailingSlash(config.baseURL))/job?price=true"),
            headers: headers,
            body: payload,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw prodiaHTTPStatusError(provider: providerID, response: response)
        }
        let multipart = try parseMultipartResponse(response)
        guard multipart.contains(where: { $0.name == "job" }) else {
            throw AIError.invalidResponse(provider: providerID, message: "Prodia multipart response missing job part")
        }
        let text = multipart.first {
            ($0.name == "output" && ($0.contentType?.hasPrefix("text/") == true || $0.fileName?.hasSuffix(".txt") == true))
                || $0.contentType?.hasPrefix("text/") == true
        }.flatMap { String(data: $0.body, encoding: .utf8) } ?? ""
        let job = prodiaJobResult(from: multipart)
        let files = prodiaLanguageFiles(from: multipart)
        let rawValue = multipartRawValue(multipart)
        return ProdiaLanguageGeneration(
            result: TextGenerationResult(
                text: text,
                finishReason: "stop",
                usage: TokenUsage(),
                providerMetadata: ["prodia": prodiaProviderMetadata(from: job)],
                rawValue: rawValue,
                warnings: warnings,
                responseMetadata: aiResponseMetadata(from: job, response: response, modelID: modelID)
            ),
            files: files
        )
    }
}

public final class ProdiaImageModel: ImageModel, @unchecked Sendable {
    public let providerID = "prodia.image"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        let options = try prodiaProviderOptions(from: request)
        var warnings: [AIWarning] = []
        var jobConfig: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if let size = request.size {
            let parts = size.split(separator: "x", omittingEmptySubsequences: false).map(String.init)
            if parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) {
                jobConfig["width"] = .number(Double(width))
                jobConfig["height"] = .number(Double(height))
            } else {
                warnings.append(AIWarning(
                    type: "unsupported",
                    feature: "size",
                    message: "Invalid size format: \(size). Expected format: WIDTHxHEIGHT (e.g., 1024x1024)"
                ))
            }
        }
        if let seed = request.seed {
            jobConfig["seed"] = .number(Double(seed))
        }
        jobConfig.merge(prodiaImageOptions(from: options)) { _, new in new }
        let body: JSONValue = .object([
            "type": .string(modelID),
            "config": .object(jobConfig)
        ])
        let response = try await config.transport.send(config.request(
            path: "/job?price=true",
            modelID: modelID,
            body: try prodiaJSONJobRequestBody(body),
            headers: request.headers.mergingHeaders(["Accept": "multipart/form-data; image/png"]),
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw prodiaHTTPStatusError(provider: providerID, response: response)
        }
        let multipart = try parseMultipartResponse(response)
        guard multipart.contains(where: { $0.name == "job" }) else {
            throw AIError.invalidResponse(provider: providerID, message: "Prodia multipart response missing job part")
        }
        let output = multipart.first { $0.name == "output" || $0.contentType?.hasPrefix("image/") == true }
        guard let output else {
            throw AIError.invalidResponse(provider: providerID, message: "Prodia multipart response missing output image")
        }
        let job = prodiaJobResult(from: multipart)
        return ImageGenerationResult(
            urls: [],
            base64Images: [output.body.base64EncodedString()],
            rawValue: multipartRawValue(multipart),
            warnings: warnings,
            providerMetadata: ["prodia": .object(["images": .array([prodiaProviderMetadata(from: job)])])],
            requestMetadata: imageGenerationRequestMetadata(request, body: body),
            responseMetadata: aiResponseMetadata(from: job, response: response, modelID: modelID)
        )
    }
}

public final class ProdiaVideoModel: VideoModel, @unchecked Sendable {
    public let providerID = "prodia.video"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        let options = try prodiaProviderOptions(from: request)
        var jobConfig: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if let seed = request.seed {
            jobConfig["seed"] = .number(Double(seed))
        } else if let seed = options["seed"] {
            jobConfig["seed"] = seed
        }
        if let resolution = options["resolution"] { jobConfig["resolution"] = resolution }
        let body: JSONValue = .object([
            "type": .string(modelID),
            "config": .object(jobConfig)
        ])
        let response: AIHTTPResponse
        if let image = request.image {
            let input = try await prodiaVideoInputImage(from: image, transport: config.transport, abortSignal: request.abortSignal)
            var form = MultipartFormData()
            form.appendFile(name: "job", fileName: "job.json", mimeType: "application/json", data: try encodeJSONBody(body))
            form.appendFile(name: "input", fileName: "input\(mediaExtension(input.mimeType))", mimeType: input.mimeType, data: input.data)
            let payload = form.finalize()
            let headers = config.headers.mergingHeaders(request.headers).mergingHeaders([
                "Accept": "multipart/form-data; video/mp4",
                "Content-Type": "multipart/form-data; boundary=\(form.boundary)"
            ])
            response = try await config.transport.send(AIHTTPRequest(
                method: "POST",
                url: try requireURL("\(withoutTrailingSlash(config.baseURL))/job?price=true"),
                headers: headers,
                body: payload,
                abortSignal: request.abortSignal
            ))
        } else {
            response = try await config.transport.send(config.request(
                path: "/job?price=true",
                modelID: modelID,
                body: try prodiaJSONJobRequestBody(body),
                headers: request.headers.mergingHeaders(["Accept": "multipart/form-data; video/mp4"]),
                abortSignal: request.abortSignal
            ))
        }
        guard (200..<300).contains(response.statusCode) else {
            throw prodiaHTTPStatusError(provider: providerID, response: response)
        }
        let multipart = try parseMultipartResponse(response)
        guard multipart.contains(where: { $0.name == "job" }) else {
            throw AIError.invalidResponse(provider: providerID, message: "Prodia multipart response missing job part")
        }
        let output = multipart.first { $0.name == "output" || $0.contentType?.hasPrefix("video/") == true }
        guard output != nil else {
            throw AIError.invalidResponse(provider: providerID, message: "Prodia multipart response missing output video")
        }
        let job = prodiaJobResult(from: multipart)
        return VideoGenerationResult(
            urls: [],
            operationID: job?["id"]?.stringValue,
            rawValue: multipartRawValue(multipart),
            providerMetadata: ["prodia": .object(["videos": .array([prodiaProviderMetadata(from: job)])])],
            requestMetadata: videoGenerationRequestMetadata(request, body: body),
            responseMetadata: aiResponseMetadata(from: job, response: response, modelID: modelID)
        )
    }
}

