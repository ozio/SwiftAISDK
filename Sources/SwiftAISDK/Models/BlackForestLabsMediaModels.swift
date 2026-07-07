import Foundation

public final class BlackForestLabsImageModel: ImageModel, @unchecked Sendable {
    public let providerID = "black-forest-labs.image"
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        let options = try blackForestLabsProviderOptions(from: request)
        let warnings = blackForestLabsWarnings(for: request)
        var body: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if let aspectRatio = request.aspectRatio {
            body["aspect_ratio"] = .string(aspectRatio)
        } else if let aspectRatio = options["aspectRatio"] ?? options["aspect_ratio"] {
            body["aspect_ratio"] = aspectRatio
        } else if let size = request.size, let aspectRatio = bflAspectRatio(from: size) {
            body["aspect_ratio"] = .string(aspectRatio)
        }
        if let dimensions = bflDimensions(from: request.size) {
            body["width"] = options["width"] ?? .number(Double(dimensions.width))
            body["height"] = options["height"] ?? .number(Double(dimensions.height))
        }
        body.merge(blackForestLabsOptions(from: options)) { _, new in new }
        if let seed = request.seed {
            body["seed"] = .number(Double(seed))
        }
        body.merge(try blackForestLabsImageInputs(files: request.files, mask: request.mask, modelID: modelID)) { _, new in new }
        let submitResponse = try await config.transport.send(config.request(path: "/\(modelID)", modelID: modelID, body: .object(body), headers: request.headers, abortSignal: request.abortSignal))
        guard (200..<300).contains(submitResponse.statusCode) else {
            throw blackForestLabsHTTPStatusError(provider: providerID, response: submitResponse)
        }
        let submitted = (json: try submitResponse.jsonValue(), response: submitResponse)
        guard let pollURL = submitted.json["polling_url"]?.stringValue,
              let requestID = submitted.json["id"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Black Forest Labs submit response did not contain id and polling_url.")
        }
        let raw = try await pollBFL(
            url: pollURL,
            id: requestID,
            headers: request.headers,
            intervalNanoseconds: bflPollInterval(options),
            timeoutNanoseconds: bflPollTimeout(options),
            abortSignal: request.abortSignal
        )
        guard let url = raw["result"]?["sample"]?.stringValue else {
            throw AIError.invalidResponse(provider: providerID, message: "Black Forest Labs poll response is Ready but missing result.sample")
        }
        let imageHeaders = blackForestLabsTrustedHeaders(for: url, baseURL: config.baseURL, headers: config.headers.mergingHeaders(request.headers))
        let image = try await downloadURL(url, transport: config.transport, headers: imageHeaders, abortSignal: request.abortSignal)
        guard (200..<300).contains(image.statusCode) else {
            throw apiCallError(provider: providerID, response: image)
        }
        return ImageGenerationResult(
            urls: [url],
            base64Images: [image.body.base64EncodedString()],
            rawValue: raw,
            warnings: warnings,
            providerMetadata: blackForestLabsProviderMetadata(submit: submitted.json, poll: raw),
            requestMetadata: imageGenerationRequestMetadata(request, body: .object(body)),
            responseMetadata: AIResponseMetadata(timestamp: Date(), modelID: modelID, headers: image.headers)
        )
    }

    private func pollBFL(url: String, id: String, headers: [String: String], intervalNanoseconds: UInt64, timeoutNanoseconds: UInt64, abortSignal: AIAbortSignal?) async throws -> JSONValue {
        let pollURL = appendQueryItemIfMissing(url: url, name: "id", value: id)
        let maxPollAttempts = bflMaxPollAttempts(intervalNanoseconds: intervalNanoseconds, timeoutNanoseconds: timeoutNanoseconds)
        for attempt in 0..<maxPollAttempts {
            let pollHeaders = blackForestLabsTrustedHeaders(for: pollURL, baseURL: config.baseURL, headers: config.headers.mergingHeaders(headers))
            let response = try await downloadURL(pollURL, transport: config.transport, headers: pollHeaders, abortSignal: abortSignal)
            guard (200..<300).contains(response.statusCode) else {
                throw blackForestLabsHTTPStatusError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            let status = raw["status"]?.stringValue ?? raw["state"]?.stringValue
            guard let status else {
                throw AIError.invalidResponse(provider: providerID, message: "Missing status in Black Forest Labs poll response")
            }
            if status == "Ready" { return raw }
            if status == "Error" || status == "Failed" {
                throw AIError.invalidResponse(provider: providerID, message: "Black Forest Labs generation failed.")
            }
            if attempt < maxPollAttempts - 1 {
                try await sleepWithAbortSignal(nanoseconds: intervalNanoseconds, abortSignal: abortSignal)
            }
        }
        throw AIError.invalidResponse(provider: providerID, message: "Black Forest Labs generation timed out.")
    }
}

private func blackForestLabsTrustedHeaders(for url: String, baseURL: String, headers: [String: String]) -> [String: String] {
    blackForestLabsIsTrustedURL(url, baseURL: baseURL) ? headers : [:]
}

private func blackForestLabsIsTrustedURL(_ url: String, baseURL: String) -> Bool {
    if isSameOriginURL(url, baseURL) {
        return true
    }
    guard let components = URLComponents(string: url),
          components.scheme?.lowercased() == "https",
          let hostname = components.host?.lowercased() else {
        return false
    }
    return hostname == "bfl.ai" || hostname.hasSuffix(".bfl.ai")
}

private func isSameOriginURL(_ lhs: String, _ rhs: String) -> Bool {
    guard let left = URLComponents(string: lhs),
          let right = URLComponents(string: rhs),
          let leftScheme = left.scheme?.lowercased(),
          let rightScheme = right.scheme?.lowercased(),
          let leftHost = left.host?.lowercased(),
          let rightHost = right.host?.lowercased(),
          leftScheme == rightScheme,
          leftHost == rightHost else {
        return false
    }
    return (left.port ?? defaultPort(for: leftScheme)) == (right.port ?? defaultPort(for: rightScheme))
}

private func defaultPort(for scheme: String) -> Int? {
    switch scheme {
    case "http": return 80
    case "https": return 443
    default: return nil
    }
}

private func blackForestLabsProviderOptions(from request: ImageGenerationRequest) throws -> [String: JSONValue] {
    var output = blackForestLabsProviderOptions(from: request.extraBody)
    if let providerValue = request.providerOptions["blackForestLabs"] {
        guard providerValue != .null else { return output }
        guard let providerOptions = providerValue.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.blackForestLabs", message: "Black Forest Labs provider options must be an object.")
        }
        output.merge(try blackForestLabsValidatedProviderOptions(from: providerOptions)) { _, providerValue in providerValue }
    }
    return output
}

private func blackForestLabsHTTPStatusError(provider: String, response: AIHTTPResponse) -> AIError {
    let body = blackForestLabsErrorMessage(from: response.body) ?? response.bodyText
    guard !response.headers.isEmpty else {
        return .apiCall(provider: provider, statusCode: response.statusCode, body: body)
    }
    return .apiCall(provider: provider, statusCode: response.statusCode, body: body, headers: response.headers)
}

private func blackForestLabsErrorMessage(from data: Data) -> String? {
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
    return json["message"]?.stringValue ?? "Unknown Black Forest Labs error"
}

private func blackForestLabsProviderOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    if let nested = extraBody["blackForestLabs"]?.objectValue {
        return nested
    }
    var output = extraBody
    output.removeValue(forKey: "blackForestLabs")
    return output
}

private func blackForestLabsOptions(from extraBody: [String: JSONValue]) -> [String: JSONValue] {
    var output = extraBody
    output.removeValue(forKey: "aspectRatio")
    output.removeValue(forKey: "aspect_ratio")
    blackForestLabsMoveKey("imagePrompt", to: "image_prompt", in: &output)
    blackForestLabsMoveKey("imagePromptStrength", to: "image_prompt_strength", in: &output)
    blackForestLabsMoveKey("outputFormat", to: "output_format", in: &output)
    blackForestLabsMoveKey("promptUpsampling", to: "prompt_upsampling", in: &output)
    blackForestLabsMoveKey("safetyTolerance", to: "safety_tolerance", in: &output)
    blackForestLabsMoveKey("webhookSecret", to: "webhook_secret", in: &output)
    blackForestLabsMoveKey("webhookUrl", to: "webhook_url", in: &output)
    blackForestLabsMoveKey("inputImage", to: "input_image", in: &output)
    for index in 2...10 {
        blackForestLabsMoveKey("inputImage\(index)", to: "input_image_\(index)", in: &output)
    }
    output.removeValue(forKey: "pollIntervalMillis")
    output.removeValue(forKey: "pollTimeoutMillis")
    return output
}

private func blackForestLabsValidatedProviderOptions(from options: [String: JSONValue]) throws -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in options where blackForestLabsSupportedProviderOptionKeys.contains(key) {
        switch key {
        case "imagePrompt", "inputImage", "inputImage2", "inputImage3", "inputImage4", "inputImage5", "inputImage6", "inputImage7", "inputImage8", "inputImage9", "inputImage10", "webhookSecret":
            guard value.stringValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.blackForestLabs.\(key)", message: "Black Forest Labs \(key) must be a string.")
            }
        case "webhookUrl":
            guard let url = value.stringValue, blackForestLabsIsURL(url) else {
                throw AIError.invalidArgument(argument: "providerOptions.blackForestLabs.webhookUrl", message: "Black Forest Labs webhookUrl must be a valid URL.")
            }
        case "imagePromptStrength":
            guard let number = value.doubleValue, number >= 0, number <= 1 else {
                throw AIError.invalidArgument(argument: "providerOptions.blackForestLabs.imagePromptStrength", message: "Black Forest Labs imagePromptStrength must be between 0 and 1.")
            }
        case "steps", "pollIntervalMillis", "pollTimeoutMillis":
            guard let number = value.doubleValue, blackForestLabsIsInteger(number), number > 0 else {
                throw AIError.invalidArgument(argument: "providerOptions.blackForestLabs.\(key)", message: "Black Forest Labs \(key) must be a positive integer.")
            }
        case "guidance":
            guard let number = value.doubleValue, number >= 0 else {
                throw AIError.invalidArgument(argument: "providerOptions.blackForestLabs.guidance", message: "Black Forest Labs guidance must be greater than or equal to 0.")
            }
        case "width", "height":
            guard let number = value.doubleValue, blackForestLabsIsInteger(number), number >= 256, number <= 1920 else {
                throw AIError.invalidArgument(argument: "providerOptions.blackForestLabs.\(key)", message: "Black Forest Labs \(key) must be an integer between 256 and 1920.")
            }
        case "outputFormat":
            guard let format = value.stringValue, ["jpeg", "png"].contains(format) else {
                throw AIError.invalidArgument(argument: "providerOptions.blackForestLabs.outputFormat", message: "Black Forest Labs outputFormat must be one of jpeg, png.")
            }
        case "promptUpsampling", "raw":
            guard value.boolValue != nil else {
                throw AIError.invalidArgument(argument: "providerOptions.blackForestLabs.\(key)", message: "Black Forest Labs \(key) must be a boolean.")
            }
        case "safetyTolerance":
            guard let number = value.doubleValue, blackForestLabsIsInteger(number), number >= 0, number <= 6 else {
                throw AIError.invalidArgument(argument: "providerOptions.blackForestLabs.safetyTolerance", message: "Black Forest Labs safetyTolerance must be an integer between 0 and 6.")
            }
        default:
            break
        }
        output[key] = value
    }
    return output
}

private let blackForestLabsSupportedProviderOptionKeys: Set<String> = [
    "imagePrompt",
    "imagePromptStrength",
    "inputImage",
    "inputImage2",
    "inputImage3",
    "inputImage4",
    "inputImage5",
    "inputImage6",
    "inputImage7",
    "inputImage8",
    "inputImage9",
    "inputImage10",
    "steps",
    "guidance",
    "width",
    "height",
    "outputFormat",
    "promptUpsampling",
    "raw",
    "safetyTolerance",
    "webhookSecret",
    "webhookUrl",
    "pollIntervalMillis",
    "pollTimeoutMillis"
]

private func blackForestLabsWarnings(for request: ImageGenerationRequest) -> [AIWarning] {
    guard request.size != nil else { return [] }
    if request.aspectRatio == nil {
        return [
            AIWarning(
                type: "unsupported",
                feature: "size",
                message: "Deriving aspect_ratio from size. Use the width and height provider options to specify dimensions for models that support them."
            )
        ]
    }
    return [
        AIWarning(
            type: "unsupported",
            feature: "size",
            message: "Black Forest Labs ignores size when aspectRatio is provided. Use the width and height provider options to specify dimensions for models that support them"
        )
    ]
}

private func blackForestLabsProviderMetadata(submit: JSONValue, poll: JSONValue) -> [String: JSONValue] {
    let imageMetadata: JSONValue = .object([
        "seed": blackForestLabsNonNull(poll["result"]?["seed"]),
        "start_time": blackForestLabsNonNull(poll["result"]?["start_time"]),
        "end_time": blackForestLabsNonNull(poll["result"]?["end_time"]),
        "duration": blackForestLabsNonNull(poll["result"]?["duration"]),
        "cost": blackForestLabsNonNull(submit["cost"]),
        "inputMegapixels": blackForestLabsNonNull(submit["input_mp"]),
        "outputMegapixels": blackForestLabsNonNull(submit["output_mp"])
    ])
    return [
        "blackForestLabs": .object([
            "images": .array([imageMetadata])
        ])
    ]
}

private func blackForestLabsNonNull(_ value: JSONValue?) -> JSONValue? {
    guard value != .null else { return nil }
    return value
}

private func blackForestLabsImageInputs(files: [ImageInputFile], mask: ImageInputFile?, modelID: String) throws -> [String: JSONValue] {
    guard files.count <= 10 else {
        throw AIError.invalidArgument(argument: "files", message: "Black Forest Labs supports up to 10 input images.")
    }
    let inputImageField = modelID == "flux-pro-1.0-fill" ? "image" : "input_image"
    var output: [String: JSONValue] = [:]
    for (index, file) in files.enumerated() {
        let key = index == 0 ? inputImageField : "\(inputImageField)_\(index + 1)"
        output[key] = .string(blackForestLabsImageString(file))
    }
    if let mask {
        output["mask"] = .string(blackForestLabsImageString(mask))
    }
    return output
}

private func blackForestLabsImageString(_ file: ImageInputFile) -> String {
    if let url = file.url {
        return url
    }
    if let data = file.data {
        return data.base64EncodedString()
    }
    return ""
}

private func blackForestLabsMoveKey(_ source: String, to destination: String, in values: inout [String: JSONValue]) {
    if let value = values.removeValue(forKey: source) {
        values[destination] = value
    }
}

private func blackForestLabsIsInteger(_ value: Double) -> Bool {
    value.isFinite && value.rounded(.towardZero) == value
}

private func blackForestLabsIsURL(_ value: String) -> Bool {
    guard let components = URLComponents(string: value) else { return false }
    return components.scheme != nil && components.host != nil
}

private func bflAspectRatio(from size: String) -> String? {
    let dimensions = size.split(separator: "x").compactMap { Int($0) }
    guard dimensions.count == 2, dimensions[0] > 0, dimensions[1] > 0 else { return nil }
    let divisor = bflGCD(dimensions[0], dimensions[1])
    return "\(dimensions[0] / divisor):\(dimensions[1] / divisor)"
}

private func bflDimensions(from size: String?) -> (width: Int, height: Int)? {
    guard let size else { return nil }
    let dimensions = size.split(separator: "x").compactMap { Int($0) }
    guard dimensions.count == 2, dimensions[0] > 0, dimensions[1] > 0 else { return nil }
    return (dimensions[0], dimensions[1])
}

private func bflGCD(_ lhs: Int, _ rhs: Int) -> Int {
    var a = abs(lhs)
    var b = abs(rhs)
    while b != 0 {
        let next = a % b
        a = b
        b = next
    }
    return max(a, 1)
}

private func bflPollInterval(_ extraBody: [String: JSONValue]) -> UInt64 {
    let milliseconds = extraBody["pollIntervalMillis"]?.intValue ?? 500
    return UInt64(max(milliseconds, 1)) * 1_000_000
}

private func bflPollTimeout(_ extraBody: [String: JSONValue]) -> UInt64 {
    let milliseconds = extraBody["pollTimeoutMillis"]?.intValue ?? 60_000
    return UInt64(max(milliseconds, 1)) * 1_000_000
}

private func bflMaxPollAttempts(intervalNanoseconds: UInt64, timeoutNanoseconds: UInt64) -> Int {
    let interval = max(intervalNanoseconds, 1)
    let attempts = (timeoutNanoseconds + interval - 1) / interval
    return max(Int(attempts), 1)
}
