# Provider Version Ledger

This ledger records the npm package versions used as Swift comparison
baselines. Before a provider-complete pass, compare the package listed here with
the current npm package or upstream repository state, then update the row if the
pass uses a newer version.

Provider/product status is tracked separately in `Docs/PortingStatus.md`. This
table is an inventory and version ledger, not the remaining work list.

Registry versions were checked with `npm view <package> version` on 2026-08-31.
The rows record the published package versions audited in this snapshot;
behavior is either ported or covered, or explicitly deferred in the status and
audit documents. Rows are not silently advanced before a package-by-package
source and behavior review.

| Package | Version baseline | Main Swift evidence |
| --- | --- | --- |
| `@ai-sdk/alibaba` | `2.0.39` | `AIProviders.alibaba`, `AlibabaLanguageModel`, `AlibabaEmbeddingModel`, `AlibabaProviderTests.swift` |
| `@ai-sdk/amazon-bedrock` | `5.0.68` | `AIProviders.amazonBedrock`, `AIProviders.amazonBedrockAnthropic`, `AIProviders.bedrockMantle`, `AmazonBedrockModels.swift`, `AmazonBedrockTests.swift` |
| `@ai-sdk/anthropic` | `4.0.46` | `AIProviders.anthropic`, `AnthropicLanguageModel`, `AnthropicBatchLanguageModel`, `AnthropicTools`, `AnthropicTests.swift`, `AnthropicBatchV4UpstreamTests.swift` |
| `@ai-sdk/anthropic-aws` | `2.0.38` | `AIProviders.anthropicAWS`, `AnthropicAWSProvider`, `AnthropicTests.swift` |
| `@ai-sdk/assemblyai` | `3.0.34` | `AIProviders.assemblyAI`, `AssemblyAITranscriptionModel`, `AssemblyAIProviderTests.swift` |
| `@ai-sdk/azure` | `4.0.54` | `AIProviders.azure`, `AzureOpenAIProvider`, `AzureOpenAITools`, `AlibabaProdiaAzureQuiverTests.swift` |
| `@ai-sdk/baseten` | `2.1.19` | `AIProviders.baseten`, `OpenAICompatibleProvider`, `BasetenProviderTests.swift` |
| `@ai-sdk/black-forest-labs` | `2.0.35` | `AIProviders.blackForestLabs`, `BlackForestLabsImageModel`, `BlackForestLabsVideoModel`, `AsyncVideoModel`, `BlackForestLabsVideoModelTests.swift`, `BlackForestLabsVideoOperationTests.swift` |
| `@ai-sdk/bytedance` | `2.0.37` | `AIProviders.byteDance`, `ByteDanceVideoModel`, `AsyncVideoModel`, `ByteDanceProviderTests.swift`, `ByteDanceAsyncVideoUpstreamParityTests.swift` |
| `@ai-sdk/cartesia` | `3.0.29` | `AIProviders.cartesia`, `CartesiaProvider`, `CartesiaSpeechModel`, `CartesiaTranscriptionModel`, `CartesiaStreamingTranscriptionModel`, `Cartesia*Tests.swift` |
| `@ai-sdk/cerebras` | `3.0.41` | `AIProviders.cerebras`, `CerebrasLanguageModel`, `CerebrasProviderTests.swift` |
| `@ai-sdk/cohere` | `4.0.35` | `AIProviders.cohere`, `CohereLanguageModel`, `CohereEmbeddingModel`, `CohereRerankingModel`, `CohereMistralVoyageTests.swift` |
| `@ai-sdk/deepgram` | `3.1.5` | `AIProviders.deepgram`, `DeepgramTranscriptionModel`, `DeepgramSpeechModel`, `DeepgramProviderTests.swift` |
| `@ai-sdk/deepinfra` | `3.0.41` | `AIProviders.deepInfra`, `OpenAICompatibleProvider`, `DeepInfraProviderTests.swift` |
| `@ai-sdk/deepseek` | `3.0.37` | `AIProviders.deepSeek`, `DeepSeekLanguageModel`, `DeepSeekFileClient`, `DeepSeekProviderTests.swift`, `DeepSeekVisionAndFilesUpstreamParityTests.swift` |
| `@ai-sdk/elevenlabs` | `3.0.35` | `AIProviders.elevenLabs`, `ElevenLabsSpeechModel`, `ElevenLabsTranscriptionModel`, `ElevenLabsProviderTests.swift` |
| `@ai-sdk/fal` | `3.0.35` | `AIProviders.fal`, `FalMediaProviderTests.swift`, `FalProviderTests.swift` |
| `@ai-sdk/fish-audio` | `3.0.12` | `AIProviders.fishAudio`, `FishAudioProvider`, `FishAudioSpeechModel`, `FishAudioTranscriptionModel`, `FishAudio*Tests.swift` |
| `@ai-sdk/fireworks` | `3.0.44` | `AIProviders.fireworks`, `FireworksProviderTests.swift` |
| `@ai-sdk/gateway` | `4.0.69` | `AIProviders.gateway`, `GatewayProvider`, `GatewayModels.swift`, `GatewayStreamingTranscriptionModel.swift`, `GatewayTests.swift`, `Gateway*UpstreamParityTests.swift` |
| `@ai-sdk/gmicloud` | `3.0.12` | `AIProviders.gmiCloud`, `GMICloudProvider`, `OpenAICompatibleChatModel`, `GMICloudProviderTests.swift` |
| `@ai-sdk/gladia` | `3.0.34` | `AIProviders.gladia`, `GladiaTranscriptionModel`, `GladiaProviderTests.swift` |
| `@ai-sdk/google` | `4.0.58` | `AIProviders.google`, `GoogleGenerativeAIProvider`, `GoogleGenerativeAI.swift`, `GoogleGenerativeMediaModels.swift`, `GoogleGenerativeAITests.swift`, `GoogleGenerativeAIMediaAndToolsTests.swift` |
| `@ai-sdk/google-vertex` | `5.0.70` | `AIProviders.googleVertex`, `GoogleVertexProvider`, `GoogleVertexProvider.swift`, `GoogleVertexModels.swift`, `GoogleVertexTests.swift`, `GoogleVertexMediaAndMaaSTests.swift` |
| `@ai-sdk/groq` | `4.0.35` | `AIProviders.groq`, `GroqLanguageModel`, `GroqTranscriptionModel`, `GroqProviderTests.swift` |
| `@ai-sdk/huggingface` | `2.0.41` | `AIProviders.huggingFace`, `HuggingFaceProvider`, `HuggingFaceResponsesLanguageModel`, `HuggingFaceProviderTests.swift` |
| `@ai-sdk/hume` | `3.0.34` | `AIProviders.hume`, `HumeSpeechModel`, `HumeProviderTests.swift` |
| `@ai-sdk/klingai` | `4.0.36` | `AIProviders.klingAI`, `KlingAIVideoModel`, `KlingAIProviderTests.swift` |
| `@ai-sdk/lmnt` | `3.0.34` | `AIProviders.lmnt`, `LMNTSpeechModel`, `LMNTProviderTests.swift` |
| `@ai-sdk/luma` | `3.0.35` | `AIProviders.luma`, `LumaImageModel`, `LumaProviderTests.swift` |
| `@ai-sdk/mcp` | `2.0.41` | `MCPClient`, `MCPHTTPTransport`, `MCPStdioTransport`, `MCPApps`, `MCPClientTests.swift`, `MCPOAuthTests.swift`, `MCPStdioTransportTests.swift` |
| `@ai-sdk/minimax` | `3.0.22` | `AIProviders.miniMax`, `MiniMaxProvider`, `AnthropicLanguageModel`, `MiniMaxVideoModel`, `MiniMaxProviderTests.swift` |
| `@ai-sdk/mistral` | `4.0.37` | `AIProviders.mistral`, `MistralLanguageModel`, `MistralEmbeddingModel`, `MistralTranscriptionModel`, `MistralSpeechModel`, `PerplexityMistralUpstreamTests.swift` |
| `@ai-sdk/moonshotai` | `3.0.43` | `AIProviders.moonshotAI`, `MoonshotLanguageModel`, `MoonshotAIProviderTests.swift` |
| `@ai-sdk/open-responses` | `2.0.36` | `AIProviders.openResponses`, `ResponsesRequestMode.openResponses`, `ResponsesEndpointTests.swift` |
| `@ai-sdk/openai` | `4.0.52` | `AIProviders.openAI`, `OpenAICompatible*Model`, `OpenAITools`, `OpenAI*Tests.swift`, `FileAndSkillClientTests.swift` |
| `@ai-sdk/openai-compatible` | `3.0.41` | `AIProviders.openAICompatible`, `OpenAICompatibleProvider`, `OpenAICompatibleTests.swift` |
| `@ai-sdk/perplexity` | `4.0.36` | `AIProviders.perplexity`, `PerplexityLanguageModel`, `PerplexityEmbeddingModel`, `PerplexityMistralUpstreamTests.swift` |
| `@ai-sdk/prodia` | `2.0.35` | `AIProviders.prodia`, `ProdiaLanguageModel`, `ProdiaMediaModel`, `ProdiaProviderTests.swift` |
| `@ai-sdk/quiverai` | `2.0.34` | `AIProviders.quiverAI`, `QuiverAIImageModel`, `QuiverAIProviderTests.swift` |
| `@ai-sdk/replicate` | `3.0.35` | `AIProviders.replicate`, `ReplicateImageModel`, `ReplicateVideoModel`, `ReplicateProviderTests.swift` |
| `@ai-sdk/revai` | `3.0.34` | `AIProviders.revAI`, `RevAITranscriptionModel`, `RevAIProviderTests.swift` |
| `@ai-sdk/togetherai` | `3.0.42` | `AIProviders.togetherAI`, `TogetherAIImageModel`, `TogetherAIRerankingModel`, `TogetherAIProviderTests.swift` |
| `@ai-sdk/vercel` | `3.0.30` | `AIProviders.vercel`, `VercelProvider`, `ProviderRegistryVercelTests.swift` |
| `@ai-sdk/voyage` | `2.0.34` | `AIProviders.voyage`, `VoyageEmbeddingModel`, `VoyageRerankingModel`, `VoyageProviderOptionSchemaTests.swift` |
| `@ai-sdk/xai` | `4.0.50` | `AIProviders.xAI`, `XAIResponses.swift`, `XAIResponsesBatchLanguageModel.swift`, `XAITools`, `XAIImageModel`, `XAIVideoModel`, `XAIProviderTests.swift`, `ProviderGroupBUpstreamParity20260831Tests.swift` |
