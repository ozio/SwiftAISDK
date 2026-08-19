import Foundation
import Testing
@testable import SwiftAISDK

private enum MCP2026DiscoveryBehavior: Sendable {
    case modern
    case legacy
    case unsupported
}

private actor MCP2026TestTransport: MCPTransport {
    nonisolated let supportsProtocolVersionDiscovery = true
    nonisolated let supportsMCPToolParameterHeaders = true

    private let discoveryBehavior: MCP2026DiscoveryBehavior
    private let toolListResultType: String?
    private let toolDefinitions: [JSONValue]
    private var messages: [JSONValue] = []
    private var protocolVersions: [String?] = []
    private var transportHeadersByMethod: [String: [String: String]] = [:]

    init(
        discoveryBehavior: MCP2026DiscoveryBehavior = .modern,
        toolListResultType: String? = "complete",
        toolDefinitions: [JSONValue] = []
    ) {
        self.discoveryBehavior = discoveryBehavior
        self.toolListResultType = toolListResultType
        self.toolDefinitions = toolDefinitions
    }

    func setProtocolVersion(_ protocolVersion: String?) async {
        protocolVersions.append(protocolVersion)
    }

    func start() async throws {}

    func request(_ message: JSONValue) async throws -> JSONValue {
        try await request(message, options: nil)
    }

    func request(_ message: JSONValue, options: MCPRequestOptions?) async throws -> JSONValue {
        messages.append(message)
        let id = message["id"] ?? .number(0)
        let method = message["method"]?.stringValue ?? ""
        if let headers = options?.transportHeaders {
            transportHeadersByMethod[method] = headers
        }

        switch method {
        case "server/discover":
            switch discoveryBehavior {
            case .modern:
                return [
                    "jsonrpc": "2.0",
                    "id": id,
                    "result": [
                        "resultType": "complete",
                        "supportedVersions": [.string(MCPClient.latestProtocolVersion)],
                        "capabilities": ["tools": [:]],
                        "instructions": "Use the stateless protocol.",
                        "_meta": [
                            "io.modelcontextprotocol/serverInfo": [
                                "name": "modern-test-server",
                                "version": "1.0.0"
                            ]
                        ]
                    ]
                ]
            case .legacy:
                return [
                    "jsonrpc": "2.0",
                    "id": id,
                    "error": [
                        "code": -32601,
                        "message": "Method not found"
                    ]
                ]
            case .unsupported:
                return [
                    "jsonrpc": "2.0",
                    "id": id,
                    "error": [
                        "code": -32022,
                        "message": "Unsupported protocol version",
                        "data": [
                            "requested": .string(MCPClient.latestProtocolVersion),
                            "supported": ["2099-01-01"]
                        ]
                    ]
                ]
            }
        case "initialize":
            return [
                "jsonrpc": "2.0",
                "id": id,
                "result": [
                    "protocolVersion": .string(MCPClient.latestLegacyProtocolVersion),
                    "capabilities": ["tools": [:]],
                    "serverInfo": [
                        "name": "legacy-test-server",
                        "version": "1.0.0"
                    ]
                ]
            ]
        case "tools/list":
            var result: [String: JSONValue] = [
                "tools": .array(toolDefinitions),
                "_meta": ["trace": "modern-list"]
            ]
            if let toolListResultType {
                result["resultType"] = .string(toolListResultType)
            }
            return [
                "jsonrpc": "2.0",
                "id": id,
                "result": .object(result)
            ]
        case "tools/call":
            return [
                "jsonrpc": "2.0",
                "id": id,
                "result": [
                    "resultType": "complete",
                    "content": [["type": "text", "text": "ok"]],
                    "_meta": ["trace": "modern-call"]
                ]
            ]
        default:
            return [
                "jsonrpc": "2.0",
                "id": id,
                "error": ["code": -32601, "message": "Unknown method"]
            ]
        }
    }

    func notify(_ message: JSONValue) async throws {
        messages.append(message)
    }

    func close() async throws {}

    func sentMessages() -> [JSONValue] {
        messages
    }

    func versions() -> [String?] {
        protocolVersions
    }

    func headers(for method: String) -> [String: String]? {
        transportHeadersByMethod[method]
    }
}

private final class MCP2026ErrorRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []

    func record(_ error: any Error) {
        lock.lock()
        if let error = error as? MCPClientError {
            messages.append(error.message)
        } else {
            messages.append(String(describing: error))
        }
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }
}

@Test func mcpModernDiscoveryAddsRequestMetadataAndTypedResultFields() async throws {
    let transport = MCP2026TestTransport()
    let client = try await MCPClient.connect(
        transport: transport,
        clientName: "swift-modern-client",
        clientVersion: "2.0.33"
    )

    let result = try await client.listTools()

    #expect(await client.serverInfo == MCPImplementation(name: "modern-test-server", version: "1.0.0"))
    #expect(await client.instructions == "Use the stateless protocol.")
    #expect(result.resultType == "complete")
    #expect(result.metadata?["trace"]?.stringValue == "modern-list")
    #expect((await transport.versions()).last == MCPClient.latestProtocolVersion)

    let messages = await transport.sentMessages()
    #expect(messages.compactMap { $0["method"]?.stringValue } == ["server/discover", "tools/list"])
    for message in messages where message["id"] != nil {
        let metadata = message["params"]?["_meta"]
        #expect(metadata?["io.modelcontextprotocol/protocolVersion"]?.stringValue == MCPClient.latestProtocolVersion)
        #expect(metadata?["io.modelcontextprotocol/clientCapabilities"]?.objectValue?.isEmpty == true)
        #expect(metadata?["io.modelcontextprotocol/clientInfo"]?["name"]?.stringValue == "swift-modern-client")
        #expect(metadata?["io.modelcontextprotocol/clientInfo"]?["version"]?.stringValue == "2.0.33")
    }

    try await client.close()
}

@Test func mcpModernDiscoveryFallsBackToLegacyInitialization() async throws {
    let transport = MCP2026TestTransport(discoveryBehavior: .legacy)
    let client = try await MCPClient.connect(transport: transport)
    _ = try await client.listTools()

    let messages = await transport.sentMessages()
    #expect(messages.compactMap { $0["method"]?.stringValue } == [
        "server/discover",
        "initialize",
        "notifications/initialized",
        "tools/list"
    ])
    #expect(messages[0]["params"]?["_meta"]?["io.modelcontextprotocol/protocolVersion"]?.stringValue == MCPClient.latestProtocolVersion)
    #expect(messages[1]["params"]?["_meta"] == nil)
    #expect(messages[3]["params"]?["_meta"] == nil)
    #expect((await transport.versions()).last == MCPClient.latestLegacyProtocolVersion)

    try await client.close()
}

@Test func mcpModernDiscoveryDoesNotFallbackForRecognizedProtocolErrors() async throws {
    let transport = MCP2026TestTransport(discoveryBehavior: .unsupported)

    do {
        _ = try await MCPClient.connect(transport: transport)
        Issue.record("Expected the modern protocol error to propagate.")
    } catch let error as MCPClientError {
        #expect(error.code == -32022)
        #expect(error.data?["requested"]?.stringValue == MCPClient.latestProtocolVersion)
        #expect(error.data?["supported"]?[0]?.stringValue == "2099-01-01")
    }

    #expect((await transport.sentMessages()).compactMap { $0["method"]?.stringValue } == ["server/discover"])
}

@Test func mcpModernResultsRequireCompleteResultType() async throws {
    let missingTransport = MCP2026TestTransport(toolListResultType: nil)
    let missingClient = try await MCPClient.connect(transport: missingTransport)
    do {
        _ = try await missingClient.listTools()
        Issue.record("Expected a missing modern resultType to throw.")
    } catch let error as MCPClientError {
        #expect(error.message == "Modern MCP result is missing resultType")
    }
    try await missingClient.close()

    let inputTransport = MCP2026TestTransport(toolListResultType: "input_required")
    let inputClient = try await MCPClient.connect(transport: inputTransport)
    do {
        _ = try await inputClient.listTools()
        Issue.record("Expected input_required to throw.")
    } catch let error as MCPClientError {
        #expect(error.message.contains("multi round-trip requests are not supported"))
    }
    try await inputClient.close()
}

@Test func mcpModernToolHeaderBindingsFilterInvalidToolsAndReachTransport() async throws {
    let validTool: JSONValue = [
        "name": "header-tool",
        "inputSchema": [
            "type": "object",
            "properties": [
                "region": ["type": "string", "x-mcp-header": "Region"],
                "count": ["type": "integer", "x-mcp-header": "Count"],
                "options": [
                    "type": "object",
                    "properties": [
                        "enabled": ["type": "boolean", "x-mcp-header": "Enabled"]
                    ]
                ]
            ]
        ]
    ]
    let invalidTool: JSONValue = [
        "name": "dynamic-header-tool",
        "inputSchema": [
            "type": "object",
            "additionalProperties": [
                "type": "string",
                "x-mcp-header": "Dynamic"
            ]
        ]
    ]
    let transport = MCP2026TestTransport(toolDefinitions: [validTool, invalidTool])
    let errors = MCP2026ErrorRecorder()
    let client = try await MCPClient.connect(
        transport: transport,
        onUncaughtError: { errors.record($0) }
    )

    let tools = try await client.listTools()
    #expect(tools.tools.map(\.name) == ["header-tool"])
    #expect(errors.snapshot().first?.contains("Ignoring MCP tool \"dynamic-header-tool\"") == true)

    let result = try await client.callTool(
        name: "header-tool",
        arguments: [
            "region": "Hello, 世界",
            "count": 42,
            "options": ["enabled": false]
        ]
    )
    #expect(result.resultType == "complete")
    #expect(result.metadata?["trace"]?.stringValue == "modern-call")
    let headers = try #require(await transport.headers(for: "tools/call"))
    #expect(headers["Mcp-Param-Region"] == "=?base64?SGVsbG8sIOS4lueVjA==?=")
    #expect(headers["Mcp-Param-Count"] == "42")
    #expect(headers["Mcp-Param-Enabled"] == "false")

    try await client.close()
}

@Test func mcpHTTPHeaderBindingsRejectUnsafeSchemasAndEncodeValues() throws {
    let duplicateSchema: JSONValue = [
        "type": "object",
        "properties": [
            "first": ["type": "string", "x-mcp-header": "Region"],
            "second": ["type": "string", "x-mcp-header": "region"]
        ]
    ]
    switch mcpToolHeaderBindings(from: duplicateSchema) {
    case .success:
        Issue.record("Expected duplicate x-mcp-header values to be rejected.")
    case let .failure(error):
        #expect(error.contains("is not unique"))
    }

    #expect(encodeMCPHeaderValue("plain-ascii") == "plain-ascii")
    #expect(encodeMCPHeaderValue(" padded ") == "=?base64?IHBhZGRlZCA=?=")
    #expect(encodeMCPHeaderValue("=?base64?literal?=") == "=?base64?PT9iYXNlNjQ/bGl0ZXJhbD89?=")
}

@Test func mcpModernHTTPTransportIsStatelessAndAddsStandardHeaders() async throws {
    let sessions = MCPSessionRecorder()
    let http = RecordingTransport(response: jsonResponse(
        #"{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete","contents":[]}}"#,
        headers: ["mcp-session-id": "server-session"]
    ))
    let transport = try MCPHTTPTransport(
        url: "https://mcp.example.com/rpc",
        transport: http,
        initialSessionID: "saved-legacy-session",
        initialProtocolVersion: MCPClient.latestProtocolVersion,
        onSessionIDChange: { sessionID in
            Task { await sessions.recordChange(sessionID) }
        },
        onSessionExpired: { sessionID in
            Task { await sessions.recordExpiration(sessionID) }
        }
    )

    try await transport.start()
    _ = try await transport.request(
        [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "resources/read",
            "params": ["uri": "file:///資料/intro.md"]
        ],
        options: MCPRequestOptions(
            abortSignal: nil,
            transportHeaders: ["Mcp-Param-Region": "ap-northeast-1"]
        )
    )
    try await transport.close()

    let requests = await http.requests()
    #expect(requests.count == 1)
    #expect(requests[0].method == "POST")
    #expect(requests[0].headers["mcp-protocol-version"] == MCPClient.latestProtocolVersion)
    #expect(requests[0].headers["mcp-session-id"] == nil)
    #expect(requests[0].headers["Mcp-Method"] == "resources/read")
    #expect(requests[0].headers["Mcp-Name"] == encodeMCPHeaderValue("file:///資料/intro.md"))
    #expect(requests[0].headers["Mcp-Param-Region"] == "ap-northeast-1")
    #expect(await sessions.changedSessionIDs().isEmpty)
    #expect(await sessions.expiredSessionIDs().isEmpty)
}
