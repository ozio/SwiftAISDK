import Foundation
import Testing
@testable import SwiftAISDK

private let weeklyAzureMAIResponse = #"{"created":1791229019,"size":"768x768","usage":{"num_input_text_tokens":10,"num_input_image_tokens":0,"num_output_tokens":576},"data":[{"b64_json":"aGk="}]}"#

@Test(arguments: ["MAI-Image-2.6", "mai-image-2.6-flash", "MAI-Image-2.5-Pro", "mai-image-2.5", "mai-image-2.5-flash", "gpt-image-1", "mai-image-custom"])
func WeeklyAzure20261011RoutesKnownMAIFamilies(_ modelID: String) async throws {
    let transport = RecordingTransport(response: jsonResponse(weeklyAzureMAIResponse))
    let model = try AIProviders.azure(resourceName: "weekly", settings: .init(apiKey: "key", transport: transport)).image(modelID)
    _ = try await model.generateImage(.init(prompt: "apple"))
    let request = try #require(await transport.requests().first)
    let mai = ["mai-image-2.6", "mai-image-2.6-flash", "mai-image-2.5-pro", "mai-image-2.5", "mai-image-2.5-flash"].contains(modelID.lowercased())
    #expect(request.url.host == (mai ? "weekly.services.ai.azure.com" : "weekly.openai.azure.com"))
    #expect(request.url.path == (mai ? "/mai/v1/images/generations" : "/openai/v1/images/generations"))
    #expect(await model.supportsFileInputs == (mai ? true : nil))
    #expect(await model.supportsMaskInputs == (mai ? false : nil))
}

@Test func WeeklyAzure20261011OverridesAPIRouteAndWarnsForMAIOnlyOptions() async throws {
    let transport = RecordingTransport(response: jsonResponse(weeklyAzureMAIResponse))
    let provider = try AIProviders.azure(resourceName: "weekly", settings: .init(apiKey: "key", transport: transport), audioSettings: .init(maiBaseURL: "https://mai.proxy/mai/v1/"))
    let result = try await provider.image("custom").generateImage(.init(prompt: "apple", size: "1536x1024", providerOptions: ["azure": ["api": "mai", "autoAspectRatio": true, "webGrounding": false, "future": true]]))
    let sent = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(sent.body))
    #expect(sent.url.absoluteString == "https://mai.proxy/mai/v1/images/generations")
    #expect(body == ["model": "custom", "prompt": "apple", "width": 1536, "height": 1024, "auto_aspect_ratio": true, "web_grounding": false])
    #expect(result.usage?.inputTokens == 10)
    #expect(result.usage?.totalTokens == 586)
    #expect(result.providerMetadata["azure"]?["images"]?[0]?["textTokens"] == 10)
    let openAI = try await provider.image("MAI-Image-2.6").generateImage(.init(prompt: "apple", providerOptions: ["azure": ["api": "openai", "webGrounding": true]]))
    #expect(openAI.warnings.contains { $0.feature == "providerOptions.azure.webGrounding" })
    #expect(await transport.requests().last?.url.host == "weekly.openai.azure.com")
}

@Test(arguments: ["1:1", "16:9", "9:16", "4:3", "invalid"])
func WeeklyAzure20261011AspectRatioDimensionsHonorPixelBudget(_ ratio: String) async throws {
    let transport = RecordingTransport(response: jsonResponse(weeklyAzureMAIResponse))
    let model = try AIProviders.azure(resourceName: "weekly", settings: .init(apiKey: "key", transport: transport)).image("MAI-Image-2.6")
    let result = try await model.generateImage(.init(prompt: "apple", aspectRatio: ratio))
    let sent = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(sent.body))
    let expected: [String: [Int]] = ["1:1": [1024, 1024], "16:9": [1360, 768], "9:16": [768, 1360], "4:3": [1168, 880]]
    if let sides = expected[ratio] { #expect(body["width"]?.intValue == sides[0]); #expect(body["height"]?.intValue == sides[1]) }
    else { #expect(body["width"] == nil); #expect(result.warnings.contains { $0.feature == "aspectRatio" }) }
}

@Test func WeeklyAzure20261011RepeatedEditsAggregateUsageAndIgnoreMaskAndSeed() async throws {
    let transport = RecordingTransport(response: jsonResponse(weeklyAzureMAIResponse))
    let model = try AIProviders.azure(resourceName: "weekly", settings: .init(apiKey: "key", transport: transport)).image("MAI-Image-2.6")
    let result = try await model.generateImage(.init(prompt: "apple", size: "1024x1024", aspectRatio: "16:9", seed: 1, count: 2,
                                                   files: [.init(data: Data([1]), mediaType: "image/png"), .init(data: Data([2]), mediaType: "image/jpeg")],
                                                   mask: .init(data: Data([3]), mediaType: "image/png"), providerOptions: ["azure": ["webGrounding": true]]))
    #expect(result.base64Images == ["aGk=", "aGk="])
    #expect(result.usage?.inputTokens == 20)
    #expect(result.usage?.outputTokens == 1152)
    #expect(result.usage?.totalTokens == 1172)
    #expect(result.providerMetadata["azure"]?["images"]?.arrayValue?.count == 2)
    #expect(Set(result.warnings.compactMap(\.feature)) == ["seed", "mask", "aspectRatio"])
    let requests = await transport.requests()
    #expect(requests.count == 2)
    for request in requests {
        #expect(request.url.path == "/mai/v1/images/edits")
        let multipart = String(decoding: try #require(request.body), as: UTF8.self)
        #expect(multipart.contains("name=\"image\"; filename=\"image-1.png\""))
        #expect(multipart.contains("name=\"image\"; filename=\"image-2.jpg\""))
        #expect(!multipart.contains("name=\"mask\""))
    }
}

@Test func WeeklyAzure20261011EntraReferenceDownloadOmitsCredentials() async throws {
    let transport = RecordingTransport(responses: [AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/jpeg"], body: Data([1])), jsonResponse(weeklyAzureMAIResponse)])
    let provider = try AIProviders.azure(resourceName: "weekly", tokenProvider: { "entra" }, settings: .init(transport: transport))
    _ = try await provider.image("MAI-Image-2.6").generateImage(.init(prompt: "edit", files: [.init(url: "https://images.example/apple.jpg")]))
    let requests = await transport.requests()
    #expect(requests[0].headers.isEmpty)
    #expect(requests[1].headers.first { $0.key.lowercased() == "authorization" }?.value == "Bearer entra")
    #expect(requests[1].headers["api-key"] == nil)
    #expect(String(decoding: try #require(requests[1].body), as: UTF8.self).contains("image-1.jpg"))
}

@Test(arguments: [400, 502, 503])
func WeeklyAzure20261011SpeechResetBecomesNonRetryableClientError(_ status: Int) async throws {
    let body = status == 502 ? "upstream reset reason: protocol error" : "voice unavailable"
    let model = try AIProviders.azure(resourceName: "weekly", settings: .init(apiKey: "key", transport: RecordingTransport(response: AIHTTPResponse(statusCode: status, body: Data(body.utf8))))).speech("mai-voice-2")
    do { _ = try await model.speak(.init(text: "test")); Issue.record("Expected speech failure") }
    catch let AIError.apiCall(error) { #expect(error.statusCode == (status == 502 ? 400 : status)); #expect(error.responseBody == body); #expect(error.isRetryable == (status == 503)) }
}

@Test(arguments: [#"{"data":[{}]}"#, #"{"usage":{"num_output_tokens":"bad"},"data":[{"b64_json":"aGk="}]}"#])
func WeeklyAzure20261011RejectsMalformedMAIResponse(_ response: String) async throws {
    let model = try AIProviders.azure(resourceName: "weekly", settings: .init(apiKey: "key", transport: RecordingTransport(response: jsonResponse(response)))).image("MAI-Image-2.6")
    await #expect(throws: AIError.self) { try await model.generateImage(.init(prompt: "apple")) }
}
