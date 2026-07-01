import Foundation
import Testing
@testable import SwiftAISDK

private let filterActiveEmptyObjectSchema: JSONValue = [
    "$schema": "http://json-schema.org/draft-07/schema#",
    "additionalProperties": false,
    "properties": .object([:]),
    "type": "object"
]

private let filterActiveCityObjectSchema: JSONValue = [
    "$schema": "http://json-schema.org/draft-07/schema#",
    "additionalProperties": false,
    "properties": ["city": ["type": "string"]],
    "required": ["city"],
    "type": "object"
]

private let filterActiveProviderDefinedTool: JSONValue = [
    "type": "provider",
    "id": "provider.tool-id",
    "args": ["key": "value"]
]

private var filterActiveMockTools: [String: JSONValue] {
    toolsDictionary(from: [
        AITool(
            name: "tool1",
            description: "Tool 1 description",
            parameters: filterActiveEmptyObjectSchema,
            execute: { _ in .null }
        ),
        AITool(
            name: "tool2",
            description: "Tool 2 description",
            parameters: filterActiveCityObjectSchema,
            execute: { _ in .null }
        )
    ])
}

private var filterActiveMockToolsWithProviderDefined: [String: JSONValue] {
    var tools = filterActiveMockTools
    tools["providerTool"] = filterActiveProviderDefinedTool
    return tools
}

@Test func aiFilterActiveToolsReturnsNilWhenToolsAreNotProvidedLikeUpstream() {
    let result = filterActiveTools(
        tools: nil,
        activeTools: ["tool1"]
    )

    #expect(result == nil)
}

@Test func aiFilterActiveToolsReturnsAllToolsWhenActiveToolsAreNotProvidedLikeUpstream() throws {
    let result = try #require(filterActiveTools(
        tools: filterActiveMockToolsWithProviderDefined,
        activeTools: nil
    ))

    #expect(result == filterActiveMockToolsWithProviderDefined)
}

@Test func aiFilterActiveToolsReturnsNoToolsWhenActiveToolsAreEmptyLikeUpstream() throws {
    let result = try #require(filterActiveTools(
        tools: filterActiveMockToolsWithProviderDefined,
        activeTools: []
    ))

    #expect(result == [:])
}

@Test func aiFilterActiveToolsFiltersToolsBasedOnActiveToolsLikeUpstream() throws {
    let result = try #require(filterActiveTools(
        tools: filterActiveMockToolsWithProviderDefined,
        activeTools: ["tool1", "providerTool"]
    ))

    #expect(result == [
        "tool1": filterActiveMockTools["tool1"],
        "providerTool": filterActiveProviderDefinedTool
    ])
}
