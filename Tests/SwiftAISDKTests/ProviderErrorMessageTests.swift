import Foundation
import Testing
@testable import SwiftAISDK

@Test func getErrorMessageReturnsUnknownErrorForNilLikeUpstream() {
    #expect(getErrorMessage(nil) == "unknown error")
}

@Test func getErrorMessageReturnsStringErrorsAsIsLikeUpstream() {
    #expect(getErrorMessage("something went wrong") == "something went wrong")
    #expect(getErrorMessage("") == "")
}

@Test func getErrorMessageUsesSwiftErrorDescriptionsLikeUpstreamErrorToString() {
    #expect(getErrorMessage(NamedTestError(name: "Error", message: "API crashed")) == "Error: API crashed")
    #expect(getErrorMessage(NamedTestError(name: "TypeError", message: "invalid argument")) == "TypeError: invalid argument")
    #expect(getErrorMessage(NamedTestError(name: "RangeError", message: "out of bounds")) == "RangeError: out of bounds")
}

@Test func getErrorMessageReturnsErrorNameWhenMessageIsEmptyLikeUpstream() {
    #expect(getErrorMessage(NamedTestError(name: "Error", message: "")) == "Error")
    #expect(getErrorMessage(NamedTestError(name: "TypeError", message: "")) == "TypeError")
}

@Test func getErrorMessageHandlesCustomErrorDescriptionsLikeUpstream() {
    #expect(getErrorMessage(NamedTestError(name: "CustomError", message: "custom failure")) == "CustomError: custom failure")
    #expect(getErrorMessage(APIStatusError(message: "rate limited", code: 429)) == "API Error 429: rate limited")
    #expect(getErrorMessage(NamedTestError(name: "CustomError", message: "")) == "CustomError")
}

@Test func getErrorMessageStringifiesJSONValuesLikeUpstream() {
    #expect(getErrorMessage(JSONValue.object(["code": "FAIL", "detail": "oops"])) == #"{"code":"FAIL","detail":"oops"}"#)
    #expect(getErrorMessage(JSONValue.array(["a", "b"])) == #"["a","b"]"#)
    #expect(getErrorMessage(JSONValue.null) == "null")
}

@Test func getErrorMessageStringifiesScalarValuesLikeUpstream() {
    #expect(getErrorMessage(42) == "42")
    #expect(getErrorMessage(42.5) == "42.5")
    #expect(getErrorMessage(false) == "false")
}

private struct NamedTestError: Error, CustomStringConvertible {
    var name: String
    var message: String

    var description: String {
        message.isEmpty ? name : "\(name): \(message)"
    }
}

private struct APIStatusError: Error, CustomStringConvertible {
    var message: String
    var code: Int

    var description: String {
        "API Error \(code): \(message)"
    }
}
