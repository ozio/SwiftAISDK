import Testing
@testable import SwiftAISDK

@Test func aiPrepareHeadersSetsContentTypeIfNotPresentLikeUpstream() {
    let headers = prepareHeaders([:] as [String: String], defaultHeaders: ["content-type": "application/json"])

    #expect(headers["content-type"] == "application/json")
}

@Test func aiPrepareHeadersDoesNotOverwriteExistingContentTypeLikeUpstream() {
    let headers = prepareHeaders(
        ["Content-Type": "text/html"],
        defaultHeaders: ["content-type": "application/json"]
    )

    #expect(headers["content-type"] == "text/html")
}

@Test func aiPrepareHeadersHandlesNilInitLikeUpstream() {
    let headers = prepareHeaders(
        nil as [String: String?]?,
        defaultHeaders: ["content-type": "application/json"]
    )

    #expect(headers["content-type"] == "application/json")
}

@Test func aiPrepareHeadersHandlesInitializedHeadersLikeUpstream() {
    let headers = prepareHeaders(
        ["init": "foo"],
        defaultHeaders: ["content-type": "application/json"]
    )

    #expect(headers["init"] == "foo")
    #expect(headers["content-type"] == "application/json")
}

@Test func aiPrepareHeadersHandlesResponseHeadersLikeUpstream() {
    let headers = prepareHeaders(
        ["init": "foo", "extra": "bar"],
        defaultHeaders: ["content-type": "application/json"]
    )

    #expect(headers["init"] == "foo")
    #expect(headers["extra"] == "bar")
    #expect(headers["content-type"] == "application/json")
}

@Test func aiPrepareRetriesSetsDefaultValuesWhenNoInputIsProvidedLikeUpstream() throws {
    let defaultPolicy = try prepareRetries(maxRetries: nil)

    #expect(defaultPolicy.maxRetries == 2)
}

@Test func aiPrepareRetriesRejectsNegativeMaxRetriesLikeUpstreamValidation() throws {
    do {
        _ = try prepareRetries(maxRetries: -1)
        Issue.record("Expected negative maxRetries to throw")
    } catch let error as AIError {
        #expect(error == .invalidArgument(argument: "maxRetries", message: "maxRetries must be >= 0"))
    }
}
