import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiEmbedManyChunksAndAggregatesResults() async throws {
    let recorder = TelemetryRecorder()
    let model = MockEmbeddingModel(results: [
        EmbeddingResult(
            embeddings: [[0.1], [0.2]],
            usage: TokenUsage(inputTokens: 2, totalTokens: 2),
            rawValue: .object(["chunk": .number(1)]),
            warnings: [AIWarning(type: "unsupported", feature: "seed")],
            providerMetadata: ["provider": .object(["first": .bool(true)])],
            responseMetadata: AIResponseMetadata(id: "resp-1")
        ),
        EmbeddingResult(
            embeddings: [[0.3]],
            usage: TokenUsage(inputTokens: 1, totalTokens: 1),
            rawValue: .object(["chunk": .number(2)]),
            providerMetadata: ["provider": .object(["second": .bool(true)])]
        )
    ])

    let result = try await AI.embedMany(
        model: model,
        values: ["a", "b", "c"],
        dimensions: 64,
        chunkSize: 2,
        providerOptions: ["test": .object(["flag": .bool(true)])],
        telemetry: Telemetry.Options(integrations: [recorder])
    )
    let events = await recorder.events()

    #expect(model.requests.map(\.values) == [["a", "b"], ["c"]])
    #expect(model.requests.allSatisfy { $0.dimensions == 64 })
    #expect(model.requests.allSatisfy { $0.providerOptions["test"]?["flag"]?.boolValue == true })
    #expect(events.map(\.kind) == [.start, .end])
    #expect(events.allSatisfy { $0.operationID == "ai.embedMany" })
    #expect(events[0].input?["values"]?[2]?.stringValue == "c")
    #expect(events[1].output?["embeddings"]?[2]?[0]?.doubleValue == 0.3)
    #expect(events[1].usage == TokenUsage(inputTokens: 3, totalTokens: 3))
    #expect(result.embeddings == [[0.1], [0.2], [0.3]])
    #expect(result.usage == TokenUsage(inputTokens: 3, totalTokens: 3))
    #expect(result.rawValue[0]?["chunk"]?.intValue == 1)
    #expect(result.rawValue[1]?["chunk"]?.intValue == 2)
    #expect(result.warnings == [AIWarning(type: "unsupported", feature: "seed")])
    #expect(result.providerMetadata["provider"]?["second"]?.boolValue == true)
    #expect(result.responseMetadata.id == "resp-1")
}

@Test func aiEmbedManySplitsByUTF8BytesAndCountInOnePassLikeUpstream() async throws {
    let model = MockEmbeddingModel(
        results: [
            EmbeddingResult(embeddings: [[1], [2]], rawValue: ["chunk": 1]),
            EmbeddingResult(embeddings: [[3], [4]], rawValue: ["chunk": 2])
        ],
        maxEmbeddingsPerCall: 3,
        maxInputBytesPerCall: 10
    )

    let result = try await AI.embedMany(
        model: model,
        values: ["12345678", "12", "12", "12345678"]
    )

    #expect(model.requests.map(\.values) == [
        ["12345678", "12"],
        ["12", "12345678"]
    ])
    #expect(result.embeddings == [[1], [2], [3], [4]])
}

@Test func aiEmbedManyDoesNotLetCallerChunkSizeExceedProviderMaximum() async throws {
    let model = MockEmbeddingModel(
        results: [
            EmbeddingResult(embeddings: [[1], [2]], rawValue: ["chunk": 1]),
            EmbeddingResult(embeddings: [[3], [4]], rawValue: ["chunk": 2]),
            EmbeddingResult(embeddings: [[5]], rawValue: ["chunk": 3])
        ],
        maxEmbeddingsPerCall: 2
    )

    _ = try await AI.embedMany(
        model: model,
        values: ["a", "b", "c", "d", "e"],
        chunkSize: 4
    )

    #expect(model.requests.map(\.values) == [["a", "b"], ["c", "d"], ["e"]])
}

@Test func aiEmbedManyWithLimitsReturnsEmptyWithoutCallingProviderLikeUpstream() async throws {
    let recorder = TelemetryRecorder()
    let model = MockEmbeddingModel(results: [], maxEmbeddingsPerCall: 2)

    let result = try await AI.embedMany(
        model: model,
        values: [],
        telemetry: Telemetry.Options(integrations: [recorder])
    )

    #expect(model.requests.isEmpty)
    #expect(result.embeddings.isEmpty)
    #expect(result.usage == TokenUsage(inputTokens: 0, totalTokens: 0))
    #expect(result.rawValue == .array([JSONValue]()))
    #expect(result.requestMetadata.body?["values"]?.arrayValue == [])
    #expect((await recorder.events()).map(\.kind) == [.start, .end])
}

@Test func aiEmbedManyUsesUTF8ByteCountsAndKeepsOversizedInputsWholeLikeUpstream() async throws {
    let unicodeModel = MockEmbeddingModel(
        results: [
            EmbeddingResult(embeddings: [[1]], rawValue: ["chunk": 1]),
            EmbeddingResult(embeddings: [[2], [3]], rawValue: ["chunk": 2])
        ],
        maxInputBytesPerCall: 7
    )

    _ = try await AI.embedMany(model: unicodeModel, values: ["éé", "éé", "abc"])
    #expect(unicodeModel.requests.map(\.values) == [["éé"], ["éé", "abc"]])

    let oversizedModel = MockEmbeddingModel(
        results: [
            EmbeddingResult(embeddings: [[1]], rawValue: ["chunk": 1]),
            EmbeddingResult(embeddings: [[2]], rawValue: ["chunk": 2])
        ],
        maxInputBytesPerCall: 3
    )

    _ = try await AI.embedMany(model: oversizedModel, values: ["abcd", "e"])
    #expect(oversizedModel.requests.map(\.values) == [["abcd"], ["e"]])
}

@Test func aiEmbedManyRejectsProviderResultCountMismatchesLikeUpstream() async throws {
    let singleCallModel = MockEmbeddingModel(results: [
        EmbeddingResult(embeddings: [[1]], rawValue: ["call": 1])
    ])
    await #expect(throws: AIError.invalidResponse(
        provider: "mock",
        message: "Expected 2 embeddings, but received 1."
    )) {
        _ = try await AI.embedMany(model: singleCallModel, values: ["a", "b"])
    }

    let chunkedModel = MockEmbeddingModel(
        results: [
            EmbeddingResult(embeddings: [[1], [2]], rawValue: ["chunk": 1]),
            EmbeddingResult(embeddings: [[3]], rawValue: ["chunk": 2])
        ],
        maxEmbeddingsPerCall: 2
    )
    await #expect(throws: AIError.invalidResponse(
        provider: "mock",
        message: "Expected 2 embeddings, but received 1."
    )) {
        _ = try await AI.embedMany(model: chunkedModel, values: ["a", "b", "c", "d"])
    }
}

@Test func aiFacadeForwardsMediaRerankAndUploadRequests() async throws {
    let imageModel = MockImageModel(result: ImageGenerationResult(urls: ["https://example.com/image.png"], rawValue: .object([:])))
    let image = try await AI.generateImage(model: imageModel, prompt: "cat", size: "1024x1024", providerOptions: ["image": .object(["quality": .string("high")])])
    #expect(image.urls == ["https://example.com/image.png"])
    #expect(image.requestMetadata.body?["prompt"]?.stringValue == "cat")
    #expect(image.requestMetadata.body?["size"]?.stringValue == "1024x1024")
    #expect(image.requestMetadata.body?["providerOptions"]?["image"]?["quality"]?.stringValue == "high")
    #expect(imageModel.requests.first?.prompt == "cat")
    #expect(imageModel.requests.first?.providerOptions["image"]?["quality"]?.stringValue == "high")

    let transcriptionModel = MockTranscriptionModel(result: TranscriptionResult(text: "hello", rawValue: .object([:])))
    let transcription = try await AI.transcribe(model: transcriptionModel, request: AudioTranscriptionRequest(audio: Data("wav".utf8), language: "en"))
    #expect(transcription.text == "hello")
    #expect(transcription.requestMetadata.body?["byteLength"]?.intValue == 3)
    #expect(transcription.requestMetadata.body?["language"]?.stringValue == "en")
    #expect(transcription.requestMetadata.body?["audio"] == nil)
    #expect(transcriptionModel.requests.first?.language == "en")

    let speechModel = MockSpeechModel(result: SpeechResult(audio: Data("audio".utf8)))
    let speech = try await AI.generateSpeech(model: speechModel, request: SpeechRequest(text: "hello", voice: "alloy", speed: 1.2, language: "en", instructions: "Warm"))
    #expect(String(data: speech.audio, encoding: .utf8) == "audio")
    #expect(speech.requestMetadata.body?["text"]?.stringValue == "hello")
    #expect(speech.requestMetadata.body?["voice"]?.stringValue == "alloy")
    #expect(speech.requestMetadata.body?["speed"]?.doubleValue == 1.2)
    #expect(speech.requestMetadata.body?["language"]?.stringValue == "en")
    #expect(speech.requestMetadata.body?["instructions"]?.stringValue == "Warm")
    #expect(speechModel.requests.first?.voice == "alloy")
    #expect(speechModel.requests.first?.speed == 1.2)
    #expect(speechModel.requests.first?.language == "en")
    #expect(speechModel.requests.first?.instructions == "Warm")

    let videoModel = MockVideoModel(result: VideoGenerationResult(urls: ["https://example.com/video.mp4"], rawValue: .object([:])))
    let video = try await AI.generateVideo(model: videoModel, request: VideoGenerationRequest(prompt: "clip", count: 2))
    #expect(video.urls == ["https://example.com/video.mp4"])
    #expect(video.requestMetadata.body?["prompt"]?.stringValue == "clip")
    #expect(video.requestMetadata.body?["count"]?.intValue == 2)
    #expect(videoModel.requests.first?.prompt == "clip")
    #expect(videoModel.requests.first?.count == 2)

    let rerankingModel = MockRerankingModel(result: RerankingResult(results: [RerankedDocument(index: 1, score: 0.9)], rawValue: .object([:])))
    let ranking = try await AI.rerank(model: rerankingModel, request: RerankingRequest(query: "q", documents: ["a", "b"], topK: 1))
    #expect(ranking.results.first?.index == 1)
    #expect(rerankingModel.requests.first?.topK == 1)

    let fileClient = MockFileClient(result: FileUploadResult(
        providerReference: ["file": "file-1"],
        rawValue: .object([:]),
        warnings: [AIWarning(type: "unsupported", feature: "displayName")],
        requestMetadata: AIRequestMetadata(body: .object(["file": .string("metadata")]))
    ))
    let file = try await AI.uploadFile(client: fileClient, request: FileUploadRequest(data: Data("file".utf8), mediaType: "text/plain", filename: "a.txt"))
    #expect(file.providerReference["file"] == "file-1")
    #expect(file.warnings == [AIWarning(type: "unsupported", feature: "displayName")])
    #expect(file.requestMetadata.body?["file"]?.stringValue == "metadata")
    #expect(fileClient.requests.first?.filename == "a.txt")

    let skillClient = MockSkillsClient(result: SkillUploadResult(
        providerReference: ["skill": "skill-1"],
        requestMetadata: AIRequestMetadata(body: .object(["skill": .string("metadata")])),
        responseMetadata: AIResponseMetadata(id: "skill-response"),
        rawValue: .object([:])
    ))
    let skill = try await AI.uploadSkill(client: skillClient, request: SkillUploadRequest(files: [SkillUploadFile(path: "skill.md", data: Data("skill".utf8))]))
    #expect(skill.providerReference["skill"] == "skill-1")
    #expect(skill.requestMetadata.body?["skill"]?.stringValue == "metadata")
    #expect(skill.responseMetadata.id == "skill-response")
    #expect(skillClient.requests.first?.files.first?.path == "skill.md")
}
@Test func aiFacadeThrowsTypedNoGeneratedMediaErrors() async throws {
    let response = AIResponseMetadata(id: "response-1", modelID: "mock")
    let failedCall = ImageGenerationCall(
        urls: [],
        warnings: [AIWarning(type: "other", message: "provider returned no images")],
        providerMetadata: ["mock": ["requestID": "request-1"]],
        responseMetadata: response
    )

    do {
        _ = try await AI.generateImage(
            model: MockImageModel(result: ImageGenerationResult(
                urls: [],
                base64Images: [],
                rawValue: .object([:]),
                responseMetadata: response,
                calls: [failedCall]
            )),
            prompt: "empty"
        )
        Issue.record("Expected image generation without images to fail")
    } catch let error as AINoOutputError {
        #expect(error.kind == .image)
        #expect(error.responses == [response])
        #expect(error.calls == [failedCall])
    }

    await #expect(throws: AINoOutputError(kind: .transcript, responses: [response])) {
        _ = try await AI.transcribe(
            model: MockTranscriptionModel(result: TranscriptionResult(
                text: "",
                rawValue: .object([:]),
                responseMetadata: response
            )),
            request: AudioTranscriptionRequest(audio: Data("wav".utf8))
        )
    }

    await #expect(throws: AINoOutputError(kind: .speech, responses: [response])) {
        _ = try await AI.generateSpeech(
            model: MockSpeechModel(result: SpeechResult(
                audio: Data(),
                responseMetadata: response
            )),
            request: SpeechRequest(text: "empty")
        )
    }

    await #expect(throws: AINoOutputError(kind: .video, responses: [response])) {
        _ = try await AI.generateVideo(
            model: MockVideoModel(result: VideoGenerationResult(
                urls: [],
                base64Videos: [],
                rawValue: .object([:]),
                responseMetadata: response
            )),
            request: VideoGenerationRequest(prompt: "empty")
        )
    }
}
@Test func aiFacadeFillsUploadRequestMetadataWhenCustomClientsDoNot() async throws {
    let fileClient = MockFileClient(result: FileUploadResult(providerReference: ["file": "file-1"], rawValue: .object([:])))
    let file = try await AI.uploadFile(client: fileClient, request: FileUploadRequest(
        data: Data("file".utf8),
        mediaType: "text/plain",
        filename: "a.txt",
        purpose: "assistants",
        displayName: "A"
    ))

    #expect(file.requestMetadata.body?["filename"]?.stringValue == "a.txt")
    #expect(file.requestMetadata.body?["mediaType"]?.stringValue == "text/plain")
    #expect(file.requestMetadata.body?["byteLength"]?.intValue == 4)
    #expect(file.requestMetadata.body?["data"] == nil)

    let skillClient = MockSkillsClient(result: SkillUploadResult(providerReference: ["skill": "skill-1"], rawValue: .object([:])))
    let skill = try await AI.uploadSkill(client: skillClient, request: SkillUploadRequest(
        files: [SkillUploadFile(path: "skill.md", data: Data("skill".utf8), mediaType: "text/markdown")],
        displayTitle: "Skill"
    ))

    #expect(skill.requestMetadata.body?["displayTitle"]?.stringValue == "Skill")
    #expect(skill.requestMetadata.body?["files"]?[0]?["path"]?.stringValue == "skill.md")
    #expect(skill.requestMetadata.body?["files"]?[0]?["mediaType"]?.stringValue == "text/markdown")
    #expect(skill.requestMetadata.body?["files"]?[0]?["byteLength"]?.intValue == 5)
    #expect(skill.requestMetadata.body?["files"]?[0]?["data"] == nil)
}

@Test func aiUploadFileAndSkillForwardProviderOptionsAndReturnProviderMetadataLikeUpstream() async throws {
    let fileClient = MockFileClient(result: FileUploadResult(
        providerReference: ["mock-provider": "file-abc123"],
        rawValue: .object([:]),
        warnings: [AIWarning(type: "unsupported", feature: "filename")],
        providerMetadata: ["mock-provider": ["size": 1_024]]
    ))
    let file = try await AI.uploadFile(client: fileClient, request: FileUploadRequest(
        data: Data([1, 2, 3]),
        mediaType: "application/octet-stream",
        filename: "test.pdf",
        providerOptions: ["mock-provider": ["purpose": "assistants"]]
    ))

    #expect(fileClient.requests.first?.providerOptions["mock-provider"]?["purpose"]?.stringValue == "assistants")
    #expect(fileClient.requests.first?.filename == "test.pdf")
    #expect(file.providerReference == ["mock-provider": "file-abc123"])
    #expect(file.providerMetadata["mock-provider"]?["size"]?.intValue == 1_024)
    #expect(file.warnings == [AIWarning(type: "unsupported", feature: "filename")])

    let skillClient = MockSkillsClient(result: SkillUploadResult(
        providerReference: ["mock-provider": "skill_123"],
        providerMetadata: ["mock-provider": ["defaultVersion": "1"]],
        warnings: [AIWarning(type: "unsupported", feature: "displayTitle")],
        rawValue: .object([:])
    ))
    let skill = try await AI.uploadSkill(client: skillClient, request: SkillUploadRequest(
        files: [SkillUploadFile(path: "test.ts", data: Data("hello".utf8))],
        displayTitle: "My Skill",
        providerOptions: ["mock-provider": ["custom": "value"]]
    ))

    #expect(skillClient.requests.first?.providerOptions["mock-provider"]?["custom"]?.stringValue == "value")
    #expect(skillClient.requests.first?.displayTitle == "My Skill")
    #expect(skill.providerReference == ["mock-provider": "skill_123"])
    #expect(skill.providerMetadata["mock-provider"]?["defaultVersion"]?.stringValue == "1")
    #expect(skill.warnings == [AIWarning(type: "unsupported", feature: "displayTitle")])
    #expect(skill.requestMetadata.body?["providerOptions"]?["mock-provider"]?["custom"]?.stringValue == "value")
}

@Test func aiFacadeForwardsAllFilesV4OperationsAndTypedResults() async throws {
    let content = AsyncThrowingStream<Data, Error> { continuation in
        continuation.yield(Data("contents".utf8))
        continuation.finish()
    }
    let client = MockFileClient(
        result: FileUploadResult(providerReference: ["mock": "file-1"], rawValue: .null),
        metadataResult: FileMetadataResult(
            providerReference: ["mock": "file-1"],
            filename: "test.txt",
            mediaType: "text/plain",
            byteSize: 8,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_700_003_600)
        ),
        downloadResult: FileDownloadResult(content: content, mediaType: "text/plain"),
        deleteResult: FileDeleteResult(providerReference: ["mock": "file-1"], deleted: true)
    )
    let recorder = TelemetryRecorder()
    let telemetry = Telemetry.Options(integrations: [recorder])
    let headers = ["X-Test": "files-v4"]
    let options: [String: JSONValue] = ["mock": ["region": "test"]]
    let reference = ["mock": "file-1"]

    let metadata = try await AI.getFileMetadata(
        client: client,
        request: FileMetadataRequest(
            file: reference,
            providerOptions: options,
            headers: headers
        ),
        telemetry: telemetry
    )
    let download = try await AI.downloadFile(
        client: client,
        request: FileDownloadRequest(file: reference, providerOptions: options, headers: headers),
        telemetry: telemetry
    )
    let deletion = try await AI.deleteFile(
        client: client,
        request: FileDeleteRequest(file: reference, providerOptions: options, headers: headers),
        telemetry: telemetry
    )

    #expect(metadata.byteSize == 8)
    #expect(metadata.createdAt == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(metadata.requestMetadata.body?["file"]?["mock"]?.stringValue == "file-1")
    #expect(metadata.requestMetadata.headers == headers)
    var downloaded = Data()
    for try await chunk in download.content { downloaded.append(chunk) }
    #expect(String(decoding: downloaded, as: UTF8.self) == "contents")
    #expect(download.requestMetadata.body?["providerOptions"]?["mock"]?["region"]?.stringValue == "test")
    #expect(deletion.deleted)
    #expect(client.metadataRequests.first?.headers == headers)
    #expect(client.downloadRequests.first?.providerOptions == options)
    #expect(client.deleteRequests.first?.file == reference)

    let operationIDs = await recorder.events().map(\.operationID)
    #expect(operationIDs == [
        "ai.getFileMetadata", "ai.getFileMetadata",
        "ai.downloadFile", "ai.downloadFile",
        "ai.deleteFile", "ai.deleteFile"
    ])
}

@Test func aiFacadeTreatsUploadStreamsAsSingleUseAndDoesNotRetry() async throws {
    let client = AlwaysFailingFileClient()
    let recorder = TelemetryRecorder()
    let cancellationProbe = FacadeUploadStreamProbe()
    let stream = AsyncThrowingStream<Data, Error> { continuation in
        continuation.onTermination = { _ in cancellationProbe.record() }
    }

    await #expect(throws: AIError.self) {
        _ = try await AI.uploadFile(
            client: client,
            request: FileUploadRequest(stream: stream, mediaType: "text/plain"),
            retryPolicy: AIRetryPolicy(maxRetries: 3),
            telemetry: Telemetry.Options(integrations: [recorder])
        )
    }

    #expect(client.attemptCount == 1)
    #expect(await waitForFacadeUploadStreamCancellation(cancellationProbe))
    let start = try #require((await recorder.events()).first)
    #expect(start.input?["dataType"]?.stringValue == "stream")
    #expect(start.input?["byteLength"] == nil)
}

private final class AlwaysFailingFileClient: AIFileClient, @unchecked Sendable {
    let providerID = "failing.files"
    private let lock = NSLock()
    private var attempts = 0
    var attemptCount: Int { lock.withLock { attempts } }

    func uploadFile(_ request: FileUploadRequest) async throws -> FileUploadResult {
        lock.withLock { attempts += 1 }
        throw AIError.apiCall(provider: providerID, statusCode: 500, body: "retryable")
    }
}

private final class FacadeUploadStreamProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var wasCancelled: Bool { lock.withLock { cancelled } }
    func record() { lock.withLock { cancelled = true } }
}

private func waitForFacadeUploadStreamCancellation(
    _ probe: FacadeUploadStreamProbe
) async -> Bool {
    for _ in 0..<100 {
        if probe.wasCancelled { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return probe.wasCancelled
}
