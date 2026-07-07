import Foundation

public struct MCPRequestOptions: Sendable {
    public var abortSignal: AIAbortSignal?

    public init(abortSignal: AIAbortSignal? = nil) {
        self.abortSignal = abortSignal
    }
}

public final class MCPHTTPTransport: MCPTransport, @unchecked Sendable {
    private let url: URL
    private let headers: [String: String]
    private let transport: any AITransport
    private let streamingTransport: (any AIStreamingTransport)?
    private let authProvider: (any MCPOAuthProvider)?
    private var protocolVersion: String?
    private var sessionID: String?
    private let terminateSessionOnClose: Bool
    private let onSessionIDChange: (@Sendable (String?) -> Void)?
    private let onSessionExpired: (@Sendable (String) -> Void)?
    private var requestHandler: (@Sendable (JSONValue) async -> JSONValue)?
    private var inboundTask: Task<Void, Never>?
    private var lastInboundEventID: String?
    private let maxInboundReconnectAttempts: Int
    private let inboundReconnectDelayNanoseconds: UInt64

    public init(
        url: URL,
        headers: [String: String] = [:],
        transport: any AITransport = URLSessionTransport.shared,
        authProvider: (any MCPOAuthProvider)? = nil,
        initialSessionID: String? = nil,
        initialProtocolVersion: String? = nil,
        terminateSessionOnClose: Bool = true,
        onSessionIDChange: (@Sendable (String?) -> Void)? = nil,
        onSessionExpired: (@Sendable (String) -> Void)? = nil,
        maxInboundReconnectAttempts: Int = 2,
        inboundReconnectDelayNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.url = url
        self.headers = headers
        self.transport = transport
        self.streamingTransport = transport as? any AIStreamingTransport
        self.authProvider = authProvider
        self.protocolVersion = initialProtocolVersion
        self.sessionID = initialSessionID
        self.terminateSessionOnClose = terminateSessionOnClose
        self.onSessionIDChange = onSessionIDChange
        self.onSessionExpired = onSessionExpired
        self.maxInboundReconnectAttempts = maxInboundReconnectAttempts
        self.inboundReconnectDelayNanoseconds = inboundReconnectDelayNanoseconds
    }

    public convenience init(
        url: String,
        headers: [String: String] = [:],
        transport: any AITransport = URLSessionTransport.shared,
        authProvider: (any MCPOAuthProvider)? = nil,
        initialSessionID: String? = nil,
        initialProtocolVersion: String? = nil,
        terminateSessionOnClose: Bool = true,
        onSessionIDChange: (@Sendable (String?) -> Void)? = nil,
        onSessionExpired: (@Sendable (String) -> Void)? = nil,
        maxInboundReconnectAttempts: Int = 2,
        inboundReconnectDelayNanoseconds: UInt64 = 1_000_000_000
    ) throws {
        try self.init(
            url: requireURL(url),
            headers: headers,
            transport: transport,
            authProvider: authProvider,
            initialSessionID: initialSessionID,
            initialProtocolVersion: initialProtocolVersion,
            terminateSessionOnClose: terminateSessionOnClose,
            onSessionIDChange: onSessionIDChange,
            onSessionExpired: onSessionExpired,
            maxInboundReconnectAttempts: maxInboundReconnectAttempts,
            inboundReconnectDelayNanoseconds: inboundReconnectDelayNanoseconds
        )
    }

    public func setRequestHandler(_ handler: (@Sendable (JSONValue) async -> JSONValue)?) async {
        requestHandler = handler
    }

    public func setProtocolVersion(_ protocolVersion: String?) async {
        self.protocolVersion = protocolVersion
    }

    public func start() async throws {
        guard inboundTask == nil else { return }
        inboundTask = Task { [weak self] in
            await self?.openInboundSSELoop()
        }
    }

    private func openInboundSSELoop() async {
        var attempts = 0
        while !Task.isCancelled {
            do {
                let shouldReconnectAfterError = try await openInboundSSEOnce()
                if !shouldReconnectAfterError { return }
                return
            } catch is CancellationError {
                return
            } catch {
                attempts += 1
                guard attempts <= maxInboundReconnectAttempts else { return }
                try? await Task.sleep(nanoseconds: inboundReconnectDelayNanoseconds)
            }
        }
    }

    @discardableResult
    private func openInboundSSEOnce() async throws -> Bool {
        if let streamingTransport {
            let response = try await sendRawStream(
                method: "GET",
                accept: "text/event-stream",
                body: nil,
                extraHeaders: lastInboundEventID.map { ["last-event-id": $0] } ?? [:],
                transport: streamingTransport
            )
            if response.statusCode == 405 {
                return false
            }
            guard (200..<300).contains(response.statusCode) else {
                throw MCPClientError(
                    message: "MCP HTTP Transport Error: GET SSE failed: \(response.statusCode)",
                    statusCode: response.statusCode,
                    url: url.absoluteString
                )
            }
            _ = try await handleStreamingResponse(response, expectedID: nil)
            return true
        }

        let response = try await sendRaw(
            method: "GET",
            accept: "text/event-stream",
            body: nil,
            extraHeaders: lastInboundEventID.map { ["last-event-id": $0] } ?? [:]
        )
        if response.statusCode == 405 {
            return false
        }
        guard (200..<300).contains(response.statusCode) else {
            throw MCPClientError(
                message: "MCP HTTP Transport Error: GET SSE failed: \(response.statusCode)",
                statusCode: response.statusCode,
                url: url.absoluteString,
                responseBody: response.bodyText
            )
        }
        _ = try await handleBufferedResponse(response, expectedID: nil)
        return true
    }

    public func request(_ message: JSONValue) async throws -> JSONValue {
        try await request(message, options: nil)
    }

    public func request(_ message: JSONValue, options: MCPRequestOptions?) async throws -> JSONValue {
        let response = try await send(message, options: options)
        let expectedID = message["id"]?.intValue
        if let responseID = expectedID, let array = response.arrayValue {
            guard let match = array.first(where: { $0["id"]?.intValue == responseID }) else {
                throw MCPClientError(message: "MCP HTTP Transport Error: response batch did not include id \(responseID).")
            }
            return match
        }
        return response
    }

    public func notify(_ message: JSONValue) async throws {
        try await sendNotification(message)
    }

    public func close() async throws {
        inboundTask?.cancel()
        inboundTask = nil
        guard terminateSessionOnClose, sessionID != nil else { return }
        _ = try? await sendRaw(
            method: "DELETE",
            accept: "application/json",
            body: nil
        )
    }

    private func send(_ message: JSONValue, options: MCPRequestOptions? = nil) async throws -> JSONValue {
        try options?.abortSignal?.throwIfAborted()
        let isInitializeRequest = message["method"]?.stringValue == "initialize"
        if let streamingTransport {
            let response = try await sendRawStream(
                method: "POST",
                accept: "application/json, text/event-stream",
                body: try encodeJSONBody(message),
                includeSessionID: !isInitializeRequest,
                abortSignal: options?.abortSignal,
                transport: streamingTransport
            )
            return try await handleStreamingResponse(response, expectedID: message["id"]?.intValue)
        }

        let response = try await sendRaw(
            method: "POST",
            accept: "application/json, text/event-stream",
            body: try encodeJSONBody(message),
            includeSessionID: !isInitializeRequest,
            abortSignal: options?.abortSignal
        )
        return try await handleBufferedResponse(response, expectedID: message["id"]?.intValue)
    }

    private func sendNotification(_ message: JSONValue) async throws {
        if let streamingTransport {
            _ = try await sendRawStream(
                method: "POST",
                accept: "application/json, text/event-stream",
                body: try encodeJSONBody(message),
                transport: streamingTransport
            )
            return
        }

        _ = try await sendRaw(
            method: "POST",
            accept: "application/json, text/event-stream",
            body: try encodeJSONBody(message)
        )
    }

    private func sendRaw(
        method: String,
        accept: String,
        body: Data?,
        extraHeaders: [String: String] = [:],
        includeSessionID: Bool = true,
        abortSignal: AIAbortSignal? = nil,
        triedAuth: Bool = false
    ) async throws -> AIHTTPResponse {
        try abortSignal?.throwIfAborted()
        let requestSessionID = includeSessionID ? sessionID : nil
        let requestHeaders = try await commonHeaders(accept: accept, hasBody: body != nil, extraHeaders: extraHeaders, includeSessionID: includeSessionID)
        let response = try await transport.send(AIHTTPRequest(
            method: method,
            url: url,
            headers: requestHeaders,
            body: body,
            abortSignal: abortSignal
        ))
        applySessionID(from: response)
        if method == "GET", response.statusCode == 405 {
            return response
        }
        if response.statusCode == 401, let authProvider, !triedAuth {
            await authProvider.invalidateCredentials(.tokens)
            let authorized = try await authProvider.authorize(resourceMetadataURL: mcpOAuthResourceMetadataURL(from: response.headers))
            guard authorized else {
                throw MCPClientError(
                    message: "MCP HTTP Transport Error: Unauthorized",
                    statusCode: response.statusCode,
                    url: url.absoluteString,
                    responseBody: response.bodyText
                )
            }
            return try await sendRaw(
                method: method,
                accept: accept,
                body: body,
                extraHeaders: extraHeaders,
                includeSessionID: includeSessionID,
                abortSignal: abortSignal,
                triedAuth: true
            )
        }
        guard (200..<300).contains(response.statusCode) else {
            var message = "MCP HTTP Transport Error: \(method) \(url.absoluteString) failed with HTTP \(response.statusCode): \(response.bodyText)"
            if method == "POST", response.statusCode == 404 {
                if let requestSessionID {
                    expireSessionID(requestSessionID)
                    message += ". The MCP session expired. Create a new client without `initialSessionID` to start a fresh session"
                } else {
                    message += ". This server does not support HTTP transport. Try using `sse` transport instead"
                }
            }
            throw MCPClientError(
                message: message,
                statusCode: response.statusCode,
                url: url.absoluteString,
                responseBody: response.bodyText
            )
        }
        return response
    }

    private func sendRawStream(
        method: String,
        accept: String,
        body: Data?,
        extraHeaders: [String: String] = [:],
        includeSessionID: Bool = true,
        abortSignal: AIAbortSignal? = nil,
        triedAuth: Bool = false,
        transport: any AIStreamingTransport
    ) async throws -> AIHTTPStreamResponse {
        try abortSignal?.throwIfAborted()
        let requestSessionID = includeSessionID ? sessionID : nil
        let requestHeaders = try await commonHeaders(accept: accept, hasBody: body != nil, extraHeaders: extraHeaders, includeSessionID: includeSessionID)
        let response = try await transport.stream(AIHTTPRequest(
            method: method,
            url: url,
            headers: requestHeaders,
            body: body,
            abortSignal: abortSignal
        ))
        applySessionID(from: response)
        if method == "GET", response.statusCode == 405 {
            return response
        }
        if response.statusCode == 401, let authProvider, !triedAuth {
            await authProvider.invalidateCredentials(.tokens)
            let authorized = try await authProvider.authorize(resourceMetadataURL: mcpOAuthResourceMetadataURL(from: response.headers))
            guard authorized else {
                throw MCPClientError(
                    message: "MCP HTTP Transport Error: Unauthorized",
                    statusCode: response.statusCode,
                    url: url.absoluteString
                )
            }
            return try await sendRawStream(
                method: method,
                accept: accept,
                body: body,
                extraHeaders: extraHeaders,
                includeSessionID: includeSessionID,
                abortSignal: abortSignal,
                triedAuth: true,
                transport: transport
            )
        }
        guard (200..<300).contains(response.statusCode) else {
            var message = "MCP HTTP Transport Error: \(method) \(url.absoluteString) failed with HTTP \(response.statusCode)"
            if method == "POST", response.statusCode == 404 {
                if let requestSessionID {
                    expireSessionID(requestSessionID)
                    message += ". The MCP session expired. Create a new client without `initialSessionID` to start a fresh session"
                } else {
                    message += ". This server does not support HTTP transport. Try using `sse` transport instead"
                }
            }
            throw MCPClientError(
                message: message,
                statusCode: response.statusCode,
                url: url.absoluteString
            )
        }
        return response
    }

    private func commonHeaders(accept: String, hasBody: Bool, extraHeaders: [String: String], includeSessionID: Bool = true) async throws -> [String: String] {
        var requestHeaders = headers
        requestHeaders["accept"] = accept
        requestHeaders["mcp-protocol-version"] = protocolVersion ?? MCPClient.latestProtocolVersion
        if hasBody {
            requestHeaders["content-type"] = "application/json"
        }
        if includeSessionID, let sessionID {
            requestHeaders["mcp-session-id"] = sessionID
        }
        requestHeaders.merge(extraHeaders) { _, new in new }
        if let token = try await authProvider?.accessToken(), !token.isEmpty {
            requestHeaders["authorization"] = "Bearer \(token)"
        }
        return requestHeaders
    }

    private func setSessionID(_ sessionID: String?) {
        guard self.sessionID != sessionID else { return }
        self.sessionID = sessionID
        onSessionIDChange?(sessionID)
    }

    private func applySessionID(from response: AIHTTPResponse) {
        if let sessionID = response.headerValue("mcp-session-id") {
            setSessionID(sessionID)
        }
    }

    private func applySessionID(from response: AIHTTPStreamResponse) {
        if let sessionID = response.headerValue("mcp-session-id") {
            setSessionID(sessionID)
        }
    }

    private func expireSessionID(_ expiredSessionID: String) {
        if sessionID == expiredSessionID {
            setSessionID(nil)
        }
        onSessionExpired?(expiredSessionID)
    }

    private func handleBufferedResponse(_ response: AIHTTPResponse, expectedID: Int?) async throws -> JSONValue {
        if response.statusCode == 202 {
            return .object([:])
        }

        let contentType = response.headerValue("content-type") ?? ""
        if contentType.localizedCaseInsensitiveContains("text/event-stream") {
            let messages = try await parseBufferedSSEMessages(response.body)
            if let expectedID {
                guard let match = messages.first(where: { $0["id"]?.intValue == expectedID }) else {
                    throw MCPClientError(message: "MCP HTTP Transport Error: SSE response did not include id \(expectedID).")
                }
                return match
            }
            return .array(messages)
        }

        if contentType.isEmpty || contentType.localizedCaseInsensitiveContains("application/json") {
            return try response.jsonValue()
        }

        throw MCPClientError(
            message: "MCP HTTP Transport Error: Unexpected content type: \(contentType)",
            statusCode: response.statusCode,
            url: url.absoluteString,
            responseBody: response.bodyText
        )
    }

    private func parseBufferedSSEMessages(_ data: Data) async throws -> [JSONValue] {
        var messages: [JSONValue] = []
        for event in parseServerSentEvents(data) where event.event == nil || event.event == "message" {
            if let id = event.id {
                lastInboundEventID = id
            }
            do {
                let message = try decodeJSONBody(Data(event.data.utf8))
                if message["method"]?.stringValue != nil, message["id"] != nil, let requestHandler {
                    let response = await requestHandler(message)
                    try await sendNotification(response)
                } else {
                    messages.append(message)
                }
            } catch {
                throw MCPClientError(message: "MCP HTTP Transport Error: Failed to parse message")
            }
        }
        return messages
    }

    private func handleStreamingResponse(_ response: AIHTTPStreamResponse, expectedID: Int?) async throws -> JSONValue {
        if response.statusCode == 202 {
            return .object([:])
        }

        let contentType = response.headerValue("content-type") ?? ""
        if contentType.localizedCaseInsensitiveContains("text/event-stream") {
            return try await processSSEStream(response.body, expectedID: expectedID)
        }

        let body = try await collectStreamData(response.body)
        if contentType.isEmpty || contentType.localizedCaseInsensitiveContains("application/json") {
            return try decodeJSONBody(body)
        }

        throw MCPClientError(
            message: "MCP HTTP Transport Error: Unexpected content type: \(contentType)",
            statusCode: response.statusCode,
            url: url.absoluteString,
            responseBody: String(data: body, encoding: .utf8)
        )
    }

    private func collectStreamData(_ stream: AsyncThrowingStream<Data, Error>) async throws -> Data {
        var body = Data()
        for try await chunk in stream {
            body.append(chunk)
        }
        return body
    }

    private func processSSEStream(_ stream: AsyncThrowingStream<Data, Error>, expectedID: Int?) async throws -> JSONValue {
        var buffer = Data()
        var eventName: String?
        var eventID: String?
        var dataLines: [String] = []

        func resetEvent() {
            eventName = nil
            eventID = nil
            dataLines.removeAll()
        }

        func handleEvent() async throws -> JSONValue? {
            defer { resetEvent() }
            guard !dataLines.isEmpty else { return nil }
            guard eventName == nil || eventName == "message" else { return nil }
            if let eventID {
                lastInboundEventID = eventID
            }
            let data = dataLines.joined(separator: "\n")
            let message: JSONValue
            do {
                message = try decodeJSONBody(Data(data.utf8))
            } catch {
                throw MCPClientError(message: "MCP HTTP Transport Error: Failed to parse message")
            }

            if message["method"]?.stringValue != nil, message["id"] != nil, let requestHandler {
                let response = await requestHandler(message)
                try await sendNotification(response)
                return nil
            }

            if let expectedID {
                return message["id"]?.intValue == expectedID ? message : nil
            }
            return nil
        }

        for try await chunk in stream {
            try Task.checkCancellation()
            buffer.append(chunk)
            while let newlineIndex = buffer.firstIndex(of: 10) {
                var lineData = Data(buffer[..<newlineIndex])
                buffer.removeSubrange(...newlineIndex)
                if lineData.last == 13 {
                    lineData.removeLast()
                }
                let line = String(decoding: lineData, as: UTF8.self)
                if line.isEmpty {
                    if let message = try await handleEvent() {
                        return message
                    }
                } else if line.hasPrefix("event:") {
                    eventName = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("id:") {
                    eventID = String(line.dropFirst("id:".count)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    dataLines.append(String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces))
                }
            }
        }

        if !buffer.isEmpty {
            dataLines.append(String(decoding: buffer, as: UTF8.self))
        }
        if let message = try await handleEvent() {
            return message
        }
        return .array([])
    }
}
