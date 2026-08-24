import Foundation
import Testing
@testable import SwiftAISDK

@Test func googleUpstreamPrimitiveEnumsUseOpenAPIEnumEncoding() throws {
    let schema: JSONValue = [
        "type": "object",
        "properties": [
            "numberValue": ["type": "number", "const": 15],
            "integerValue": ["type": "integer", "enum": [1, 2]],
            "booleanValue": ["type": "boolean", "const": true],
            "nullValue": ["const": nil]
        ]
    ]

    let converted = try googleOpenAPISchema(from: schema, isRoot: true)

    #expect(converted == [
        "type": "object",
        "properties": [
            "numberValue": ["type": "number", "format": "enum", "enum": ["15"]],
            "integerValue": ["type": "integer", "format": "enum", "enum": ["1", "2"]],
            "booleanValue": ["type": "boolean", "format": "enum", "enum": ["true"]],
            "nullValue": ["type": "null"]
        ]
    ])
}

@Test func googleUpstreamPrimitiveEnumsInferTypesAndNullability() throws {
    let schema: JSONValue = [
        "type": "object",
        "properties": [
            "nullableString": ["type": ["string", "null"], "enum": ["a", "b"]],
            "nullableNumber": ["type": ["number", "null"], "enum": [1, 2]],
            "nullableBoolean": ["type": ["boolean", "null"], "enum": [true, nil]],
            "untypedNumber": ["enum": [1, 2]],
            "untypedBoolean": ["enum": [true, false]]
        ]
    ]

    let converted = try googleOpenAPISchema(from: schema, isRoot: true)

    #expect(converted == [
        "type": "object",
        "properties": [
            "nullableString": ["type": "string", "nullable": true, "enum": ["a", "b"]],
            "nullableNumber": ["type": "number", "nullable": true, "format": "enum", "enum": ["1", "2"]],
            "nullableBoolean": ["type": "boolean", "nullable": true, "format": "enum", "enum": ["true"]],
            "untypedNumber": ["type": "number", "format": "enum", "enum": ["1", "2"]],
            "untypedBoolean": ["type": "boolean", "format": "enum", "enum": ["true", "false"]]
        ]
    ])
}

@Test func googleUpstreamPrimitiveEnumsRejectMixedValues() {
    #expect(throws: AIError.invalidArgument(
        argument: "schema",
        message: "Google does not support this JSON Schema enum. Enum values must share one supported primitive type and match the schema type."
    )) {
        _ = try googleOpenAPISchema(from: ["enum": ["text", 1]], isRoot: true)
    }
}

@Test func googleUpstreamMixedEnumFailurePropagatesBeforeRequest() async throws {
    let transport = RecordingTransport(response: jsonResponse("{}"))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-3.7-flash")
    let expected = AIError.invalidArgument(
        argument: "schema",
        message: "Google does not support this JSON Schema enum. Enum values must share one supported primitive type and match the schema type."
    )

    await #expect(throws: expected) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Return structured output.")],
            responseFormat: .json(schema: ["enum": ["text", 1]])
        ))
    }
    #expect(await transport.requests().isEmpty)
}

@Test func googleUpstreamStrictForcedToolChoicesUseAnyMode() throws {
    let tools: [String: JSONValue] = [
        "createMeeting": [
            "type": "object",
            "properties": ["title": ["type": "string"]],
            "required": ["title"]
        ],
        "getWeather": [
            "type": "object",
            "strict": true,
            "properties": ["city": ["type": "string"]],
            "required": ["city"]
        ]
    ]

    let required = try googlePrepareTools(
        from: tools,
        toolChoice: ["type": "required"],
        modelID: "gemini-3.7-flash",
        isVertexProvider: false
    )
    let named = try googlePrepareTools(
        from: tools,
        toolChoice: ["type": "tool", "toolName": "createMeeting"],
        modelID: "gemini-3.7-flash",
        isVertexProvider: false
    )
    let automatic = try googlePrepareTools(
        from: tools,
        toolChoice: ["type": "auto"],
        modelID: "gemini-3.7-flash",
        isVertexProvider: false
    )

    #expect(required?.toolConfig?["functionCallingConfig"]?["mode"]?.stringValue == "ANY")
    #expect(named?.toolConfig?["functionCallingConfig"]?["mode"]?.stringValue == "ANY")
    #expect(named?.toolConfig?["functionCallingConfig"]?["allowedFunctionNames"]?[0]?.stringValue == "createMeeting")
    #expect(automatic?.toolConfig?["functionCallingConfig"]?["mode"]?.stringValue == "VALIDATED")
}

@Test func googleUpstreamPreservesDetailedRetryInfoInAPICallError() async throws {
    let errorBody = """
    {
      "error": {
        "code": 429,
        "message": "You exceeded your current quota, please check your plan.",
        "status": "RESOURCE_EXHAUSTED",
        "details": [
          {"@type":"type.googleapis.com/google.rpc.QuotaFailure"},
          {"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"34.4s"}
        ]
      }
    }
    """
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 429,
        headers: ["content-type": "application/json"],
        body: Data(errorBody.utf8)
    ))
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.languageModel("gemini-3.7-flash")

    do {
        _ = try await model.generate(LanguageModelRequest(messages: [.user("Retry?")]))
        Issue.record("Expected a Google API call error.")
    } catch let error as AIError {
        guard case let .apiCall(apiError) = error else {
            Issue.record("Expected AIError.apiCall, got \(error).")
            return
        }
        let data = try secureJSONParse(apiError.responseBody)
        #expect(apiError.statusCode == 429)
        #expect(data["error"]?["details"]?[0]?["@type"]?.stringValue == "type.googleapis.com/google.rpc.QuotaFailure")
        #expect(data["error"]?["details"]?[1]?["@type"]?.stringValue == "type.googleapis.com/google.rpc.RetryInfo")
        #expect(data["error"]?["details"]?[1]?["retryDelay"]?.stringValue == "34.4s")
    }
}

@Test func googleUpstreamInlinesDirectAndNestedRootSchemaReferences() throws {
    let schema: JSONValue = [
        "type": "object",
        "properties": [
            "settings": [
                "$ref": "#/$defs/Settings",
                "description": "Formatting settings"
            ],
            "legacyLocale": ["$ref": "#/definitions/LegacyLocale"]
        ],
        "required": ["settings"],
        "$defs": [
            "Locale": ["type": "string", "enum": ["de", "en"]],
            "Settings": [
                "type": "object",
                "properties": ["locale": ["$ref": "#/$defs/Locale"]],
                "required": ["locale"]
            ]
        ],
        "definitions": [
            "LegacyLocale": ["type": "string", "enum": ["ja", "en"]]
        ]
    ]

    #expect(try googleOpenAPISchema(from: schema, isRoot: true) == [
        "type": "object",
        "properties": [
            "settings": [
                "type": "object",
                "properties": [
                    "locale": ["type": "string", "enum": ["de", "en"]]
                ],
                "required": ["locale"],
                "description": "Formatting settings"
            ],
            "legacyLocale": ["type": "string", "enum": ["ja", "en"]]
        ],
        "required": ["settings"]
    ])

    let rootReference: JSONValue = [
        "type": "object",
        "$ref": "#/$defs/Parameters",
        "$defs": [
            "Parameters": [
                "type": "object",
                "properties": ["value": ["type": "string"]]
            ]
        ]
    ]
    #expect(try googleOpenAPISchema(from: rootReference, isRoot: true) == [
        "type": "object",
        "properties": ["value": ["type": "string"]]
    ])

    let falseReference: JSONValue = [
        "$ref": "#/$defs/Disabled",
        "$defs": ["Disabled": false]
    ]
    #expect(try googleOpenAPISchema(from: falseReference, isRoot: true) == [
        "type": "boolean",
        "properties": [:]
    ])
}

@Test func googleUpstreamRejectsUnsupportedMissingAndRecursiveSchemaReferences() {
    #expect(throws: AIError.invalidArgument(
        argument: "schema",
        message: "Google schema conversion only supports references to direct children of root-level $defs or definitions. Unsupported reference: #/properties/value"
    )) {
        _ = try googleOpenAPISchema(from: ["$ref": "#/properties/value"], isRoot: true)
    }

    #expect(throws: AIError.invalidArgument(
        argument: "schema",
        message: "Google schema conversion only supports references to direct children of root-level $defs or definitions. Unsupported reference: #/$defs/Missing"
    )) {
        _ = try googleOpenAPISchema(from: ["$ref": "#/$defs/Missing"], isRoot: true)
    }

    let recursiveSchema: JSONValue = [
        "type": "object",
        "properties": ["node": ["$ref": "#/$defs/Node"]],
        "$defs": [
            "Node": [
                "type": "object",
                "properties": ["child": ["$ref": "#/$defs/Node"]]
            ]
        ]
    ]
    #expect(throws: AIError.invalidArgument(
        argument: "schema",
        message: "Google schema conversion does not support recursive JSON Schema references."
    )) {
        _ = try googleOpenAPISchema(from: recursiveSchema, isRoot: true)
    }
}

@Test func googleAndVertexUpstreamInlineLocalReferencesInRequests() async throws {
    let response = jsonResponse("""
    {"candidates":[{"content":{"parts":[{"text":"Done"}],"role":"model"},"finishReason":"STOP","index":0}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":1,"totalTokenCount":2}}
    """)
    let toolSchema: JSONValue = [
        "type": "object",
        "description": "Format a date",
        "properties": [
            "locale": [
                "$ref": "#/$defs/Locale",
                "description": "Locale for formatting"
            ]
        ],
        "required": ["locale"],
        "$defs": [
            "Locale": ["type": "string", "enum": ["de", "en"]]
        ]
    ]
    let expectedParameters: JSONValue = [
        "type": "object",
        "description": "Format a date",
        "properties": [
            "locale": [
                "type": "string",
                "enum": ["de", "en"],
                "description": "Locale for formatting"
            ]
        ],
        "required": ["locale"]
    ]

    let googleTransport = RecordingTransport(response: response)
    let google = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: googleTransport))
    _ = try await google.languageModel("gemini-2.5-flash").generate(LanguageModelRequest(
        messages: [.user("Format it.")],
        tools: ["formatDate": toolSchema]
    ))
    _ = try await google.languageModel("gemini-2.5-flash").generate(LanguageModelRequest(
        messages: [.user("Return JSON.")],
        responseFormat: .json(schema: toolSchema)
    ))
    let googleRequests = await googleTransport.requests()
    let googleToolBody = try decodeJSONBody(try #require(googleRequests.first?.body))
    let googleResponseBody = try decodeJSONBody(try #require(googleRequests.last?.body))
    #expect(googleToolBody["tools"]?[0]?["functionDeclarations"]?[0]?["parameters"] == expectedParameters)
    #expect(googleResponseBody["generationConfig"]?["responseSchema"] == expectedParameters)

    let vertexTransport = RecordingTransport(response: response)
    let vertex = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
        apiKey: "vertex-key",
        transport: vertexTransport
    ))
    _ = try await vertex.languageModel("gemini-2.5-flash").generate(LanguageModelRequest(
        messages: [.user("Format it.")],
        tools: ["formatDate": toolSchema]
    ))
    let vertexBody = try decodeJSONBody(try #require((await vertexTransport.requests()).first?.body))
    #expect(vertexBody["tools"]?[0]?["functionDeclarations"]?[0]?["parameters"] == expectedParameters)
}

@Test func googleUpstreamFutureFullFlashModelsUseLowMinimumThinkingLevel() {
    let cases: [(modelID: String, reasoning: String, expected: String)] = [
        ("gemini-3.7-flash-video-understanding-eap", "minimal", "low"),
        ("gemini-3.7-flash-video-understanding-eap", "none", "low"),
        ("gemini-flash-latest", "minimal", "low"),
        ("gemini-flash-latest", "none", "low"),
        ("models/gemini-3.7-flash", "minimal", "low"),
        ("gemini-3.8-flash", "minimal", "low"),
        ("gemini-3.10-flash-preview", "minimal", "low"),
        ("gemini-4.0-flash", "minimal", "low"),
        ("gemini-3-flash-preview", "minimal", "minimal"),
        ("gemini-3.6-flash", "minimal", "minimal"),
        ("gemini-3.7-flash-lite", "minimal", "minimal"),
        ("gemini-3.10-flash-lite-preview", "minimal", "minimal"),
        ("gemini-flash-lite-latest", "minimal", "minimal")
    ]

    for testCase in cases {
        var warnings: [AIWarning] = []
        let config = googleThinkingConfig(
            for: testCase.reasoning,
            modelID: testCase.modelID,
            warnings: &warnings
        )
        #expect(config?["thinkingLevel"]?.stringValue == testCase.expected)
    }
}
