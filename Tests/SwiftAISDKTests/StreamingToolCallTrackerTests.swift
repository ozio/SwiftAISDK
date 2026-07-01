import Foundation
import Testing
@testable import SwiftAISDK

@Test func streamingToolCallTrackerAccumulatesSingleToolCallAcrossDeltasLikeUpstream() throws {
    var tracker = AIStreamingToolCallTracker()

    var parts = try tracker.processDelta(AIStreamingToolCallDelta(
        index: 0,
        id: "call_1",
        type: "function",
        functionName: "get_weather",
        arguments: #"{"ci"#
    ))
    #expect(parts == [
        .toolInputStart(id: "call_1", name: "get_weather"),
        .toolInputDelta(id: "call_1", delta: #"{"ci"#)
    ])

    parts = try tracker.processDelta(AIStreamingToolCallDelta(
        index: 0,
        arguments: #"ty": "San"#
    ))
    #expect(parts == [
        .toolInputDelta(id: "call_1", delta: #"ty": "San"#)
    ])

    parts = try tracker.processDelta(AIStreamingToolCallDelta(
        index: 0,
        arguments: #" Francisco"}"#
    ))
    #expect(parts == [
        .toolInputDelta(id: "call_1", delta: #" Francisco"}"#),
        .toolInputEnd(id: "call_1"),
        .toolCall(AIToolCall(
            id: "call_1",
            name: "get_weather",
            arguments: #"{"city": "San Francisco"}"#
        ))
    ])
}

@Test func streamingToolCallTrackerFinalizesFullToolCallInSingleChunkLikeUpstream() throws {
    var tracker = AIStreamingToolCallTracker()

    let parts = try tracker.processDelta(AIStreamingToolCallDelta(
        index: 0,
        id: "call_1",
        type: "function",
        functionName: "get_weather",
        arguments: #"{"city": "London"}"#
    ))

    #expect(parts == [
        .toolInputStart(id: "call_1", name: "get_weather"),
        .toolInputDelta(id: "call_1", delta: #"{"city": "London"}"#),
        .toolInputEnd(id: "call_1"),
        .toolCall(AIToolCall(
            id: "call_1",
            name: "get_weather",
            arguments: #"{"city": "London"}"#
        ))
    ])
}

@Test func streamingToolCallTrackerHandlesMultipleConcurrentToolCallsLikeUpstream() throws {
    var tracker = AIStreamingToolCallTracker()

    let first = try tracker.processDelta(AIStreamingToolCallDelta(
        index: 0,
        id: "call_1",
        type: "function",
        functionName: "get_weather",
        arguments: ""
    ))
    let second = try tracker.processDelta(AIStreamingToolCallDelta(
        index: 1,
        id: "call_2",
        type: "function",
        functionName: "get_time",
        arguments: ""
    ))

    #expect(first + second == [
        .toolInputStart(id: "call_1", name: "get_weather"),
        .toolInputStart(id: "call_2", name: "get_time")
    ])
}

@Test func streamingToolCallTrackerSkipsDeltasForFinishedToolCallsLikeUpstream() throws {
    var tracker = AIStreamingToolCallTracker()

    _ = try tracker.processDelta(AIStreamingToolCallDelta(
        index: 0,
        id: "call_1",
        type: "function",
        functionName: "fn",
        arguments: "{}"
    ))

    let parts = try tracker.processDelta(AIStreamingToolCallDelta(
        index: 0,
        arguments: "extra"
    ))

    #expect(parts == [])
}

@Test func streamingToolCallTrackerSkipsDeltaEmissionWhenArgumentsAreNilLikeUpstream() throws {
    var tracker = AIStreamingToolCallTracker()

    _ = try tracker.processDelta(AIStreamingToolCallDelta(
        index: 0,
        id: "call_1",
        type: "function",
        functionName: "fn",
        arguments: ""
    ))

    let parts = try tracker.processDelta(AIStreamingToolCallDelta(
        index: 0,
        arguments: nil
    ))

    #expect(parts == [])
}

@Test func streamingToolCallTrackerUsesIndexFallbackLikeUpstream() throws {
    var tracker = AIStreamingToolCallTracker()

    let first = try tracker.processDelta(AIStreamingToolCallDelta(
        id: "call_1",
        type: "function",
        functionName: "fn1",
        arguments: "{}"
    ))
    let second = try tracker.processDelta(AIStreamingToolCallDelta(
        id: "call_2",
        type: "function",
        functionName: "fn2",
        arguments: "{}"
    ))

    let starts = (first + second).compactMap { part -> LanguageStreamPart? in
        if case .toolInputStart = part { return part }
        return nil
    }
    #expect(starts == [
        .toolInputStart(id: "call_1", name: "fn1"),
        .toolInputStart(id: "call_2", name: "fn2")
    ])
}

@Test func streamingToolCallTrackerValidatesRequiredFieldsLikeUpstream() {
    var missingIDTracker = AIStreamingToolCallTracker()
    expectInvalidStreamingToolCall(message: "Expected 'id' to be a string.") {
        _ = try missingIDTracker.processDelta(AIStreamingToolCallDelta(
            index: 0,
            type: "function",
            functionName: "fn"
        ))
    }

    var missingNameTracker = AIStreamingToolCallTracker()
    expectInvalidStreamingToolCall(message: "Expected 'function.name' to be a string.") {
        _ = try missingNameTracker.processDelta(AIStreamingToolCallDelta(
            index: 0,
            id: "call_1",
            type: "function"
        ))
    }
}

@Test func streamingToolCallTrackerValidatesTypeLikeUpstream() throws {
    var noValidation = AIStreamingToolCallTracker(typeValidation: .none)
    _ = try noValidation.processDelta(AIStreamingToolCallDelta(
        index: 0,
        id: "call_1",
        type: "custom",
        functionName: "fn",
        arguments: ""
    ))

    var ifPresent = AIStreamingToolCallTracker(typeValidation: .ifPresent)
    expectInvalidStreamingToolCall(message: "Expected 'function' type.") {
        _ = try ifPresent.processDelta(AIStreamingToolCallDelta(
            index: 0,
            id: "call_1",
            type: "custom",
            functionName: "fn",
            arguments: ""
        ))
    }

    var ifPresentWithoutType = AIStreamingToolCallTracker(typeValidation: .ifPresent)
    _ = try ifPresentWithoutType.processDelta(AIStreamingToolCallDelta(
        index: 0,
        id: "call_1",
        functionName: "fn",
        arguments: ""
    ))

    var required = AIStreamingToolCallTracker(typeValidation: .required)
    expectInvalidStreamingToolCall(message: "Expected 'function' type.") {
        _ = try required.processDelta(AIStreamingToolCallDelta(
            index: 0,
            id: "call_1",
            functionName: "fn",
            arguments: ""
        ))
    }

    var requiredWithType = AIStreamingToolCallTracker(typeValidation: .required)
    _ = try requiredWithType.processDelta(AIStreamingToolCallDelta(
        index: 0,
        id: "call_1",
        type: "function",
        functionName: "fn",
        arguments: ""
    ))
}

@Test func streamingToolCallTrackerFlushFinalizesUnfinishedToolCallsLikeUpstream() throws {
    var tracker = AIStreamingToolCallTracker()

    _ = try tracker.processDelta(AIStreamingToolCallDelta(
        index: 0,
        id: "call_1",
        type: "function",
        functionName: "fn",
        arguments: #"{"key": "val"#
    ))

    let parts = tracker.flush()
    #expect(parts == [
        .toolInputEnd(id: "call_1"),
        .toolCall(AIToolCall(
            id: "call_1",
            name: "fn",
            arguments: #"{"key": "val"#
        ))
    ])
}

@Test func streamingToolCallTrackerDoesNotRefinalizeFinishedToolCallsLikeUpstream() throws {
    var tracker = AIStreamingToolCallTracker()

    _ = try tracker.processDelta(AIStreamingToolCallDelta(
        index: 0,
        id: "call_1",
        type: "function",
        functionName: "fn",
        arguments: "{}"
    ))

    #expect(tracker.flush() == [])
}

@Test func streamingToolCallTrackerIncludesProviderMetadataLikeUpstream() throws {
    var tracker = AIStreamingToolCallTracker(
        extractMetadata: { delta in
            delta.rawValue?["extra_content"]?["google"]?["thought_signature"].map { ["thoughtSignature": $0] }
        },
        buildToolCallProviderMetadata: { metadata in
            guard let signature = metadata?["thoughtSignature"] else { return nil }
            return ["google": .object(["thoughtSignature": signature])]
        }
    )

    let parts = try tracker.processDelta(AIStreamingToolCallDelta(
        index: 0,
        id: "call_1",
        type: "function",
        functionName: "fn",
        arguments: "{}",
        rawValue: .object([
            "extra_content": .object([
                "google": .object(["thought_signature": .string("sig123")])
            ])
        ])
    ))

    #expect(parts.last == .toolCall(AIToolCall(
        id: "call_1",
        name: "fn",
        arguments: "{}",
        providerMetadata: ["google": .object(["thoughtSignature": .string("sig123")])],
        rawValue: .object([
            "extra_content": .object([
                "google": .object(["thought_signature": .string("sig123")])
            ])
        ])
    )))
}

@Test func streamingToolCallTrackerIncludesProviderMetadataOnFlushLikeUpstream() throws {
    var tracker = AIStreamingToolCallTracker(
        extractMetadata: { _ in ["custom": .object(["key": .string("value")])] },
        buildToolCallProviderMetadata: { metadata in
            metadata.map { ["provider": .object($0)] }
        }
    )

    _ = try tracker.processDelta(AIStreamingToolCallDelta(
        index: 0,
        id: "call_1",
        type: "function",
        functionName: "fn",
        arguments: #"{"incomplete"#
    ))

    let parts = tracker.flush()
    #expect(parts.last == .toolCall(AIToolCall(
        id: "call_1",
        name: "fn",
        arguments: #"{"incomplete"#,
        providerMetadata: ["provider": .object(["custom": .object(["key": .string("value")])])]
    )))
}

private func expectInvalidStreamingToolCall(
    message expectedMessage: String,
    operation: () throws -> Void
) {
    do {
        try operation()
        Issue.record("Expected invalid streaming tool call.")
    } catch let error as AIError {
        #expect(error == .invalidResponse(provider: "provider-utils", message: expectedMessage))
    } catch {
        Issue.record("Expected AIError.invalidResponse, got \(error).")
    }
}
