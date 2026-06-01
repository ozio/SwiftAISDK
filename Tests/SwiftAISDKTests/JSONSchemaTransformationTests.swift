import Testing
@testable import SwiftAISDK

@Test func addAdditionalPropertiesToJSONSchemaNormalizesNestedObjectSchemas() {
    let schema: JSONValue = [
        "type": "object",
        "additionalProperties": true,
        "properties": [
            "plain": ["type": "string"],
            "nested": [
                "type": "object",
                "properties": [
                    "value": ["type": "string"]
                ]
            ],
            "union": [
                "type": ["object", "null"],
                "properties": [
                    "id": ["type": "string"]
                ]
            ],
            "array": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "item": ["type": "string"]
                    ]
                ]
            ],
            "tuple": [
                "type": "array",
                "items": [
                    ["type": "object", "properties": ["left": ["type": "string"]]],
                    ["type": "string"]
                ]
            ],
            "choice": [
                "anyOf": [
                    ["type": "object", "properties": ["a": ["type": "string"]]],
                    ["type": "string"]
                ],
                "allOf": [
                    ["type": "object", "properties": ["b": ["type": "string"]]]
                ],
                "oneOf": [
                    ["type": "object", "properties": ["c": ["type": "string"]]]
                ]
            ]
        ],
        "definitions": [
            "Defined": [
                "type": "object",
                "properties": ["name": ["type": "string"]]
            ]
        ]
    ]

    let result = addAdditionalPropertiesToJSONSchema(schema)

    #expect(result["additionalProperties"]?.boolValue == false)
    #expect(result["properties"]?["nested"]?["additionalProperties"]?.boolValue == false)
    #expect(result["properties"]?["union"]?["additionalProperties"]?.boolValue == false)
    #expect(result["properties"]?["array"]?["items"]?["additionalProperties"]?.boolValue == false)
    #expect(result["properties"]?["tuple"]?["items"]?[0]?["additionalProperties"]?.boolValue == false)
    #expect(result["properties"]?["tuple"]?["items"]?[1]?["additionalProperties"] == nil)
    #expect(result["properties"]?["choice"]?["anyOf"]?[0]?["additionalProperties"]?.boolValue == false)
    #expect(result["properties"]?["choice"]?["anyOf"]?[1]?["additionalProperties"] == nil)
    #expect(result["properties"]?["choice"]?["allOf"]?[0]?["additionalProperties"]?.boolValue == false)
    #expect(result["properties"]?["choice"]?["oneOf"]?[0]?["additionalProperties"]?.boolValue == false)
    #expect(result["definitions"]?["Defined"]?["additionalProperties"]?.boolValue == false)
}

@Test func addAdditionalPropertiesToJSONSchemaLeavesNonObjectSchemasUntouched() {
    let stringSchema: JSONValue = ["type": "string", "properties": ["ignored": ["type": "object"]]]
    let boolSchema: JSONValue = true

    #expect(addAdditionalPropertiesToJSONSchema(stringSchema) == stringSchema)
    #expect(addAdditionalPropertiesToJSONSchema(boolSchema) == boolSchema)
}
