import Foundation
import Testing
@testable import SwiftAISDK

@Test func blackForestLabsImageSubmitsAndPolls() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-1","polling_url":"https://api.bfl.ai/v1/get_result","cost":0.01,"input_mp":0.5,"output_mp":0.75}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://bfl.example.com/image.png","seed":42}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("png".utf8))
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))
    let model = try provider.imageModel("flux-pro-1.1")

    let result = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        size: "1024x768",
        extraBody: [
            "promptUpsampling": true,
            "outputFormat": "png",
            "imagePromptStrength": 0.4,
            "safetyTolerance": 2,
            "webhookUrl": "https://hooks.example.com/bfl",
            "inputImage": "image-b64",
            "pollIntervalMillis": 1,
            "pollTimeoutMillis": 1000
        ]
    ))

    #expect(result.urls == ["https://bfl.example.com/image.png"])
    #expect(result.base64Images == [Data("png".utf8).base64EncodedString()])
    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].url.absoluteString == "https://api.bfl.ai/v1/flux-pro-1.1")
    #expect(requests[0].headers["x-key"] == "bfl-key")
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["prompt"]?.stringValue == "cat")
    #expect(body["aspect_ratio"]?.stringValue == "4:3")
    #expect(body["width"]?.intValue == 1024)
    #expect(body["height"]?.intValue == 768)
    #expect(body["prompt_upsampling"]?.boolValue == true)
    #expect(body["output_format"]?.stringValue == "png")
    #expect(body["image_prompt_strength"]?.doubleValue == 0.4)
    #expect(body["safety_tolerance"]?.intValue == 2)
    #expect(body["webhook_url"]?.stringValue == "https://hooks.example.com/bfl")
    #expect(body["input_image"]?.stringValue == "image-b64")
    #expect(body["pollIntervalMillis"] == nil)
    #expect(body["pollTimeoutMillis"] == nil)
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://api.bfl.ai/v1/get_result?id=bfl-1")
    #expect(requests[2].method == "GET")
    #expect(requests[2].url.absoluteString == "https://bfl.example.com/image.png")
}

@Test func blackForestLabsImageMapsFilesMaskAndNestedOptions() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-fill-1","polling_url":"https://api.bfl.ai/v1/get_result"}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://bfl.example.com/fill.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("fill-png".utf8))
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))
    let model = try provider.imageModel("flux-pro-1.0-fill")

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "replace background",
        size: "1280x720",
        files: [
            ImageInputFile(url: "https://example.com/input.png"),
            ImageInputFile(data: Data([1, 2, 3]), mediaType: "image/png")
        ],
        mask: ImageInputFile(data: Data([9, 8, 7]), mediaType: "image/png"),
        extraBody: [
            "blackForestLabs": .object([
                "width": 640,
                "height": 360,
                "seed": 123,
                "guidance": 2.5,
                "promptUpsampling": true,
                "outputFormat": "jpeg",
                "pollIntervalMillis": 1,
                "pollTimeoutMillis": 1000
            ])
        ]
    ))

    let requests = await transport.requests()
    let body = try decodeJSONBody(try #require(requests[0].body))
    #expect(body["prompt"]?.stringValue == "replace background")
    #expect(body["aspect_ratio"]?.stringValue == "16:9")
    #expect(body["width"]?.intValue == 640)
    #expect(body["height"]?.intValue == 360)
    #expect(body["seed"]?.intValue == 123)
    #expect(body["guidance"]?.doubleValue == 2.5)
    #expect(body["prompt_upsampling"]?.boolValue == true)
    #expect(body["output_format"]?.stringValue == "jpeg")
    #expect(body["image"]?.stringValue == "https://example.com/input.png")
    #expect(body["image_2"]?.stringValue == Data([1, 2, 3]).base64EncodedString())
    #expect(body["mask"]?.stringValue == Data([9, 8, 7]).base64EncodedString())
    #expect(body["blackForestLabs"] == nil)
    #expect(body["pollIntervalMillis"] == nil)
    #expect(body["pollTimeoutMillis"] == nil)

    await #expect(throws: AIError.self) {
        _ = try await model.generateImage(ImageGenerationRequest(
            prompt: "too many",
            files: (0..<11).map { ImageInputFile(url: "https://example.com/\($0).png") }
        ))
    }
}
