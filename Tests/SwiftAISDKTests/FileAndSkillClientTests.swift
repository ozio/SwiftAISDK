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
    #expect(request.headers["Authorization"] == "Bearer test-key")
    #expect(request.headers["content-type"]?.hasPrefix("multipart/form-data; boundary=SwiftAISDK-") == true)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"file\"; filename=\"notes.txt\""))
    #expect(bodyText.contains("name=\"purpose\""))
    #expect(bodyText.contains("assistants"))
    #expect(!bodyText.contains("name=\"display_name\""))
    #expect(!bodyText.contains("Notes"))
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
    #expect(request.headers["Authorization"] == "Bearer xai-key")
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"file\"; filename=\"blob\""))
    #expect(bodyText.contains("name=\"team_id\""))
    #expect(bodyText.contains("team-123"))
    #expect(!bodyText.contains("name=\"purpose\""))
    #expect(!bodyText.contains("Upload"))
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
    #expect(request.headers["Authorization"] == "Bearer test-key")
    #expect(request.headers["content-type"]?.hasPrefix("multipart/form-data; boundary=SwiftAISDK-") == true)
    let bodyText = String(data: try #require(request.body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"files[]\"; filename=\"index.ts\""))
    #expect(bodyText.contains("Content-Type: text/typescript"))
    #expect(bodyText.contains("console.log('hi')"))
}
