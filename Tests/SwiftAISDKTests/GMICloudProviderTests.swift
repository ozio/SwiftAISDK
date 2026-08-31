import Foundation
import Testing
@testable import SwiftAISDK

private let gmiCloudMaxTokensErrorBody = #"{"error":{"message":"Backend request failed with status 400","type":"backend_error","code":400,"details":"{\"error\":{\"type\":\"invalid_request_error\",\"code\":\"400001\",\"message\":\"The request is invalid: Invalid max_tokens value, the valid range of max_tokens is [1, 393216]. Please check the request body, required fields, and request format.\",\"source\":\"client\"}}"}}"#

@Test func gmiCloudGlobalFactoryAndVersionAliasMatchPublishedPackage() throws {
    let provider = try createGMICloud(settings: ProviderSettings(apiKey: "gmi-key", transport: RecordingTransport(responses: [])))

    #expect(gmiCloudProviderVersion == "3.0.12")
    #expect(provider.providerID == "gmicloud")
    #expect(try provider.chat("model").providerID == "gmicloud.chat")
}

@Test func gmiCloudProviderDefaultsMatchPublishedPackage() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"gmi-1","model":"deepseek-ai/DeepSeek-V4-Flash-0731","choices":[{"message":{"content":"Paris"},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":1,"total_tokens":3,"gmi_cached_tokens":1}}"#))
    let provider = try GMICloudProvider(settings: ProviderSettings(apiKey: "gmi-key", transport: transport))
    let model = try provider("deepseek-ai/DeepSeek-V4-Flash-0731")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("What is the capital of France?")],
        maxOutputTokens: 32
    ))

    #expect(provider.providerID == "gmicloud")
    #expect(provider.supportedCapabilities == [.language])
    #expect(model.providerID == "gmicloud.chat")
    #expect(model.modelID == "deepseek-ai/DeepSeek-V4-Flash-0731")
    #expect(result.text == "Paris")
    #expect(result.usage?.inputTokens == 2)
    #expect(result.usage?.outputTokens == 1)
    #expect(result.usage?.totalTokens == 3)
    #expect(result.usage?.rawValue?["gmi_cached_tokens"]?.intValue == 1)

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.gmi-serving.com/v1/chat/completions")
    #expect(request.headers["authorization"] == "Bearer gmi-key")
    #expect(request.headers["user-agent"] == "ai-sdk/gmicloud/3.0.12")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "deepseek-ai/DeepSeek-V4-Flash-0731")
    #expect(body["max_tokens"]?.intValue == 32)
}

@Test func gmiCloudProviderUsesEnvironmentKeyCustomURLHeadersAndAliases() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}"#))
    let provider = try GMICloudProvider(settings: ProviderSettings(
        baseURL: "https://example.com/gmi/",
        headers: [
            "authorization": "Bearer custom-key",
            "User-Agent": "ExampleApp/1.0",
            "x-client": "swift"
        ],
        environment: ["GMI_CLOUD_APIKEY": "environment-key"],
        transport: transport
    ))

    let callable = try provider("Qwen/Qwen3.8-Max")
    let language = try provider.languageModel("moonshotai/kimi-k3")
    let chatModel = try provider.chatModel("zai-org/GLM-5.2-FP8")
    let chat = try provider.chat("MiniMaxAI/MiniMax-M3")
    let futureModel = try provider.chat("organization/future-model")
    let aliases = [callable, language, chatModel, chat, futureModel]
    #expect(aliases.map { $0.providerID } == Array(repeating: "gmicloud.chat", count: 5))
    #expect(aliases.map { $0.modelID } == [
        "Qwen/Qwen3.8-Max",
        "moonshotai/kimi-k3",
        "zai-org/GLM-5.2-FP8",
        "MiniMaxAI/MiniMax-M3",
        "organization/future-model"
    ])

    _ = try await callable.generate(LanguageModelRequest(messages: [.user("Hi")]))
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://example.com/gmi/chat/completions")
    #expect(request.headers["authorization"] == "Bearer custom-key")
    #expect(request.headers["user-agent"] == "ExampleApp/1.0 ai-sdk/gmicloud/3.0.12")
    #expect(request.headers["x-client"] == "swift")
}

@Test func gmiCloudStreamingIncludesUsageByDefault() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    data: {"id":"gmi-stream","model":"deepseek-ai/DeepSeek-V4-Flash-0731","choices":[{"delta":{"content":"Hel"},"finish_reason":null}]}

    data: {"id":"gmi-stream","model":"deepseek-ai/DeepSeek-V4-Flash-0731","choices":[{"delta":{"content":"lo"},"finish_reason":"stop"}]}

    data: {"choices":[],"usage":{"prompt_tokens":4,"completion_tokens":2,"total_tokens":6}}

    data: [DONE]

    """))
    let provider = try GMICloudProvider(settings: ProviderSettings(apiKey: "gmi-key", transport: transport))
    let model = try provider.chat("deepseek-ai/DeepSeek-V4-Flash-0731")

    var text = ""
    var usage: TokenUsage?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        if case let .textDeltaPart(_, delta, _) = part {
            text += delta
        }
        if case let .finishMetadata(_, finishUsage, _) = part {
            usage = finishUsage
        }
    }

    #expect(text == "Hello")
    #expect(usage?.inputTokens == 4)
    #expect(usage?.outputTokens == 2)
    #expect(usage?.totalTokens == 6)
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"]?.boolValue == true)
    #expect(body["stream_options"]?["include_usage"]?.boolValue == true)
}

@Test func gmiCloudErrorsPreferNestedEngineDiagnostic() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 400,
        headers: ["content-type": "application/json", "x-gmi": "rejected"],
        body: Data(gmiCloudMaxTokensErrorBody.utf8)
    ))
    let provider = try GMICloudProvider(settings: ProviderSettings(apiKey: "gmi-key", transport: transport))

    await #expect(throws: AIError.apiCall(
        provider: "gmicloud.chat",
        statusCode: 400,
        body: "The request is invalid: Invalid max_tokens value, the valid range of max_tokens is [1, 393216]. Please check the request body, required fields, and request format.",
        headers: ["content-type": "application/json", "x-gmi": "rejected"]
    )) {
        _ = try await provider("deepseek-ai/DeepSeek-V4-Flash-0731").generate(
            LanguageModelRequest(messages: [.user("Hi")], maxOutputTokens: 999_999_999)
        )
    }
}

@Test func gmiCloudErrorParserMatchesPublishedFallbackBehavior() throws {
    let thinkingBody = #"{"error":{"message":"Backend request failed with status 400","details":"{\"error\":{\"message\":\"The request is invalid: Thinking mode does not support this tool_choice.\"}}"}}"#
    let imageBody = #"{"error":{"message":"Backend request failed with status 400","details":"{\"error\":{\"message\":\"unknown variant `image_url`, expected `text`\"}}"}}"#
    #expect(gmiCloudErrorMessage(from: Data(thinkingBody.utf8)) == "The request is invalid: Thinking mode does not support this tool_choice.")
    #expect(gmiCloudErrorMessage(from: Data(imageBody.utf8)) == "unknown variant `image_url`, expected `text`")
    #expect(gmiCloudErrorMessage(from: Data(#"{"error":{"message":"outer"}}"#.utf8)) == "outer")
    #expect(gmiCloudErrorMessage(from: Data(#"{"error":{"message":"outer","details":"<html>nginx</html>"}}"#.utf8)) == "outer")
    #expect(gmiCloudErrorMessage(from: Data(#"{"error":{"message":"outer","details":"{\"error\":{\"code\":\"500\"}}"}}"#.utf8)) == "outer")
    #expect(gmiCloudErrorMessage(from: Data("No matching target server found for model foo".utf8)) == nil)
}

@Test func gmiCloudProviderRejectsUnsupportedModelFamilies() throws {
    let provider = try GMICloudProvider(settings: ProviderSettings(apiKey: "gmi-key", transport: RecordingTransport(responses: [])))

    #expect(throws: AIError.unsupportedModel(provider: "gmicloud", capability: .embedding, modelID: "embed")) {
        _ = try provider.embeddingModel("embed")
    }
    #expect(throws: AIError.unsupportedModel(provider: "gmicloud", capability: .embedding, modelID: "legacy-embed")) {
        _ = try provider.textEmbeddingModel("legacy-embed")
    }
    #expect(throws: AIError.unsupportedModel(provider: "gmicloud", capability: .image, modelID: "image")) {
        _ = try provider.imageModel("image")
    }
}

@Test func gmiCloudProviderRequiresPublishedEnvironmentVariable() {
    #expect(throws: AIError.missingAPIKey(provider: "gmicloud", environmentVariables: ["GMI_CLOUD_APIKEY"])) {
        _ = try GMICloudProvider(settings: ProviderSettings(environment: [:]))
    }
}
