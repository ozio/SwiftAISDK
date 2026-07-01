import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiParseToolCallParsesValidToolCallLikeUpstream() async throws {
    let result = try await parseToolCall(
        AIToolCall(
            id: "123",
            name: "testTool",
            arguments: #"{"param1":"test","param2":42}"#
        ),
        toolsByName: ["testTool": parseTestTool()]
    )

    #expect(result.toolCall.id == "123")
    #expect(result.toolCall.name == "testTool")
    #expect(result.input == ["param1": "test", "param2": 42])
}

@Test func aiParseToolCallRefinesInputAfterParsingLikeUpstream() async throws {
    let result = try await parseToolCall(
        AIToolCall(
            id: "123",
            name: "testTool",
            arguments: #"{"value":" raw "}"#
        ),
        toolsByName: [
            "testTool": AITool(
                name: "testTool",
                parameters: [
                    "type": "object",
                    "properties": [
                        "value": ["type": "string"]
                    ],
                    "required": ["value"]
                ],
                refineArguments: { input in
                    ["value": .string(input["value"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? "")]
                },
                execute: { _ in "ok" }
            )
        ]
    )

    #expect(result.input == ["value": "raw"])
}

@Test func aiParseToolCallParsesProviderExecutedDynamicToolWithoutRegisteredToolsLikeUpstream() async throws {
    let call = AIToolCall(
        id: "123",
        name: "testTool",
        arguments: #"{"param1":"test","param2":42}"#,
        providerExecuted: true,
        dynamic: true,
        providerMetadata: ["testProvider": ["signature": "sig"]]
    )

    let result = try await parseToolCall(call, toolsByName: [:])

    #expect(result.toolCall == call)
    #expect(result.input == ["param1": "test", "param2": 42])
}

@Test func aiParseToolCallPreservesProviderMetadataLikeUpstream() async throws {
    let result = try await parseToolCall(
        AIToolCall(
            id: "123",
            name: "testTool",
            arguments: #"{"param1":"test","param2":42}"#,
            providerMetadata: ["testProvider": ["signature": "sig"]]
        ),
        toolsByName: ["testTool": parseTestTool()]
    )

    #expect(result.toolCall.providerMetadata == ["testProvider": ["signature": "sig"]])
}

@Test func aiParseToolCallTreatsEmptyInputAsEmptyObjectLikeUpstream() async throws {
    let result = try await parseToolCall(
        AIToolCall(id: "123", name: "emptyTool", arguments: ""),
        toolsByName: ["emptyTool": emptyObjectTool()]
    )

    #expect(result.input == [:])
}

@Test func aiParseToolCallThrowsNoSuchToolWhenToolsAreMissingLikeUpstreamSwift() async {
    do {
        _ = try await parseToolCall(
            AIToolCall(id: "123", name: "testTool", arguments: "{}"),
            toolsByName: nil
        )
        Issue.record("expected no such tool error")
    } catch let error as AINoSuchToolError {
        #expect(error.toolName == "testTool")
        #expect(error.availableToolNames.isEmpty)
    } catch {
        Issue.record("expected AINoSuchToolError, got \(error)")
    }
}

@Test func aiParseToolCallThrowsNoSuchToolWhenToolIsNotFoundLikeUpstreamSwift() async {
    do {
        _ = try await parseToolCall(
            AIToolCall(id: "123", name: "nonExistentTool", arguments: "{}"),
            toolsByName: ["testTool": parseTestTool()]
        )
        Issue.record("expected no such tool error")
    } catch let error as AINoSuchToolError {
        #expect(error.toolName == "nonExistentTool")
        #expect(error.availableToolNames == ["testTool"])
    } catch {
        Issue.record("expected AINoSuchToolError, got \(error)")
    }
}

@Test func aiParseToolCallThrowsInvalidToolInputWhenArgumentsDoNotMatchSchemaLikeUpstreamSwift() async {
    do {
        _ = try await parseToolCall(
            AIToolCall(
                id: "123",
                name: "testTool",
                arguments: #"{"param1":"test"}"#
            ),
            toolsByName: ["testTool": parseTestTool()]
        )
        Issue.record("expected invalid tool input error")
    } catch let error as AIInvalidToolInputError {
        #expect(error.toolName == "testTool")
        #expect(error.toolCallID == "123")
        #expect(error.input == ["param1": "test"])
    } catch {
        Issue.record("expected AIInvalidToolInputError, got \(error)")
    }
}

@Test func aiParseToolCallMarksRegisteredDynamicToolsLikeUpstream() async throws {
    let result = try await parseToolCall(
        AIToolCall(
            id: "123",
            name: "testTool",
            arguments: #"{"param1":"test","param2":42}"#
        ),
        toolsByName: ["testTool": AITool.dynamic(
            name: "testTool",
            parameters: parseTestToolSchema(),
            execute: { _ in "ok" }
        )]
    )

    #expect(result.toolCall.dynamic)
    #expect(result.input == ["param1": "test", "param2": 42])
}

@Test func aiParseToolCallThrowsRepairErrorWhenRefinementThrowsLikeSwiftRuntime() async {
    struct RefineFailure: Error, CustomStringConvertible {
        var description: String { "test error" }
    }

    do {
        _ = try await parseToolCall(
            AIToolCall(
                id: "123",
                name: "testTool",
                arguments: #"{"param1":"test","param2":42}"#
            ),
            toolsByName: ["testTool": AITool(
                name: "testTool",
                parameters: parseTestToolSchema(),
                refineArguments: { _ in throw RefineFailure() },
                execute: { _ in "ok" }
            )]
        )
        Issue.record("expected tool call repair error")
    } catch let error as AIToolCallRepairError {
        #expect(error.toolName == "testTool")
        #expect(error.toolCallID == "123")
        #expect(error.originalError.contains("test error"))
    } catch {
        Issue.record("expected AIToolCallRepairError, got \(error)")
    }
}

private func parseTestTool() -> AITool {
    AITool(
        name: "testTool",
        parameters: parseTestToolSchema(),
        execute: { _ in "ok" }
    )
}

private func parseTestToolSchema() -> JSONValue {
    [
        "type": "object",
        "properties": [
            "param1": ["type": "string"],
            "param2": ["type": "number"]
        ],
        "required": ["param1", "param2"]
    ]
}

private func emptyObjectTool() -> AITool {
    AITool(
        name: "emptyTool",
        parameters: ["type": "object", "properties": [:]],
        execute: { _ in "ok" }
    )
}
