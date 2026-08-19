import Foundation

/// Experimental xAI realtime V4 adapter.
public final class XAIRealtimeModel: AIRealtimeModelV4, @unchecked Sendable {
    public let providerID = "xai.realtime"
    public let modelID: String

    let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.modelID = modelID
        self.config = config
    }

    public func doCreateClientSecret(
        _ options: AIRealtimeClientSecretOptions = .init()
    ) async throws -> AIRealtimeClientSecretResult {
        var body: [String: JSONValue] = [:]
        if let expiresAfterSeconds = options.expiresAfterSeconds {
            body["expires_after"] = .object([
                "seconds": .number(Double(expiresAfterSeconds))
            ])
        }

        let requestBody = JSONValue.object(body)
        let request = try config.request(
            path: "/realtime/client_secrets",
            modelID: modelID,
            body: requestBody,
            abortSignal: options.abortSignal
        )
        let response = try await config.transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw AIError.apiCall(AIAPICallError(
                provider: providerID,
                url: request.url.absoluteString,
                requestBody: requestBody,
                statusCode: response.statusCode,
                responseHeaders: response.headers,
                responseBody:
                    "xAI realtime client secret request failed: "
                        + "\(response.statusCode) \(response.bodyText)"
            ))
        }

        let raw: JSONValue
        do {
            raw = try response.jsonValue()
        } catch {
            throw AIError.invalidResponse(
                provider: providerID,
                message: "Client secret response was not valid JSON."
            )
        }
        guard let token = raw["value"]?.stringValue, !token.isEmpty else {
            throw AIError.invalidResponse(
                provider: providerID,
                message: "Client secret response is missing value."
            )
        }

        return AIRealtimeClientSecretResult(
            token: token,
            url: try realtimeWebSocketURL(),
            expiresAt: raw["expires_at"]?.intValue
        )
    }

    public func getWebSocketConfig(
        token: String,
        url: String
    ) -> AIRealtimeWebSocketConfiguration {
        AIRealtimeWebSocketConfiguration(
            url: url,
            protocols: ["xai-client-secret.\(token)"]
        )
    }

    public func parseServerEvent(
        _ raw: JSONValue
    ) -> [AIRealtimeServerEvent] {
        let type = raw["type"]?.stringValue ?? ""
        let responseID = raw["response_id"]?.stringValue ?? ""
        let itemID = raw["item_id"]?.stringValue ?? ""
        let nestedItemID = raw["item"]?["id"]?.stringValue
        let nestedResponseID = raw["response"]?["id"]?.stringValue

        let event: AIRealtimeServerEvent
        switch type {
        case "session.created":
            event = .sessionCreated(
                sessionID: raw["session"]?["id"]?.stringValue,
                raw: raw
            )

        case "session.updated":
            event = .sessionUpdated(raw: raw)

        case "conversation.created":
            event = .custom(rawType: type, raw: raw)

        case "input_audio_buffer.speech_started":
            event = .speechStarted(
                itemID: raw["item_id"]?.stringValue,
                raw: raw
            )

        case "input_audio_buffer.speech_stopped":
            event = .speechStopped(
                itemID: raw["item_id"]?.stringValue,
                raw: raw
            )

        case "input_audio_buffer.committed":
            event = .audioCommitted(
                itemID: raw["item_id"]?.stringValue,
                previousItemID: raw["previous_item_id"]?.stringValue,
                raw: raw
            )

        case "conversation.item.added":
            event = .conversationItemAdded(
                itemID: nestedItemID ?? itemID,
                item: raw["item"] ?? .null,
                raw: raw
            )

        case "conversation.item.input_audio_transcription.completed":
            event = .inputTranscriptionCompleted(
                itemID: itemID,
                transcript: raw["transcript"]?.stringValue ?? "",
                raw: raw
            )

        case "response.created":
            event = .responseCreated(
                responseID: nestedResponseID ?? responseID,
                raw: raw
            )

        case "response.done":
            event = .responseDone(
                responseID: nestedResponseID ?? responseID,
                status: raw["response"]?["status"]?.stringValue
                    ?? "completed",
                raw: raw
            )

        case "response.output_item.added":
            event = .outputItemAdded(
                responseID: responseID,
                itemID: nestedItemID ?? itemID,
                raw: raw
            )

        case "response.output_item.done":
            event = .outputItemDone(
                responseID: responseID,
                itemID: nestedItemID ?? itemID,
                raw: raw
            )

        case "response.content_part.added":
            event = .contentPartAdded(
                responseID: responseID,
                itemID: itemID,
                raw: raw
            )

        case "response.content_part.done":
            event = .contentPartDone(
                responseID: responseID,
                itemID: itemID,
                raw: raw
            )

        case "response.output_audio.delta":
            event = .audioDelta(
                responseID: responseID,
                itemID: itemID,
                delta: raw["delta"]?.stringValue ?? "",
                raw: raw
            )

        case "response.output_audio.done":
            event = .audioDone(
                responseID: responseID,
                itemID: itemID,
                raw: raw
            )

        case "response.output_audio_transcript.delta":
            event = .audioTranscriptDelta(
                responseID: responseID,
                itemID: itemID,
                delta: raw["delta"]?.stringValue ?? "",
                raw: raw
            )

        case "response.output_audio_transcript.done":
            event = .audioTranscriptDone(
                responseID: responseID,
                itemID: itemID,
                transcript: raw["transcript"]?.stringValue,
                raw: raw
            )

        case "response.text.delta":
            event = .textDelta(
                responseID: responseID,
                itemID: itemID,
                delta: raw["delta"]?.stringValue ?? "",
                raw: raw
            )

        case "response.text.done":
            event = .textDone(
                responseID: responseID,
                itemID: itemID,
                text: raw["text"]?.stringValue,
                raw: raw
            )

        case "response.function_call_arguments.delta":
            event = .functionCallArgumentsDelta(
                responseID: responseID,
                itemID: itemID,
                callID: raw["call_id"]?.stringValue ?? "",
                delta: raw["delta"]?.stringValue ?? "",
                raw: raw
            )

        case "response.function_call_arguments.done":
            event = .functionCallArgumentsDone(
                responseID: responseID,
                itemID: itemID,
                callID: raw["call_id"]?.stringValue ?? "",
                name: raw["name"]?.stringValue ?? "",
                arguments: raw["arguments"]?.stringValue ?? "",
                raw: raw
            )

        case "mcp_list_tools.in_progress",
             "mcp_list_tools.completed",
             "mcp_list_tools.failed",
             "response.mcp_call_arguments.delta",
             "response.mcp_call_arguments.done",
             "response.mcp_call.in_progress",
             "response.mcp_call.completed",
             "response.mcp_call.failed":
            event = .custom(rawType: type, raw: raw)

        case "error":
            event = .error(
                message: raw["error"]?["message"]?.stringValue
                    ?? raw["message"]?.stringValue
                    ?? "Unknown error",
                code: raw["error"]?["code"]?.stringValue
                    ?? raw["code"]?.stringValue,
                raw: raw
            )

        default:
            event = .custom(rawType: type, raw: raw)
        }

        return [event]
    }

    public func serializeClientEvent(
        _ event: AIRealtimeClientEvent
    ) async throws -> AIRealtimeWireMessage? {
        let raw: JSONValue?
        switch event {
        case let .sessionUpdate(configuration):
            raw = .object([
                "type": .string("session.update"),
                "session": buildSessionConfig(configuration)
            ])

        case let .inputAudioAppend(audio):
            raw = .object([
                "type": .string("input_audio_buffer.append"),
                "audio": .string(audio)
            ])

        case .inputAudioCommit:
            raw = ["type": "input_audio_buffer.commit"]

        case .inputAudioClear:
            raw = ["type": "input_audio_buffer.clear"]

        case let .conversationItemCreate(item):
            raw = serializeConversationItem(item)

        case .conversationItemTruncate:
            // xAI silently ignores this native event. Dropping it avoids a
            // no-op while local playback can still stop on speech_started.
            return nil

        case let .responseCreate(options):
            var root: [String: JSONValue] = [
                "type": .string("response.create")
            ]
            if let options {
                var response: [String: JSONValue] = [:]
                if let modalities = options.modalities {
                    response["modalities"] = .array(
                        modalities.map(JSONValue.string)
                    )
                }
                if let instructions = options.instructions {
                    response["instructions"] = .string(instructions)
                }
                // Upstream xAI currently ignores normalized metadata.
                root["response"] = .object(response)
            }
            raw = .object(root)

        case .responseCancel:
            raw = ["type": "response.cancel"]
        }

        return raw.map(AIRealtimeWireMessage.json)
    }

    public func buildSessionConfig(
        _ config: AIRealtimeSessionConfiguration
    ) -> JSONValue {
        var session: [String: JSONValue] = [:]

        if let instructions = config.instructions {
            session["instructions"] = .string(instructions)
        }
        if let voice = config.voice {
            session["voice"] = .string(voice)
        }

        var audio: [String: JSONValue] = [:]
        if let format = config.inputAudioFormat {
            audio["input"] = .object([
                "format": audioFormatJSON(format)
            ])
        }
        if let format = config.outputAudioFormat {
            audio["output"] = .object([
                "format": audioFormatJSON(format)
            ])
        }
        if !audio.isEmpty {
            session["audio"] = .object(audio)
        }

        if let turnDetection = config.turnDetection {
            if turnDetection.type == .disabled {
                session["turn_detection"] = .null
            } else {
                var raw: [String: JSONValue] = [
                    // xAI maps semantic-vad to its supported server_vad mode.
                    "type": .string("server_vad")
                ]
                if let threshold = turnDetection.threshold {
                    raw["threshold"] = .number(threshold)
                }
                if let silence = turnDetection.silenceDurationMilliseconds {
                    raw["silence_duration_ms"] = .number(Double(silence))
                }
                if let padding = turnDetection.prefixPaddingMilliseconds {
                    raw["prefix_padding_ms"] = .number(Double(padding))
                }
                session["turn_detection"] = .object(raw)
            }
        }

        if let tools = config.tools, !tools.isEmpty {
            session["tools"] = .array(tools.map(toolJSON))
        }

        if let providerOptions = config.providerOptions {
            if case let .array(additionalTools)? = providerOptions["tools"] {
                let currentTools: [JSONValue]
                if case let .array(existing)? = session["tools"] {
                    currentTools = existing
                } else {
                    currentTools = []
                }
                session["tools"] = .array(currentTools + additionalTools)
            }
            for (key, value) in providerOptions where key != "tools" {
                session[key] = value
            }
        }

        return .object(session)
    }

    private func realtimeWebSocketURL() throws -> String {
        guard let components = URLComponents(string: config.baseURL),
              let host = components.host, !host.isEmpty else {
            throw AIError.invalidURL(config.baseURL)
        }
        let port = components.port.map { ":\($0)" } ?? ""
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~")
        )
        guard let encodedModelID = modelID.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) else {
            throw AIError.invalidArgument(
                argument: "modelID",
                message: "Could not encode the xAI realtime model ID."
            )
        }
        return "wss://\(host)\(port)/v1/realtime?model=\(encodedModelID)"
    }

    private func serializeConversationItem(
        _ item: AIRealtimeConversationItem
    ) -> JSONValue {
        let nativeItem: JSONValue
        switch item {
        case let .textMessage(text):
            nativeItem = .object([
                "type": .string("message"),
                "role": .string("user"),
                "content": .array([.object([
                    "type": .string("input_text"),
                    "text": .string(text)
                ])])
            ])

        case let .audioMessage(audio):
            nativeItem = .object([
                "type": .string("message"),
                "role": .string("user"),
                "content": .array([.object([
                    "type": .string("input_audio"),
                    "audio": .string(audio)
                ])])
            ])

        case let .functionCallOutput(callID, _, output):
            nativeItem = .object([
                "type": .string("function_call_output"),
                "call_id": .string(callID),
                "output": .string(output)
            ])
        }

        return .object([
            "type": .string("conversation.item.create"),
            "item": nativeItem
        ])
    }

    private func audioFormatJSON(
        _ format: AIRealtimeAudioFormat
    ) -> JSONValue {
        .object([
            "type": .string(format.type),
            "rate": format.rate.map { .number(Double($0)) }
        ])
    }

    private func toolJSON(_ tool: AIRealtimeToolDefinition) -> JSONValue {
        .object([
            "type": .string(tool.type),
            "name": .string(tool.name),
            "description": tool.description.map(JSONValue.string),
            "parameters": tool.parameters
        ])
    }
}
