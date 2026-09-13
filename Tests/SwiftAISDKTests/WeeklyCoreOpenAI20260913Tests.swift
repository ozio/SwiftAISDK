import Foundation
import Testing
@testable import SwiftAISDK

@Suite("WeeklyCoreOpenAI20260913", .serialized)
struct WeeklyCoreOpenAI20260913Tests {
    @Test func providerOwnedBatchSupportsModalitiesLifecycleAndCompatibilityValidation() async throws {
        let provider = WeeklyCoreOpenAI20260913BatchProvider()
        let started = try await AI.startBatch(
            provider: provider,
            requests: [
                .text(TextBatchRequest(
                    id: "text-1",
                    modelID: "text-model",
                    request: LanguageModelRequest(messages: [.user("hello")])
                )),
                .image(ImageBatchRequest(
                    id: "image-1",
                    modelID: "image-model",
                    request: ImageGenerationRequest(prompt: "a fox")
                ))
            ],
            headers: ["x-test": "batch"],
            idempotencyKey: "stable-key"
        )

        #expect(started.batch.reference.version == 2)
        #expect(started.batch.reference.providerID == provider.providerID)
        #expect(await provider.startedModalities() == ["text", "image"])
        #expect(await provider.startHeaders()["idempotency-key"] == "stable-key")
        #expect(await provider.startHeaders()["user-agent"]?.contains("ai/7.0.99") == true)

        _ = try await AI.cancelBatch(provider: provider, batch: started.batch.reference)
        let listed = try await AI.listBatches(
            provider: provider,
            limit: 4,
            cursor: "after-1",
            retryPolicy: .none
        )
        #expect(await provider.cancelledIDs() == ["batch-1"])
        #expect(await provider.listOptions() == "4:after-1")
        #expect(listed.batches.map(\.reference.id) == ["batch-2"])
        #expect(listed.nextCursor == "after-2")

        let stream = try AI.getBatchResults(
            provider: provider,
            batch: started.batch.reference,
            retryPolicy: .none
        )
        var resultKinds: [String] = []
        for try await item in stream {
            switch item {
            case let .text(.succeeded(id, result)):
                resultKinds.append("text:\(id):\(result.text)")
            case let .image(.succeeded(id, result)):
                resultKinds.append("image:\(id):\(result.urls.first ?? "")")
            default:
                Issue.record("Unexpected provider-owned batch item: \(item)")
            }
        }
        #expect(resultKinds == ["text:text-1:done", "image:image-1:https://example.com/image.png"])

        let incompatible = WeeklyCoreOpenAI20260913BatchProvider()
        do {
            _ = try await AI.startBatch(provider: incompatible, requests: [
                .text(TextBatchRequest(
                    id: "one",
                    modelID: "text-model",
                    request: LanguageModelRequest(
                        messages: [.user("one")],
                        tools: ["lookup": ["type": "object", "properties": ["city": ["type": "string"]]]]
                    )
                )),
                .text(TextBatchRequest(
                    id: "two",
                    modelID: "text-model",
                    request: LanguageModelRequest(
                        messages: [.user("two")],
                        tools: ["lookup": ["type": "object", "properties": ["city": ["type": "number"]]]]
                    )
                ))
            ])
            Issue.record("Expected incompatible same-named batch tools to be rejected.")
        } catch let error as AIError {
            #expect(error.description.contains("must have the same definition in every batch request"))
        }
        #expect(await incompatible.startCallCount() == 0)
    }

    @Test func providerBatchServicesEnforceOpenAIGatewayAndXAIBoundaries() async throws {
        let openAITransport = RecordingTransport(responses: [
            jsonResponse(#"{"id":"batch-1","status":"cancelling"}"#),
            jsonResponse(#"{"data":[{"id":"batch-2","status":"completed"}],"has_more":true,"last_id":"batch-2"}"#)
        ])
        let openAI = try AIProviders.openAI(settings: ProviderSettings(apiKey: "key", transport: openAITransport))
        let openAIBatch = try openAI.experimentalBatch()
        #expect(openAIBatch.providerID == "openai.batch")
        #expect(isURLSupported(
            mediaType: "image/png",
            url: "https://example.com/image.png",
            supportedURLs: openAIBatch.supportedURLs
        ))
        #expect(!isURLSupported(
            mediaType: "text/plain",
            url: "https://example.com/prompt.txt",
            supportedURLs: openAIBatch.supportedURLs
        ))
        await #expect(throws: AIError.self) {
            _ = try await AI.cancelBatch(
                provider: openAIBatch,
                batch: AIBatchReference(id: "batch-1", providerID: "openai.responses.batch")
            )
        }
        await #expect(throws: AIError.self) {
            _ = try await openAIBatch.startBatch(AIBatchStartOptions(requests: [
                .image(ImageBatchRequest(id: "image", modelID: "gpt-image-2.5-flare", request: ImageGenerationRequest(prompt: "fox")))
            ]))
        }
        #expect(await openAITransport.requests().isEmpty)
        _ = try await openAIBatch.cancelBatch(AIBatchOperationOptions(batchID: "batch-1"))
        let openAIList = try await openAIBatch.listBatches(AIBatchListOptions(limit: 1, cursor: "before"))
        #expect(openAIList.batches.map(\.batchID) == ["batch-2"])
        #expect(openAIList.nextCursor == "batch-2")
        let openAIRequests = await openAITransport.requests()
        #expect(openAIRequests.map(\.method) == ["POST", "GET"])
        #expect(openAIRequests[0].url.path.hasSuffix("/batches/batch-1/cancel"))
        #expect(openAIRequests[1].url.query?.contains("limit=1") == true)
        #expect(openAIRequests[1].url.query?.contains("after=before") == true)

        let gatewayTransport = RecordingTransport(response: jsonResponse(#"{"batchId":"unused","status":"pending"}"#))
        let gateway = try AIProviders.gateway(settings: ProviderSettings(apiKey: "key", transport: gatewayTransport))
        let gatewayBatch = gateway.experimentalBatch()
        #expect(gatewayBatch.providerID == "gateway.batch")
        #expect(isURLSupported(
            mediaType: "application/octet-stream",
            url: "data:application/octet-stream;base64,AA==",
            supportedURLs: gatewayBatch.supportedURLs
        ))
        await #expect(throws: AIError.self) {
            _ = try await gatewayBatch.startBatch(AIBatchStartOptions(requests: [
                .image(ImageBatchRequest(id: "image", modelID: "image-model", request: ImageGenerationRequest(prompt: "fox")))
            ]))
        }
        #expect(await gatewayTransport.requests().isEmpty)
        _ = try await gatewayBatch.startBatch(AIBatchStartOptions(requests: [
            .text(TextBatchRequest(
                id: "text",
                modelID: "openai/gpt-5.6",
                request: LanguageModelRequest(
                    messages: [.user("use lookup")],
                    tools: ["lookup": ["type": "object", "properties": [:]]],
                    toolChoice: "required"
                )
            ))
        ]))
        let gatewayStartRequest = try #require(await gatewayTransport.requests().first)
        let gatewayStartBody = try decodeJSONBody(try #require(gatewayStartRequest.body))
        #expect(gatewayStartBody["requests"]?[0]?["options"]?["toolChoice"]?["type"]?.stringValue == "required")

        let xaiStartTransport = RecordingTransport(responses: [
            jsonResponse(#"{"id":"file-1"}"#),
            jsonResponse(#"{"batch_id":"batch-xai","state":{"num_requests":2,"num_pending":2,"num_success":0,"num_error":0,"num_cancelled":0}}"#)
        ])
        let xai = try AIProviders.xAI(settings: ProviderSettings(apiKey: "key", transport: xaiStartTransport))
        let xaiBatch = try xai.experimentalBatch()
        #expect(xaiBatch.providerID == "xai.batch")
        #expect(isURLSupported(
            mediaType: "text/plain",
            url: "https://example.com/prompt.txt",
            supportedURLs: xaiBatch.supportedURLs
        ))
        let xaiStart = try await xaiBatch.startBatch(AIBatchStartOptions(requests: [
            .text(TextBatchRequest(id: "text", modelID: "grok-4", request: LanguageModelRequest(messages: [.user("hello")]))),
            .image(ImageBatchRequest(id: "image", modelID: "grok-imagine-image", request: ImageGenerationRequest(prompt: "fox")))
        ]))
        #expect(xaiStart.batchID == "batch-xai")
        let uploadBody = String(data: try #require((await xaiStartTransport.requests()).first?.body), encoding: .utf8) ?? ""
        let normalizedUploadBody = uploadBody.replacingOccurrences(of: "\\/", with: "/")
        #expect(normalizedUploadBody.contains("/v1/responses"))
        #expect(normalizedUploadBody.contains("/v1/images/generations"))

        let xaiResultTransport = RecordingTransport(responses: [
            jsonResponse(#"{"batch_id":"batch-xai","state":{"num_requests":2,"num_pending":0,"num_success":2,"num_error":0,"num_cancelled":0}}"#),
            jsonResponse(#"{"results":[{"batch_request_id":"image-ok","batch_result":{"response":{"image_generation":{"data":[{"b64_json":"aW1hZ2U=","respect_moderation":true}]}}}},{"batch_request_id":"image-denied","batch_result":{"response":{"image_generation":{"data":[{"respect_moderation":false}]}}}}]}"#)
        ])
        let xaiResultProvider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "key", transport: xaiResultTransport))
        let xaiResults = try await xaiResultProvider.experimentalBatch().getBatchResults(AIBatchOperationOptions(batchID: "batch-xai"))
        var xaiKinds: [String] = []
        for try await item in xaiResults {
            switch item {
            case let .image(.succeeded(id, result)):
                xaiKinds.append("success:\(id):\(result.base64Images.count)")
                #expect(result.providerMetadata["xai"]?["images"]?[0]?["revisedPrompt"] == nil)
            case let .image(.failed(id, error, _)):
                xaiKinds.append("failure:\(id):\(error.message)")
            default:
                Issue.record("Expected xAI image batch item.")
            }
        }
        #expect(xaiKinds == [
            "success:image-ok:1",
            "failure:image-denied:Image generation was blocked due to a content policy violation."
        ])
    }

    @Test func routesLikeOpenAIIsNotEnoughToExposeProviderOwnedBatch() throws {
        let provider = try OpenAICompatibleProvider(
            providerID: "routes-like-but-not-openai",
            defaultBaseURL: "https://example.com/v1",
            authorization: .none,
            routesLikeOpenAI: true
        )
        _ = try provider.batchLanguageModel("model-1")
        #expect(throws: AIError.self) {
            _ = try provider.experimentalBatch()
        }
    }

    @Test func imageRetryabilityAccountsForEveryEmptyAttemptAndMediaSignaturesAreStrict() async throws {
        let retryingModel = WeeklyCoreOpenAI20260913ImageModel(results: [
            ImageGenerationResult(
                urls: [],
                rawValue: ["attempt": 1],
                warnings: [AIWarning(type: "other", message: "retry")],
                responseMetadata: AIResponseMetadata(id: "response-1"),
                isRetryable: true
            ),
            ImageGenerationResult(
                urls: ["https://example.com/final.png"],
                rawValue: ["attempt": 2],
                warnings: [AIWarning(type: "other", message: "success")],
                responseMetadata: AIResponseMetadata(id: "response-2"),
                isRetryable: false
            )
        ])
        let generated = try await AI.generateImage(
            model: retryingModel,
            request: ImageGenerationRequest(prompt: "fox"),
            retryPolicy: AIRetryPolicy(maxRetries: 1, initialDelayNanoseconds: 0)
        )
        #expect(await retryingModel.callCount() == 2)
        #expect(generated.urls == ["https://example.com/final.png"])
        #expect(generated.calls.map(\.responseMetadata.id) == ["response-1", "response-2"])
        #expect(generated.warnings.map(\.message) == ["retry", "success"])

        let terminalModel = WeeklyCoreOpenAI20260913ImageModel(results: [
            ImageGenerationResult(
                urls: [],
                rawValue: ["empty": true],
                responseMetadata: AIResponseMetadata(id: "terminal"),
                isRetryable: false
            )
        ])
        do {
            _ = try await AI.generateImage(
                model: terminalModel,
                request: ImageGenerationRequest(prompt: "blocked"),
                retryPolicy: AIRetryPolicy(maxRetries: 3, initialDelayNanoseconds: 0)
            )
            Issue.record("Expected a terminal empty image result.")
        } catch let error as AINoOutputError {
            #expect(error.kind == .image)
            #expect(error.responses.map(\.id) == ["terminal"])
            #expect(error.calls.count == 1)
        }
        #expect(await terminalModel.callCount() == 1)

        #expect(detectMediaType(data: Data("GIF87a".utf8)) == "image/gif")
        #expect(detectMediaType(data: Data("GIF89a".utf8)) == "image/gif")
        #expect(detectMediaType(data: Data("GIFxxx".utf8)) == nil)
        #expect(detectMediaType(data: Data([0x42, 0x4D, 0, 0, 0, 0, 0, 0, 0, 0])) == "image/bmp")
        #expect(detectMediaType(data: Data([0x42, 0x4D, 0, 0, 0, 0, 1, 0, 0, 0])) == nil)
    }

    @Test func rerankingIndexesAndToolOutputErrorPartsAreValidated() async throws {
        let model = MockRerankingModel(result: RerankingResult(
            results: [RerankedDocument(index: 2, score: 0.9)],
            rawValue: [:]
        ))
        await #expect(throws: AIError.self) {
            _ = try await AI.rerank(
                model: model,
                request: RerankingRequest(query: "q", documents: ["only"]),
                retryPolicy: .none
            )
        }

        let errorResult = AIToolResult(
            toolCallID: "call-1",
            toolName: "lookup",
            result: ["message": "failed"],
            isError: true,
            dynamic: true
        )
        let part = AIUIMessagePart.toolResult(errorResult)
        #expect(isToolOutputErrorUIPart(part))
        #expect(toolOutputErrorUIPart(part) == errorResult)
        #expect(!isToolOutputErrorUIPart(.toolResult(AIToolResult(
            toolCallID: "call-2",
            toolName: "lookup",
            result: ["ok": true]
        ))))
    }

    @Test func streamTextEnforcesToolChoiceIncludingPrepareStepOverrides() async throws {
        let simpleModel = MockLanguageModel(
            result: TextGenerationResult(text: "", rawValue: [:]),
            streamParts: [.textDelta("no tool"), .finish(reason: "stop", usage: nil)]
        )
        do {
            for try await _ in AI.streamText(
                model: simpleModel,
                request: LanguageModelRequest(messages: [.user("use a tool")], toolChoice: "required"),
                retryPolicy: .none
            ) {}
            Issue.record("Expected required streaming tool choice to fail.")
        } catch let error as AIToolChoiceViolationError {
            #expect(error.toolChoice["type"]?.stringValue == "required")
            #expect(error.finishReason == "stop")
        }

        let preparedModel = MockLanguageModel(
            result: TextGenerationResult(text: "", rawValue: [:]),
            streamParts: [.textDelta("wrong tool"), .finish(reason: "stop", usage: nil)]
        )
        let lookup = AITool(name: "lookup", parameters: ["type": "object", "properties": [:]]) { _ in
            ["ok": true]
        }
        do {
            for try await _ in AI.streamText(
                model: preparedModel,
                request: LanguageModelRequest(messages: [.user("use lookup")]),
                executableTools: [lookup],
                maxSteps: 1,
                prepareStep: { context in
                    var request = context.request
                    request.toolChoice = ["type": "tool", "toolName": "lookup"]
                    return AIPrepareStepResult(request: request)
                },
                retryPolicy: .none
            ) {}
            Issue.record("Expected prepareStep forced tool choice to fail.")
        } catch let error as AIToolChoiceViolationError {
            #expect(error.description.contains("required tool 'lookup'"))
        }
    }

    @Test func videoWebhookReceiverStartsBeforeRequestAndStartErrorsWinRaces() async throws {
        let startFailureState = WeeklyCoreOpenAI20260913VideoState(startShouldFail: true)
        let startFailureModel = WeeklyCoreOpenAI20260913VideoModel(state: startFailureState)
        do {
            _ = try await AI.generateVideo(
                model: startFailureModel,
                request: VideoGenerationRequest(prompt: "race"),
                retryPolicy: .none,
                poll: VideoGenerationPollOptions(timeoutMilliseconds: 1_000),
                webhook: {
                    VideoGenerationWebhookRegistration(url: "https://example.com/hook") { signal in
                        await startFailureState.markReceiverStarted()
                        _ = await signal?.waitUntilAborted()
                        await startFailureState.markReceiverAborted()
                        throw WeeklyCoreOpenAI20260913VideoError.webhook
                    }
                }
            )
            Issue.record("Expected start failure to win the webhook rejection race.")
        } catch let error as WeeklyCoreOpenAI20260913VideoError {
            #expect(error == .start)
        }
        #expect(await startFailureState.didStartReceiver())
        for _ in 0..<100 where !(await startFailureState.didAbortReceiver()) {
            await Task.yield()
        }
        #expect(await startFailureState.didAbortReceiver())

        let webhookFailureState = WeeklyCoreOpenAI20260913VideoState(startShouldFail: false)
        let webhookFailureModel = WeeklyCoreOpenAI20260913VideoModel(state: webhookFailureState)
        do {
            _ = try await AI.generateVideo(
                model: webhookFailureModel,
                request: VideoGenerationRequest(prompt: "rejection"),
                retryPolicy: .none,
                poll: VideoGenerationPollOptions(timeoutMilliseconds: 1_000),
                webhook: {
                    VideoGenerationWebhookRegistration(url: "https://example.com/hook") { _ in
                        await webhookFailureState.markReceiverStarted()
                        throw WeeklyCoreOpenAI20260913VideoError.webhook
                    }
                }
            )
            Issue.record("Expected webhook rejection after a successful start.")
        } catch let error as WeeklyCoreOpenAI20260913VideoError {
            #expect(error == .webhook)
        }
        #expect(await webhookFailureState.statusCallCount() == 0)
    }

    @Test func mcpDiscoveryRejectsPrivateInitialAndRedirectTargetsBeforeRequests() async throws {
        let directTransport = RecordingTransport(response: jsonResponse("{}"))
        await #expect(throws: MCPClientError.self) {
            _ = try await MCPOAuthDiscovery.discoverAuthorizationServerMetadata(
                authorizationServerURL: "http://169.254.169.254/oauth",
                transport: directTransport
            )
        }
        #expect(await directTransport.requests().isEmpty)

        let localDiscoveryTransport = RecordingTransport(response: jsonResponse(
            #"{"issuer":"http://localhost:4000","authorization_endpoint":"http://localhost:4000/authorize","token_endpoint":"http://localhost:4000/token","response_types_supported":["code"],"code_challenge_methods_supported":["S256"]}"#
        ))
        let localMetadata = try await MCPOAuthDiscovery.discoverAuthorizationServerMetadata(
            authorizationServerURL: "http://localhost:4000",
            transport: localDiscoveryTransport
        )
        #expect(localMetadata?.issuer == "http://localhost:4000")
        #expect(await localDiscoveryTransport.requests().count == 1)

        for protectedResource in [false, true] {
            let redirectTransport = RecordingTransport(response: AIHTTPResponse(
                statusCode: 302,
                headers: ["location": "http://127.0.0.1/private"]
            ))
            if protectedResource {
                await #expect(throws: MCPClientError.self) {
                    _ = try await MCPOAuthDiscovery.discoverProtectedResourceMetadata(
                        serverURL: "https://resource.example.com/mcp",
                        transport: redirectTransport
                    )
                }
            } else {
                await #expect(throws: MCPClientError.self) {
                    _ = try await MCPOAuthDiscovery.discoverAuthorizationServerMetadata(
                        authorizationServerURL: "https://auth.example.com",
                        transport: redirectTransport
                    )
                }
            }
            #expect(await redirectTransport.requests().count == 1)
            #expect(await redirectTransport.requests().allSatisfy { $0.followRedirects == false })
        }
    }

    @Test func mcpTrustsOnlyConfiguredLocalFlowsAndSafeCredentialOrigins() async throws {
        let remoteProvider = TestOAuthClientProvider(clientInformation: MCPOAuthClientInformation(clientID: "client"))
        let remoteTransport = RecordingTransport(response: jsonResponse(#"{"resource":"https://resource.example.com/mcp","authorization_servers":["http://localhost:4000"]}"#))
        await #expect(throws: MCPClientError.self) {
            _ = try await MCPOAuth.auth(
                provider: remoteProvider,
                serverURL: "https://resource.example.com/mcp",
                transport: remoteTransport
            )
        }
        #expect(await remoteTransport.requests().count == 1)

        let localProvider = TestOAuthClientProvider(
            clientInformation: MCPOAuthClientInformation(clientID: "client"),
            state: "state"
        )
        let localTransport = RecordingTransport(responses: [
            jsonResponse(#"{"resource":"http://localhost:3000/mcp","authorization_servers":["http://localhost:4000"]}"#),
            jsonResponse(#"{"issuer":"http://localhost:4000","authorization_endpoint":"http://localhost:4000/authorize","token_endpoint":"http://localhost:4000/token","response_types_supported":["code"],"code_challenge_methods_supported":["S256"]}"#)
        ])
        let localResult = try await MCPOAuth.auth(
            provider: localProvider,
            serverURL: "http://localhost:3000/mcp",
            transport: localTransport
        )
        #expect(localResult == .redirect)
        #expect(await localTransport.requests().map { $0.url.host } == ["localhost", "localhost"])
        #expect(await localTransport.requests().map { $0.url.port } == [3000, 4000])

        let blockedTransport = RecordingTransport(response: jsonResponse(#"{"access_token":"unsafe"}"#))
        let privateAuthorizationServer = try requireURL("http://169.254.169.254")
        await #expect(throws: MCPClientError.self) {
            _ = try await MCPOAuth.exchangeAuthorization(
                authorizationServerURL: privateAuthorizationServer,
                clientInformation: MCPOAuthClientInformation(clientID: "client"),
                authorizationCode: "code",
                codeVerifier: "verifier",
                redirectURI: try requireURL("http://localhost:3000/callback"),
                transport: blockedTransport
            )
        }
        await #expect(throws: MCPClientError.self) {
            _ = try await MCPOAuth.refreshAuthorization(
                authorizationServerURL: privateAuthorizationServer,
                clientInformation: MCPOAuthClientInformation(clientID: "client"),
                refreshToken: "refresh",
                transport: blockedTransport
            )
        }
        await #expect(throws: MCPClientError.self) {
            _ = try await MCPOAuth.registerClient(
                authorizationServerURL: privateAuthorizationServer,
                clientMetadata: MCPOAuthClientMetadata(redirectURIs: [try requireURL("http://localhost:3000/callback")]),
                transport: blockedTransport
            )
        }
        #expect(await blockedTransport.requests().isEmpty)

        let loopbackTransport = RecordingTransport(responses: [
            jsonResponse(#"{"access_token":"access","token_type":"Bearer"}"#),
            jsonResponse(#"{"access_token":"refreshed","token_type":"Bearer"}"#),
            jsonResponse(#"{"client_id":"registered","redirect_uris":["http://localhost:3000/callback"]}"#)
        ])
        let loopback = try requireURL("http://localhost:4000")
        _ = try await MCPOAuth.exchangeAuthorization(
            authorizationServerURL: loopback,
            clientInformation: MCPOAuthClientInformation(clientID: "client"),
            authorizationCode: "code",
            codeVerifier: "verifier",
            redirectURI: try requireURL("http://localhost:3000/callback"),
            transport: loopbackTransport
        )
        _ = try await MCPOAuth.refreshAuthorization(
            authorizationServerURL: loopback,
            clientInformation: MCPOAuthClientInformation(clientID: "client"),
            refreshToken: "refresh",
            transport: loopbackTransport
        )
        _ = try await MCPOAuth.registerClient(
            authorizationServerURL: loopback,
            clientMetadata: MCPOAuthClientMetadata(redirectURIs: [try requireURL("http://localhost:3000/callback")]),
            transport: loopbackTransport
        )
        #expect(await loopbackTransport.requests().count == 3)
        #expect(await loopbackTransport.requests().allSatisfy { !$0.followRedirects })
    }

    @Test func openAIPropertyNamesAsyncToolsAndProgrammaticDenialsMatchUpstream() throws {
        let normalized = try normalizeOpenAIJSONSchema([
            "type": "object",
            "properties": [
                "nested": [
                    "type": "object",
                    "propertyNames": ["type": "string"],
                    "additionalProperties": [
                        "type": "object",
                        "propertyNames": ["type": "string"]
                    ]
                ]
            ]
        ])
        #expect(normalized.schema["properties"]?["nested"]?["propertyNames"] == nil)
        #expect(normalized.schema["properties"]?["nested"]?["additionalProperties"]?["propertyNames"] == nil)
        #expect(normalized.warnings.count == 1)
        #expect(throws: AIError.self) {
            _ = try normalizeOpenAIJSONSchema(["type": "object", "propertyNames": ["type": "number"]])
        }

        let functionSchema: JSONValue = [
            "type": "object",
            "properties": [:],
            "providerOptions": ["openai": ["async": true]]
        ]
        let supported = try openAIResponsesTools(
            from: [
                "function": functionSchema,
                "custom": OpenAITools.customTool(name: "custom", async: true)
            ],
            supportsAsyncToolCalling: true
        )
        #expect(supported.tools.allSatisfy { $0["async"]?.boolValue == true })
        let unsupported = try openAIResponsesTools(
            from: ["function": functionSchema, "custom": OpenAITools.customTool(name: "custom", async: true)],
            supportsAsyncToolCalling: false
        )
        #expect(unsupported.tools.allSatisfy { $0["async"] == nil })
        #expect(unsupported.warnings.count == 2)

        let parsed = openAIResponsesToolCalls(from: [
            "output": [
                ["type": "function_call", "id": "item-f", "call_id": "call-f", "name": "function", "arguments": "{}", "async": true],
                ["type": "custom_tool_call", "id": "item-c", "call_id": "call-c", "name": "custom", "input": "raw", "async": false]
            ]
        ], providerID: "openai.responses")
        #expect(parsed[0].providerMetadata["openai"]?["async"]?.boolValue == true)
        #expect(openAIResponsesFunctionCallItem(parsed[0], toolNamespaces: [:])["async"]?.boolValue == true)
        #expect(parsed[1].providerMetadata["openai"]?["async"]?.boolValue == false)
        #expect(openAIResponsesCustomToolCallItem(parsed[1])["async"]?.boolValue == false)

        var processed: Set<String> = []
        var warnings: [AIWarning] = []
        #expect(throws: AIError.self) {
            _ = try openAIResponsesInputMessageJSON(
                AIMessage(role: .tool, content: [.toolResult(AIToolResult(
                    toolCallID: "program-call",
                    toolName: "programmatic_tool_calling",
                    result: ["type": "execution-denied", "reason": "no"]
                ))]),
                store: true,
                processedApprovalIDs: &processed,
                programmaticToolCallIDs: ["program-call"],
                warnings: &warnings
            )
        }
    }

    @Test func openAIFoundryWebSearchApplyPatchEmptyChoicesAndImage25AreCovered() async throws {
        var processed: Set<String> = []
        var warnings: [AIWarning] = []
        for message in [AIMessage.system("system"), .user("user"), .assistant("assistant")] {
            let items = try openAIResponsesInputMessageJSON(
                message,
                store: true,
                processedApprovalIDs: &processed,
                explicitMessageItemType: true,
                warnings: &warnings
            )
            #expect(items.first?["type"]?.stringValue == "message")
        }

        let webTools = ["search": OpenAITools.webSearch()]
        var providerControlled: [String: JSONValue] = ["include": ["caller.explicit"]]
        openAIResponsesApplyAutomaticOptions(
            to: &providerControlled,
            tools: webTools,
            isReasoningModel: false,
            supportsWebSearchSourcesInclude: false
        )
        #expect(providerControlled["include"]?.arrayValue?.compactMap(\.stringValue) == ["caller.explicit"])
        var automatic: [String: JSONValue] = [:]
        openAIResponsesApplyAutomaticOptions(
            to: &automatic,
            tools: webTools,
            isReasoningModel: false,
            supportsWebSearchSourcesInclude: true
        )
        #expect(automatic["include"]?.arrayValue?.compactMap(\.stringValue) == ["web_search_call.action.sources"])

        for modelID in [
            "gpt-image-2.5-flare",
            "gpt-image-2.5-flare-2026-09-08",
            "gpt-image-2.5-sunburst",
            "gpt-image-2.5-sunburst-2026-09-08"
        ] {
            #expect(openAIImageMaxImagesPerCall(modelID) == 10)
            let options = openAIImageOptions(
                providerOptions: ["openai": ["quality": "xhigh", "inputFidelity": "max"]],
                extraBody: [:]
            )
            #expect(options["quality"]?.stringValue == "xhigh")
            #expect(options["input_fidelity"]?.stringValue == "max")
        }

        let emptyTransport = RecordingTransport(response: jsonResponse(#"{"choices":[]}"#))
        let compatible = try AIProviders.openAICompatible(
            name: "compatible",
            baseURL: "https://example.com/v1",
            apiKey: "key",
            transport: emptyTransport
        )
        do {
            _ = try await compatible.chatModel("model").generate(LanguageModelRequest(messages: [.user("hi")]))
            Issue.record("Expected empty choices to fail structurally.")
        } catch let error as AIError {
            #expect(error.description.contains("Response did not contain any choices"))
        }

        let patchTransport = RecordingTransport(response: openAIResponsesApplyPatchFixtureResponse())
        let patchProvider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "key", transport: patchTransport))
        let patchResult = try await patchProvider.languageModel("gpt-5.1").generate(LanguageModelRequest(
            messages: [.user("patch")],
            tools: ["apply_patch": OpenAITools.applyPatch()]
        ))
        #expect(patchResult.finishReason == "tool-calls")
    }

    @Test func openResponsesImagesDefaultAndPreserveValidDetailAcrossUserAndToolContent() throws {
        let prepared = openResponsesInput(
            from: [AIMessage(role: .user, content: [
                .imageURL("https://example.com/auto.png"),
                .data(mimeType: "image/png", data: Data([1]), providerMetadata: ["openai": ["imageDetail": "low"]]),
                .file(mimeType: "image/jpeg", data: Data([2]), providerMetadata: ["openai": ["imageDetail": "invalid"]])
            ])],
            providerID: "openai.responses",
            providerOptionsName: "openai"
        )
        let content = try #require(prepared.input[0]?["content"]?.arrayValue)
        #expect(content.map { $0["detail"]?.stringValue } == ["auto", "low", "auto"])

        var warnings: [AIWarning] = []
        let output = openResponsesToolResultOutput(
            AIToolResult(
                toolCallID: "call",
                toolName: "image",
                result: .null,
                modelOutput: [
                    "type": "content",
                    "value": [[
                        "type": "image-data",
                        "data": "aW1hZ2U=",
                        "mediaType": "image/png",
                        "providerOptions": ["openai": ["imageDetail": "high"]]
                    ]]
                ]
            ),
            providerID: "openai.responses",
            providerOptionsName: "openai",
            warnings: &warnings
        )
        #expect(output[0]?["detail"]?.stringValue == "high")

        var openAIWarnings: [AIWarning] = []
        let openAIOutput = openResponsesToolResultOutput(
            AIToolResult(
                toolCallID: "call-openai",
                toolName: "image",
                result: .null,
                modelOutput: [
                    "type": "content",
                    "value": [[
                        "type": "image-data",
                        "data": "aW1hZ2U=",
                        "mediaType": "image/png"
                    ]]
                ]
            ),
            providerID: "openai.responses",
            warnings: &openAIWarnings
        )
        #expect(openAIOutput[0]?["detail"] == nil)
    }

    @Test func gatewayForwardsUnaryStreamWarningsAndImageRetryability() async throws {
        let unaryTransport = RecordingTransport(response: jsonResponse(#"{"content":[{"type":"text","text":"ok"}],"finishReason":"stop","warnings":[{"type":"unsupported","feature":"temperature","message":"ignored"}]}"#))
        let unaryProvider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "key", transport: unaryTransport))
        let unary = try await unaryProvider.languageModel("openai/gpt").generate(LanguageModelRequest(messages: [.user("hi")]))
        #expect(unary.warnings == [AIWarning(type: "unsupported", feature: "temperature", message: "ignored")])

        let streamTransport = RecordingTransport(response: sseResponse("""
        data: {"type":"stream-start","warnings":[{"type":"other","message":"routed"}]}

        data: {"type":"stream-start","warnings":[{"type":"other","message":"duplicate"}]}

        data: {"type":"finish","finishReason":"stop"}

        data: [DONE]
        """))
        let streamProvider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "key", transport: streamTransport))
        var streamWarnings: [AIWarning] = []
        let streamModel = try streamProvider.languageModel("openai/gpt")
        for try await part in streamModel.stream(LanguageModelRequest(messages: [.user("hi")])) {
            if case let .streamStart(warnings) = part { streamWarnings.append(contentsOf: warnings) }
        }
        #expect(streamWarnings == [AIWarning(type: "other", message: "routed")])

        let imageTransport = RecordingTransport(response: jsonResponse(#"{"images":[],"isRetryable":false}"#))
        let imageProvider = try AIProviders.gateway(settings: ProviderSettings(apiKey: "key", transport: imageTransport))
        let image = try await imageProvider.imageModel("image/model").generateImage(ImageGenerationRequest(prompt: "fox"))
        #expect(image.isRetryable == false)
    }
}

private actor WeeklyCoreOpenAI20260913BatchProvider: AIBatchProvider {
    nonisolated let providerID = "weekly.batch"
    private var modalities: [String] = []
    private var capturedHeaders: [String: String] = [:]
    private var starts = 0
    private var cancelled: [String] = []
    private var listed: String?

    func startBatch(_ options: AIBatchStartOptions<AIBatchRequest>) async throws -> AIBatchStartResult {
        starts += 1
        capturedHeaders = normalizeHeaders(options.headers)
        modalities = options.requests.map {
            switch $0 {
            case .text: "text"
            case .image: "image"
            }
        }
        return AIBatchStartResult(
            batchID: "batch-1",
            status: AIBatchStatus(status: .pending)
        )
    }

    func getBatchStatus(_ options: AIBatchOperationOptions) async throws -> AIBatchStatus {
        AIBatchStatus(status: .completed)
    }

    func getBatchResults(_ options: AIBatchOperationOptions) async throws -> AsyncThrowingStream<AIBatchV4ItemResult, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.text(.succeeded(
                id: "text-1",
                result: TextGenerationResult(text: "done", rawValue: [:])
            )))
            continuation.yield(.image(.succeeded(
                id: "image-1",
                result: ImageGenerationResult(urls: ["https://example.com/image.png"], rawValue: [:])
            )))
            continuation.finish()
        }
    }

    func cancelBatch(_ options: AIBatchOperationOptions) async throws -> AIBatchCancelResult {
        cancelled.append(options.batchID)
        return AIBatchCancelResult()
    }

    func listBatches(_ options: AIBatchListOptions) async throws -> AIBatchListResult {
        listed = "\(options.limit ?? -1):\(options.cursor ?? "")"
        return AIBatchListResult(
            batches: [AIBatchListItem(batchID: "batch-2", status: AIBatchStatus(status: .completed))],
            nextCursor: "after-2"
        )
    }

    func startedModalities() -> [String] { modalities }
    func startHeaders() -> [String: String] { capturedHeaders }
    func startCallCount() -> Int { starts }
    func cancelledIDs() -> [String] { cancelled }
    func listOptions() -> String? { listed }
}

private actor WeeklyCoreOpenAI20260913ImageModel: ImageModel {
    nonisolated let providerID = "weekly.image"
    nonisolated let modelID = "weekly-image-model"
    private var results: [ImageGenerationResult]
    private var calls = 0

    init(results: [ImageGenerationResult]) {
        self.results = results
    }

    func generateImage(_ request: ImageGenerationRequest) async throws -> ImageGenerationResult {
        calls += 1
        return results.count > 1 ? results.removeFirst() : results[0]
    }

    func callCount() -> Int { calls }
}

private enum WeeklyCoreOpenAI20260913VideoError: Error, Equatable {
    case start
    case webhook
}

private actor WeeklyCoreOpenAI20260913VideoState {
    nonisolated let startShouldFail: Bool
    private var receiverStarted = false
    private var receiverAborted = false
    private var statusCalls = 0

    init(startShouldFail: Bool) {
        self.startShouldFail = startShouldFail
    }

    func markReceiverStarted() { receiverStarted = true }
    func markReceiverAborted() { receiverAborted = true }
    func didStartReceiver() -> Bool { receiverStarted }
    func didAbortReceiver() -> Bool { receiverAborted }
    func recordStatus() { statusCalls += 1 }
    func statusCallCount() -> Int { statusCalls }
}

private struct WeeklyCoreOpenAI20260913VideoModel: AsyncVideoModel {
    let providerID = "weekly.video"
    let modelID = "weekly-video-model"
    let supportsUnaryVideoGeneration = false
    let supportsVideoGenerationWebhooks = true
    let state: WeeklyCoreOpenAI20260913VideoState

    func startVideoGeneration(_ request: VideoGenerationOperationStartRequest) async throws -> VideoGenerationOperationStartResult {
        for _ in 0..<100 where !(await state.didStartReceiver()) {
            await Task.yield()
        }
        if state.startShouldFail { throw WeeklyCoreOpenAI20260913VideoError.start }
        return VideoGenerationOperationStartResult(operation: ["id": "video-1"])
    }

    func videoGenerationStatus(_ request: VideoGenerationOperationStatusRequest) async throws -> VideoGenerationOperationStatusResult {
        await state.recordStatus()
        return .completed(VideoGenerationResult(urls: ["https://example.com/video.mp4"], rawValue: [:]))
    }
}
