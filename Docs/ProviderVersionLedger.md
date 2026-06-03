# Provider Version Ledger

This ledger records the npm package versions used as Swift comparison
baselines. Before a provider-complete pass, compare the package listed here with
the current npm package or upstream repository state, then update the row if the
pass uses a newer version.

Provider sweep status is tracked separately in `Docs/ProviderSyncStatus.md`.
This table is an inventory and version ledger, not the remaining work list.

Versions below were checked with `npm view <package> version` on 2026-06-03.

| Package | Version baseline | Main Swift evidence |
| --- | --- | --- |
| `@ai-sdk/alibaba` | `1.0.25` | `AIProviders.alibaba`, `AlibabaLanguageModel`, `AlibabaProviderTests.swift` |
| `@ai-sdk/amazon-bedrock` | `4.0.112` | `AIProviders.amazonBedrock`, `AIProviders.amazonBedrockAnthropic`, `AIProviders.bedrockMantle`, `AmazonBedrockModels.swift`, `AmazonBedrockTests.swift` |
| `@ai-sdk/anthropic` | `3.0.81` | `AIProviders.anthropic`, `AnthropicLanguageModel`, `AnthropicTools`, `AnthropicTests.swift` |
| `@ai-sdk/anthropic-aws` | `1.0.3` | `AIProviders.anthropicAWS`, `AnthropicAWSProvider`, `AnthropicTests.swift` |
| `@ai-sdk/assemblyai` | `2.0.33` | `AIProviders.assemblyAI`, `AssemblyAITranscriptionModel`, `AssemblyAIProviderTests.swift` |
| `@ai-sdk/azure` | `3.0.69` | `AIProviders.azure`, `AzureOpenAIProvider`, `AzureOpenAITools`, `AlibabaProdiaAzureQuiverTests.swift` |
| `@ai-sdk/baseten` | `1.0.51` | `AIProviders.baseten`, `OpenAICompatibleProvider`, `BasetenProviderTests.swift` |
| `@ai-sdk/black-forest-labs` | `1.0.34` | `AIProviders.blackForestLabs`, `BlackForestLabsImageModel`, `BlackForestLabsProviderTests.swift` |
| `@ai-sdk/bytedance` | `1.0.14` | `AIProviders.byteDance`, `ByteDanceVideoModel`, `ByteDanceProviderTests.swift` |
| `@ai-sdk/cerebras` | `2.0.54` | `AIProviders.cerebras`, `CerebrasLanguageModel`, `CerebrasProviderTests.swift` |
| `@ai-sdk/cohere` | `3.0.36` | `AIProviders.cohere`, `CohereLanguageModel`, `CohereEmbeddingModel`, `CohereRerankingModel`, `CohereMistralVoyageTests.swift` |
| `@ai-sdk/deepgram` | `2.0.33` | `AIProviders.deepgram`, `DeepgramTranscriptionModel`, `DeepgramSpeechModel`, `DeepgramProviderTests.swift` |
| `@ai-sdk/deepinfra` | `2.0.52` | `AIProviders.deepInfra`, `OpenAICompatibleProvider`, `DeepInfraProviderTests.swift` |
| `@ai-sdk/deepseek` | `2.0.35` | `AIProviders.deepSeek`, `DeepSeekLanguageModel`, `DeepSeekProviderTests.swift` |
| `@ai-sdk/elevenlabs` | `2.0.33` | `AIProviders.elevenLabs`, `ElevenLabsSpeechModel`, `ElevenLabsTranscriptionModel`, `ElevenLabsProviderTests.swift` |
| `@ai-sdk/fal` | `2.0.34` | `AIProviders.fal`, `FalMediaProviderTests.swift`, `FalProviderTests.swift` |
| `@ai-sdk/fireworks` | `2.0.53` | `AIProviders.fireworks`, `FireworksProviderTests.swift` |
| `@ai-sdk/gateway` | `3.0.123` | `AIProviders.gateway`, `GatewayProvider`, `GatewayModels.swift`, `GatewayTests.swift` |
| `@ai-sdk/gladia` | `2.0.33` | `AIProviders.gladia`, `GladiaTranscriptionModel`, `GladiaProviderTests.swift` |
| `@ai-sdk/google` | `3.0.80` | `AIProviders.google`, `GoogleGenerativeAIProvider`, `GoogleGenerativeAI.swift`, `GoogleGenerativeAITests.swift` |
| `@ai-sdk/google-vertex` | `4.0.141` | `AIProviders.googleVertex`, `GoogleVertexProvider`, `GoogleVertexProvider.swift`, `GoogleVertexTests.swift` |
| `@ai-sdk/groq` | `3.0.39` | `AIProviders.groq`, `GroqLanguageModel`, `GroqTranscriptionModel`, `GroqProviderTests.swift` |
| `@ai-sdk/huggingface` | `1.0.50` | `AIProviders.huggingFace`, `HuggingFaceProvider`, `HuggingFaceResponsesLanguageModel`, `HuggingFaceProviderTests.swift` |
| `@ai-sdk/hume` | `2.0.33` | `AIProviders.hume`, `HumeSpeechModel`, `HumeProviderTests.swift` |
| `@ai-sdk/klingai` | `3.0.18` | `AIProviders.klingAI`, `KlingAIVideoModel`, `KlingAIProviderTests.swift` |
| `@ai-sdk/lmnt` | `2.0.33` | `AIProviders.lmnt`, `LMNTSpeechModel`, `LMNTProviderTests.swift` |
| `@ai-sdk/luma` | `2.0.33` | `AIProviders.luma`, `LumaImageModel`, `LumaProviderTests.swift` |
| `@ai-sdk/mcp` | `1.0.45` | `MCPClient`, `MCPHTTPTransport`, `MCPStdioTransport`, `MCPClientTests.swift`, `MCPOAuthTests.swift`, `MCPStdioTransportTests.swift` |
| `@ai-sdk/mistral` | `3.0.37` | `AIProviders.mistral`, `MistralLanguageModel`, `MistralEmbeddingModel`, `CohereMistralVoyageTests.swift` |
| `@ai-sdk/moonshotai` | `2.0.23` | `AIProviders.moonshotAI`, `MoonshotLanguageModel`, `MoonshotAIProviderTests.swift` |
| `@ai-sdk/open-responses` | `1.0.16` | `AIProviders.openResponses`, `ResponsesRequestMode.openResponses`, `ResponsesEndpointTests.swift` |
| `@ai-sdk/openai` | `3.0.67` | `AIProviders.openAI`, `OpenAICompatible*Model`, `OpenAITools`, `OpenAI*Tests.swift` |
| `@ai-sdk/openai-compatible` | `2.0.48` | `AIProviders.openAICompatible`, `OpenAICompatibleProvider`, `OpenAICompatibleTests.swift` |
| `@ai-sdk/perplexity` | `3.0.33` | `AIProviders.perplexity`, `PerplexityLanguageModel`, `ResponsesEndpointTests.swift` |
| `@ai-sdk/prodia` | `1.0.31` | `AIProviders.prodia`, `ProdiaLanguageModel`, `ProdiaMediaModel`, `ProdiaProviderTests.swift` |
| `@ai-sdk/quiverai` | `1.0.0` | `AIProviders.quiverAI`, `QuiverAIImageModel`, `QuiverAIProviderTests.swift` |
| `@ai-sdk/replicate` | `2.0.33` | `AIProviders.replicate`, `ReplicateImageModel`, `ReplicateVideoModel`, `ReplicateProviderTests.swift` |
| `@ai-sdk/revai` | `2.0.33` | `AIProviders.revAI`, `RevAITranscriptionModel`, `RevAIProviderTests.swift` |
| `@ai-sdk/togetherai` | `2.0.53` | `AIProviders.togetherAI`, `TogetherAIImageModel`, `TogetherAIRerankingModel`, `TogetherAIProviderTests.swift` |
| `@ai-sdk/vercel` | `2.0.50` | `AIProviders.vercel`, `VercelProvider`, `ProviderRegistryVercelTests.swift` |
| `@ai-sdk/voyage` | `1.0.4` | `AIProviders.voyage`, `VoyageEmbeddingModel`, `VoyageRerankingModel`, `VoyageProviderOptionSchemaTests.swift` |
| `@ai-sdk/xai` | `3.0.93` | `AIProviders.xAI`, `XAITools`, `XAIImageModel`, `XAIVideoModel`, `XAIProviderTests.swift` |
