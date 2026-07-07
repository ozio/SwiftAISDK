# Upstream Test Inventory

Generated inventory of test/spec files from the upstream Vercel AI SDK monorepo.
Use it as a review checklist before porting behavior into SwiftAISDK; do not copy tests mechanically when the Swift public surface differs.

## Snapshot

- Generated at: 2026-07-07T07:57:57.769Z
- Upstream ref: `main`
- Upstream commit: [`148babc531b5`](https://github.com/vercel/ai/tree/148babc531b55f85e61308639fa6e04ba0d27220)
- Commit line: `148babc531b55f85e61308639fa6e04ba0d27220 2026-07-06T14:44:46-07:00 fix(workflow): drop orphan UI chunks after negative startIndex reconnect (#15543)`
- Total upstream test/spec files: 667
- Package/example groups with tests: 69
- Groups tracked by SwiftAISDK ledger/core snapshot: 46
- Groups not tracked locally: 23

## Maintenance Plan

1. Refresh this inventory during the weekly upstream check after version discovery.
2. For each package being ported, inspect every upstream test file listed under that package before editing Swift code.
3. Translate behavior assertions into idiomatic Swift tests, preserving local API differences and existing transport/test helpers.
4. Record intentionally skipped upstream tests in the package sync report when they cover JS-only runtime, framework UI hooks, codemods, or product surfaces SwiftAISDK does not expose.
5. Keep the inventory commit SHA in reports so future diffs can distinguish test drift from implementation drift.

## Tracked Package Matrix

| Package group | Upstream package | Baseline | Kind | Upstream tests | Local evidence |
| --- | --- | --- | --- | ---: | --- |
| `ai` | `ai` | `7.0.16` | core | 124 | Docs/CoreV6Parity.md |
| `alibaba` | `@ai-sdk/alibaba` | `2.0.7` | provider | 7 | AIProviders.alibaba, AlibabaLanguageModel, AlibabaEmbeddingModel, AlibabaProviderTests.swift |
| `amazon-bedrock` | `@ai-sdk/amazon-bedrock` | `5.0.12` | provider | 17 | AIProviders.amazonBedrock, AIProviders.amazonBedrockAnthropic, AIProviders.bedrockMantle, AmazonBedrockModels.swift, AmazonBedrockTests.swift |
| `anthropic` | `@ai-sdk/anthropic` | `4.0.8` | provider | 11 | AIProviders.anthropic, AnthropicLanguageModel, AnthropicTools, AnthropicTests.swift, AnthropicStreamingAndClientsTests.swift |
| `anthropic-aws` | `@ai-sdk/anthropic-aws` | `2.0.0` | provider | 2 | AIProviders.anthropicAWS, AnthropicAWSProvider, AnthropicTests.swift |
| `assemblyai` | `@ai-sdk/assemblyai` | `3.0.5` | provider | 2 | AIProviders.assemblyAI, AssemblyAITranscriptionModel, AssemblyAIProviderTests.swift |
| `azure` | `@ai-sdk/azure` | `4.0.8` | provider | 1 | AIProviders.azure, AzureOpenAIProvider, AzureOpenAITools, AlibabaProdiaAzureQuiverTests.swift |
| `baseten` | `@ai-sdk/baseten` | `2.0.5` | provider | 1 | AIProviders.baseten, OpenAICompatibleProvider, BasetenProviderTests.swift |
| `black-forest-labs` | `@ai-sdk/black-forest-labs` | `2.0.5` | provider | 2 | AIProviders.blackForestLabs, BlackForestLabsImageModel, BlackForestLabsProviderTests.swift |
| `bytedance` | `@ai-sdk/bytedance` | `2.0.6` | provider | 1 | AIProviders.byteDance, ByteDanceVideoModel, ByteDanceProviderTests.swift |
| `cerebras` | `@ai-sdk/cerebras` | `3.0.5` | provider | 2 | AIProviders.cerebras, CerebrasLanguageModel, CerebrasProviderTests.swift |
| `cohere` | `@ai-sdk/cohere` | `4.0.5` | provider | 5 | AIProviders.cohere, CohereLanguageModel, CohereEmbeddingModel, CohereRerankingModel, CohereMistralVoyageTests.swift |
| `deepgram` | `@ai-sdk/deepgram` | `3.0.5` | provider | 3 | AIProviders.deepgram, DeepgramTranscriptionModel, DeepgramSpeechModel, DeepgramProviderTests.swift |
| `deepinfra` | `@ai-sdk/deepinfra` | `3.0.5` | provider | 3 | AIProviders.deepInfra, OpenAICompatibleProvider, DeepInfraProviderTests.swift |
| `deepseek` | `@ai-sdk/deepseek` | `3.0.5` | provider | 3 | AIProviders.deepSeek, DeepSeekLanguageModel, DeepSeekProviderTests.swift |
| `elevenlabs` | `@ai-sdk/elevenlabs` | `3.0.6` | provider | 3 | AIProviders.elevenLabs, ElevenLabsSpeechModel, ElevenLabsTranscriptionModel, ElevenLabsProviderTests.swift |
| `fal` | `@ai-sdk/fal` | `3.0.6` | provider | 6 | AIProviders.fal, FalMediaProviderTests.swift, FalProviderTests.swift |
| `fireworks` | `@ai-sdk/fireworks` | `3.0.6` | provider | 2 | AIProviders.fireworks, FireworksProviderTests.swift |
| `gateway` | `@ai-sdk/gateway` | `4.0.12` | provider | 19 | AIProviders.gateway, GatewayProvider, GatewayModels.swift, GatewayTests.swift |
| `gladia` | `@ai-sdk/gladia` | `3.0.5` | provider | 2 | AIProviders.gladia, GladiaTranscriptionModel, GladiaProviderTests.swift |
| `google` | `@ai-sdk/google` | `4.0.8` | provider | 24 | AIProviders.google, GoogleGenerativeAIProvider, GoogleGenerativeAI.swift, GoogleGenerativeMediaModels.swift, GoogleGenerativeAITests.swift, GoogleGenerativeAIMediaAndToolsTests.swift |
| `google-vertex` | `@ai-sdk/google-vertex` | `5.0.11` | provider | 18 | AIProviders.googleVertex, GoogleVertexProvider, GoogleVertexProvider.swift, GoogleVertexModels.swift, GoogleVertexTests.swift, GoogleVertexMediaAndMaaSTests.swift |
| `groq` | `@ai-sdk/groq` | `4.0.5` | provider | 6 | AIProviders.groq, GroqLanguageModel, GroqTranscriptionModel, GroqProviderTests.swift |
| `huggingface` | `@ai-sdk/huggingface` | `2.0.5` | provider | 2 | AIProviders.huggingFace, HuggingFaceProvider, HuggingFaceResponsesLanguageModel, HuggingFaceProviderTests.swift |
| `hume` | `@ai-sdk/hume` | `3.0.5` | provider | 2 | AIProviders.hume, HumeSpeechModel, HumeProviderTests.swift |
| `klingai` | `@ai-sdk/klingai` | `4.0.6` | provider | 3 | AIProviders.klingAI, KlingAIVideoModel, KlingAIProviderTests.swift |
| `lmnt` | `@ai-sdk/lmnt` | `3.0.5` | provider | 2 | AIProviders.lmnt, LMNTSpeechModel, LMNTProviderTests.swift |
| `luma` | `@ai-sdk/luma` | `3.0.6` | provider | 2 | AIProviders.luma, LumaImageModel, LumaProviderTests.swift |
| `mcp` | `@ai-sdk/mcp` | `2.0.7` | provider | 10 | MCPClient, MCPHTTPTransport, MCPStdioTransport, MCPApps, MCPClientTests.swift, MCPOAuthTests.swift, MCPStdioTransportTests.swift |
| `mistral` | `@ai-sdk/mistral` | `4.0.5` | provider | 5 | AIProviders.mistral, MistralLanguageModel, MistralEmbeddingModel, CohereMistralVoyageTests.swift |
| `moonshotai` | `@ai-sdk/moonshotai` | `3.0.7` | provider | 2 | AIProviders.moonshotAI, MoonshotLanguageModel, MoonshotAIProviderTests.swift |
| `open-responses` | `@ai-sdk/open-responses` | `2.0.5` | provider | 3 | AIProviders.openResponses, ResponsesRequestMode.openResponses, ResponsesEndpointTests.swift |
| `openai` | `@ai-sdk/openai` | `4.0.8` | provider | 19 | AIProviders.openAI, OpenAICompatible*Model, OpenAITools, OpenAI*Tests.swift, FileAndSkillClientTests.swift |
| `openai-compatible` | `@ai-sdk/openai-compatible` | `3.0.5` | provider | 8 | AIProviders.openAICompatible, OpenAICompatibleProvider, OpenAICompatibleTests.swift |
| `perplexity` | `@ai-sdk/perplexity` | `4.0.6` | provider | 2 | AIProviders.perplexity, PerplexityLanguageModel, ResponsesEndpointTests.swift |
| `prodia` | `@ai-sdk/prodia` | `2.0.6` | provider | 4 | AIProviders.prodia, ProdiaLanguageModel, ProdiaMediaModel, ProdiaProviderTests.swift |
| `provider` | `@ai-sdk/provider` | `4.0.2` | core | 1 | Docs/CoreV6Parity.md |
| `provider-utils` | `@ai-sdk/provider-utils` | `5.0.5` | core | 69 | Docs/CoreV6Parity.md |
| `quiverai` | `@ai-sdk/quiverai` | `2.0.5` | provider | 2 | AIProviders.quiverAI, QuiverAIImageModel, QuiverAIProviderTests.swift |
| `react` | `@ai-sdk/react` | `4.0.17` | core | 6 | Docs/CoreV6Parity.md |
| `replicate` | `@ai-sdk/replicate` | `3.0.6` | provider | 3 | AIProviders.replicate, ReplicateImageModel, ReplicateVideoModel, ReplicateProviderTests.swift |
| `revai` | `@ai-sdk/revai` | `3.0.5` | provider | 2 | AIProviders.revAI, RevAITranscriptionModel, RevAIProviderTests.swift |
| `togetherai` | `@ai-sdk/togetherai` | `3.0.6` | provider | 3 | AIProviders.togetherAI, TogetherAIImageModel, TogetherAIRerankingModel, TogetherAIProviderTests.swift |
| `vercel` | `@ai-sdk/vercel` | `3.0.5` | provider | 1 | AIProviders.vercel, VercelProvider, ProviderRegistryVercelTests.swift |
| `voyage` | `@ai-sdk/voyage` | `2.0.5` | provider | 3 | AIProviders.voyage, VoyageEmbeddingModel, VoyageRerankingModel, VoyageProviderOptionSchemaTests.swift |
| `xai` | `@ai-sdk/xai` | `4.0.7` | provider | 16 | AIProviders.xAI, XAIResponses.swift, XAITools, XAIImageModel, XAIVideoModel, XAIProviderTests.swift |

## Untracked Upstream Groups With Tests

These are visible in the upstream monorepo but are not currently tracked in the SwiftAISDK provider ledger or core snapshot. Most are framework adapters, codemods, harnesses, examples, or tooling packages.

| Group | Tests |
| --- | ---: |
| `angular` | 3 |
| `codemod` | 86 |
| `devtools` | 3 |
| `examples/ai-functions` | 24 |
| `harness` | 23 |
| `harness-claude-code` | 6 |
| `harness-codex` | 6 |
| `harness-deepagents` | 7 |
| `harness-opencode` | 7 |
| `harness-pi` | 13 |
| `langchain` | 4 |
| `llamaindex` | 1 |
| `otel` | 8 |
| `policy-opa` | 10 |
| `rsc` | 6 |
| `sandbox-just-bash` | 1 |
| `sandbox-vercel` | 2 |
| `svelte` | 3 |
| `test-server` | 1 |
| `tui` | 6 |
| `vue` | 4 |
| `workflow` | 8 |
| `workflow-harness` | 1 |

## Test Files By Group

### `ai (ai@7.0.16)`

- [`packages/ai/internal/index.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/internal/index.test.ts)
- [`packages/ai/src/agent/create-agent-ui-stream-response.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/agent/create-agent-ui-stream-response.test.ts)
- [`packages/ai/src/agent/tool-loop-agent.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/agent/tool-loop-agent.test.ts)
- [`packages/ai/src/embed/embed-many.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/embed/embed-many.test.ts)
- [`packages/ai/src/embed/embed.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/embed/embed.test.ts)
- [`packages/ai/src/generate-image/generate-image.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-image/generate-image.test.ts)
- [`packages/ai/src/generate-object/generate-object.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-object/generate-object.test.ts)
- [`packages/ai/src/generate-object/inject-json-instruction.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-object/inject-json-instruction.test.ts)
- [`packages/ai/src/generate-object/stream-object.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-object/stream-object.test.ts)
- [`packages/ai/src/generate-speech/generate-speech.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-speech/generate-speech.test.ts)
- [`packages/ai/src/generate-text/calculate-tokens-per-second.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/calculate-tokens-per-second.test.ts)
- [`packages/ai/src/generate-text/collect-tool-approvals.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/collect-tool-approvals.test.ts)
- [`packages/ai/src/generate-text/execute-tool-call.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/execute-tool-call.test.ts)
- [`packages/ai/src/generate-text/execute-tools-from-stream.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/execute-tools-from-stream.test.ts)
- [`packages/ai/src/generate-text/filter-active-tools.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/filter-active-tools.test.ts)
- [`packages/ai/src/generate-text/generate-text.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/generate-text.test.ts)
- [`packages/ai/src/generate-text/invoke-tool-callbacks-from-stream.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/invoke-tool-callbacks-from-stream.test.ts)
- [`packages/ai/src/generate-text/output.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/output.test.ts)
- [`packages/ai/src/generate-text/parse-tool-call.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/parse-tool-call.test.ts)
- [`packages/ai/src/generate-text/prune-messages.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/prune-messages.test.ts)
- [`packages/ai/src/generate-text/resolve-tool-approval.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/resolve-tool-approval.test.ts)
- [`packages/ai/src/generate-text/restricted-telemetry-dispatcher.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/restricted-telemetry-dispatcher.test.ts)
- [`packages/ai/src/generate-text/smooth-stream.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/smooth-stream.test.ts)
- [`packages/ai/src/generate-text/stop-condition.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/stop-condition.test.ts)
- [`packages/ai/src/generate-text/stream-language-model-call.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/stream-language-model-call.test.ts)
- [`packages/ai/src/generate-text/stream-text.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/stream-text.test.ts)
- [`packages/ai/src/generate-text/sum-token-counts.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/sum-token-counts.test.ts)
- [`packages/ai/src/generate-text/to-response-messages.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/to-response-messages.test.ts)
- [`packages/ai/src/generate-text/tool-approval-signature.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/tool-approval-signature.test.ts)
- [`packages/ai/src/generate-text/validate-tool-approvals.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/validate-tool-approvals.test.ts)
- [`packages/ai/src/generate-text/validate-tool-context.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-text/validate-tool-context.test.ts)
- [`packages/ai/src/generate-video/generate-video.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/generate-video/generate-video.test.ts)
- [`packages/ai/src/logger/log-warnings.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/logger/log-warnings.test.ts)
- [`packages/ai/src/middleware/add-tool-input-examples-middleware.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/middleware/add-tool-input-examples-middleware.test.ts)
- [`packages/ai/src/middleware/default-embedding-settings-middleware.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/middleware/default-embedding-settings-middleware.test.ts)
- [`packages/ai/src/middleware/default-settings-middleware.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/middleware/default-settings-middleware.test.ts)
- [`packages/ai/src/middleware/extract-json-middleware.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/middleware/extract-json-middleware.test.ts)
- [`packages/ai/src/middleware/extract-reasoning-middleware.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/middleware/extract-reasoning-middleware.test.ts)
- [`packages/ai/src/middleware/simulate-streaming-middleware.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/middleware/simulate-streaming-middleware.test.ts)
- [`packages/ai/src/middleware/wrap-embedding-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/middleware/wrap-embedding-model.test.ts)
- [`packages/ai/src/middleware/wrap-image-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/middleware/wrap-image-model.test.ts)
- [`packages/ai/src/middleware/wrap-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/middleware/wrap-language-model.test.ts)
- [`packages/ai/src/middleware/wrap-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/middleware/wrap-provider.test.ts)
- [`packages/ai/src/model/as-embedding-model-v3.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/model/as-embedding-model-v3.test.ts)
- [`packages/ai/src/model/as-embedding-model-v4.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/model/as-embedding-model-v4.test.ts)
- [`packages/ai/src/model/as-image-model-v3.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/model/as-image-model-v3.test.ts)
- [`packages/ai/src/model/as-image-model-v4.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/model/as-image-model-v4.test.ts)
- [`packages/ai/src/model/as-language-model-v3.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/model/as-language-model-v3.test.ts)
- [`packages/ai/src/model/as-language-model-v4.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/model/as-language-model-v4.test.ts)
- [`packages/ai/src/model/as-provider-v4.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/model/as-provider-v4.test.ts)
- [`packages/ai/src/model/as-reranking-model-v4.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/model/as-reranking-model-v4.test.ts)
- [`packages/ai/src/model/as-speech-model-v3.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/model/as-speech-model-v3.test.ts)
- [`packages/ai/src/model/as-speech-model-v4.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/model/as-speech-model-v4.test.ts)
- [`packages/ai/src/model/as-transcription-model-v3.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/model/as-transcription-model-v3.test.ts)
- [`packages/ai/src/model/as-transcription-model-v4.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/model/as-transcription-model-v4.test.ts)
- [`packages/ai/src/model/as-video-model-v4.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/model/as-video-model-v4.test.ts)
- [`packages/ai/src/model/resolve-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/model/resolve-model.test.ts)
- [`packages/ai/src/prompt/convert-to-language-model-prompt.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/prompt/convert-to-language-model-prompt.test.ts)
- [`packages/ai/src/prompt/convert-to-language-model-prompt.validation.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/prompt/convert-to-language-model-prompt.validation.test.ts)
- [`packages/ai/src/prompt/create-tool-model-output.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/prompt/create-tool-model-output.test.ts)
- [`packages/ai/src/prompt/file-part-data.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/prompt/file-part-data.test.ts)
- [`packages/ai/src/prompt/prepare-language-model-call-options.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/prompt/prepare-language-model-call-options.test.ts)
- [`packages/ai/src/prompt/prepare-tool-choice.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/prompt/prepare-tool-choice.test.ts)
- [`packages/ai/src/prompt/prepare-tools.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/prompt/prepare-tools.test.ts)
- [`packages/ai/src/prompt/standardize-prompt.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/prompt/standardize-prompt.test.ts)
- [`packages/ai/src/realtime/browser-realtime-transport.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/realtime/browser-realtime-transport.test.ts)
- [`packages/ai/src/realtime/realtime-event-reducer.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/realtime/realtime-event-reducer.test.ts)
- [`packages/ai/src/realtime/realtime-session.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/realtime/realtime-session.test.ts)
- [`packages/ai/src/registry/custom-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/registry/custom-provider.test.ts)
- [`packages/ai/src/registry/provider-registry.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/registry/provider-registry.test.ts)
- [`packages/ai/src/rerank/rerank.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/rerank/rerank.test.ts)
- [`packages/ai/src/telemetry/create-telemetry-dispatcher.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/telemetry/create-telemetry-dispatcher.test.ts)
- [`packages/ai/src/telemetry/telemetry-registry.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/telemetry/telemetry-registry.test.ts)
- [`packages/ai/src/telemetry/tracing-channel-publisher.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/telemetry/tracing-channel-publisher.test.ts)
- [`packages/ai/src/telemetry/tracing-channel.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/telemetry/tracing-channel.test.ts)
- [`packages/ai/src/test/mock-embedding-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/test/mock-embedding-model.test.ts)
- [`packages/ai/src/test/mock-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/test/mock-language-model.test.ts)
- [`packages/ai/src/text-stream/create-text-stream-response.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/text-stream/create-text-stream-response.test.ts)
- [`packages/ai/src/text-stream/pipe-text-stream-to-response.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/text-stream/pipe-text-stream-to-response.test.ts)
- [`packages/ai/src/text-stream/to-text-stream.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/text-stream/to-text-stream.test.ts)
- [`packages/ai/src/transcribe/stream-transcribe.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/transcribe/stream-transcribe.test.ts)
- [`packages/ai/src/transcribe/transcribe.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/transcribe/transcribe.test.ts)
- [`packages/ai/src/ui-message-stream/create-ui-message-stream-response.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/ui-message-stream/create-ui-message-stream-response.test.ts)
- [`packages/ai/src/ui-message-stream/create-ui-message-stream.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/ui-message-stream/create-ui-message-stream.test.ts)
- [`packages/ai/src/ui-message-stream/get-response-ui-message-id.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/ui-message-stream/get-response-ui-message-id.test.ts)
- [`packages/ai/src/ui-message-stream/handle-ui-message-stream-finish.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/ui-message-stream/handle-ui-message-stream-finish.test.ts)
- [`packages/ai/src/ui-message-stream/pipe-ui-message-stream-to-response.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/ui-message-stream/pipe-ui-message-stream-to-response.test.ts)
- [`packages/ai/src/ui-message-stream/read-ui-message-stream.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/ui-message-stream/read-ui-message-stream.test.ts)
- [`packages/ai/src/ui-message-stream/to-ui-message-chunk.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/ui-message-stream/to-ui-message-chunk.test.ts)
- [`packages/ai/src/ui-message-stream/to-ui-message-stream.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/ui-message-stream/to-ui-message-stream.test.ts)
- [`packages/ai/src/ui/chat.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/ui/chat.test.ts)
- [`packages/ai/src/ui/convert-to-model-messages.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/ui/convert-to-model-messages.test.ts)
- [`packages/ai/src/ui/direct-chat-transport.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/ui/direct-chat-transport.test.ts)
- [`packages/ai/src/ui/http-chat-transport.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/ui/http-chat-transport.test.ts)
- [`packages/ai/src/ui/last-assistant-message-is-complete-with-approval-responses.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/ui/last-assistant-message-is-complete-with-approval-responses.test.ts)
- [`packages/ai/src/ui/last-assistant-message-is-complete-with-tool-calls.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/ui/last-assistant-message-is-complete-with-tool-calls.test.ts)
- [`packages/ai/src/ui/process-text-stream.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/ui/process-text-stream.test.ts)
- [`packages/ai/src/ui/process-ui-message-stream.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/ui/process-ui-message-stream.test.ts)
- [`packages/ai/src/ui/transform-text-to-ui-message-stream.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/ui/transform-text-to-ui-message-stream.test.ts)
- [`packages/ai/src/ui/ui-messages.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/ui/ui-messages.test.ts)
- [`packages/ai/src/ui/validate-ui-messages.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/ui/validate-ui-messages.test.ts)
- [`packages/ai/src/upload-file/upload-file.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/upload-file/upload-file.test.ts)
- [`packages/ai/src/upload-skill/upload-skill.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/upload-skill/upload-skill.test.ts)
- [`packages/ai/src/util/async-iterable-stream.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/async-iterable-stream.test.ts)
- [`packages/ai/src/util/cosine-similarity.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/cosine-similarity.test.ts)
- [`packages/ai/src/util/create-id-map.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/create-id-map.test.ts)
- [`packages/ai/src/util/create-stitchable-stream.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/create-stitchable-stream.test.ts)
- [`packages/ai/src/util/download/download.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/download/download.test.ts)
- [`packages/ai/src/util/fix-json.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/fix-json.test.ts)
- [`packages/ai/src/util/get-potential-start-index.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/get-potential-start-index.test.ts)
- [`packages/ai/src/util/is-deep-equal-data.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/is-deep-equal-data.test.ts)
- [`packages/ai/src/util/merge-abort-signals.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/merge-abort-signals.test.ts)
- [`packages/ai/src/util/merge-callbacks.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/merge-callbacks.test.ts)
- [`packages/ai/src/util/merge-objects.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/merge-objects.test.ts)
- [`packages/ai/src/util/notify.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/notify.test.ts)
- [`packages/ai/src/util/parse-partial-json.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/parse-partial-json.test.ts)
- [`packages/ai/src/util/prepare-headers.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/prepare-headers.test.ts)
- [`packages/ai/src/util/prepare-retries.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/prepare-retries.test.ts)
- [`packages/ai/src/util/retry-with-exponential-backoff.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/retry-with-exponential-backoff.test.ts)
- [`packages/ai/src/util/serial-job-executor.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/serial-job-executor.test.ts)
- [`packages/ai/src/util/set-abort-timeout.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/set-abort-timeout.test.ts)
- [`packages/ai/src/util/simulate-readable-stream.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/simulate-readable-stream.test.ts)
- [`packages/ai/src/util/split-array.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/split-array.test.ts)
- [`packages/ai/src/util/write-to-server-response.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/ai/src/util/write-to-server-response.test.ts)

### `alibaba (@ai-sdk/alibaba@2.0.7)`

- [`packages/alibaba/src/alibaba-chat-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/alibaba/src/alibaba-chat-language-model.test.ts)
- [`packages/alibaba/src/alibaba-embedding-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/alibaba/src/alibaba-embedding-model.test.ts)
- [`packages/alibaba/src/alibaba-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/alibaba/src/alibaba-provider.test.ts)
- [`packages/alibaba/src/alibaba-video-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/alibaba/src/alibaba-video-model.test.ts)
- [`packages/alibaba/src/convert-alibaba-usage.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/alibaba/src/convert-alibaba-usage.test.ts)
- [`packages/alibaba/src/convert-to-alibaba-chat-messages.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/alibaba/src/convert-to-alibaba-chat-messages.test.ts)
- [`packages/alibaba/src/get-cache-control.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/alibaba/src/get-cache-control.test.ts)

### `amazon-bedrock (@ai-sdk/amazon-bedrock@5.0.12)`

- [`packages/amazon-bedrock/src/amazon-bedrock-api-types.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/amazon-bedrock/src/amazon-bedrock-api-types.test.ts)
- [`packages/amazon-bedrock/src/amazon-bedrock-chat-language-model-options.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/amazon-bedrock/src/amazon-bedrock-chat-language-model-options.test.ts)
- [`packages/amazon-bedrock/src/amazon-bedrock-chat-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/amazon-bedrock/src/amazon-bedrock-chat-language-model.test.ts)
- [`packages/amazon-bedrock/src/amazon-bedrock-embedding-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/amazon-bedrock/src/amazon-bedrock-embedding-model.test.ts)
- [`packages/amazon-bedrock/src/amazon-bedrock-event-stream-response-handler.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/amazon-bedrock/src/amazon-bedrock-event-stream-response-handler.test.ts)
- [`packages/amazon-bedrock/src/amazon-bedrock-image-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/amazon-bedrock/src/amazon-bedrock-image-model.test.ts)
- [`packages/amazon-bedrock/src/amazon-bedrock-prepare-tools.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/amazon-bedrock/src/amazon-bedrock-prepare-tools.test.ts)
- [`packages/amazon-bedrock/src/amazon-bedrock-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/amazon-bedrock/src/amazon-bedrock-provider.test.ts)
- [`packages/amazon-bedrock/src/amazon-bedrock-sigv4-fetch.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/amazon-bedrock/src/amazon-bedrock-sigv4-fetch.test.ts)
- [`packages/amazon-bedrock/src/anthropic/amazon-bedrock-anthropic-fetch.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/amazon-bedrock/src/anthropic/amazon-bedrock-anthropic-fetch.test.ts)
- [`packages/amazon-bedrock/src/anthropic/amazon-bedrock-anthropic-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/amazon-bedrock/src/anthropic/amazon-bedrock-anthropic-provider.test.ts)
- [`packages/amazon-bedrock/src/convert-amazon-bedrock-usage.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/amazon-bedrock/src/convert-amazon-bedrock-usage.test.ts)
- [`packages/amazon-bedrock/src/convert-to-amazon-bedrock-chat-messages.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/amazon-bedrock/src/convert-to-amazon-bedrock-chat-messages.test.ts)
- [`packages/amazon-bedrock/src/inject-fetch-headers.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/amazon-bedrock/src/inject-fetch-headers.test.ts)
- [`packages/amazon-bedrock/src/mantle/bedrock-mantle-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/amazon-bedrock/src/mantle/bedrock-mantle-provider.test.ts)
- [`packages/amazon-bedrock/src/normalize-tool-call-id.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/amazon-bedrock/src/normalize-tool-call-id.test.ts)
- [`packages/amazon-bedrock/src/reranking/amazon-bedrock-reranking-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/amazon-bedrock/src/reranking/amazon-bedrock-reranking-model.test.ts)

### `angular`

- [`packages/angular/src/lib/chat.ng.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/angular/src/lib/chat.ng.test.ts)
- [`packages/angular/src/lib/completion.ng.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/angular/src/lib/completion.ng.test.ts)
- [`packages/angular/src/lib/structured-object.ng.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/angular/src/lib/structured-object.ng.test.ts)

### `anthropic (@ai-sdk/anthropic@4.0.8)`

- [`packages/anthropic/src/anthropic-error.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/anthropic/src/anthropic-error.test.ts)
- [`packages/anthropic/src/anthropic-files.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/anthropic/src/anthropic-files.test.ts)
- [`packages/anthropic/src/anthropic-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/anthropic/src/anthropic-language-model.test.ts)
- [`packages/anthropic/src/anthropic-prepare-tools.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/anthropic/src/anthropic-prepare-tools.test.ts)
- [`packages/anthropic/src/anthropic-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/anthropic/src/anthropic-provider.test.ts)
- [`packages/anthropic/src/convert-anthropic-usage.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/anthropic/src/convert-anthropic-usage.test.ts)
- [`packages/anthropic/src/convert-to-anthropic-prompt.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/anthropic/src/convert-to-anthropic-prompt.test.ts)
- [`packages/anthropic/src/sanitize-json-schema.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/anthropic/src/sanitize-json-schema.test.ts)
- [`packages/anthropic/src/skills/anthropic-skills.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/anthropic/src/skills/anthropic-skills.test.ts)
- [`packages/anthropic/src/tool/bash_20241022.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/anthropic/src/tool/bash_20241022.test.ts)
- [`packages/anthropic/src/tool/bash_20250124.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/anthropic/src/tool/bash_20250124.test.ts)

### `anthropic-aws (@ai-sdk/anthropic-aws@2.0.0)`

- [`packages/anthropic-aws/src/anthropic-aws-fetch.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/anthropic-aws/src/anthropic-aws-fetch.test.ts)
- [`packages/anthropic-aws/src/anthropic-aws-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/anthropic-aws/src/anthropic-aws-provider.test.ts)

### `assemblyai (@ai-sdk/assemblyai@3.0.5)`

- [`packages/assemblyai/src/assemblyai-error.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/assemblyai/src/assemblyai-error.test.ts)
- [`packages/assemblyai/src/assemblyai-transcription-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/assemblyai/src/assemblyai-transcription-model.test.ts)

### `azure (@ai-sdk/azure@4.0.8)`

- [`packages/azure/src/azure-openai-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/azure/src/azure-openai-provider.test.ts)

### `baseten (@ai-sdk/baseten@2.0.5)`

- [`packages/baseten/src/baseten-provider.unit.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/baseten/src/baseten-provider.unit.test.ts)

### `black-forest-labs (@ai-sdk/black-forest-labs@2.0.5)`

- [`packages/black-forest-labs/src/black-forest-labs-image-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/black-forest-labs/src/black-forest-labs-image-model.test.ts)
- [`packages/black-forest-labs/src/black-forest-labs-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/black-forest-labs/src/black-forest-labs-provider.test.ts)

### `bytedance (@ai-sdk/bytedance@2.0.6)`

- [`packages/bytedance/src/bytedance-video-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/bytedance/src/bytedance-video-model.test.ts)

### `cerebras (@ai-sdk/cerebras@3.0.5)`

- [`packages/cerebras/src/cerebras-chat-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/cerebras/src/cerebras-chat-language-model.test.ts)
- [`packages/cerebras/src/cerebras-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/cerebras/src/cerebras-provider.test.ts)

### `codemod`

- [`packages/codemod/src/test/add-await-converttomodelmessages.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/add-await-converttomodelmessages.test.ts)
- [`packages/codemod/src/test/create-transformer.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/create-transformer.test.ts)
- [`packages/codemod/src/test/flatten-streamtext-file-properties.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/flatten-streamtext-file-properties.test.ts)
- [`packages/codemod/src/test/import-LanguageModelV2-from-provider-package.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/import-LanguageModelV2-from-provider-package.test.ts)
- [`packages/codemod/src/test/move-include-raw-chunks-to-include.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/move-include-raw-chunks-to-include.test.ts)
- [`packages/codemod/src/test/move-maxsteps-to-stopwhen.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/move-maxsteps-to-stopwhen.test.ts)
- [`packages/codemod/src/test/move-tool-invocations-to-parts.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/move-tool-invocations-to-parts.test.ts)
- [`packages/codemod/src/test/not-implemented.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/not-implemented.test.ts)
- [`packages/codemod/src/test/remove-ai-stream-methods-from-stream-text-result.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-ai-stream-methods-from-stream-text-result.test.ts)
- [`packages/codemod/src/test/remove-anthropic-facade.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-anthropic-facade.test.ts)
- [`packages/codemod/src/test/remove-await-fn.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-await-fn.test.ts)
- [`packages/codemod/src/test/remove-deprecated-provider-registry-exports.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-deprecated-provider-registry-exports.test.ts)
- [`packages/codemod/src/test/remove-experimental-active-tools.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-experimental-active-tools.test.ts)
- [`packages/codemod/src/test/remove-experimental-ai-fn-exports.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-experimental-ai-fn-exports.test.ts)
- [`packages/codemod/src/test/remove-experimental-custom-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-experimental-custom-provider.test.ts)
- [`packages/codemod/src/test/remove-experimental-generate-image.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-experimental-generate-image.test.ts)
- [`packages/codemod/src/test/remove-experimental-message-types.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-experimental-message-types.test.ts)
- [`packages/codemod/src/test/remove-experimental-prepare-step.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-experimental-prepare-step.test.ts)
- [`packages/codemod/src/test/remove-experimental-streamdata.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-experimental-streamdata.test.ts)
- [`packages/codemod/src/test/remove-experimental-tool.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-experimental-tool.test.ts)
- [`packages/codemod/src/test/remove-experimental-useassistant.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-experimental-useassistant.test.ts)
- [`packages/codemod/src/test/remove-google-facade.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-google-facade.test.ts)
- [`packages/codemod/src/test/remove-is-tool-or-dynamic-tool-uipart.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-is-tool-or-dynamic-tool-uipart.test.ts)
- [`packages/codemod/src/test/remove-isxxxerror.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-isxxxerror.test.ts)
- [`packages/codemod/src/test/remove-media-content-part-type.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-media-content-part-type.test.ts)
- [`packages/codemod/src/test/remove-metadata-with-headers.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-metadata-with-headers.test.ts)
- [`packages/codemod/src/test/remove-mistral-facade.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-mistral-facade.test.ts)
- [`packages/codemod/src/test/remove-openai-facade.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-openai-facade.test.ts)
- [`packages/codemod/src/test/remove-tool-call-options-type.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/remove-tool-call-options-type.test.ts)
- [`packages/codemod/src/test/rename-IDGenerator-to-IdGenerator.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-IDGenerator-to-IdGenerator.test.ts)
- [`packages/codemod/src/test/rename-addtoolresult-to-addtooloutput.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-addtoolresult-to-addtooloutput.test.ts)
- [`packages/codemod/src/test/rename-call-settings-type.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-call-settings-type.test.ts)
- [`packages/codemod/src/test/rename-converttocoremessages-to-converttomodelmessages-v6.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-converttocoremessages-to-converttomodelmessages-v6.test.ts)
- [`packages/codemod/src/test/rename-converttocoremessages-to-converttomodelmessages.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-converttocoremessages-to-converttomodelmessages.test.ts)
- [`packages/codemod/src/test/rename-core-message-to-model-message.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-core-message-to-model-message.test.ts)
- [`packages/codemod/src/test/rename-datastream-methods-to-uimessage.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-datastream-methods-to-uimessage.test.ts)
- [`packages/codemod/src/test/rename-experimental-context-to-context.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-experimental-context-to-context.test.ts)
- [`packages/codemod/src/test/rename-experimental-generate-speech.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-experimental-generate-speech.test.ts)
- [`packages/codemod/src/test/rename-experimental-include-to-include.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-experimental-include-to-include.test.ts)
- [`packages/codemod/src/test/rename-experimental-on-finish-to-on-end.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-experimental-on-finish-to-on-end.test.ts)
- [`packages/codemod/src/test/rename-experimental-on-start-to-on-start.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-experimental-on-start-to-on-start.test.ts)
- [`packages/codemod/src/test/rename-experimental-on-step-start-to-on-step-start.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-experimental-on-step-start-to-on-step-start.test.ts)
- [`packages/codemod/src/test/rename-experimental-on-tool-call-finish-to-on-tool-execution-end.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-experimental-on-tool-call-finish-to-on-tool-execution-end.test.ts)
- [`packages/codemod/src/test/rename-experimental-on-tool-call-start-to-on-tool-execution-start.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-experimental-on-tool-call-start-to-on-tool-execution-start.test.ts)
- [`packages/codemod/src/test/rename-experimental-telemetry-to-telemetry.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-experimental-telemetry-to-telemetry.test.ts)
- [`packages/codemod/src/test/rename-experimental-transcribe.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-experimental-transcribe.test.ts)
- [`packages/codemod/src/test/rename-format-stream-part.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-format-stream-part.test.ts)
- [`packages/codemod/src/test/rename-full-stream-to-stream.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-full-stream-to-stream.test.ts)
- [`packages/codemod/src/test/rename-google-generative-ai-to-google.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-google-generative-ai-to-google.test.ts)
- [`packages/codemod/src/test/rename-message-to-ui-message.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-message-to-ui-message.test.ts)
- [`packages/codemod/src/test/rename-mock-v2-to-v3.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-mock-v2-to-v3.test.ts)
- [`packages/codemod/src/test/rename-on-embed-finish-to-on-embed-end.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-on-embed-finish-to-on-embed-end.test.ts)
- [`packages/codemod/src/test/rename-on-finish-to-on-end.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-on-finish-to-on-end.test.ts)
- [`packages/codemod/src/test/rename-on-rerank-finish-to-on-rerank-end.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-on-rerank-finish-to-on-rerank-end.test.ts)
- [`packages/codemod/src/test/rename-on-step-finish-to-on-step-end.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-on-step-finish-to-on-step-end.test.ts)
- [`packages/codemod/src/test/rename-parse-stream-part.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-parse-stream-part.test.ts)
- [`packages/codemod/src/test/rename-pipedatastreamtoresponse-to-pipeuimessagestreamtoresponse.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-pipedatastreamtoresponse-to-pipeuimessagestreamtoresponse.test.ts)
- [`packages/codemod/src/test/rename-step-count-is.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-step-count-is.test.ts)
- [`packages/codemod/src/test/rename-system-to-instructions.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-system-to-instructions.test.ts)
- [`packages/codemod/src/test/rename-text-embedding-to-embedding.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-text-embedding-to-embedding.test.ts)
- [`packages/codemod/src/test/rename-todatastreamresponse-to-touimessagestreamresponse.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-todatastreamresponse-to-touimessagestreamresponse.test.ts)
- [`packages/codemod/src/test/rename-tool-call-options-to-tool-execution-options.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-tool-call-options-to-tool-execution-options.test.ts)
- [`packages/codemod/src/test/rename-tool-parameters-to-inputschema.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-tool-parameters-to-inputschema.test.ts)
- [`packages/codemod/src/test/rename-vertex-provider-metadata-key.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rename-vertex-provider-metadata-key.test.ts)
- [`packages/codemod/src/test/replace-anthropic-cache-creation-input-tokens.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/replace-anthropic-cache-creation-input-tokens.test.ts)
- [`packages/codemod/src/test/replace-baseurl.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/replace-baseurl.test.ts)
- [`packages/codemod/src/test/replace-cached-input-tokens.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/replace-cached-input-tokens.test.ts)
- [`packages/codemod/src/test/replace-continuation-steps.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/replace-continuation-steps.test.ts)
- [`packages/codemod/src/test/replace-datastream-to-uimessagestream.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/replace-datastream-to-uimessagestream.test.ts)
- [`packages/codemod/src/test/replace-experimental-output-with-output.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/replace-experimental-output-with-output.test.ts)
- [`packages/codemod/src/test/replace-fal-snake-case.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/replace-fal-snake-case.test.ts)
- [`packages/codemod/src/test/replace-image-message-part-with-file.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/replace-image-message-part-with-file.test.ts)
- [`packages/codemod/src/test/replace-langchain-toaistream.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/replace-langchain-toaistream.test.ts)
- [`packages/codemod/src/test/replace-nanoid.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/replace-nanoid.test.ts)
- [`packages/codemod/src/test/replace-reasoning-tokens.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/replace-reasoning-tokens.test.ts)
- [`packages/codemod/src/test/replace-roundtrips-with-maxsteps.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/replace-roundtrips-with-maxsteps.test.ts)
- [`packages/codemod/src/test/replace-textdelta-with-text.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/replace-textdelta-with-text.test.ts)
- [`packages/codemod/src/test/replace-token-usage-types.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/replace-token-usage-types.test.ts)
- [`packages/codemod/src/test/replace-usechat-api-with-transport.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/replace-usechat-api-with-transport.test.ts)
- [`packages/codemod/src/test/replace-usechat-input-with-state.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/replace-usechat-input-with-state.test.ts)
- [`packages/codemod/src/test/replace-zod-import-with-v3.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/replace-zod-import-with-v3.test.ts)
- [`packages/codemod/src/test/require-createIdGenerator-size-argument.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/require-createIdGenerator-size-argument.test.ts)
- [`packages/codemod/src/test/restructure-file-stream-parts.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/restructure-file-stream-parts.test.ts)
- [`packages/codemod/src/test/rewrite-framework-imports.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/rewrite-framework-imports.test.ts)
- [`packages/codemod/src/test/test-utils.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/test-utils.test.ts)
- [`packages/codemod/src/test/wrap-tomodeloutput-parameter.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/codemod/src/test/wrap-tomodeloutput-parameter.test.ts)

### `cohere (@ai-sdk/cohere@4.0.5)`

- [`packages/cohere/src/cohere-chat-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/cohere/src/cohere-chat-language-model.test.ts)
- [`packages/cohere/src/cohere-embedding-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/cohere/src/cohere-embedding-model.test.ts)
- [`packages/cohere/src/cohere-prepare-tools.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/cohere/src/cohere-prepare-tools.test.ts)
- [`packages/cohere/src/convert-to-cohere-chat-prompt.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/cohere/src/convert-to-cohere-chat-prompt.test.ts)
- [`packages/cohere/src/reranking/cohere-reranking-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/cohere/src/reranking/cohere-reranking-model.test.ts)

### `deepgram (@ai-sdk/deepgram@3.0.5)`

- [`packages/deepgram/src/deepgram-error.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/deepgram/src/deepgram-error.test.ts)
- [`packages/deepgram/src/deepgram-speech-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/deepgram/src/deepgram-speech-model.test.ts)
- [`packages/deepgram/src/deepgram-transcription-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/deepgram/src/deepgram-transcription-model.test.ts)

### `deepinfra (@ai-sdk/deepinfra@3.0.5)`

- [`packages/deepinfra/src/deepinfra-chat-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/deepinfra/src/deepinfra-chat-language-model.test.ts)
- [`packages/deepinfra/src/deepinfra-image-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/deepinfra/src/deepinfra-image-model.test.ts)
- [`packages/deepinfra/src/deepinfra-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/deepinfra/src/deepinfra-provider.test.ts)

### `deepseek (@ai-sdk/deepseek@3.0.5)`

- [`packages/deepseek/src/chat/convert-to-deepseek-chat-messages.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/deepseek/src/chat/convert-to-deepseek-chat-messages.test.ts)
- [`packages/deepseek/src/chat/deepseek-chat-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/deepseek/src/chat/deepseek-chat-language-model.test.ts)
- [`packages/deepseek/src/chat/deepseek-prepare-tools.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/deepseek/src/chat/deepseek-prepare-tools.test.ts)

### `devtools`

- [`packages/devtools/src/db.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/devtools/src/db.test.ts)
- [`packages/devtools/src/integration.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/devtools/src/integration.test.ts)
- [`packages/devtools/src/viewer/server.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/devtools/src/viewer/server.test.ts)

### `elevenlabs (@ai-sdk/elevenlabs@3.0.6)`

- [`packages/elevenlabs/src/elevenlabs-error.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/elevenlabs/src/elevenlabs-error.test.ts)
- [`packages/elevenlabs/src/elevenlabs-speech-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/elevenlabs/src/elevenlabs-speech-model.test.ts)
- [`packages/elevenlabs/src/elevenlabs-transcription-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/elevenlabs/src/elevenlabs-transcription-model.test.ts)

### `examples/ai-functions`

- [`examples/ai-functions/src/e2e/amazon-bedrock-anthropic.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/amazon-bedrock-anthropic.test.ts)
- [`examples/ai-functions/src/e2e/amazon-bedrock.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/amazon-bedrock.test.ts)
- [`examples/ai-functions/src/e2e/anthropic.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/anthropic.test.ts)
- [`examples/ai-functions/src/e2e/azure.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/azure.test.ts)
- [`examples/ai-functions/src/e2e/baseten.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/baseten.test.ts)
- [`examples/ai-functions/src/e2e/cerebras.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/cerebras.test.ts)
- [`examples/ai-functions/src/e2e/cohere.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/cohere.test.ts)
- [`examples/ai-functions/src/e2e/deepinfra.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/deepinfra.test.ts)
- [`examples/ai-functions/src/e2e/deepseek.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/deepseek.test.ts)
- [`examples/ai-functions/src/e2e/fireworks.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/fireworks.test.ts)
- [`examples/ai-functions/src/e2e/gateway.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/gateway.test.ts)
- [`examples/ai-functions/src/e2e/google-vertex-anthropic.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/google-vertex-anthropic.test.ts)
- [`examples/ai-functions/src/e2e/google-vertex.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/google-vertex.test.ts)
- [`examples/ai-functions/src/e2e/google.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/google.test.ts)
- [`examples/ai-functions/src/e2e/groq.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/groq.test.ts)
- [`examples/ai-functions/src/e2e/huggingface.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/huggingface.test.ts)
- [`examples/ai-functions/src/e2e/luma.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/luma.test.ts)
- [`examples/ai-functions/src/e2e/mistral.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/mistral.test.ts)
- [`examples/ai-functions/src/e2e/openai.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/openai.test.ts)
- [`examples/ai-functions/src/e2e/perplexity.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/perplexity.test.ts)
- [`examples/ai-functions/src/e2e/raw-chunks.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/raw-chunks.test.ts)
- [`examples/ai-functions/src/e2e/togetherai.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/togetherai.test.ts)
- [`examples/ai-functions/src/e2e/vercel.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/vercel.test.ts)
- [`examples/ai-functions/src/e2e/xai.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/examples/ai-functions/src/e2e/xai.test.ts)

### `fal (@ai-sdk/fal@3.0.6)`

- [`packages/fal/src/fal-error.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/fal/src/fal-error.test.ts)
- [`packages/fal/src/fal-image-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/fal/src/fal-image-model.test.ts)
- [`packages/fal/src/fal-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/fal/src/fal-provider.test.ts)
- [`packages/fal/src/fal-speech-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/fal/src/fal-speech-model.test.ts)
- [`packages/fal/src/fal-transcription-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/fal/src/fal-transcription-model.test.ts)
- [`packages/fal/src/fal-video-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/fal/src/fal-video-model.test.ts)

### `fireworks (@ai-sdk/fireworks@3.0.6)`

- [`packages/fireworks/src/fireworks-image-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/fireworks/src/fireworks-image-model.test.ts)
- [`packages/fireworks/src/fireworks-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/fireworks/src/fireworks-provider.test.ts)

### `gateway (@ai-sdk/gateway@4.0.12)`

- [`packages/gateway/src/errors/as-gateway-error.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gateway/src/errors/as-gateway-error.test.ts)
- [`packages/gateway/src/errors/create-gateway-error.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gateway/src/errors/create-gateway-error.test.ts)
- [`packages/gateway/src/errors/extract-api-call-response.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gateway/src/errors/extract-api-call-response.test.ts)
- [`packages/gateway/src/errors/gateway-error-types.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gateway/src/errors/gateway-error-types.test.ts)
- [`packages/gateway/src/errors/parse-auth-method.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gateway/src/errors/parse-auth-method.test.ts)
- [`packages/gateway/src/gateway-embedding-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gateway/src/gateway-embedding-model.test.ts)
- [`packages/gateway/src/gateway-fetch-metadata.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gateway/src/gateway-fetch-metadata.test.ts)
- [`packages/gateway/src/gateway-generation-info.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gateway/src/gateway-generation-info.test.ts)
- [`packages/gateway/src/gateway-image-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gateway/src/gateway-image-model.test.ts)
- [`packages/gateway/src/gateway-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gateway/src/gateway-language-model.test.ts)
- [`packages/gateway/src/gateway-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gateway/src/gateway-provider.test.ts)
- [`packages/gateway/src/gateway-realtime-auth.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gateway/src/gateway-realtime-auth.test.ts)
- [`packages/gateway/src/gateway-realtime-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gateway/src/gateway-realtime-model.test.ts)
- [`packages/gateway/src/gateway-reranking-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gateway/src/gateway-reranking-model.test.ts)
- [`packages/gateway/src/gateway-speech-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gateway/src/gateway-speech-model.test.ts)
- [`packages/gateway/src/gateway-spend-report.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gateway/src/gateway-spend-report.test.ts)
- [`packages/gateway/src/gateway-transcription-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gateway/src/gateway-transcription-model.test.ts)
- [`packages/gateway/src/gateway-video-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gateway/src/gateway-video-model.test.ts)
- [`packages/gateway/src/vercel-environment.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gateway/src/vercel-environment.test.ts)

### `gladia (@ai-sdk/gladia@3.0.5)`

- [`packages/gladia/src/gladia-error.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gladia/src/gladia-error.test.ts)
- [`packages/gladia/src/gladia-transcription-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/gladia/src/gladia-transcription-model.test.ts)

### `google (@ai-sdk/google@4.0.8)`

- [`packages/google/src/convert-json-schema-to-openapi-schema.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/convert-json-schema-to-openapi-schema.test.ts)
- [`packages/google/src/convert-to-google-messages.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/convert-to-google-messages.test.ts)
- [`packages/google/src/get-model-path.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/get-model-path.test.ts)
- [`packages/google/src/google-embedding-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/google-embedding-model.test.ts)
- [`packages/google/src/google-files.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/google-files.test.ts)
- [`packages/google/src/google-image-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/google-image-model.test.ts)
- [`packages/google/src/google-json-accumulator.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/google-json-accumulator.test.ts)
- [`packages/google/src/google-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/google-language-model.test.ts)
- [`packages/google/src/google-prepare-tools.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/google-prepare-tools.test.ts)
- [`packages/google/src/google-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/google-provider.test.ts)
- [`packages/google/src/google-speech-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/google-speech-model.test.ts)
- [`packages/google/src/google-supported-file-url.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/google-supported-file-url.test.ts)
- [`packages/google/src/google-video-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/google-video-model.test.ts)
- [`packages/google/src/interactions/build-google-interactions-stream-transform.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/interactions/build-google-interactions-stream-transform.test.ts)
- [`packages/google/src/interactions/convert-to-google-interactions-input.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/interactions/convert-to-google-interactions-input.test.ts)
- [`packages/google/src/interactions/extract-google-interactions-sources.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/interactions/extract-google-interactions-sources.test.ts)
- [`packages/google/src/interactions/google-interactions-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/interactions/google-interactions-language-model.test.ts)
- [`packages/google/src/interactions/map-google-interactions-finish-reason.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/interactions/map-google-interactions-finish-reason.test.ts)
- [`packages/google/src/interactions/parse-google-interactions-outputs.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/interactions/parse-google-interactions-outputs.test.ts)
- [`packages/google/src/interactions/poll-google-interactions.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/interactions/poll-google-interactions.test.ts)
- [`packages/google/src/interactions/prepare-google-interactions-tools.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/interactions/prepare-google-interactions-tools.test.ts)
- [`packages/google/src/interactions/stream-google-interactions.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/interactions/stream-google-interactions.test.ts)
- [`packages/google/src/realtime/google-realtime-event-mapper.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/realtime/google-realtime-event-mapper.test.ts)
- [`packages/google/src/realtime/google-realtime-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google/src/realtime/google-realtime-model.test.ts)

### `google-vertex (@ai-sdk/google-vertex@5.0.11)`

- [`packages/google-vertex/src/anthropic/edge/google-vertex-anthropic-provider-edge.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google-vertex/src/anthropic/edge/google-vertex-anthropic-provider-edge.test.ts)
- [`packages/google-vertex/src/anthropic/google-vertex-anthropic-provider-node.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google-vertex/src/anthropic/google-vertex-anthropic-provider-node.test.ts)
- [`packages/google-vertex/src/anthropic/google-vertex-anthropic-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google-vertex/src/anthropic/google-vertex-anthropic-provider.test.ts)
- [`packages/google-vertex/src/edge/google-vertex-auth-edge.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google-vertex/src/edge/google-vertex-auth-edge.test.ts)
- [`packages/google-vertex/src/edge/google-vertex-provider-edge.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google-vertex/src/edge/google-vertex-provider-edge.test.ts)
- [`packages/google-vertex/src/google-vertex-auth-google-auth-library.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google-vertex/src/google-vertex-auth-google-auth-library.test.ts)
- [`packages/google-vertex/src/google-vertex-embedding-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google-vertex/src/google-vertex-embedding-model.test.ts)
- [`packages/google-vertex/src/google-vertex-image-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google-vertex/src/google-vertex-image-model.test.ts)
- [`packages/google-vertex/src/google-vertex-provider-base.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google-vertex/src/google-vertex-provider-base.test.ts)
- [`packages/google-vertex/src/google-vertex-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google-vertex/src/google-vertex-provider.test.ts)
- [`packages/google-vertex/src/google-vertex-transcription-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google-vertex/src/google-vertex-transcription-model.test.ts)
- [`packages/google-vertex/src/google-vertex-video-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google-vertex/src/google-vertex-video-model.test.ts)
- [`packages/google-vertex/src/maas/edge/google-vertex-maas-provider-edge.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google-vertex/src/maas/edge/google-vertex-maas-provider-edge.test.ts)
- [`packages/google-vertex/src/maas/google-vertex-maas-provider-node.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google-vertex/src/maas/google-vertex-maas-provider-node.test.ts)
- [`packages/google-vertex/src/maas/google-vertex-maas-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google-vertex/src/maas/google-vertex-maas-provider.test.ts)
- [`packages/google-vertex/src/xai/edge/google-vertex-xai-provider-edge.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google-vertex/src/xai/edge/google-vertex-xai-provider-edge.test.ts)
- [`packages/google-vertex/src/xai/google-vertex-xai-provider-node.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google-vertex/src/xai/google-vertex-xai-provider-node.test.ts)
- [`packages/google-vertex/src/xai/google-vertex-xai-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/google-vertex/src/xai/google-vertex-xai-provider.test.ts)

### `groq (@ai-sdk/groq@4.0.5)`

- [`packages/groq/src/convert-groq-usage.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/groq/src/convert-groq-usage.test.ts)
- [`packages/groq/src/convert-to-groq-chat-messages.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/groq/src/convert-to-groq-chat-messages.test.ts)
- [`packages/groq/src/groq-chat-language-model-options.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/groq/src/groq-chat-language-model-options.test.ts)
- [`packages/groq/src/groq-chat-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/groq/src/groq-chat-language-model.test.ts)
- [`packages/groq/src/groq-prepare-tools.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/groq/src/groq-prepare-tools.test.ts)
- [`packages/groq/src/groq-transcription-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/groq/src/groq-transcription-model.test.ts)

### `harness`

- [`packages/harness/src/agent/harness-agent.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/agent/harness-agent.test.ts)
- [`packages/harness/src/agent/internal/bootstrap-recipe.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/agent/internal/bootstrap-recipe.test.ts)
- [`packages/harness/src/agent/internal/run-prompt.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/agent/internal/run-prompt.test.ts)
- [`packages/harness/src/agent/internal/sandbox-bootstrap.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/agent/internal/sandbox-bootstrap.test.ts)
- [`packages/harness/src/agent/internal/strip-work-dir.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/agent/internal/strip-work-dir.test.ts)
- [`packages/harness/src/agent/internal/to-harness-stream.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/agent/internal/to-harness-stream.test.ts)
- [`packages/harness/src/agent/internal/translate-stream-part.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/agent/internal/translate-stream-part.test.ts)
- [`packages/harness/src/agent/internal/validate-tool-call.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/agent/internal/validate-tool-call.test.ts)
- [`packages/harness/src/agent/observability/file-reporter.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/agent/observability/file-reporter.test.ts)
- [`packages/harness/src/agent/prepare-sandbox-for-harness.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/agent/prepare-sandbox-for-harness.test.ts)
- [`packages/harness/src/agent/prewarm.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/agent/prewarm.test.ts)
- [`packages/harness/src/agent/telemetry-integration.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/agent/telemetry-integration.test.ts)
- [`packages/harness/src/bridge/disk-replay.integration.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/bridge/disk-replay.integration.test.ts)
- [`packages/harness/src/bridge/index.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/bridge/index.test.ts)
- [`packages/harness/src/bridge/reconnect.integration.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/bridge/reconnect.integration.test.ts)
- [`packages/harness/src/errors/harness-capability-unsupported-error.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/errors/harness-capability-unsupported-error.test.ts)
- [`packages/harness/src/utils/ai-gateway-auth.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/utils/ai-gateway-auth.test.ts)
- [`packages/harness/src/utils/bridge-ready.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/utils/bridge-ready.test.ts)
- [`packages/harness/src/utils/classify-disk-log.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/utils/classify-disk-log.test.ts)
- [`packages/harness/src/utils/sandbox-channel.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/utils/sandbox-channel.test.ts)
- [`packages/harness/src/utils/sandbox-home-dir.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/utils/sandbox-home-dir.test.ts)
- [`packages/harness/src/utils/shell-quote.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/utils/shell-quote.test.ts)
- [`packages/harness/src/utils/write-skills.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness/src/utils/write-skills.test.ts)

### `harness-claude-code`

- [`packages/harness-claude-code/src/bridge/claude-skills-option.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-claude-code/src/bridge/claude-skills-option.test.ts)
- [`packages/harness-claude-code/src/bridge/compaction-latch.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-claude-code/src/bridge/compaction-latch.test.ts)
- [`packages/harness-claude-code/src/claude-code-auth.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-claude-code/src/claude-code-auth.test.ts)
- [`packages/harness-claude-code/src/claude-code-bridge-protocol.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-claude-code/src/claude-code-bridge-protocol.test.ts)
- [`packages/harness-claude-code/src/claude-code-harness.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-claude-code/src/claude-code-harness.test.ts)
- [`packages/harness-claude-code/src/claude-code-instructions.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-claude-code/src/claude-code-instructions.test.ts)

### `harness-codex`

- [`packages/harness-codex/src/bridge/cli-relay.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-codex/src/bridge/cli-relay.test.ts)
- [`packages/harness-codex/src/bridge/tool-relay-auth.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-codex/src/bridge/tool-relay-auth.test.ts)
- [`packages/harness-codex/src/codex-auth.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-codex/src/codex-auth.test.ts)
- [`packages/harness-codex/src/codex-bridge-protocol.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-codex/src/codex-bridge-protocol.test.ts)
- [`packages/harness-codex/src/codex-harness.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-codex/src/codex-harness.test.ts)
- [`packages/harness-codex/src/codex-instructions.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-codex/src/codex-instructions.test.ts)

### `harness-deepagents`

- [`packages/harness-deepagents/src/bridge/approvals.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-deepagents/src/bridge/approvals.test.ts)
- [`packages/harness-deepagents/src/bridge/json-schema-to-zod.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-deepagents/src/bridge/json-schema-to-zod.test.ts)
- [`packages/harness-deepagents/src/bridge/local-shell-backend.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-deepagents/src/bridge/local-shell-backend.test.ts)
- [`packages/harness-deepagents/src/bridge/tool-filtering.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-deepagents/src/bridge/tool-filtering.test.ts)
- [`packages/harness-deepagents/src/deepagents-auth.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-deepagents/src/deepagents-auth.test.ts)
- [`packages/harness-deepagents/src/deepagents-bridge-protocol.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-deepagents/src/deepagents-bridge-protocol.test.ts)
- [`packages/harness-deepagents/src/deepagents-harness.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-deepagents/src/deepagents-harness.test.ts)

### `harness-opencode`

- [`packages/harness-opencode/src/bridge/opencode-events.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-opencode/src/bridge/opencode-events.test.ts)
- [`packages/harness-opencode/src/bridge/opencode-path.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-opencode/src/bridge/opencode-path.test.ts)
- [`packages/harness-opencode/src/bridge/opencode-usage.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-opencode/src/bridge/opencode-usage.test.ts)
- [`packages/harness-opencode/src/bridge/tool-relay-auth.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-opencode/src/bridge/tool-relay-auth.test.ts)
- [`packages/harness-opencode/src/opencode-auth.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-opencode/src/opencode-auth.test.ts)
- [`packages/harness-opencode/src/opencode-bridge-protocol.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-opencode/src/opencode-bridge-protocol.test.ts)
- [`packages/harness-opencode/src/opencode-harness.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-opencode/src/opencode-harness.test.ts)

### `harness-pi`

- [`packages/harness-pi/src/pi-auth.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-pi/src/pi-auth.test.ts)
- [`packages/harness-pi/src/pi-events.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-pi/src/pi-events.test.ts)
- [`packages/harness-pi/src/pi-harness.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-pi/src/pi-harness.test.ts)
- [`packages/harness-pi/src/pi-model-resolver.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-pi/src/pi-model-resolver.test.ts)
- [`packages/harness-pi/src/pi-paths.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-pi/src/pi-paths.test.ts)
- [`packages/harness-pi/src/pi-remote-ops.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-pi/src/pi-remote-ops.test.ts)
- [`packages/harness-pi/src/pi-resume-state.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-pi/src/pi-resume-state.test.ts)
- [`packages/harness-pi/src/pi-session.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-pi/src/pi-session.test.ts)
- [`packages/harness-pi/src/pi-skills.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-pi/src/pi-skills.test.ts)
- [`packages/harness-pi/src/pi-translate.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-pi/src/pi-translate.test.ts)
- [`packages/harness-pi/src/pi-utils.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-pi/src/pi-utils.test.ts)
- [`packages/harness-pi/src/pi-workspace-mirror.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-pi/src/pi-workspace-mirror.test.ts)
- [`packages/harness-pi/src/pi-workspace-vfs.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/harness-pi/src/pi-workspace-vfs.test.ts)

### `huggingface (@ai-sdk/huggingface@2.0.5)`

- [`packages/huggingface/src/huggingface-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/huggingface/src/huggingface-provider.test.ts)
- [`packages/huggingface/src/responses/huggingface-responses-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/huggingface/src/responses/huggingface-responses-language-model.test.ts)

### `hume (@ai-sdk/hume@3.0.5)`

- [`packages/hume/src/hume-error.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/hume/src/hume-error.test.ts)
- [`packages/hume/src/hume-speech-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/hume/src/hume-speech-model.test.ts)

### `klingai (@ai-sdk/klingai@4.0.6)`

- [`packages/klingai/src/klingai-auth.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/klingai/src/klingai-auth.test.ts)
- [`packages/klingai/src/klingai-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/klingai/src/klingai-provider.test.ts)
- [`packages/klingai/src/klingai-video-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/klingai/src/klingai-video-model.test.ts)

### `langchain`

- [`packages/langchain/src/adapter.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/langchain/src/adapter.test.ts)
- [`packages/langchain/src/stream-callbacks.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/langchain/src/stream-callbacks.test.ts)
- [`packages/langchain/src/transport.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/langchain/src/transport.test.ts)
- [`packages/langchain/src/utils.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/langchain/src/utils.test.ts)

### `llamaindex`

- [`packages/llamaindex/src/llamaindex-adapter.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/llamaindex/src/llamaindex-adapter.test.ts)

### `lmnt (@ai-sdk/lmnt@3.0.5)`

- [`packages/lmnt/src/lmnt-error.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/lmnt/src/lmnt-error.test.ts)
- [`packages/lmnt/src/lmnt-speech-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/lmnt/src/lmnt-speech-model.test.ts)

### `luma (@ai-sdk/luma@3.0.6)`

- [`packages/luma/src/luma-image-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/luma/src/luma-image-model.test.ts)
- [`packages/luma/src/luma-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/luma/src/luma-provider.test.ts)

### `mcp (@ai-sdk/mcp@2.0.7)`

- [`packages/mcp/src/tool/json-rpc-message.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/mcp/src/tool/json-rpc-message.test.ts)
- [`packages/mcp/src/tool/mcp-apps.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/mcp/src/tool/mcp-apps.test.ts)
- [`packages/mcp/src/tool/mcp-client.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/mcp/src/tool/mcp-client.test.ts)
- [`packages/mcp/src/tool/mcp-http-transport.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/mcp/src/tool/mcp-http-transport.test.ts)
- [`packages/mcp/src/tool/mcp-sse-transport.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/mcp/src/tool/mcp-sse-transport.test.ts)
- [`packages/mcp/src/tool/mcp-stdio/create-child-process.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/mcp/src/tool/mcp-stdio/create-child-process.test.ts)
- [`packages/mcp/src/tool/mcp-stdio/get-environment.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/mcp/src/tool/mcp-stdio/get-environment.test.ts)
- [`packages/mcp/src/tool/mcp-stdio/mcp-stdio-transport.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/mcp/src/tool/mcp-stdio/mcp-stdio-transport.test.ts)
- [`packages/mcp/src/tool/oauth.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/mcp/src/tool/oauth.test.ts)
- [`packages/mcp/src/util/oauth.util.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/mcp/src/util/oauth.util.test.ts)

### `mistral (@ai-sdk/mistral@4.0.5)`

- [`packages/mistral/src/convert-mistral-usage.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/mistral/src/convert-mistral-usage.test.ts)
- [`packages/mistral/src/convert-to-mistral-chat-messages.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/mistral/src/convert-to-mistral-chat-messages.test.ts)
- [`packages/mistral/src/mistral-chat-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/mistral/src/mistral-chat-language-model.test.ts)
- [`packages/mistral/src/mistral-embedding-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/mistral/src/mistral-embedding-model.test.ts)
- [`packages/mistral/src/mistral-prepare-tools.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/mistral/src/mistral-prepare-tools.test.ts)

### `moonshotai (@ai-sdk/moonshotai@3.0.7)`

- [`packages/moonshotai/src/convert-moonshotai-chat-usage.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/moonshotai/src/convert-moonshotai-chat-usage.test.ts)
- [`packages/moonshotai/src/moonshotai-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/moonshotai/src/moonshotai-provider.test.ts)

### `open-responses (@ai-sdk/open-responses@2.0.5)`

- [`packages/open-responses/src/responses/convert-to-open-responses-input.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/open-responses/src/responses/convert-to-open-responses-input.test.ts)
- [`packages/open-responses/src/responses/map-open-responses-finish-reason.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/open-responses/src/responses/map-open-responses-finish-reason.test.ts)
- [`packages/open-responses/src/responses/open-responses-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/open-responses/src/responses/open-responses-language-model.test.ts)

### `openai (@ai-sdk/openai@4.0.8)`

- [`packages/openai/src/chat/convert-to-openai-chat-messages.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai/src/chat/convert-to-openai-chat-messages.test.ts)
- [`packages/openai/src/chat/openai-chat-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai/src/chat/openai-chat-language-model.test.ts)
- [`packages/openai/src/chat/openai-chat-prepare-tools.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai/src/chat/openai-chat-prepare-tools.test.ts)
- [`packages/openai/src/completion/openai-completion-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai/src/completion/openai-completion-language-model.test.ts)
- [`packages/openai/src/embedding/openai-embedding-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai/src/embedding/openai-embedding-model.test.ts)
- [`packages/openai/src/files/openai-files.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai/src/files/openai-files.test.ts)
- [`packages/openai/src/image/openai-image-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai/src/image/openai-image-model.test.ts)
- [`packages/openai/src/openai-error.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai/src/openai-error.test.ts)
- [`packages/openai/src/openai-language-model-capabilities.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai/src/openai-language-model-capabilities.test.ts)
- [`packages/openai/src/openai-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai/src/openai-provider.test.ts)
- [`packages/openai/src/realtime/openai-realtime-event-mapper.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai/src/realtime/openai-realtime-event-mapper.test.ts)
- [`packages/openai/src/realtime/openai-realtime-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai/src/realtime/openai-realtime-model.test.ts)
- [`packages/openai/src/responses/convert-to-openai-responses-input.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai/src/responses/convert-to-openai-responses-input.test.ts)
- [`packages/openai/src/responses/openai-responses-api.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai/src/responses/openai-responses-api.test.ts)
- [`packages/openai/src/responses/openai-responses-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai/src/responses/openai-responses-language-model.test.ts)
- [`packages/openai/src/responses/openai-responses-prepare-tools.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai/src/responses/openai-responses-prepare-tools.test.ts)
- [`packages/openai/src/skills/openai-skills.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai/src/skills/openai-skills.test.ts)
- [`packages/openai/src/speech/openai-speech-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai/src/speech/openai-speech-model.test.ts)
- [`packages/openai/src/transcription/openai-transcription-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai/src/transcription/openai-transcription-model.test.ts)

### `openai-compatible (@ai-sdk/openai-compatible@3.0.5)`

- [`packages/openai-compatible/src/chat/convert-to-openai-compatible-chat-messages.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai-compatible/src/chat/convert-to-openai-compatible-chat-messages.test.ts)
- [`packages/openai-compatible/src/chat/openai-compatible-chat-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai-compatible/src/chat/openai-compatible-chat-language-model.test.ts)
- [`packages/openai-compatible/src/chat/openai-compatible-prepare-tools.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai-compatible/src/chat/openai-compatible-prepare-tools.test.ts)
- [`packages/openai-compatible/src/completion/openai-compatible-completion-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai-compatible/src/completion/openai-compatible-completion-language-model.test.ts)
- [`packages/openai-compatible/src/embedding/openai-compatible-embedding-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai-compatible/src/embedding/openai-compatible-embedding-model.test.ts)
- [`packages/openai-compatible/src/image/openai-compatible-image-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai-compatible/src/image/openai-compatible-image-model.test.ts)
- [`packages/openai-compatible/src/openai-compatible-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai-compatible/src/openai-compatible-provider.test.ts)
- [`packages/openai-compatible/src/utils/to-camel-case.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/openai-compatible/src/utils/to-camel-case.test.ts)

### `otel`

- [`packages/otel/src/gen-ai-format-messages.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/otel/src/gen-ai-format-messages.test.ts)
- [`packages/otel/src/legacy-open-telemetry.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/otel/src/legacy-open-telemetry.test.ts)
- [`packages/otel/src/open-telemetry.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/otel/src/open-telemetry.test.ts)
- [`packages/otel/src/record-span.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/otel/src/record-span.test.ts)
- [`packages/otel/src/sanitize-attribute-value.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/otel/src/sanitize-attribute-value.test.ts)
- [`packages/otel/src/select-attributes.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/otel/src/select-attributes.test.ts)
- [`packages/otel/src/select-telemetry-attributes.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/otel/src/select-telemetry-attributes.test.ts)
- [`packages/otel/src/stringify-for-telemetry.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/otel/src/stringify-for-telemetry.test.ts)

### `perplexity (@ai-sdk/perplexity@4.0.6)`

- [`packages/perplexity/src/convert-to-perplexity-messages.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/perplexity/src/convert-to-perplexity-messages.test.ts)
- [`packages/perplexity/src/perplexity-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/perplexity/src/perplexity-language-model.test.ts)

### `policy-opa`

- [`packages/policy-opa/examples/git-in-bash/parse-git-invocation.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/policy-opa/examples/git-in-bash/parse-git-invocation.test.ts)
- [`packages/policy-opa/src/opa/http-policy-client.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/policy-opa/src/opa/http-policy-client.test.ts)
- [`packages/policy-opa/src/opa/normalize-opa-decision.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/policy-opa/src/opa/normalize-opa-decision.test.ts)
- [`packages/policy-opa/src/opa/opa-capability-middleware.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/policy-opa/src/opa/opa-capability-middleware.test.ts)
- [`packages/policy-opa/src/opa/opa-policy.integration.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/policy-opa/src/opa/opa-policy.integration.test.ts)
- [`packages/policy-opa/src/opa/opa-policy.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/policy-opa/src/opa/opa-policy.test.ts)
- [`packages/policy-opa/src/opa/wasm-policy-client.evaluate.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/policy-opa/src/opa/wasm-policy-client.evaluate.test.ts)
- [`packages/policy-opa/src/opa/wasm-policy-client.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/policy-opa/src/opa/wasm-policy-client.test.ts)
- [`packages/policy-opa/src/shadow.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/policy-opa/src/shadow.test.ts)
- [`packages/policy-opa/src/wrap-mcp-tools.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/policy-opa/src/wrap-mcp-tools.test.ts)

### `prodia (@ai-sdk/prodia@2.0.6)`

- [`packages/prodia/src/prodia-image-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/prodia/src/prodia-image-model.test.ts)
- [`packages/prodia/src/prodia-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/prodia/src/prodia-language-model.test.ts)
- [`packages/prodia/src/prodia-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/prodia/src/prodia-provider.test.ts)
- [`packages/prodia/src/prodia-video-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/prodia/src/prodia-video-model.test.ts)

### `provider (@ai-sdk/provider@4.0.2)`

- [`packages/provider/src/errors/get-error-message.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider/src/errors/get-error-message.test.ts)

### `provider-utils (@ai-sdk/provider-utils@5.0.5)`

- [`packages/provider-utils/src/add-additional-properties-to-json-schema.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/add-additional-properties-to-json-schema.test.ts)
- [`packages/provider-utils/src/as-array.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/as-array.test.ts)
- [`packages/provider-utils/src/cancel-response-body.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/cancel-response-body.test.ts)
- [`packages/provider-utils/src/convert-async-iterator-to-readable-stream.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/convert-async-iterator-to-readable-stream.test.ts)
- [`packages/provider-utils/src/convert-image-model-file-to-data-uri.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/convert-image-model-file-to-data-uri.test.ts)
- [`packages/provider-utils/src/convert-to-form-data.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/convert-to-form-data.test.ts)
- [`packages/provider-utils/src/create-tool-name-mapping.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/create-tool-name-mapping.test.ts)
- [`packages/provider-utils/src/delay.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/delay.test.ts)
- [`packages/provider-utils/src/delayed-promise.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/delayed-promise.test.ts)
- [`packages/provider-utils/src/detect-media-type.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/detect-media-type.test.ts)
- [`packages/provider-utils/src/download-blob.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/download-blob.test.ts)
- [`packages/provider-utils/src/extract-lines.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/extract-lines.test.ts)
- [`packages/provider-utils/src/fetch-with-validated-redirects.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/fetch-with-validated-redirects.test.ts)
- [`packages/provider-utils/src/filter-nullable.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/filter-nullable.test.ts)
- [`packages/provider-utils/src/generate-id.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/generate-id.test.ts)
- [`packages/provider-utils/src/get-from-api.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/get-from-api.test.ts)
- [`packages/provider-utils/src/get-runtime-environment-user-agent.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/get-runtime-environment-user-agent.test.ts)
- [`packages/provider-utils/src/handle-fetch-error.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/handle-fetch-error.test.ts)
- [`packages/provider-utils/src/inject-json-instruction.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/inject-json-instruction.test.ts)
- [`packages/provider-utils/src/is-browser-runtime.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/is-browser-runtime.test.ts)
- [`packages/provider-utils/src/is-json-serializable.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/is-json-serializable.test.ts)
- [`packages/provider-utils/src/is-provider-reference.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/is-provider-reference.test.ts)
- [`packages/provider-utils/src/is-same-origin.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/is-same-origin.test.ts)
- [`packages/provider-utils/src/is-url-supported.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/is-url-supported.test.ts)
- [`packages/provider-utils/src/map-reasoning-to-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/map-reasoning-to-provider.test.ts)
- [`packages/provider-utils/src/media-type-to-extension.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/media-type-to-extension.test.ts)
- [`packages/provider-utils/src/normalize-headers.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/normalize-headers.test.ts)
- [`packages/provider-utils/src/parse-json.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/parse-json.test.ts)
- [`packages/provider-utils/src/read-response-with-size-limit.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/read-response-with-size-limit.test.ts)
- [`packages/provider-utils/src/remove-undefined-entries.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/remove-undefined-entries.test.ts)
- [`packages/provider-utils/src/resolve-full-media-type.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/resolve-full-media-type.test.ts)
- [`packages/provider-utils/src/resolve-provider-reference.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/resolve-provider-reference.test.ts)
- [`packages/provider-utils/src/resolve.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/resolve.test.ts)
- [`packages/provider-utils/src/response-handler.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/response-handler.test.ts)
- [`packages/provider-utils/src/schema.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/schema.test.ts)
- [`packages/provider-utils/src/secure-json-parse.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/secure-json-parse.test.ts)
- [`packages/provider-utils/src/serialize-model-options.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/serialize-model-options.test.ts)
- [`packages/provider-utils/src/streaming-tool-call-tracker.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/streaming-tool-call-tracker.test.ts)
- [`packages/provider-utils/src/strip-file-extension.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/strip-file-extension.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parse-def.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parse-def.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/array.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/array.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/bigint.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/bigint.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/branded.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/branded.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/catch.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/catch.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/date.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/date.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/default.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/default.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/effects.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/effects.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/intersection.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/intersection.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/map.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/map.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/native-enum.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/native-enum.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/nullable.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/nullable.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/number.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/number.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/object.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/object.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/optional.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/optional.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/pipe.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/pipe.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/promise.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/promise.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/readonly.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/readonly.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/record.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/record.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/set.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/set.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/string.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/string.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/tuple.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/tuple.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/union.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/union.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/refs.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/refs.test.ts)
- [`packages/provider-utils/src/to-json-schema/zod3-to-json-schema/zod3-to-json-schema.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/to-json-schema/zod3-to-json-schema/zod3-to-json-schema.test.ts)
- [`packages/provider-utils/src/types/executable-tool.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/types/executable-tool.test.ts)
- [`packages/provider-utils/src/types/execute-tool.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/types/execute-tool.test.ts)
- [`packages/provider-utils/src/validate-download-url.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/validate-download-url.test.ts)
- [`packages/provider-utils/src/validate-types.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/validate-types.test.ts)
- [`packages/provider-utils/src/with-user-agent-suffix.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/provider-utils/src/with-user-agent-suffix.test.ts)

### `quiverai (@ai-sdk/quiverai@2.0.5)`

- [`packages/quiverai/src/quiverai-image-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/quiverai/src/quiverai-image-model.test.ts)
- [`packages/quiverai/src/quiverai-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/quiverai/src/quiverai-provider.test.ts)

### `react (@ai-sdk/react@4.0.17)`

- [`packages/react/src/mcp-apps/bridge.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/react/src/mcp-apps/bridge.test.ts)
- [`packages/react/src/mcp-apps/utils.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/react/src/mcp-apps/utils.test.ts)
- [`packages/react/src/use-chat.ui.test.tsx`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/react/src/use-chat.ui.test.tsx)
- [`packages/react/src/use-completion.ui.test.tsx`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/react/src/use-completion.ui.test.tsx)
- [`packages/react/src/use-object.ui.test.tsx`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/react/src/use-object.ui.test.tsx)
- [`packages/react/src/use-realtime.test.tsx`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/react/src/use-realtime.test.tsx)

### `replicate (@ai-sdk/replicate@3.0.6)`

- [`packages/replicate/src/replicate-image-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/replicate/src/replicate-image-model.test.ts)
- [`packages/replicate/src/replicate-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/replicate/src/replicate-provider.test.ts)
- [`packages/replicate/src/replicate-video-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/replicate/src/replicate-video-model.test.ts)

### `revai (@ai-sdk/revai@3.0.5)`

- [`packages/revai/src/revai-error.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/revai/src/revai-error.test.ts)
- [`packages/revai/src/revai-transcription-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/revai/src/revai-transcription-model.test.ts)

### `rsc`

- [`packages/rsc/src/ai-state.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/rsc/src/ai-state.test.ts)
- [`packages/rsc/src/stream-ui/stream-ui.ui.test.tsx`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/rsc/src/stream-ui/stream-ui.ui.test.tsx)
- [`packages/rsc/src/streamable-ui/create-streamable-ui.ui.test.tsx`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/rsc/src/streamable-ui/create-streamable-ui.ui.test.tsx)
- [`packages/rsc/src/streamable-value/create-streamable-value.test.tsx`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/rsc/src/streamable-value/create-streamable-value.test.tsx)
- [`packages/rsc/src/streamable-value/read-streamable-value.ui.test.tsx`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/rsc/src/streamable-value/read-streamable-value.ui.test.tsx)
- [`packages/rsc/tests/e2e/spec/streamable.e2e.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/rsc/tests/e2e/spec/streamable.e2e.test.ts)

### `sandbox-just-bash`

- [`packages/sandbox-just-bash/src/just-bash-sandbox-session.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/sandbox-just-bash/src/just-bash-sandbox-session.test.ts)

### `sandbox-vercel`

- [`packages/sandbox-vercel/src/vercel-sandbox-session.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/sandbox-vercel/src/vercel-sandbox-session.test.ts)
- [`packages/sandbox-vercel/src/vercel-sandbox.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/sandbox-vercel/src/vercel-sandbox.test.ts)

### `svelte`

- [`packages/svelte/src/chat.svelte.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/svelte/src/chat.svelte.test.ts)
- [`packages/svelte/src/completion.svelte.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/svelte/src/completion.svelte.test.ts)
- [`packages/svelte/src/structured-object.svelte.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/svelte/src/structured-object.svelte.test.ts)

### `test-server`

- [`packages/test-server/src/with-vitest.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/test-server/src/with-vitest.test.ts)

### `togetherai (@ai-sdk/togetherai@3.0.6)`

- [`packages/togetherai/src/reranking/togetherai-reranking-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/togetherai/src/reranking/togetherai-reranking-model.test.ts)
- [`packages/togetherai/src/togetherai-image-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/togetherai/src/togetherai-image-model.test.ts)
- [`packages/togetherai/src/togetherai-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/togetherai/src/togetherai-provider.test.ts)

### `tui`

- [`packages/tui/src/agent-tui.integration.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/tui/src/agent-tui.integration.test.ts)
- [`packages/tui/src/agent-tui.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/tui/src/agent-tui.test.ts)
- [`packages/tui/src/tui/layout.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/tui/src/tui/layout.test.ts)
- [`packages/tui/src/tui/markdown.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/tui/src/tui/markdown.test.ts)
- [`packages/tui/src/tui/terminal-frame-buffer.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/tui/src/tui/terminal-frame-buffer.test.ts)
- [`packages/tui/src/tui/terminal-renderer.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/tui/src/tui/terminal-renderer.test.ts)

### `vercel (@ai-sdk/vercel@3.0.5)`

- [`packages/vercel/src/vercel-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/vercel/src/vercel-provider.test.ts)

### `voyage (@ai-sdk/voyage@2.0.5)`

- [`packages/voyage/src/reranking/voyage-reranking-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/voyage/src/reranking/voyage-reranking-model.test.ts)
- [`packages/voyage/src/voyage-embedding-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/voyage/src/voyage-embedding-model.test.ts)
- [`packages/voyage/src/voyage-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/voyage/src/voyage-provider.test.ts)

### `vue`

- [`packages/vue/src/chat.vue.ui.test.tsx`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/vue/src/chat.vue.ui.test.tsx)
- [`packages/vue/src/use-chat.ui.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/vue/src/use-chat.ui.test.ts)
- [`packages/vue/src/use-completion.ui.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/vue/src/use-completion.ui.test.ts)
- [`packages/vue/src/use-object.ui.test.tsx`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/vue/src/use-object.ui.test.tsx)

### `workflow`

- [`packages/workflow/src/serializable-schema.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/workflow/src/serializable-schema.test.ts)
- [`packages/workflow/src/stream-text-iterator.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/workflow/src/stream-text-iterator.test.ts)
- [`packages/workflow/src/workflow-agent-compat.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/workflow/src/workflow-agent-compat.test.ts)
- [`packages/workflow/src/workflow-agent-e2e.integration.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/workflow/src/workflow-agent-e2e.integration.test.ts)
- [`packages/workflow/src/workflow-agent.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/workflow/src/workflow-agent.test.ts)
- [`packages/workflow/src/workflow-chat-transport.stream-repair.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/workflow/src/workflow-chat-transport.stream-repair.test.ts)
- [`packages/workflow/src/workflow-chat-transport.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/workflow/src/workflow-chat-transport.test.ts)
- [`packages/workflow/src/workflow-smoke.integration.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/workflow/src/workflow-smoke.integration.test.ts)

### `workflow-harness`

- [`packages/workflow-harness/src/run-harness-agent-slice.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/workflow-harness/src/run-harness-agent-slice.test.ts)

### `xai (@ai-sdk/xai@4.0.7)`

- [`packages/xai/src/convert-to-xai-chat-messages.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/xai/src/convert-to-xai-chat-messages.test.ts)
- [`packages/xai/src/convert-xai-chat-usage.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/xai/src/convert-xai-chat-usage.test.ts)
- [`packages/xai/src/files/xai-files.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/xai/src/files/xai-files.test.ts)
- [`packages/xai/src/realtime/xai-realtime-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/xai/src/realtime/xai-realtime-model.test.ts)
- [`packages/xai/src/responses/convert-to-xai-responses-input.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/xai/src/responses/convert-to-xai-responses-input.test.ts)
- [`packages/xai/src/responses/convert-xai-responses-usage.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/xai/src/responses/convert-xai-responses-usage.test.ts)
- [`packages/xai/src/responses/xai-responses-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/xai/src/responses/xai-responses-language-model.test.ts)
- [`packages/xai/src/responses/xai-responses-prepare-tools.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/xai/src/responses/xai-responses-prepare-tools.test.ts)
- [`packages/xai/src/xai-chat-language-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/xai/src/xai-chat-language-model.test.ts)
- [`packages/xai/src/xai-error.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/xai/src/xai-error.test.ts)
- [`packages/xai/src/xai-image-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/xai/src/xai-image-model.test.ts)
- [`packages/xai/src/xai-prepare-tools.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/xai/src/xai-prepare-tools.test.ts)
- [`packages/xai/src/xai-provider.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/xai/src/xai-provider.test.ts)
- [`packages/xai/src/xai-speech-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/xai/src/xai-speech-model.test.ts)
- [`packages/xai/src/xai-transcription-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/xai/src/xai-transcription-model.test.ts)
- [`packages/xai/src/xai-video-model.test.ts`](https://github.com/vercel/ai/blob/148babc531b55f85e61308639fa6e04ba0d27220/packages/xai/src/xai-video-model.test.ts)
