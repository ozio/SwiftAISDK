import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiInvokeToolCallbacksFromStreamInvokesCallbacksInOrderAndPassesThroughLikeUpstream() async throws {
    let recorder = ToolInputCallbackRecorder()
    let abortController = AIAbortController()
    let request = LanguageModelRequest(
        messages: [.user("test-input")],
        toolContexts: ["test-tool": ["requestId": "req-1"]],
        abortSignal: abortController.signal
    )
    let chunks: [LanguageStreamPart] = [
        .textDeltaPart(id: "text-1", delta: "hello"),
        .toolInputStart(id: "call-1", name: "test-tool"),
        .toolInputDelta(id: "call-1", delta: #"{"value":""#),
        .toolInputDelta(id: "call-1", delta: #"Sparkle Day"}"#),
        .toolInputEnd(id: "call-1"),
        .toolCall(AIToolCall(
            id: "call-1",
            name: "test-tool",
            arguments: #"{"value":"Sparkle Day"}"#
        ))
    ]
    let tool = AITool(
        name: "test-tool",
        parameters: [
            "type": "object",
            "properties": ["value": ["type": "string"]],
            "required": ["value"]
        ],
        onInputStart: { context in
            await recorder.record(.start(
                toolCallID: context.toolCallID,
                messages: context.messages,
                toolContext: context.toolContext,
                abortSignalMatches: context.abortSignal === abortController.signal
            ))
        },
        onInputDelta: { context in
            await recorder.record(.delta(
                toolCallID: context.toolCallID,
                inputTextDelta: context.inputTextDelta,
                messages: context.messages,
                toolContext: context.toolContext,
                abortSignalMatches: context.abortSignal === abortController.signal
            ))
        },
        onInputAvailable: { context in
            await recorder.record(.available(
                toolCallID: context.toolCallID,
                input: context.input,
                messages: context.messages,
                toolContext: context.toolContext,
                abortSignalMatches: context.abortSignal === abortController.signal
            ))
        },
        execute: { _ in "unused" }
    )

    let resultChunks = try await collectForwardedToolCallbackStream(
        chunks,
        toolsByName: ["test-tool": tool],
        request: request
    )
    let recordedEvents = await recorder.events()

    #expect(resultChunks == chunks)
    #expect(recordedEvents == [
        .start(
            toolCallID: "call-1",
            messages: [.user("test-input")],
            toolContext: ["requestId": "req-1"],
            abortSignalMatches: true
        ),
        .delta(
            toolCallID: "call-1",
            inputTextDelta: #"{"value":""#,
            messages: [.user("test-input")],
            toolContext: ["requestId": "req-1"],
            abortSignalMatches: true
        ),
        .delta(
            toolCallID: "call-1",
            inputTextDelta: #"Sparkle Day"}"#,
            messages: [.user("test-input")],
            toolContext: ["requestId": "req-1"],
            abortSignalMatches: true
        ),
        .available(
            toolCallID: "call-1",
            input: ["value": "Sparkle Day"],
            messages: [.user("test-input")],
            toolContext: ["requestId": "req-1"],
            abortSignalMatches: true
        )
    ])
}

private enum ToolInputCallbackEvent: Equatable, Sendable {
    case start(
        toolCallID: String,
        messages: [AIMessage],
        toolContext: JSONValue?,
        abortSignalMatches: Bool
    )
    case delta(
        toolCallID: String,
        inputTextDelta: String,
        messages: [AIMessage],
        toolContext: JSONValue?,
        abortSignalMatches: Bool
    )
    case available(
        toolCallID: String,
        input: JSONValue,
        messages: [AIMessage],
        toolContext: JSONValue?,
        abortSignalMatches: Bool
    )
}

private actor ToolInputCallbackRecorder {
    private var recordedEvents: [ToolInputCallbackEvent] = []

    func record(_ event: ToolInputCallbackEvent) {
        recordedEvents.append(event)
    }

    func events() -> [ToolInputCallbackEvent] {
        recordedEvents
    }
}

private func collectForwardedToolCallbackStream(
    _ chunks: [LanguageStreamPart],
    toolsByName: [String: AITool],
    request: LanguageModelRequest
) async throws -> [LanguageStreamPart] {
    let inputStream = AsyncThrowingStream<LanguageStreamPart, Error> { continuation in
        for chunk in chunks {
            continuation.yield(chunk)
        }
        continuation.finish()
    }
    let outputStream = AsyncThrowingStream<LanguageStreamPart, Error> { continuation in
        let task = Task {
            do {
                _ = try await forwardLanguageStream(
                    inputStream,
                    to: continuation,
                    toolsByName: toolsByName,
                    request: request
                )
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
    }
    var result: [LanguageStreamPart] = []
    for try await part in outputStream {
        result.append(part)
    }
    return result
}
