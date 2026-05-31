import Foundation
import Testing
@testable import ai_sdk_port

@Test func aiGenerateTextPromptBuildsLanguageRequest() async throws {
    let model = MockLanguageModel(result: TextGenerationResult(text: "done", rawValue: .object([:])))

    let result = try await AI.generateText(
        model: model,
        prompt: "Hello",
        temperature: 0.2,
        topK: 20,
        seed: 7,
        responseFormat: .json(name: "Answer"),
        reasoning: "low",
        providerOptions: ["openai": .object(["parallelToolCalls": .bool(false)])],
        extraBody: ["user": .string("user-1")]
    )

    #expect(result.text == "done")
    #expect(model.requests.count == 1)
    let request = try #require(model.requests.first)
    #expect(request.messages == [.user("Hello")])
    #expect(request.temperature == 0.2)
    #expect(request.topK == 20)
    #expect(request.seed == 7)
    #expect(request.responseFormat == .json(name: "Answer"))
    #expect(request.reasoning == "low")
    #expect(request.providerOptions["openai"]?["parallelToolCalls"]?.boolValue == false)
    #expect(request.extraBody["user"]?.stringValue == "user-1")
}

@Test func aiStreamTextForwardsRequestToModel() async throws {
    let parts: [LanguageStreamPart] = [
        .streamStart(warnings: []),
        .textDelta("hi"),
        .finish(reason: "stop", usage: TokenUsage(totalTokens: 1))
    ]
    let model = MockLanguageModel(result: TextGenerationResult(text: "", rawValue: .object([:])), streamParts: parts)

    var streamed: [LanguageStreamPart] = []
    for try await part in AI.streamText(model: model, prompt: "Stream", includeRawChunks: true) {
        streamed.append(part)
    }

    #expect(streamed == parts)
    #expect(model.streamRequests.count == 1)
    #expect(model.streamRequests.first?.messages == [.user("Stream")])
    #expect(model.streamRequests.first?.includeRawChunks == true)
}

@Test func aiEmbedManyChunksAndAggregatesResults() async throws {
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
        providerOptions: ["test": .object(["flag": .bool(true)])]
    )

    #expect(model.requests.map(\.values) == [["a", "b"], ["c"]])
    #expect(model.requests.allSatisfy { $0.dimensions == 64 })
    #expect(model.requests.allSatisfy { $0.providerOptions["test"]?["flag"]?.boolValue == true })
    #expect(result.embeddings == [[0.1], [0.2], [0.3]])
    #expect(result.usage == TokenUsage(inputTokens: 3, totalTokens: 3))
    #expect(result.rawValue[0]?["chunk"]?.intValue == 1)
    #expect(result.rawValue[1]?["chunk"]?.intValue == 2)
    #expect(result.warnings == [AIWarning(type: "unsupported", feature: "seed")])
    #expect(result.providerMetadata["provider"]?["second"]?.boolValue == true)
    #expect(result.responseMetadata.id == "resp-1")
}

@Test func aiFacadeForwardsMediaRerankAndUploadRequests() async throws {
    let imageModel = MockImageModel(result: ImageGenerationResult(urls: ["https://example.com/image.png"], rawValue: .object([:])))
    let image = try await AI.generateImage(model: imageModel, prompt: "cat", size: "1024x1024", providerOptions: ["image": .object(["quality": .string("high")])])
    #expect(image.urls == ["https://example.com/image.png"])
    #expect(imageModel.requests.first?.prompt == "cat")
    #expect(imageModel.requests.first?.providerOptions["image"]?["quality"]?.stringValue == "high")

    let transcriptionModel = MockTranscriptionModel(result: TranscriptionResult(text: "hello", rawValue: .object([:])))
    let transcription = try await AI.transcribe(model: transcriptionModel, request: AudioTranscriptionRequest(audio: Data("wav".utf8), language: "en"))
    #expect(transcription.text == "hello")
    #expect(transcriptionModel.requests.first?.language == "en")

    let speechModel = MockSpeechModel(result: SpeechResult(audio: Data("audio".utf8)))
    let speech = try await AI.generateSpeech(model: speechModel, request: SpeechRequest(text: "hello", voice: "alloy"))
    #expect(String(data: speech.audio, encoding: .utf8) == "audio")
    #expect(speechModel.requests.first?.voice == "alloy")

    let videoModel = MockVideoModel(result: VideoGenerationResult(urls: ["https://example.com/video.mp4"], rawValue: .object([:])))
    let video = try await AI.generateVideo(model: videoModel, request: VideoGenerationRequest(prompt: "clip"))
    #expect(video.urls == ["https://example.com/video.mp4"])
    #expect(videoModel.requests.first?.prompt == "clip")

    let rerankingModel = MockRerankingModel(result: RerankingResult(results: [RerankedDocument(index: 1, score: 0.9)], rawValue: .object([:])))
    let ranking = try await AI.rerank(model: rerankingModel, request: RerankingRequest(query: "q", documents: ["a", "b"], topK: 1))
    #expect(ranking.results.first?.index == 1)
    #expect(rerankingModel.requests.first?.topK == 1)

    let fileClient = MockFileClient(result: FileUploadResult(providerReference: ["file": "file-1"], rawValue: .object([:])))
    let file = try await AI.uploadFile(client: fileClient, request: FileUploadRequest(data: Data("file".utf8), mediaType: "text/plain", filename: "a.txt"))
    #expect(file.providerReference["file"] == "file-1")
    #expect(fileClient.requests.first?.filename == "a.txt")

    let skillClient = MockSkillsClient(result: SkillUploadResult(providerReference: ["skill": "skill-1"], rawValue: .object([:])))
    let skill = try await AI.uploadSkill(client: skillClient, request: SkillUploadRequest(files: [SkillUploadFile(path: "skill.md", data: Data("skill".utf8))]))
    #expect(skill.providerReference["skill"] == "skill-1")
    #expect(skillClient.requests.first?.files.first?.path == "skill.md")
}

private final class MockLanguageModel: LanguageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-language"
    var requests: [LanguageModelRequest] = []
    var streamRequests: [LanguageModelRequest] = []
    private let result: TextGenerationResult
    private let streamParts: [LanguageStreamPart]

    init(result: TextGenerationResult, streamParts: [LanguageStreamPart] = []) {
        self.result = result
        self.streamParts = streamParts
    }

    func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        requests.append(request)
        return result
    }

    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        streamRequests.append(request)
        let parts = streamParts
        return AsyncThrowingStream { continuation in
            for part in parts {
                continuation.yield(part)
            }
            continuation.finish()
        }
    }
}

private final class MockEmbeddingModel: EmbeddingModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-embedding"
    var requests: [EmbeddingRequest] = []
    private var results: [EmbeddingResult]

    init(results: [EmbeddingResult]) {
        self.results = results
    }

    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResult {
        requests.append(request)
        return results.count > 1 ? results.removeFirst() : results[0]
    }
}

private final class MockImageModel: ImageModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-image"
    var requests: [ImageGenerationRequest] = []
    let result: ImageGenerationResult

    init(result: ImageGenerationResult) { self.result = result }

    func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        requests.append(request)
        return result
    }
}

private final class MockTranscriptionModel: TranscriptionModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-transcription"
    var requests: [AudioTranscriptionRequest] = []
    let result: TranscriptionResult

    init(result: TranscriptionResult) { self.result = result }

    func transcribe(_ request: AudioTranscriptionRequest) async throws -> TranscriptionResult {
        requests.append(request)
        return result
    }
}

private final class MockSpeechModel: SpeechModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-speech"
    var requests: [SpeechRequest] = []
    let result: SpeechResult

    init(result: SpeechResult) { self.result = result }

    func speak(_ request: SpeechRequest) async throws -> SpeechResult {
        requests.append(request)
        return result
    }
}

private final class MockVideoModel: VideoModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-video"
    var requests: [VideoGenerationRequest] = []
    let result: VideoGenerationResult

    init(result: VideoGenerationResult) { self.result = result }

    func generateVideo(_ request: VideoGenerationRequest) async throws -> VideoGenerationResult {
        requests.append(request)
        return result
    }
}

private final class MockRerankingModel: RerankingModel, @unchecked Sendable {
    let providerID = "mock"
    let modelID = "mock-reranking"
    var requests: [RerankingRequest] = []
    let result: RerankingResult

    init(result: RerankingResult) { self.result = result }

    func rerank(_ request: RerankingRequest) async throws -> RerankingResult {
        requests.append(request)
        return result
    }
}

private final class MockFileClient: AIFileClient, @unchecked Sendable {
    let providerID = "mock.files"
    var requests: [FileUploadRequest] = []
    let result: FileUploadResult

    init(result: FileUploadResult) { self.result = result }

    func uploadFile(_ request: FileUploadRequest) async throws -> FileUploadResult {
        requests.append(request)
        return result
    }
}

private final class MockSkillsClient: AISkillsClient, @unchecked Sendable {
    let providerID = "mock.skills"
    var requests: [SkillUploadRequest] = []
    let result: SkillUploadResult

    init(result: SkillUploadResult) { self.result = result }

    func uploadSkill(_ request: SkillUploadRequest) async throws -> SkillUploadResult {
        requests.append(request)
        return result
    }
}
