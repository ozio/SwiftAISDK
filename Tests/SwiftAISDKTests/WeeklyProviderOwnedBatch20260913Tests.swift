import Foundation
import Testing
@testable import SwiftAISDK

@Suite("WeeklyProviderOwnedBatch20260913", .serialized)
struct WeeklyProviderOwnedBatch20260913Tests {
    @Test func anthropicUsesPerRequestModelsAndProviderOwnedIdentity() async throws {
        let transport = RecordingTransport(response: jsonResponse(weeklyAnthropicBatchResponse(
            status: "in_progress",
            processing: 2
        )))
        let anthropic = try AIProviders.anthropic(settings: ProviderSettings(
            apiKey: "test-api-key",
            transport: transport
        ))
        let batch = anthropic.experimentalBatch()

        let result = try await batch.startBatch(AIBatchStartOptions(requests: [
            .text(TextBatchRequest(
                id: "haiku_request",
                modelID: "claude-3-haiku-20240307",
                request: LanguageModelRequest(messages: [.user("Short answer")])
            )),
            .text(TextBatchRequest(
                id: "sonnet-request",
                modelID: "claude-sonnet-4-5",
                request: LanguageModelRequest(messages: [.user("Long answer")])
            ))
        ]))

        #expect(batch.providerID == "anthropic.batch")
        #expect(isURLSupported(
            mediaType: "image/png",
            url: "https://assets.example.com/image.png",
            supportedURLs: batch.supportedURLs
        ))
        #expect(isURLSupported(
            mediaType: "application/pdf",
            url: "http://assets.example.com/report.pdf",
            supportedURLs: batch.supportedURLs
        ))
        #expect(!isURLSupported(
            mediaType: "text/plain",
            url: "https://assets.example.com/note.txt",
            supportedURLs: batch.supportedURLs
        ))
        #expect(result.batchID == "msgbatch_123")
        let request = try #require(await transport.requests().first)
        #expect(request.url.absoluteString == "https://api.anthropic.com/v1/messages/batches")
        let body = try decodeJSONBody(try #require(request.body))
        #expect(body["requests"]?[0]?["custom_id"]?.stringValue == "haiku_request")
        #expect(body["requests"]?[0]?["params"]?["model"]?.stringValue == "claude-3-haiku-20240307")
        #expect(body["requests"]?[1]?["custom_id"]?.stringValue == "sonnet-request")
        #expect(body["requests"]?[1]?["params"]?["model"]?.stringValue == "claude-sonnet-4-5")
    }

    @Test func anthropicRejectsNonASCIIIDsAndImageRequestsBeforeIO() async throws {
        let transport = RecordingTransport(response: jsonResponse("{}"))
        let anthropic = try AIProviders.anthropic(settings: ProviderSettings(
            apiKey: "test-api-key",
            transport: transport
        ))
        let batch = anthropic.experimentalBatch()

        await #expect(throws: AIError.self) {
            _ = try await batch.startBatch(AIBatchStartOptions(requests: [
                .text(TextBatchRequest(
                    id: "café",
                    modelID: "claude-sonnet-4-5",
                    request: LanguageModelRequest(messages: [.user("Hello")])
                ))
            ]))
        }
        await #expect(throws: AIError.self) {
            _ = try await batch.startBatch(AIBatchStartOptions(requests: [
                .image(ImageBatchRequest(
                    id: "image",
                    modelID: "claude-sonnet-4-5",
                    request: ImageGenerationRequest(prompt: "A red panda")
                ))
            ]))
        }

        #expect(await transport.requests().isEmpty)
    }

    @Test func anthropicExposesStatusCancelAndCursorListing() async throws {
        let transport = RecordingTransport(responses: [
            jsonResponse(weeklyAnthropicBatchResponse(status: "in_progress", processing: 1)),
            jsonResponse(weeklyAnthropicBatchResponse(
                status: "canceling",
                processing: 1,
                cancelInitiatedAt: "2026-09-13T00:01:00Z"
            )),
            jsonResponse("""
            {
              "data": [\(weeklyAnthropicBatchResponse(status: "ended", succeeded: 1))],
              "has_more": true,
              "last_id": "msgbatch_123"
            }
            """)
        ])
        let anthropic = try AIProviders.anthropic(settings: ProviderSettings(
            apiKey: "test-api-key",
            transport: transport
        ))
        let batch = anthropic.experimentalBatch()

        let status = try await batch.getBatchStatus(AIBatchOperationOptions(batchID: "msgbatch_123"))
        _ = try await batch.cancelBatch(AIBatchOperationOptions(batchID: "msgbatch_123"))
        let page = try await batch.listBatches(AIBatchListOptions(limit: 25, cursor: "msgbatch_before"))

        #expect(status.status == .pending)
        #expect(page.batches.map(\.batchID) == ["msgbatch_123"])
        #expect(page.batches.first?.status.status == .completed)
        #expect(page.nextCursor == "msgbatch_123")
        let requests = await transport.requests()
        #expect(requests.count == 3)
        #expect(requests[0].method == "GET")
        #expect(requests[0].url.path.hasSuffix("/messages/batches/msgbatch_123"))
        #expect(requests[1].method == "POST")
        #expect(requests[1].url.path.hasSuffix("/messages/batches/msgbatch_123/cancel"))
        #expect(try decodeJSONBody(try #require(requests[1].body)) == .object([:]))
        let listComponents = try #require(URLComponents(url: requests[2].url, resolvingAgainstBaseURL: false))
        #expect(requests[2].method == "GET")
        #expect(listComponents.path.hasSuffix("/messages/batches"))
        #expect(Set(listComponents.queryItems ?? []) == Set([
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "after_id", value: "msgbatch_before")
        ]))
    }

    @Test func anthropicProviderResultsRemainTextAndItemLocal() async throws {
        let status = weeklyAnthropicBatchResponse(
            status: "ended",
            succeeded: 2,
            resultsURL: "https://api.anthropic.com/v1/messages/batches/msgbatch_123/results"
        )
        let invalid = #"{"custom_id":"invalid","result":{"type":"succeeded","message":{"type":"message"}}}"#
        let valid = #"{"custom_id":"valid","result":{"type":"succeeded","message":{"id":"msg_valid","type":"message","role":"assistant","model":"claude-sonnet-4-5","content":[{"type":"text","text":"Paris"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":2,"output_tokens":1}}}}"#
        let transport = RecordingTransport(responses: [
            jsonResponse(status),
            AIHTTPResponse(
                statusCode: 200,
                headers: ["content-type": "application/jsonl"],
                body: Data("\(invalid)\n\(valid)\n".utf8)
            )
        ])
        let anthropic = try AIProviders.anthropic(settings: ProviderSettings(
            apiKey: "test-api-key",
            transport: transport
        ))

        let stream = try await anthropic.experimentalBatch().getBatchResults(
            AIBatchOperationOptions(batchID: "msgbatch_123")
        )
        var items: [AIBatchV4ItemResult] = []
        for try await item in stream { items.append(item) }

        #expect(items.count == 2)
        guard case let .text(.failed(invalidID, invalidError, _)) = items[0] else {
            Issue.record("Expected an item-local Anthropic text failure")
            return
        }
        #expect(invalidID == "invalid")
        #expect(invalidError.code == "invalid_response")
        guard case let .text(.succeeded(validID, result)) = items[1] else {
            Issue.record("Expected the later Anthropic text result to succeed")
            return
        }
        #expect(validID == "valid")
        #expect(result.text == "Paris")
    }

    @Test func googleStartsMixedTextAndImageUnderOneEndpointModel() async throws {
        let transport = RecordingTransport(response: jsonResponse(weeklyGoogleBatchOperation(
            state: "BATCH_STATE_PENDING",
            done: false,
            total: 2,
            successful: 0,
            pending: 2
        )))
        let google = try AIProviders.google(settings: ProviderSettings(
            apiKey: "test-api-key",
            transport: transport
        ))
        let batch = google.experimentalBatch()

        let result = try await batch.startBatch(AIBatchStartOptions(requests: [
            .text(TextBatchRequest(
                id: "text",
                modelID: "gemini-2.5-flash",
                request: LanguageModelRequest(messages: [.user("Capital of France?")])
            )),
            .image(ImageBatchRequest(
                id: "image",
                modelID: "gemini-2.5-flash",
                request: ImageGenerationRequest(
                    prompt: "A red panda",
                    size: "1024x1024",
                    aspectRatio: "16:9",
                    seed: 42,
                    providerOptions: [
                        "google": [
                            "googleSearch": ["searchTypes": ["webSearch": [:]]]
                        ]
                    ]
                )
            ))
        ]))

        #expect(batch.providerID == "google.batch")
        #expect(isURLSupported(
            mediaType: "application/pdf",
            url: "https://generativelanguage.googleapis.com/v1beta/files/file-1",
            supportedURLs: batch.supportedURLs
        ))
        #expect(isURLSupported(
            mediaType: "video/mp4",
            url: "https://www.youtube.com/watch?v=video-id&feature=share",
            supportedURLs: batch.supportedURLs
        ))
        #expect(!isURLSupported(
            mediaType: "image/png",
            url: "https://assets.example.com/image.png",
            supportedURLs: batch.supportedURLs
        ))
        #expect(result.batchID == "batches/batch-123")
        #expect(result.warnings.contains {
            $0.requestID == "image" && $0.warning.feature == "size"
        })
        let request = try #require(await transport.requests().first)
        #expect(request.url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:batchGenerateContent")
        let body = try decodeJSONBody(try #require(request.body))
        let requests = try #require(body["batch"]?["inputConfig"]?["requests"]?["requests"]?.arrayValue)
        #expect(requests.count == 2)
        #expect(requests[0]["metadata"]?["key"]?.stringValue == "text")
        #expect(requests[0]["request"]?["contents"]?[0]?["parts"]?[0]?["text"]?.stringValue == "Capital of France?")
        #expect(requests[1]["metadata"]?["key"]?.stringValue == "image")
        let imageBody = requests[1]["request"]
        #expect(imageBody?["contents"]?[0]?["parts"]?[0]?["text"]?.stringValue == "A red panda")
        #expect(imageBody?["generationConfig"]?["responseModalities"]?[0]?.stringValue == "IMAGE")
        #expect(imageBody?["generationConfig"]?["imageConfig"]?["aspectRatio"]?.stringValue == "16:9")
        #expect(imageBody?["generationConfig"]?["seed"]?.intValue == 42)
        #expect(imageBody?["tools"]?[0]?["googleSearch"]?["searchTypes"]?["webSearch"]?.objectValue?.isEmpty == true)
    }

    @Test func googleRejectsEmptyMissingAndMixedModelsBeforeIO() async throws {
        let transport = RecordingTransport(response: jsonResponse("{}"))
        let google = try AIProviders.google(settings: ProviderSettings(
            apiKey: "test-api-key",
            transport: transport
        ))
        let batch = google.experimentalBatch()

        await #expect(throws: AIError.self) {
            _ = try await batch.startBatch(AIBatchStartOptions(requests: []))
        }
        await #expect(throws: AIError.self) {
            _ = try await batch.startBatch(AIBatchStartOptions(requests: [
                .text(TextBatchRequest(
                    id: "missing-model",
                    request: LanguageModelRequest(messages: [.user("Hello")])
                ))
            ]))
        }
        await #expect(throws: AIError.self) {
            _ = try await batch.startBatch(AIBatchStartOptions(requests: [
                .text(TextBatchRequest(
                    id: "text",
                    modelID: "gemini-2.5-flash",
                    request: LanguageModelRequest(messages: [.user("Hello")])
                )),
                .image(ImageBatchRequest(
                    id: "image",
                    modelID: "gemini-3-pro-image-preview",
                    request: ImageGenerationRequest(prompt: "Hello")
                ))
            ]))
        }

        #expect(await transport.requests().isEmpty)
    }

    @Test func googleUsesFileUploadAtTheInlineBoundaryWithoutLeakingCredentials() async throws {
        let transport = RecordingTransport(responses: [
            AIHTTPResponse(
                statusCode: 200,
                headers: ["x-goog-upload-url": "https://upload.example.com/session"],
                body: Data()
            ),
            jsonResponse(#"{"file":{"name":"files/batch-input","expirationTime":"2026-09-14T00:00:00Z"}}"#),
            jsonResponse(weeklyGoogleBatchOperation())
        ])
        let google = try AIProviders.google(settings: ProviderSettings(
            apiKey: "test-api-key",
            headers: ["Provider-Header": "provider"],
            transport: transport
        ))
        let batch = google.experimentalBatch()
        let largePrompt = String(repeating: "a", count: 20_000_000)

        let result = try await batch.startBatch(AIBatchStartOptions(
            requests: [
                .text(TextBatchRequest(
                    id: "small",
                    modelID: "gemini-2.5-flash",
                    request: LanguageModelRequest(messages: [.user("small")])
                )),
                .text(TextBatchRequest(
                    id: "large",
                    modelID: "gemini-2.5-flash",
                    request: LanguageModelRequest(messages: [.user(largePrompt)])
                ))
            ],
            headers: ["Operation-Header": "operation"]
        ))

        #expect(result.providerMetadata["google"]?["inputFileId"]?.stringValue == "files/batch-input")
        let requests = await transport.requests()
        #expect(requests.map(\.url.absoluteString) == [
            "https://generativelanguage.googleapis.com/upload/v1beta/files",
            "https://upload.example.com/session",
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:batchGenerateContent"
        ])
        let startHeaders = normalizeHeaders(requests[0].headers)
        let sessionHeaders = normalizeHeaders(requests[1].headers)
        #expect(startHeaders["x-goog-api-key"] == "test-api-key")
        #expect(startHeaders["provider-header"] == "provider")
        #expect(startHeaders["operation-header"] == "operation")
        #expect(sessionHeaders["x-goog-api-key"] == nil)
        #expect(sessionHeaders["provider-header"] == nil)
        #expect(sessionHeaders["operation-header"] == nil)
        #expect(sessionHeaders["user-agent"] == nil)
        #expect(requests[1].body?.count ?? 0 > 20_000_000)
    }

    @Test func googleExposesCancelListAndIsolatesMixedResultItems() async throws {
        let inlineResult: JSONValue = [
            "name": "batches/batch-123",
            "done": true,
            "metadata": [
                "state": "BATCH_STATE_SUCCEEDED",
                "output": [
                    "inlinedResponses": [
                        "inlinedResponses": [
                            [
                                "metadata": ["key": "image"],
                                "response": weeklyGoogleBatchResponse(
                                    responseID: "image-response",
                                    parts: [[
                                        "inlineData": [
                                            "mimeType": "image/png",
                                            "data": "aGVsbG8="
                                        ]
                                    ]]
                                )
                            ],
                            [
                                "metadata": ["key": "invalid"],
                                "response": weeklyGoogleBatchResponse(parts: [["text": 42]])
                            ],
                            [
                                "metadata": ["key": "text"],
                                "response": weeklyGoogleBatchResponse(parts: [["text": "Paris"]])
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let listPage: JSONValue = [
            "operations": [[
                "name": "batches/batch-456",
                "done": false,
                "metadata": ["state": "BATCH_STATE_PENDING"]
            ]],
            "nextPageToken": "next-page"
        ]
        let transport = RecordingTransport(responses: [
            jsonResponse("{}"),
            jsonResponse(try weeklyJSONString(listPage)),
            jsonResponse(try weeklyJSONString(inlineResult))
        ])
        let google = try AIProviders.google(settings: ProviderSettings(
            apiKey: "test-api-key",
            transport: transport
        ))
        let batch = google.experimentalBatch()

        _ = try await batch.cancelBatch(AIBatchOperationOptions(batchID: "batches/batch-123"))
        let page = try await batch.listBatches(AIBatchListOptions(limit: 10, cursor: "before"))
        let stream = try await batch.getBatchResults(AIBatchOperationOptions(batchID: "batches/batch-123"))
        var items: [AIBatchV4ItemResult] = []
        for try await item in stream { items.append(item) }

        #expect(page.batches.map(\.batchID) == ["batches/batch-456"])
        #expect(page.nextCursor == "next-page")
        #expect(items.count == 3)
        guard case let .image(.succeeded(imageID, imageResult)) = items[0] else {
            Issue.record("Expected a Google image batch result")
            return
        }
        #expect(imageID == "image")
        #expect(imageResult.base64Images == ["aGVsbG8="])
        #expect(imageResult.responseMetadata.id == "image-response")
        guard case let .text(.failed(invalidID, invalidError, _)) = items[1] else {
            Issue.record("Expected an item-local Google text failure")
            return
        }
        #expect(invalidID == "invalid")
        #expect(invalidError.code == "invalid_response")
        guard case let .text(.succeeded(textID, textResult)) = items[2] else {
            Issue.record("Expected the later Google text result to succeed")
            return
        }
        #expect(textID == "text")
        #expect(textResult.text == "Paris")

        let requests = await transport.requests()
        #expect(requests.count == 3)
        #expect(requests[0].method == "POST")
        #expect(requests[0].url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/batches/batch-123:cancel")
        let listComponents = try #require(URLComponents(url: requests[1].url, resolvingAgainstBaseURL: false))
        #expect(requests[1].method == "GET")
        #expect(listComponents.path == "/v1beta/batches")
        #expect(Set(listComponents.queryItems ?? []) == Set([
            URLQueryItem(name: "pageSize", value: "10"),
            URLQueryItem(name: "pageToken", value: "before")
        ]))
        #expect(requests[2].method == "GET")
        #expect(requests[2].url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/batches/batch-123")
    }
}

private func weeklyAnthropicBatchResponse(
    status: String,
    processing: Int = 0,
    succeeded: Int = 0,
    errored: Int = 0,
    canceled: Int = 0,
    expired: Int = 0,
    cancelInitiatedAt: String? = nil,
    resultsURL: String? = nil
) -> String {
    let value: JSONValue = [
        "id": "msgbatch_123",
        "type": "message_batch",
        "processing_status": .string(status),
        "request_counts": [
            "processing": .number(Double(processing)),
            "succeeded": .number(Double(succeeded)),
            "errored": .number(Double(errored)),
            "canceled": .number(Double(canceled)),
            "expired": .number(Double(expired))
        ],
        "created_at": "2026-09-13T00:00:00Z",
        "expires_at": "2026-09-14T00:00:00Z",
        "archived_at": .null,
        "cancel_initiated_at": cancelInitiatedAt.map(JSONValue.string) ?? .null,
        "ended_at": status == "ended" ? "2026-09-13T00:02:00Z" : .null,
        "results_url": resultsURL.map(JSONValue.string) ?? .null
    ]
    return (try? weeklyJSONString(value)) ?? "{}"
}

private func weeklyGoogleBatchOperation(
    state: String = "BATCH_STATE_SUCCEEDED",
    done: Bool = true,
    total: Int = 1,
    successful: Int = 1,
    failed: Int = 0,
    pending: Int = 0
) -> String {
    let value: JSONValue = [
        "name": "batches/batch-123",
        "done": .bool(done),
        "metadata": [
            "state": .string(state),
            "createTime": "2026-09-13T00:00:00Z",
            "batchStats": [
                "requestCount": .string(String(total)),
                "successfulRequestCount": .string(String(successful)),
                "failedRequestCount": .string(String(failed)),
                "pendingRequestCount": .string(String(pending))
            ]
        ]
    ]
    return (try? weeklyJSONString(value)) ?? "{}"
}

private func weeklyGoogleBatchResponse(
    responseID: String = "response-1",
    parts: [JSONValue]
) -> JSONValue {
    [
        "responseId": .string(responseID),
        "modelVersion": "gemini-2.5-flash",
        "candidates": [[
            "content": ["role": "model", "parts": .array(parts)],
            "finishReason": "STOP"
        ]],
        "usageMetadata": [
            "promptTokenCount": 1,
            "candidatesTokenCount": 1,
            "totalTokenCount": 2
        ]
    ]
}

private func weeklyJSONString(_ value: JSONValue) throws -> String {
    guard let string = String(data: try encodeJSONBody(value), encoding: .utf8) else {
        throw AIError.invalidArgument(argument: "value", message: "Could not encode test JSON.")
    }
    return string
}
