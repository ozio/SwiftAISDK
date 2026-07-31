import Foundation

public actor MCPClient {
    public static let latestProtocolVersion = "2025-11-25"
    public static let supportedProtocolVersions: Set<String> = [
        "2025-11-25",
        "2025-06-18",
        "2025-03-26",
        "2024-11-05"
    ]

    public private(set) var serverInfo = MCPImplementation(name: "", version: "")
    public private(set) var instructions: String?
    public private(set) var serverCapabilities: JSONValue = .object([:])
    public private(set) var initializeResult: JSONValue = .object([
        "protocolVersion": .string(MCPClient.latestProtocolVersion),
        "capabilities": .object([:]),
        "serverInfo": .object([
            "name": .string(""),
            "version": .string("")
        ])
    ])

    private let transport: any MCPTransport
    private let clientInfo: MCPImplementation
    private let clientCapabilities: JSONValue
    private let initialInitializeResult: JSONValue?
    private let initializationOptions: MCPRequestOptions?
    private let maxRetries: Int
    private var requestID = 0
    private var isClosed = true
    private var elicitationRequestHandler: MCPElicitationHandler?

    private init(
        transport: any MCPTransport,
        clientName: String,
        clientVersion: String,
        clientCapabilities: JSONValue,
        initialInitializeResult: JSONValue?,
        initializationOptions: MCPRequestOptions?,
        maxRetries: Int
    ) {
        self.transport = transport
        self.clientInfo = MCPImplementation(name: clientName, version: clientVersion)
        self.clientCapabilities = clientCapabilities
        self.initialInitializeResult = initialInitializeResult
        self.initializationOptions = initializationOptions
        self.maxRetries = maxRetries
    }

    public static func connect(
        transport: any MCPTransport,
        clientName: String = "swift-ai-sdk-mcp-client",
        clientVersion: String = "1.0.0",
        clientCapabilities: JSONValue = .object([:]),
        initialInitializeResult: JSONValue? = nil,
        initializationOptions: MCPRequestOptions? = nil,
        maxRetries: Int = 0
    ) async throws -> MCPClient {
        guard maxRetries >= 0 else {
            throw MCPClientError(message: "maxRetries must be >= 0")
        }
        let client = MCPClient(
            transport: transport,
            clientName: clientName,
            clientVersion: clientVersion,
            clientCapabilities: clientCapabilities,
            initialInitializeResult: initialInitializeResult,
            initializationOptions: initializationOptions,
            maxRetries: maxRetries
        )
        try await client.initialize()
        return client
    }

    public func close() async throws {
        await transport.setRequestHandler(nil)
        guard !isClosed else { return }
        try await transport.close()
        isClosed = true
    }

    public func listTools(cursor: String? = nil) async throws -> MCPListToolsResult {
        try assertCapability("tools", method: "tools/list")
        let result = try await request(
            method: "tools/list",
            params: cursor.map { .object(["cursor": .string($0)]) }
        )
        return try MCPListToolsResult(json: result)
    }

    public func callTool(name: String, arguments: JSONValue = .object([:]), options: MCPRequestOptions? = nil) async throws -> MCPCallToolResult {
        try assertCapability("tools", method: "tools/call")
        let result = try await callToolWithRetry(options: options) {
            try await self.request(
                method: "tools/call",
                params: .object([
                    "name": .string(name),
                    "arguments": arguments
                ]),
                options: options
            )
        }
        return MCPCallToolResult(json: result)
    }

    public func tools() async throws -> [String: AITool] {
        let definitions = try await listTools()
        return toolsFromDefinitions(definitions)
    }

    public func toolsFromDefinitions(_ definitions: MCPListToolsResult) -> [String: AITool] {
        definitions.tools.reduce(into: [String: AITool]()) { output, definition in
            output[definition.name] = tool(from: definition)
        }
    }

    public func listResources(cursor: String? = nil, options: MCPRequestOptions? = nil) async throws -> MCPListResourcesResult {
        let result = try await request(
            method: "resources/list",
            params: cursor.map { .object(["cursor": .string($0)]) },
            options: options
        )
        return try MCPListResourcesResult(json: result)
    }

    public func readResource(uri: String, options: MCPRequestOptions? = nil) async throws -> MCPReadResourceResult {
        let result = try await request(
            method: "resources/read",
            params: .object(["uri": .string(uri)]),
            options: options
        )
        return try MCPReadResourceResult(json: result)
    }

    public func listResourceTemplates(options: MCPRequestOptions? = nil) async throws -> MCPListResourceTemplatesResult {
        let result = try await request(method: "resources/templates/list", options: options)
        return try MCPListResourceTemplatesResult(json: result)
    }

    public func experimentalListPrompts(cursor: String? = nil, options: MCPRequestOptions? = nil) async throws -> MCPListPromptsResult {
        let result = try await request(
            method: "prompts/list",
            params: cursor.map { .object(["cursor": .string($0)]) },
            options: options
        )
        return try MCPListPromptsResult(json: result)
    }

    public func experimentalGetPrompt(name: String, arguments: JSONValue = .object([:]), options: MCPRequestOptions? = nil) async throws -> MCPGetPromptResult {
        let result = try await request(
            method: "prompts/get",
            params: .object([
                "name": .string(name),
                "arguments": arguments
            ]),
            options: options
        )
        return try MCPGetPromptResult(json: result)
    }

    public func complete(
        ref: JSONValue,
        argument: MCPCompleteArgument,
        contextArguments: [String: String]? = nil,
        metadata: JSONValue? = nil,
        options: MCPRequestOptions? = nil
    ) async throws -> MCPCompleteResult {
        var params: [String: JSONValue] = [
            "ref": ref,
            "argument": argument.rawValue
        ]
        if let contextArguments {
            params["context"] = .object([
                "arguments": .object(contextArguments.mapValues(JSONValue.string))
            ])
        }
        if let metadata {
            params["_meta"] = metadata
        }
        let result = try await request(
            method: "completion/complete",
            params: .object(params),
            options: options
        )
        return try MCPCompleteResult(json: result)
    }

    public func onElicitationRequest(_ handler: MCPElicitationHandler?) {
        elicitationRequestHandler = handler
    }

    private func initialize() async throws {
        let externalSignal = initializationOptions?.abortSignal
        let timeout = initializationOptions?.effectiveTimeoutMilliseconds
        let timeoutController = timeout.map { _ in AIAbortController() }
        let timeoutTask: Task<Void, Never>? = if let timeout, let timeoutController {
            Task {
                let milliseconds = UInt64(max(0, timeout))
                let (nanoseconds, overflow) = milliseconds.multipliedReportingOverflow(by: 1_000_000)
                do {
                    try await Task.sleep(nanoseconds: overflow ? UInt64.max : nanoseconds)
                    timeoutController.abort(reason: "MCP client initialization timed out after \(timeout)ms", reasonName: "TimeoutError")
                } catch {}
            }
        } else {
            nil
        }
        defer { timeoutTask?.cancel() }
        let effectiveOptions = MCPRequestOptions(abortSignal: mergeAbortSignals(externalSignal, timeoutController?.signal))

        do {
            if externalSignal?.isAborted == true {
                throw MCPClientError(message: "MCP client initialization was aborted")
            }
            await transport.setRequestHandler { [weak self] request in
                guard let self else {
                    return mcpJSONRPCErrorResponse(
                        id: request["id"],
                        code: -32603,
                        message: "MCP client has been released."
                    )
                }
                return await self.handleIncomingRequest(request)
            }
            try effectiveOptions.abortSignal?.throwIfAborted()
            isClosed = false
            try await mcpRunWithRequestOptions(
                effectiveOptions,
                timeoutMessage: { timeout in "MCP client initialization timed out after \(timeout)ms" },
                abortMessage: "MCP client initialization was aborted"
            ) { [transport] _ in
                try await transport.start()
            }

            if let initialInitializeResult {
                try await applyInitializeResult(initialInitializeResult)
                return
            }

            let result = try await request(
                method: "initialize",
                params: .object([
                    "protocolVersion": .string(Self.latestProtocolVersion),
                    "capabilities": clientCapabilities,
                    "clientInfo": clientInfo.jsonValue
                ]),
                skipCapabilityCheck: true,
                options: effectiveOptions
            )
            try await applyInitializeResult(result)
            try effectiveOptions.abortSignal?.throwIfAborted()
            try await notify(method: "notifications/initialized", options: effectiveOptions)
            try effectiveOptions.abortSignal?.throwIfAborted()
        } catch {
            try? await close()
            if timeoutController?.signal.isAborted == true, let timeout {
                throw MCPClientError(message: "MCP client initialization timed out after \(timeout)ms")
            }
            if externalSignal?.isAborted == true {
                throw MCPClientError(message: "MCP client initialization was aborted")
            }
            throw error
        }
    }

    private func applyInitializeResult(_ result: JSONValue) async throws {
        guard let protocolVersion = result["protocolVersion"]?.stringValue else {
            throw MCPClientError(message: "Server sent invalid initialize result.")
        }
        guard Self.supportedProtocolVersions.contains(protocolVersion) else {
            throw MCPClientError(message: "Server protocol version is not supported: \(protocolVersion)")
        }
        serverCapabilities = result["capabilities"] ?? .object([:])
        serverInfo = try MCPImplementation(json: result["serverInfo"] ?? .object([:]))
        initializeResult = result
        instructions = result["instructions"]?.stringValue
        await transport.setProtocolVersion(protocolVersion)
    }

    private func handleIncomingRequest(_ message: JSONValue) async -> JSONValue {
        let id = message["id"]
        guard let method = message["method"]?.stringValue else {
            return mcpJSONRPCErrorResponse(id: id, code: -32600, message: "Invalid MCP request.")
        }

        if method == "ping" {
            return mcpJSONRPCResultResponse(id: id, result: .object([:]))
        }

        guard method == "elicitation/create" else {
            return mcpJSONRPCErrorResponse(
                id: id,
                code: -32601,
                message: "Unsupported request method: \(method)"
            )
        }

        guard let elicitationRequestHandler else {
            return mcpJSONRPCErrorResponse(
                id: id,
                code: -32601,
                message: "No elicitation handler registered on client"
            )
        }

        do {
            let request = try MCPElicitationRequest(params: message["params"] ?? .object([:]))
            let result = try await elicitationRequestHandler(request)
            return mcpJSONRPCResultResponse(id: id, result: result.rawValue)
        } catch let error as MCPClientError {
            return mcpJSONRPCErrorResponse(
                id: id,
                code: -32602,
                message: "Invalid elicitation request: \(error.message)",
                data: error.data
            )
        } catch {
            return mcpJSONRPCErrorResponse(
                id: id,
                code: -32603,
                message: String(describing: error)
            )
        }
    }

    private func request(
        method: String,
        params: JSONValue? = nil,
        skipCapabilityCheck: Bool = false,
        options: MCPRequestOptions? = nil
    ) async throws -> JSONValue {
        guard !isClosed else {
            throw MCPClientError(message: "Attempted to send a request from a closed client.")
        }
        if !skipCapabilityCheck {
            try assertCapability(capabilityName(for: method), method: method)
        }
        let id = requestID
        requestID += 1
        let message = JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": .number(Double(id)),
            "method": .string(method),
            "params": params
        ])
        let response = try await mcpRunWithRequestOptions(
            options,
            timeoutMessage: { timeout in "Request timed out after \(timeout)ms" },
            abortMessage: "Request was aborted"
        ) { [transport] effectiveOptions in
            try await transport.request(message, options: effectiveOptions)
        }
        return try result(from: response, expectedID: id)
    }

    private func notify(
        method: String,
        params: JSONValue? = nil,
        options: MCPRequestOptions? = nil
    ) async throws {
        let message = JSONValue.object([
            "jsonrpc": .string("2.0"),
            "method": .string(method),
            "params": params
        ])
        try await mcpRunWithRequestOptions(
            options,
            timeoutMessage: { timeout in "Request timed out after \(timeout)ms" },
            abortMessage: "Request was aborted"
        ) { [transport] effectiveOptions in
            try effectiveOptions.abortSignal?.throwIfAborted()
            try await transport.notify(message)
        }
    }

    private func result(from response: JSONValue, expectedID: Int) throws -> JSONValue {
        if let responseID = response["id"]?.intValue, responseID != expectedID {
            throw MCPClientError(message: "Protocol error: received response for id \(responseID), expected \(expectedID).")
        }
        if let error = response["error"] {
            throw MCPClientError(
                message: error["message"]?.stringValue ?? "Unknown MCP error.",
                code: error["code"]?.intValue,
                data: error["data"]
            )
        }
        guard let result = response["result"] else {
            throw MCPClientError(message: "Expected MCP JSON-RPC response with result.")
        }
        return result
    }

    private func assertCapability(_ capability: String, method: String) throws {
        guard capability != "initialize" else { return }
        if serverCapabilities[capability] == nil {
            throw MCPClientError(message: "Server does not support \(capability) for \(method).")
        }
    }

    private func capabilityName(for method: String) -> String {
        if method.hasPrefix("tools/") { return "tools" }
        if method.hasPrefix("resources/") { return "resources" }
        if method.hasPrefix("prompts/") { return "prompts" }
        if method == "completion/complete" { return "completions" }
        return method
    }

    private func callToolWithRetry(
        options: MCPRequestOptions?,
        execute: () async throws -> JSONValue
    ) async throws -> JSONValue {
        guard maxRetries > 0 else {
            return try await execute()
        }
        var errors: [Error] = []
        for attempt in 0...maxRetries {
            try options?.abortSignal?.throwIfAborted()
            do {
                return try await execute()
            } catch {
                errors.append(error)
                guard attempt < maxRetries, mcpShouldRetryToolCall(error) else {
                    throw error
                }
            }
        }
        throw errors.last ?? MCPClientError(message: "MCP tool call failed.")
    }

    private func tool(from definition: MCPToolDefinition) -> AITool {
        var inputSchema = definition.inputSchema.objectValue ?? ["type": .string("object")]
        if inputSchema["properties"] == nil {
            inputSchema["properties"] = .object([:])
        }
        if inputSchema["additionalProperties"] == nil {
            inputSchema["additionalProperties"] = .bool(false)
        }

        let resolvedTitle = definition.title ?? definition.annotations?["title"]?.stringValue
        var metadata: [String: JSONValue] = [
            "clientName": .string(clientInfo.name),
            "toolName": .string(definition.name)
        ]
        if let resolvedTitle {
            metadata["title"] = .string(resolvedTitle)
        }
        if let mcpMetadata = definition.metadata {
            metadata["_meta"] = mcpMetadata
        }

        return AITool.dynamic(
            name: definition.name,
            description: definition.description,
            parameters: .object(inputSchema),
            providerMetadata: ["mcp": .object(metadata)],
            toModelOutput: { context in
                mcpToolModelOutput(from: context.output)
            }
        ) { [weak self] arguments, context in
            guard let self else {
                throw MCPClientError(message: "MCP client has been released.")
            }
            try context.abortSignal?.throwIfAborted()
            return try await self.callTool(
                name: definition.name,
                arguments: arguments,
                options: MCPRequestOptions(abortSignal: context.abortSignal)
            ).rawValue
        } execute: { [weak self] arguments in
            guard let self else {
                throw MCPClientError(message: "MCP client has been released.")
            }
            return try await self.callTool(name: definition.name, arguments: arguments).rawValue
        }
    }
}

private final class MCPRequestRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?
    private var abortRegistration: AIAbortHandlerRegistration?
    private var completed = false

    init(continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func install(
        timeoutTask: Task<Void, Never>?,
        operationTask: Task<Void, Never>,
        abortRegistration: AIAbortHandlerRegistration?
    ) {
        lock.lock()
        if completed {
            lock.unlock()
            timeoutTask?.cancel()
            operationTask.cancel()
            abortRegistration?.cancel()
            return
        }
        self.timeoutTask = timeoutTask
        self.operationTask = operationTask
        self.abortRegistration = abortRegistration
        lock.unlock()
    }

    func resolve(_ result: Result<Value, Error>) {
        lock.lock()
        guard !completed, let continuation else {
            lock.unlock()
            return
        }
        completed = true
        self.continuation = nil
        let timeoutTask = self.timeoutTask
        let operationTask = self.operationTask
        let abortRegistration = self.abortRegistration
        self.timeoutTask = nil
        self.operationTask = nil
        self.abortRegistration = nil
        lock.unlock()

        timeoutTask?.cancel()
        operationTask?.cancel()
        abortRegistration?.cancel()
        continuation.resume(with: result)
    }
}

private func mcpRunWithRequestOptions<Value: Sendable>(
    _ options: MCPRequestOptions?,
    timeoutMessage: @escaping @Sendable (Int) -> String,
    abortMessage: String,
    operation: @escaping @Sendable (MCPRequestOptions) async throws -> Value
) async throws -> Value {
    let externalSignal = options?.abortSignal
    if externalSignal?.isAborted == true {
        throw MCPClientError(message: abortMessage)
    }
    let timeout = options?.effectiveTimeoutMilliseconds
    guard externalSignal != nil || timeout != nil else {
        return try await operation(MCPRequestOptions())
    }

    let timeoutController = timeout.map { _ in AIAbortController() }
    let combinedSignal = mergeAbortSignals(externalSignal, timeoutController?.signal)
    let effectiveOptions = MCPRequestOptions(abortSignal: combinedSignal)

    return try await withCheckedThrowingContinuation { continuation in
        let race = MCPRequestRace<Value>(continuation: continuation)
        let abortRegistration = externalSignal?.addAbortHandler { _ in
            race.resolve(.failure(MCPClientError(message: abortMessage)))
        }
        let timeoutTask: Task<Void, Never>? = if let timeout, let timeoutController {
            Task {
                let milliseconds = UInt64(max(0, timeout))
                let (nanoseconds, overflow) = milliseconds.multipliedReportingOverflow(by: 1_000_000)
                do {
                    try await Task.sleep(nanoseconds: overflow ? UInt64.max : nanoseconds)
                    let message = timeoutMessage(timeout)
                    timeoutController.abort(reason: message, reasonName: "TimeoutError")
                    race.resolve(.failure(MCPClientError(message: message)))
                } catch {}
            }
        } else {
            nil
        }

        let operationTask = Task {
            do {
                try effectiveOptions.abortSignal?.throwIfAborted()
                let value = try await operation(effectiveOptions)
                if externalSignal?.isAborted == true {
                    race.resolve(.failure(MCPClientError(message: abortMessage)))
                } else if timeoutController?.signal.isAborted == true, let timeout {
                    race.resolve(.failure(MCPClientError(message: timeoutMessage(timeout))))
                } else {
                    race.resolve(.success(value))
                }
            } catch {
                if externalSignal?.isAborted == true {
                    race.resolve(.failure(MCPClientError(message: abortMessage)))
                } else if timeoutController?.signal.isAborted == true, let timeout {
                    race.resolve(.failure(MCPClientError(message: timeoutMessage(timeout))))
                } else {
                    race.resolve(.failure(error))
                }
            }
        }
        race.install(
            timeoutTask: timeoutTask,
            operationTask: operationTask,
            abortRegistration: abortRegistration
        )
    }
}

private func mcpShouldRetryToolCall(_ error: Error) -> Bool {
    if let error = error as? MCPClientError {
        if let status = error.statusCode {
            return status == 408 || status == 409 || status == 429 || status >= 500
        }
        if error.code != nil {
            return false
        }
    }
    let text = String(describing: error)
    return ["ConnectionRefused", "ConnectionClosed", "FailedToOpenSocket", "ECONNRESET", "ECONNREFUSED", "ETIMEDOUT", "EPIPE"].contains { text.contains($0) }
}
