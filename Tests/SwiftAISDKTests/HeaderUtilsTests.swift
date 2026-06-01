import Testing
@testable import SwiftAISDK

@Test func normalizeHeadersLowercasesKeysAndFiltersNilValues() {
    let headers: [String: String?] = [
        "Authorization": "Bearer token",
        "X-Feature": nil,
        "CONTENT-TYPE": "application/json"
    ]

    #expect(normalizeHeaders(headers) == [
        "authorization": "Bearer token",
        "content-type": "application/json"
    ])
    #expect(normalizeHeaderEntries([
        ("Authorization", "Bearer token"),
        ("X-Ignore", nil)
    ]) == ["authorization": "Bearer token"])
}

@Test func combineHeadersUsesLaterValuesLikeProviderUtils() {
    #expect(combineHeaders(
        ["Authorization": "Bearer old", "accept": "application/json"],
        ["Authorization": "Bearer new", "x-feature": "enabled"]
    ) == [
        "Authorization": "Bearer new",
        "accept": "application/json",
        "x-feature": "enabled"
    ])

    #expect(["a": "1"].mergingHeaders(["a": "2", "b": "3"]) == ["a": "2", "b": "3"])
}

@Test func withUserAgentSuffixNormalizesAndAppendsParts() {
    let headers = withUserAgentSuffix(
        [
            "User-Agent": "TestApp/1.0",
            "Authorization": "Bearer token",
            "X-Ignore": nil
        ],
        "ai-sdk/0.0.0-test",
        "provider/test"
    )

    #expect(headers["user-agent"] == "TestApp/1.0 ai-sdk/0.0.0-test provider/test")
    #expect(headers["authorization"] == "Bearer token")
    #expect(headers["x-ignore"] == nil)
}

@Test func withUserAgentSuffixCreatesHeaderWhenMissing() {
    let headers = withUserAgentSuffix(["Accept": "application/json"], "ai-sdk/0.0.0-test")

    #expect(headers["accept"] == "application/json")
    #expect(headers["user-agent"] == "ai-sdk/0.0.0-test")
}
