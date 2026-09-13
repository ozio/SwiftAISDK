import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIFilesUploadUsesMultipartFilesEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"file_123","filename":"notes.txt","purpose":"assistants","bytes":3,"created_at":1710000000,"status":"processed"}
    """, headers: ["openai-request-id": "file-request"]))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let result = try await provider.files().uploadFile(FileUploadRequest(
        data: Data("hey".utf8),
        mediaType: "text/plain",
        filename: "notes.txt",
        displayName: "Notes"
    ))

    #expect(result.providerReference["openai"] == "file_123")
    #expect(result.filename == "notes.txt")
    #expect(result.responseMetadata.id == "file_123")
    #expect(result.responseMetadata.headers["openai-request-id"] == "file-request")
    #expect(result.responseMetadata.body?["purpose"]?.stringValue == "assistants")
    #expect(result.requestMetadata.body?["file"]?["filename"]?.stringValue == "notes.txt")
    #expect(result.requestMetadata.body?["file"]?["mediaType"]?.stringValue == "text/plain")
    #expect(result.requestMetadata.body?["file"]?["byteLength"]?.intValue == 3)
    #expect(result.requestMetadata.body?["file"]?["data"] == nil)
    #expect(result.requestMetadata.body?["purpose"]?.stringValue == "assistants")
    #expect(result.requestMetadata.body?["displayName"]?.stringValue == "Notes")
    #expect(result.warnings == [AIWarning(type: "unsupported", feature: "displayName")])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/files")
    #expect(request.headers["authorization"] == "Bearer test-key")
    #expect(request.headers["user-agent"] == "ai-sdk/openai/4.0.66")
    #expect(request.headers["content-type"]?.hasPrefix("multipart/form-data; boundary=SwiftAISDK-") == true)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"file\"; filename=\"notes.txt\""))
    #expect(bodyText.contains("name=\"purpose\""))
    #expect(bodyText.contains("assistants"))
    #expect(!bodyText.contains("name=\"display_name\""))
    #expect(!bodyText.contains("Notes"))
}

@Test func openAIFilesUploadSerializesProviderExpiryAsNestedMultipartFields() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"file_expiring","filename":"notes.txt","purpose":"batch","bytes":3,"created_at":1710000000,"expires_at":1710003600,"status":"processed"}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport, name: "custom-openai"))

    let result = try await provider.files().uploadFile(FileUploadRequest(
        data: Data("hey".utf8),
        mediaType: "text/plain",
        filename: "notes.txt",
        purpose: "assistants",
        providerOptions: ["openai": ["purpose": "batch", "expiresAfter": 3_600]]
    ))

    #expect(result.requestMetadata.body?["purpose"]?.stringValue == "batch")
    #expect(result.requestMetadata.body?["expiresAfter"]?.intValue == 3_600)
    let request = try #require(await transport.requests().first)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"purpose\"\r\n\r\nbatch"))
    #expect(bodyText.contains("name=\"expires_after[anchor]\"\r\n\r\ncreated_at"))
    #expect(bodyText.contains("name=\"expires_after[seconds]\"\r\n\r\n3600"))
    #expect(!bodyText.contains("name=\"expires_after\"\r\n"))
}

@Test func openAIFilesUploadValidatesProviderOptions() async throws {
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: RecordingTransport(responses: [])))

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions", message: "invalid openai provider options")) {
        _ = try await provider.files().uploadFile(FileUploadRequest(
            data: Data("hey".utf8),
            mediaType: "text/plain",
            providerOptions: ["openai": ["expiresAfter": "soon"]]
        ))
    }
}

@Test func openAIFilesUploadSerializesLargeFiniteExpiryWithoutTrapping() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"file_large_expiry","filename":"notes.txt","purpose":"assistants","bytes":3,"created_at":1710000000,"status":"processed"}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))

    _ = try await provider.files().uploadFile(FileUploadRequest(
        data: Data("hey".utf8),
        mediaType: "text/plain",
        filename: "notes.txt",
        providerOptions: ["openai": ["expiresAfter": 1e20]]
    ))

    let request = try #require(await transport.requests().first)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"expires_after[seconds]\"\r\n\r\n100000000000000000000"))
}

@Test func xAIFilesUploadUsesFilesEndpointTeamIDAndMetadata() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"file_xai_123","object":"file","filename":"upload.csv","bytes":512,"created_at":1700000000}
    """, headers: ["xai-request-id": "file-request"]))
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let result = try await provider.files().uploadFile(FileUploadRequest(
        data: Data("a,b\n1,2".utf8),
        mediaType: "text/csv",
        purpose: "fine-tune",
        displayName: "Upload",
        extraBody: ["xai": .object(["teamId": .string("team-123")])]
    ))

    #expect(result.providerReference["xai"] == "file_xai_123")
    #expect(result.filename == "upload.csv")
    #expect(result.mediaType == "text/csv")
    #expect(result.metadata["xai"]?["filename"]?.stringValue == "upload.csv")
    #expect(result.metadata["xai"]?["bytes"]?.intValue == 512)
    #expect(result.metadata["xai"]?["createdAt"]?.intValue == 1_700_000_000)
    #expect(result.responseMetadata.id == "file_xai_123")
    #expect(result.responseMetadata.headers["xai-request-id"] == "file-request")
    #expect(result.requestMetadata.body?["file"]?["filename"]?.stringValue == "blob")
    #expect(result.requestMetadata.body?["file"]?["mediaType"]?.stringValue == "text/csv")
    #expect(result.requestMetadata.body?["file"]?["byteLength"]?.intValue == 7)
    #expect(result.requestMetadata.body?["file"]?["data"] == nil)
    #expect(result.requestMetadata.body?["teamId"]?.stringValue == "team-123")
    #expect(result.warnings == [
        AIWarning(type: "unsupported", feature: "displayName"),
        AIWarning(type: "unsupported", feature: "purpose")
    ])
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.x.ai/v1/files")
    #expect(request.headers["authorization"] == "Bearer xai-key")
    #expect(request.headers["user-agent"] == "ai-sdk/xai/4.0.58")
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"file\"; filename=\"blob\""))
    #expect(bodyText.contains("name=\"team_id\""))
    #expect(bodyText.contains("team-123"))
    #expect(!bodyText.contains("name=\"purpose\""))
    #expect(!bodyText.contains("Upload"))
}

@Test func xAIFilesUploadMapsProviderOptionsTeamIDLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"file_xai_456","object":"file","filename":"upload.json","bytes":2,"created_at":1700000001}
    """))
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))

    let result = try await provider.files().uploadFile(FileUploadRequest(
        data: Data("{}".utf8),
        mediaType: "application/json",
        filename: "upload.json",
        providerOptions: ["xai": ["teamId": "team-provider", "filePath": "/tmp/upload.json", "unknown": "ignored"]]
    ))

    #expect(result.providerReference["xai"] == "file_xai_456")
    #expect(result.requestMetadata.body?["teamId"]?.stringValue == "team-provider")
    #expect(result.requestMetadata.body?["filePath"] == nil)
    #expect(result.requestMetadata.body?["unknown"] == nil)
    let bodyText = String(data: try #require((await transport.requests()).first?.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"file\"; filename=\"upload.json\""))
    #expect(bodyText.contains("name=\"team_id\""))
    #expect(bodyText.contains("team-provider"))
    #expect(!bodyText.contains("filePath"))
    #expect(!bodyText.contains("ignored"))
}

@Test func xAIFilesUploadValidatesProviderOptionsLikeUpstreamSchema() async throws {
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: RecordingTransport(responses: [])))

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai", message: "xAI file provider options must be an object.")) {
        _ = try await provider.files().uploadFile(FileUploadRequest(
            data: Data("{}".utf8),
            mediaType: "application/json",
            providerOptions: ["xai": "bad"]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.teamId", message: "xAI teamId must be a string.")) {
        _ = try await provider.files().uploadFile(FileUploadRequest(
            data: Data("{}".utf8),
            mediaType: "application/json",
            providerOptions: ["xai": ["teamId": 123]]
        ))
    }

    await #expect(throws: AIError.invalidArgument(argument: "providerOptions.xai.filePath", message: "xAI filePath must be a string.")) {
        _ = try await provider.files().uploadFile(FileUploadRequest(
            data: Data("{}".utf8),
            mediaType: "application/json",
            providerOptions: ["xai": ["filePath": .null]]
        ))
    }
}

@Test func xAIFilesUploadNullProviderOptionsNamespaceKeepsExtraBodyEscapeHatch() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"file_xai_789","object":"file","filename":"upload.txt","bytes":4,"created_at":1700000002}
    """))
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))

    _ = try await provider.files().uploadFile(FileUploadRequest(
        data: Data("text".utf8),
        mediaType: "text/plain",
        providerOptions: ["xai": .null],
        extraBody: ["xai": ["teamId": "team-extra"]]
    ))

    #expect(String(data: try #require((await transport.requests()).first?.body), encoding: .utf8)?.contains("team-extra") == true)
}

@Test func openAISkillsUploadUsesMultipartSkillsEndpoint() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"skill_123","object":"skill","name":"capture-skill","description":"captures data","default_version":"1","latest_version":"2","created_at":1772078479,"updated_at":1772078480}
    """, headers: ["openai-request-id": "skill-request"]))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let result = try await provider.skills().uploadSkill(SkillUploadRequest(
        files: [
            SkillUploadFile(path: "index.ts", data: Data("console.log('hi')".utf8), mediaType: "text/typescript")
        ],
        displayTitle: "Capture Skill"
    ))

    #expect(result.providerReference["openai"] == "skill_123")
    #expect(result.name == "capture-skill")
    #expect(result.description == "captures data")
    #expect(result.latestVersion == "2")
    #expect(result.providerMetadata["openai"]?["defaultVersion"]?.stringValue == "1")
    #expect(result.providerMetadata["openai"]?["createdAt"]?.intValue == 1_772_078_479)
    #expect(result.providerMetadata["openai"]?["updatedAt"]?.intValue == 1_772_078_480)
    #expect(result.responseMetadata.id == "skill_123")
    #expect(result.responseMetadata.headers["openai-request-id"] == "skill-request")
    #expect(result.responseMetadata.body?["latest_version"]?.stringValue == "2")
    #expect(result.requestMetadata.body?["files"]?[0]?["path"]?.stringValue == "index.ts")
    #expect(result.requestMetadata.body?["files"]?[0]?["mediaType"]?.stringValue == "text/typescript")
    #expect(result.requestMetadata.body?["files"]?[0]?["byteLength"]?.intValue == 17)
    #expect(result.requestMetadata.body?["files"]?[0]?["data"] == nil)
    #expect(result.requestMetadata.body?["displayTitle"] == nil)
    #expect(result.warnings == [AIWarning(type: "unsupported", feature: "displayTitle")])

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/skills")
    #expect(request.headers["authorization"] == "Bearer test-key")
    #expect(request.headers["user-agent"] == "ai-sdk/openai/4.0.66")
    #expect(request.headers["content-type"]?.hasPrefix("multipart/form-data; boundary=SwiftAISDK-") == true)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"files[]\"; filename=\"index.ts\""))
    #expect(bodyText.contains("Content-Type: text/typescript"))
    #expect(bodyText.contains("console.log('hi')"))
}

@Test func openAIFilesV4StreamsFieldsBeforeFileAndReturnsTypedFields() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"file-stream","filename":"batch.jsonl","purpose":"batch","bytes":2048,"created_at":1700000000,"expires_at":1700172800,"status":"processed"}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        transport: transport
    ))
    let files = provider.files()
    #expect(files.supportedFileOperations == [.upload, .getMetadata, .download, .delete])

    let result = try await files.uploadFile(FileUploadRequest(
        stream: AsyncThrowingStream { continuation in
            continuation.yield(Data("{\"a\":1}\n".utf8))
            continuation.yield(Data("{\"b\":2}\n".utf8))
            continuation.finish()
        },
        mediaType: "application/jsonl",
        filename: "batch.jsonl",
        providerOptions: ["openai": ["purpose": "batch", "expiresAfter": 172_800]]
    ))

    #expect(result.providerReference == ["openai": "file-stream"])
    #expect(result.byteSize == 2_048)
    #expect(result.createdAt == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(result.expiresAt == Date(timeIntervalSince1970: 1_700_172_800))
    #expect(result.providerMetadata["openai"]?["status"]?.stringValue == "processed")
    #expect(result.requestMetadata.body?["file"]?["type"]?.stringValue == "stream")
    #expect(result.requestMetadata.body?["file"]?["byteLength"] == nil)

    let request = try #require(await transport.requests().first)
    #expect(request.body == nil)
    let stream = try #require(request.bodyStream)
    let body = String(decoding: try await collectFileTestStream(stream), as: UTF8.self)
    let purpose = try #require(body.range(of: #"name="purpose""#)?.lowerBound)
    let expiry = try #require(body.range(of: #"name="expires_after[anchor]""#)?.lowerBound)
    let file = try #require(body.range(of: #"name="file"; filename="batch.jsonl""#)?.lowerBound)
    #expect(purpose < expiry)
    #expect(expiry < file)
    #expect(body.contains("{\"a\":1}\n{\"b\":2}\n"))
}

@Test func openAIFilesV4CancelsStreamWhenOptionsFailBeforeRequest() async throws {
    let probe = FileStreamCancellationProbe()
    let transport = RecordingTransport(responses: [])
    let provider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        transport: transport
    ))

    await #expect(throws: AIError.self) {
        _ = try await provider.files().uploadFile(FileUploadRequest(
            stream: cancellationObservedFileStream(probe),
            mediaType: "application/jsonl",
            providerOptions: ["openai": ["expiresAfter": "soon"]]
        ))
    }

    #expect(await waitForFileStreamCancellation(probe))
    #expect(await transport.requests().isEmpty)
}

@Test func openAIFilesV4CancelsStreamsOnTransportAndResponseProcessingFailures() async throws {
    let transportProbe = FileStreamCancellationProbe()
    let failingProvider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        transport: FailingFileUploadTransport()
    ))
    await #expect(throws: FileUploadTransportFailure.self) {
        _ = try await failingProvider.files().uploadFile(FileUploadRequest(
            stream: cancellationObservedFileStream(transportProbe),
            mediaType: "application/octet-stream"
        ))
    }
    #expect(await waitForFileStreamCancellation(transportProbe))

    let responseProbe = FileStreamCancellationProbe()
    let invalidResponseTransport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        headers: ["content-type": "application/json"],
        body: Data("not-json".utf8)
    ))
    let invalidResponseProvider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        transport: invalidResponseTransport
    ))
    await #expect(throws: Error.self) {
        _ = try await invalidResponseProvider.files().uploadFile(FileUploadRequest(
            stream: cancellationObservedFileStream(responseProbe),
            mediaType: "application/octet-stream"
        ))
    }
    #expect(await waitForFileStreamCancellation(responseProbe))
}

@Test func openAIFilesV4MetadataDownloadDeleteForwardHeadersAbortAndEncodeIDs() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"file/a","object":"file","bytes":1024,"created_at":1700000000,"expires_at":1700172800,"filename":"test.jsonl","purpose":"batch","status":"processed"}
        """),
        AIHTTPResponse(
            statusCode: 200,
            headers: ["content-type": "application/jsonl; charset=utf-8"],
            body: Data("{\"result\":\"ok\"}\n".utf8)
        ),
        jsonResponse(#"{"id":"file/a","object":"file","deleted":true}"#)
    ])
    let provider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        transport: transport
    ))
    let files = provider.files()
    let controller = AIAbortController()
    let reference = ["openai": "file/a"]

    let metadata = try await files.getFileMetadata(FileMetadataRequest(
        file: reference,
        headers: ["X-Test": "metadata"],
        abortSignal: controller.signal
    ))
    #expect(metadata.providerReference == reference)
    #expect(metadata.filename == "test.jsonl")
    #expect(metadata.byteSize == 1_024)
    #expect(metadata.createdAt == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(metadata.expiresAt == Date(timeIntervalSince1970: 1_700_172_800))
    #expect(metadata.providerMetadata["openai"]?["purpose"]?.stringValue == "batch")

    let download = try await files.downloadFile(FileDownloadRequest(
        file: reference,
        headers: ["X-Test": "download"],
        abortSignal: controller.signal
    ))
    #expect(download.mediaType == "application/jsonl")
    #expect(String(decoding: try await collectFileTestStream(download.content), as: UTF8.self) == "{\"result\":\"ok\"}\n")

    let deletion = try await files.deleteFile(FileDeleteRequest(
        file: reference,
        headers: ["X-Test": "delete"],
        abortSignal: controller.signal
    ))
    #expect(deletion.providerReference == reference)
    #expect(deletion.deleted)

    let requests = await transport.requests()
    #expect(requests.map(\.method) == ["GET", "GET", "DELETE"])
    #expect(requests.map(\.url.absoluteString) == [
        "https://api.openai.com/v1/files/file%2Fa",
        "https://api.openai.com/v1/files/file%2Fa/content",
        "https://api.openai.com/v1/files/file%2Fa"
    ])
    #expect(requests[0].headers["X-Test"] == "metadata")
    #expect(requests[1].headers["X-Test"] == "download")
    #expect(requests[2].headers["X-Test"] == "delete")
    #expect(requests.allSatisfy { $0.headers["authorization"] == "Bearer test-key" })
    #expect(requests.allSatisfy { $0.abortSignal === controller.signal })
}

@Test func openAIFilesV4IgnoresUnrepresentableIntegerMetadata() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"file-large","object":"file","bytes":9.223372036854776e18}
    """))
    let files = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        transport: transport
    )).files()

    let metadata = try await files.getFileMetadata(FileMetadataRequest(
        file: ["openai": "file-large"]
    ))

    #expect(metadata.byteSize == nil)
    #expect(metadata.providerMetadata["openai"]?["bytes"]?.doubleValue == Double(Int.max))
}

@Test func managedFilesV4RejectBlankReferencesAndProtectDotSegments() async throws {
    let openAITransport = RecordingTransport(responses: [])
    let openAI = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        transport: openAITransport
    )).files()
    for reference in [["openai": ""], ["openai": "   "], ["other": "file"]] {
        await #expect(throws: AIError.invalidArgument(
            argument: "file",
            message: "file reference is missing an 'openai' file id."
        )) {
            _ = try await openAI.getFileMetadata(FileMetadataRequest(file: reference))
        }
    }
    #expect(await openAITransport.requests().isEmpty)

    let xaiTransport = RecordingTransport(responses: [
        jsonResponse(#"{"id":".","object":"file"}"#),
        jsonResponse(#"{"id":"..","object":"file"}"#)
    ])
    let xai = try AIProviders.xAI(settings: ProviderSettings(
        apiKey: "xai-key",
        transport: xaiTransport
    )).files()
    _ = try await xai.getFileMetadata(FileMetadataRequest(file: ["xai": "."]))
    _ = try await xai.getFileMetadata(FileMetadataRequest(file: ["xai": ".."]))
    #expect((await xaiTransport.requests()).map(\.url.absoluteString) == [
        "https://api.x.ai/v1/files/%252E",
        "https://api.x.ai/v1/files/%252E%252E"
    ])
}

@Test func managedFilesV4EncodesReservedAndNonASCIIFileIDBytes() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"a:b@c;&=+$,/é%","object":"file"}"#)
    ])
    let provider = try AIProviders.openAI(settings: ProviderSettings(
        apiKey: "test-key",
        transport: transport
    ))

    _ = try await provider.files().getFileMetadata(FileMetadataRequest(
        file: ["openai": "a:b@c;&=+$,/é%"]
    ))

    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.openai.com/v1/files/a%3Ab%40c%3B%26%3D%2B%24%2C%2F%C3%A9%25")
}

@Test func xAIFilesV4OrdersExpiryTeamFileAndValidatesExpiry() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"file-xai-stream","object":"file","bytes":3,"created_at":1700000000,"expires_at":1700172800,"filename":"batch.jsonl"}
    """))
    let files = try AIProviders.xAI(settings: ProviderSettings(
        apiKey: "xai-key",
        transport: transport
    )).files()
    #expect(files.supportedFileOperations == [.upload, .getMetadata, .download, .delete])

    let result = try await files.uploadFile(FileUploadRequest(
        stream: AsyncThrowingStream { continuation in
            continuation.yield(Data([1, 2, 3]))
            continuation.finish()
        },
        mediaType: "application/octet-stream",
        providerOptions: ["xai": ["expiresAfter": 172_800, "teamId": "team-1"]]
    ))
    #expect(result.byteSize == 3)
    #expect(result.expiresAt == Date(timeIntervalSince1970: 1_700_172_800))
    #expect(result.providerMetadata["xai"]?["expiresAt"]?.intValue == 1_700_172_800)
    let request = try #require(await transport.requests().first)
    let body = String(decoding: try await collectFileTestStream(try #require(request.bodyStream)), as: UTF8.self)
    let expiry = try #require(body.range(of: #"name="expires_after""#)?.lowerBound)
    let team = try #require(body.range(of: #"name="team_id""#)?.lowerBound)
    let file = try #require(body.range(of: #"name="file""#)?.lowerBound)
    #expect(expiry < team)
    #expect(team < file)

    for invalid: JSONValue in [100, 0.5, 3_599.5, 2_592_001] {
        let invalidTransport = RecordingTransport(responses: [])
        let invalidFiles = try AIProviders.xAI(settings: ProviderSettings(
            apiKey: "xai-key",
            transport: invalidTransport
        )).files()
        await #expect(throws: AIError.invalidArgument(
            argument: "providerOptions.xai.expiresAfter",
            message: "xAI expiresAfter must be an integer between 3600 and 2592000."
        )) {
            _ = try await invalidFiles.uploadFile(FileUploadRequest(
                data: Data([1]),
                mediaType: "application/octet-stream",
                providerOptions: ["xai": ["expiresAfter": invalid]]
            ))
        }
        #expect(await invalidTransport.requests().isEmpty)
    }
}

@Test func xAIFilesV4BufferedMultipartAlsoPlacesExpiryBeforeFile() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"file-xai-buffered","object":"file"}"#))
    let files = try AIProviders.xAI(settings: ProviderSettings(
        apiKey: "xai-key",
        transport: transport
    )).files()
    _ = try await files.uploadFile(FileUploadRequest(
        data: Data([1, 2, 3]),
        mediaType: "application/octet-stream",
        providerOptions: ["xai": ["expiresAfter": 3_600, "teamId": "team-1"]]
    ))

    let request = try #require(await transport.requests().first)
    let body = String(decoding: try #require(request.body), as: UTF8.self)
    let expiry = try #require(body.range(of: #"name="expires_after""#)?.lowerBound)
    let team = try #require(body.range(of: #"name="team_id""#)?.lowerBound)
    let file = try #require(body.range(of: #"name="file""#)?.lowerBound)
    #expect(expiry < team)
    #expect(team < file)
}

@Test func xAIFilesV4MetadataDownloadAndDeleteMatchManagedSurface() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"file-xai","object":"file","bytes":9,"created_at":1700000000,"expires_at":1700003600,"filename":"data.csv","purpose":"assistants","status":"processed"}"#),
        AIHTTPResponse(
            statusCode: 200,
            headers: ["content-type": "text/csv; charset=utf-8"],
            body: Data("a,b\n1,2\n".utf8)
        ),
        jsonResponse(#"{"id":"file-xai","object":"file","deleted":true}"#)
    ])
    let files = try AIProviders.xAI(settings: ProviderSettings(
        apiKey: "xai-key",
        transport: transport
    )).files()
    let reference = ["xai": "file-xai"]

    let metadata = try await files.getFileMetadata(FileMetadataRequest(file: reference))
    #expect(metadata.providerReference == reference)
    #expect(metadata.filename == "data.csv")
    #expect(metadata.byteSize == 9)
    #expect(metadata.providerMetadata["xai"]?["status"]?.stringValue == "processed")

    let download = try await files.downloadFile(FileDownloadRequest(file: reference))
    #expect(download.mediaType == "text/csv")
    #expect(String(decoding: try await collectFileTestStream(download.content), as: UTF8.self) == "a,b\n1,2\n")

    let deletion = try await files.deleteFile(FileDeleteRequest(file: reference))
    #expect(deletion.providerReference == reference)
    #expect(deletion.deleted)
    #expect((await transport.requests()).map(\.method) == ["GET", "GET", "DELETE"])
}

@Test func uploadOnlyFilesClientsKeepOptionalOperationsAndCancelStreams() async throws {
    let transport = RecordingTransport(responses: [])
    let clients: [any AIFileClient] = [
        try AIProviders.anthropic(settings: ProviderSettings(apiKey: "anthropic-key", transport: transport)).files(),
        try AIProviders.google(settings: ProviderSettings(apiKey: "google-key", transport: transport)).files(),
        try AIProviders.deepSeek(settings: ProviderSettings(apiKey: "deepseek-key", transport: transport)).files()
    ]

    for client in clients {
        #expect(client.supportedFileOperations == [.upload])
        await #expect(throws: AIError.self) {
            _ = try await client.deleteFile(FileDeleteRequest(file: ["test": "file"] ))
        }
        let probe = FileStreamCancellationProbe()
        await #expect(throws: AIError.self) {
            _ = try await client.uploadFile(FileUploadRequest(
                stream: cancellationObservedFileStream(probe),
                mediaType: "application/octet-stream"
            ))
        }
        #expect(await waitForFileStreamCancellation(probe))
    }
    #expect(await transport.requests().isEmpty)
}

private func collectFileTestStream(
    _ stream: AsyncThrowingStream<Data, Error>
) async throws -> Data {
    var data = Data()
    for try await chunk in stream { data.append(chunk) }
    return data
}

private final class FileStreamCancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var terminated = false

    var wasTerminated: Bool { lock.withLock { terminated } }

    func recordTermination() {
        lock.withLock { terminated = true }
    }
}

private func cancellationObservedFileStream(
    _ probe: FileStreamCancellationProbe
) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
        continuation.onTermination = { _ in probe.recordTermination() }
    }
}

private func waitForFileStreamCancellation(_ probe: FileStreamCancellationProbe) async -> Bool {
    for _ in 0..<100 {
        if probe.wasTerminated { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return probe.wasTerminated
}

private struct FileUploadTransportFailure: Error {}

private struct FailingFileUploadTransport: AITransport {
    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        throw FileUploadTransportFailure()
    }
}
