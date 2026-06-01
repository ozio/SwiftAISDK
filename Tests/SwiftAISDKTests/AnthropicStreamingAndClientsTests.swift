import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicFilesUploadAddsBetaHeader() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"file_abc","type":"file","filename":"data.pdf","mime_type":"application/pdf","size_bytes":10,"created_at":"2026-01-01T00:00:00Z","downloadable":true}
    """, headers: ["anthropic-request-id": "file-request"]))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let files = provider.files()
    #expect(files.providerID == "anthropic.messages")
    let result = try await files.uploadFile(FileUploadRequest(data: Data([1, 2, 3]), mediaType: "application/pdf", filename: "data.pdf"))

    #expect(result.providerReference["anthropic"] == "file_abc")
    #expect(result.mediaType == "application/pdf")
    #expect(result.responseMetadata.id == "file_abc")
    #expect(result.responseMetadata.headers["anthropic-request-id"] == "file-request")
    #expect(result.requestMetadata.body?["file"]?["filename"]?.stringValue == "data.pdf")
    #expect(result.requestMetadata.body?["file"]?["mediaType"]?.stringValue == "application/pdf")
    #expect(result.requestMetadata.body?["file"]?["byteLength"]?.intValue == 3)
    #expect(result.requestMetadata.body?["file"]?["data"] == nil)
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.anthropic.com/v1/files")
    #expect(request.headers["x-api-key"] == "claude-key")
    #expect(request.headers["anthropic-beta"] == "files-api-2025-04-14")
}

@Test func anthropicSkillsUploadAddsBetaHeaderAndFetchesVersionMetadata() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"skill_01","display_title":"Test Capture Skill","latest_version":"1772078378207930","source":"custom","created_at":"2026-02-26T03:59:39.314772Z","updated_at":"2026-02-26T03:59:39.314772Z"}
        """, headers: ["anthropic-request-id": "skill-request"]),
        jsonResponse("""
        {"type":"skill_version","skill_id":"skill_01","name":"test-capture-skill","description":"An updated test skill for fixture capture"}
        """)
    ])
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let skills = provider.skills()
    #expect(skills.providerID == "anthropic.skills")
    let result = try await skills.uploadSkill(SkillUploadRequest(
        files: [
            SkillUploadFile(path: "index.ts", data: Data("console.log('hi')".utf8), mediaType: "text/typescript")
        ],
        displayTitle: "My Custom Title"
    ))

    #expect(result.providerReference["anthropic"] == "skill_01")
    #expect(result.displayTitle == "Test Capture Skill")
    #expect(result.name == "test-capture-skill")
    #expect(result.description == "An updated test skill for fixture capture")
    #expect(result.latestVersion == "1772078378207930")
    #expect(result.providerMetadata["anthropic"]?["source"]?.stringValue == "custom")
    #expect(result.providerMetadata["anthropic"]?["createdAt"]?.stringValue == "2026-02-26T03:59:39.314772Z")
    #expect(result.providerMetadata["anthropic"]?["updatedAt"]?.stringValue == "2026-02-26T03:59:39.314772Z")
    #expect(result.responseMetadata.id == "skill_01")
    #expect(result.responseMetadata.headers["anthropic-request-id"] == "skill-request")
    #expect(result.responseMetadata.body?["latest_version"]?.stringValue == "1772078378207930")
    #expect(result.requestMetadata.body?["files"]?[0]?["path"]?.stringValue == "index.ts")
    #expect(result.requestMetadata.body?["files"]?[0]?["mediaType"]?.stringValue == "text/typescript")
    #expect(result.requestMetadata.body?["files"]?[0]?["byteLength"]?.intValue == 17)
    #expect(result.requestMetadata.body?["files"]?[0]?["data"] == nil)
    #expect(result.requestMetadata.body?["displayTitle"]?.stringValue == "My Custom Title")
    #expect(result.warnings.isEmpty)

    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].url.absoluteString == "https://api.anthropic.com/v1/skills")
    #expect(requests[0].headers["x-api-key"] == "claude-key")
    #expect(requests[0].headers["anthropic-beta"] == "skills-2025-10-02")
    #expect(requests[0].headers["content-type"]?.hasPrefix("multipart/form-data; boundary=SwiftAISDK-") == true)
    let bodyText = String(data: try #require(requests[0].body), encoding: .utf8) ?? ""
    #expect(bodyText.contains("name=\"display_title\""))
    #expect(bodyText.contains("My Custom Title"))
    #expect(bodyText.contains("name=\"files[]\"; filename=\"index.ts\""))
    #expect(bodyText.contains("Content-Type: text/typescript"))
    #expect(requests[1].method == "GET")
    #expect(requests[1].url.absoluteString == "https://api.anthropic.com/v1/skills/skill_01/versions/1772078378207930")
    #expect(requests[1].headers["anthropic-beta"] == "skills-2025-10-02")
}

@Test func anthropicAWSFilesAndSkillsUseUpstreamProviderIDs() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"file_aws","type":"file","filename":"data.pdf","mime_type":"application/pdf","size_bytes":10}
        """),
        jsonResponse("""
        {"id":"skill_aws","display_title":"AWS Skill","latest_version":"v1","source":"custom"}
        """),
        jsonResponse("""
        {"type":"skill_version","skill_id":"skill_aws","name":"aws-skill","description":"AWS hosted skill"}
        """)
    ])
    let provider = try AIProviders.anthropicAWS(settings: AnthropicAWSProviderSettings(
        region: "us-west-2",
        workspaceID: "wrkspc_test",
        apiKey: "aws-api-key",
        transport: transport
    ))

    let files = provider.files()
    #expect(files.providerID == "anthropic-aws.messages")
    let file = try await files.uploadFile(FileUploadRequest(data: Data([1, 2, 3]), mediaType: "application/pdf", filename: "data.pdf"))
    #expect(file.providerReference["anthropic-aws"] == "file_aws")

    let skills = provider.skills()
    #expect(skills.providerID == "anthropic-aws.skills")
    let skill = try await skills.uploadSkill(SkillUploadRequest(
        files: [
            SkillUploadFile(path: "index.ts", data: Data("console.log('hi')".utf8), mediaType: "text/typescript")
        ],
        displayTitle: "AWS Skill"
    ))
    #expect(skill.providerReference["anthropic-aws"] == "skill_aws")
    #expect(skill.providerMetadata["anthropic-aws"]?["source"]?.stringValue == "custom")

    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].url.absoluteString == "https://aws-external-anthropic.us-west-2.api.aws/v1/files")
    #expect(requests[0].headers["x-api-key"] == "aws-api-key")
    #expect(requests[0].headers["anthropic-beta"] == "files-api-2025-04-14")
    #expect(requests[1].url.absoluteString == "https://aws-external-anthropic.us-west-2.api.aws/v1/skills")
    #expect(requests[1].headers["anthropic-beta"] == "skills-2025-10-02")
    #expect(requests[2].url.absoluteString == "https://aws-external-anthropic.us-west-2.api.aws/v1/skills/skill_aws/versions/v1")
}

@Test func anthropicLanguageStreamsMessagesEvents() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hel"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"lo"}}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":2}}

    event: message_stop
    data: {"type":"message_stop"}

    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-5-haiku-latest")

    var deltas: [String] = []
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .textDelta(delta):
            deltas.append(delta)
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(deltas == ["hel", "lo"])
    #expect(finishReason == "stop")
    let request = try #require(await transport.requests().first)
    #expect(request.url.absoluteString == "https://api.anthropic.com/v1/messages")
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["stream"] == true)
}

@Test func anthropicLanguageStreamsThinkingDeltasAndMappedFinishReason() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"think"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"answer"}}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"},"usage":{"output_tokens":3}}

    event: message_stop
    data: {"type":"message_stop"}

    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-7-sonnet-latest")

    var reasoning: [String] = []
    var text: [String] = []
    var finishReason: String?
    var outputTokens: Int?
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .reasoningDelta(delta):
            reasoning.append(delta)
        case let .textDelta(delta):
            text.append(delta)
        case let .finish(reason, usage):
            finishReason = reason
            outputTokens = usage?.outputTokens
        default:
            break
        }
    }

    #expect(reasoning == ["think"])
    #expect(text == ["answer"])
    #expect(finishReason == "length")
    #expect(outputTokens == 3)
}

@Test func anthropicLanguageStreamsToolUseDeltasAndFinalCall() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    event: content_block_start
    data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"lookup","input":{}}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"query\\":"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\\"weather\\"}"}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":0}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":4}}

    event: message_stop
    data: {"type":"message_stop"}

    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-5-haiku-latest")

    var deltas: [String] = []
    var inputLifecycle: [String] = []
    var toolCall: AIToolCall?
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(
        messages: [.user("Use a tool.")],
        tools: ["lookup": ["type": "object", "properties": ["query": ["type": "string"]]]]
    )) {
        switch part {
        case let .toolInputStart(id, name, _, _, _, _):
            inputLifecycle.append("start:\(id):\(name)")
        case let .toolInputDelta(id, delta, _):
            inputLifecycle.append("delta:\(id):\(delta)")
        case let .toolInputEnd(id, _):
            inputLifecycle.append("end:\(id)")
        case let .toolCallDelta(_, _, argumentsDelta, _):
            deltas.append(argumentsDelta)
        case let .toolCall(call):
            toolCall = call
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    let finalToolCall = try #require(toolCall)
    #expect(deltas == ["", "{\"query\":", "\"weather\"}"])
    #expect(inputLifecycle == [
        "start:toolu_1:lookup",
        "delta:toolu_1:{\"query\":",
        "delta:toolu_1:\"weather\"}",
        "end:toolu_1"
    ])
    #expect(finalToolCall.id == "toolu_1")
    #expect(finalToolCall.name == "lookup")
    #expect(finalToolCall.providerExecuted == false)
    #expect(try decodeJSONBody(Data(finalToolCall.arguments.utf8))["query"]?.stringValue == "weather")
    #expect(finishReason == "tool-calls")
}

@Test func anthropicLanguageStreamsCitationSources() async throws {
    let transport = RecordingTransport(response: sseResponse("""
    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Based on the document"}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,"delta":{"type":"citations_delta","citation":{"type":"char_location","cited_text":"important information","document_index":0,"document_title":"Test Document","start_char_index":15,"end_char_index":35}}}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":2}}

    event: message_stop
    data: {"type":"message_stop"}

    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-3-5-haiku-latest")

    var deltas: [String] = []
    var sources: [AISource] = []
    var finishReason: String?
    for try await part in model.stream(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .data(mimeType: "text/plain", data: Data("Test document content".utf8)),
            .text("What does this say?")
        ])
    ])) {
        switch part {
        case let .textDelta(delta):
            deltas.append(delta)
        case let .source(source):
            sources.append(source)
        case let .finish(reason, _):
            finishReason = reason
        default:
            break
        }
    }

    #expect(deltas == ["Based on the document"])
    #expect(sources.count == 1)
    #expect(sources[0].id == "anthropic-source-0")
    #expect(sources[0].sourceType == "document")
    #expect(sources[0].title == "Test Document")
    #expect(sources[0].mediaType == "text/plain")
    #expect(sources[0].providerMetadata["anthropic"]?["citedText"]?.stringValue == "important information")
    #expect(sources[0].providerMetadata["anthropic"]?["startCharIndex"]?.intValue == 15)
    #expect(sources[0].providerMetadata["anthropic"]?["endCharIndex"]?.intValue == 35)
    #expect(finishReason == "stop")
}
