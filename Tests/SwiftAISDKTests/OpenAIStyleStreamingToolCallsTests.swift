import Testing
@testable import SwiftAISDK

@Test func openAIStyleStreamingToolCallsPreferIDsAndHandleReusedIndexesLikeUpstream() throws {
    var tracker = OpenAIStyleStreamingToolCalls()

    _ = tracker.apply(delta: [
        "index": 1,
        "id": "call_1",
        "function": ["name": "first", "arguments": #"{"one":1}"#]
    ])
    _ = tracker.apply(delta: [
        "index": 3,
        "id": "call_2",
        "function": ["name": "second", "arguments": #"{"two":2}"#]
    ])
    #expect(!tracker.hasMatchingBuffer(for: ["index": 1, "id": "call_3"]))
    _ = tracker.apply(delta: [
        "index": 1,
        "id": "call_3",
        "function": ["name": "third", "arguments": #"{"three":3}"#]
    ])

    let calls = tracker.finishedParts().compactMap { part -> AIToolCall? in
        if case let .toolCall(call) = part { return call }
        return nil
    }
    #expect(calls.map(\.id) == ["call_1", "call_2", "call_3"])
}

@Test func openAIStyleStreamingToolCallsUsesLatestCallWhenIndexIsMissingLikeUpstream() throws {
    var tracker = OpenAIStyleStreamingToolCalls()

    _ = tracker.apply(delta: [
        "index": 7,
        "id": "call_1",
        "function": ["name": "lookup", "arguments": #"{"value":""#]
    ])
    #expect(tracker.hasMatchingBuffer(for: ["function": ["arguments": "ok"]]))
    _ = tracker.apply(delta: ["function": ["arguments": "ok"]])
    _ = tracker.apply(delta: ["index": 7, "id": "", "function": ["arguments": #""}"#]])

    let call = try #require(tracker.finishedParts().compactMap { part -> AIToolCall? in
        if case let .toolCall(call) = part { return call }
        return nil
    }.first)
    #expect(call.arguments == #"{"value":"ok"}"#)
}
