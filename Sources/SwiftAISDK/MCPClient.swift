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

public struct MCPResource: Equatable, Hashable, Sendable {
    public var uri: String
    public var name: String
    public var title: String?
    public var description: String?
    public var mimeType: String?
    public var size: Int?
    public var rawValue: JSONValue

    public init(uri: String, name: String, title: String? = nil, description: String? = nil, mimeType: String? = nil, size: Int? = nil, rawValue: JSONValue? = nil) {
        self.uri = uri
        self.name = name
        self.title = title
        self.description = description
        self.mimeType = mimeType
        self.size = size
        self.rawValue = rawValue ?? .object([
            "uri": .string(uri),
            "name": .string(name),
            "title": title.map(JSONValue.string),
            "description": description.map(JSONValue.string),
            "mimeType": mimeType.map(JSONValue.string),
            "size": size.map { .number(Double($0)) }
        ])
    }

    init(json: JSONValue) throws {
        guard let uri = json["uri"]?.stringValue, let name = json["name"]?.stringValue else {
            throw MCPClientError(message: "Expected MCP resource with uri and name.")
        }
        self.init(
            uri: uri,
            name: name,
            title: json["title"]?.stringValue,
            description: json["description"]?.stringValue,
            mimeType: json["mimeType"]?.stringValue,
            size: json["size"]?.intValue,
            rawValue: json
        )
    }
}

public struct MCPListResourcesResult: Equatable, Hashable, Sendable {
    public var resources: [MCPResource]
    public var nextCursor: String?
    public var rawValue: JSONValue

    public init(resources: [MCPResource], nextCursor: String? = nil, rawValue: JSONValue? = nil) {
        self.resources = resources
        self.nextCursor = nextCursor
        self.rawValue = rawValue ?? .object([
            "resources": .array(resources.map(\.rawValue)),
            "nextCursor": nextCursor.map(JSONValue.string)
        ])
    }

    init(json: JSONValue) throws {
        guard let values = json["resources"]?.arrayValue else {
            throw MCPClientError(message: "Expected MCP resources/list result with resources array.")
        }
        self.init(
            resources: try values.map(MCPResource.init(json:)),
            nextCursor: json["nextCursor"]?.stringValue,
            rawValue: json
        )
    }
}

public struct MCPResourceContent: Equatable, Hashable, Sendable {
    public var uri: String
    public var mimeType: String?
    public var text: String?
    public var blob: String?
    public var rawValue: JSONValue

    public init(uri: String, mimeType: String? = nil, text: String? = nil, blob: String? = nil, rawValue: JSONValue? = nil) {
        self.uri = uri
        self.mimeType = mimeType
        self.text = text
        self.blob = blob
        self.rawValue = rawValue ?? .object([
            "uri": .string(uri),
            "mimeType": mimeType.map(JSONValue.string),
            "text": text.map(JSONValue.string),
            "blob": blob.map(JSONValue.string)
        ])
    }

    init(json: JSONValue) throws {
        guard let uri = json["uri"]?.stringValue else {
            throw MCPClientError(message: "Expected MCP resource content with uri.")
        }
        self.init(
            uri: uri,
            mimeType: json["mimeType"]?.stringValue,
            text: json["text"]?.stringValue,
            blob: json["blob"]?.stringValue,
            rawValue: json
        )
    }
}

public struct MCPReadResourceResult: Equatable, Hashable, Sendable {
    public var contents: [MCPResourceContent]
    public var rawValue: JSONValue

    public init(contents: [MCPResourceContent], rawValue: JSONValue? = nil) {
        self.contents = contents
        self.rawValue = rawValue ?? .object(["contents": .array(contents.map(\.rawValue))])
    }

    init(json: JSONValue) throws {
        guard let values = json["contents"]?.arrayValue else {
            throw MCPClientError(message: "Expected MCP resources/read result with contents array.")
        }
        self.init(contents: try values.map(MCPResourceContent.init(json:)), rawValue: json)
    }
}

public struct MCPResourceTemplate: Equatable, Hashable, Sendable {
    public var uriTemplate: String
    public var name: String
    public var title: String?
    public var description: String?
    public var mimeType: String?
    public var rawValue: JSONValue

    public init(uriTemplate: String, name: String, title: String? = nil, description: String? = nil, mimeType: String? = nil, rawValue: JSONValue? = nil) {
        self.uriTemplate = uriTemplate
        self.name = name
        self.title = title
        self.description = description
        self.mimeType = mimeType
        self.rawValue = rawValue ?? .object([
            "uriTemplate": .string(uriTemplate),
            "name": .string(name),
            "title": title.map(JSONValue.string),
            "description": description.map(JSONValue.string),
            "mimeType": mimeType.map(JSONValue.string)
        ])
    }

    init(json: JSONValue) throws {
        guard let uriTemplate = json["uriTemplate"]?.stringValue, let name = json["name"]?.stringValue else {
            throw MCPClientError(message: "Expected MCP resource template with uriTemplate and name.")
        }
        self.init(
            uriTemplate: uriTemplate,
            name: name,
            title: json["title"]?.stringValue,
            description: json["description"]?.stringValue,
            mimeType: json["mimeType"]?.stringValue,
            rawValue: json
        )
    }
}

public struct MCPListResourceTemplatesResult: Equatable, Hashable, Sendable {
    public var resourceTemplates: [MCPResourceTemplate]
    public var rawValue: JSONValue

    public init(resourceTemplates: [MCPResourceTemplate], rawValue: JSONValue? = nil) {
        self.resourceTemplates = resourceTemplates
        self.rawValue = rawValue ?? .object(["resourceTemplates": .array(resourceTemplates.map(\.rawValue))])
    }

    init(json: JSONValue) throws {
        guard let values = json["resourceTemplates"]?.arrayValue else {
            throw MCPClientError(message: "Expected MCP resources/templates/list result with resourceTemplates array.")
        }
        self.init(resourceTemplates: try values.map(MCPResourceTemplate.init(json:)), rawValue: json)
    }
}

public struct MCPPromptArgument: Equatable, Hashable, Sendable {
    public var name: String
    public var description: String?
    public var required: Bool?
    public var rawValue: JSONValue

    public init(name: String, description: String? = nil, required: Bool? = nil, rawValue: JSONValue? = nil) {
        self.name = name
        self.description = description
        self.required = required
        self.rawValue = rawValue ?? .object([
            "name": .string(name),
            "description": description.map(JSONValue.string),
            "required": required.map(JSONValue.bool)
        ])
    }

    init(json: JSONValue) throws {
        guard let name = json["name"]?.stringValue else {
            throw MCPClientError(message: "Expected MCP prompt argument with name.")
        }
        self.init(
            name: name,
            description: json["description"]?.stringValue,
            required: json["required"]?.boolValue,
            rawValue: json
        )
    }
}

public struct MCPPrompt: Equatable, Hashable, Sendable {
    public var name: String
    public var title: String?
    public var description: String?
    public var arguments: [MCPPromptArgument]
    public var rawValue: JSONValue

    public init(name: String, title: String? = nil, description: String? = nil, arguments: [MCPPromptArgument] = [], rawValue: JSONValue? = nil) {
        self.name = name
        self.title = title
        self.description = description
        self.arguments = arguments
        self.rawValue = rawValue ?? .object([
            "name": .string(name),
            "title": title.map(JSONValue.string),
            "description": description.map(JSONValue.string),
            "arguments": .array(arguments.map(\.rawValue))
        ])
    }

    init(json: JSONValue) throws {
        guard let name = json["name"]?.stringValue else {
            throw MCPClientError(message: "Expected MCP prompt with name.")
        }
        self.init(
            name: name,
            title: json["title"]?.stringValue,
            description: json["description"]?.stringValue,
            arguments: try (json["arguments"]?.arrayValue ?? []).map(MCPPromptArgument.init(json:)),
            rawValue: json
        )
    }
}

public struct MCPListPromptsResult: Equatable, Hashable, Sendable {
    public var prompts: [MCPPrompt]
    public var nextCursor: String?
    public var rawValue: JSONValue

    public init(prompts: [MCPPrompt], nextCursor: String? = nil, rawValue: JSONValue? = nil) {
        self.prompts = prompts
        self.nextCursor = nextCursor
        self.rawValue = rawValue ?? .object([
            "prompts": .array(prompts.map(\.rawValue)),
            "nextCursor": nextCursor.map(JSONValue.string)
        ])
    }

    init(json: JSONValue) throws {
        guard let values = json["prompts"]?.arrayValue else {
            throw MCPClientError(message: "Expected MCP prompts/list result with prompts array.")
        }
        self.init(
            prompts: try values.map(MCPPrompt.init(json:)),
            nextCursor: json["nextCursor"]?.stringValue,
            rawValue: json
        )
    }
}

public struct MCPPromptMessage: Equatable, Hashable, Sendable {
    public var role: String
    public var content: JSONValue
    public var rawValue: JSONValue

    public init(role: String, content: JSONValue, rawValue: JSONValue? = nil) {
        self.role = role
        self.content = content
        self.rawValue = rawValue ?? .object([
            "role": .string(role),
            "content": content
        ])
    }

    init(json: JSONValue) throws {
        guard let role = json["role"]?.stringValue, let content = json["content"] else {
            throw MCPClientError(message: "Expected MCP prompt message with role and content.")
        }
        self.init(role: role, content: content, rawValue: json)
    }
}

public struct MCPGetPromptResult: Equatable, Hashable, Sendable {
    public var description: String?
    public var messages: [MCPPromptMessage]
    public var rawValue: JSONValue

    public init(description: String? = nil, messages: [MCPPromptMessage], rawValue: JSONValue? = nil) {
        self.description = description
        self.messages = messages
        self.rawValue = rawValue ?? .object([
            "description": description.map(JSONValue.string),
            "messages": .array(messages.map(\.rawValue))
        ])
    }

    init(json: JSONValue) throws {
        guard let values = json["messages"]?.arrayValue else {
            throw MCPClientError(message: "Expected MCP prompts/get result with messages array.")
        }
        self.init(
            description: json["description"]?.stringValue,
            messages: try values.map(MCPPromptMessage.init(json:)),
            rawValue: json
        )
    }
}

public struct MCPElicitationRequest: Equatable, Hashable, Sendable {
    public var message: String
    public var requestedSchema: JSONValue
    public var metadata: JSONValue?
    public var rawValue: JSONValue

    public init(message: String, requestedSchema: JSONValue, metadata: JSONValue? = nil, rawValue: JSONValue? = nil) {
        self.message = message
        self.requestedSchema = requestedSchema
        self.metadata = metadata
        self.rawValue = rawValue ?? .object([
            "message": .string(message),
            "requestedSchema": requestedSchema,
            "_meta": metadata
        ])
    }

    init(params: JSONValue) throws {
        guard let message = params["message"]?.stringValue, let requestedSchema = params["requestedSchema"] else {
            throw MCPClientError(message: "Expected MCP elicitation request with message and requestedSchema.")
        }
        self.init(
            message: message,
            requestedSchema: requestedSchema,
            metadata: params["_meta"],
            rawValue: params
        )
    }
}

public enum MCPElicitAction: String, Sendable {
    case accept
    case decline
    case cancel
}

public struct MCPElicitResult: Equatable, Hashable, Sendable {
    public var action: MCPElicitAction
    public var content: [String: JSONValue]?
    public var rawValue: JSONValue

    public init(action: MCPElicitAction, content: [String: JSONValue]? = nil, rawValue: JSONValue? = nil) {
        self.action = action
        self.content = content
        self.rawValue = rawValue ?? .object([
            "action": .string(action.rawValue),
            "content": content.map(JSONValue.object)
        ])
    }
}

public typealias MCPElicitationHandler = @Sendable (MCPElicitationRequest) async throws -> MCPElicitResult

public protocol MCPTransport: Sendable {
    func setRequestHandler(_ handler: (@Sendable (JSONValue) async -> JSONValue)?) async
    func start() async throws
    func request(_ message: JSONValue) async throws -> JSONValue
    func notify(_ message: JSONValue) async throws
    func close() async throws
}

public extension MCPTransport {
    func setRequestHandler(_ handler: (@Sendable (JSONValue) async -> JSONValue)?) async {}
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
    private var elicitationRequestHandler: MCPElicitationHandler?

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

    public func listResources(cursor: String? = nil) async throws -> MCPListResourcesResult {
        let result = try await request(
            method: "resources/list",
            params: cursor.map { .object(["cursor": .string($0)]) }
        )
        return try MCPListResourcesResult(json: result)
    }

    public func readResource(uri: String) async throws -> MCPReadResourceResult {
        let result = try await request(
            method: "resources/read",
            params: .object(["uri": .string(uri)])
        )
        return try MCPReadResourceResult(json: result)
    }

    public func listResourceTemplates() async throws -> MCPListResourceTemplatesResult {
        let result = try await request(method: "resources/templates/list")
        return try MCPListResourceTemplatesResult(json: result)
    }

    public func experimentalListPrompts(cursor: String? = nil) async throws -> MCPListPromptsResult {
        let result = try await request(
            method: "prompts/list",
            params: cursor.map { .object(["cursor": .string($0)]) }
        )
        return try MCPListPromptsResult(json: result)
    }

    public func experimentalGetPrompt(name: String, arguments: JSONValue = .object([:])) async throws -> MCPGetPromptResult {
        let result = try await request(
            method: "prompts/get",
            params: .object([
                "name": .string(name),
                "arguments": arguments
            ])
        )
        return try MCPGetPromptResult(json: result)
    }

    public func onElicitationRequest(_ handler: MCPElicitationHandler?) {
        elicitationRequestHandler = handler
    }

    private func initialize() async throws {
        do {
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
            providerMetadata: ["mcp": .object(metadata)],
            toModelOutput: { context in
                mcpToolModelOutput(from: context.output)
            }
        ) { [weak self] arguments in
            guard let self else {
                throw MCPClientError(message: "MCP client has been released.")
            }
            return try await self.callTool(name: definition.name, arguments: arguments).rawValue
        }
    }
}

private func mcpToolModelOutput(from result: JSONValue) -> JSONValue {
    guard let content = result["content"]?.arrayValue else {
        return .object([
            "type": .string("json"),
            "value": result
        ])
    }

    return .object([
        "type": .string("content"),
        "value": .array(content.map(mcpToolModelOutputPart))
    ])
}

private func mcpToolModelOutputPart(_ part: JSONValue) -> JSONValue {
    if part["type"]?.stringValue == "text", let text = part["text"]?.stringValue {
        return .object([
            "type": .string("text"),
            "text": .string(text)
        ])
    }
    if part["type"]?.stringValue == "image",
       let data = part["data"]?.stringValue,
       let mimeType = part["mimeType"]?.stringValue {
        return .object([
            "type": .string("file"),
            "mediaType": .string(mimeType),
            "data": .object([
                "type": .string("data"),
                "data": .string(data)
            ])
        ])
    }
    return .object([
        "type": .string("text"),
        "text": .string(mcpJSONString(part) ?? "")
    ])
}

private func mcpJSONString(_ value: JSONValue) -> String? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

private func mcpJSONRPCResultResponse(id: JSONValue?, result: JSONValue) -> JSONValue {
    .object([
        "jsonrpc": .string("2.0"),
        "id": id,
        "result": result
    ])
}

private func mcpJSONRPCErrorResponse(id: JSONValue?, code: Int, message: String, data: JSONValue? = nil) -> JSONValue {
    .object([
        "jsonrpc": .string("2.0"),
        "id": id,
        "error": .object([
            "code": .number(Double(code)),
            "message": .string(message),
            "data": data
        ])
    ])
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
