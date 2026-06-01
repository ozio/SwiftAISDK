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
    let modelOutput = try await #require(search.toModelOutput?(
        AIToolModelOutputContext(toolCallID: "call-1", input: ["query": "swift"], output: result)
    ))
    #expect(modelOutput["type"]?.stringValue == "content")
    #expect(modelOutput["value"]?[0]?["type"]?.stringValue == "text")
    #expect(modelOutput["value"]?[0]?["text"]?.stringValue == "Result for swift")

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

@Test func mcpToolModelOutputConvertsImagesAndUnknownContent() async throws {
    let transport = MockMCPTransport(
        capabilities: fullMCPCapabilities(),
        toolResult: [
            "content": [
                [
                    "type": "image",
                    "data": "base64-image",
                    "mimeType": "image/png"
                ],
                [
                    "type": "custom",
                    "data": ["foo": "bar"]
                ]
            ]
        ]
    )
    let client = try await MCPClient.connect(transport: transport)
    let tool = try await #require(client.tools()["search"])
    let result = try await tool.execute(["query": "image"])

    let modelOutput = try await #require(tool.toModelOutput?(
        AIToolModelOutputContext(toolCallID: "call-1", input: ["query": "image"], output: result)
    ))
    #expect(modelOutput["type"]?.stringValue == "content")
    #expect(modelOutput["value"]?[0]?["type"]?.stringValue == "file")
    #expect(modelOutput["value"]?[0]?["mediaType"]?.stringValue == "image/png")
    #expect(modelOutput["value"]?[0]?["data"]?["type"]?.stringValue == "data")
    #expect(modelOutput["value"]?[0]?["data"]?["data"]?.stringValue == "base64-image")
    #expect(modelOutput["value"]?[1]?["type"]?.stringValue == "text")
    #expect(modelOutput["value"]?[1]?["text"]?.stringValue?.contains("\"custom\"") == true)
}

@Test func mcpToolModelOutputFallsBackToJSONForNonContentResults() async throws {
    let transport = MockMCPTransport(
        capabilities: fullMCPCapabilities(),
        toolResult: ["structuredContent": ["ok": true]]
    )
    let client = try await MCPClient.connect(transport: transport)
    let tool = try await #require(client.tools()["search"])
    let result = try await tool.execute(["query": "json"])

    let modelOutput = try await #require(tool.toModelOutput?(
        AIToolModelOutputContext(toolCallID: "call-1", input: ["query": "json"], output: result)
    ))
    #expect(modelOutput["type"]?.stringValue == "json")
    #expect(modelOutput["value"]?["structuredContent"]?["ok"]?.boolValue == true)
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

@Test func mcpClientListsReadsResourcesAndTemplates() async throws {
    let transport = MockMCPTransport(capabilities: fullMCPCapabilities())
    let client = try await MCPClient.connect(transport: transport)

    let resources = try await client.listResources(cursor: "cursor-1")
    #expect(resources.nextCursor == "cursor-2")
    #expect(resources.resources.first?.uri == "file:///docs/intro.md")
    #expect(resources.resources.first?.title == "Intro")
    #expect(resources.resources.first?.mimeType == "text/markdown")

    let content = try await client.readResource(uri: "file:///docs/intro.md")
    #expect(content.contents.first?.text == "# Intro")
    #expect(content.contents.first?.mimeType == "text/markdown")

    let templates = try await client.listResourceTemplates()
    #expect(templates.resourceTemplates.first?.uriTemplate == "file:///docs/{slug}.md")
    #expect(templates.resourceTemplates.first?.name == "doc")

    let sent = await transport.sentMessages()
    #expect(sent.map { $0["method"]?.stringValue } == [
        "initialize",
        "notifications/initialized",
        "resources/list",
        "resources/read",
        "resources/templates/list"
    ])
    #expect(sent[2]["params"]?["cursor"]?.stringValue == "cursor-1")
    #expect(sent[3]["params"]?["uri"]?.stringValue == "file:///docs/intro.md")
}

@Test func mcpClientListsAndGetsPrompts() async throws {
    let transport = MockMCPTransport(capabilities: fullMCPCapabilities())
    let client = try await MCPClient.connect(transport: transport)

    let prompts = try await client.experimentalListPrompts(cursor: "prompt-cursor")
    #expect(prompts.nextCursor == "prompt-cursor-2")
    #expect(prompts.prompts.first?.name == "summarize")
    #expect(prompts.prompts.first?.arguments.first?.name == "topic")
    #expect(prompts.prompts.first?.arguments.first?.required == true)

    let prompt = try await client.experimentalGetPrompt(name: "summarize", arguments: ["topic": "Swift"])
    #expect(prompt.description == "Summarize a topic.")
    #expect(prompt.messages.first?.role == "user")
    #expect(prompt.messages.first?.content["text"]?.stringValue == "Summarize Swift")

    let sent = await transport.sentMessages()
    #expect(sent.map { $0["method"]?.stringValue } == [
        "initialize",
        "notifications/initialized",
        "prompts/list",
        "prompts/get"
    ])
    #expect(sent[2]["params"]?["cursor"]?.stringValue == "prompt-cursor")
    #expect(sent[3]["params"]?["name"]?.stringValue == "summarize")
    #expect(sent[3]["params"]?["arguments"]?["topic"]?.stringValue == "Swift")
}

@Test func mcpClientHandlesElicitationRequests() async throws {
    let transport = MockMCPTransport(capabilities: fullMCPCapabilities())
    let client = try await MCPClient.connect(
        transport: transport,
        clientCapabilities: .object(["elicitation": .object(["applyDefaults": .bool(true)])])
    )
    let recorder = MCPElicitationRecorder()
    await client.onElicitationRequest { request in
        await recorder.record(request)
        return MCPElicitResult(
            action: .accept,
            content: ["city": .string("Tokyo"), "days": .number(3)]
        )
    }

    let response = await transport.simulateIncomingRequest([
        "jsonrpc": "2.0",
        "id": 99,
        "method": "elicitation/create",
        "params": [
            "message": "Choose travel settings.",
            "requestedSchema": [
                "type": "object",
                "properties": [
                    "city": ["type": "string"],
                    "days": ["type": "integer"]
                ],
                "required": ["city"]
            ],
            "_meta": ["trace": "elicitation"]
        ]
    ])

    let request = try await #require(recorder.request())
    #expect(request.message == "Choose travel settings.")
    #expect(request.requestedSchema["properties"]?["city"]?["type"]?.stringValue == "string")
    #expect(request.metadata?["trace"]?.stringValue == "elicitation")
    #expect(response["id"]?.intValue == 99)
    #expect(response["result"]?["action"]?.stringValue == "accept")
    #expect(response["result"]?["content"]?["city"]?.stringValue == "Tokyo")
    #expect(response["result"]?["content"]?["days"]?.intValue == 3)

    let sent = await transport.sentMessages()
    #expect(sent[0]["params"]?["capabilities"]?["elicitation"]?["applyDefaults"]?.boolValue == true)
}

@Test func mcpClientRejectsElicitationWithoutHandler() async throws {
    let transport = MockMCPTransport(capabilities: fullMCPCapabilities())
    let client = try await MCPClient.connect(
        transport: transport,
        clientCapabilities: .object(["elicitation": .object([:])])
    )
    _ = await client.serverInfo

    let response = await transport.simulateIncomingRequest([
        "jsonrpc": "2.0",
        "id": 7,
        "method": "elicitation/create",
        "params": [
            "message": "Need input.",
            "requestedSchema": ["type": "object"]
        ]
    ])

    #expect(response["error"]?["code"]?.intValue == -32601)
    #expect(response["error"]?["message"]?.stringValue == "No elicitation handler registered on client")
}

@Test func mcpClientHandlesPingAndUnsupportedIncomingRequests() async throws {
    let transport = MockMCPTransport(capabilities: fullMCPCapabilities())
    let client = try await MCPClient.connect(transport: transport)
    _ = await client.serverInfo

    let ping = await transport.simulateIncomingRequest([
        "jsonrpc": "2.0",
        "id": 1,
        "method": "ping"
    ])
    #expect(ping["result"]?.objectValue?.isEmpty == true)

    let unsupported = await transport.simulateIncomingRequest([
        "jsonrpc": "2.0",
        "id": 2,
        "method": "sampling/createMessage"
    ])
    #expect(unsupported["error"]?["code"]?.intValue == -32601)
    #expect(unsupported["error"]?["message"]?.stringValue == "Unsupported request method: sampling/createMessage")
}

@Test func mcpClientRejectsInvalidElicitationRequest() async throws {
    let transport = MockMCPTransport(capabilities: fullMCPCapabilities())
    let client = try await MCPClient.connect(
        transport: transport,
        clientCapabilities: .object(["elicitation": .object([:])])
    )
    await client.onElicitationRequest { _ in
        MCPElicitResult(action: .decline)
    }

    let response = await transport.simulateIncomingRequest([
        "jsonrpc": "2.0",
        "id": 8,
        "method": "elicitation/create",
        "params": [
            "requestedSchema": ["type": "object"]
        ]
    ])

    #expect(response["error"]?["code"]?.intValue == -32602)
    #expect(response["error"]?["message"]?.stringValue?.contains("message and requestedSchema") == true)
}

@Test func mcpClientRejectsResourcesWhenServerHasNoResourceCapability() async throws {
    let transport = MockMCPTransport(capabilities: .object(["tools": .object([:])]))
    let client = try await MCPClient.connect(transport: transport)

    do {
        _ = try await client.listResources()
        Issue.record("Expected missing resource capability to throw.")
    } catch let error as MCPClientError {
        #expect(error.description.contains("does not support resources"))
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
    #expect(request.headers["accept"] == "application/json, text/event-stream")
    #expect(request.headers["mcp-protocol-version"] == MCPClient.latestProtocolVersion)
    let body = try #require(request.body).jsonValueForTest()
    #expect(body["method"]?.stringValue == "ping")
    #expect(requests.count == 2)
}

@Test func mcpHTTPTransportParsesSSEResponsesAndTerminatesSession() async throws {
    let http = RecordingTransport(responses: [
        AIHTTPResponse(
            statusCode: 200,
            headers: [
                "content-type": "text/event-stream",
                "mcp-session-id": "session-1"
            ],
            body: Data("event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"ok\":true}}\n\n".utf8)
        ),
        AIHTTPResponse(statusCode: 200)
    ])
    let transport = try MCPHTTPTransport(url: "https://mcp.example.com/rpc", transport: http)

    let response = try await transport.request([
        "jsonrpc": "2.0",
        "id": 3,
        "method": "initialize",
        "params": [:]
    ])
    try await transport.close()

    #expect(response["result"]?["ok"]?.boolValue == true)
    let requests = await http.requests()
    #expect(requests.count == 2)
    #expect(requests[1].method == "DELETE")
    #expect(requests[1].headers["mcp-session-id"] == "session-1")
}

@Test func mcpHTTPTransportStartHandlesBufferedInboundSSERequests() async throws {
    let http = RecordingTransport(responses: [
        AIHTTPResponse(
            statusCode: 200,
            headers: ["content-type": "text/event-stream"],
            body: Data("event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"ping\"}\n\n".utf8)
        ),
        AIHTTPResponse(statusCode: 202)
    ])
    let transport = try MCPHTTPTransport(url: "https://mcp.example.com/rpc", transport: http)
    await transport.setRequestHandler { request in
        [
            "jsonrpc": "2.0",
            "id": request["id"] ?? .null,
            "result": [:]
        ]
    }

    try await transport.start()

    let requests = try await waitForRecordedRequests(http, count: 2)
    #expect(requests.count == 2)
    #expect(requests[0].method == "GET")
    #expect(requests[0].headers["accept"] == "text/event-stream")
    #expect(requests[1].method == "POST")
    let body = try #require(requests[1].body).jsonValueForTest()
    #expect(body["id"]?.intValue == 11)
    #expect(body["result"]?.objectValue?.isEmpty == true)
}

@Test func mcpHTTPTransportStreamsPOSTSSEResponseBeforeStreamEnds() async throws {
    let http = StreamingRecordingTransport(responses: [
        streamResponse(
            headers: ["content-type": "text/event-stream"],
            chunks: ["event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":4,\"result\":{\"ok\":true}}\n\n"],
            finishes: false
        )
    ])
    let transport = try MCPHTTPTransport(url: "https://mcp.example.com/rpc", transport: http)

    let response = try await transport.request([
        "jsonrpc": "2.0",
        "id": 4,
        "method": "initialize",
        "params": [:]
    ])

    #expect(response["result"]?["ok"]?.boolValue == true)
    let requests = await http.requests()
    #expect(requests.count == 1)
    #expect(requests[0].method == "POST")
    #expect(requests[0].headers["accept"] == "application/json, text/event-stream")
}

@Test func mcpHTTPTransportUsesStreamingInboundSSEWithoutBlockingStart() async throws {
    let http = StreamingRecordingTransport(responses: [
        streamResponse(
            headers: ["content-type": "text/event-stream"],
            chunks: ["event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":21,\"method\":\"ping\"}\n\n"],
            finishes: false
        ),
        streamResponse(statusCode: 202)
    ])
    let transport = try MCPHTTPTransport(url: "https://mcp.example.com/rpc", transport: http)
    await transport.setRequestHandler { request in
        [
            "jsonrpc": "2.0",
            "id": request["id"] ?? .null,
            "result": [:]
        ]
    }

    try await transport.start()

    let requests = try await waitForStreamingRequests(http, count: 2)
    #expect(requests[0].method == "GET")
    #expect(requests[0].headers["accept"] == "text/event-stream")
    #expect(requests[1].method == "POST")
    let body = try #require(requests[1].body).jsonValueForTest()
    #expect(body["id"]?.intValue == 21)
    #expect(body["result"]?.objectValue?.isEmpty == true)

    try await transport.close()
}

@Test func mcpHTTPTransportReconnectsInboundSSEWithLastEventID() async throws {
    let http = StreamingRecordingTransport(responses: [
        streamResponse(
            headers: ["content-type": "text/event-stream"],
            chunks: ["id: cursor-1\nevent: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":31,\"method\":\"ping\"}\n\n"],
            errorAfterChunks: TestStreamFailure()
        ),
        streamResponse(statusCode: 202),
        streamResponse(
            headers: ["content-type": "text/event-stream"],
            chunks: [],
            finishes: false
        )
    ])
    let transport = try MCPHTTPTransport(
        url: "https://mcp.example.com/rpc",
        transport: http,
        inboundReconnectDelayNanoseconds: 1_000_000
    )
    await transport.setRequestHandler { request in
        [
            "jsonrpc": "2.0",
            "id": request["id"] ?? .null,
            "result": [:]
        ]
    }

    try await transport.start()

    let requests = try await waitForStreamingRequests(http, count: 3)
    #expect(requests[0].method == "GET")
    #expect(requests[1].method == "POST")
    #expect(requests[2].method == "GET")
    #expect(requests[2].headers["last-event-id"] == "cursor-1")

    try await transport.close()
}

private actor MockMCPTransport: MCPTransport {
    private var messages: [JSONValue] = []
    private let capabilities: JSONValue
    private let toolResult: JSONValue?
    private var requestHandler: (@Sendable (JSONValue) async -> JSONValue)?

    init(
        capabilities: JSONValue = .object(["tools": .object(["listChanged": .bool(false)])]),
        toolResult: JSONValue? = nil
    ) {
        self.capabilities = capabilities
        self.toolResult = toolResult
    }

    func setRequestHandler(_ handler: (@Sendable (JSONValue) async -> JSONValue)?) async {
        requestHandler = handler
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
                "result": toolResult ?? [
                    "content": [
                        [
                            "type": "text",
                            "text": .string("Result for \(query)")
                        ]
                    ],
                    "isError": false
                ]
            ]
        case "resources/list":
            return [
                "jsonrpc": "2.0",
                "id": id,
                "result": [
                    "nextCursor": "cursor-2",
                    "resources": [
                        [
                            "uri": "file:///docs/intro.md",
                            "name": "intro",
                            "title": "Intro",
                            "description": "Intro docs",
                            "mimeType": "text/markdown",
                            "size": 128
                        ]
                    ]
                ]
            ]
        case "resources/read":
            return [
                "jsonrpc": "2.0",
                "id": id,
                "result": [
                    "contents": [
                        [
                            "uri": "file:///docs/intro.md",
                            "mimeType": "text/markdown",
                            "text": "# Intro"
                        ]
                    ]
                ]
            ]
        case "resources/templates/list":
            return [
                "jsonrpc": "2.0",
                "id": id,
                "result": [
                    "resourceTemplates": [
                        [
                            "uriTemplate": "file:///docs/{slug}.md",
                            "name": "doc",
                            "title": "Doc",
                            "description": "Documentation page",
                            "mimeType": "text/markdown"
                        ]
                    ]
                ]
            ]
        case "prompts/list":
            return [
                "jsonrpc": "2.0",
                "id": id,
                "result": [
                    "nextCursor": "prompt-cursor-2",
                    "prompts": [
                        [
                            "name": "summarize",
                            "title": "Summarize",
                            "description": "Summarize a topic.",
                            "arguments": [
                                [
                                    "name": "topic",
                                    "description": "Topic to summarize",
                                    "required": true
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        case "prompts/get":
            let topic = message["params"]?["arguments"]?["topic"]?.stringValue ?? "topic"
            return [
                "jsonrpc": "2.0",
                "id": id,
                "result": [
                    "description": "Summarize a topic.",
                    "messages": [
                        [
                            "role": "user",
                            "content": [
                                "type": "text",
                                "text": .string("Summarize \(topic)")
                            ]
                        ]
                    ]
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

    func simulateIncomingRequest(_ request: JSONValue) async -> JSONValue {
        guard let requestHandler else {
            return [
                "jsonrpc": "2.0",
                "id": request["id"] ?? .null,
                "error": [
                    "code": -32603,
                    "message": "No request handler registered."
                ]
            ]
        }
        return await requestHandler(request)
    }
}

private func fullMCPCapabilities() -> JSONValue {
    .object([
        "tools": .object(["listChanged": .bool(false)]),
        "resources": .object(["listChanged": .bool(false)]),
        "prompts": .object(["listChanged": .bool(false)]),
        "elicitation": .object(["applyDefaults": .bool(true)])
    ])
}

private actor MCPElicitationRecorder {
    private var recordedRequest: MCPElicitationRequest?

    func record(_ request: MCPElicitationRequest) {
        recordedRequest = request
    }

    func request() -> MCPElicitationRequest? {
        recordedRequest
    }
}

private actor StreamingRecordingTransport: AIStreamingTransport {
    private var recordedRequests: [AIHTTPRequest] = []
    private var responses: [AIHTTPStreamResponse]

    init(responses: [AIHTTPStreamResponse]) {
        self.responses = responses
    }

    func requests() -> [AIHTTPRequest] {
        recordedRequests
    }

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        let response = try await stream(request)
        var body = Data()
        for try await chunk in response.body {
            body.append(chunk)
        }
        return AIHTTPResponse(statusCode: response.statusCode, headers: response.headers, body: body)
    }

    func stream(_ request: AIHTTPRequest) async throws -> AIHTTPStreamResponse {
        recordedRequests.append(request)
        guard !responses.isEmpty else {
            return streamResponse(statusCode: 202)
        }
        return responses.removeFirst()
    }
}

private func streamResponse(
    statusCode: Int = 200,
    headers: [String: String] = [:],
    chunks: [String] = [],
    finishes: Bool = true,
    errorAfterChunks: Error? = nil
) -> AIHTTPStreamResponse {
    AIHTTPStreamResponse(
        statusCode: statusCode,
        headers: headers,
        body: AsyncThrowingStream { continuation in
            let task = Task {
                for chunk in chunks {
                    try Task.checkCancellation()
                    continuation.yield(Data(chunk.utf8))
                }
                if let errorAfterChunks {
                    continuation.finish(throwing: errorAfterChunks)
                    return
                }
                if finishes {
                    continuation.finish()
                } else {
                    while !Task.isCancelled {
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    )
}

private struct TestStreamFailure: Error {}

private extension Data {
    func jsonValueForTest() throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: self)
    }
}

private func waitForRecordedRequests(_ transport: RecordingTransport, count: Int) async throws -> [AIHTTPRequest] {
    for _ in 0..<50 {
        let requests = await transport.requests()
        if requests.count >= count {
            return requests
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    return await transport.requests()
}

private func waitForStreamingRequests(_ transport: StreamingRecordingTransport, count: Int) async throws -> [AIHTTPRequest] {
    for _ in 0..<50 {
        let requests = await transport.requests()
        if requests.count >= count {
            return requests
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    return await transport.requests()
}
