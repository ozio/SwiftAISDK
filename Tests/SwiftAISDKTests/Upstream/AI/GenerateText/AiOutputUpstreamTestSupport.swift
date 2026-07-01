import Foundation
import Testing
@testable import SwiftAISDK

struct OutputContent: Codable, Equatable, Sendable {
    var content: String
}

struct OutputValue: Codable, Equatable, Sendable {
    var value: String
}

struct OutputSummary: Codable, Equatable, Sendable {
    var summary: String
}

func collectStreamEnumPartials(text: String) async throws -> [String] {
    let model = ObjectFacadeMockLanguageModel(
        result: TextGenerationResult(text: "", rawValue: .object([:])),
        streamParts: [
            .textDelta(text),
            .finish(reason: "stop", usage: nil)
        ]
    )
    var partials: [String] = []
    do {
        for try await part in AI.streamEnum(
            model: model,
            prompt: "Choose.",
            values: ["aaa", "aab", "ccc"]
        ) {
            if case let .partial(partial) = part {
                partials.append(partial)
            }
        }
    } catch is AIObjectGenerationError {
        return partials
    }
    return partials
}

func outputValueSchema() -> JSONValue {
    [
        "type": "object",
        "properties": ["value": ["type": "string"]],
        "required": ["value"],
        "additionalProperties": false
    ]
}

func outputContentSchema() -> JSONValue {
    [
        "type": "object",
        "properties": ["content": ["type": "string"]],
        "required": ["content"],
        "additionalProperties": false
    ]
}
