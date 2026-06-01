import Testing
@testable import SwiftAISDK

@Test func isProviderReferenceMatchesProviderUtilsShapeRules() {
    #expect(isProviderReference(["openai": "file-abc123"]))
    #expect(isProviderReference(["fileId": "abc"]))

    let plainJSON: JSONValue = ["openai": "file-abc123"]
    let fileIDJSON: JSONValue = ["fileId": "abc"]
    let taggedReference: JSONValue = ["type": "reference", "reference": ["fileId": "abc"]]
    let taggedData: JSONValue = ["type": "data", "data": "x"]
    let nonStringValue: JSONValue = ["openai": ["id": "file-abc123"]]

    #expect(isProviderReference(plainJSON))
    #expect(isProviderReference(fileIDJSON))
    #expect(!isProviderReference(taggedReference))
    #expect(!isProviderReference(taggedData))
    #expect(isProviderReference(nonStringValue))
    #expect(!isProviderReference(.null))
    #expect(!isProviderReference("some-string"))
    #expect(!isProviderReference(42))
}

@Test func resolveProviderReferenceReturnsProviderSpecificIdentifier() throws {
    let reference: AIProviderReference = [
        "openai": "file-abc",
        "anthropic": "file-xyz"
    ]

    #expect(try resolveProviderReference(reference: reference, provider: "openai") == "file-abc")
    #expect(try resolveProviderReference(reference, provider: "anthropic") == "file-xyz")
}

@Test func resolveProviderReferenceThrowsTypedErrorWhenMissing() {
    let reference: AIProviderReference = [
        "anthropic": "file-xyz",
        "google": "file-123"
    ]

    #expect(throws: AINoSuchProviderReferenceError(provider: "openai", reference: reference)) {
        _ = try resolveProviderReference(reference: reference, provider: "openai")
    }
    #expect(throws: AINoSuchProviderReferenceError(provider: "openai", reference: [:])) {
        _ = try resolveProviderReference(reference: [:], provider: "openai")
    }
}

@Test func uploadResultsResolveProviderReferences() throws {
    let file = FileUploadResult(providerReference: ["openai": "file-1"], rawValue: .object([:]))
    let skill = SkillUploadResult(providerReference: ["anthropic": "skill-1"], rawValue: .object([:]))

    #expect(try file.providerID(for: "openai") == "file-1")
    #expect(try skill.providerID(for: "anthropic") == "skill-1")
}
