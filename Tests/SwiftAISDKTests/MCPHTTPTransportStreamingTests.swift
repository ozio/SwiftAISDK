import Foundation
import Testing
@testable import SwiftAISDK

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
