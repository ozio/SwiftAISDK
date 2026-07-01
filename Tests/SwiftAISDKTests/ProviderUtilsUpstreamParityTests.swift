import Testing
@testable import SwiftAISDK

@Test func providerUtilsAsArrayMatchesUpstream() {
    let missingString: String? = nil
    let singleValue: String? = "value"
    let arrayValue: [String]? = ["a", "b"]

    #expect(asArray(missingString).isEmpty)
    #expect(asArray(singleValue) == ["value"])
    #expect(asArray(arrayValue) == ["a", "b"])
}

@Test func providerUtilsFilterNullableMatchesUpstream() {
    #expect(filterNullable(1, nil, 2, nil, 3) == [1, 2, 3])
    #expect(filterNullable(JSONValue.number(0), .bool(false), .string(""), nil) == [0, false, ""])
}

@Test func providerUtilsRemoveNilEntriesMatchesUpstreamRemoveUndefinedEntries() {
    let input: [String: JSONValue?] = [
        "a": false,
        "b": 0,
        "c": "",
        "d": nil,
        "e": nil
    ]

    #expect(removeNilEntries(input) == [
        "a": false,
        "b": 0,
        "c": ""
    ])
    #expect(removeNilEntries([:] as [String: JSONValue?]) == [:])
    #expect(removeNilEntries(["a": nil, "b": nil] as [String: JSONValue?]) == [:])
}

@Test func providerUtilsStripFileExtensionMatchesUpstream() {
    #expect(stripFileExtension("report.pdf") == "report")
    #expect(stripFileExtension("report") == "report")
    #expect(stripFileExtension("archive.tar.gz") == "archive")
    #expect(stripFileExtension("report.") == "report")
}

@Test func providerUtilsGenerateIDLengthAndUniquenessMatchUpstream() {
    #expect(createIdGenerator(size: 10)().count == 10)
    #expect(createIdGenerator()().count == 16)
    #expect(generateId() != generateId())
}

@Test func providerUtilsIsSameOriginMatchesUpstream() {
    #expect(isSameOrigin("https://api.example.com/v1/file", "https://api.example.com"))
    #expect(isSameOrigin("https://api.example.com/a?x=1", "https://api.example.com/b"))
    #expect(!isSameOrigin("https://cdn.evil.com/file", "https://api.example.com"))
    #expect(!isSameOrigin("http://api.example.com/file", "https://api.example.com"))
    #expect(!isSameOrigin("https://api.example.com:8443/file", "https://api.example.com"))
    #expect(!isSameOrigin("not-a-url", "https://api.example.com"))
    #expect(!isSameOrigin("https://api.example.com/file", "not-a-url"))
}

@Test func providerUtilsIsURLSupportedMatchesSpecificWildcardAndTopLevelRules() {
    let example = AISupportedURLPattern { $0 == "https://example.com" }
    let imagePath = AISupportedURLPattern { $0.hasPrefix("https://images.example.com/") }
    let anotherImage = AISupportedURLPattern { $0 == "https://another.com/img.png" }
    let anyDotCom = AISupportedURLPattern { $0 == "https://any.com" }
    let textDotCom = AISupportedURLPattern { $0 == "https://text.com" }

    #expect(!isURLSupported(mediaType: "text/plain", url: "https://example.com", supportedURLs: [:]))
    #expect(isURLSupported(mediaType: "text/plain", url: "https://example.com", supportedURLs: ["text/plain": [example]]))
    #expect(isURLSupported(mediaType: "image/png", url: "https://images.example.com/cat.png", supportedURLs: ["image/png": [imagePath]]))
    #expect(isURLSupported(mediaType: "image/png", url: "https://another.com/img.png", supportedURLs: ["image/png": [imagePath, anotherImage]]))
    #expect(!isURLSupported(mediaType: "text/plain", url: "https://another.com", supportedURLs: ["text/plain": [example]]))
    #expect(!isURLSupported(mediaType: "image/png", url: "https://example.com", supportedURLs: ["text/plain": [example]]))

    #expect(isURLSupported(mediaType: "text/plain", url: "https://example.com", supportedURLs: ["*": [example]]))
    #expect(isURLSupported(mediaType: "image/jpeg", url: "https://images.example.com/dog.jpg", supportedURLs: ["*": [imagePath]]))
    #expect(!isURLSupported(mediaType: "video/mp4", url: "https://another.com", supportedURLs: ["*": [example]]))

    let mixedSupportedURLs = [
        "text/plain": [textDotCom],
        "*": [anyDotCom]
    ]
    #expect(isURLSupported(mediaType: "text/plain", url: "https://text.com", supportedURLs: mixedSupportedURLs))
    #expect(isURLSupported(mediaType: "text/plain", url: "https://any.com", supportedURLs: mixedSupportedURLs))
    #expect(isURLSupported(mediaType: "image/png", url: "https://any.com", supportedURLs: mixedSupportedURLs))
    #expect(!isURLSupported(mediaType: "text/plain", url: "https://other.com", supportedURLs: mixedSupportedURLs))
    #expect(!isURLSupported(mediaType: "image/png", url: "https://other.com", supportedURLs: mixedSupportedURLs))

    #expect(isURLSupported(mediaType: "image/png", url: "https://example.com", supportedURLs: ["image/*": [example]]))
    #expect(isURLSupported(mediaType: "image/png", url: "https://any.com", supportedURLs: ["image/*": [imagePath], "*": [anyDotCom]]))
    #expect(isURLSupported(mediaType: "image", url: "https://images.example.com/cat.png", supportedURLs: ["image/*": [imagePath]]))
    #expect(isURLSupported(mediaType: "image", url: "https://example.com", supportedURLs: ["*": [example]]))
    #expect(!isURLSupported(mediaType: "image", url: "https://images.example.com/cat.png", supportedURLs: ["image/png": [imagePath]]))
    #expect(!isURLSupported(mediaType: "image", url: "https://example.com/audio.mp3", supportedURLs: ["audio/*": [imagePath]]))
}

@Test func providerUtilsIsURLSupportedMatchesEmptyAndCaseRules() {
    #expect(isURLSupported(
        mediaType: "text/plain",
        url: "",
        supportedURLs: ["text/plain": [AISupportedURLPattern { _ in true }]]
    ))
    #expect(!isURLSupported(
        mediaType: "text/plain",
        url: "",
        supportedURLs: ["text/plain": [AISupportedURLPattern { !$0.isEmpty && $0.hasPrefix("https://") }]]
    ))
    #expect(isURLSupported(
        mediaType: "TEXT/PLAIN",
        url: "https://example.com",
        supportedURLs: ["text/plain": [AISupportedURLPattern { $0 == "https://example.com" }]]
    ))
    #expect(isURLSupported(
        mediaType: "text/plain",
        url: "https://EXAMPLE.com/PATH",
        supportedURLs: ["text/plain": [AISupportedURLPattern { $0 == "https://example.com/path" }]]
    ))
    #expect(!isURLSupported(
        mediaType: "text/plain",
        url: "https://example.com",
        supportedURLs: ["text/plain": [], "*": [AISupportedURLPattern { $0 == "https://any.com" }]]
    ))
    #expect(isURLSupported(
        mediaType: "text/plain",
        url: "https://any.com",
        supportedURLs: ["text/plain": [], "*": [AISupportedURLPattern { $0 == "https://any.com" }]]
    ))
}

@Test func providerUtilsCreateToolNameMappingMatchesUpstream() {
    let mapping = createToolNameMapping(
        tools: [
            "custom-computer-tool": [
                "type": "provider",
                "id": "anthropic.computer-use",
                "args": [:] as JSONValue
            ],
            "custom-code-tool": [
                "type": "provider",
                "id": "openai.code-interpreter",
                "args": [:] as JSONValue
            ]
        ],
        providerToolNames: [
            "anthropic.computer-use": "computer_use",
            "openai.code-interpreter": "code_interpreter"
        ]
    )

    #expect(mapping.toProviderToolName("custom-computer-tool") == "computer_use")
    #expect(mapping.toProviderToolName("custom-code-tool") == "code_interpreter")
    #expect(mapping.toCustomToolName("computer_use") == "custom-computer-tool")
    #expect(mapping.toCustomToolName("code_interpreter") == "custom-code-tool")
}

@Test func providerUtilsCreateToolNameMappingFallbacksMatchUpstream() {
    let functionOnly = createToolNameMapping(
        tools: [
            "my-function-tool": [
                "type": "function",
                "description": "A function tool",
                "inputSchema": ["type": "object"] as JSONValue
            ]
        ],
        providerToolNames: [:]
    )
    #expect(functionOnly.toProviderToolName("my-function-tool") == "my-function-tool")
    #expect(functionOnly.toCustomToolName("my-function-tool") == "my-function-tool")

    let unknownProvider = createToolNameMapping(
        tools: [
            "custom-tool": [
                "type": "provider",
                "id": "unknown.tool",
                "args": [:] as JSONValue
            ]
        ],
        providerToolNames: [:]
    )
    #expect(unknownProvider.toProviderToolName("custom-tool") == "custom-tool")
    #expect(unknownProvider.toCustomToolName("unknown-name") == "unknown-name")

    let missingName = createToolNameMapping(
        tools: [
            "custom-computer-tool": [
                "type": "provider",
                "id": "anthropic.computer-use",
                "args": [:] as JSONValue
            ]
        ],
        providerToolNames: ["anthropic.computer-use": "computer_use"]
    )
    #expect(missingName.toProviderToolName("non-existent-tool") == "non-existent-tool")
    #expect(missingName.toCustomToolName("non-existent-provider-tool") == "non-existent-provider-tool")

    let empty = createToolNameMapping(tools: [:], providerToolNames: [:])
    #expect(empty.toProviderToolName("any-tool") == "any-tool")
    #expect(empty.toCustomToolName("any-tool") == "any-tool")
}

@Test func providerUtilsCreateToolNameMappingMixedToolsMatchUpstream() {
    let mapping = createToolNameMapping(
        tools: [
            "function-tool": [
                "type": "function",
                "description": "A function tool",
                "inputSchema": ["type": "object"] as JSONValue
            ],
            "provider-tool": [
                "type": "provider",
                "id": "anthropic.computer-use",
                "args": [:] as JSONValue
            ]
        ],
        providerToolNames: ["anthropic.computer-use": "computer_use"]
    )

    #expect(mapping.toProviderToolName("function-tool") == "function-tool")
    #expect(mapping.toCustomToolName("function-tool") == "function-tool")
    #expect(mapping.toProviderToolName("provider-tool") == "computer_use")
    #expect(mapping.toCustomToolName("computer_use") == "provider-tool")
}

@Test func providerUtilsMapReasoningToProviderEffortMatchesUpstream() {
    let effortMap = [
        "minimal": "low",
        "low": "low",
        "medium": "medium",
        "high": "high",
        "xhigh": "max"
    ]

    var directWarnings: [AIWarning] = []
    #expect(mapReasoningToProviderEffort(reasoning: "medium", effortMap: effortMap, warnings: &directWarnings) == "medium")
    #expect(directWarnings == [])

    var minimalWarnings: [AIWarning] = []
    #expect(mapReasoningToProviderEffort(reasoning: "minimal", effortMap: effortMap, warnings: &minimalWarnings) == "low")
    #expect(minimalWarnings == [
        AIWarning(
            type: "compatibility",
            feature: "reasoning",
            message: #"reasoning "minimal" is not directly supported by this model. mapped to effort "low"."#
        )
    ])

    var xhighWarnings: [AIWarning] = []
    #expect(mapReasoningToProviderEffort(reasoning: "xhigh", effortMap: effortMap, warnings: &xhighWarnings) == "max")
    #expect(xhighWarnings == [
        AIWarning(
            type: "compatibility",
            feature: "reasoning",
            message: #"reasoning "xhigh" is not directly supported by this model. mapped to effort "max"."#
        )
    ])

    var unsupportedWarnings: [AIWarning] = []
    #expect(mapReasoningToProviderEffort(reasoning: "high", effortMap: ["medium": "medium"], warnings: &unsupportedWarnings) == nil)
    #expect(unsupportedWarnings == [
        AIWarning(type: "unsupported", feature: "reasoning", message: #"reasoning "high" is not supported by this model."#)
    ])
}

@Test func providerUtilsIsCustomReasoningMatchesUpstream() {
    #expect(!isCustomReasoning(nil))
    #expect(!isCustomReasoning("provider-default"))
    #expect(isCustomReasoning("none"))
    for value in ["minimal", "low", "medium", "high", "xhigh"] {
        #expect(isCustomReasoning(value))
    }
}

@Test func providerUtilsMapReasoningToProviderBudgetMatchesUpstream() {
    var knownWarnings: [AIWarning] = []
    #expect(mapReasoningToProviderBudget(
        reasoning: "medium",
        maxOutputTokens: 64_000,
        maxReasoningBudget: 64_000,
        warnings: &knownWarnings
    ) == 19_200)
    #expect(knownWarnings == [])

    var capWarnings: [AIWarning] = []
    #expect(mapReasoningToProviderBudget(
        reasoning: "xhigh",
        maxOutputTokens: 64_000,
        maxReasoningBudget: 50_000,
        warnings: &capWarnings
    ) == 50_000)
    #expect(capWarnings == [])

    var floorWarnings: [AIWarning] = []
    #expect(mapReasoningToProviderBudget(
        reasoning: "minimal",
        maxOutputTokens: 10_000,
        maxReasoningBudget: 10_000,
        warnings: &floorWarnings
    ) == 1024)
    #expect(floorWarnings == [])

    var customMinWarnings: [AIWarning] = []
    #expect(mapReasoningToProviderBudget(
        reasoning: "minimal",
        maxOutputTokens: 10_000,
        maxReasoningBudget: 10_000,
        minReasoningBudget: 512,
        warnings: &customMinWarnings
    ) == 512)
    #expect(customMinWarnings == [])

    var customPercentageWarnings: [AIWarning] = []
    #expect(mapReasoningToProviderBudget(
        reasoning: "medium",
        maxOutputTokens: 10_000,
        maxReasoningBudget: 10_000,
        budgetPercentages: ["medium": 0.5],
        warnings: &customPercentageWarnings
    ) == 5000)
    #expect(customPercentageWarnings == [])

    var unsupportedWarnings: [AIWarning] = []
    #expect(mapReasoningToProviderBudget(
        reasoning: "high",
        maxOutputTokens: 64_000,
        maxReasoningBudget: 64_000,
        budgetPercentages: ["medium": 0.5],
        warnings: &unsupportedWarnings
    ) == nil)
    #expect(unsupportedWarnings == [
        AIWarning(type: "unsupported", feature: "reasoning", message: #"reasoning "high" is not supported by this model."#)
    ])
}

@Test func providerUtilsInjectJSONInstructionTextMatchesUpstreamPromptAndSchemaCases() {
    let schema: JSONValue = ["type": "object"]

    #expect(jsonInstructionText(
        prompt: "Generate a person",
        schema: schema,
        instruction: .automatic
    ) == """
    Generate a person

    JSON schema:
    {"type":"object"}
    You MUST answer with a JSON object that matches the JSON schema above.
    """)

    #expect(jsonInstructionText(
        prompt: "Generate a person",
        schema: nil,
        instruction: .automatic
    ) == """
    Generate a person

    You MUST answer with JSON.
    """)

    #expect(jsonInstructionText(
        prompt: nil,
        schema: schema,
        instruction: .automatic
    ) == """
    JSON schema:
    {"type":"object"}
    You MUST answer with a JSON object that matches the JSON schema above.
    """)

    #expect(jsonInstructionText(prompt: nil, schema: nil, instruction: .automatic) == "You MUST answer with JSON.")
}

@Test func providerUtilsInjectJSONInstructionTextMatchesUpstreamCustomAndEmptyCases() {
    #expect(jsonInstructionText(
        prompt: "Generate a person",
        schema: ["type": "object"],
        instruction: AIJSONInstruction(schemaPrefix: "Custom prefix:", schemaSuffix: "Custom suffix")
    ) == """
    Generate a person

    Custom prefix:
    {"type":"object"}
    Custom suffix
    """)

    #expect(jsonInstructionText(
        prompt: "",
        schema: ["type": "object"],
        instruction: .automatic
    ) == """
    JSON schema:
    {"type":"object"}
    You MUST answer with a JSON object that matches the JSON schema above.
    """)

    #expect(jsonInstructionText(
        prompt: "Generate something",
        schema: [:] as JSONValue,
        instruction: .automatic
    ) == """
    Generate something

    JSON schema:
    {}
    You MUST answer with a JSON object that matches the JSON schema above.
    """)
}

@Test func providerUtilsInjectJSONInstructionTextMatchesUpstreamStructuredSchemaCases() {
    let basicSchema: JSONValue = [
        "type": "object",
        "properties": [
            "name": ["type": "string"],
            "age": ["type": "number"]
        ],
        "required": ["name", "age"]
    ]
    let basicText = jsonInstructionText(
        prompt: "Generate a person",
        schema: basicSchema,
        instruction: .automatic
    )
    #expect(basicText.hasPrefix("Generate a person\n\nJSON schema:\n"))
    #expect(basicText.hasSuffix("\nYou MUST answer with a JSON object that matches the JSON schema above."))
    #expect(try! injectedInstructionSchema(from: basicText) == basicSchema)

    let complexSchema: JSONValue = [
        "type": "object",
        "properties": [
            "person": [
                "type": "object",
                "properties": [
                    "name": ["type": "string"],
                    "age": ["type": "number"],
                    "address": [
                        "type": "object",
                        "properties": [
                            "street": ["type": "string"],
                            "city": ["type": "string"]
                        ]
                    ]
                ]
            ]
        ]
    ]
    let complexText = jsonInstructionText(
        prompt: "Generate a complex person",
        schema: complexSchema,
        instruction: .automatic
    )
    #expect(complexText.hasPrefix("Generate a complex person\n\nJSON schema:\n"))
    #expect(complexText.hasSuffix("\nYou MUST answer with a JSON object that matches the JSON schema above."))
    #expect(try! injectedInstructionSchema(from: complexText) == complexSchema)

    let specialSchema: JSONValue = [
        "type": "object",
        "properties": [
            "special@property": ["type": "string"],
            "emoji\u{1F60A}": ["type": "string"]
        ]
    ]
    let specialText = jsonInstructionText(
        prompt: nil,
        schema: specialSchema,
        instruction: .automatic
    )
    #expect(specialText.hasPrefix("JSON schema:\n"))
    #expect(specialText.hasSuffix("\nYou MUST answer with a JSON object that matches the JSON schema above."))
    #expect(try! injectedInstructionSchema(from: specialText) == specialSchema)
}

@Test func providerUtilsInjectJSONInstructionTextMatchesUpstreamLongPromptAndSchemaCase() {
    var properties: [String: JSONValue] = [:]
    for index in 0..<100 {
        properties["prop\(index)"] = ["type": "string"]
    }
    let schema: JSONValue = [
        "type": "object",
        "properties": .object(properties)
    ]
    let longPrompt = String(repeating: "A", count: 1_000)
    let text = jsonInstructionText(
        prompt: longPrompt,
        schema: schema,
        instruction: .automatic
    )
    #expect(text.hasPrefix("\(longPrompt)\n\nJSON schema:\n"))
    #expect(text.hasSuffix("\nYou MUST answer with a JSON object that matches the JSON schema above."))
    #expect(try! injectedInstructionSchema(from: text) == schema)
}

@Test func providerUtilsInjectJSONInstructionIntoMessagesMatchesUpstreamSystemCases() {
    let schema: JSONValue = ["type": "object"]
    let original = [
        AIMessage.system("Generate a person"),
        AIMessage.user("Return JSON.")
    ]

    let result = injectJSONInstruction(into: original, schema: schema, instruction: .automatic)

    #expect(result[0].role == .system)
    #expect(result[0].combinedText == """
    Generate a person

    JSON schema:
    {"type":"object"}
    You MUST answer with a JSON object that matches the JSON schema above.
    """)
    #expect(result[1] == .user("Return JSON."))
    #expect(original[0] == .system("Generate a person"))
}

@Test func providerUtilsInjectJSONInstructionIntoMessagesMatchesUpstreamMissingSystemCases() {
    let schema: JSONValue = ["type": "object"]

    let emptyResult = injectJSONInstruction(into: [], schema: schema, instruction: .automatic)
    #expect(emptyResult == [
        AIMessage.system("""
        JSON schema:
        {"type":"object"}
        You MUST answer with a JSON object that matches the JSON schema above.
        """)
    ])

    let noSystem = injectJSONInstruction(
        into: [.user("Hello"), .assistant("Hi there")],
        schema: schema,
        instruction: .automatic
    )
    #expect(noSystem[0].role == .system)
    #expect(noSystem[0].combinedText == """
    JSON schema:
    {"type":"object"}
    You MUST answer with a JSON object that matches the JSON schema above.
    """)
    #expect(noSystem.dropFirst() == [.user("Hello"), .assistant("Hi there")])

    let emptySystem = injectJSONInstruction(
        into: [.system(""), .user("Generate data")],
        schema: schema,
        instruction: .automatic
    )
    #expect(emptySystem[0].combinedText == """
    JSON schema:
    {"type":"object"}
    You MUST answer with a JSON object that matches the JSON schema above.
    """)
    #expect(emptySystem[1] == .user("Generate data"))
}

@Test func providerUtilsInjectJSONInstructionIntoMessagesMatchesUpstreamNoSchemaAndCustomSuffixCases() {
    let noSchema = injectJSONInstruction(into: [.system("Generate data")], schema: nil, instruction: .automatic)
    #expect(noSchema == [
        AIMessage.system("""
        Generate data

        You MUST answer with JSON.
        """)
    ])

    let custom = injectJSONInstruction(
        into: [.system("Generate data")],
        schema: ["type": "object"],
        instruction: AIJSONInstruction(schemaPrefix: "Custom schema:", schemaSuffix: "Follow this format exactly.")
    )
    #expect(custom == [
        AIMessage.system("""
        Generate data

        Custom schema:
        {"type":"object"}
        Follow this format exactly.
        """)
    ])
}

private func injectedInstructionSchema(from text: String) throws -> JSONValue {
    let prefix = "JSON schema:\n"
    let suffix = "\nYou MUST answer with a JSON object that matches the JSON schema above."
    guard let prefixRange = text.range(of: prefix),
          let suffixRange = text.range(of: suffix, options: .backwards),
          prefixRange.upperBound <= suffixRange.lowerBound else {
        throw AIError.invalidArgument(argument: "text", message: "Missing injected JSON schema.")
    }
    return try parseJSON(String(text[prefixRange.upperBound..<suffixRange.lowerBound]))
}

@Test func providerUtilsExtractLinesMatchesUpstreamRangeAndDefaultCases() {
    #expect(extractLines(text: "a\nb\nc") == "a\nb\nc")
    #expect(extractLines(text: "a\nb\nc\nd", startLine: 2, endLine: 3) == "b\nc")
    #expect(extractLines(text: "a\nb\nc", startLine: 2, endLine: 99) == "b\nc")
    #expect(extractLines(text: "a\nb\nc", endLine: 2) == "a\nb")
    #expect(extractLines(text: "a\nb\nc", startLine: 2) == "b\nc")
    #expect(extractLines(text: "one-liner", startLine: 1, endLine: 1) == "one-liner")
}

@Test func providerUtilsExtractLinesPreservesDetectedLineEndingsLikeUpstream() {
    #expect(extractLines(text: "a\r\nb\r\nc\r\nd", startLine: 2, endLine: 3) == "b\r\nc")
    #expect(extractLines(text: "a\rb\rc\rd", startLine: 2, endLine: 3) == "b\rc")
}

@Test func providerUtilsDelayResolvesImmediateAndZeroDurationsLikeUpstream() async throws {
    try await delay(nil)
    try await delay(0)
    try await delay(-100)
}

@Test func providerUtilsDelayRejectsAlreadyAbortedSignalLikeUpstream() async throws {
    let controller = AIAbortController()
    controller.abort(reason: "Delay was aborted")

    do {
        try await delay(1_000, abortSignal: controller.signal)
        Issue.record("Expected delay to throw AIAbortError.")
    } catch let error as AIAbortError {
        #expect(error.reason == "Delay was aborted")
    }
}

@Test func providerUtilsDelayRejectsWhenSignalAbortsDuringDelayLikeUpstream() async throws {
    let controller = AIAbortController()
    let task = Task {
        try await delay(5_000, abortSignal: controller.signal)
    }

    try await Task.sleep(nanoseconds: 10_000_000)
    controller.abort(reason: "Delay was aborted")

    do {
        try await task.value
        Issue.record("Expected delay task to throw AIAbortError.")
    } catch let error as AIAbortError {
        #expect(error.reason == "Delay was aborted")
    }
}

@Test func providerUtilsDelayedPromiseResolvesAndRejectsAfterAccessLikeUpstream() async throws {
    let resolved = AIDelayedPromise<String>()
    #expect(resolved.isPending)
    resolved.resolve("success")
    #expect(resolved.isResolved)
    #expect(try await resolved.value() == "success")
    #expect(try await resolved.value() == "success")

    let rejected = AIDelayedPromise<String>()
    rejected.reject(AIError.invalidArgument(argument: "test", message: "failure"))
    #expect(rejected.isRejected)
    do {
        _ = try await rejected.value()
        Issue.record("Expected delayed promise rejection.")
    } catch {
        #expect(String(describing: error).contains("failure"))
    }
}

@Test func providerUtilsDelayedPromiseBlocksUntilResolvedLikeUpstream() async throws {
    let delayed = AIDelayedPromise<String>()
    let task = Task {
        try await delayed.value()
    }

    try await Task.sleep(nanoseconds: 10_000_000)
    #expect(delayed.isPending)

    delayed.resolve("delayed-success")
    #expect(try await task.value == "delayed-success")
    #expect(delayed.isResolved)
}

@Test func providerUtilsDelayedPromiseBlocksUntilRejectedLikeUpstream() async throws {
    let delayed = AIDelayedPromise<String>()
    let task = Task {
        try await delayed.value()
    }

    try await Task.sleep(nanoseconds: 10_000_000)
    #expect(delayed.isPending)

    delayed.reject(AIError.invalidArgument(argument: "test", message: "delayed-failure"))
    do {
        _ = try await task.value
        Issue.record("Expected delayed promise rejection.")
    } catch {
        #expect(String(describing: error).contains("delayed-failure"))
    }
    #expect(delayed.isRejected)
}

@Test func providerUtilsDelayedPromiseResolvesAllPendingWaitersLikeUpstream() async throws {
    let delayed = AIDelayedPromise<String>()
    let first = Task { try await delayed.value() }
    let second = Task { try await delayed.value() }

    try await Task.sleep(nanoseconds: 10_000_000)
    #expect(delayed.isPending)

    delayed.resolve("success")

    let firstValue = try await first.value
    let secondValue = try await second.value
    #expect([firstValue, secondValue] == ["success", "success"])
}
