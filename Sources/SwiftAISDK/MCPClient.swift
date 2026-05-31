import Foundation

public struct MCPClientError: Error, CustomStringConvertible, Sendable {
    public var message: String
    public var code: Int?
    public var data: JSONValue?

    public init(message: String, code: Int? = nil, data: JSONValue? = nil) {
        self.message = message
        self.code = code
        self.data = data
    }

    public var description: String {
        if let code {
            return "MCP client error \(code): \(message)"
        }
        return "MCP client error: \(message)"
    }
}

public struct MCPImplementation: Equatable, Hashable, Sendable {
    public var name: String
    public var version: String
    public var title: String?

    public init(name: String, version: String, title: String? = nil) {
        self.name = name
        self.version = version
        self.title = title
    }

    init(json: JSONValue) throws {
        guard let name = json["name"]?.stringValue, let version = json["version"]?.stringValue else {
            throw MCPClientError(message: "Expected MCP implementation with name and version.")
        }
        self.init(name: name, version: version, title: json["title"]?.stringValue)
    }

    var jsonValue: JSONValue {
        .object([
            "name": .string(name),
            "version": .string(version),
            "title": title.map(JSONValue.string)
        ])
    }
}

public struct MCPToolDefinition: Equatable, Hashable, Sendable {
    public var name: String
    public var title: String?
    public var description: String?
    public var inputSchema: JSONValue
    public var outputSchema: JSONValue?
    public var annotations: JSONValue?
    public var metadata: JSONValue?

    public init(
        name: String,
        title: String? = nil,
        description: String? = nil,
        inputSchema: JSONValue,
        outputSchema: JSONValue? = nil,
        annotations: JSONValue? = nil,
        metadata: JSONValue? = nil
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.annotations = annotations
        self.metadata = metadata
    }

    init(json: JSONValue) throws {
        guard let name = json["name"]?.stringValue else {
            throw MCPClientError(message: "Expected MCP tool definition with name.")
        }
        self.init(
            name: name,
            title: json["title"]?.stringValue,
            description: json["description"]?.stringValue,
            inputSchema: json["inputSchema"] ?? .object(["type": .string("object")]),
            outputSchema: json["outputSchema"],
            annotations: json["annotations"],
            metadata: json["_meta"]
        )
    }
}

public struct MCPListToolsResult: Equatable, Hashable, Sendable {
    public var tools: [MCPToolDefinition]
    public var nextCursor: String?
    public var rawValue: JSONValue

    public init(tools: [MCPToolDefinition], nextCursor: String? = nil, rawValue: JSONValue? = nil) {
        self.tools = tools
        self.nextCursor = nextCursor
        self.rawValue = rawValue ?? .object([
            "tools": .array(tools.map(\.jsonValue)),
            "nextCursor": nextCursor.map(JSONValue.string)
        ])
    }

    init(json: JSONValue) throws {
        guard let toolValues = json["tools"]?.arrayValue else {
            throw MCPClientError(message: "Expected MCP tools/list result with tools array.")
        }
        self.init(
            tools: try toolValues.map(MCPToolDefinition.init(json:)),
            nextCursor: json["nextCursor"]?.stringValue,
            rawValue: json
        )
    }
}

public struct MCPCallToolResult: Equatable, Hashable, Sendable {
    public var content: [JSONValue]
    public var structuredContent: JSONValue?
    public var toolResult: JSONValue?
    public var isError: Bool
    public var rawValue: JSONValue

    public init(
        content: [JSONValue] = [],
        structuredContent: JSONValue? = nil,
        toolResult: JSONValue? = nil,
        isError: Bool = false,
        rawValue: JSONValue? = nil
    ) {
        self.content = content
        self.structuredContent = structuredContent
        self.toolResult = toolResult
        self.isError = isError
        self.rawValue = rawValue ?? .object([
            "content": .array(content),
            "structuredContent": structuredContent,
            "toolResult": toolResult,
            "isError": .bool(isError)
        ])
    }

    init(json: JSONValue) {
        self.init(
            content: json["content"]?.arrayValue ?? [],
            structuredContent: json["structuredContent"],
            toolResult: json["toolResult"],
            isError: json["isError"]?.boolValue ?? false,
            rawValue: json
        )
    }
}

public protocol MCPTransport: Sendable {
    func start() async throws
    func request(_ message: JSONValue) async throws -> JSONValue
    func notify(_ message: JSONValue) async throws
    func close() async throws
}

public final class MCPHTTPTransport: MCPTransport, @unchecked Sendable {
    private let url: URL
    private let headers: [String: String]
    private let transport: any AITransport

    public init(url: URL, headers: [String: String] = [:], transport: any AITransport = URLSessionTransport.shared) {
        self.url = url
        self.headers = headers
        self.transport = transport
    }

    public convenience init(url: String, headers: [String: String] = [:], transport: any AITransport = URLSessionTransport.shared) throws {
        try self.init(url: requireURL(url), headers: headers, transport: transport)
    }

    public func start() async throws {}

    public func request(_ message: JSONValue) async throws -> JSONValue {
        try await send(message)
    }

    public func notify(_ message: JSONValue) async throws {
        try await sendNotification(message)
    }

    public func close() async throws {}

    private func send(_ message: JSONValue) async throws -> JSONValue {
        let response = try await sendRaw(message)
        return try response.jsonValue()
    }

    private func sendNotification(_ message: JSONValue) async throws {
        _ = try await sendRaw(message)
    }

    private func sendRaw(_ message: JSONValue) async throws -> AIHTTPResponse {
        var requestHeaders = [
            "content-type": "application/json",
            "accept": "application/json"
        ]
        requestHeaders.merge(headers) { _, new in new }
        let response = try await transport.send(AIHTTPRequest(
            method: "POST",
            url: url,
            headers: requestHeaders,
            body: try encodeJSONBody(message)
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw MCPClientError(message: "HTTP \(response.statusCode): \(response.bodyText)")
        }
        return response
    }
}

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

    private let transport: any MCPTransport
    private let clientInfo: MCPImplementation
    private let clientCapabilities: JSONValue
    private var requestID = 0
    private var isClosed = true

    private init(
        transport: any MCPTransport,
        clientName: String,
        clientVersion: String,
        clientCapabilities: JSONValue
    ) {
        self.transport = transport
        self.clientInfo = MCPImplementation(name: clientName, version: clientVersion)
        self.clientCapabilities = clientCapabilities
    }

    public static func connect(
        transport: any MCPTransport,
        clientName: String = "swift-ai-sdk-mcp-client",
        clientVersion: String = "1.0.0",
        clientCapabilities: JSONValue = .object([:])
    ) async throws -> MCPClient {
        let client = MCPClient(
            transport: transport,
            clientName: clientName,
            clientVersion: clientVersion,
            clientCapabilities: clientCapabilities
        )
        try await client.initialize()
        return client
    }

    public func close() async throws {
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

    public func callTool(name: String, arguments: JSONValue = .object([:])) async throws -> MCPCallToolResult {
        try assertCapability("tools", method: "tools/call")
        let result = try await request(
            method: "tools/call",
            params: .object([
                "name": .string(name),
                "arguments": arguments
            ])
        )
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

    private func initialize() async throws {
        do {
            try await transport.start()
            isClosed = false

            let result = try await request(
                method: "initialize",
                params: .object([
                    "protocolVersion": .string(Self.latestProtocolVersion),
                    "capabilities": clientCapabilities,
                    "clientInfo": clientInfo.jsonValue
                ]),
                skipCapabilityCheck: true
            )
            guard let protocolVersion = result["protocolVersion"]?.stringValue else {
                throw MCPClientError(message: "Server sent invalid initialize result.")
            }
            guard Self.supportedProtocolVersions.contains(protocolVersion) else {
                throw MCPClientError(message: "Server protocol version is not supported: \(protocolVersion)")
            }
            serverCapabilities = result["capabilities"] ?? .object([:])
            serverInfo = try MCPImplementation(json: result["serverInfo"] ?? .object([:]))
            instructions = result["instructions"]?.stringValue

            try await notify(method: "notifications/initialized")
        } catch {
            try? await close()
            throw error
        }
    }

    private func request(method: String, params: JSONValue? = nil, skipCapabilityCheck: Bool = false) async throws -> JSONValue {
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
        let response = try await transport.request(message)
        return try result(from: response, expectedID: id)
    }

    private func notify(method: String, params: JSONValue? = nil) async throws {
        let message = JSONValue.object([
            "jsonrpc": .string("2.0"),
            "method": .string(method),
            "params": params
        ])
        try await transport.notify(message)
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
        return method
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
            providerMetadata: ["mcp": .object(metadata)]
        ) { [weak self] arguments in
            guard let self else {
                throw MCPClientError(message: "MCP client has been released.")
            }
            return try await self.callTool(name: definition.name, arguments: arguments).rawValue
        }
    }
}

private extension MCPToolDefinition {
    var jsonValue: JSONValue {
        .object([
            "name": .string(name),
            "title": title.map(JSONValue.string),
            "description": description.map(JSONValue.string),
            "inputSchema": inputSchema,
            "outputSchema": outputSchema,
            "annotations": annotations,
            "_meta": metadata
        ])
    }
}
