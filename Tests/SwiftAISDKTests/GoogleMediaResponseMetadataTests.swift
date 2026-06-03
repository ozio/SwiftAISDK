import Foundation
import Testing
@testable import SwiftAISDK

@Test func googleImageModelsCarryResponseMetadata() async throws {
    let imagenTransport = RecordingTransport(response: jsonResponse(
        #"{"predictions":[{"bytesBase64Encoded":"image-1"}]}"#,
        headers: ["google-header": "imagen"]
    ))
    let imagenProvider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: imagenTransport))
    let imagenModel = try imagenProvider.imageModel("imagen-4.0-generate-001")

    let beforeImagen = Date()
    let imagen = try await imagenModel.generateImage(ImageGenerationRequest(prompt: "cat"))
    let afterImagen = Date()

    #expect(imagen.requestMetadata.body?["instances"]?[0]?["prompt"]?.stringValue == "cat")
    #expect(imagen.responseMetadata.modelID == "imagen-4.0-generate-001")
    #expect(imagen.responseMetadata.headers["google-header"] == "imagen")
    #expect(imagen.responseMetadata.body?["predictions"]?[0]?["bytesBase64Encoded"]?.stringValue == "image-1")
    #expect(try #require(imagen.responseMetadata.timestamp) >= beforeImagen)
    #expect(try #require(imagen.responseMetadata.timestamp) <= afterImagen)

    let geminiTransport = RecordingTransport(response: jsonResponse(
        #"{"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"gemini-image"}}]}}]}"#,
        headers: ["google-header": "gemini-image"]
    ))
    let geminiProvider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: geminiTransport))
    let geminiModel = try geminiProvider.imageModel("gemini-2.5-flash-image")

    let gemini = try await geminiModel.generateImage(ImageGenerationRequest(prompt: "cat"))

    #expect(gemini.requestMetadata.body?["contents"]?[0]?["parts"]?[0]?["text"]?.stringValue == "cat")
    #expect(gemini.responseMetadata.modelID == "gemini-2.5-flash-image")
    #expect(gemini.responseMetadata.headers["google-header"] == "gemini-image")
    #expect(gemini.responseMetadata.body?["candidates"]?[0]?["content"]?["parts"]?[0]?["inlineData"]?["data"]?.stringValue == "gemini-image")
}

@Test func googleVideoAndFilesCarryResponseMetadata() async throws {
    let videoTransport = RecordingTransport(responses: [
        jsonResponse(#"{"name":"operations/video-1","done":false}"#, headers: ["google-header": "create"]),
        jsonResponse(#"{"name":"operations/video-1","done":true,"response":{"generateVideoResponse":{"generatedSamples":[{"video":{"uri":"https://generativelanguage.googleapis.com/files/video-123.mp4?alt=media"}}]}}}"#, headers: ["google-header": "poll"])
    ])
    let videoProvider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: videoTransport))
    let videoModel = try videoProvider.videoModel("veo-3.1-generate-preview")

    let video = try await videoModel.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        extraBody: ["pollIntervalMs": 0]
    ))

    #expect(video.requestMetadata.body?["instances"]?[0]?["prompt"]?.stringValue == "cat running")
    #expect(video.responseMetadata.modelID == "veo-3.1-generate-preview")
    #expect(video.responseMetadata.headers["google-header"] == "poll")
    #expect(video.responseMetadata.body?["name"]?.stringValue == "operations/video-1")

    let fileTransport = RecordingTransport(responses: [
        AIHTTPResponse(statusCode: 200, headers: ["x-goog-upload-url": "https://upload.example.com/session"], body: Data()),
        jsonResponse(
            #"{"file":{"name":"files/abc","mimeType":"video/mp4","uri":"https://generativelanguage.googleapis.com/v1beta/files/abc","state":"ACTIVE"}}"#,
            headers: ["google-header": "upload"]
        )
    ])
    let fileProvider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: fileTransport))
    let file = try await fileProvider.files().uploadFile(FileUploadRequest(data: Data("video".utf8), mediaType: "video/mp4"))

    #expect(file.responseMetadata.headers["google-header"] == "upload")
    #expect(file.responseMetadata.body?["file"]?["name"]?.stringValue == "files/abc")
    #expect(file.requestMetadata.body?["file"]?["mediaType"]?.stringValue == "video/mp4")
    #expect(file.requestMetadata.body?["file"]?["byteLength"]?.intValue == 5)
    #expect(file.requestMetadata.body?["file"]?["data"] == nil)
}

@Test func googleVertexMediaModelsCarryResponseMetadata() async throws {
    let imageTransport = RecordingTransport(response: jsonResponse(
        #"{"predictions":[{"bytesBase64Encoded":"vertex-image"}]}"#,
        headers: ["vertex-header": "image"]
    ))
    let imageProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(apiKey: "vertex-key", baseURL: "https://api.example.com", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("imagen-3.0-generate-002")

    let image = try await imageModel.generateImage(ImageGenerationRequest(prompt: "cat"))

    #expect(image.requestMetadata.body?["instances"]?[0]?["prompt"]?.stringValue == "cat")
    #expect(image.responseMetadata.modelID == "imagen-3.0-generate-002")
    #expect(image.responseMetadata.headers["vertex-header"] == "image")
    #expect(image.responseMetadata.body?["predictions"]?[0]?["bytesBase64Encoded"]?.stringValue == "vertex-image")

    let geminiTransport = RecordingTransport(response: jsonResponse(
        #"{"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"vertex-gemini-image"}}]},"finishReason":"STOP"}]}"#,
        headers: ["vertex-header": "gemini-image"]
    ))
    let geminiProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(apiKey: "vertex-key", baseURL: "https://api.example.com", transport: geminiTransport))
    let geminiModel = try geminiProvider.imageModel("gemini-2.5-flash-image")

    let geminiImage = try await geminiModel.generateImage(ImageGenerationRequest(prompt: "cat"))

    #expect(geminiImage.requestMetadata.body?["prompt"]?.stringValue == "cat")
    #expect(geminiImage.responseMetadata.modelID == "gemini-2.5-flash-image")
    #expect(geminiImage.responseMetadata.headers["vertex-header"] == "gemini-image")

    let videoTransport = RecordingTransport(response: jsonResponse(
        #"{"name":"operations/vertex-video","done":true,"response":{"videos":[{"gcsUri":"gs://bucket/video.mp4"}]}}"#,
        headers: ["vertex-header": "video"]
    ))
    let videoProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(apiKey: "vertex-key", baseURL: "https://api.example.com", transport: videoTransport))
    let videoModel = try videoProvider.videoModel("veo-2.0-generate-001")

    let video = try await videoModel.generateVideo(VideoGenerationRequest(prompt: "cat running"))

    #expect(video.requestMetadata.body?["instances"]?[0]?["prompt"]?.stringValue == "cat running")
    #expect(video.responseMetadata.modelID == "veo-2.0-generate-001")
    #expect(video.responseMetadata.headers["vertex-header"] == "video")
    #expect(video.responseMetadata.body?["name"]?.stringValue == "operations/vertex-video")
}
