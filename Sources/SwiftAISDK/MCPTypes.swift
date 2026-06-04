import Foundation

public struct MCPClientError: Error, CustomStringConvertible, Sendable {
    public var message: String
    public var code: Int?
    public var data: JSONValue?
    public var statusCode: Int?
    public var url: String?
    public var responseBody: String?

    public init(
        message: String,
        code: Int? = nil,
        data: JSONValue? = nil,
        statusCode: Int? = nil,
        url: String? = nil,
        responseBody: String? = nil
    ) {
        self.message = message
        self.code = code
        self.data = data
        self.statusCode = statusCode
        self.url = url
        self.responseBody = responseBody
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

public enum MCPOAuthCredentialScope: String, Sendable {
    case all
    case client
    case tokens
    case verifier
}

public protocol MCPOAuthProvider: Sendable {
    func accessToken() async throws -> String?
    func authorize(resourceMetadataURL: URL?) async throws -> Bool
    func invalidateCredentials(_ scope: MCPOAuthCredentialScope) async
}

public extension MCPOAuthProvider {
    func invalidateCredentials(_ scope: MCPOAuthCredentialScope) async {}
}

public protocol MCPTransport: Sendable {
    func setRequestHandler(_ handler: (@Sendable (JSONValue) async -> JSONValue)?) async
    func setProtocolVersion(_ protocolVersion: String?) async
    func start() async throws
    func request(_ message: JSONValue) async throws -> JSONValue
    func request(_ message: JSONValue, options: MCPRequestOptions?) async throws -> JSONValue
    func notify(_ message: JSONValue) async throws
    func close() async throws
}

public extension MCPTransport {
    func setRequestHandler(_ handler: (@Sendable (JSONValue) async -> JSONValue)?) async {}
    func setProtocolVersion(_ protocolVersion: String?) async {}
    func request(_ message: JSONValue, options: MCPRequestOptions?) async throws -> JSONValue {
        try options?.abortSignal?.throwIfAborted()
        return try await request(message)
    }
}

