# Provider Version Ledger

This ledger records the npm package versions used as Swift comparison
baselines. Before a provider-complete pass, compare the package listed here with
the current npm package or upstream repository state, then update the row if the
pass uses a newer version.

Provider/product status is tracked separately in `Docs/PortingStatus.md`. This
table is an inventory and version ledger, not the remaining work list.

Registry versions were checked with `npm view <package> version` on 2026-09-06.
The rows record the published package versions audited in this snapshot;
behavior is either ported or covered, or explicitly deferred in the status and
audit documents. Rows are not silently advanced before a package-by-package
source and behavior review.

| Package | Version baseline | Main Swift evidence |
| --- | --- | --- |
| `@ai-sdk/alibaba` | `2.0.41` | `AIProviders.alibaba`, `AlibabaLanguageModel`, `AlibabaEmbeddingModel`, `AlibabaProviderTests.swift` |
| `@ai-sdk/amazon-bedrock` | `5.0.76` | `AIProviders.amazonBedrock`, `AIProviders.amazonBedrockAnthropic`, `AIProviders.bedrockMantle`, `AmazonBedrockModels.swift`, `AmazonBedrockTests.swift`, `AnthropicBedrockUpstream202609Tests.swift` |
| `@ai-sdk/anthropic` | `4.0.49` | `AIProviders.anthropic`, `AnthropicLanguageModel`, `AnthropicBatchLanguageModel`, `AnthropicTools`, `AnthropicTests.swift`, `AnthropicBatchV4UpstreamTests.swift`, `AnthropicBedrockUpstream202609Tests.swift` |
| `@ai-sdk/anthropic-aws` | `2.0.41` | `AIProviders.anthropicAWS`, `AnthropicAWSProvider`, `AnthropicTests.swift`, `AnthropicBedrockUpstream202609Tests.swift` |
| `@ai-sdk/assemblyai` | `3.0.36` | `AIProviders.assemblyAI`, `AssemblyAITranscriptionModel`, `AssemblyAIProviderTests.swift` |
| `@ai-sdk/azure` | `4.0.63` | `AIProviders.azure`, `AzureOpenAIProvider`, `AzureOpenAITools`, `AlibabaProdiaAzureQuiverTests.swift` |
| `@ai-sdk/baseten` | `2.1.22` | `AIProviders.baseten`, `OpenAICompatibleProvider`, `BasetenProviderTests.swift` |
| `@ai-sdk/black-forest-labs` | `2.0.37` | `AIProviders.blackForestLabs`, `BlackForestLabsImageModel`, `BlackForestLabsVideoModel`, `AsyncVideoModel`, `BlackForestLabsVideoModelTests.swift`, `BlackForestLabsVideoOperationTests.swift` |
| `@ai-sdk/bytedance` | `2.0.39` | `AIProviders.byteDance`, `ByteDanceVideoModel`, `AsyncVideoModel`, `ByteDanceProviderTests.swift`, `ByteDanceAsyncVideoUpstreamParityTests.swift`, `MediaStatusRedirectUpstreamTests.swift` |
| `@ai-sdk/cartesia` | `3.0.31` | `AIProviders.cartesia`, `CartesiaProvider`, `CartesiaSpeechModel`, `CartesiaTranscriptionModel`, `CartesiaStreamingTranscriptionModel`, `Cartesia*Tests.swift` |
| `@ai-sdk/cerebras` | `3.0.44` | `AIProviders.cerebras`, `CerebrasLanguageModel`, `CerebrasProviderTests.swift` |
| `@ai-sdk/cohere` | `4.0.37` | `AIProviders.cohere`, `CohereLanguageModel`, `CohereEmbeddingModel`, `CohereRerankingModel`, `CohereMistralVoyageTests.swift` |
| `@ai-sdk/deepgram` | `3.1.7` | `AIProviders.deepgram`, `DeepgramTranscriptionModel`, `DeepgramSpeechModel`, `DeepgramProviderTests.swift` |
| `@ai-sdk/deepinfra` | `3.0.44` | `AIProviders.deepInfra`, `OpenAICompatibleProvider`, `DeepInfraProviderTests.swift` |
| `@ai-sdk/deepseek` | `3.0.39` | `AIProviders.deepSeek`, `DeepSeekLanguageModel`, `DeepSeekFileClient`, `DeepSeekProviderTests.swift`, `DeepSeekVisionAndFilesUpstreamParityTests.swift` |
| `@ai-sdk/elevenlabs` | `3.0.37` | `AIProviders.elevenLabs`, `ElevenLabsSpeechModel`, `ElevenLabsTranscriptionModel`, `ElevenLabsProviderTests.swift` |
| `@ai-sdk/fal` | `3.0.37` | `AIProviders.fal`, `FalMediaProviderTests.swift`, `FalProviderTests.swift` |
| `@ai-sdk/fish-audio` | `3.0.14` | `AIProviders.fishAudio`, `FishAudioProvider`, `FishAudioSpeechModel`, `FishAudioTranscriptionModel`, `FishAudio*Tests.swift` |
| `@ai-sdk/fireworks` | `3.0.47` | `AIProviders.fireworks`, `FireworksProviderTests.swift` |
| `@ai-sdk/gateway` | `4.0.75` | `AIProviders.gateway`, `GatewayProvider`, `GatewayModels.swift`, `GatewayStreamingTranscriptionModel.swift`, `GatewayTests.swift`, `Gateway*UpstreamParityTests.swift` |
| `@ai-sdk/gmicloud` | `3.0.15` | `AIProviders.gmiCloud`, `GMICloudProvider`, `OpenAICompatibleChatModel`, `GMICloudProviderTests.swift` |
| `@ai-sdk/gladia` | `3.0.36` | `AIProviders.gladia`, `GladiaTranscriptionModel`, `GladiaProviderTests.swift` |
| `@ai-sdk/google` | `4.0.64` | `AIProviders.google`, `GoogleGenerativeAIProvider`, `GoogleGenerativeAI.swift`, `GoogleGenerativeMediaModels.swift`, `GoogleGenerativeAITests.swift`, `GoogleGenerativeAIMediaAndToolsTests.swift`, `GoogleBatchLanguageModel`, `GoogleBatchUpstreamTests.swift`, `GoogleGenerativeAIVideoAndInteractionsTests.swift` |
| `@ai-sdk/google-vertex` | `5.0.76` | `AIProviders.googleVertex`, `GoogleVertexProvider`, `GoogleVertexProvider.swift`, `GoogleVertexModels.swift`, `GoogleVertexTests.swift`, `GoogleVertexMediaAndMaaSTests.swift` |
| `@ai-sdk/groq` | `4.0.37` | `AIProviders.groq`, `GroqLanguageModel`, `GroqTranscriptionModel`, `GroqProviderTests.swift` |
| `@ai-sdk/huggingface` | `2.0.44` | `AIProviders.huggingFace`, `HuggingFaceProvider`, `HuggingFaceResponsesLanguageModel`, `HuggingFaceProviderTests.swift` |
| `@ai-sdk/hume` | `3.0.36` | `AIProviders.hume`, `HumeSpeechModel`, `HumeProviderTests.swift` |
| `@ai-sdk/klingai` | `4.0.38` | `AIProviders.klingAI`, `KlingAIVideoModel`, `KlingAIProviderTests.swift`, `MediaStatusRedirectUpstreamTests.swift` |
| `@ai-sdk/lmnt` | `3.0.36` | `AIProviders.lmnt`, `LMNTSpeechModel`, `LMNTProviderTests.swift` |
| `@ai-sdk/luma` | `3.0.37` | `AIProviders.luma`, `LumaImageModel`, `LumaProviderTests.swift` |
| `@ai-sdk/mcp` | `2.0.45` | `MCPClient`, `MCPHTTPTransport`, `MCPStdioTransport`, `MCPApps`, `MCPClientTests.swift`, `MCPOAuthTests.swift`, `MCPStdioTransportTests.swift`, `MCPModernProtocolTests.swift` |
| `@ai-sdk/minimax` | `3.0.25` | `AIProviders.miniMax`, `MiniMaxProvider`, `AnthropicLanguageModel`, `MiniMaxVideoModel`, `MiniMaxProviderTests.swift`, `MediaStatusRedirectUpstreamTests.swift` |
| `@ai-sdk/mistral` | `4.0.39` | `AIProviders.mistral`, `MistralLanguageModel`, `MistralEmbeddingModel`, `MistralTranscriptionModel`, `MistralSpeechModel`, `PerplexityMistralUpstreamTests.swift` |
| `@ai-sdk/moonshotai` | `3.0.45` | `AIProviders.moonshotAI`, `MoonshotLanguageModel`, `MoonshotAIProviderTests.swift` |
| `@ai-sdk/open-responses` | `2.0.39` | `AIProviders.openResponses`, `ResponsesRequestMode.openResponses`, `ResponsesEndpointTests.swift`, `OpenAIResponsesMessageConversionTests.swift` |
| `@ai-sdk/openai` | `4.0.60` | `AIProviders.openAI`, `OpenAICompatible*Model`, `OpenAITools`, `OpenAI*Tests.swift`, `FileAndSkillClientTests.swift`, `CoreOpenAIUpstream202609Tests.swift`, `OpenAIResponsesBatchV4UpstreamTests.swift` |
| `@ai-sdk/openai-compatible` | `3.0.44` | `AIProviders.openAICompatible`, `OpenAICompatibleProvider`, `OpenAICompatibleTests.swift` |
| `@ai-sdk/perplexity` | `4.0.39` | `AIProviders.perplexity`, `PerplexityLanguageModel`, `PerplexityEmbeddingModel`, `PerplexityMistralUpstreamTests.swift` |
| `@ai-sdk/prodia` | `2.0.37` | `AIProviders.prodia`, `ProdiaLanguageModel`, `ProdiaMediaModel`, `ProdiaProviderTests.swift` |
| `@ai-sdk/quiverai` | `2.0.36` | `AIProviders.quiverAI`, `QuiverAIImageModel`, `QuiverAIProviderTests.swift` |
| `@ai-sdk/replicate` | `3.0.37` | `AIProviders.replicate`, `ReplicateImageModel`, `ReplicateVideoModel`, `ReplicateProviderTests.swift` |
| `@ai-sdk/revai` | `3.0.36` | `AIProviders.revAI`, `RevAITranscriptionModel`, `RevAIProviderTests.swift` |
| `@ai-sdk/togetherai` | `3.0.45` | `AIProviders.togetherAI`, `TogetherAIImageModel`, `TogetherAIRerankingModel`, `TogetherAIProviderTests.swift` |
| `@ai-sdk/vercel` | `3.0.30` | `AIProviders.vercel`, `VercelProvider`, `ProviderRegistryVercelTests.swift` |
| `@ai-sdk/voyage` | `2.0.36` | `AIProviders.voyage`, `VoyageEmbeddingModel`, `VoyageRerankingModel`, `VoyageProviderOptionSchemaTests.swift` |
| `@ai-sdk/xai` | `4.0.54` | `AIProviders.xAI`, `XAIResponses.swift`, `XAIResponsesBatchLanguageModel.swift`, `XAITools`, `XAIImageModel`, `XAIVideoModel`, `XAIProviderTests.swift`, `ProviderGroupBUpstreamParity20260831Tests.swift` |
