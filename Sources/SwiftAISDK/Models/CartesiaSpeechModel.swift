import Foundation

public final class CartesiaSpeechModel: SpeechModel, @unchecked Sendable {
    public let providerID = "cartesia.speech"
    public let modelID: String

    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func speak(_ request: SpeechRequest) async throws -> SpeechResult {
        guard let voice = request.voice, !voice.isEmpty else {
            throw AIError.invalidArgument(
                argument: "voice",
                message: "Cartesia speech models require a `voice` to be set."
            )
        }

        var warnings: [AIWarning] = []
        let parsed = try cartesiaSpeechOptions(from: request)
        let outputFormat = cartesiaSpeechOutputFormat(
            request.format ?? "mp3",
            options: parsed.options,
            warnings: &warnings
        )

        var body: [String: JSONValue] = [
            "model_id": .string(modelID),
            "transcript": .string(request.text),
            "voice": .object([
                "mode": .string("id"),
                "id": .string(voice)
            ]),
            "output_format": .object(outputFormat)
        ]

        if let language = parsed.options.language {
            body["language"] = .string(language)
        } else if let language = request.language, !language.isEmpty {
            body["language"] = .string(language)
        }

        if let speed = parsed.options.speed ?? request.speed {
            if (0.6...1.5).contains(speed) {
                body["generation_config"] = .object([
                    "speed": .number(speed)
                ])
            } else {
                warnings.append(AIWarning(
                    type: "unsupported",
                    feature: "speed",
                    message: "Cartesia speed must be between 0.6 and 1.5. The speed option was ignored."
                ))
            }
        }

        if let instructions = request.instructions, !instructions.isEmpty {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "instructions",
                message: "Cartesia speech models do not support instructions. Instructions parameter was ignored."
            ))
        }

        body.merge(parsed.bodyOverrides) { _, override in override }

        let response = try await config.transport.send(config.request(
            path: "/tts/bytes",
            modelID: modelID,
            body: .object(body),
            headers: request.headers,
            abortSignal: request.abortSignal
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw cartesiaHTTPStatusError(provider: providerID, response: response)
        }

        return SpeechResult(
            audio: response.body,
            contentType: response.headers.contentType,
            warnings: warnings,
            requestMetadata: AIRequestMetadata(
                body: .object(body),
                headers: request.headers
            ),
            responseMetadata: aiResponseMetadata(
                response: response,
                modelID: modelID
            )
        )
    }
}

private struct CartesiaSpeechOptions {
    var container: String?
    var encoding: String?
    var sampleRate: Int?
    var bitRate: Int?
    var speed: Double?
    var language: String?
}

private struct ParsedCartesiaSpeechOptions {
    var options: CartesiaSpeechOptions
    var bodyOverrides: [String: JSONValue]
}

private let cartesiaSpeechOptionKeys: Set<String> = [
    "container",
    "encoding",
    "sampleRate",
    "bitRate",
    "speed",
    "language"
]

private let cartesiaSpeechContainers: Set<String> = ["raw", "wav", "mp3"]
private let cartesiaSpeechEncodings: Set<String> = [
    "pcm_f32le",
    "pcm_s16le",
    "pcm_mulaw",
    "pcm_alaw"
]
private let cartesiaSpeechSampleRates: Set<Int> = [
    8_000,
    16_000,
    22_050,
    24_000,
    44_100,
    48_000
]
private let cartesiaSpeechBitRates: Set<Int> = [
    32_000,
    64_000,
    96_000,
    128_000,
    192_000
]

private func cartesiaSpeechOptions(
    from request: SpeechRequest
) throws -> ParsedCartesiaSpeechOptions {
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

    var validated = try validateCartesiaSpeechOptions(extraOptions)
    if let namespace = request.providerOptions["cartesia"] {
        guard namespace != .null else {
            return ParsedCartesiaSpeechOptions(
                options: validated,
                bodyOverrides: extraOptions.filter {
                    !cartesiaSpeechOptionKeys.contains($0.key)
                }
            )
        }
        guard let object = namespace.objectValue else {
            throw AIError.invalidArgument(
                argument: "providerOptions.cartesia",
                message: "Cartesia provider options must be an object."
            )
        }
        let providerOptions = try validateCartesiaSpeechOptions(object)
        validated = validated.merging(providerOptions)
    }

    return ParsedCartesiaSpeechOptions(
        options: validated,
        bodyOverrides: extraOptions.filter {
            !cartesiaSpeechOptionKeys.contains($0.key)
        }
    )
}

private func validateCartesiaSpeechOptions(
    _ values: [String: JSONValue]
) throws -> CartesiaSpeechOptions {
    var options = CartesiaSpeechOptions()

    if let value = values["container"], value != .null {
        guard let container = value.stringValue,
              cartesiaSpeechContainers.contains(container) else {
            throw AIError.invalidArgument(
                argument: "providerOptions.cartesia.container",
                message: "Cartesia container must be one of raw, wav, mp3."
            )
        }
        options.container = container
    }

    if let value = values["encoding"], value != .null {
        guard let encoding = value.stringValue,
              cartesiaSpeechEncodings.contains(encoding) else {
            throw AIError.invalidArgument(
                argument: "providerOptions.cartesia.encoding",
                message: "Cartesia encoding must be one of pcm_f32le, pcm_s16le, pcm_mulaw, pcm_alaw."
            )
        }
        options.encoding = encoding
    }

    if let value = values["sampleRate"], value != .null {
        guard let sampleRate = cartesiaInteger(value),
              cartesiaSpeechSampleRates.contains(sampleRate) else {
            throw AIError.invalidArgument(
                argument: "providerOptions.cartesia.sampleRate",
                message: "Cartesia sampleRate must be one of 8000, 16000, 22050, 24000, 44100, 48000."
            )
        }
        options.sampleRate = sampleRate
    }

    if let value = values["bitRate"], value != .null {
        guard let bitRate = cartesiaInteger(value),
              cartesiaSpeechBitRates.contains(bitRate) else {
            throw AIError.invalidArgument(
                argument: "providerOptions.cartesia.bitRate",
                message: "Cartesia bitRate must be one of 32000, 64000, 96000, 128000, 192000."
            )
        }
        options.bitRate = bitRate
    }

    if let value = values["speed"], value != .null {
        guard let speed = value.doubleValue, (0.6...1.5).contains(speed) else {
            throw AIError.invalidArgument(
                argument: "providerOptions.cartesia.speed",
                message: "Cartesia speed must be between 0.6 and 1.5."
            )
        }
        options.speed = speed
    }

    if let value = values["language"], value != .null {
        guard let language = value.stringValue else {
            throw AIError.invalidArgument(
                argument: "providerOptions.cartesia.language",
                message: "Cartesia language must be a string."
            )
        }
        options.language = language
    }

    return options
}

private extension CartesiaSpeechOptions {
    func merging(_ override: CartesiaSpeechOptions) -> CartesiaSpeechOptions {
        CartesiaSpeechOptions(
            container: override.container ?? container,
            encoding: override.encoding ?? encoding,
            sampleRate: override.sampleRate ?? sampleRate,
            bitRate: override.bitRate ?? bitRate,
            speed: override.speed ?? speed,
            language: override.language ?? language
        )
    }
}

private func cartesiaSpeechOutputFormat(
    _ outputFormat: String,
    options: CartesiaSpeechOptions,
    warnings: inout [AIWarning]
) -> [String: JSONValue] {
    let parts = outputFormat.lowercased().components(separatedBy: "_")
    let formatName = parts.first ?? ""
    let mapped = cartesiaMappedSpeechOutputFormat(formatName)
    var resolved = mapped ?? cartesiaDefaultSpeechOutputFormat

    if mapped == nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "outputFormat",
            message: "Unknown output format \"\(outputFormat)\". Falling back to mp3. Use providerOptions.cartesia to configure container, encoding, and sampleRate directly."
        ))
    } else if parts.count > 1 {
        let parsedRate = parts.count == 2 ? Int(parts[1]) : nil
        if let parsedRate,
           cartesiaSpeechSampleRates.contains(parsedRate) {
            resolved["sample_rate"] = .number(Double(parsedRate))
        } else {
            let fallbackRate = resolved["sample_rate"]?.intValue ?? 44_100
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "outputFormat",
                message: "Unsupported Cartesia sample rate in output format \"\(outputFormat)\". Using \(fallbackRate) Hz instead."
            ))
        }
    }

    let resolvedContainer = resolved["container"]?.stringValue ?? "mp3"
    let container = options.container ?? resolvedContainer
    let sampleRate = options.sampleRate
        ?? resolved["sample_rate"]?.intValue
        ?? 44_100

    if container == "mp3" {
        if options.encoding != nil {
            warnings.append(AIWarning(
                type: "unsupported",
                feature: "providerOptions.cartesia.encoding",
                message: "Cartesia MP3 output does not accept an encoding. The encoding option was ignored."
            ))
        }
        return [
            "container": .string(container),
            "sample_rate": .number(Double(sampleRate)),
            "bit_rate": .number(Double(
                options.bitRate
                    ?? (resolvedContainer == "mp3"
                        ? resolved["bit_rate"]?.intValue
                        : nil)
                    ?? 128_000
            ))
        ]
    }

    if options.bitRate != nil {
        warnings.append(AIWarning(
            type: "unsupported",
            feature: "providerOptions.cartesia.bitRate",
            message: "Cartesia raw and WAV output do not accept a bit rate. The bitRate option was ignored."
        ))
    }

    let defaultEncoding: String
    if resolvedContainer == "mp3" {
        defaultEncoding = container == "wav" ? "pcm_s16le" : "pcm_f32le"
    } else {
        defaultEncoding = resolved["encoding"]?.stringValue ?? "pcm_f32le"
    }

    return [
        "container": .string(container),
        "encoding": .string(options.encoding ?? defaultEncoding),
        "sample_rate": .number(Double(sampleRate))
    ]
}

private let cartesiaDefaultSpeechOutputFormat: [String: JSONValue] = [
    "container": .string("mp3"),
    "sample_rate": .number(44_100),
    "bit_rate": .number(128_000)
]

private func cartesiaMappedSpeechOutputFormat(
    _ name: String
) -> [String: JSONValue]? {
    switch name {
    case "alaw":
        [
            "container": .string("raw"),
            "encoding": .string("pcm_alaw"),
            "sample_rate": .number(8_000)
        ]
    case "mp3":
        cartesiaDefaultSpeechOutputFormat
    case "mulaw":
        [
            "container": .string("raw"),
            "encoding": .string("pcm_mulaw"),
            "sample_rate": .number(8_000)
        ]
    case "pcm", "raw":
        [
            "container": .string("raw"),
            "encoding": .string("pcm_f32le"),
            "sample_rate": .number(44_100)
        ]
    case "wav":
        [
            "container": .string("wav"),
            "encoding": .string("pcm_s16le"),
            "sample_rate": .number(44_100)
        ]
    default:
        nil
    }
}

private func cartesiaInteger(_ value: JSONValue) -> Int? {
    guard let number = value.doubleValue,
          number.isFinite,
          number.rounded() == number,
          let integer = Int(exactly: number) else {
        return nil
    }
    return integer
}
