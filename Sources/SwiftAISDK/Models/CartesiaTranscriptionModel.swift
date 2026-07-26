import Foundation

public final class CartesiaTranscriptionModel: TranscriptionModel, @unchecked Sendable {
    public let providerID = "cartesia.transcription"
    public let modelID: String

    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func transcribe(
        _ request: AudioTranscriptionRequest
    ) async throws -> TranscriptionResult {
        guard !isCartesiaStreamingTranscriptionModel(modelID) else {
            throw AIError.invalidArgument(
                argument: "modelID",
                message: "Cartesia \(modelID) supports streaming transcription, which SwiftAISDK does not currently expose."
            )
        }

        let parsed = try cartesiaTranscriptionOptions(from: request)
        let language = parsed.language
            ?? request.language.flatMap { $0.isEmpty ? nil : $0 }
        var warnings: [AIWarning] = []
        if parsed.hasStreamingOptions {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "providerOptions.cartesia.streaming",
                message: "Cartesia batch transcription does not support streaming options."
            ))
        }

        let fileName = "audio.\(mediaTypeToExtension(request.mimeType))"
        var form = MultipartFormData()
        form.appendField(name: "model", value: modelID)
        form.appendFile(
            name: "file",
            fileName: fileName,
            mimeType: request.mimeType,
            data: request.audio
        )
        if let language {
            form.appendField(name: "language", value: language)
        }
        for granularity in parsed.timestampGranularities ?? [] {
            form.appendField(
                name: "timestamp_granularities[]",
                value: granularity
            )
        }
        for (key, value) in parsed.extraFields {
            if case let .array(items) = value {
                for item in items {
                    if let scalar = jsonScalarString(item) {
                        form.appendField(name: "\(key)[]", value: scalar)
                    }
                }
            } else if let scalar = jsonScalarString(value) {
                form.appendField(name: key, value: scalar)
            }
        }

        let response = try await config.transport.send(config.rawRequest(
            path: "/stt",
            modelID: modelID,
            body: form.finalize(),
            contentType: "multipart/form-data; boundary=\(form.boundary)",
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw cartesiaHTTPStatusError(provider: providerID, response: response)
        }

        let raw = try response.jsonValue()
        let parsedResponse = try parseCartesiaTranscriptionResponse(raw)
        var metadataBody: [String: JSONValue] = [
            "model": .string(modelID),
            "file": .object([
                "filename": .string(fileName),
                "mimeType": .string(request.mimeType),
                "byteLength": .number(Double(request.audio.count))
            ])
        ]
        if let language {
            metadataBody["language"] = .string(language)
        }
        if let granularities = parsed.timestampGranularities {
            metadataBody["timestampGranularities"] = .array(
                granularities.map(JSONValue.string)
            )
        }
        metadataBody.merge(parsed.extraFields) { _, value in value }

        return TranscriptionResult(
            text: parsedResponse.text,
            rawValue: raw,
            segments: parsedResponse.segments,
            language: parsedResponse.language,
            durationInSeconds: parsedResponse.durationInSeconds,
            warnings: warnings,
            requestMetadata: AIRequestMetadata(
                body: .object(metadataBody),
                headers: request.headers
            ),
            responseMetadata: aiResponseMetadata(
                from: raw,
                response: response,
                modelID: modelID
            )
        )
    }
}

private struct ParsedCartesiaTranscriptionOptions {
    var language: String?
    var timestampGranularities: [String]?
    var hasStreamingOptions: Bool
    var extraFields: [String: JSONValue]

    init(
        language: String? = nil,
        timestampGranularities: [String]? = nil,
        hasStreamingOptions: Bool = false,
        extraFields: [String: JSONValue] = [:]
    ) {
        self.language = language
        self.timestampGranularities = timestampGranularities
        self.hasStreamingOptions = hasStreamingOptions
        self.extraFields = extraFields
    }

    func merging(
        _ override: ParsedCartesiaTranscriptionOptions
    ) -> ParsedCartesiaTranscriptionOptions {
        ParsedCartesiaTranscriptionOptions(
            language: override.language ?? language,
            timestampGranularities: override.timestampGranularities
                ?? timestampGranularities,
            hasStreamingOptions: hasStreamingOptions
                || override.hasStreamingOptions,
            extraFields: extraFields
        )
    }
}

private let cartesiaTranscriptionOptionKeys: Set<String> = [
    "language",
    "timestampGranularities",
    "streaming"
]

private func cartesiaTranscriptionOptions(
    from request: AudioTranscriptionRequest
) throws -> ParsedCartesiaTranscriptionOptions {
    var extraOptions = request.extraBody
    if let nested = extraOptions.removeValue(forKey: "cartesia") {
        if nested == .null {
            // A null legacy namespace is a no-op, matching providerOptions.
        } else if let object = nested.objectValue {
            extraOptions.merge(object) { _, nestedValue in nestedValue }
        } else {
            throw AIError.invalidArgument(
                argument: "extraBody.cartesia",
                message: "Cartesia provider options must be an object."
            )
        }
    }

    var validated = try validateCartesiaTranscriptionOptions(extraOptions)
    if let namespace = request.providerOptions["cartesia"] {
        guard namespace != .null else {
            validated.extraFields = extraOptions.filter {
                !cartesiaTranscriptionOptionKeys.contains($0.key)
            }
            return validated
        }
        guard let object = namespace.objectValue else {
            throw AIError.invalidArgument(
                argument: "providerOptions.cartesia",
                message: "Cartesia provider options must be an object."
            )
        }
        validated = validated.merging(
            try validateCartesiaTranscriptionOptions(object)
        )
    }

    validated.extraFields = extraOptions.filter {
        !cartesiaTranscriptionOptionKeys.contains($0.key)
    }
    return validated
}

private func validateCartesiaTranscriptionOptions(
    _ values: [String: JSONValue]
) throws -> ParsedCartesiaTranscriptionOptions {
    var options = ParsedCartesiaTranscriptionOptions()

    if let value = values["language"], value != .null {
        guard let language = value.stringValue else {
            throw AIError.invalidArgument(
                argument: "providerOptions.cartesia.language",
                message: "Cartesia language must be a string."
            )
        }
        options.language = language
    }

    if let value = values["timestampGranularities"], value != .null {
        guard let array = value.arrayValue,
              array.allSatisfy({ $0.stringValue == "word" }) else {
            throw AIError.invalidArgument(
                argument: "providerOptions.cartesia.timestampGranularities",
                message: "Cartesia timestampGranularities only supports word."
            )
        }
        options.timestampGranularities = array.compactMap(\.stringValue)
    }

    if let value = values["streaming"] {
        guard let streaming = value.objectValue else {
            throw AIError.invalidArgument(
                argument: "providerOptions.cartesia.streaming",
                message: "Cartesia streaming options must be an object."
            )
        }
        if let turnDetection = streaming["turnDetection"],
           turnDetection.boolValue == nil {
            throw AIError.invalidArgument(
                argument: "providerOptions.cartesia.streaming.turnDetection",
                message: "Cartesia turnDetection must be a boolean."
            )
        }
        options.hasStreamingOptions = true
    }

    return options
}

private struct ParsedCartesiaTranscriptionResponse {
    var text: String
    var segments: [TranscriptionSegment]
    var language: String?
    var durationInSeconds: Double?
}

private func parseCartesiaTranscriptionResponse(
    _ raw: JSONValue
) throws -> ParsedCartesiaTranscriptionResponse {
    guard let text = raw["text"]?.stringValue else {
        throw AIError.invalidResponse(
            provider: "cartesia.transcription",
            message: "Cartesia transcription response did not contain valid text."
        )
    }

    let language: String?
    if let value = raw["language"], value != .null {
        guard let parsed = value.stringValue else {
            throw AIError.invalidResponse(
                provider: "cartesia.transcription",
                message: "Cartesia transcription response language must be a string or null."
            )
        }
        language = parsed
    } else {
        language = nil
    }

    let duration: Double?
    if let value = raw["duration"], value != .null {
        guard let parsed = value.doubleValue else {
            throw AIError.invalidResponse(
                provider: "cartesia.transcription",
                message: "Cartesia transcription response duration must be a number or null."
            )
        }
        duration = parsed
    } else {
        duration = nil
    }

    var segments: [TranscriptionSegment] = []
    if let words = raw["words"], words != .null {
        guard let items = words.arrayValue else {
            throw AIError.invalidResponse(
                provider: "cartesia.transcription",
                message: "Cartesia transcription response words must be an array or null."
            )
        }
        for (index, word) in items.enumerated() {
            guard let text = word["word"]?.stringValue,
                  let start = word["start"]?.doubleValue,
                  let end = word["end"]?.doubleValue else {
                throw AIError.invalidResponse(
                    provider: "cartesia.transcription",
                    message: "Cartesia transcription response words[\(index)] is invalid."
                )
            }
            segments.append(TranscriptionSegment(
                text: text,
                startSecond: start,
                endSecond: end
            ))
        }
    }

    return ParsedCartesiaTranscriptionResponse(
        text: text,
        segments: segments,
        language: language,
        durationInSeconds: duration
    )
}

private func isCartesiaStreamingTranscriptionModel(
    _ modelID: String
) -> Bool {
    modelID == "ink-2" || modelID.hasPrefix("ink-2-")
}
