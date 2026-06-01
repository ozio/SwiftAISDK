import Foundation
import Testing
@testable import SwiftAISDK

@Test func secureJSONParseParsesJSONValuesAndRejectsPrototypePayloads() throws {
    #expect(try secureJSONParse(#"{"a":5,"b":6}"#) == ["a": 5, "b": 6])
    #expect(try secureJSONParse("null") == .null)
    #expect(try secureJSONParse("0") == 0)
    #expect(try secureJSONParse(#""X""#) == "X")
    #expect(try secureJSONParse(#"{ "constructor": "string value" }"#) == ["constructor": "string value"])
    #expect(try secureJSONParse(#"{ "constructor": null }"#) == ["constructor": .null])

    #expect(throws: AIJSONParseError.self) {
        _ = try secureJSONParse(#"{ "__proto__": { "isAdmin": true } }"#)
    }
    #expect(throws: AIJSONParseError.self) {
        _ = try secureJSONParse(#"{ "\u005f\u005fproto__": { "isAdmin": true } }"#)
    }
    #expect(throws: AIJSONParseError.self) {
        _ = try secureJSONParse(#"{ "constructor": { "prototype": { "isAdmin": true } } }"#)
    }
    #expect(throws: AIJSONParseError.self) {
        _ = try secureJSONParse(#"{ "\u0063\u006f\u006e\u0073\u0074\u0072\u0075\u0063\u0074\u006f\u0072": { "prototype": { "isAdmin": true } } }"#)
    }
}

@Test func parseJSONValidatesOptionalSchema() throws {
    let schema: JSONValue = [
        "type": "object",
        "properties": ["foo": ["type": "string"]],
        "required": ["foo"],
        "additionalProperties": false
    ]

    #expect(try parseJSON(#"{"foo":"bar"}"#, schema: schema) == ["foo": "bar"])
    #expect(throws: AIJSONSchemaValidationIssue.self) {
        _ = try parseJSON(#"{"foo":42}"#, schema: schema)
    }
    #expect(throws: AIJSONParseError.self) {
        _ = try parseJSON("invalid json")
    }
}

@Test func safeParseJSONPreservesRawValueForValidationFailures() {
    let schema: JSONValue = [
        "type": "object",
        "properties": ["age": ["type": "number"]],
        "required": ["age"]
    ]

    let success = safeParseJSON(#"{"age":42}"#, schema: schema)
    #expect(success.success)
    #expect(success.value == ["age": 42])
    #expect(success.rawValue == ["age": 42])

    let validationFailure = safeParseJSON(#"{"age":"twenty"}"#, schema: schema)
    #expect(!validationFailure.success)
    #expect(validationFailure.value == nil)
    #expect(validationFailure.rawValue == ["age": "twenty"])

    let parseFailure = safeParseJSON("invalid json")
    #expect(!parseFailure.success)
    #expect(parseFailure.rawValue == nil)
}

@Test func isParsableJSONUsesSecureParser() {
    #expect(isParsableJSON(#"{"foo":"bar"}"#))
    #expect(isParsableJSON("[1,2,3]"))
    #expect(!isParsableJSON("invalid"))
    #expect(!isParsableJSON(#"{ "__proto__": { "isAdmin": true } }"#))
}

@Test func isJSONSerializableMatchesJSONBoundaryRules() {
    final class TestClass {}

    #expect(isJSONSerializable(nil))
    #expect(isJSONSerializable("test"))
    #expect(isJSONSerializable(42))
    #expect(isJSONSerializable(true))
    #expect(isJSONSerializable(["test", 42, true, nil, ["nested": ["value"]]] as [Any?]))
    #expect(isJSONSerializable(["string": "test", "nested": ["array": ["value"]]] as [String: Any]))

    #expect(!isJSONSerializable(Date()))
    #expect(!isJSONSerializable(TestClass()))
}
