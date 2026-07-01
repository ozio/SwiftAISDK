import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiStandardizePromptThrowsWhenMessagesContainSystemMessageByDefaultLikeUpstream() throws {
    #expect(throws: AIError.invalidArgument(
        argument: "messages",
        message: "System messages are not allowed in the prompt or messages fields. Use the instructions option instead."
    )) {
        _ = try standardizePrompt(messages: [.system("INSTRUCTIONS")])
    }
}

@Test func aiStandardizePromptAllowsSystemMessagesWhenConfiguredLikeUpstream() throws {
    let result = try standardizePrompt(
        allowSystemInMessages: true,
        messages: [.system("INSTRUCTIONS"), .user("Hello, world!")]
    )

    #expect(result.instructions == nil)
    #expect(result.messages == [.system("INSTRUCTIONS"), .user("Hello, world!")])
}

@Test func aiStandardizePromptThrowsWhenAllowedSystemMessageHasPartsLikeUpstream() throws {
    let systemWithParts = AIMessage(role: .system, content: [
        .text("INSTRUCTIONS"),
        .imageURL("https://example.com/image.png")
    ])

    #expect(throws: AIError.invalidArgument(
        argument: "messages",
        message: "The messages do not match the ModelMessage[] schema."
    )) {
        _ = try standardizePrompt(allowSystemInMessages: true, messages: [systemWithParts])
    }
}

@Test func aiStandardizePromptThrowsWhenMessagesArrayIsEmptyLikeUpstream() throws {
    #expect(throws: AIError.invalidArgument(argument: "messages", message: "messages must not be empty")) {
        _ = try standardizePrompt(messages: [])
    }
}

@Test func aiStandardizePromptSupportsSystemModelMessageInstructionsLikeUpstream() throws {
    let result = try standardizePrompt(
        instructions: [.system("INSTRUCTIONS")],
        prompt: "Hello, world!"
    )

    #expect(result.instructions == [.system("INSTRUCTIONS")])
    #expect(result.messages == [.user("Hello, world!")])
}

@Test func aiStandardizePromptSupportsArrayOfSystemInstructionsLikeUpstream() throws {
    let result = try standardizePrompt(
        instructions: [.system("INSTRUCTIONS"), .system("INSTRUCTIONS 2")],
        prompt: "Hello, world!"
    )

    #expect(result.instructions == [.system("INSTRUCTIONS"), .system("INSTRUCTIONS 2")])
    #expect(result.messages == [.user("Hello, world!")])
}

@Test func aiStandardizePromptFallsBackToSystemWhenInstructionsAreMissingLikeUpstream() throws {
    let result = try standardizePrompt(system: "SYSTEM", prompt: "Hello, world!")

    #expect(result.instructions == [.system("SYSTEM")])
    #expect(result.messages == [.user("Hello, world!")])
}

@Test func aiStandardizePromptPrefersInstructionsOverSystemLikeUpstream() throws {
    let result = try standardizePrompt(
        system: "SYSTEM",
        instructions: [.system("INSTRUCTIONS")],
        prompt: "Hello, world!"
    )

    #expect(result.instructions == [.system("INSTRUCTIONS")])
    #expect(result.messages == [.user("Hello, world!")])
}

@Test func aiStandardizePromptRejectsMissingAndConflictingPromptSourcesLikeUpstream() throws {
    #expect(throws: AIError.invalidArgument(argument: "prompt", message: "prompt or messages must be defined")) {
        _ = try standardizePrompt()
    }
    #expect(throws: AIError.invalidArgument(argument: "prompt", message: "prompt and messages cannot be defined at the same time")) {
        _ = try standardizePrompt(prompt: "Hello", messages: [.user("Hi")])
    }
}

@Test func aiStandardizePromptRejectsNonSystemInstructionsLikeUpstream() throws {
    #expect(throws: AIError.invalidArgument(
        argument: "instructions",
        message: "instructions must be a string, SystemModelMessage, or array of SystemModelMessage"
    )) {
        _ = try standardizePrompt(instructions: [.user("not system")], prompt: "Hello")
    }
}
