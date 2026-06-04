import Foundation

public final class GoogleInteractionsLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let agent: String?
    private let config: ModelHTTPConfig

    init(modelID: String, agent: String?, config: ModelHTTPConfig) {
        self.providerID = "\(config.providerID).interactions"
        self.modelID = modelID
        self.agent = agent
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = try googleInteractionsPreparedCall(for: request, modelID: modelID, agent: agent, stream: false)
        let raw = try await sendInteractions(body: .object(prepared.body), headers: request.headers, abortSignal: request.abortSignal)
        let final = try await resolvedInteraction(raw, requestHeaders: request.headers, abortSignal: request.abortSignal)
        let text = googleInteractionsText(from: final)
        let toolCalls = googleInteractionsToolCalls(from: final)
        guard !text.isEmpty || !toolCalls.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No model_output text found in Google Interactions response.")
        }
        return TextGenerationResult(
            text: text,
            finishReason: googleInteractionsFinishReason(status: final["status"]?.stringValue, hasFunctionCall: googleInteractionsHasFunctionCall(final)),
            usage: googleInteractionsUsage(from: final),
            toolCalls: toolCalls,
            sources: googleInteractionsSources(from: final),
            providerMetadata: googleInteractionsProviderMetadata(from: final),
            rawValue: final,
            warnings: prepared.warnings
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let prepared = try googleInteractionsPreparedCall(for: request, modelID: modelID, agent: agent, stream: true)
                    let response = try await config.transport.send(config.request(
                        path: "/interactions",
                        modelID: modelID,
                        body: .object(prepared.body),
                        headers: googleInteractionsHeaders(request.headers),
                        abortSignal: request.abortSignal
                    ))
                    guard (200..<300).contains(response.statusCode) else {
                        throw httpStatusError(provider: providerID, response: response)
                    }

                    if !prepared.warnings.isEmpty {
                        continuation.yield(.streamStart(warnings: prepared.warnings))
                    }
                    var toolCalls = GoogleInteractionsStreamingToolCalls()
                    var hasFunctionCall = false
                    var sourceCounter = 0
                    var emittedSourceKeys: Set<String> = []
                    for event in parseServerSentEvents(response.body) where event.data != "[DONE]" {
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        if request.includeRawChunks {
                            continuation.yield(.raw(raw))
                        }
                        for source in googleInteractionsSources(from: raw, sourceCounter: &sourceCounter, emittedKeys: &emittedSourceKeys) {
                            continuation.yield(.source(source))
                        }
                        let eventType = raw["event_type"]?.stringValue
                        if let interaction = raw["interaction"] {
                            let metadata = googleInteractionsProviderMetadata(from: interaction)
                            if !metadata.isEmpty {
                                continuation.yield(.metadata(metadata))
                            }
                        }
                        if eventType == "step.start",
                           raw["step"]?["type"]?.stringValue == "function_call" {
                            hasFunctionCall = true
                            for part in toolCalls.start(step: raw["step"], index: raw["index"]?.intValue) {
                                continuation.yield(part)
                            }
                        }
                        if eventType == "step.delta", let delta = raw["delta"] {
                            if let text = delta["text"]?.stringValue, !text.isEmpty {
                                continuation.yield(.textDelta(text))
                            }
                            if let summary = delta["summary"]?.stringValue, !summary.isEmpty {
                                continuation.yield(.reasoningDelta(summary))
                            }
                            if delta["type"]?.stringValue == "arguments_delta" {
                                hasFunctionCall = true
                                for part in toolCalls.delta(delta, index: raw["index"]?.intValue) {
                                    continuation.yield(part)
                                }
                            }
                        }
                        if eventType == "step.stop" {
                            for part in toolCalls.stop(index: raw["index"]?.intValue) {
                                continuation.yield(part)
                            }
                        }
                        if eventType == "interaction.completed" || eventType == "interaction.failed" || eventType == "interaction.incomplete" || eventType == "interaction.cancelled" {
                            let interaction = raw["interaction"] ?? raw
                            continuation.yield(.finish(
                                reason: googleInteractionsFinishReason(status: interaction["status"]?.stringValue, hasFunctionCall: hasFunctionCall),
                                usage: googleInteractionsUsage(from: interaction)
                            ))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func sendInteractions(body: JSONValue, headers: [String: String], abortSignal: AIAbortSignal?) async throws -> JSONValue {
        let response = try await config.transport.send(config.request(path: "/interactions", modelID: modelID, body: body, headers: googleInteractionsHeaders(headers), abortSignal: abortSignal))
        guard (200..<300).contains(response.statusCode) else {
            throw httpStatusError(provider: providerID, response: response)
        }
        return try response.jsonValue()
    }

    private func resolvedInteraction(_ raw: JSONValue, requestHeaders: [String: String], abortSignal: AIAbortSignal?) async throws -> JSONValue {
        guard agent != nil,
              !googleInteractionsIsTerminal(raw["status"]?.stringValue),
              let id = raw["id"]?.stringValue else {
            return raw
        }
        return try await pollInteraction(id: id, requestHeaders: requestHeaders, timeoutNanoseconds: googleInteractionsPollTimeout(raw: raw), abortSignal: abortSignal)
    }

    private func pollInteraction(id: String, requestHeaders: [String: String], timeoutNanoseconds: UInt64, abortSignal: AIAbortSignal?) async throws -> JSONValue {
        let started = DispatchTime.now().uptimeNanoseconds
        repeat {
            let response = try await config.transport.send(AIHTTPRequest(
                method: "GET",
                url: try requireURL("\(config.baseURL)/interactions/\(id)"),
                headers: config.headers.mergingHeaders(googleInteractionsHeaders(requestHeaders)),
                abortSignal: abortSignal
            ))
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: providerID, response: response)
            }
            let raw = try response.jsonValue()
            if googleInteractionsIsTerminal(raw["status"]?.stringValue) {
                return raw
            }
            try await sleepWithAbortSignal(nanoseconds: 10_000_000, abortSignal: abortSignal)
        } while DispatchTime.now().uptimeNanoseconds - started < timeoutNanoseconds

        throw AIError.invalidResponse(provider: providerID, message: "Google Interactions polling timed out.")
    }
}

