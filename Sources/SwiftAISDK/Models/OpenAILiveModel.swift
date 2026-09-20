import Foundation

/// OpenAI Live's continuous-audio model over an authenticated server WebSocket.
public final class OpenAILiveModel:
    AIRealtimeModelV4,
    AIRealtimeModelV4ValidationHooks,
    @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    public let capabilities: AIRealtimeModelCapabilities? =
        AIRealtimeModelCapabilities(
        conversation: .continuous,
        transports: [.webSocket],
        connections: [.serverWebSocket],
        startup: .sessionStart,
        finalization: .sessionClose
    )

    private let baseURL: String
    private let headers: [String: String]

    public init(
        modelID: String = "gpt-live-1",
        settings: ProviderSettings = .init()
    ) throws {
        let providerName = settings.name ?? "openai"
        let apiKey = settings.apiKey
            ?? settings.environmentValue(["OPENAI_API_KEY"])
        guard let apiKey else {
            throw AIError.missingAPIKey(
                provider: providerName,
                environmentVariables: ["OPENAI_API_KEY"]
            )
        }

        self.providerID = providerName + ".live"
        self.modelID = modelID
        self.baseURL = withoutTrailingSlash(
            settings.baseURL
                ?? settings.environmentValue(["OPENAI_BASE_URL"])
                ?? "https://api.openai.com/v1"
        )

        var headers = normalizeHeaders(settings.headers)
        headers["authorization"] =
            headers["authorization"] ?? "Bearer " + apiKey
        if let organization = settings.organization {
            headers["openai-organization"] =
                headers["openai-organization"] ?? organization
        }
        if let project = settings.project {
            headers["openai-project"] =
                headers["openai-project"] ?? project
        }
        headers["user-agent"] =
            headers["user-agent"] ?? userAgent(providerName)
        self.headers = headers
    }

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID.hasSuffix(".live")
            ? config.providerID
            : config.providerID + ".live"
        self.modelID = modelID
        self.baseURL = withoutTrailingSlash(config.baseURL)
        self.headers = config.headers
    }

    public func getWebSocketConfig(
        token: String,
        url: String
    ) -> AIRealtimeWebSocketConfiguration {
        AIRealtimeWebSocketConfiguration(
            url: url,
            headers: ["authorization": "Bearer " + token]
        )
    }

    public func getValidatedWebSocketConfig(
        token: String,
        url: String
    ) throws -> AIRealtimeWebSocketConfiguration {
        throw unsupported(
            "OpenAI Live does not support client-secret WebSocket connections."
        )
    }

    public func getServerWebSocketConfig() throws
        -> AIRealtimeWebSocketConfiguration {
        let rawURL = baseURL + "/live/sessions"
        guard var components = URLComponents(string: rawURL) else {
            throw AIError.invalidURL(rawURL)
        }
        switch components.scheme?.lowercased() {
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        default:
            throw AIError.invalidURL(rawURL)
        }
        guard let url = components.url?.absoluteString else {
            throw AIError.invalidURL(rawURL)
        }
        return AIRealtimeWebSocketConfiguration(
            url: url,
            headers: headers
        )
    }

    public func createServerEventParser() -> AIRealtimeServerEventParser {
        { raw in Self.parseLiveServerEvent(raw) }
    }

    public func parseServerEvent(
        _ raw: JSONValue
    ) -> [AIRealtimeServerEvent] {
        Self.parseLiveServerEvent(raw)
    }

    public func serializeClientEvent(
        _ event: AIRealtimeClientEvent
    ) async throws -> AIRealtimeWireMessage? {
        var raw: [String: JSONValue]
        switch event {
        case let .sessionStart(configuration, eventID):
            raw = [
                "type": .string("session.start"),
                "session": try buildValidatedSessionConfig(configuration)
            ]
            addEventID(eventID, to: &raw)

        case .sessionUpdate, .sessionUpdateWithEventID:
            throw unsupported(
                "OpenAI Live session-update; startup settings are immutable; "
                    + "use context-append or input-audio-mute/input-audio-unmute"
            )

        case let .sessionClose(eventID):
            raw = ["type": .string("session.close")]
            addEventID(eventID, to: &raw)

        case let .inputAudioAppend(audio):
            raw = [
                "type": .string("session.input_audio.append"),
                "audio": .string(audio)
            ]

        case let .inputAudioAppendWithEventID(audio, eventID):
            raw = [
                "type": .string("session.input_audio.append"),
                "audio": .string(audio)
            ]
            addEventID(eventID, to: &raw)

        case let .inputAudioMute(eventID):
            raw = ["type": .string("session.input_audio.mute")]
            addEventID(eventID, to: &raw)

        case let .inputAudioUnmute(eventID):
            raw = ["type": .string("session.input_audio.unmute")]
            addEventID(eventID, to: &raw)

        case let .contextAppend(
            content,
            delegationID,
            eventID,
            providerOptions
        ):
            if let delegationID, delegationID.isEmpty {
                throw invalid(
                    "delegationID",
                    "OpenAI Live delegation IDs must not be empty."
                )
            }
            let channel = try contextChannel(providerOptions)
            raw = [
                "type": .string("session." + channel + ".append"),
                "content": .string(content),
                "delegation_id": delegationID.map(JSONValue.string) ?? .null
            ]
            addEventID(eventID, to: &raw)

        case .inputAudioCommit,
             .inputAudioClear,
             .conversationItemCreate,
             .conversationItemTruncate,
             .responseCreate,
             .responseCancel:
            throw unsupported(
                "OpenAI Live voice-turn command; use continuous audio and "
                    + "context-append instead."
            )
        }
        return .json(.object(raw))
    }

    public func buildSessionConfig(
        _ config: AIRealtimeSessionConfiguration
    ) -> JSONValue {
        (try? buildValidatedSessionConfig(config))
            ?? .object(["model": .string(modelID)])
    }

    public func buildValidatedSessionConfig(
        _ config: AIRealtimeSessionConfiguration
    ) throws -> JSONValue {
        try validateSupportedSessionFields(config)
        let options = try openAIOptions(config.providerOptions)

        if let client = options["client"] {
            guard client.objectValue != nil else {
                throw invalid(
                    "providerOptions.openai.client",
                    "OpenAI Live client permissions must be an object."
                )
            }
            throw unsupported(
                "OpenAI Live client permissions outside WebRTC startup"
            )
        }

        let delegation = try liveDelegation(options["delegation"])
        let optionVoice = try liveVoice(options["voice"])
        if optionVoice != nil, config.voice != nil {
            throw invalid(
                "voice",
                "Choose either voice or providerOptions.openai.voice."
            )
        }
        let input = try liveInput(options["input"])
        let store = try liveStore(options["store"])
        let inputFormat = try liveAudioFormat(
            config.inputAudioFormat,
            argument: "inputAudioFormat"
        )
        let outputFormat = try liveAudioFormat(
            config.outputAudioFormat,
            argument: "outputAudioFormat"
        )
        if let inputFormat, let outputFormat,
           inputFormat != outputFormat {
            throw invalid(
                "outputAudioFormat",
                "OpenAI Live requires the same input and output audio format."
            )
        }

        let format = inputFormat
            ?? outputFormat
            ?? AIRealtimeAudioFormat(type: "audio/pcm", rate: 24_000)
        let voice = optionVoice
            ?? config.voice.map(JSONValue.string)
            ?? .string("marin")
        var session: [String: JSONValue] = [
            "model": .string(modelID),
            "audio": .object([
                "format": audioFormatJSON(format),
                "output": .object(["voice": voice])
            ])
        ]
        if let instructions = config.instructions {
            session["instructions"] = .string(instructions)
        }
        if let delegation {
            session["delegation"] = delegation
        }
        if let input {
            session["input"] = input
        }
        if let store {
            session["store"] = .bool(store)
        }
        return .object(session)
    }

    private func validateSupportedSessionFields(
        _ config: AIRealtimeSessionConfiguration
    ) throws {
        let unsupportedFields: [(String, Bool)] = [
            ("outputModalities", config.outputModalities != nil),
            ("inputAudioTranscription", config.inputAudioTranscription != nil),
            ("outputAudioTranscription", config.outputAudioTranscription != nil),
            ("turnDetection", config.turnDetection != nil),
            ("tools", config.tools != nil)
        ]
        if let field = unsupportedFields.first(where: { $0.1 })?.0 {
            throw unsupported("OpenAI Live session setting: " + field)
        }
    }

    private func openAIOptions(
        _ providerOptions: [String: JSONValue]?
    ) throws -> [String: JSONValue] {
        guard let value = providerOptions?["openai"] else { return [:] }
        if value == .null { return [:] }
        guard case let .object(options) = value else {
            throw invalid(
                "providerOptions.openai",
                "OpenAI Live provider options must be an object."
            )
        }
        let allowed = Set(["client", "delegation", "input", "store", "voice"])
        if let key = options.keys.first(where: { !allowed.contains($0) }) {
            throw invalid(
                "providerOptions.openai." + key,
                "Unsupported OpenAI Live provider option."
            )
        }
        return options
    }

    private func liveDelegation(
        _ value: JSONValue?
    ) throws -> JSONValue? {
        guard let value else { return nil }
        if value == .null { return .null }
        guard case let .object(object) = value,
              let type = object["type"]?.stringValue else {
            throw invalid(
                "providerOptions.openai.delegation",
                "OpenAI Live delegation must be null or client delegation."
            )
        }
        if type == "responses" {
            throw unsupported(
                "OpenAI Live Responses delegation; only client delegation is supported"
            )
        }
        guard type == "client",
              Set(object.keys) == Set(["type"]) else {
            throw invalid(
                "providerOptions.openai.delegation.type",
                "OpenAI Live supports only client delegation."
            )
        }
        return value
    }

    private func liveVoice(_ value: JSONValue?) throws -> JSONValue? {
        guard let value else { return nil }
        guard case let .object(object) = value,
              Set(object.keys) == Set(["id"]),
              let id = object["id"]?.stringValue,
              !id.isEmpty else {
            throw invalid(
                "providerOptions.openai.voice",
                "OpenAI Live voice must contain a non-empty id."
            )
        }
        return value
    }

    private func liveInput(_ value: JSONValue?) throws -> JSONValue? {
        guard let value else { return nil }
        guard case let .array(messages) = value, messages.count <= 128 else {
            throw invalid(
                "providerOptions.openai.input",
                "OpenAI Live input must contain at most 128 messages."
            )
        }
        for (index, message) in messages.enumerated() {
            guard Self.isValidInputMessage(message) else {
                throw invalid(
                    "providerOptions.openai.input[" + String(index) + "]",
                    "OpenAI Live startup message has an invalid shape."
                )
            }
        }
        return value
    }

    private func liveStore(_ value: JSONValue?) throws -> Bool? {
        guard let value else { return nil }
        guard let store = value.boolValue else {
            throw invalid(
                "providerOptions.openai.store",
                "OpenAI Live store must be a boolean."
            )
        }
        return store
    }

    private func liveAudioFormat(
        _ format: AIRealtimeAudioFormat?,
        argument: String
    ) throws -> AIRealtimeAudioFormat? {
        guard let format else { return nil }
        let valid = (format.type == "audio/pcm"
            && (format.rate == 16_000 || format.rate == 24_000))
            || ((format.type == "audio/pcma"
                    || format.type == "audio/pcmu")
                && format.rate == 8_000)
        guard valid else {
            throw invalid(
                argument,
                "OpenAI Live supports PCM at 16000/24000 Hz or PCMA/PCMU at 8000 Hz."
            )
        }
        return format
    }

    private func contextChannel(
        _ providerOptions: [String: JSONValue]?
    ) throws -> String {
        guard let value = providerOptions?["openai"] else {
            return "thinking"
        }
        if value == .null { return "thinking" }
        guard case let .object(options) = value,
              options.keys.allSatisfy({ $0 == "channel" }) else {
            throw invalid(
                "providerOptions.openai",
                "OpenAI Live context options support only channel."
            )
        }
        guard let channelValue = options["channel"] else {
            return "thinking"
        }
        guard let channel = channelValue.stringValue,
              ["instructions", "thinking", "commentary"].contains(channel)
        else {
            throw invalid(
                "providerOptions.openai.channel",
                "OpenAI Live context channel must be instructions, thinking, or commentary."
            )
        }
        return channel
    }

    private func audioFormatJSON(
        _ format: AIRealtimeAudioFormat
    ) -> JSONValue {
        .object([
            "type": .string(format.type),
            "rate": format.rate.map { .number(Double($0)) }
        ])
    }

    private func addEventID(
        _ eventID: String?,
        to raw: inout [String: JSONValue]
    ) {
        if let eventID {
            raw["event_id"] = .string(eventID)
        }
    }

    private func invalid(_ argument: String, _ message: String) -> AIError {
        .invalidArgument(argument: argument, message: message)
    }

    private func unsupported(_ functionality: String) -> AIError {
        .invalidArgument(
            argument: "functionality",
            message: functionality + " is not supported."
        )
    }
}

private extension OpenAILiveModel {
    static let knownServerEventTypes: Set<String> = [
        "session.started",
        "session.closed",
        "session.usage.updated",
        "session.output_audio.delta",
        "session.input_transcript.delta",
        "session.output_transcript.delta",
        "session.delegation.created",
        "session.updated",
        "session.input_audio.muted",
        "session.input_audio.unmuted",
        "session.instructions.appended",
        "session.thinking.appended",
        "session.commentary.appended",
        "error"
    ]

    static func parseLiveServerEvent(
        _ raw: JSONValue
    ) -> [AIRealtimeServerEvent] {
        guard case let .object(root) = raw,
              let type = root["type"]?.stringValue else {
            return [invalidServerEvent(raw)]
        }
        guard knownServerEventTypes.contains(type) else {
            return [.custom(rawType: type, raw: raw)]
        }

        switch type {
        case "session.started":
            let delegation: (
                valid: Bool,
                value: [String: JSONValue]?
            )
            if let session = root["session"]?.objectValue {
                delegation = nullableObject(session, "delegation")
            } else {
                delegation = (false, nil)
            }
            guard let session = root["session"]?.objectValue,
                  let sessionID = nonEmptyString(session["id"]),
                  delegation.valid else {
                return [invalidServerEvent(raw)]
            }
            let mode: AIRealtimeDelegationMode
            if let object = delegation.value {
                guard let type = object["type"]?.stringValue,
                      type == "client" || type == "responses" else {
                    return [invalidServerEvent(raw)]
                }
                mode = type == "responses" ? .provider : .client
            } else {
                mode = .client
            }
            return [.sessionStarted(
                sessionID: sessionID,
                delegationMode: mode,
                raw: raw
            )]

        case "session.closed":
            let session = nullableObject(root, "session")
            guard session.valid,
                  session.value == nil
                    || nonEmptyString(session.value?["id"]) != nil,
                  let seconds = usageSeconds(root["usage"]),
                  let reason = root["reason"]?.stringValue else {
                return [invalidServerEvent(raw)]
            }
            return [.sessionClosed(
                sessionID: session.value.flatMap {
                    nonEmptyString($0["id"])
                },
                usage: .init(seconds: seconds),
                reason: reason,
                raw: raw
            )]

        case "session.usage.updated":
            guard let seconds = usageSeconds(root["usage"]) else {
                return [invalidServerEvent(raw)]
            }
            let context = nullableObject(root, "context_window")
            guard context.valid else { return [invalidServerEvent(raw)] }
            let ratio = context.value?["usage_ratio"]?.doubleValue
            if context.value != nil,
               ratio == nil || ratio! < 0 || ratio! > 1 {
                return [invalidServerEvent(raw)]
            }
            return [.sessionUsage(
                usage: .init(seconds: seconds),
                contextWindowUsageRatio: ratio,
                raw: raw
            )]

        case "session.output_audio.delta":
            guard let delta = root["delta"]?.stringValue else {
                return [invalidServerEvent(raw)]
            }
            return [.audioChunk(delta: delta, raw: raw)]

        case "session.input_transcript.delta",
             "session.output_transcript.delta":
            guard let delta = root["delta"]?.stringValue,
                  let start = nonnegativeNumber(root["start_ms"]),
                  let end = nonnegativeNumber(root["end_ms"]) else {
                return [invalidServerEvent(raw)]
            }
            guard end >= start else {
                return [.error(
                    message: "Invalid OpenAI Live event time interval.",
                    code: "invalid_server_event",
                    raw: raw
                )]
            }
            return [.transcriptFragment(
                speaker: type == "session.input_transcript.delta"
                    ? .user
                    : .assistant,
                delta: delta,
                startMilliseconds: start,
                endMilliseconds: end,
                raw: raw
            )]

        case "session.delegation.created":
            guard let delegation = root["delegation"]?.objectValue else {
                return [invalidServerEvent(raw)]
            }
            let target = nullableString(delegation, "target")
            let responseID = nullableString(
                delegation,
                "response_id"
            )
            let offset = nullableNonnegativeNumber(root, "offset_ms")
            guard let delegationID = nonEmptyString(delegation["id"]),
                  target.valid,
                  target.value == nil
                    || target.value == "client"
                    || target.value == "responses",
                  responseID.valid,
                  responseID.value == nil || !responseID.value!.isEmpty,
                  offset.valid else {
                return [invalidServerEvent(raw)]
            }
            return [.delegationCreated(
                delegationID: delegationID,
                target: target.value.map {
                    $0 == "responses" ? .provider : .client
                },
                offsetMilliseconds: offset.value,
                responseID: responseID.value,
                raw: raw
            )]

        case "session.updated":
            guard let session = root["session"]?.objectValue,
                  nonEmptyString(session["id"]) != nil else {
                return [invalidServerEvent(raw)]
            }
            return acknowledgment(
                root,
                command: "session.update",
                raw: raw
            )

        case "session.input_audio.muted":
            return acknowledgment(
                root,
                command: "session.input_audio.mute",
                raw: raw
            )

        case "session.input_audio.unmuted":
            return acknowledgment(
                root,
                command: "session.input_audio.unmute",
                raw: raw
            )

        case "session.instructions.appended",
             "session.thinking.appended",
             "session.commentary.appended":
            guard let start = nonnegativeNumber(root["start_ms"]),
                  let end = nonnegativeNumber(root["end_ms"]) else {
                return [invalidServerEvent(raw)]
            }
            guard end >= start else {
                return [.error(
                    message: "Invalid OpenAI Live event time interval.",
                    code: "invalid_server_event",
                    raw: raw
                )]
            }
            return acknowledgment(
                root,
                command: String(type.dropLast(2)),
                raw: raw
            )

        case "error":
            guard let error = root["error"]?.objectValue else {
                return [invalidServerEvent(raw)]
            }
            let code = nullableString(error, "code")
            let clientEventID = nullableString(
                error,
                "client_event_id"
            )
            guard let message = error["message"]?.stringValue,
                  code.valid,
                  clientEventID.valid else {
                return [invalidServerEvent(raw)]
            }
            if let clientEventID = clientEventID.value {
                return [.correlatedError(
                    message: message,
                    code: code.value,
                    clientEventID: clientEventID,
                    raw: raw
                )]
            }
            return [.error(message: message, code: code.value, raw: raw)]

        default:
            return [.custom(rawType: type, raw: raw)]
        }
    }

    static func acknowledgment(
        _ root: [String: JSONValue],
        command: String,
        raw: JSONValue
    ) -> [AIRealtimeServerEvent] {
        let eventID = nullableString(root, "client_event_id")
        guard eventID.valid else { return [invalidServerEvent(raw)] }
        return [.commandAcknowledged(
            command: command,
            clientEventID: eventID.value,
            raw: raw
        )]
    }

    static func invalidServerEvent(
        _ raw: JSONValue
    ) -> AIRealtimeServerEvent {
        .error(
            message: "Invalid OpenAI Live server event.",
            code: "invalid_server_event",
            raw: raw
        )
    }

    static func usageSeconds(_ value: JSONValue?) -> Double? {
        guard let object = value?.objectValue else { return nil }
        return nonnegativeNumber(object["seconds"])
    }

    static func nonnegativeNumber(_ value: JSONValue?) -> Double? {
        guard let value = value?.doubleValue,
              value.isFinite,
              value >= 0 else {
            return nil
        }
        return value
    }

    static func nonEmptyString(_ value: JSONValue?) -> String? {
        guard let value = value?.stringValue, !value.isEmpty else {
            return nil
        }
        return value
    }

    static func nullableObject(
        _ object: [String: JSONValue],
        _ key: String
    ) -> (valid: Bool, value: [String: JSONValue]?) {
        guard let value = object[key] else { return (true, nil) }
        if value == .null { return (true, nil) }
        guard case let .object(value) = value else {
            return (false, nil)
        }
        return (true, value)
    }

    static func nullableString(
        _ object: [String: JSONValue],
        _ key: String
    ) -> (valid: Bool, value: String?) {
        guard let value = object[key] else { return (true, nil) }
        if value == .null { return (true, nil) }
        guard let value = value.stringValue else { return (false, nil) }
        return (true, value)
    }

    static func nullableNonnegativeNumber(
        _ object: [String: JSONValue],
        _ key: String
    ) -> (valid: Bool, value: Double?) {
        guard let value = object[key] else { return (true, nil) }
        if value == .null { return (true, nil) }
        guard let number = nonnegativeNumber(value) else {
            return (false, nil)
        }
        return (true, number)
    }

    static func isValidInputMessage(_ value: JSONValue) -> Bool {
        guard case let .object(message) = value,
              Set(message.keys) == Set(["type", "role", "content"]),
              message["type"]?.stringValue == "message",
              let role = message["role"]?.stringValue,
              case let .array(content)? = message["content"],
              content.count == 1,
              case let .object(part) = content[0],
              Set(part.keys) == Set(["type", "text"]),
              part["text"]?.stringValue != nil,
              let partType = part["type"]?.stringValue else {
            return false
        }
        switch role {
        case "developer", "user":
            return partType == "input_text"
        case "assistant":
            return partType == "text" || partType == "output_text"
        default:
            return false
        }
    }
}
