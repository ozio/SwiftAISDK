import Foundation
import Testing
@testable import SwiftAISDK

@Suite("WeeklyCoreMCP20260927Tests")
struct WeeklyCoreMCP20260927Tests {
    @Test func stdioCustomEnvironmentWinsOverInheritedValues() {
        let environment = mcpStdioEnvironment([
            "PATH": "/weekly/custom/bin",
            "HOME": "/weekly/custom/home"
        ])

        #expect(environment["PATH"] == "/weekly/custom/bin")
        #expect(environment["HOME"] == "/weekly/custom/home")
    }

    @Test func discoveryProtocolHeaderIsRemovedAfterCrossOriginRedirect() async throws {
        let transport = Weekly20260927Transport(responses: [
            AIHTTPResponse(
                statusCode: 302,
                headers: ["location": "https://metadata.example.net/final"]
            ),
            AIHTTPResponse(statusCode: 200, body: Data("{}".utf8))
        ])

        _ = try await discoveryGET(
            url: try #require(URL(string: "https://auth.example.com/start")),
            protocolVersion: "2026-09-01",
            trustedOrigin: nil,
            transport: transport
        )

        let requests = await transport.requests()
        #expect(requests.count == 2)
        #expect(weekly20260927Header("MCP-Protocol-Version", in: requests[0].headers) == "2026-09-01")
        #expect(weekly20260927Header("MCP-Protocol-Version", in: requests[1].headers) == nil)
    }

    @Test func preregisteredOAuthClientIsNotInvalidatedOnRefreshInvalidClient() async throws {
        let provider = TestOAuthClientProvider(
            clientInformation: try oauthClientInformation(clientID: "pre-registered-client"),
            tokens: try oauthTokens(accessToken: "old-access", refreshToken: "old-refresh")
        )
        let transport = RecordingTransport(responses: [
            jsonResponse("""
            {
              "resource": "https://resource.example.com/mcp",
              "authorization_servers": ["https://auth.example.com"]
            }
            """),
            oauthAuthorizationMetadataResponse(),
            AIHTTPResponse(
                statusCode: 401,
                headers: ["content-type": "application/json"],
                body: Data("""
                {
                  "error": "invalid_client",
                  "error_description": "Client registration is still valid locally"
                }
                """.utf8)
            )
        ])

        do {
            _ = try await MCPOAuth.auth(
                provider: provider,
                serverURL: "https://resource.example.com/mcp/rpc",
                transport: transport
            )
            Issue.record("Expected invalid_client to propagate for a pre-registered client.")
        } catch let error as MCPOAuthServerError {
            #expect(error.code == "invalid_client")
        }

        #expect(await provider.invalidations().isEmpty)
        #expect(try await provider.clientInformation()?.clientID == "pre-registered-client")
        #expect(await transport.requests().count == 3)
    }

    @Test func untrustedFetchUsesAnExplicitSafeFirstHopHeaderAndStripsItCrossOrigin() async throws {
        let transport = Weekly20260927Transport(responses: [
            AIHTTPResponse(
                statusCode: 302,
                headers: ["location": "https://cdn.example.net/file"]
            ),
            AIHTTPResponse(statusCode: 200, body: Data("downloaded".utf8))
        ])

        let response = try await fetchUntrustedURL(
            "https://files.example.com/start",
            transport: transport,
            headers: [
                "Authorization": "Bearer secret",
                "Cookie": "session=secret",
                "User-Agent": "SwiftAISDK/weekly",
                "X-Weekly-Safe": "forward-once",
                "X-Weekly-Unsafe": "never-forward"
            ],
            untrustedFirstHopHeaders: ["X-Weekly-Safe"]
        )

        #expect(response.body == Data("downloaded".utf8))
        let requests = await transport.requests()
        #expect(requests.count == 2)
        #expect(weekly20260927Header("authorization", in: requests[0].headers) == nil)
        #expect(weekly20260927Header("cookie", in: requests[0].headers) == nil)
        #expect(weekly20260927Header("x-weekly-unsafe", in: requests[0].headers) == nil)
        #expect(weekly20260927Header("x-weekly-safe", in: requests[0].headers) == "forward-once")
        #expect(weekly20260927Header("user-agent", in: requests[0].headers) == "SwiftAISDK/weekly")
        #expect(weekly20260927Header("x-weekly-safe", in: requests[1].headers) == nil)
        #expect(weekly20260927Header("user-agent", in: requests[1].headers) == "SwiftAISDK/weekly")
    }

    @Test func generatedFileURLIsMaterializedAndHTTPFailureIsReported() async throws {
        let successTransport = Weekly20260927Transport(responses: [
            AIHTTPResponse(statusCode: 200, body: Data([1, 2, 3]))
        ])
        let resolved = try await resolveGeneratedFile(
            AIStreamFile(mediaType: "application/octet-stream", url: "https://files.example.com/result.bin"),
            abortSignal: nil,
            transport: successTransport
        )

        #expect(resolved.data == Data([1, 2, 3]))
        #expect(resolved.url == nil)

        let failureTransport = Weekly20260927Transport(responses: [
            AIHTTPResponse(statusCode: 404)
        ])
        do {
            _ = try await resolveGeneratedFile(
                AIStreamFile(mediaType: "application/octet-stream", url: "https://files.example.com/missing.bin"),
                abortSignal: nil,
                transport: failureTransport
            )
            Issue.record("Expected a non-success generated-file response to fail.")
        } catch let error as AIDownloadError {
            #expect(error.message.contains("404"))
        }
    }

    @Test func localCallerOnlyToolCannotBeCalledDirectlyByTheModel() async throws {
        let capture = ToolCapture()
        let caller = experimentalToolCaller(
            AITool(
                name: "code",
                parameters: ["type": "object", "properties": [:]],
                execute: { _ in "unbound" }
            ),
            definition: .local(
                bind: { _ in
                    AITool(
                        name: "code",
                        parameters: ["type": "object", "properties": [:]],
                        execute: { _ in "bound" }
                    )
                },
                prepareModelMessage: { _ in "catalog:weather" }
            )
        )
        let localOnly = AITool(
            name: "weather",
            parameters: ["type": "object", "properties": [:]],
            execute: { arguments in
                await capture.record(arguments)
                return "sunny"
            }
        )
        let model = MockLanguageModel(result: TextGenerationResult(
            text: "",
            finishReason: "tool-calls",
            toolCalls: [AIToolCall(id: "call-weather", name: "weather", arguments: "{}")],
            rawValue: .object([:])
        ))

        let result = try await AI.generateText(
            model: model,
            request: LanguageModelRequest(messages: [.user("weather")]),
            executableTools: [caller, localOnly],
            maxSteps: 1,
            toolCallers: ["weather": ["code"]],
            retryPolicy: .none
        )

        #expect(await capture.value() == nil)
        #expect(model.requests.first?.tools.keys.sorted() == ["code"])
        #expect(model.requests.first?.messages == [
            .user("weather"),
            .user("catalog:weather")
        ])
        let toolResult = try #require(result.toolResults.first)
        #expect(toolResult.toolName == "weather")
        #expect(toolResult.toolCallID == "call-weather")
        #expect(toolResult.isError)
        #expect(toolResult.result["type"]?.stringValue == "error-text")
        #expect(toolResult.result["value"]?.stringValue?.contains("No such tool: weather") == true)
        #expect(toolResult.result["value"]?.stringValue?.contains("code") == true)

        let callerModel = MockLanguageModel(result: TextGenerationResult(
            text: "",
            finishReason: "tool-calls",
            toolCalls: [AIToolCall(id: "call-code", name: "code", arguments: "{}")],
            rawValue: .object([:])
        ))
        let callerResult = try await AI.generateText(
            model: callerModel,
            request: LanguageModelRequest(messages: [.user("weather")]),
            executableTools: [caller, localOnly],
            maxSteps: 1,
            toolCallers: ["weather": ["code"]],
            retryPolicy: .none
        )

        #expect(callerResult.toolResults.first?.toolName == "code")
        #expect(callerResult.toolResults.first?.result.stringValue == "bound")
        #expect(callerResult.toolResults.first?.isError == false)
    }

    @Test func approvalPreservesAndRevalidatesTheSchemaInputBeforeRefinement() async throws {
        let tool = AITool(
            name: "normalize",
            parameters: [
                "type": "object",
                "properties": ["value": ["type": "string"]],
                "required": ["value"],
                "additionalProperties": false
            ],
            refineArguments: { input in
                var object = input.objectValue ?? [:]
                object["value"] = .string(object["value"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? "")
                return .object(object)
            },
            execute: { $0 }
        )
        let request = LanguageModelRequest(messages: [.user("normalize")])
        let originalInput: JSONValue = ["value": "  hello  "]
        let refinedInput: JSONValue = ["value": "hello"]
        let batch = try await executeToolCalls(
            [AIToolCall(id: "call-1", name: "normalize", arguments: try #require(canonicalJSONText(originalInput)))],
            toolsByName: ["normalize": tool],
            request: request,
            toolApproval: { _ in .userApproval }
        )

        let approvalRequest = try #require(batch.approvalRequests.first)
        #expect(approvalRequest.inputSchemaInput == originalInput)
        #expect(approvalRequest.arguments == canonicalJSONText(refinedInput))

        let collected = AICollectedToolApproval(
            approvalRequest: approvalRequest,
            approvalResponse: AIToolApprovalResponse(id: approvalRequest.id, approved: true),
            toolCall: AIToolCall(
                id: "call-1",
                name: "normalize",
                arguments: try #require(canonicalJSONText(refinedInput))
            )
        )
        let accepted = try await validateApprovedToolApprovals(
            approvedToolApprovals: [collected],
            toolsByName: ["normalize": tool],
            request: request,
            toolApproval: nil
        )
        #expect(accepted.approvedToolApprovals.count == 1)
        #expect(accepted.invalidToolApprovals.isEmpty)

        var tampered = collected
        tampered.approvalRequest.inputSchemaInput = ["value": 42]
        let rejected = try await validateApprovedToolApprovals(
            approvedToolApprovals: [tampered],
            toolsByName: ["normalize": tool],
            request: request,
            toolApproval: nil
        )
        #expect(rejected.approvedToolApprovals.isEmpty)
        #expect(rejected.invalidToolApprovals.count == 1)
    }

    @Test func uiStreamOnEndReceivesOriginalMessageAndACompletedOutcomeOnce() async throws {
        let capture = Weekly20260927EndCapture()
        let original = AIUIMessage.user("question", id: "original-message")
        let input = AsyncThrowingStream<LanguageStreamPart, Error> { continuation in
            continuation.yield(.textStart(id: "answer"))
            continuation.yield(.textDeltaPart(id: "answer", delta: "done"))
            continuation.yield(.textEnd(id: "answer"))
            continuation.finish()
        }
        let snapshots = AIUIMessageStreamReducer.snapshots(
            from: input,
            originalMessage: original,
            onEnd: { await capture.record($0) }
        )

        var last: AIUIMessage?
        for try await snapshot in snapshots {
            last = snapshot
        }

        let events = await capture.events()
        #expect(events.count == 1)
        #expect(events.first?.outcome == .completed)
        #expect(events.first?.isAborted == false)
        #expect(events.first?.isCancelled == false)
        #expect(events.first?.message.id == "original-message")
        #expect(last?.id == "original-message")
    }
}

private actor Weekly20260927Transport: AITransport {
    private var scriptedResponses: [AIHTTPResponse]
    private var recordedRequests: [AIHTTPRequest] = []

    init(responses: [AIHTTPResponse]) {
        scriptedResponses = responses
    }

    func requests() -> [AIHTTPRequest] {
        recordedRequests
    }

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        recordedRequests.append(request)
        guard !scriptedResponses.isEmpty else {
            throw AIError.invalidResponse(provider: "weekly-20260927", message: "Missing scripted response.")
        }
        return scriptedResponses.removeFirst()
    }
}

private actor Weekly20260927EndCapture {
    private var values: [AIUIMessageStreamEndEvent] = []

    func record(_ event: AIUIMessageStreamEndEvent) {
        values.append(event)
    }

    func events() -> [AIUIMessageStreamEndEvent] {
        values
    }
}

private func weekly20260927Header(_ name: String, in headers: [String: String]) -> String? {
    headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
}
