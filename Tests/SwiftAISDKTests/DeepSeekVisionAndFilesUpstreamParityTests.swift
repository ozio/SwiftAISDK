import Foundation
import Testing
@testable import SwiftAISDK

@Test func deepSeekV4SerializesInlineURLAndReferencedImagesLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"done"},"finish_reason":"stop"}],"usage":{"total_tokens":3}}"#))
    let provider = try AIProviders.deepSeek(settings: ProviderSettings(apiKey: "deepseek-key", transport: transport))
    let model = try provider.languageModel("deepseek-v4-flash-vision-exp")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .text("Compare these images"),
            .data(mimeType: "image/png", data: Data([0, 1, 2, 3])),
            .imageURL("https://example.com/cat.png"),
            .providerReference(
                mimeType: "image/png",
                reference: ["deepseek": "file-api-deepseek", "openai": "file-openai"]
            )
        ])
    ]))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content[0]["type"]?.stringValue == "text")
    #expect(content[0]["text"]?.stringValue == "Compare these images")
    #expect(content[1]["type"]?.stringValue == "image_url")
    #expect(content[1]["image_url"]?["url"]?.stringValue == "data:image/png;base64,AAECAw==")
    #expect(content[2]["image_url"]?["url"]?.stringValue == "https://example.com/cat.png")
    #expect(content[3]["type"]?.stringValue == "file")
    #expect(content[3]["file_id"]?.stringValue == "file-api-deepseek")
}

@Test func deepSeekV4RejectsImageReferenceWithoutDeepSeekIdentifier() async throws {
    let transport = RecordingTransport(response: jsonResponse("{}"))
    let provider = try AIProviders.deepSeek(settings: ProviderSettings(apiKey: "deepseek-key", transport: transport))
    let model = try provider.languageModel("deepseek-v4-flash-vision-exp")

    await #expect(throws: AINoSuchProviderReferenceError.self) {
        _ = try await model.generate(LanguageModelRequest(messages: [
            AIMessage(role: .user, content: [
                .providerReference(mimeType: "image/png", reference: ["openai": "file-openai"])
            ])
        ]))
    }
    #expect(await transport.requests().isEmpty)
}

@Test func deepSeekFilesUploadsUserDataWithExpiryAndReturnsMetadata() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {
      "id":"file-api-xyz789",
      "object":"file",
      "bytes":1024,
      "created_at":1700000000,
      "filename":"comic-cat.png",
      "purpose":"user_data",
      "expires_at":1700003600
    }
    """))
    let provider = try AIProviders.deepSeek(settings: ProviderSettings(
        apiKey: "deepseek-key",
        headers: ["Custom-Header": "custom-value"],
        transport: transport
    ))

    let result = try await provider.files().uploadFile(FileUploadRequest(
        data: Data([1, 2, 3]),
        mediaType: "image/png",
        filename: "comic-cat.png",
        providerOptions: ["deepseek": ["expiresAfter": 3_600]]
    ))

    #expect(result.providerReference == ["deepseek": "file-api-xyz789"])
    #expect(result.filename == "comic-cat.png")
    #expect(result.mediaType == "image/png")
    #expect(result.warnings == [])
    #expect(result.providerMetadata["deepseek"]?["purpose"]?.stringValue == "user_data")
    #expect(result.providerMetadata["deepseek"]?["bytes"]?.intValue == 1024)
    #expect(result.providerMetadata["deepseek"]?["createdAt"]?.intValue == 1_700_000_000)
    #expect(result.providerMetadata["deepseek"]?["expiresAt"]?.intValue == 1_700_003_600)

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.deepseek.com/files")
    #expect(request.headers["authorization"] == "Bearer deepseek-key")
    #expect(request.headers["custom-header"] == "custom-value")
    let requestBody = try #require(request.body)
    let multipart = try #require(String(data: requestBody, encoding: .utf8))
    #expect(multipart.contains("name=\"purpose\"\r\n\r\nuser_data"))
    #expect(multipart.contains("name=\"expires_after[anchor]\"\r\n\r\ncreated_at"))
    #expect(multipart.contains("name=\"expires_after[seconds]\"\r\n\r\n3600"))
}

@Test func deepSeekFilesValidatesExpiryRangeAndIntegerShape() async throws {
    let provider = try AIProviders.deepSeek(settings: ProviderSettings(
        apiKey: "deepseek-key",
        transport: RecordingTransport(response: jsonResponse("{}"))
    ))
    let files = provider.files()
    let expected = AIError.invalidArgument(
        argument: "providerOptions.deepseek.expiresAfter",
        message: "DeepSeek expiresAfter must be an integer between 3600 and 2592000."
    )

    await #expect(throws: expected) {
        _ = try await files.uploadFile(FileUploadRequest(
            data: Data([1]),
            mediaType: "image/png",
            providerOptions: ["deepseek": ["expiresAfter": 3_599]]
        ))
    }
    await #expect(throws: expected) {
        _ = try await files.uploadFile(FileUploadRequest(
            data: Data([1]),
            mediaType: "image/png",
            providerOptions: ["deepseek": ["expiresAfter": 3_600.5]]
        ))
    }
}

@Test func deepSeekFilesUsesBlobFilenameWhenCallerOmitsFilenameLikeFormData() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"file-api-blob"}"#))
    let provider = try AIProviders.deepSeek(settings: ProviderSettings(
        apiKey: "deepseek-key",
        transport: transport
    ))

    let result = try await provider.files().uploadFile(FileUploadRequest(
        data: Data([1, 2, 3]),
        mediaType: "image/png"
    ))

    #expect(result.filename == nil)
    #expect(result.requestMetadata.body?["file"]?["filename"]?.stringValue == "blob")
    let request = try #require(await transport.requests().first)
    let requestBody = try #require(request.body)
    let multipart = try #require(String(data: requestBody, encoding: .utf8))
    #expect(multipart.contains("name=\"file\"; filename=\"blob\""))
}

@Test func deepSeekFilesExtractsNestedAPIErrorMessageLikeUpstream() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 400,
        headers: ["content-type": "application/json", "x-request-id": "req-files-1"],
        body: Data(#"{"error":{"message":"File type is not supported","type":"invalid_request_error","code":"invalid_file"}}"#.utf8)
    ))
    let provider = try AIProviders.deepSeek(settings: ProviderSettings(
        apiKey: "deepseek-key",
        transport: transport
    ))

    do {
        _ = try await provider.files().uploadFile(FileUploadRequest(
            data: Data([1]),
            mediaType: "application/octet-stream"
        ))
        Issue.record("Expected DeepSeek Files API error.")
    } catch let error as AIError {
        let apiError = try #require(error.apiCallError)
        #expect(apiError.provider == "deepseek.files")
        #expect(apiError.statusCode == 400)
        #expect(apiError.responseBody == "File type is not supported")
        #expect(apiError.responseHeaders["x-request-id"] == "req-files-1")
        #expect(!apiError.isRetryable)
    }
}
