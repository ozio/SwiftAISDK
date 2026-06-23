# Provider Capability Matrix

Snapshot date: 2026-06-23

This document is generated from `AIProviderCapabilities` in
`Sources/SwiftAISDK/Providers/ProviderCapabilityMatrix.swift`. Update that
file first when adding or changing provider coverage; the drift test will
fail until this document is regenerated from the same source.

Legend:

- `L`: language
- `C`: completion
- `E`: embedding
- `I`: image
- `T`: transcription
- `S`: speech
- `AG`: audio generation
- `AT`: audio transformation
- `D`: dubbing
- `V`: video
- `R`: reranking
- `F`: file upload client
- `K`: skill upload client

| Upstream package | Provider ID | Swift factories | L | C | E | I | T | S | AG | AT | D | V | R | F | K |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `@ai-sdk/alibaba` | `alibaba` | `AIProviders.alibaba` | ✅ |  | ✅ |  |  |  |  |  |  | ✅ |  |  |  |
| `@ai-sdk/amazon-bedrock` | `amazon-bedrock` | `AIProviders.amazonBedrock` | ✅ |  | ✅ | ✅ |  |  |  |  |  |  | ✅ |  |  |
| `@ai-sdk/amazon-bedrock` | `amazon-bedrock.anthropic` | `AIProviders.amazonBedrockAnthropic` | ✅ |  |  |  |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/amazon-bedrock` | `bedrock-mantle` | `AIProviders.bedrockMantle` | ✅ |  |  |  |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/anthropic` | `anthropic` | `AIProviders.anthropic` | ✅ |  |  |  |  |  |  |  |  |  |  | ✅ | ✅ |
| `@ai-sdk/anthropic-aws` | `anthropic-aws` | `AIProviders.anthropicAWS` | ✅ |  |  |  |  |  |  |  |  |  |  | ✅ | ✅ |
| `@ai-sdk/assemblyai` | `assemblyai` | `AIProviders.assemblyAI` |  |  |  |  | ✅ |  |  |  |  |  |  |  |  |
| `@ai-sdk/azure` | `azure` | `AIProviders.azure` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |  |  |  |  |  |  |  |
| `@ai-sdk/baseten` | `baseten` | `AIProviders.baseten` | ✅ |  | ✅ |  |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/black-forest-labs` | `black-forest-labs` | `AIProviders.blackForestLabs` |  |  |  | ✅ |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/bytedance` | `bytedance` | `AIProviders.byteDance` |  |  |  |  |  |  |  |  |  | ✅ |  |  |  |
| `@ai-sdk/cerebras` | `cerebras` | `AIProviders.cerebras` | ✅ |  |  |  |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/cohere` | `cohere` | `AIProviders.cohere` | ✅ |  | ✅ |  |  |  |  |  |  |  | ✅ |  |  |
| `@ai-sdk/deepgram` | `deepgram` | `AIProviders.deepgram` |  |  |  |  | ✅ | ✅ |  |  |  |  |  |  |  |
| `@ai-sdk/deepinfra` | `deepinfra` | `AIProviders.deepInfra` | ✅ | ✅ | ✅ | ✅ |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/deepseek` | `deepseek` | `AIProviders.deepSeek` | ✅ |  |  |  |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/elevenlabs` | `elevenlabs` | `AIProviders.elevenLabs` |  |  |  |  | ✅ | ✅ | ✅ | ✅ | ✅ |  |  |  |  |
| `@ai-sdk/fal` | `fal` | `AIProviders.fal` |  |  |  | ✅ | ✅ | ✅ |  |  |  | ✅ |  |  |  |
| `@ai-sdk/fireworks` | `fireworks` | `AIProviders.fireworks` | ✅ | ✅ | ✅ | ✅ |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/gateway` | `gateway` | `AIProviders.gateway` | ✅ |  | ✅ | ✅ | ✅ | ✅ |  |  |  | ✅ | ✅ |  |  |
| `@ai-sdk/gladia` | `gladia` | `AIProviders.gladia` |  |  |  |  | ✅ |  |  |  |  |  |  |  |  |
| `@ai-sdk/google` | `google.generative-ai` | `AIProviders.google` | ✅ |  | ✅ | ✅ |  |  |  |  |  | ✅ |  | ✅ |  |
| `@ai-sdk/google-vertex` | `google.vertex` | `AIProviders.googleVertex` | ✅ |  | ✅ | ✅ | ✅ |  |  |  |  | ✅ |  |  |  |
| `@ai-sdk/google-vertex` | `googleVertex.maas` | `AIProviders.googleVertexMaaS` | ✅ | ✅ | ✅ | ✅ |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/google-vertex` | `googleVertex.xai` | `AIProviders.googleVertexXAI` | ✅ |  |  |  |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/google-vertex` | `googleVertex.anthropic` | `AIProviders.googleVertexAnthropic` | ✅ |  |  |  |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/groq` | `groq` | `AIProviders.groq` | ✅ |  |  |  | ✅ |  |  |  |  |  |  |  |  |
| `@ai-sdk/huggingface` | `huggingface` | `AIProviders.huggingFace` | ✅ |  |  |  |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/hume` | `hume` | `AIProviders.hume` |  |  |  |  |  | ✅ |  |  |  |  |  |  |  |
| `@ai-sdk/klingai` | `klingai` | `AIProviders.klingAI` |  |  |  |  |  |  |  |  |  | ✅ |  |  |  |
| `@ai-sdk/lmnt` | `lmnt` | `AIProviders.lmnt` |  |  |  |  |  | ✅ |  |  |  |  |  |  |  |
| `@ai-sdk/luma` | `luma` | `AIProviders.luma` |  |  |  | ✅ |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/mistral` | `mistral` | `AIProviders.mistral` | ✅ |  | ✅ |  |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/moonshotai` | `moonshotai` | `AIProviders.moonshotAI` | ✅ |  |  |  |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/open-responses` | `open-responses.responses` | `AIProviders.openResponses` | ✅ |  |  |  |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/openai` | `openai` | `AIProviders.openAI` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |  |  |  |  |  | ✅ | ✅ |
| `@ai-sdk/openai-compatible` | `openai-compatible` | `AIProviders.openAICompatible` | ✅ | ✅ | ✅ | ✅ |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/perplexity` | `perplexity` | `AIProviders.perplexity` | ✅ |  |  |  |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/prodia` | `prodia` | `AIProviders.prodia` | ✅ |  |  | ✅ |  |  |  |  |  | ✅ |  |  |  |
| `@ai-sdk/quiverai` | `quiverai` | `AIProviders.quiverAI` |  |  |  | ✅ |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/replicate` | `replicate` | `AIProviders.replicate` |  |  |  | ✅ |  |  |  |  |  | ✅ |  |  |  |
| `@ai-sdk/revai` | `revai` | `AIProviders.revAI` |  |  |  |  | ✅ |  |  |  |  |  |  |  |  |
| `@ai-sdk/togetherai` | `togetherai` | `AIProviders.togetherAI` | ✅ | ✅ | ✅ | ✅ |  |  |  |  |  |  | ✅ |  |  |
| `@ai-sdk/vercel` | `vercel` | `AIProviders.vercel` | ✅ |  |  |  |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/voyage` | `voyage` | `AIProviders.voyage` |  |  | ✅ |  |  |  |  |  |  |  | ✅ |  |  |
| `@ai-sdk/xai` | `xai` | `AIProviders.xAI` | ✅ |  |  | ✅ |  |  |  |  |  | ✅ |  | ✅ |  |

## Provider Notes

| Provider ID | Note |
| --- | --- |
| `baseten` | `ProviderSettings.modelURL` selects dedicated Baseten endpoints: chat uses `/sync/v1`, rejects `/predict`, and falls back to the Model API for plain `/sync`, while embeddings require `/sync` or `/sync/v1` and mirror the upstream performance-client body plus 128-input batching. |
| `gateway` | Gateway also exposes model, credits, spend, and generation metadata management APIs. |
| `google.generative-ai` | Also exposes Gemini interactions models and agents. |
| `moonshotai` | Chat requests stream usage by default and maps `providerOptions.moonshotai` thinking/reasoningHistory through the upstream option schema. |
| `open-responses.responses` | Custom URL factory; provider ID is derived from the caller supplied name. Uses the upstream open-responses request builder, optional API key, versioned user-agent suffix, and the caller supplied providerOptions namespace. |
| `openai-compatible` | Generic OpenAI-compatible factory; caller supplies provider ID and base URL. |
| `togetherai` | Image generation mirrors upstream `maxImagesPerCall = 1`; image and reranking responses are validated against the upstream-focused JSON shapes. |

## Reality Gates

Use three gates when judging provider completeness:

1. The provider appears in `AIProviderCapabilities.all`.
2. Unit tests cover the request and response or stream shape for every
   supported capability in the matrix.
3. At least one opt-in live smoke test exists for representative
   providers and can be run with real keys.

The live smoke suite is intentionally off by default. Run it with:

```sh
LIVE_AI_TESTS=1 swift test --filter LiveProviderSmoke
```

The suite reads `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`,
`DEEPSEEK_API_KEY`, `ASSEMBLYAI_API_KEY`, `ELEVENLABS_API_KEY`,
and `OPENAI_COMPATIBLE_API_KEY`.
When running from Xcode, set them as test environment variables in the
scheme instead of Run/Profile arguments.
Override model IDs with
`LIVE_OPENAI_MODEL`, `LIVE_ANTHROPIC_MODEL`, `LIVE_GOOGLE_MODEL`,
`LIVE_DEEPSEEK_MODEL`, `LIVE_ASSEMBLYAI_MODEL`, `LIVE_OPENAI_COMPATIBLE_MODEL`,
`LIVE_OPENAI_COMPATIBLE_BASE_URL`, `LIVE_ELEVENLABS_SPEECH_MODEL`,
`LIVE_ELEVENLABS_TRANSCRIPTION_MODEL`, and `LIVE_ELEVENLABS_VOICE`.
It covers text generation, text streaming, executable generate/stream tool loops,
OpenAI-compatible generation/streaming/completion/tool loops/object generation,
AssemblyAI transcription, ElevenLabs speech/transcription/audio generation/audio
transformation/dubbing, and representative embeddings.
Embedding checks also read
`LIVE_OPENAI_EMBEDDING_MODEL` and `LIVE_GOOGLE_EMBEDDING_MODEL`.
