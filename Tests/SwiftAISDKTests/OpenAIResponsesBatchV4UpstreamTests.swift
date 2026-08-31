import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesBatchV4CreatesPublishedMultipartAndPreparedJSONLRequests() async throws {
    let transport = OpenAIBatchScriptedTransport(sendResponses: [
        jsonResponse(#"{"id":"file-input","object":"file","filename":"batch.jsonl","purpose":"batch"}"#),
        jsonResponse(openAIBatchMetadata(
            status: "validating",
            total: 2,
            completed: 0,
            failed: 0
        ))
    ])
    let provider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-api-key",
        headers: ["Provider-Header": "provider"],
        transport: transport
    ))
    let model = try provider.batchLanguageModel("gpt-5.6")
    let abortController = AIAbortController()
    let result = try await model.startBatch(AIBatchStartOptions(
        requests: [
            AILanguageModelBatchRequest(
                id: "france",
                request: LanguageModelRequest(messages: [.user("What is the capital of France?")])
            ),
            AILanguageModelBatchRequest(
                id: "compact",
                request: LanguageModelRequest(
                    messages: [.user("Compact this context.")],
                    topK: 10,
                    providerOptions: ["openai": ["compactionTrigger": true]]
                )
            )
        ],
        abortSignal: abortController.signal,
        headers: ["Operation-Header": "operation"]
    ))

    #expect(result.batchID == "batch_123")
    #expect(result.status.status == .pending)
    #expect(result.status.rawStatus == "validating")
    #expect(result.status.requestCounts == AIBatchRequestCounts(
        total: 2,
        pending: 2,
        completed: 0,
        failed: 0
    ))
    #expect(result.status.createdAt == "2023-11-14T22:13:20.000Z")
    #expect(result.status.expiresAt == "2023-11-15T22:13:20.000Z")
    #expect(result.warnings.contains {
        $0.requestID == "compact"
            && $0.warning.type == "unsupported"
            && $0.warning.feature == "topK"
    })

    let requests = await transport.sendRequests()
    #expect(requests.count == 2)
    #expect(requests[0].url.absoluteString == "https://api.openai.com/v1/files")
    #expect(requests[1].url.absoluteString == "https://api.openai.com/v1/batches")
    #expect(normalizeHeaders(requests[0].headers)["authorization"] == "Bearer test-api-key")
    #expect(normalizeHeaders(requests[0].headers)["provider-header"] == "provider")
    #expect(normalizeHeaders(requests[0].headers)["operation-header"] == "operation")
    #expect(requests[0].abortSignal === abortController.signal)
    #expect(requests[1].abortSignal === abortController.signal)

    let multipartBody = try #require(requests[0].body)
    let multipart = try #require(String(data: multipartBody, encoding: .utf8))
    #expect(multipart.contains(#"name="file"; filename="batch.jsonl""#))
    #expect(multipart.contains("Content-Type: application/jsonl"))
    #expect(multipart.contains("name=\"purpose\"\r\n\r\nbatch"))
    #expect(multipart.contains("name=\"expires_after[anchor]\"\r\n\r\ncreated_at"))
    #expect(multipart.contains("name=\"expires_after[seconds]\"\r\n\r\n172800"))
    let lines = try openAIBatchMultipartJSONLines(multipart)
    #expect(lines.count == 2)
    #expect(lines[0]["custom_id"]?.stringValue == "france")
    #expect(lines[0]["method"]?.stringValue == "POST")
    #expect(lines[0]["url"]?.stringValue == "/v1/responses")
    #expect(lines[0]["body"]?["model"]?.stringValue == "gpt-5.6")
    #expect(lines[0]["body"]?["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "What is the capital of France?")
    #expect(lines[1]["body"]?["input"]?[1]?["type"]?.stringValue == "compaction_trigger")

    let createBody = try decodeJSONBody(try #require(requests[1].body))
    #expect(createBody == [
        "input_file_id": "file-input",
        "endpoint": "/v1/responses",
        "completion_window": "24h"
    ])
}

@Test func openAIResponsesBatchV4MapsAllStatusesAndNormalizesCountsAndErrors() async throws {
    let cases: [(String, AIBatchLifecycleStatus)] = [
        ("validating", .pending),
        ("in_progress", .pending),
        ("finalizing", .pending),
        ("cancelling", .pending),
        ("completed", .completed),
        ("failed", .failed),
        ("expired", .failed),
        ("cancelled", .failed),
        ("future_status", .pending)
    ]
    for (rawStatus, expected) in cases {
        let transport = OpenAIBatchScriptedTransport(sendResponses: [
            jsonResponse(openAIBatchMetadata(status: rawStatus))
        ])
        let provider = try AIProviders.openAI(settings: ProviderSettings(
            apiKey: "test-api-key",
            transport: transport
        ))
        let model = try provider.batchLanguageModel("gpt-5.6")
        let status = try await model.getBatchStatus(AIBatchOperationOptions(batchID: "batch_123"))
        #expect(status.status == expected)
        #expect(status.rawStatus == rawStatus)
    }

    let transport = OpenAIBatchScriptedTransport(sendResponses: [jsonResponse("""
    {
      "id":"batch_123",
      "status":"failed",
      "created_at":1700000000,
      "expires_at":1700086400,
      "request_counts":{"total":5,"completed":2,"failed":1},
      "errors":{"data":[{"code":"invalid_request","message":"Invalid input file."}]}
    }
    """)])
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-api-key", transport: transport))
    let status = try await provider.batchLanguageModel("gpt-5.6").getBatchStatus(
        AIBatchOperationOptions(batchID: "batch_123")
    )
    #expect(status.requestCounts == AIBatchRequestCounts(
        total: 5,
        pending: 2,
        completed: 2,
        failed: 1
    ))
    #expect(status.error == AIBatchError(
        message: "Invalid input file.",
        code: "invalid_request"
    ))
}

@Test func openAIResponsesBatchV4IncrementallyParsesSuccessAndTerminalFailuresAcrossBothFiles() async throws {
    let success = openAIBatchResultLine(
        id: "france",
        statusCode: 200,
        body: try secureJSONParse(openAIResponsesBatchResultBody(text: "Paris"))
    )
    let httpError = openAIBatchResultLine(
        id: "http-error",
        statusCode: 400,
        body: ["error": [
            "message": "Invalid request.",
            "type": "invalid_request_error",
            "param": nil,
            "code": "invalid_request"
        ]]
    )
    let errors = """
    {"custom_id":"cancelled","response":null,"error":{"code":"batch_cancelled","message":"Batch cancelled."}}
    {"custom_id":"expired","response":null,"error":{"code":"batch_expired","message":"Batch expired."}}
    {"custom_id":"failed","response":null,"error":{"code":"request_timeout","message":"Request timed out."}}
    """
    let combinedOutput = "\(success)\r\n\(httpError)"
    let outputData = Data(combinedOutput.utf8)
    let firstSplit = outputData.index(outputData.startIndex, offsetBy: 19)
    let secondSplit = outputData.index(firstSplit, offsetBy: 37)
    let transport = OpenAIBatchScriptedTransport(
        sendResponses: [jsonResponse(openAIBatchMetadata(
            status: "completed",
            outputFileID: "file-output",
            errorFileID: "file-errors"
        ))],
        streamScripts: [
            OpenAIBatchStreamScript(chunks: [
                Data(outputData[..<firstSplit]),
                Data(outputData[firstSplit..<secondSplit]),
                Data(outputData[secondSplit...])
            ]),
            OpenAIBatchStreamScript(chunks: [Data(errors.utf8)])
        ]
    )
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-api-key", transport: transport))
    let model = try provider.batchLanguageModel("gpt-5.6")
    let stream = try await model.getBatchResults(AIBatchOperationOptions(
        batchID: "batch_123",
        headers: ["Operation-Header": "operation"]
    ))
    var items: [AIBatchItemResult<TextGenerationResult>] = []
    for try await item in stream { items.append(item) }

    #expect(items.count == 5)
    guard case let .succeeded(id, result) = items[0] else {
        Issue.record("Expected successful Responses batch item")
        return
    }
    #expect(id == "france")
    #expect(result.content == [.text("Paris")])
    #expect(result.finishReason == "stop")
    #expect(result.usage?.inputTokens == 10)
    #expect(result.usage?.inputTokensNoCache == 8)
    #expect(result.usage?.inputTokensCacheRead == 2)
    #expect(result.usage?.outputTokens == 3)
    #expect(result.usage?.outputTextTokens == 2)
    #expect(result.usage?.outputReasoningTokens == 1)
    #expect(result.responseMetadata.id == "resp_123")
    #expect(result.responseMetadata.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(result.responseMetadata.modelID == "gpt-5.6")
    #expect(result.providerMetadata["openai"]?["responseId"]?.stringValue == "resp_123")
    #expect(result.providerMetadata["openai"]?["serviceTier"]?.stringValue == "default")

    guard case let .failed(httpID, httpFailure, _) = items[1] else {
        Issue.record("Expected HTTP item failure")
        return
    }
    #expect(httpID == "http-error")
    #expect(httpFailure == AIBatchError(
        message: "Invalid request.",
        type: "invalid_request_error",
        code: "invalid_request",
        statusCode: 400
    ))
    guard case let .cancelled(cancelledID, cancelledError, _) = items[2] else {
        Issue.record("Expected cancelled item")
        return
    }
    #expect(cancelledID == "cancelled")
    #expect(cancelledError?.code == "batch_cancelled")
    guard case let .expired(expiredID, expiredError, _) = items[3] else {
        Issue.record("Expected expired item")
        return
    }
    #expect(expiredID == "expired")
    #expect(expiredError?.code == "batch_expired")
    guard case let .failed(failedID, failedError, _) = items[4] else {
        Issue.record("Expected failed item")
        return
    }
    #expect(failedID == "failed")
    #expect(failedError.code == "request_timeout")

    let streamRequests = await transport.streamRequests()
    #expect(streamRequests.map(\.url.absoluteString) == [
        "https://api.openai.com/v1/files/file-output/content",
        "https://api.openai.com/v1/files/file-errors/content"
    ])
    #expect(normalizeHeaders(streamRequests[0].headers)["operation-header"] == "operation")
}

@Test func openAIResponsesBatchV4RejectsPendingResultsAndCompletedBatchWithoutOutput() async throws {
    let pendingTransport = OpenAIBatchScriptedTransport(sendResponses: [jsonResponse(openAIBatchMetadata(
        status: "in_progress",
        total: 2,
        completed: 1,
        failed: 0
    ))])
    let pendingProvider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-api-key",
        transport: pendingTransport
    ))
    await #expect(throws: AIError.self) {
        _ = try await pendingProvider.batchLanguageModel("gpt-5.6").getBatchResults(
            AIBatchOperationOptions(batchID: "batch_123")
        )
    }

    let terminalTransport = OpenAIBatchScriptedTransport(sendResponses: [
        jsonResponse(openAIBatchMetadata(status: "completed"))
    ])
    let terminalProvider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-api-key",
        transport: terminalTransport
    ))
    await #expect(throws: AIError.invalidResponse(
        provider: "openai.responses",
        message: "OpenAI batch \"batch_123\" completed without batch output."
    )) {
        _ = try await terminalProvider.batchLanguageModel("gpt-5.6").getBatchResults(
            AIBatchOperationOptions(batchID: "batch_123")
        )
    }
    #expect(await terminalTransport.streamRequests().isEmpty)
}

@Test func openAIResponsesBatchV4ConvertsToolCallsToItemFailuresAndMalformedJSONLToStreamErrors() async throws {
    let toolCallBody: JSONValue = [
        "id": "resp_tool",
        "created_at": 1_700_000_000,
        "model": "gpt-5.6",
        "output": [[
            "type": "function_call",
            "id": "function-call",
            "call_id": "call-123",
            "name": "get_weather",
            "arguments": #"{"city":"Paris"}"#,
            "namespace": nil,
            "caller": nil
        ]],
        "incomplete_details": nil
    ]
    let valid = openAIBatchResultLine(id: "tool", statusCode: 200, body: toolCallBody)
    let transport = OpenAIBatchScriptedTransport(
        sendResponses: [jsonResponse(openAIBatchMetadata(
            status: "completed",
            outputFileID: "file-output"
        ))],
        streamScripts: [OpenAIBatchStreamScript(chunks: [Data("\(valid)\n{not json}\n".utf8)])]
    )
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-api-key", transport: transport))
    let stream = try await provider.batchLanguageModel("gpt-5.6").getBatchResults(
        AIBatchOperationOptions(batchID: "batch_123")
    )
    var iterator = stream.makeAsyncIterator()
    let first = try #require(try await iterator.next())
    guard case let .failed(id, error, _) = first else {
        Issue.record("Expected tool-call item failure")
        return
    }
    #expect(id == "tool")
    #expect(error.code == "unsupported_content")
    await #expect(throws: (any Error).self) {
        _ = try await iterator.next()
    }
}

@Test func openAIResponsesBatchV4KeepsInvalidAndUnsupportedItemsLocalAndPreservesReasoningMetadata() async throws {
    let invalid = openAIBatchResultLine(
        id: "invalid",
        statusCode: 200,
        body: ["output": 42]
    )
    let image = openAIBatchResultLine(
        id: "image",
        statusCode: 200,
        body: [
            "id": "resp_image",
            "output": [[
                "type": "image_generation_call",
                "id": "image_123",
                "result": "aW1hZ2U="
            ]]
        ]
    )
    let reasoning = openAIBatchResultLine(
        id: "reasoning",
        statusCode: 200,
        body: [
            "id": "resp_reasoning",
            "created_at": 1_700_000_000,
            "model": "gpt-5.6",
            "output": [
                [
                    "type": "reasoning",
                    "id": "reasoning_123",
                    "encrypted_content": "encrypted-reasoning",
                    "summary": [[
                        "type": "summary_text",
                        "text": "I should answer directly."
                    ]]
                ],
                [
                    "type": "message",
                    "role": "assistant",
                    "id": "message_123",
                    "content": [[
                        "type": "output_text",
                        "text": "Paris",
                        "annotations": [],
                        "logprobs": [[
                            "token": "Paris",
                            "logprob": -0.1,
                            "top_logprobs": []
                        ]]
                    ]]
                ]
            ],
            "reasoning": ["context": "reasoning-context"],
            "incomplete_details": nil,
            "usage": [
                "input_tokens": 1,
                "output_tokens": 1,
                "input_tokens_details": ["cached_tokens": 0],
                "output_tokens_details": ["reasoning_tokens": 1]
            ]
        ]
    )
    let transport = OpenAIBatchScriptedTransport(
        sendResponses: [jsonResponse(openAIBatchMetadata(
            status: "completed",
            outputFileID: "file-output",
            total: 3,
            completed: 3,
            failed: 0
        ))],
        streamScripts: [OpenAIBatchStreamScript(chunks: [Data("\(invalid)\n\(image)\n\(reasoning)".utf8)])]
    )
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-api-key", transport: transport))
    let stream = try await provider.batchLanguageModel("gpt-5.6").getBatchResults(
        AIBatchOperationOptions(batchID: "batch_123")
    )
    var items: [AIBatchItemResult<TextGenerationResult>] = []
    for try await item in stream { items.append(item) }

    #expect(items.count == 3)
    guard case let .failed(invalidID, invalidError, _) = items[0] else {
        Issue.record("Expected an item-local invalid response")
        return
    }
    #expect(invalidID == "invalid")
    #expect(invalidError == AIBatchError(
        message: "OpenAI returned an invalid Responses batch result.",
        code: "invalid_response"
    ))
    guard case let .failed(imageID, imageError, _) = items[1] else {
        Issue.record("Expected an item-local unsupported response")
        return
    }
    #expect(imageID == "image")
    #expect(imageError == AIBatchError(
        message: "OpenAI returned an unsupported \"image_generation_call\" output item in an AI SDK text batch.",
        code: "unsupported_content"
    ))
    guard case let .succeeded(reasoningID, result) = items[2] else {
        Issue.record("Expected the later reasoning result to succeed")
        return
    }
    #expect(reasoningID == "reasoning")
    #expect(result.text == "Paris")
    guard case let .reasoning(text, metadata) = result.content[0] else {
        Issue.record("Expected reasoning content")
        return
    }
    #expect(text == "I should answer directly.")
    #expect(metadata["openai"]?["itemId"]?.stringValue == "reasoning_123")
    #expect(metadata["openai"]?["reasoningEncryptedContent"]?.stringValue == "encrypted-reasoning")
    #expect(result.providerMetadata["openai"]?["reasoningContext"]?.stringValue == "reasoning-context")
    #expect(result.providerMetadata["openai"]?["logprobs"]?[0]?[0]?["token"]?.stringValue == "Paris")
}

@Test func openAIResponsesBatchV4IsExposedOnlyByOpenAIResponsesFactorySurfaces() throws {
    let provider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-api-key",
        transport: RecordingTransport(response: jsonResponse("{}"))
    ))
    #expect(try provider("gpt-5.6") is any BatchLanguageModel)
    #expect(try provider.languageModel("gpt-5.6") is any BatchLanguageModel)
    #expect(try provider.responses("gpt-5.6") is any BatchLanguageModel)
    #expect(!(try provider.chat("gpt-5.6") is any BatchLanguageModel))
    #expect(!(try provider.completion("gpt-3.5-turbo-instruct") is any BatchLanguageModel))
    #expect(!(try provider.image("gpt-image-1") is any BatchLanguageModel))
}

private actor OpenAIBatchScriptedTransport: AIStreamingTransport {
    private var sendResponsesQueue: [AIHTTPResponse]
    private var streamScriptsQueue: [OpenAIBatchStreamScript]
    private var recordedSendRequests: [AIHTTPRequest] = []
    private var recordedStreamRequests: [AIHTTPRequest] = []

    init(
        sendResponses: [AIHTTPResponse],
        streamScripts: [OpenAIBatchStreamScript] = []
    ) {
        self.sendResponsesQueue = sendResponses
        self.streamScriptsQueue = streamScripts
    }

    func sendRequests() -> [AIHTTPRequest] { recordedSendRequests }
    func streamRequests() -> [AIHTTPRequest] { recordedStreamRequests }

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        recordedSendRequests.append(request)
        guard !sendResponsesQueue.isEmpty else {
            throw AIError.invalidResponse(provider: "test", message: "No scripted send response.")
        }
        return sendResponsesQueue.removeFirst()
    }

    func stream(_ request: AIHTTPRequest) async throws -> AIHTTPStreamResponse {
        recordedStreamRequests.append(request)
        guard !streamScriptsQueue.isEmpty else {
            throw AIError.invalidResponse(provider: "test", message: "No scripted stream response.")
        }
        let script = streamScriptsQueue.removeFirst()
        return AIHTTPStreamResponse(
            statusCode: script.statusCode,
            headers: script.headers,
            body: AsyncThrowingStream { continuation in
                for chunk in script.chunks { continuation.yield(chunk) }
                continuation.finish()
            }
        )
    }
}

private struct OpenAIBatchStreamScript: Sendable {
    var statusCode: Int = 200
    var headers: [String: String] = ["content-type": "application/jsonl"]
    var chunks: [Data]
}

private func openAIBatchMetadata(
    status: String,
    outputFileID: String? = nil,
    errorFileID: String? = nil,
    total: Int = 2,
    completed: Int = 2,
    failed: Int = 0
) -> String {
    let output = outputFileID.map { #""\#($0)""# } ?? "null"
    let errors = errorFileID.map { #""\#($0)""# } ?? "null"
    return """
    {
      "id":"batch_123",
      "status":"\(status)",
      "output_file_id":\(output),
      "error_file_id":\(errors),
      "created_at":1700000000,
      "expires_at":1700086400,
      "request_counts":{"total":\(total),"completed":\(completed),"failed":\(failed)},
      "errors":null
    }
    """
}

private func openAIResponsesBatchResultBody(text: String) -> String {
    """
    {
      "id":"resp_123",
      "created_at":1700000000,
      "model":"gpt-5.6",
      "output":[{
        "type":"message",
        "role":"assistant",
        "id":"msg_123",
        "phase":null,
        "content":[{"type":"output_text","text":"\(text)","logprobs":null,"annotations":[]}]
      }],
      "service_tier":"default",
      "reasoning":null,
      "incomplete_details":null,
      "usage":{
        "input_tokens":10,
        "input_tokens_details":{"cached_tokens":2},
        "output_tokens":3,
        "output_tokens_details":{"reasoning_tokens":1}
      }
    }
    """
}

private func openAIBatchResultLine(id: String, statusCode: Int, body: JSONValue) -> String {
    let line: JSONValue = [
        "custom_id": .string(id),
        "response": [
            "status_code": .number(Double(statusCode)),
            "request_id": .string("openai-\(id)"),
            "body": body
        ],
        "error": .null
    ]
    return String(data: try! encodeJSONBody(line), encoding: .utf8)!
}

private func openAIBatchMultipartJSONLines(_ multipart: String) throws -> [JSONValue] {
    let marker = "Content-Type: application/jsonl\r\n\r\n"
    guard let start = multipart.range(of: marker)?.upperBound,
          let end = multipart.range(of: "\r\n--", range: start..<multipart.endIndex)?.lowerBound else {
        throw AIError.invalidResponse(provider: "test", message: "Multipart JSONL file part was not found.")
    }
    return try multipart[start..<end]
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map { try secureJSONParse(String($0)) }
}
