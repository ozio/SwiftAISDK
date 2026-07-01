import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesHandlesComputerUseToolCallsLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesComputerUseFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o-mini")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Use the computer to complete a task.")],
        tools: [
            "computerUse": [
                "type": "provider",
                "id": "openai.computer_use",
                "name": "computerUse",
                "args": [:]
            ]
        ]
    ))

    #expect(result.content.count == 3)
    guard case let .toolCall(toolCall) = result.content[0],
          case let .toolResult(toolResult) = result.content[1],
          case let .text(text, textMetadata) = result.content[2] else {
        Issue.record("Expected upstream computer use tool-call, tool-result, and text content")
        return
    }

    #expect(toolCall.id == "computer_67cf2b3051e88190b006770db6fdb13d")
    #expect(toolCall.name == "computer_use")
    #expect(toolCall.arguments == "")
    #expect(toolCall.providerExecuted == true)
    #expect(toolResult.toolCallID == "computer_67cf2b3051e88190b006770db6fdb13d")
    #expect(toolResult.toolName == "computer_use")
    #expect(toolResult.result["type"]?.stringValue == "computer_use_tool_result")
    #expect(toolResult.result["status"]?.stringValue == "completed")
    #expect(text == "I've completed the computer task.")
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_computer_test")
}

@Test func openAIResponsesHandlesMixedURLAndFileCitationAnnotationsLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesMixedCitationsFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))

    #expect(result.content.count == 3)
    guard case let .text(text, textMetadata) = result.content[0],
          case let .source(urlSource) = result.content[1],
          case let .source(fileSource) = result.content[2] else {
        Issue.record("Expected upstream text, URL source, and document source content")
        return
    }

    #expect(text == "Based on web search and file content.")
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_123")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["type"]?.stringValue == "url_citation")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["start_index"]?.intValue == 0)
    #expect(textMetadata["openai"]?["annotations"]?[0]?["end_index"]?.intValue == 10)
    #expect(textMetadata["openai"]?["annotations"]?[0]?["url"]?.stringValue == "https://example.com")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["title"]?.stringValue == "Example URL")
    #expect(textMetadata["openai"]?["annotations"]?[1]?["type"]?.stringValue == "file_citation")
    #expect(textMetadata["openai"]?["annotations"]?[1]?["file_id"]?.stringValue == "file-abc123")
    #expect(textMetadata["openai"]?["annotations"]?[1]?["filename"]?.stringValue == "resource1.json")
    #expect(textMetadata["openai"]?["annotations"]?[1]?["index"]?.intValue == 123)

    #expect(urlSource.id == "id-0")
    #expect(urlSource.sourceType == "url")
    #expect(urlSource.title == "Example URL")
    #expect(urlSource.url == "https://example.com")

    #expect(fileSource.id == "id-1")
    #expect(fileSource.sourceType == "document")
    #expect(fileSource.title == "resource1.json")
    #expect(fileSource.filename == "resource1.json")
    #expect(fileSource.mediaType == "text/plain")
    #expect(fileSource.providerMetadata["openai"]?["type"]?.stringValue == "file_citation")
    #expect(fileSource.providerMetadata["openai"]?["fileId"]?.stringValue == "file-abc123")
    #expect(fileSource.providerMetadata["openai"]?["index"]?.intValue == 123)
}

@Test func openAIResponsesHandlesFileCitationAnnotationsOnlyLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesFileCitationOnlyFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))

    #expect(result.content.count == 2)
    guard case let .text(text, textMetadata) = result.content[0],
          case let .source(source) = result.content[1] else {
        Issue.record("Expected upstream text and document source content")
        return
    }

    #expect(text == "Based on the file content.")
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_456")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["type"]?.stringValue == "file_citation")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["file_id"]?.stringValue == "file-xyz789")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["filename"]?.stringValue == "resource1.json")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["index"]?.intValue == 123)
    #expect(source.id == "id-0")
    #expect(source.sourceType == "document")
    #expect(source.title == "resource1.json")
    #expect(source.filename == "resource1.json")
    #expect(source.mediaType == "text/plain")
    #expect(source.providerMetadata["openai"]?["type"]?.stringValue == "file_citation")
    #expect(source.providerMetadata["openai"]?["fileId"]?.stringValue == "file-xyz789")
    #expect(source.providerMetadata["openai"]?["index"]?.intValue == 123)
}

@Test func openAIResponsesHandlesFileCitationAnnotationsWithoutOptionalFieldsLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesFileCitationsWithoutOptionalFieldsFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))

    #expect(result.content.count == 3)
    guard case let .text(text, textMetadata) = result.content[0],
          case let .source(firstSource) = result.content[1],
          case let .source(secondSource) = result.content[2] else {
        Issue.record("Expected upstream text and two document source content parts")
        return
    }

    #expect(text == "Answer for the specified years....")
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_789")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["file_id"]?.stringValue == "file-YRcoCqn3Fo2K4JgraG")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["filename"]?.stringValue == "resource1.json")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["index"]?.intValue == 145)
    #expect(textMetadata["openai"]?["annotations"]?[1]?["file_id"]?.stringValue == "file-YRcoCqn3Fo2K4JgraG")
    #expect(textMetadata["openai"]?["annotations"]?[1]?["filename"]?.stringValue == "resource1.json")
    #expect(textMetadata["openai"]?["annotations"]?[1]?["index"]?.intValue == 192)

    #expect(firstSource.id == "id-0")
    #expect(firstSource.sourceType == "document")
    #expect(firstSource.title == "resource1.json")
    #expect(firstSource.filename == "resource1.json")
    #expect(firstSource.mediaType == "text/plain")
    #expect(firstSource.providerMetadata["openai"]?["type"]?.stringValue == "file_citation")
    #expect(firstSource.providerMetadata["openai"]?["fileId"]?.stringValue == "file-YRcoCqn3Fo2K4JgraG")
    #expect(firstSource.providerMetadata["openai"]?["index"]?.intValue == 145)

    #expect(secondSource.id == "id-1")
    #expect(secondSource.sourceType == "document")
    #expect(secondSource.title == "resource1.json")
    #expect(secondSource.filename == "resource1.json")
    #expect(secondSource.mediaType == "text/plain")
    #expect(secondSource.providerMetadata["openai"]?["type"]?.stringValue == "file_citation")
    #expect(secondSource.providerMetadata["openai"]?["fileId"]?.stringValue == "file-YRcoCqn3Fo2K4JgraG")
    #expect(secondSource.providerMetadata["openai"]?["index"]?.intValue == 192)
}

@Test func openAIResponsesHandlesContainerFileCitationAnnotationsLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesContainerFileCitationFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))

    #expect(result.content.count == 2)
    guard case let .text(text, textMetadata) = result.content[0],
          case let .source(source) = result.content[1] else {
        Issue.record("Expected upstream text and container file source content")
        return
    }

    #expect(text == "Generated with container file.")
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_container")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["type"]?.stringValue == "container_file_citation")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["container_id"]?.stringValue == "cntr_test")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["file_id"]?.stringValue == "file-container")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["filename"]?.stringValue == "data.csv")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["start_index"]?.intValue == 0)
    #expect(textMetadata["openai"]?["annotations"]?[0]?["end_index"]?.intValue == 10)
    #expect(textMetadata["openai"]?["annotations"]?[0]?["index"] == nil)

    #expect(source.id == "id-0")
    #expect(source.sourceType == "document")
    #expect(source.title == "data.csv")
    #expect(source.filename == "data.csv")
    #expect(source.mediaType == "text/plain")
    #expect(source.providerMetadata["openai"]?["type"]?.stringValue == "container_file_citation")
    #expect(source.providerMetadata["openai"]?["containerId"]?.stringValue == "cntr_test")
    #expect(source.providerMetadata["openai"]?["fileId"]?.stringValue == "file-container")
    #expect(source.providerMetadata["openai"]?["index"] == nil)
}

@Test func openAIResponsesHandlesFilePathAnnotationsLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesFilePathAnnotationFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))

    #expect(result.content.count == 2)
    guard case let .text(text, textMetadata) = result.content[0],
          case let .source(source) = result.content[1] else {
        Issue.record("Expected upstream text and file path source content")
        return
    }

    #expect(text == "Output written to file.")
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_file_path")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["type"]?.stringValue == "file_path")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["file_id"]?.stringValue == "file-path-123")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["index"]?.intValue == 0)

    #expect(source.id == "id-0")
    #expect(source.sourceType == "document")
    #expect(source.title == "file-path-123")
    #expect(source.filename == "file-path-123")
    #expect(source.mediaType == "application/octet-stream")
    #expect(source.providerMetadata["openai"]?["type"]?.stringValue == "file_path")
    #expect(source.providerMetadata["openai"]?["fileId"]?.stringValue == "file-path-123")
    #expect(source.providerMetadata["openai"]?["index"]?.intValue == 0)
}

@Test func openAIResponsesUsesAzureProviderMetadataKeyWhenProviderIncludesAzureLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesAzureProviderMetadataFixtureResponse())
    let provider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))

    #expect(result.providerMetadata["azure"] != nil)
    #expect(result.providerMetadata["openai"] == nil)
    #expect(result.providerMetadata["azure"]?["responseId"]?.stringValue == "resp_provider_metadata_azure")
}

@Test func openAIResponsesUsesOpenAIProviderMetadataKeyWhenProviderDoesNotIncludeAzureLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesOpenAIProviderMetadataFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))

    #expect(result.providerMetadata["openai"] != nil)
    #expect(result.providerMetadata["azure"] == nil)
    #expect(result.providerMetadata["openai"]?["responseId"]?.stringValue == "resp_provider_metadata_openai")
}

@Test func openAIResponsesUsesAzureProviderMetadataKeyInToolCallContentWhenProviderIncludesAzureLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesAzureToolCallProviderMetadataFixtureResponse())
    let provider = try AIProviders.azure(resourceName: "test-resource", settings: ProviderSettings(apiKey: "azure-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesUpstreamFunctionTools()
    ))

    guard case let .toolCall(toolCall) = result.content.first else {
        Issue.record("Expected upstream tool call content")
        return
    }

    #expect(toolCall.providerMetadata["azure"] != nil)
    #expect(toolCall.providerMetadata["openai"] == nil)
}

@Test func openAIResponsesParsesCompactionOutputItemFromRealFixtureLikeUpstream() async throws {
    let fixture = try openAIResponsesFixtureJSON("openai-compaction.1.json")
    let output = try #require(fixture["output"]?.arrayValue)
    let expectedText = try #require(output[0]["content"]?[0]?["text"]?.stringValue)
    let expectedCompactionItemID = try #require(output[1]["id"]?.stringValue)
    let expectedEncryptedContent = try #require(output[1]["encrypted_content"]?.stringValue)
    let transport = RecordingTransport(response: try openAIResponsesFixtureResponse("openai-compaction.1.json"))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: [
            "openai": [
                "store": false,
                "contextManagement": [
                    ["type": "compaction", "compactThreshold": 50000]
                ]
            ]
        ]
    ))

    #expect(result.content.count == 2)
    guard case let .text(text, textMetadata) = result.content[0],
          case let .custom(custom, customMetadata) = result.content[1] else {
        Issue.record("Expected upstream text and compaction custom content")
        return
    }

    #expect(text == expectedText)
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == output[0]["id"]?.stringValue)
    #expect(custom["kind"]?.stringValue == "openai.compaction")
    #expect(customMetadata["openai"]?["type"]?.stringValue == "compaction")
    #expect(customMetadata["openai"]?["itemId"]?.stringValue == expectedCompactionItemID)
    #expect(customMetadata["openai"]?["encryptedContent"]?.stringValue == expectedEncryptedContent)
}

@Test func openAIResponsesSendsContextManagementInRequestBodyLikeUpstream() async throws {
    let transport = RecordingTransport(response: try openAIResponsesFixtureResponse("openai-compaction.1.json"))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: [
            "openai": [
                "store": false,
                "contextManagement": [
                    ["type": "compaction", "compactThreshold": 50000]
                ]
            ]
        ]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["model"]?.stringValue == "gpt-5.2")
    #expect(body["store"]?.boolValue == false)
    #expect(body["context_management"]?[0]?["type"]?.stringValue == "compaction")
    #expect(body["context_management"]?[0]?["compact_threshold"]?.intValue == 50000)
    #expect(body["contextManagement"] == nil)
    #expect(body["context_management"]?[0]?["compactThreshold"] == nil)
}

@Test func openAIResponsesIncludesCompactionItemWithEncryptedContentLikeUpstream() async throws {
    let transport = RecordingTransport(response: try openAIResponsesFixtureResponse("openai-compaction.1.json"))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: [
            "openai": [
                "store": false,
                "contextManagement": [
                    ["type": "compaction", "compactThreshold": 50000]
                ]
            ]
        ]
    ))

    let compactionPart = result.content.first { part in
        guard case let .custom(_, metadata) = part else { return false }
        return metadata["openai"]?["type"]?.stringValue == "compaction"
    }
    guard case let .custom(_, metadata) = compactionPart else {
        Issue.record("Expected upstream compaction custom content")
        return
    }

    #expect(metadata["openai"]?["type"]?.stringValue == "compaction")
    #expect(metadata["openai"]?["itemId"]?.stringValue != nil)
    #expect(metadata["openai"]?["encryptedContent"]?.stringValue != nil)
}

@Test func openAIResponsesExtractsUsageFromCompactionResponseLikeUpstream() async throws {
    let transport = RecordingTransport(response: try openAIResponsesFixtureResponse("openai-compaction.1.json"))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: [
            "openai": [
                "store": false,
                "contextManagement": [
                    ["type": "compaction", "compactThreshold": 50000]
                ]
            ]
        ]
    ))

    #expect(result.usage?.inputTokens == 51097)
    #expect(result.usage?.outputTokens == 2056)
}

@Test func openAIResponsesIncludesPhaseInProviderMetadataForMessageOutputItemsLikeUpstream() async throws {
    let transport = RecordingTransport(response: try openAIResponsesFixtureResponse("openai-phase.1.json"))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.3-codex")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))

    let textParts = result.content.compactMap { part -> (String, [String: JSONValue])? in
        guard case let .text(text, providerMetadata) = part else { return nil }
        return (text, providerMetadata)
    }

    #expect(textParts.count == 2)
    #expect(textParts[0].1["openai"]?["itemId"]?.stringValue == "msg_0465b6d1ae1f97c500699f883243a481a3b50b985223592984")
    #expect(textParts[0].1["openai"]?["phase"]?.stringValue == "commentary")
    #expect(textParts[1].1["openai"]?["itemId"]?.stringValue == "msg_0465b6d1ae1f97c500699f8835e09c81a3b91e9d502ff18555")
    #expect(textParts[1].1["openai"]?["phase"]?.stringValue == "final_answer")
}

@Test func openAIResponsesThrowsWhenShellSkillReferenceCannotResolveOpenAILikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    await #expect(throws: AINoSuchProviderReferenceError(provider: "openai", reference: ["anthropic": "skill_abc"])) {
        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Use a skill.")],
            tools: [
                "shell": OpenAITools.shell(environment: OpenAITools.shellContainerAutoEnvironment(
                    skills: [OpenAITools.shellSkillReference(providerReference: ["anthropic": "skill_abc"])]
                ))
            ]
        ))
    }

    #expect(await transport.requests().isEmpty)
}

@Test func openAIResponsesPreparesShellEnvironmentVariantsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use shells.")],
        tools: [
            "plain_shell": OpenAITools.shell(),
            "empty_container_shell": OpenAITools.shell(environment: OpenAITools.shellContainerAutoEnvironment()),
            "inline_skill_shell": OpenAITools.shell(environment: OpenAITools.shellContainerAutoEnvironment(
                skills: [OpenAITools.shellInlineSkill(name: "my-skill", description: "A test skill", base64ZipData: "dGVzdA==")]
            )),
            "disabled_network_shell": OpenAITools.shell(environment: OpenAITools.shellContainerAutoEnvironment(
                networkPolicy: OpenAITools.shellDisabledNetworkPolicy()
            )),
            "allowlist_network_shell": OpenAITools.shell(environment: OpenAITools.shellContainerAutoEnvironment(
                networkPolicy: OpenAITools.shellAllowlistNetworkPolicy(
                    allowedDomains: ["example.com", "api.test.org"],
                    domainSecrets: [
                        OpenAITools.shellDomainSecret(domain: "api.test.org", name: "API_KEY", value: "secret123")
                    ]
                )
            )),
            "file_memory_shell": OpenAITools.shell(environment: OpenAITools.shellContainerAutoEnvironment(
                fileIDs: ["file-1", "file-2"],
                memoryLimit: "16g"
            )),
            "referenced_container_shell": OpenAITools.shell(environment: OpenAITools.shellContainerReferenceEnvironment(containerID: "ctr_abc123")),
            "local_shell": OpenAITools.shell(environment: OpenAITools.shellLocalEnvironment(
                skills: [OpenAITools.shellLocalSkill(name: "calculator", description: "Perform math calculations", path: "/path/to/calculator")]
            )),
            "implicit_local_shell": OpenAITools.shell(environment: [
                "skills": [
                    [
                        "name": "calculator",
                        "description": "Perform math calculations",
                        "path": "/path/to/calculator"
                    ]
                ]
            ]),
            "empty_local_shell": OpenAITools.shell(environment: OpenAITools.shellLocalEnvironment())
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let tools = try #require(body["tools"]?.arrayValue)
    let shellTools = tools.filter { $0["type"]?.stringValue == "shell" }
    let hasEmptyContainer = shellTools.contains { tool in
        let environment = tool["environment"]
        return environment?["type"]?.stringValue == "container_auto"
            && environment?["skills"] == nil
            && environment?["network_policy"] == nil
    }
    let hasContainerReference = shellTools.contains { tool in
        let environment = tool["environment"]
        return environment?["type"]?.stringValue == "container_reference"
            && environment?["container_id"]?.stringValue == "ctr_abc123"
    }
    let hasLocalEnvironment = shellTools.contains { tool in
        let environment = tool["environment"]
        return environment?["type"]?.stringValue == "local"
            && environment?["skills"]?[0]?["path"]?.stringValue == "/path/to/calculator"
    }

    #expect(shellTools.count == 10)
    #expect(shellTools.contains { $0["environment"] == nil })
    #expect(hasEmptyContainer)
    #expect(shellTools.contains { $0["environment"]?["skills"]?[0]?["source"]?["media_type"]?.stringValue == "application/zip" })
    #expect(shellTools.contains { $0["environment"]?["network_policy"]?["type"]?.stringValue == "disabled" })
    #expect(shellTools.contains { $0["environment"]?["network_policy"]?["allowed_domains"]?[1]?.stringValue == "api.test.org" })
    #expect(shellTools.contains { $0["environment"]?["network_policy"]?["domain_secrets"]?[0]?["value"]?.stringValue == "secret123" })
    #expect(shellTools.contains { $0["environment"]?["file_ids"]?[1]?.stringValue == "file-2" && $0["environment"]?["memory_limit"]?.stringValue == "16g" })
    #expect(hasContainerReference)
    #expect(hasLocalEnvironment)
    #expect(shellTools.contains { $0["environment"]?["type"]?.stringValue == "local" && $0["environment"]?["skills"] == nil })
}

