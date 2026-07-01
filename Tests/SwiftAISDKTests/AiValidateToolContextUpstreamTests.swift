import Foundation
import Testing
@testable import SwiftAISDK

private let validateToolContextSchema: JSONValue = [
    "type": "object",
    "properties": [
        "apiKey": ["type": "string"]
    ],
    "required": ["apiKey"]
]

@Test func aiValidateToolContextReturnsContextAsIsWhenNoSchemaIsDefinedLikeUpstream() throws {
    let toolContext: JSONValue = ["apiKey": 123]

    let result = try validateToolContext(
        toolName: "weather",
        context: toolContext,
        contextSchema: nil
    )

    #expect(result == toolContext)
}

@Test func aiValidateToolContextReturnsValidatedContextWhenSchemaMatchesLikeUpstream() throws {
    let result = try validateToolContext(
        toolName: "weather",
        context: ["apiKey": "secret"],
        contextSchema: validateToolContextSchema
    )

    #expect(result == ["apiKey": "secret"])
}

@Test func aiValidateToolContextThrowsTypeValidationErrorWhenSchemaFailsLikeUpstream() throws {
    let toolContext: JSONValue = ["apiKey": 123]

    do {
        _ = try validateToolContext(
            toolName: "weather",
            context: toolContext,
            contextSchema: validateToolContextSchema
        )
        Issue.record("Expected validateToolContext to throw.")
    } catch let error as AITypeValidationError {
        #expect(error.value == toolContext)
        #expect(error.context == AITypeValidationContext(
            field: "tool context",
            entityName: "weather"
        ))
    }
}
