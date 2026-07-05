import Foundation
import Testing
@testable import SwiftAISDK

@Test func anthropicPDFFilePartDoesNotIncludeCitationsByDefaultLikeUpstream() async throws {
    let pdfData = Data("%PDF-1.7\n".utf8)
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .file(mimeType: "application/pdf", data: pdfData)
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let document = try #require(body["messages"]?[0]?["content"]?[0])
    #expect(document["type"]?.stringValue == "document")
    #expect(document["source"] == [
        "type": "base64",
        "media_type": "application/pdf",
        "data": .string(pdfData.base64EncodedString())
    ])
    #expect(document["citations"] == nil)
    #expect(document["title"] == nil)
    #expect(request.headers["anthropic-beta"] == "pdfs-2024-09-25")
}

@Test func anthropicPDFFilePartCitationsMapLikeUpstream() async throws {
    let pdfData = Data("%PDF-1.7\n".utf8)
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .file(
                mimeType: "application/pdf",
                data: pdfData,
                providerMetadata: ["anthropic": ["citations": ["enabled": true]]]
            )
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let document = try #require(body["messages"]?[0]?["content"]?[0])
    #expect(document["type"]?.stringValue == "document")
    #expect(document["source"] == [
        "type": "base64",
        "media_type": "application/pdf",
        "data": .string(pdfData.base64EncodedString())
    ])
    #expect(document["citations"] == ["enabled": true])
}

@Test func anthropicPDFFilePartCustomTitleContextCitationsMapLikeUpstream() async throws {
    let pdfData = Data("%PDF-1.7\n".utf8)
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .file(
                mimeType: "application/pdf",
                data: pdfData,
                filename: "original-name.pdf",
                providerMetadata: [
                    "anthropic": [
                        "title": "Custom Document Title",
                        "context": "This is metadata about the document",
                        "citations": ["enabled": true]
                    ]
                ]
            )
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let document = try #require(body["messages"]?[0]?["content"]?[0])
    #expect(document["type"]?.stringValue == "document")
    #expect(document["title"]?.stringValue == "Custom Document Title")
    #expect(document["context"]?.stringValue == "This is metadata about the document")
    #expect(document["citations"] == ["enabled": true])
}

@Test func anthropicMultiplePDFFilePartCitationsMapLikeUpstream() async throws {
    let pdfData1 = Data("%PDF-1.7 doc1\n".utf8)
    let pdfData2 = Data("%PDF-1.7 doc2\n".utf8)
    let transport = RecordingTransport(response: jsonResponse("""
    {"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":3,"output_tokens":2}}
    """))
    let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "claude-key", transport: transport))
    let model = try provider.languageModel("claude-sonnet-4-6")

    _ = try await model.generate(LanguageModelRequest(messages: [
        AIMessage(role: .user, content: [
            .file(
                mimeType: "application/pdf",
                data: pdfData1,
                filename: "doc1.pdf",
                providerMetadata: [
                    "anthropic": [
                        "citations": ["enabled": true],
                        "title": "Custom Title 1"
                    ]
                ]
            ),
            .file(
                mimeType: "application/pdf",
                data: pdfData2,
                filename: "doc2.pdf",
                providerMetadata: [
                    "anthropic": [
                        "citations": ["enabled": true],
                        "title": "Custom Title 2",
                        "context": "Additional context for document 2"
                    ]
                ]
            ),
            .text("Analyze both documents")
        ])
    ]))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let content = try #require(body["messages"]?[0]?["content"]?.arrayValue)
    #expect(content.count == 3)
    #expect(content[0]["type"]?.stringValue == "document")
    #expect(content[0]["source"]?["data"]?.stringValue == pdfData1.base64EncodedString())
    #expect(content[0]["title"]?.stringValue == "Custom Title 1")
    #expect(content[0]["citations"] == ["enabled": true])
    #expect(content[0]["context"] == nil)
    #expect(content[1]["type"]?.stringValue == "document")
    #expect(content[1]["source"]?["data"]?.stringValue == pdfData2.base64EncodedString())
    #expect(content[1]["title"]?.stringValue == "Custom Title 2")
    #expect(content[1]["context"]?.stringValue == "Additional context for document 2")
    #expect(content[1]["citations"] == ["enabled": true])
    #expect(content[2] == ["type": "text", "text": "Analyze both documents"])
}

@Test func anthropicModelCapabilitiesMirrorUpstreamLanguageModelMatrix() throws {
    let newOpus = anthropicModelCapabilities("claude-opus-4-8")
    #expect(newOpus.maxOutputTokens == 128_000)
    #expect(newOpus.supportsStructuredOutput == true)
    #expect(newOpus.supportsAdaptiveThinking == true)
    #expect(newOpus.rejectsSamplingParameters == true)
    #expect(newOpus.supportsXhighEffort == true)
    #expect(newOpus.isKnownModel == true)

    let fable = anthropicModelCapabilities("claude-fable-5")
    #expect(fable.maxOutputTokens == 128_000)
    #expect(fable.rejectsSamplingParameters == true)
    #expect(fable.supportsXhighEffort == true)

    let sonnet5 = anthropicModelCapabilities("claude-sonnet-5")
    #expect(sonnet5.maxOutputTokens == 128_000)
    #expect(sonnet5.supportsStructuredOutput == true)
    #expect(sonnet5.supportsAdaptiveThinking == true)
    #expect(sonnet5.rejectsSamplingParameters == true)
    #expect(sonnet5.supportsXhighEffort == true)

    let opus47 = anthropicModelCapabilities("claude-opus-4-7")
    #expect(opus47.maxOutputTokens == 128_000)
    #expect(opus47.rejectsSamplingParameters == true)
    #expect(opus47.supportsXhighEffort == true)

    let opus46 = anthropicModelCapabilities("claude-opus-4-6")
    #expect(opus46.rejectsSamplingParameters == false)
    #expect(opus46.supportsXhighEffort == false)
    #expect(opus46.supportsAdaptiveThinking == true)

    let sonnet46 = anthropicModelCapabilities("claude-sonnet-4-6")
    #expect(sonnet46.rejectsSamplingParameters == false)
    #expect(sonnet46.supportsXhighEffort == false)
    #expect(sonnet46.supportsAdaptiveThinking == true)
}
