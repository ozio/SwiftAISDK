import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiPrepareToolChoiceReturnsAutoWhenChoiceIsMissingLikeUpstream() {
    let result = prepareToolChoice(nil)

    #expect(result == ["type": "auto"])
}

@Test func aiPrepareToolChoiceHandlesStringNoneLikeUpstream() {
    let result = prepareToolChoice("none")

    #expect(result == ["type": "none"])
}

@Test func aiPrepareToolChoiceHandlesObjectToolChoiceLikeUpstream() {
    let result = prepareToolChoice(["type": "tool", "toolName": "tool2"])

    #expect(result == ["type": "tool", "toolName": "tool2"])
}

@Test func aiPrepareToolChoiceHandlesStringAutoLikeUpstream() {
    let result = prepareToolChoice("auto")

    #expect(result == ["type": "auto"])
}

@Test func aiPrepareToolChoiceHandlesStringRequiredLikeUpstream() {
    let result = prepareToolChoice("required")

    #expect(result == ["type": "required"])
}
