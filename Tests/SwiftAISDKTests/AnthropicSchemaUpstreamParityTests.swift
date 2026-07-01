import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicSanitizesNumberConstraintsIntoDescriptionLikeUpstream() throws {
    let schema: JSONValue = [
        "type": "object",
        "properties": [
            "recurringIntervalMinutes": [
                "type": "number",
                "exclusiveMinimum": 0,
                "minimum": 1,
                "maximum": 60,
                "exclusiveMaximum": 120
            ]
        ],
        "required": ["recurringIntervalMinutes"],
        "additionalProperties": true
    ]

    let result = anthropicSanitizeJSONSchema(schema)

    #expect(result == [
        "type": "object",
        "properties": [
            "recurringIntervalMinutes": [
                "type": "number",
                "description": "minimum: 1; maximum: 60; exclusive minimum: 0; exclusive maximum: 120."
            ]
        ],
        "required": ["recurringIntervalMinutes"],
        "additionalProperties": false
    ])
}

@Test func anthropicSanitizesStringConstraintsAndUnsupportedFormatLikeUpstream() throws {
    let schema: JSONValue = [
        "type": "object",
        "properties": [
            "slug": [
                "type": "string",
                "description": "A URL slug",
                "minLength": 1,
                "maxLength": 20,
                "pattern": "^[a-z0-9-]+$",
                "format": "regex"
            ],
            "email": [
                "type": "string",
                "format": "email"
            ]
        ]
    ]

    let result = anthropicSanitizeJSONSchema(schema)

    #expect(result["properties"]?["slug"]?["format"] == nil)
    #expect(result["properties"]?["slug"]?["description"]?.stringValue == "A URL slug\nmin length: 1; max length: 20; pattern: ^[a-z0-9-]+$; format: regex.")
    #expect(result["properties"]?["email"]?["format"]?.stringValue == "email")
    #expect(result["additionalProperties"]?.boolValue == false)
}

@Test func anthropicSanitizesNestedDefinitionsArraysAndAnyOfLikeUpstream() throws {
    let schema: JSONValue = [
        "type": "object",
        "$defs": [
            "item": [
                "type": "object",
                "properties": [
                    "name": [
                        "type": "string",
                        "minLength": 2
                    ]
                ],
                "required": ["name"]
            ]
        ],
        "properties": [
            "items": [
                "type": "array",
                "minItems": 1,
                "maxItems": 3,
                "uniqueItems": true,
                "items": [
                    "anyOf": [
                        ["$ref": "#/$defs/item"],
                        ["type": "string", "maxLength": 10]
                    ]
                ]
            ]
        ]
    ]

    let result = anthropicSanitizeJSONSchema(schema)

    #expect(result["$defs"]?["item"]?["additionalProperties"]?.boolValue == false)
    #expect(result["$defs"]?["item"]?["properties"]?["name"]?["description"]?.stringValue == "min length: 2.")
    #expect(result["properties"]?["items"]?["description"]?.stringValue == "min items: 1; max items: 3; unique items: true.")
    #expect(result["properties"]?["items"]?["items"]?["anyOf"]?[0]?["$ref"]?.stringValue == "#/$defs/item")
    #expect(result["properties"]?["items"]?["items"]?["anyOf"]?[1]?["description"]?.stringValue == "max length: 10.")
}

@Test func anthropicSanitizesOneOfAsAnyOfLikeUpstream() throws {
    let schema: JSONValue = [
        "oneOf": [
            ["type": "string", "minLength": 1],
            ["type": "number", "minimum": 0]
        ]
    ]

    let result = anthropicSanitizeJSONSchema(schema)

    #expect(result["oneOf"] == nil)
    #expect(result["anyOf"]?[0]?["type"]?.stringValue == "string")
    #expect(result["anyOf"]?[0]?["description"]?.stringValue == "min length: 1.")
    #expect(result["anyOf"]?[1]?["type"]?.stringValue == "number")
    #expect(result["anyOf"]?[1]?["description"]?.stringValue == "minimum: 0.")
}

@Test func anthropicSchemaSanitizerDoesNotMutateInputLikeUpstream() throws {
    let schema: JSONValue = [
        "type": "object",
        "properties": [
            "value": [
                "type": "number",
                "exclusiveMinimum": 0
            ]
        ]
    ]

    _ = anthropicSanitizeJSONSchema(schema)

    #expect(schema == [
        "type": "object",
        "properties": [
            "value": [
                "type": "number",
                "exclusiveMinimum": 0
            ]
        ]
    ])
}

@Test func anthropicResponseFormatSanitizesJSONSchemaInRequestLikeUpstream() async throws {
    let schema: JSONValue = [
        "type": "object",
        "properties": [
            "score": [
                "type": "number",
                "minimum": 0,
                "maximum": 10
            ]
        ],
        "required": ["score"]
    ]
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"{\\"score\\":10}"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Return JSON.")],
        responseFormat: .json(schema: schema)
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let requestSchema = body["output_config"]?["format"]?["schema"]
    #expect(requestSchema?["properties"]?["score"]?["minimum"] == nil)
    #expect(requestSchema?["properties"]?["score"]?["maximum"] == nil)
    #expect(requestSchema?["properties"]?["score"]?["description"]?.stringValue == "minimum: 0; maximum: 10.")
    #expect(requestSchema?["additionalProperties"]?.boolValue == false)
}

