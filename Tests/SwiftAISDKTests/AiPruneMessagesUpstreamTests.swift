import Testing
@testable import SwiftAISDK

@Test func aiPruneMessagesRemovesAllReasoningLikeUpstream() {
    let result = pruneMessages(messagesFixture1(), reasoning: .all)

    #expect(result.map(\.reasoning) == [nil, nil, nil, nil])
    #expect(result[1].content == [
        .toolCall(tokyoCall()),
        .toolCall(busanCall()),
        .toolApprovalRequest(busanApprovalRequest())
    ])
    #expect(result[3].content == [.text("The weather in Tokyo is sunny. I could not get the weather in Busan.")])
}

@Test func aiPruneMessagesRemovesReasoningBeforeLastMessageLikeUpstream() {
    let result = pruneMessages(messagesFixture1(), reasoning: .beforeLastMessage)

    #expect(result[1].reasoning == nil)
    #expect(result[3].reasoning == "I have got the weather in Tokyo and Busan.")
    #expect(result[3].content == [.text("The weather in Tokyo is sunny. I could not get the weather in Busan.")])
}

@Test func aiPruneMessagesRemovesAllToolPartsLikeUpstream() {
    let result = pruneMessages(messagesFixture1(), toolCalls: [.all()])

    #expect(result == [
        .user("Weather in Tokyo and Busan?"),
        AIMessage(role: .assistant, content: [], reasoning: "I need to get the weather in Tokyo and Busan."),
        AIMessage(
            role: .assistant,
            content: [.text("The weather in Tokyo is sunny. I could not get the weather in Busan.")],
            reasoning: "I have got the weather in Tokyo and Busan."
        )
    ])
}

@Test func aiPruneMessagesKeepsToolPartsInLastMessageLikeUpstream() {
    let result = pruneMessages(messagesFixture2(), toolCalls: [.beforeLastMessage()])

    #expect(result == messagesFixture2())
}

@Test func aiPruneMessagesRemovesEarlierMultiTurnToolPartsWhenLastMessageHasNoToolsLikeUpstream() {
    let result = pruneMessages(multiTurnToolCallMessagesFixture(), toolCalls: [.beforeLastMessage()])

    #expect(result == [
        .user("ask me a question"),
        AIMessage.assistant("What can i help you with"),
        AIMessage.assistant("What would you like to discuss or work on?"),
        .user("never mind. lets end this conversation"),
        AIMessage.assistant("ok, have a nice day"),
        .user("thank you")
    ])
}

@Test func aiPruneMessagesKeepsAssociatedToolPartsBeforeLastTwoMessagesLikeUpstream() {
    let result = pruneMessages(messagesFixture1(), toolCalls: [.beforeLastMessages(2)])

    #expect(result == messagesFixture1())
}

@Test func aiPruneMessagesAppliesMultipleToolSettingsLikeUpstream() {
    let result = pruneMessages(
        messagesFixture1(),
        toolCalls: [
            .all(tools: ["get-weather-tool-1"]),
            .beforeLastMessages(2, tools: ["get-weather-tool-2"])
        ]
    )

    #expect(result == [
        .user("Weather in Tokyo and Busan?"),
        AIMessage(
            role: .assistant,
            content: [
                .toolCall(busanCall()),
                .toolApprovalRequest(busanApprovalRequest())
            ],
            reasoning: "I need to get the weather in Tokyo and Busan."
        ),
        .toolResponses(
            approvalResponses: [AIToolApprovalResponse(id: "approval-1", approved: true)],
            toolResults: [busanResult()]
        ),
        AIMessage(
            role: .assistant,
            content: [.text("The weather in Tokyo is sunny. I could not get the weather in Busan.")],
            reasoning: "I have got the weather in Tokyo and Busan."
        )
    ])
}

@Test func aiPruneMessagesPrunesApprovalResponseWithRequestAndToolCallLikeUpstreamRegression() {
    let result = pruneMessages(
        [
            .user("Weather in Tokyo and Busan?"),
            AIMessage(
                role: .assistant,
                content: [
                    .toolCall(tokyoCall()),
                    .toolCall(busanCall()),
                    .toolApprovalRequest(busanApprovalRequest())
                ]
            ),
            .toolResponses(
                approvalResponses: [AIToolApprovalResponse(id: "approval-1", approved: true)],
                toolResults: [tokyoResult(), busanResult()]
            )
        ],
        toolCalls: [.all(tools: ["get-weather-tool-2"])]
    )

    #expect(result == [
        .user("Weather in Tokyo and Busan?"),
        AIMessage(role: .assistant, content: [.toolCall(tokyoCall())]),
        .toolResponses(toolResults: [tokyoResult()])
    ])

    let approvalRequests = result.flatMap(\.content).compactMap { part -> AIToolApprovalRequest? in
        if case let .toolApprovalRequest(request) = part { return request }
        return nil
    }
    let approvalResponses = result.flatMap(\.content).compactMap { part -> AIToolApprovalResponse? in
        if case let .toolApprovalResponse(response) = part { return response }
        return nil
    }
    #expect(Set(approvalResponses.map(\.id)).isSubset(of: Set(approvalRequests.map(\.id))))
}

@Test func aiPruneMessagesDropsUnresolvedApprovalResponsesDuringSelectivePruningLikeUpstreamRegression() {
    let result = pruneMessages(
        [
            .user("Weather in Tokyo and Busan?"),
            AIMessage(role: .assistant, content: [.toolCall(tokyoCall())]),
            .toolResponses(
                approvalResponses: [AIToolApprovalResponse(id: "unknown-approval", approved: true)],
                toolResults: [tokyoResult()]
            )
        ],
        toolCalls: [.all(tools: ["get-weather-tool-2"])]
    )

    #expect(result == [
        .user("Weather in Tokyo and Busan?"),
        AIMessage(role: .assistant, content: [.toolCall(tokyoCall())]),
        .toolResponses(toolResults: [tokyoResult()])
    ])
}

private func messagesFixture1() -> [AIMessage] {
    [
        .user("Weather in Tokyo and Busan?"),
        AIMessage(
            role: .assistant,
            content: [
                .toolCall(tokyoCall()),
                .toolCall(busanCall()),
                .toolApprovalRequest(busanApprovalRequest())
            ],
            reasoning: "I need to get the weather in Tokyo and Busan."
        ),
        .toolResponses(
            approvalResponses: [AIToolApprovalResponse(id: "approval-1", approved: true)],
            toolResults: [tokyoResult(), busanResult()]
        ),
        AIMessage(
            role: .assistant,
            content: [.text("The weather in Tokyo is sunny. I could not get the weather in Busan.")],
            reasoning: "I have got the weather in Tokyo and Busan."
        )
    ]
}

private func messagesFixture2() -> [AIMessage] {
    [
        .user("Weather in Tokyo and Busan?"),
        AIMessage(
            role: .assistant,
            content: [
                .toolCall(tokyoCall()),
                .toolCall(busanCall()),
                .toolApprovalRequest(AIToolApprovalRequest(
                    id: "approval-1",
                    toolName: "get-weather-tool-1",
                    arguments: #"{"city": "Tokyo"}"#,
                    toolCallID: "call-1"
                ))
            ],
            reasoning: "I need to get the weather in Tokyo and Busan."
        )
    ]
}

private func multiTurnToolCallMessagesFixture() -> [AIMessage] {
    let call1 = AIToolCall(
        id: "toolu_01P9s4havAQSjDmS4eWT1N2V",
        name: "AskUserQuestion",
        arguments: #"{"question":"What would you like help with today?","options":["Tool 1 Option 1","Tool 1 Option 2","Tool 1 Option 3"]}"#
    )
    let call2 = AIToolCall(
        id: "toolu_01TMAuwWKLmBoQtx7K88dxsQ",
        name: "AskUserQuestion",
        arguments: #"{"question":"Ok what else?","options":["Tool 2 Option 1","Tool 2 Option 2","Tool 2 Option 3"]}"#
    )
    return [
        .user("ask me a question"),
        AIMessage.assistant(text: "What can i help you with", toolCalls: [call1]),
        .toolResult(AIToolResult(
            toolCallID: call1.id,
            toolName: call1.name,
            result: "Something else"
        )),
        AIMessage.assistant(toolCalls: [call2]),
        .toolResult(AIToolResult(
            toolCallID: call2.id,
            toolName: call2.name,
            result: "Other - I'll describe it"
        )),
        AIMessage.assistant("What would you like to discuss or work on?"),
        .user("never mind. lets end this conversation"),
        AIMessage.assistant("ok, have a nice day"),
        .user("thank you")
    ]
}

private func tokyoCall() -> AIToolCall {
    AIToolCall(id: "call-1", name: "get-weather-tool-1", arguments: #"{"city": "Tokyo"}"#)
}

private func busanCall() -> AIToolCall {
    AIToolCall(id: "call-2", name: "get-weather-tool-2", arguments: #"{"city": "Busan"}"#)
}

private func busanApprovalRequest() -> AIToolApprovalRequest {
    AIToolApprovalRequest(
        id: "approval-1",
        toolName: "get-weather-tool-2",
        arguments: #"{"city": "Busan"}"#,
        toolCallID: "call-2"
    )
}

private func tokyoResult() -> AIToolResult {
    AIToolResult(toolCallID: "call-1", toolName: "get-weather-tool-1", result: "sunny")
}

private func busanResult() -> AIToolResult {
    AIToolResult(
        toolCallID: "call-2",
        toolName: "get-weather-tool-2",
        result: "Error: Fetching weather data failed",
        isError: true
    )
}
