import Foundation
import Testing
@testable import SwiftAISDK

@Test func mcpClientInitializesAndBuildsDynamicTools() async throws {
    let transport = MockMCPTransport()
    let client = try await MCPClient.connect(
        transport: transport,
        clientName: "TestMCPClient",
        clientVersion: "1.2.3"
    )

    #expect(await client.serverInfo == MCPImplementation(name: "mock-server", version: "0.1.0"))
    #expect(await client.instructions == "Use these mock tools carefully.")

    let tools = try await client.tools()
    let search = try #require(tools["search"])
    #expect(search.dynamic)
    #expect(search.name == "search")
    #expect(search.description == "Search documents")
    #expect(search.parameters["properties"]?["query"]?["type"]?.stringValue == "string")
    #expect(search.parameters["additionalProperties"]?.boolValue == false)
    #expect(search.providerMetadata["mcp"]?["clientName"]?.stringValue == "TestMCPClient")
    #expect(search.providerMetadata["mcp"]?["toolName"]?.stringValue == "search")
    #expect(search.providerMetadata["mcp"]?["title"]?.stringValue == "Search")

    let result = try await search.execute(["query": "swift"])
    #expect(result["content"]?[0]?["text"]?.stringValue == "Result for swift")
    #expect(result["isError"]?.boolValue == false)

    let sent = await transport.sentMessages()
    #expect(sent.map { $0["method"]?.stringValue } == [
        "initialize",
        "notifications/initialized",
        "tools/list",
        "tools/call"
    ])
    #expect(sent[0]["params"]?["clientInfo"]?["name"]?.stringValue == "TestMCPClient")
    #expect(sent[3]["params"]?["name"]?.stringValue == "search")
    #expect(sent[3]["params"]?["arguments"]?["query"]?.stringValue == "swift")
}

@Test func mcpClientCreatesToolsFromCachedDefinitionsWithoutListingAgain() async throws {
    let transport = MockMCPTransport()
    let client = try await MCPClient.connect(transport: transport)
    let definitions = try await client.listTools()
    await transport.reset()

    let tools = await client.toolsFromDefinitions(definitions)
    let search = try #require(tools["search"])
    _ = try await search.execute(["query": "cached"])

    let sent = await transport.sentMessages()
    #expect(sent.map { $0["method"]?.stringValue } == ["tools/call"])
}

@Test func mcpClientRejectsToolCallsWhenServerHasNoToolCapability() async throws {
    let transport = MockMCPTransport(capabilities: .object([:]))
    let client = try await MCPClient.connect(transport: transport)

    do {
        _ = try await client.listTools()
        Issue.record("Expected missing tool capability to throw.")
    } catch let error as MCPClientError {
        #expect(error.description.contains("does not support tools"))
    }
}

@Test func mcpHTTPTransportPostsJSONRPCMessages() async throws {
    let http = RecordingTransport(responses: [
        jsonResponse(#"{"jsonrpc":"2.0","id":7,"result":{"ok":true}}"#),
        AIHTTPResponse(statusCode: 202)
    ])
    let transport = try MCPHTTPTransport(url: "https://mcp.example.com/rpc", headers: ["authorization": "Bearer token"], transport: http)

    let response = try await transport.request([
        "jsonrpc": "2.0",
        "id": 7,
        "method": "ping"
    ])
    try await transport.notify([
        "jsonrpc": "2.0",
        "method": "notifications/initialized"
    ])

    #expect(response["result"]?["ok"]?.boolValue == true)
    let requests = await http.requests()
    let request = try #require(requests.first)
    #expect(request.method == "POST")
    #expect(request.url.absoluteString == "https://mcp.example.com/rpc")
    #expect(request.headers["authorization"] == "Bearer token")
    let body = try #require(request.body).jsonValueForTest()
    #expect(body["method"]?.stringValue == "ping")
    #expect(requests.count == 2)
}

private actor MockMCPTransport: MCPTransport {
    private var messages: [JSONValue] = []
    private let capabilities: JSONValue

    init(capabilities: JSONValue = .object(["tools": .object(["listChanged": .bool(false)])])) {
        self.capabilities = capabilities
    }

    func start() async throws {}

    func request(_ message: JSONValue) async throws -> JSONValue {
        messages.append(message)
        let id = message["id"] ?? .number(0)
        switch message["method"]?.stringValue {
        case "initialize":
            return [
                "jsonrpc": "2.0",
                "id": id,
                "result": [
                    "protocolVersion": .string(MCPClient.latestProtocolVersion),
                    "capabilities": capabilities,
                    "serverInfo": [
                        "name": "mock-server",
                        "version": "0.1.0"
                    ],
                    "instructions": "Use these mock tools carefully."
                ]
            ]
        case "tools/list":
            return [
                "jsonrpc": "2.0",
                "id": id,
                "result": [
                    "tools": [
                        [
                            "name": "search",
                            "title": "Search",
                            "description": "Search documents",
                            "inputSchema": [
                                "type": "object",
                                "properties": [
                                    "query": ["type": "string"]
                                ]
                            ],
                            "_meta": [
                                "source": "mock"
                            ]
                        ]
                    ]
                ]
            ]
        case "tools/call":
            let query = message["params"]?["arguments"]?["query"]?.stringValue ?? ""
            return [
                "jsonrpc": "2.0",
                "id": id,
                "result": [
                    "content": [
                        [
                            "type": "text",
                            "text": .string("Result for \(query)")
                        ]
                    ],
                    "isError": false
                ]
            ]
        default:
            return [
                "jsonrpc": "2.0",
                "id": id,
                "error": [
                    "code": -32601,
                    "message": "Unknown method"
                ]
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

    func reset() {
        messages = []
    }
}

private extension Data {
    func jsonValueForTest() throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: self)
    }
}
