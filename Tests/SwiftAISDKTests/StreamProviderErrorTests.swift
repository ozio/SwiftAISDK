import Testing
@testable import SwiftAISDK

@Test func streamProviderErrorNormalizesTypedNestedAndMessageOnlyPayloadsLikeUpstream() throws {
    let typed = AIStreamProviderError(
        message: "Overloaded",
        type: "overloaded_error",
        code: "provider_overloaded",
        statusCode: 529,
        isRetryable: true,
        data: ["message": "Overloaded"]
    )
    let typedPart = LanguageStreamPart.providerError(typed)
    #expect(typedPart.streamProviderError == typed)

    let nested = LanguageStreamPart.error(
        message: "fallback",
        rawValue: [
            "type": "response.failed",
            "response": [
                "error": [
                    "code": "rate_limit_exceeded",
                    "message": "Try again later"
                ]
            ]
        ]
    ).streamProviderError
    #expect(nested?.message == "Try again later")
    #expect(nested?.type == "response.failed")
    #expect(nested?.code == "rate_limit_exceeded")
    #expect(nested?.statusCode == nil)
    #expect(nested?.isRetryable == false)

    let messageOnly = LanguageStreamPart.error(message: "Internal server error").streamProviderError
    #expect(messageOnly?.statusCode == 500)
    #expect(messageOnly?.isRetryable == true)
}

@Test func streamProviderErrorPreservesProviderTypeAndNumericHTTPCodeLikeUpstream() throws {
    let part = LanguageStreamPart.error(
        message: "Rate limit reached",
        rawValue: [
            "message": "Rate limit reached",
            "type": "rate_limit_error",
            "code": 429
        ]
    )

    let error = try #require(part.streamProviderError)
    #expect(error.type == "rate_limit_error")
    #expect(error.code == 429)
    #expect(error.statusCode == 429)
    #expect(error.isRetryable)
}
