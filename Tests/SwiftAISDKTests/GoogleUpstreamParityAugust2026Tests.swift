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
