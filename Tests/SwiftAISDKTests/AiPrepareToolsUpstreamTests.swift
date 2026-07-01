import Foundation
import Testing
@testable import SwiftAISDK

private let emptyObjectSchema: JSONValue = [
    "$schema": "http://json-schema.org/draft-07/schema#",
    "additionalProperties": false,
    "properties": .object([:]),
    "type": "object"
]

private let cityObjectSchema: JSONValue = [
    "$schema": "http://json-schema.org/draft-07/schema#",
    "additionalProperties": false,
    "properties": ["city": ["type": "string"]],
    "required": ["city"],
    "type": "object"
]

private func mockExecutableTools() -> [AITool] {
    [
        AITool(
            name: "tool1",
            description: "Tool 1 description",
            parameters: emptyObjectSchema,
            execute: { _ in .null }
        ),
        AITool(
            name: "tool2",
            description: "Tool 2 description",
            parameters: cityObjectSchema,
            execute: { _ in .null }
        )
    ]
}

private var mockFunctionTools: [String: JSONValue] {
    toolsDictionary(from: mockExecutableTools())
}

private let mockProviderDefinedTool: JSONValue = [
    "type": "provider",
    "id": "provider.tool-id",
    "args": ["key": "value"]
]

@Test func aiPrepareToolsReturnsNilWhenToolsAreNotProvidedLikeUpstream() {
    #expect(prepareTools(tools: nil) == nil)
    #expect(prepareTools(tools: [:]) == nil)
}

@Test func aiPrepareToolsReturnsAllFunctionToolsLikeUpstream() throws {
    let result = try #require(prepareTools(tools: mockFunctionTools))
    let byName = Dictionary(uniqueKeysWithValues: result.map { tool in
        (tool["name"]?.stringValue ?? "", tool)
    })

    #expect(byName["tool1"] == [
        "type": "function",
        "name": "tool1",
        "description": "Tool 1 description",
        "inputSchema": emptyObjectSchema
    ])
    #expect(byName["tool2"] == [
        "type": "function",
        "name": "tool2",
        "description": "Tool 2 description",
        "inputSchema": cityObjectSchema
    ])
}

@Test func aiPrepareToolsHandlesProviderDefinedToolsLikeUpstream() throws {
    var tools = mockFunctionTools
    tools["providerTool"] = mockProviderDefinedTool

    let result = try #require(prepareTools(tools: tools))
    let providerTool = try #require(result.first { $0["name"]?.stringValue == "providerTool" })

    #expect(providerTool == [
        "type": "provider",
        "name": "providerTool",
        "id": "provider.tool-id",
        "args": ["key": "value"]
    ])
}

@Test func aiPrepareToolsOrdersPartialToolOrderAndAppendsOmittedToolsAlphabeticallyLikeUpstream() throws {
    let tools: [String: JSONValue] = [
        "zebra": AITool(name: "zebra", description: "Zebra tool", parameters: emptyObjectSchema, execute: { _ in .null }).schema,
        "alpha": AITool(name: "alpha", description: "Alpha tool", parameters: emptyObjectSchema, execute: { _ in .null }).schema,
        "providerTool": mockProviderDefinedTool,
        "middle": AITool(name: "middle", description: "Middle tool", parameters: emptyObjectSchema, execute: { _ in .null }).schema
    ]

    let result = try #require(prepareTools(tools: tools, toolOrder: ["middle"]))

    #expect(result.compactMap { $0["name"]?.stringValue } == ["middle", "alpha", "providerTool", "zebra"])
}

@Test func aiPrepareToolsPreservesToolOrderBeforeSortingRemainingToolsLikeUpstream() throws {
    let tools: [String: JSONValue] = [
        "zebra": AITool(name: "zebra", description: "Zebra tool", parameters: emptyObjectSchema, execute: { _ in .null }).schema,
        "alpha": AITool(name: "alpha", description: "Alpha tool", parameters: emptyObjectSchema, execute: { _ in .null }).schema,
        "middle": AITool(name: "middle", description: "Middle tool", parameters: emptyObjectSchema, execute: { _ in .null }).schema
    ]

    let result = try #require(prepareTools(tools: tools, toolOrder: ["zebra", "middle"]))

    #expect(result.compactMap { $0["name"]?.stringValue } == ["zebra", "middle", "alpha"])
}

@Test func aiPrepareToolsDoesNotDuplicateDuplicateToolOrderNamesLikeUpstream() throws {
    let result = try #require(prepareTools(tools: mockFunctionTools, toolOrder: ["tool2", "tool2"]))

    #expect(result.compactMap { $0["name"]?.stringValue } == ["tool2", "tool1"])
}

@Test func aiPrepareToolsPassesThroughProviderOptionsLikeUpstream() throws {
    let tool = AITool(
        name: "tool1",
        description: "Tool 1 description",
        parameters: emptyObjectSchema,
        providerOptions: ["aProvider": ["aSetting": "aValue"]],
        execute: { _ in .null }
    )

    let result = try #require(prepareTools(tools: toolsDictionary(from: [tool])))
    let prepared = try #require(result.first)

    #expect(prepared["providerOptions"] == ["aProvider": ["aSetting": "aValue"]])
    #expect(prepared["inputSchema"] == emptyObjectSchema)
}

@Test func aiPrepareToolsPassesThroughStrictModeSettingsLikeUpstream() throws {
    let tool = AITool(
        name: "tool1",
        description: "Tool 1 description",
        parameters: emptyObjectSchema,
        strict: true,
        execute: { _ in .null }
    )

    let result = try #require(prepareTools(tools: toolsDictionary(from: [tool])))
    let prepared = try #require(result.first)

    #expect(prepared["strict"] == true)
    #expect(prepared["inputSchema"] == emptyObjectSchema)
}

@Test func aiPrepareToolsPassesThroughInputExamplesLikeUpstream() throws {
    let tool = AITool(
        name: "tool1",
        description: "Tool 1 description",
        parameters: cityObjectSchema,
        inputExamples: [["input": ["city": "New York"]]],
        execute: { _ in .null }
    )

    let result = try #require(prepareTools(tools: toolsDictionary(from: [tool])))
    let prepared = try #require(result.first)

    #expect(prepared["inputExamples"] == [["input": ["city": "New York"]]])
    #expect(prepared["inputSchema"] == cityObjectSchema)
}

@Test func aiPrepareToolsSupportsResolvedDynamicDescriptionsLikeUpstream() throws {
    let userName = "Ada"
    let sandboxDescription = "test-sandbox"
    let contextual = AITool.dynamic(
        name: "contextual",
        description: "User is \(userName)",
        parameters: emptyObjectSchema,
        execute: { _ in .null }
    )
    let withSandbox = AITool.dynamic(
        name: "withSandbox",
        description: "Env: \(sandboxDescription)",
        parameters: emptyObjectSchema,
        execute: { _ in .null }
    )

    let result = try #require(prepareTools(tools: toolsDictionary(from: [contextual, withSandbox])))
    let byName = Dictionary(uniqueKeysWithValues: result.map { tool in
        (tool["name"]?.stringValue ?? "", tool["description"]?.stringValue)
    })

    #expect(byName["contextual"] == "User is Ada")
    #expect(byName["withSandbox"] == "Env: test-sandbox")
}
