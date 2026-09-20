import Foundation
import Testing
@testable import SwiftAISDK

@Suite("BedrockStreamErrorParityTests")
struct BedrockStreamErrorParityTests {
    @Test func nonSuccessStreamsPreserveTypedAndUntypedMessages() async {
        let cases = [
            (
                payload: #"{"type":"ValidationException","message":"invalid request"}"#,
                expected: "ValidationException: invalid request"
            ),
            (
                payload: #"{"message":"slow down"}"#,
                expected: "slow down"
            )
        ]

        for item in cases {
            let payload = Data(item.payload.utf8)
            let response = AIHTTPStreamResponse(
                statusCode: 429,
                headers: ["x-amzn-requestid": "req-1"],
                body: AsyncThrowingStream { continuation in
                    continuation.yield(payload)
                    continuation.finish()
                }
            )

            do {
                try await streamFromBedrockResponse(
                    providerID: "amazon-bedrock",
                    response: response,
                    requestURL: URL(string: "https://bedrock-runtime.us-east-1.amazonaws.com/model/test/converse-stream")!,
                    emit: { _ in }
                )
                Issue.record("Expected a Bedrock API call error.")
            } catch let error as AIError {
                #expect(error == .apiCall(
                    provider: "amazon-bedrock",
                    statusCode: 429,
                    body: item.expected,
                    headers: ["x-amzn-requestid": "req-1"]
                ))
            } catch {
                Issue.record("Expected AIError, got \(error).")
            }
        }
    }
}
