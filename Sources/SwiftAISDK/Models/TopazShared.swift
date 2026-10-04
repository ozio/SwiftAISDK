import Foundation

// Published @ai-sdk/topaz 3.0.0 option schemas. Unknown keys are stripped,
// while `filter` and `additionalFilters` deliberately remain open records.
enum TopazOptionRule: Sendable {
    case string, bool, object, objects
    case enumeration(Set<String>)
    case number(min: Double, max: Double = .greatestFiniteMagnitude, integer: Bool = false, exclusiveMin: Bool = false)
}

let topazSourceContainers: Set<String> = [
    "3gp", "avi", "dv", "flv", "m1v", "m2t", "m2ts", "m2v", "m4v", "mkv", "mov",
    "mp4", "mpeg", "mpg", "mts", "mxf", "ser", "ts", "vob", "webm", "wmv"
]
let topazOutputContainers: Set<String> = ["mp4", "mov", "mkv", "avi", "webm"]

let topazImageOptionRules: [String: TopazOptionRule] = [
    "enhancementStrength": .enumeration(["low", "medium", "high"]),
    "grain": .bool, "grainDensity": .number(min: 0, max: 1),
    "grainModel": .enumeration(["silver", "gaussian", "grey"]),
    "grainSize": .number(min: 1, max: 5), "grainStrength": .number(min: 0, max: 1),
    "inputWidth": .number(min: 0, integer: true, exclusiveMin: true),
    "inputHeight": .number(min: 0, integer: true, exclusiveMin: true),
    "outputWidth": .number(min: 1, max: 32000, integer: true),
    "outputHeight": .number(min: 1, max: 32000, integer: true),
    "outputFormat": .enumeration(["jpeg", "jpg", "png", "tiff", "tif"]),
    "cropToFill": .bool, "webhookUrl": .string,
    "pollIntervalMillis": .number(min: 0, integer: true, exclusiveMin: true),
    "pollTimeoutMillis": .number(min: 0, integer: true, exclusiveMin: true)
]

let topazVideoOptionRules: [String: TopazOptionRule] = [
    "source": .object, "output": .object, "filter": .object, "additionalFilters": .objects,
    "videoType": .enumeration(["Progressive", "Interlaced", "ProgressiveInterlaced"]),
    "auto": .enumeration(["Auto", "Manual", "Relative"]),
    "fieldOrder": .enumeration(["TopFirst", "BottomFirst", "Auto"]),
    "focusFixLevel": .enumeration(["None", "Normal", "Strong"]),
    "compression": .number(min: -1, max: 1), "details": .number(min: -1, max: 1),
    "prenoise": .number(min: 0, max: 0.1), "noise": .number(min: -1, max: 1),
    "halo": .number(min: -1, max: 1), "preblur": .number(min: -1, max: 1),
    "blur": .number(min: -1, max: 1), "grain": .number(min: 0, max: 0.1),
    "grainSigma": .number(min: 0, max: 1), "grainSize": .number(min: 0, max: 5),
    "grainType": .enumeration(["silver_rich", "gaussian", "grey"]),
    "recoverOriginalDetailValue": .number(min: 0, max: 1),
    "sharpness": .number(min: 1, max: 5),
    "videoBitDepth": .number(min: 0, integer: true, exclusiveMin: true),
    "videoCodec": .enumeration(["ffv1", "prores", "vp9"]),
    "videoProfile": .enumeration(["420", "422", "444"]), "watermark": .bool
]

private let topazVideoSourceRules: [String: TopazOptionRule] = [
    "width": .number(min: 0, integer: true, exclusiveMin: true),
    "height": .number(min: 0, integer: true, exclusiveMin: true),
    "duration": .number(min: 0, exclusiveMin: true),
    "frameRate": .number(min: 0, exclusiveMin: true),
    "frameCount": .number(min: 0, integer: true, exclusiveMin: true),
    "container": .enumeration(topazSourceContainers)
]

private let topazVideoOutputRules: [String: TopazOptionRule] = [
    "width": .number(min: 0, integer: true, exclusiveMin: true),
    "height": .number(min: 0, integer: true, exclusiveMin: true),
    "frameRate": .number(min: 0, exclusiveMin: true),
    "audioCodec": .enumeration(["AAC", "AC3", "PCM"]), "audioBitrate": .string,
    "audioTransfer": .enumeration(["Copy", "Convert", "None"]),
    "videoEncoder": .enumeration(["AV1", "H264", "H265", "ProRes", "VP9"]),
    "videoProfile": .string, "videoBitrate": .string,
    "dynamicCompressionLevel": .enumeration(["Low", "Mid", "High"]),
    "cropToFit": .bool, "container": .enumeration(topazOutputContainers)
]

func topazOptions(
    providerOptions: [String: JSONValue], extraBody: [String: JSONValue], video: Bool
) throws -> [String: JSONValue] {
    var options = extraBody["topaz"]?.objectValue ?? extraBody.filter { $0.key != "topaz" }
    if let value = providerOptions["topaz"], value != .null {
        guard let object = value.objectValue else {
            throw AIError.invalidArgument(argument: "providerOptions.topaz", message: "Topaz provider options must be an object.")
        }
        options.merge(object) { _, new in new }
    }
    options = try topazValidateOptions(options, rules: video ? topazVideoOptionRules : topazImageOptionRules)
    if video {
        for (key, rules) in [("source", topazVideoSourceRules), ("output", topazVideoOutputRules)] {
            if let object = options[key]?.objectValue {
                options[key] = .object(try topazValidateOptions(object, rules: rules, path: "providerOptions.topaz.\(key)"))
            }
        }
    }
    return options
}

private func topazValidateOptions(
    _ options: [String: JSONValue], rules: [String: TopazOptionRule], path: String = "providerOptions.topaz"
) throws -> [String: JSONValue] {
    var result: [String: JSONValue] = [:]
    for (key, value) in options {
        guard let rule = rules[key] else { continue }
        let valid: Bool
        switch rule {
        case .string: valid = value.stringValue != nil
        case .bool: valid = value.boolValue != nil
        case .object: valid = value.objectValue != nil
        case .objects: valid = value.arrayValue?.allSatisfy { $0.objectValue != nil } == true
        case let .enumeration(allowed): valid = value.stringValue.map(allowed.contains) == true
        case let .number(min, max, integer, exclusiveMin):
            if let number = value.doubleValue {
                valid = number.isFinite && (exclusiveMin ? number > min : number >= min)
                    && number <= max && (!integer || number.rounded() == number)
            } else { valid = false }
        }
        guard valid else {
            throw AIError.invalidArgument(argument: "\(path).\(key)", message: "Invalid Topaz option \(path).\(key).")
        }
        if ["pollIntervalMillis", "pollTimeoutMillis"].contains(key),
           value.doubleValue.flatMap({ Int(exactly: $0) }) == nil {
            throw AIError.invalidArgument(argument: "\(path).\(key)", message: "Topaz polling duration exceeds the supported integer range.")
        }
        result[key] = value
    }
    return result
}

func topazHTTPError(provider: String, response: AIHTTPResponse, message: String? = nil) -> AIError {
    var error = AIAPICallError(
        provider: provider, url: response.url?.absoluteString, statusCode: response.statusCode,
        responseHeaders: response.headers, responseBody: String(data: response.body, encoding: .utf8) ?? ""
    )
    if let message {
        error.message = message
    } else if let raw = try? response.jsonValue(), raw.objectValue != nil {
        let detailMessages = raw["detail"]?.arrayValue?.compactMap { $0["msg"]?.stringValue } ?? []
        var text = raw["detail"]?.stringValue
            ?? (detailMessages.isEmpty ? nil : detailMessages.joined(separator: "; "))
            ?? raw["message"]?.stringValue ?? raw["error"]?.stringValue ?? "Unknown Topaz API error"
        if let code = raw["errorCode"]?.stringValue { text += " (\(code))" }
        let issues = raw["errors"]?.arrayValue?.compactMap { $0["msg"]?.stringValue } ?? []
        if !issues.isEmpty { text += ": " + issues.joined(separator: "; ") }
        error.message = text
    }
    return .apiCall(error)
}

func topazResponseJSON(_ response: AIHTTPResponse, provider: String) throws -> JSONValue {
    guard (200..<300).contains(response.statusCode) else {
        throw topazHTTPError(provider: provider, response: response)
    }
    let raw = try response.jsonValue()
    guard raw.objectValue != nil else {
        throw AIError.invalidResponse(provider: provider, message: "Topaz response must be an object.")
    }
    return raw
}

// Optional/nullish response fields are accepted, but a present value must have
// the published type. Unknown status strings remain pending.
func topazResponseFields(_ raw: JSONValue, provider: String, strings: [String] = [], numbers: [String] = []) throws {
    for key in strings where raw[key] != nil && raw[key] != .null {
        guard raw[key]?.stringValue != nil else {
            throw AIError.invalidResponse(provider: provider, message: "Topaz \(key) must be a string.")
        }
    }
    for key in numbers where raw[key] != nil && raw[key] != .null {
        guard let value = raw[key]?.doubleValue, value.isFinite else {
            throw AIError.invalidResponse(provider: provider, message: "Topaz \(key) must be a number.")
        }
    }
}

func topazNonNull(_ value: JSONValue?) -> JSONValue? { value == .null ? nil : value }

func topazDimensions(_ value: String?, argument: String) throws -> (width: JSONValue?, height: JSONValue?) {
    guard let value else { return (nil, nil) }
    let parts = value.split(separator: "x", omittingEmptySubsequences: false)
    guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]),
          width.isFinite, height.isFinite, width > 0, height > 0 else {
        throw AIError.invalidArgument(argument: argument, message: "Topaz \(argument) must use WIDTHxHEIGHT in pixels.")
    }
    return (.number(width), .number(height))
}

func topazWarning(_ feature: String, _ message: String) -> AIWarning {
    AIWarning(type: "unsupported", feature: feature, message: message)
}

func topazPathComponent(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~"))) ?? value
}

func topazHeaders(_ config: ModelHTTPConfig, _ callHeaders: [String: String]) -> [String: String] {
    config.headers.mergingHeaders(normalizeHeaders(callHeaders))
}

// Cleanup must survive both Swift task cancellation and the caller's abort
// signal. Failure here must never obscure the original failure.
func topazCancelQuietly(config: ModelHTTPConfig, modelID: String, path: String, headers: [String: String]) async {
    await Task.detached {
        guard let url = try? config.url(modelID, path) else { return }
        _ = try? await config.transport.send(AIHTTPRequest(
            method: "DELETE", url: url, headers: topazHeaders(config, headers)
        ))
    }.value
}
