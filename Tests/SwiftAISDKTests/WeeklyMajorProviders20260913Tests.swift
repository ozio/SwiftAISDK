import Foundation
import Testing
@testable import SwiftAISDK

@Suite("WeeklyMajorProviders20260913", .serialized)
struct WeeklyMajorProviders20260913Tests {
    @Test func emptyToolCallArraysDoNotInterruptReasoningStreams() async throws {
        let alibabaTransport = RecordingTransport(response: sseResponse("""
        data: {"choices":[{"delta":{"reasoning_content":"Think ","tool_calls":[]},"finish_reason":null}]}

        data: {"choices":[{"delta":{"reasoning_content":"more...","tool_calls":[]},"finish_reason":null}]}

        data: {"choices":[{"delta":{"content":"Hello","tool_calls":[]},"finish_reason":"stop"}]}

        data: [DONE]

        """))
        let alibaba = try AIProviders.alibaba(settings: ProviderSettings(apiKey: "key", transport: alibabaTransport))
        let alibabaLifecycle = try await reasoningLifecycle(from: alibaba.languageModel("qwen3-max"))
        #expect(alibabaLifecycle == [
            "start:reasoning-0",
            "delta:reasoning-0:Think ",
            "delta:reasoning-0:more...",
            "end:reasoning-0"
        ])

        let groqTransport = RecordingTransport(response: sseResponse("""
        data: {"choices":[{"delta":{"reasoning":"Think ","tool_calls":[]},"finish_reason":null}]}

        data: {"choices":[{"delta":{"reasoning":"more...","tool_calls":[]},"finish_reason":null}]}

        data: {"choices":[{"delta":{"content":"Hello","tool_calls":[]},"finish_reason":"stop"}]}

        data: [DONE]

        """))
        let groq = try AIProviders.groq(settings: ProviderSettings(apiKey: "key", transport: groqTransport))
        let groqLifecycle = try await reasoningLifecycle(from: groq.languageModel("qwen/qwen3-32b"))
        #expect(groqLifecycle == [
            "start:reasoning-0",
            "delta:reasoning-0:Think ",
            "delta:reasoning-0:more...",
            "end:reasoning-0"
        ])

        let deepSeekTransport = RecordingTransport(response: sseResponse("""
        data: {"choices":[{"delta":{"reasoning_content":"Think ","tool_calls":[]},"finish_reason":null}]}

        data: {"choices":[{"delta":{"reasoning_content":"more...","tool_calls":[]},"finish_reason":null}]}

        data: {"choices":[{"delta":{"content":"Hello","tool_calls":[]},"finish_reason":"stop"}]}

        data: [DONE]

        """))
        let deepSeek = try AIProviders.deepSeek(settings: ProviderSettings(apiKey: "key", transport: deepSeekTransport))
        let deepSeekLifecycle = try await reasoningLifecycle(from: deepSeek.languageModel("deepseek-reasoner"))
        #expect(deepSeekLifecycle == [
            "start:reasoning-0",
            "delta:reasoning-0:Think ",
            "delta:reasoning-0:more...",
            "end:reasoning-0"
        ])
    }

    @Test func deepSeekV4AliasesPreserveReasoningAndDisableSampling() throws {
        for modelID in [
            "deepseek-v4-pro",
            "deepseek-v4-pro-0813",
            "deepseek-v4-flash",
            "deepseek-v4-flash-0731",
            "deepseek-v4-flash-vision-exp",
            "deepseek-flash",
            "deepseek-pro"
        ] {
            #expect(deepSeekIsV4Model(modelID))
        }
        #expect(!deepSeekIsV4Model("deepseek-chat"))
        #expect(!deepSeekIsV4Model("deepseek-reasoner"))

        let messages = try deepSeekMessages(
            [
                .assistant("Previous", reasoning: "preserved thought"),
                .user("Continue")
            ],
            responseFormat: nil,
            modelID: "deepseek-flash"
        )
        #expect(messages.messages[0]["reasoning_content"]?.stringValue == "preserved thought")

        let prepared = try deepSeekPreparedCall(
            for: LanguageModelRequest(messages: [.user("Hi")], temperature: 0.7, topP: 0.8),
            modelID: "deepseek-pro",
            stream: false
        )
        #expect(prepared.body["temperature"] == nil)
        #expect(prepared.body["top_p"] == nil)
        #expect(prepared.warnings.contains { $0.type == "unsupported" && $0.feature == "temperature" })
        #expect(prepared.warnings.contains { $0.type == "unsupported" && $0.feature == "topP" })
    }

    @Test func mistralCurrentReasoningModelsSendReasoningEffort() async throws {
        let completeSet = [
            "glm-5-2",
            "labs-leanstral-1-5",
            "labs-leanstral-1-5-1",
            "magistral-medium-latest",
            "magistral-small-latest",
            "mistral-medium",
            "mistral-medium-2604",
            "mistral-medium-3",
            "mistral-medium-3-5",
            "mistral-medium-3.5",
            "mistral-medium-latest",
            "mistral-small-2603",
            "mistral-small-latest",
            "mistral-vibe-cli-fast",
            "mistral-vibe-cli-latest",
            "mistral-vibe-cli-with-tools",
            "zai-glm-5-2"
        ]
        for modelID in completeSet {
            #expect(mistralSupportsReasoningEffort(modelID))
        }

        for modelID in [
            "mistral-medium-3-5",
            "mistral-medium-latest",
            "mistral-vibe-cli-fast",
            "zai-glm-5-2",
            "glm-5-2",
            "labs-leanstral-1-5"
        ] {
            let transport = RecordingTransport(response: jsonResponse("""
            {"id":"cmpl-1","model":"\(modelID)","choices":[{"message":{"content":"ok"},"finish_reason":"stop"}],"usage":{"total_tokens":1}}
            """))
            let provider = try AIProviders.mistral(settings: ProviderSettings(apiKey: "key", transport: transport))
            let result = try await provider.languageModel(modelID).generate(LanguageModelRequest(
                messages: [.user("Hi")],
                reasoning: "high"
            ))
            #expect(!result.warnings.contains { $0.type == "unsupported" && $0.feature == "reasoning" })
            let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
            #expect(body["reasoning_effort"]?.stringValue == "high")
        }
    }

    @Test func anthropicReturnsInputTransformationsAndStrictPrefixMismatch() async throws {
        let transformations: JSONValue = [
            ["type": "octet_length", "path": "/messages/0/content", "reason": "normalization"]
        ]
        let transport = RecordingTransport(response: jsonResponse("""
        {"id":"msg-1","model":"claude-opus-4-6","content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1},"input_transformations":[{"type":"octet_length","path":"/messages/0/content","reason":"normalization"}]}
        """))
        let provider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "key", transport: transport))
        let result = try await provider.languageModel("claude-opus-4-6").generate(LanguageModelRequest(
            messages: [.user("Hi")],
            providerOptions: [
                "anthropic": [
                    "thinking": [
                        "type": "adaptive",
                        "blockBinding": ["prefixMismatchBehavior": "error"]
                    ]
                ]
            ]
        ))
        #expect(result.providerMetadata["anthropic"]?["inputTransformations"] == transformations)
        let request = try #require(await transport.requests().first)
        let body = try decodeJSONBody(try #require(request.body))
        #expect(body["thinking"]?["block_binding"]?["prefix_mismatch_behavior"]?.stringValue == "error")
        #expect(request.headers["anthropic-beta"]?.contains("thinking-binding-controls-2026-08-01") == true)

        let streamTransport = RecordingTransport(response: sseResponse("""
        data: {"type":"message_start","message":{"id":"msg-stream","model":"claude-opus-4-6","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"output_tokens":0},"input_transformations":[{"type":"start","path":"/messages/0","reason":"start"}]}}

        data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":1},"input_transformations":[{"type":"delta","path":"/messages/1","reason":"latest"}]}

        data: {"type":"message_stop"}

        """))
        let streamProvider = try AIProviders.anthropic(settings: ProviderSettings(apiKey: "key", transport: streamTransport))
        let streamModel = try streamProvider.languageModel("claude-opus-4-6")
        var finishMetadata: [String: JSONValue] = [:]
        for try await part in streamModel.stream(LanguageModelRequest(messages: [.user("Hi")])) {
            if case let .finishMetadata(_, _, metadata) = part {
                finishMetadata = metadata
            }
        }
        #expect(finishMetadata["anthropic"]?["inputTransformations"] == [
            ["type": "delta", "path": "/messages/1", "reason": "latest"]
        ])
    }

    @Test func amazonBedrockEndpointPrecedencePartitionsAndMantleIncludes() async throws {
        var regionReads = 0
        let explicit = resolveAmazonBedrockBaseURL(
            baseURL: "https://explicit.example.com/",
            serviceEndpointURL: "https://service.example.com/",
            globalEndpointURL: "https://global.example.com/",
            service: "bedrock-runtime",
            getRegion: {
                regionReads += 1
                return "us-east-1"
            }
        )
        #expect(explicit == "https://explicit.example.com")
        #expect(regionReads == 0)

        let service = resolveAmazonBedrockBaseURL(
            baseURL: nil,
            serviceEndpointURL: "https://service.example.com/",
            globalEndpointURL: "https://global.example.com/",
            service: "bedrock-runtime",
            getRegion: {
                regionReads += 1
                return "us-east-1"
            }
        )
        #expect(service == "https://service.example.com")
        #expect(regionReads == 0)

        let global = resolveAmazonBedrockBaseURL(
            baseURL: nil,
            serviceEndpointURL: nil,
            globalEndpointURL: "https://global.example.com/",
            service: "bedrock-agent-runtime",
            getRegion: {
                regionReads += 1
                return "us-east-1"
            }
        )
        #expect(global == "https://global.example.com")
        #expect(regionReads == 0)

        let suffixes = [
            ("cn-north-1", "amazonaws.com.cn"),
            ("us-gov-west-1", "amazonaws.com"),
            ("us-iso-east-1", "c2s.ic.gov"),
            ("us-isob-east-1", "sc2s.sgov.gov"),
            ("eu-isoe-west-1", "cloud.adc-e.uk"),
            ("us-isof-south-1", "csp.hci.ic.gov"),
            ("eusc-de-east-1", "amazonaws.eu"),
            ("ap-northeast-1", "amazonaws.com")
        ]
        for (region, suffix) in suffixes {
            let url = resolveAmazonBedrockBaseURL(
                baseURL: nil,
                serviceEndpointURL: nil,
                globalEndpointURL: nil,
                service: "bedrock-runtime",
                getRegion: { region }
            )
            #expect(url == "https://bedrock-runtime.\(region).\(suffix)")
        }

        let transport = RecordingTransport(response: jsonResponse("""
        {"id":"resp-1","status":"completed","output_text":"ok"}
        """))
        let provider = try AIProviders.bedrockMantle(settings: AmazonBedrockProviderSettings(
            region: "us-east-1",
            apiKey: "key",
            transport: transport
        ))
        let model = try provider.responses("openai.gpt-oss-120b")
        let webSearchTool: JSONValue = [
            "type": "provider",
            "id": "openai.web_search",
            "name": "webSearch",
            "args": [:]
        ]

        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Search")],
            tools: ["webSearch": webSearchTool]
        ))
        let automaticBody = try decodeJSONBody(try #require((await transport.requests())[0].body))
        #expect(automaticBody["tools"]?[0]?["type"]?.stringValue == "web_search")
        #expect(automaticBody["include"] == nil)

        _ = try await model.generate(LanguageModelRequest(
            messages: [.user("Search")],
            tools: ["webSearch": webSearchTool],
            providerOptions: [
                "openai": [
                    "include": ["web_search_call.action.sources"]
                ]
            ]
        ))
        let explicitBody = try decodeJSONBody(try #require((await transport.requests())[1].body))
        #expect(explicitBody["include"] == ["web_search_call.action.sources"])
    }

    @Test func vertexDownloadsToolResultFilesWithoutCredentialsAndWithBounds() async throws {
        let png = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a])
        let transport = RecordingTransport(responses: [
            AIHTTPResponse(
                statusCode: 302,
                headers: ["location": "https://cdn.example.com/result.png"]
            ),
            AIHTTPResponse(
                statusCode: 200,
                headers: ["content-type": "application/octet-stream"],
                body: png
            ),
            jsonResponse("""
            {"candidates":[{"content":{"parts":[{"text":"ok"}]},"finishReason":"STOP"}]}
            """)
        ])
        let provider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
            apiKey: "vertex-secret",
            baseURL: "https://vertex.example.com",
            toolResultDownloads: GoogleVertexToolResultDownloadSettings(maxBytes: 99),
            headers: ["Authorization": "Bearer must-not-leak", "Cookie": "session=secret"],
            transport: transport
        ))
        let toolResult = AIToolResult(
            toolCallID: "call-1",
            toolName: "screenshot",
            result: .null,
            modelOutput: [
                "type": "content",
                "value": [[
                    "type": "file",
                    "mediaType": "image",
                    "data": [
                        "type": "url",
                        "url": "https://files.example.com/result"
                    ]
                ]]
            ]
        )
        _ = try await provider.languageModel("gemini-3-pro-preview").generate(LanguageModelRequest(
            messages: [.toolResult(toolResult)]
        ))

        let requests = await transport.requests()
        #expect(requests.count == 3)
        #expect(requests[0].method == "GET")
        #expect(requests[0].url.absoluteString == "https://files.example.com/result")
        #expect(requests[0].headers.isEmpty)
        #expect(requests[0].followRedirects == false)
        #expect(requests[0].maxResponseBytes == 99)
        #expect(requests[1].method == "GET")
        #expect(requests[1].url.absoluteString == "https://cdn.example.com/result.png")
        #expect(requests[1].headers.isEmpty)
        #expect(requests[1].followRedirects == false)
        #expect(requests[2].headers["x-goog-api-key"] == "vertex-secret")

        let body = try decodeJSONBody(try #require(requests[2].body))
        let inlineData = body["contents"]?[0]?["parts"]?[0]?["functionResponse"]?["parts"]?[0]?["inlineData"]
        #expect(inlineData?["mimeType"]?.stringValue == "image/png")
        #expect(inlineData?["data"]?.stringValue == png.base64EncodedString())
    }

    @Test func vertexLeavesUserURLsAloneAndUsesDefaultSevenMiBLimit() async throws {
        let directTransport = RecordingTransport(response: jsonResponse("""
        {"candidates":[{"content":{"parts":[{"text":"ok"}]},"finishReason":"STOP"}]}
        """))
        let directProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
            apiKey: "key",
            baseURL: "https://vertex.example.com",
            transport: directTransport
        ))
        _ = try await directProvider.languageModel("gemini-2.5-pro").generate(LanguageModelRequest(
            messages: [AIMessage(role: .user, content: [.imageURL("https://files.example.com/user.png")])]
        ))
        let directRequests = await directTransport.requests()
        #expect(directRequests.count == 1)
        let directBody = try decodeJSONBody(try #require(directRequests[0].body))
        #expect(directBody["contents"]?[0]?["parts"]?[0]?["fileData"]?["fileUri"]?.stringValue == "https://files.example.com/user.png")

        let downloadTransport = RecordingTransport(responses: [
            AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data([0x00])),
            jsonResponse("""
            {"candidates":[{"content":{"parts":[{"text":"ok"}]},"finishReason":"STOP"}]}
            """)
        ])
        let downloadProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
            apiKey: "key",
            baseURL: "https://vertex.example.com",
            transport: downloadTransport
        ))
        _ = try await downloadProvider.languageModel("gemini-3-pro-preview").generate(LanguageModelRequest(
            messages: [.toolResult(remoteToolResult(url: "https://files.example.com/default.png"))]
        ))
        #expect((await downloadTransport.requests()).first?.maxResponseBytes == 7 * 1024 * 1024)

        let oversizedTransport = RecordingTransport(response: AIHTTPResponse(
            statusCode: 200,
            body: Data([0x01, 0x02, 0x03])
        ))
        let oversizedProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
            apiKey: "key",
            baseURL: "https://vertex.example.com",
            toolResultDownloads: GoogleVertexToolResultDownloadSettings(maxBytes: 2),
            transport: oversizedTransport
        ))
        await #expect(throws: AIDownloadError.self) {
            _ = try await oversizedProvider.languageModel("gemini-3-pro-preview").generate(LanguageModelRequest(
                messages: [.toolResult(remoteToolResult(url: "https://files.example.com/oversized.png"))]
            ))
        }
    }

    @Test func googleAndVertexImagePromptBlocksAreTerminal() async throws {
        let blockedResponse = jsonResponse("""
        {"promptFeedback":{"blockReason":"SAFETY","safetyRatings":[]}}
        """)

        let googleTransport = RecordingTransport(response: blockedResponse)
        let googleProvider = try AIProviders.google(settings: ProviderSettings(
            apiKey: "key",
            transport: googleTransport
        ))
        let googleResult = try await googleProvider.imageModel("gemini-2.5-flash-image").generateImage(
            ImageGenerationRequest(prompt: "blocked")
        )
        #expect(googleResult.base64Images.isEmpty)
        #expect(googleResult.isRetryable == false)
        #expect(googleResult.providerMetadata["google"]?["promptFeedback"]?["blockReason"]?.stringValue == "SAFETY")

        let vertexTransport = RecordingTransport(response: blockedResponse)
        let vertexProvider = try AIProviders.googleVertex(settings: GoogleVertexProviderSettings(
            apiKey: "key",
            baseURL: "https://vertex.example.com",
            transport: vertexTransport
        ))
        let vertexResult = try await vertexProvider.imageModel("gemini-2.5-flash-image").generateImage(
            ImageGenerationRequest(prompt: "blocked")
        )
        #expect(vertexResult.base64Images.isEmpty)
        #expect(vertexResult.isRetryable == false)
    }
}

private func reasoningLifecycle(from model: any LanguageModel) async throws -> [String] {
    var lifecycle: [String] = []
    for try await part in model.stream(LanguageModelRequest(messages: [.user("Hi")])) {
        switch part {
        case let .reasoningStart(id, _):
            lifecycle.append("start:\(id)")
        case let .reasoningDeltaPart(id, delta, _):
            lifecycle.append("delta:\(id):\(delta)")
        case let .reasoningEnd(id, _):
            lifecycle.append("end:\(id)")
        default:
            break
        }
    }
    return lifecycle
}

private func remoteToolResult(url: String) -> AIToolResult {
    AIToolResult(
        toolCallID: "call-1",
        toolName: "screenshot",
        result: [
            "type": "content",
            "value": [[
                "type": "file",
                "mediaType": "image",
                "data": ["type": "url", "url": .string(url)]
            ]]
        ]
    )
}
