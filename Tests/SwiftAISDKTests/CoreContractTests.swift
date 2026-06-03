import Foundation
import Testing
@testable import SwiftAISDK

@Test func languageModelRequestCarriesV4CallOptions() {
    let request = LanguageModelRequest(
        messages: [.user("hello")],
        temperature: 0.2,
        topP: 0.9,
        topK: 40,
        presencePenalty: 0.1,
        frequencyPenalty: 0.3,
        seed: 123,
        maxOutputTokens: 256,
        stopSequences: ["END"],
        responseFormat: .json(schema: .object(["type": .string("object")]), name: "Answer", description: "Structured answer"),
        reasoning: "high",
        tools: ["lookup": .object(["type": .string("function")])],
        toolChoice: .object(["type": .string("auto")]),
        includeRawChunks: true,
        providerOptions: ["openai": .object(["parallelToolCalls": .bool(false)])],
        extraBody: ["user": .string("user-1")],
        headers: ["x-test": "1"]
    )

    #expect(request.topK == 40)
    #expect(request.presencePenalty == 0.1)
    #expect(request.frequencyPenalty == 0.3)
    #expect(request.seed == 123)
    #expect(request.responseFormat == .json(schema: .object(["type": .string("object")]), name: "Answer", description: "Structured answer"))
    #expect(request.reasoning == "high")
    #expect(request.toolChoice?["type"]?.stringValue == "auto")
    #expect(request.includeRawChunks)
    #expect(request.providerOptions["openai"]?["parallelToolCalls"]?.boolValue == false)
    #expect(request.extraBody["user"]?.stringValue == "user-1")
}

@Test func typedCoreErrorsExposeUsefulDiagnostics() throws {
    let apiError = AIAPICallError(
        provider: "mock",
        url: "https://api.example.test/v1",
        requestBody: ["prompt": "hello"],
        statusCode: 503,
        responseHeaders: ["Retry-After": "1"],
        responseBody: "try later"
    )
    #expect(apiError.isRetryable)
    #expect(apiError.description.contains("HTTP 503"))
    #expect(apiError.requestBody?["prompt"]?.stringValue == "hello")

    do {
        _ = try parseJSON(
            #"{"count":"many"}"#,
            schema: [
                "type": "object",
                "properties": ["count": ["type": "integer"]],
                "required": ["count"]
            ]
        )
        Issue.record("Expected type validation error.")
    } catch let error as AITypeValidationError {
        #expect(error.path == "$.count")
        #expect(error.message.contains("expected integer"))
    }

    let noOutput = AINoOutputGeneratedError(provider: "mock", outputKind: .object)
    #expect(noOutput.description.contains("mock"))
    #expect(noOutput.description.contains("object output"))
}

@Test func languageStreamPartRepresentsV4LifecycleMetadataAndToolParts() {
    let response = AIResponseMetadata(
        id: "resp-1",
        timestamp: Date(timeIntervalSince1970: 1_772_078_479),
        modelID: "model-1",
        headers: ["x-request-id": "req-1"],
        body: .object(["id": .string("resp-1")])
    )
    let toolResult = AIToolResult(
        toolCallID: "call-1",
        toolName: "lookup",
        result: .object(["ok": .bool(true)]),
        preliminary: true,
        dynamic: true,
        providerMetadata: ["provider": .object(["trace": .string("trace-1")])]
    )
    let approval = AIToolApprovalRequest(id: "approval-1", toolName: "lookup", arguments: "{\"q\":\"hi\"}")
    let file = AIStreamFile(id: "file-1", mediaType: "application/pdf", filename: "report.pdf")

    let parts: [LanguageStreamPart] = [
        .streamStart(warnings: [AIWarning(type: "unsupported", feature: "seed")]),
        .textStart(id: "text-1", providerMetadata: ["provider": .object(["block": .number(1)])]),
        .textDeltaPart(id: "text-1", delta: "hello"),
        .textEnd(id: "text-1"),
        .reasoningStart(id: "reasoning-1"),
        .reasoningDeltaPart(id: "reasoning-1", delta: "thinking"),
        .reasoningEnd(id: "reasoning-1"),
        .toolInputStart(id: "call-1", name: "lookup", providerExecuted: true, dynamic: true, title: "Lookup"),
        .toolInputDelta(id: "call-1", delta: "{\"q\""),
        .toolInputEnd(id: "call-1"),
        .toolResult(toolResult),
        .toolApprovalRequest(approval),
        .file(file),
        .reasoningFile(file),
        .custom(.object(["type": .string("provider-event")]), providerMetadata: ["provider": .object(["kind": .string("custom")])]),
        .responseMetadata(response),
        .error(message: "provider error", rawValue: .object(["code": .string("bad")]))
    ]

    #expect(parts.first == .streamStart(warnings: [AIWarning(type: "unsupported", feature: "seed")]))
    #expect(parts.contains(.toolResult(toolResult)))
    #expect(parts.contains(.toolApprovalRequest(approval)))
    #expect(parts.contains(.responseMetadata(response)))
    #expect(parts.contains(.error(message: "provider error", rawValue: .object(["code": .string("bad")]))))
}

@Test func resultTypesCarrySharedWarningsAndMetadataWithoutBreakingDefaults() {
    let response = AIResponseMetadata(id: "resp-1", modelID: "model-1", headers: ["x-request-id": "req-1"])
    let request = AIRequestMetadata(body: .object(["model": .string("model-1")]), headers: ["x-test": "1"])
    let providerMetadata: [String: JSONValue] = ["provider": .object(["detail": .string("kept")])]
    let warning = AIWarning(type: "unsupported", feature: "seed")

    let text = TextGenerationResult(
        text: "hello",
        rawValue: .object([:]),
        requestMetadata: request,
        responseMetadata: response
    )
    #expect(text.requestMetadata == request)
    #expect(text.responseMetadata == response)
    #expect(text.warnings.isEmpty)

    let embedding = EmbeddingResult(
        embeddings: [[0.1]],
        rawValue: .object([:]),
        warnings: [warning],
        providerMetadata: providerMetadata,
        requestMetadata: request,
        responseMetadata: response
    )
    #expect(embedding.warnings == [warning])
    #expect(embedding.providerMetadata == providerMetadata)
    #expect(embedding.requestMetadata == request)
    #expect(embedding.responseMetadata == response)

    let image = ImageGenerationResult(
        urls: ["https://example.com/image.png"],
        rawValue: .object([:]),
        warnings: [warning],
        usage: TokenUsage(inputTokens: 2),
        providerMetadata: providerMetadata,
        requestMetadata: request,
        responseMetadata: response
    )
    #expect(image.usage?.inputTokens == 2)
    #expect(image.providerMetadata == providerMetadata)
    #expect(image.requestMetadata == request)

    let transcription = TranscriptionResult(
        text: "hello",
        rawValue: .object([:]),
        segments: [TranscriptionSegment(text: "hello", startSecond: 0, endSecond: 1.2)],
        language: "en",
        durationInSeconds: 1.2,
        warnings: [warning],
        providerMetadata: providerMetadata,
        requestMetadata: request,
        responseMetadata: response
    )
    #expect(transcription.segments.first?.endSecond == 1.2)
    #expect(transcription.language == "en")
    #expect(transcription.requestMetadata == request)

    let speech = SpeechResult(audio: Data("audio".utf8), warnings: [warning], providerMetadata: providerMetadata, requestMetadata: request, responseMetadata: response)
    #expect(speech.warnings == [warning])
    #expect(speech.requestMetadata == request)

    let video = VideoGenerationResult(urls: [], rawValue: .object([:]), warnings: [warning], providerMetadata: providerMetadata, requestMetadata: request, responseMetadata: response)
    #expect(video.providerMetadata == providerMetadata)
    #expect(video.requestMetadata == request)

    let reranking = RerankingResult(results: [], rawValue: .object([:]), warnings: [warning], providerMetadata: providerMetadata, requestMetadata: request, responseMetadata: response)
    #expect(reranking.requestMetadata == request)
    #expect(reranking.responseMetadata == response)

    let file = FileUploadResult(providerReference: ["file": "file-1"], rawValue: .object([:]), warnings: [warning], providerMetadata: providerMetadata, requestMetadata: request, responseMetadata: response)
    #expect(file.providerMetadata == providerMetadata)
    #expect(file.warnings == [warning])
    #expect(file.requestMetadata == request)

    let skill = SkillUploadResult(providerReference: ["skill": "skill-1"], providerMetadata: providerMetadata, requestMetadata: request, responseMetadata: response, warnings: [warning], rawValue: .object([:]))
    #expect(skill.providerMetadata == providerMetadata)
    #expect(skill.requestMetadata == request)
    #expect(skill.responseMetadata == response)
    #expect(skill.warnings == [warning])
}
