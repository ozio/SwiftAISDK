import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiGenerateTextReturnsToolApprovalRequestLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
    let approvalRequest = AIToolApprovalRequest(
        id: "approval-call-1",
        toolName: "tool1",
        arguments: #"{"value":"value"}"#,
        toolCallID: "call-1"
    )
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "",
        content: [.toolCall(toolCall)],
        finishReason: "tool-calls",
        rawValue: .object([:])
    ))
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { _ in
        Issue.record("Tool should not execute before user approval.")
        return "unused"
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 3,
        toolApproval: { _ in .userApproval }
    )

    #expect(model.requests.count == 1)
    #expect(result.steps.count == 1)
    #expect(result.finishReason == "tool-calls")
    #expect(result.content == [.toolCall(toolCall), .toolApprovalRequest(approvalRequest)])
    #expect(result.toolResults == [])
    #expect(result.toolApprovalRequests == [approvalRequest])
    #expect(result.responseMessages == [
        AIMessage(role: .assistant, content: [
            .toolCall(toolCall),
            .toolApprovalRequest(approvalRequest)
        ])
    ])
}

@Test func aiGenerateTextReturnsToolDefinedApprovalRequestLikeUpstream() async throws {
    let toolCall = AIToolCall(id: "call-1", name: "tool1", arguments: #"{"value":"value"}"#)
    let approvalRequest = AIToolApprovalRequest(
        id: "approval-call-1",
        toolName: "tool1",
        arguments: #"{"value":"value"}"#,
        toolCallID: "call-1"
    )
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "",
        content: [.toolCall(toolCall)],
        finishReason: "tool-calls",
        rawValue: .object([:])
    ))
    let approvalCapture = ToolDefinedApprovalCapture()
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ],
        needsApproval: { input, context in
            await approvalCapture.record(input: input, context: context)
            return true
        }
    ) { _ in
        Issue.record("Tool-defined approval should stop before execution.")
        return "unused"
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 3
    )

    #expect(await approvalCapture.calls() == [
        ToolDefinedApprovalCapture.Call(
            input: ["value": "value"],
            toolCallID: "call-1",
            messages: [.user("test-input")]
        )
    ])
    #expect(model.requests.count == 1)
    #expect(result.steps.count == 1)
    #expect(result.finishReason == "tool-calls")
    #expect(result.content == [.toolCall(toolCall), .toolApprovalRequest(approvalRequest)])
    #expect(result.toolResults == [])
    #expect(result.toolApprovalRequests == [approvalRequest])
    #expect(result.responseMessages == [
        AIMessage(role: .assistant, content: [
            .toolCall(toolCall),
            .toolApprovalRequest(approvalRequest)
        ])
    ])
}

@Test func aiGenerateTextExecutesApplicableToolAndReturnsApprovalRequestLikeUpstream() async throws {
    let approvalCall = AIToolCall(
        id: "call-1",
        name: "tool1",
        arguments: #"{"value":"value-needs-approval"}"#
    )
    let executableCall = AIToolCall(
        id: "call-2",
        name: "tool1",
        arguments: #"{"value":"value-no-approval"}"#
    )
    let executableResult = AIToolResult(
        toolCallID: "call-2",
        toolName: "tool1",
        result: "result for value-no-approval"
    )
    let approvalRequest = AIToolApprovalRequest(
        id: "approval-call-1",
        toolName: "tool1",
        arguments: #"{"value":"value-needs-approval"}"#,
        toolCallID: "call-1"
    )
    let model = MockLanguageModel(result: TextGenerationResult(
        text: "",
        content: [.toolCall(approvalCall), .toolCall(executableCall)],
        finishReason: "tool-calls",
        rawValue: .object([:])
    ))
    let executionCapture = ToolExecutionInputListCapture()
    let approvalCapture = ApprovalContextCapture()
    let tool = AITool(
        name: "tool1",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ]
    ) { input in
        await executionCapture.record(input)
        return .string("result for \(input["value"]?.stringValue ?? "")")
    }

    let result = try await AI.generateText(
        model: model,
        prompt: "test-input",
        executableTools: [tool],
        maxSteps: 3,
        toolApproval: { context in
            await approvalCapture.record(context)
            return context.arguments["value"]?.stringValue == "value-needs-approval"
                ? .userApproval
                : .notApplicable
        }
    )

    #expect(await approvalCapture.calls() == [
        ApprovalContextCapture.Call(
            toolCallID: "call-1",
            arguments: ["value": "value-needs-approval"],
            messages: [.user("test-input")]
        ),
        ApprovalContextCapture.Call(
            toolCallID: "call-2",
            arguments: ["value": "value-no-approval"],
            messages: [.user("test-input")]
        )
    ])
    #expect(await executionCapture.values() == [["value": "value-no-approval"]])
    #expect(result.steps.count == 1)
    #expect(result.finishReason == "tool-calls")
    let expectedContent: [AIResultContentPart] = [
        .toolCall(approvalCall),
        .toolCall(executableCall),
        .toolResult(executableResult),
        .toolApprovalRequest(approvalRequest)
    ]
    #expect(result.content == expectedContent)
    #expect(result.toolResults == [executableResult])
    #expect(result.toolApprovalRequests == [approvalRequest])
    #expect(result.responseMessages == [
        AIMessage(role: .assistant, content: [
            .toolCall(approvalCall),
            .toolCall(executableCall),
            .toolApprovalRequest(approvalRequest)
        ]),
        AIMessage(role: .tool, content: [.toolResult(executableResult)])
    ])
}
