# Provider Version Ledger

This ledger records the npm package versions used as Swift comparison
baselines. Before a provider-complete pass, compare the package listed here with
the current npm package or upstream repository state, then update the row if the
pass uses a newer version.

Provider/product status is tracked separately in `Docs/PortingStatus.md`. This
table is an inventory and version ledger, not the remaining work list.

Registry versions were checked with `npm view <package> version` on 2026-08-19.
The rows record the published package versions actually audited and ported;
they are not silently advanced when a newer registry version has not yet had a
package-by-package source and behavior review.

| Package | Version baseline | Main Swift evidence |
| --- | --- | --- |
| `@ai-sdk/alibaba` | `2.0.32` | `AIProviders.alibaba`, `AlibabaLanguageModel`, `AlibabaEmbeddingModel`, `AlibabaProviderTests.swift` |
| `@ai-sdk/amazon-bedrock` | `5.0.58` | `AIProviders.amazonBedrock`, `AIProviders.amazonBedrockAnthropic`, `AIProviders.bedrockMantle`, `AmazonBedrockModels.swift`, `AmazonBedrockTests.swift` |
| `@ai-sdk/anthropic` | `4.0.39` | `AIProviders.anthropic`, `AnthropicLanguageModel`, `AnthropicBatchLanguageModel`, `AnthropicTools`, `AnthropicTests.swift`, `AnthropicBatchV4UpstreamTests.swift` |
| `@ai-sdk/anthropic-aws` | `2.0.31` | `AIProviders.anthropicAWS`, `AnthropicAWSProvider`, `AnthropicTests.swift` |
| `@ai-sdk/assemblyai` | `3.0.27` | `AIProviders.assemblyAI`, `AssemblyAITranscriptionModel`, `AssemblyAIProviderTests.swift` |
| `@ai-sdk/azure` | `4.0.44` | `AIProviders.azure`, `AzureOpenAIProvider`, `AzureOpenAITools`, `AlibabaProdiaAzureQuiverTests.swift` |
| `@ai-sdk/baseten` | `2.1.9` | `AIProviders.baseten`, `OpenAICompatibleProvider`, `BasetenProviderTests.swift` |
| `@ai-sdk/black-forest-labs` | `2.0.28` | `AIProviders.blackForestLabs`, `BlackForestLabsImageModel`, `BlackForestLabsVideoModel`, `AsyncVideoModel`, `BlackForestLabsVideoModelTests.swift`, `BlackForestLabsVideoOperationTests.swift` |
| `@ai-sdk/bytedance` | `2.0.29` | `AIProviders.byteDance`, `ByteDanceVideoModel`, `ByteDanceProviderTests.swift` |
| `@ai-sdk/cartesia` | `3.0.22` | `AIProviders.cartesia`, `CartesiaProvider`, `CartesiaSpeechModel`, `CartesiaTranscriptionModel`, `CartesiaStreamingTranscriptionModel`, `Cartesia*Tests.swift` |
| `@ai-sdk/cerebras` | `3.0.31` | `AIProviders.cerebras`, `CerebrasLanguageModel`, `CerebrasProviderTests.swift` |
| `@ai-sdk/cohere` | `4.0.27` | `AIProviders.cohere`, `CohereLanguageModel`, `CohereEmbeddingModel`, `CohereRerankingModel`, `CohereMistralVoyageTests.swift` |
| `@ai-sdk/deepgram` | `3.0.27` | `AIProviders.deepgram`, `DeepgramTranscriptionModel`, `DeepgramSpeechModel`, `DeepgramProviderTests.swift` |
| `@ai-sdk/deepinfra` | `3.0.31` | `AIProviders.deepInfra`, `OpenAICompatibleProvider`, `DeepInfraProviderTests.swift` |
| `@ai-sdk/deepseek` | `3.0.28` | `AIProviders.deepSeek`, `DeepSeekLanguageModel`, `DeepSeekProviderTests.swift` |
| `@ai-sdk/elevenlabs` | `3.0.28` | `AIProviders.elevenLabs`, `ElevenLabsSpeechModel`, `ElevenLabsTranscriptionModel`, `ElevenLabsProviderTests.swift` |
| `@ai-sdk/fal` | `3.0.28` | `AIProviders.fal`, `FalMediaProviderTests.swift`, `FalProviderTests.swift` |
| `@ai-sdk/fish-audio` | `3.0.5` | `AIProviders.fishAudio`, `FishAudioProvider`, `FishAudioSpeechModel`, `FishAudioTranscriptionModel`, `FishAudio*Tests.swift` |
| `@ai-sdk/fireworks` | `3.0.34` | `AIProviders.fireworks`, `FireworksProviderTests.swift` |
| `@ai-sdk/gateway` | `4.0.54` | `AIProviders.gateway`, `GatewayProvider`, `GatewayModels.swift`, `GatewayTests.swift` |
| `@ai-sdk/gmicloud` | `3.0.2` | `AIProviders.gmiCloud`, `GMICloudProvider`, `OpenAICompatibleChatModel`, `GMICloudProviderTests.swift` |
| `@ai-sdk/gladia` | `3.0.27` | `AIProviders.gladia`, `GladiaTranscriptionModel`, `GladiaProviderTests.swift` |
| `@ai-sdk/google` | `4.0.45` | `AIProviders.google`, `GoogleGenerativeAIProvider`, `GoogleGenerativeAI.swift`, `GoogleGenerativeMediaModels.swift`, `GoogleGenerativeAITests.swift`, `GoogleGenerativeAIMediaAndToolsTests.swift` |
| `@ai-sdk/google-vertex` | `5.0.56` | `AIProviders.googleVertex`, `GoogleVertexProvider`, `GoogleVertexProvider.swift`, `GoogleVertexModels.swift`, `GoogleVertexTests.swift`, `GoogleVertexMediaAndMaaSTests.swift` |
| `@ai-sdk/groq` | `4.0.28` | `AIProviders.groq`, `GroqLanguageModel`, `GroqTranscriptionModel`, `GroqProviderTests.swift` |
| `@ai-sdk/huggingface` | `2.0.31` | `AIProviders.huggingFace`, `HuggingFaceProvider`, `HuggingFaceResponsesLanguageModel`, `HuggingFaceProviderTests.swift` |
| `@ai-sdk/hume` | `3.0.27` | `AIProviders.hume`, `HumeSpeechModel`, `HumeProviderTests.swift` |
| `@ai-sdk/klingai` | `4.0.29` | `AIProviders.klingAI`, `KlingAIVideoModel`, `KlingAIProviderTests.swift` |
| `@ai-sdk/lmnt` | `3.0.27` | `AIProviders.lmnt`, `LMNTSpeechModel`, `LMNTProviderTests.swift` |
| `@ai-sdk/luma` | `3.0.28` | `AIProviders.luma`, `LumaImageModel`, `LumaProviderTests.swift` |
| `@ai-sdk/mcp` | `2.0.33` | `MCPClient`, `MCPHTTPTransport`, `MCPStdioTransport`, `MCPApps`, `MCPClientTests.swift`, `MCPOAuthTests.swift`, `MCPStdioTransportTests.swift` |
| `@ai-sdk/minimax` | `3.0.15` | `AIProviders.miniMax`, `MiniMaxProvider`, `AnthropicLanguageModel`, `MiniMaxVideoModel`, `MiniMaxProviderTests.swift` |
| `@ai-sdk/mistral` | `4.0.29` | `AIProviders.mistral`, `MistralLanguageModel`, `MistralEmbeddingModel`, `MistralTranscriptionModel`, `MistralSpeechModel`, `PerplexityMistralUpstreamTests.swift` |
| `@ai-sdk/moonshotai` | `3.0.35` | `AIProviders.moonshotAI`, `MoonshotLanguageModel`, `MoonshotAIProviderTests.swift` |
| `@ai-sdk/open-responses` | `2.0.28` | `AIProviders.openResponses`, `ResponsesRequestMode.openResponses`, `ResponsesEndpointTests.swift` |
| `@ai-sdk/openai` | `4.0.43` | `AIProviders.openAI`, `OpenAICompatible*Model`, `OpenAITools`, `OpenAI*Tests.swift`, `FileAndSkillClientTests.swift` |
| `@ai-sdk/openai-compatible` | `3.0.31` | `AIProviders.openAICompatible`, `OpenAICompatibleProvider`, `OpenAICompatibleTests.swift` |
| `@ai-sdk/perplexity` | `4.0.29` | `AIProviders.perplexity`, `PerplexityLanguageModel`, `PerplexityEmbeddingModel`, `PerplexityMistralUpstreamTests.swift` |
| `@ai-sdk/prodia` | `2.0.28` | `AIProviders.prodia`, `ProdiaLanguageModel`, `ProdiaMediaModel`, `ProdiaProviderTests.swift` |
| `@ai-sdk/quiverai` | `2.0.27` | `AIProviders.quiverAI`, `QuiverAIImageModel`, `QuiverAIProviderTests.swift` |
| `@ai-sdk/replicate` | `3.0.28` | `AIProviders.replicate`, `ReplicateImageModel`, `ReplicateVideoModel`, `ReplicateProviderTests.swift` |
| `@ai-sdk/revai` | `3.0.27` | `AIProviders.revAI`, `RevAITranscriptionModel`, `RevAIProviderTests.swift` |
| `@ai-sdk/togetherai` | `3.0.32` | `AIProviders.togetherAI`, `TogetherAIImageModel`, `TogetherAIRerankingModel`, `TogetherAIProviderTests.swift` |
| `@ai-sdk/vercel` | `3.0.30` | `AIProviders.vercel`, `VercelProvider`, `ProviderRegistryVercelTests.swift` |
| `@ai-sdk/voyage` | `2.0.27` | `AIProviders.voyage`, `VoyageEmbeddingModel`, `VoyageRerankingModel`, `VoyageProviderOptionSchemaTests.swift` |
| `@ai-sdk/xai` | `4.0.40` | `AIProviders.xAI`, `XAIResponses.swift`, `XAITools`, `XAIImageModel`, `XAIVideoModel`, `XAIProviderTests.swift` |
