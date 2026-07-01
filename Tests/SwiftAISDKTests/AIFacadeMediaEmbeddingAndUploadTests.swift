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

    await #expect(throws: AINoOutputError(kind: .image, responses: [response])) {
        _ = try await AI.generateImage(
            model: MockImageModel(result: ImageGenerationResult(
                urls: [],
                base64Images: [],
                rawValue: .object([:]),
                responseMetadata: response
            )),
            prompt: "empty"
        )
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
