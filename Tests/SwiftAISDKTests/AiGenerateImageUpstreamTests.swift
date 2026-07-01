import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiGenerateImageForwardsRequestAndReturnsMetadataLikeUpstream() async throws {
    let inputImage = ImageInputFile(
        data: Data([0x89, 0x50, 0x4e, 0x47]),
        mediaType: "image/png",
        fileName: "input.png"
    )
    let mask = ImageInputFile(
        data: Data([0xff, 0xff, 0xff, 0x00]),
        mediaType: "image/png",
        fileName: "mask.png"
    )
    let warning = AIWarning(type: "other", message: "Setting is not supported")
    let responseMetadata = AIResponseMetadata(
        id: "image-response",
        modelID: "test-model",
        headers: ["x-test": "value"],
        body: ["foo": "bar"]
    )
    let controller = AIAbortController()
    let model = MockImageModel(result: ImageGenerationResult(
        urls: ["https://example.com/image.png"],
        base64Images: [Data([1, 2, 3]).base64EncodedString()],
        rawValue: ["raw": true],
        warnings: [warning],
        usage: TokenUsage(inputTokens: 10, outputTokens: 0, totalTokens: 10),
        providerMetadata: [
            "testProvider": [
                "images": [
                    ["revisedPrompt": "test-revised-prompt"],
                    .null
                ]
            ]
        ],
        responseMetadata: responseMetadata
    ))

    let result = try await AI.generateImage(
        model: model,
        prompt: "sunny day at the beach",
        size: "1024x1024",
        aspectRatio: "16:9",
        seed: 12345,
        count: 1,
        files: [inputImage],
        mask: mask,
        providerOptions: [
            "mock-provider": [
                "style": "vivid"
            ]
        ],
        extraBody: [
            "quality": "hd"
        ],
        headers: [
            "custom-request-header": "request-header-value"
        ],
        abortSignal: controller.signal
    )

    let request = try #require(model.requests.first)
    #expect(request.prompt == "sunny day at the beach")
    #expect(request.files == [inputImage])
    #expect(request.mask == mask)
    #expect(request.size == "1024x1024")
    #expect(request.aspectRatio == "16:9")
    #expect(request.seed == 12345)
    #expect(request.count == 1)
    #expect(request.providerOptions["mock-provider"]?["style"]?.stringValue == "vivid")
    #expect(request.extraBody["quality"]?.stringValue == "hd")
    #expect(request.headers["custom-request-header"] == "request-header-value")
    #expect(request.abortSignal === controller.signal)

    #expect(result.urls == ["https://example.com/image.png"])
    #expect(result.base64Images == [Data([1, 2, 3]).base64EncodedString()])
    #expect(result.warnings == [warning])
    #expect(result.usage == TokenUsage(inputTokens: 10, outputTokens: 0, totalTokens: 10))
    #expect(result.providerMetadata["testProvider"]?["images"]?[0]?["revisedPrompt"]?.stringValue == "test-revised-prompt")
    #expect(result.responseMetadata == responseMetadata)
    #expect(result.requestMetadata.body?["prompt"]?.stringValue == "sunny day at the beach")
    #expect(result.requestMetadata.body?["files"]?[0]?["mediaType"]?.stringValue == "image/png")
    #expect(result.requestMetadata.body?["files"]?[0]?["fileName"]?.stringValue == "input.png")
    #expect(result.requestMetadata.body?["files"]?[0]?["byteLength"]?.intValue == 4)
    #expect(result.requestMetadata.body?["mask"]?["fileName"]?.stringValue == "mask.png")
    #expect(result.requestMetadata.body?["providerOptions"]?["mock-provider"]?["style"]?.stringValue == "vivid")
    #expect(result.requestMetadata.body?["extraBody"]?["quality"]?.stringValue == "hd")
    #expect(result.requestMetadata.headers["custom-request-header"] == "request-header-value")
}
