# Provider Capability Matrix

Snapshot date: 2026-05-31

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
- `V`: video
- `R`: reranking
- `F`: file upload client
- `K`: skill upload client

| Upstream package | Provider ID | Swift factories | L | C | E | I | T | S | V | R | F | K |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `@ai-sdk/alibaba` | `alibaba` | `AIProviders.alibaba` | yes |  |  |  |  |  | yes |  |  |  |
| `@ai-sdk/amazon-bedrock` | `amazon-bedrock` | `AIProviders.amazonBedrock` | yes |  | yes | yes |  |  |  | yes |  |  |
| `@ai-sdk/amazon-bedrock` | `amazon-bedrock.anthropic` | `AIProviders.amazonBedrockAnthropic` | yes |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/amazon-bedrock` | `bedrock-mantle` | `AIProviders.bedrockMantle`, `AIProviders.amazonBedrockMantle` | yes |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/anthropic` | `anthropic` | `AIProviders.anthropic` | yes |  |  |  |  |  |  |  | yes | yes |
| `@ai-sdk/anthropic-aws` | `anthropic-aws` | `AIProviders.anthropicAWS`, `AIProviders.anthropicAws` | yes |  |  |  |  |  |  |  | yes | yes |
| `@ai-sdk/assemblyai` | `assemblyai` | `AIProviders.assemblyAI`, `AIProviders.assemblyai` |  |  |  |  | yes |  |  |  |  |  |
| `@ai-sdk/azure` | `azure` | `AIProviders.azure` | yes | yes | yes | yes | yes | yes |  |  |  |  |
| `@ai-sdk/baseten` | `baseten` | `AIProviders.baseten` | yes |  | yes |  |  |  |  |  |  |  |
| `@ai-sdk/black-forest-labs` | `black-forest-labs` | `AIProviders.blackForestLabs` |  |  |  | yes |  |  |  |  |  |  |
| `@ai-sdk/bytedance` | `bytedance` | `AIProviders.byteDance`, `AIProviders.bytedance` |  |  |  |  |  |  | yes |  |  |  |
| `@ai-sdk/cerebras` | `cerebras` | `AIProviders.cerebras` | yes |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/cohere` | `cohere` | `AIProviders.cohere` | yes |  | yes |  |  |  |  | yes |  |  |
| `@ai-sdk/deepgram` | `deepgram` | `AIProviders.deepgram` |  |  |  |  | yes | yes |  |  |  |  |
| `@ai-sdk/deepinfra` | `deepinfra` | `AIProviders.deepInfra`, `AIProviders.deepinfra` | yes | yes | yes | yes |  |  |  |  |  |  |
| `@ai-sdk/deepseek` | `deepseek` | `AIProviders.deepSeek`, `AIProviders.deepseek` | yes |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/elevenlabs` | `elevenlabs` | `AIProviders.elevenLabs`, `AIProviders.elevenlabs` |  |  |  |  | yes | yes |  |  |  |  |
| `@ai-sdk/fal` | `fal` | `AIProviders.fal` |  |  |  | yes | yes | yes | yes |  |  |  |
| `@ai-sdk/fireworks` | `fireworks` | `AIProviders.fireworks` | yes | yes | yes | yes |  |  |  |  |  |  |
| `@ai-sdk/gateway` | `gateway` | `AIProviders.gateway` | yes | yes | yes | yes | yes | yes | yes | yes |  |  |
| `@ai-sdk/gladia` | `gladia` | `AIProviders.gladia` |  |  |  |  | yes |  |  |  |  |  |
| `@ai-sdk/google` | `google.generative-ai` | `AIProviders.google` | yes |  | yes | yes |  |  | yes |  | yes |  |
| `@ai-sdk/google-vertex` | `google.vertex` | `AIProviders.googleVertex` | yes |  | yes | yes |  |  | yes |  |  |  |
| `@ai-sdk/google-vertex` | `googleVertex.maas` | `AIProviders.googleVertexMaaS` | yes | yes | yes | yes |  |  |  |  |  |  |
| `@ai-sdk/google-vertex` | `googleVertex.xai` | `AIProviders.googleVertexXAI` | yes |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/google-vertex` | `googleVertex.anthropic` | `AIProviders.googleVertexAnthropic` | yes |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/groq` | `groq` | `AIProviders.groq` | yes |  |  |  | yes |  |  |  |  |  |
| `@ai-sdk/huggingface` | `huggingface` | `AIProviders.huggingFace`, `AIProviders.huggingface` | yes |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/hume` | `hume` | `AIProviders.hume` |  |  |  |  |  | yes |  |  |  |  |
| `@ai-sdk/klingai` | `klingai` | `AIProviders.klingAI`, `AIProviders.klingai` |  |  |  |  |  |  | yes |  |  |  |
| `@ai-sdk/lmnt` | `lmnt` | `AIProviders.lmnt` |  |  |  |  |  | yes |  |  |  |  |
| `@ai-sdk/luma` | `luma` | `AIProviders.luma` |  |  |  | yes |  |  |  |  |  |  |
| `@ai-sdk/mistral` | `mistral` | `AIProviders.mistral` | yes |  | yes |  |  |  |  |  |  |  |
| `@ai-sdk/moonshotai` | `moonshotai` | `AIProviders.moonshotAI`, `AIProviders.moonshotai` | yes |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/open-responses` | `open-responses.responses` | `AIProviders.openResponses` | yes |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/openai` | `openai` | `AIProviders.openAI`, `AIProviders.openai` | yes | yes | yes | yes | yes | yes |  |  | yes | yes |
| `@ai-sdk/openai-compatible` | `openai-compatible` | `AIProviders.openAICompatible`, `AIProviders.openaiCompatible` | yes | yes | yes | yes |  |  |  |  |  |  |
| `@ai-sdk/perplexity` | `perplexity` | `AIProviders.perplexity` | yes |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/prodia` | `prodia` | `AIProviders.prodia` | yes |  |  | yes |  |  | yes |  |  |  |
| `@ai-sdk/quiverai` | `quiverai` | `AIProviders.quiverAI`, `AIProviders.quiverai` |  |  |  | yes |  |  |  |  |  |  |
| `@ai-sdk/replicate` | `replicate` | `AIProviders.replicate` |  |  |  | yes |  |  | yes |  |  |  |
| `@ai-sdk/revai` | `revai` | `AIProviders.revAI`, `AIProviders.revai` |  |  |  |  | yes |  |  |  |  |  |
| `@ai-sdk/togetherai` | `togetherai` | `AIProviders.togetherAI`, `AIProviders.togetherai` | yes | yes | yes | yes |  |  |  | yes |  |  |
| `@ai-sdk/vercel` | `vercel` | `AIProviders.vercel` | yes |  |  |  |  |  |  |  |  |  |
| `@ai-sdk/voyage` | `voyage` | `AIProviders.voyage` |  |  | yes |  |  |  |  | yes |  |  |
| `@ai-sdk/xai` | `xai` | `AIProviders.xAI`, `AIProviders.xai` | yes |  |  | yes |  |  | yes |  | yes |  |

## Provider Notes

| Provider ID | Note |
| --- | --- |
| `baseten` | `ProviderSettings.modelURL` selects dedicated Baseten endpoints: chat uses `/sync/v1`, rejects `/predict`, and falls back to the Model API for plain `/sync`, while embeddings require `/sync` or `/sync/v1`. |
| `gateway` | Gateway also exposes model, credits, spend, and generation metadata management APIs. |
| `google.generative-ai` | Also exposes Gemini interactions models and agents. |
| `moonshotai` | Chat requests stream usage by default and maps `providerOptions.moonshotai` thinking/reasoningHistory through the upstream option schema. |
| `open-responses.responses` | Custom URL factory; provider ID is derived from the caller supplied name. |
| `openai-compatible` | Generic OpenAI-compatible factory; caller supplies provider ID and base URL. |

## Reality Gates

Use three gates when judging provider completeness:

1. The provider appears in `AIProviderCapabilities.all`.
2. Unit tests cover the request and response or stream shape for every
   supported capability in the matrix.
3. At least one opt-in live smoke test exists for representative first-party
   providers and can be run with real keys.

The live smoke suite is intentionally off by default. Run it with:

```sh
LIVE_AI_TESTS=1 swift test --filter LiveProviderSmoke
```

The suite reads `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, and `GEMINI_API_KEY`
first, then falls back to `openai-api-key.txt`, `claude-api-key.txt`, and
`gemini-api-key.txt` in the package root. Override model IDs with
`LIVE_OPENAI_MODEL`, `LIVE_ANTHROPIC_MODEL`, and `LIVE_GOOGLE_MODEL`.
It covers text generation, text streaming, executable generate/stream tool loops, and
representative embeddings. Embedding checks also read
`LIVE_OPENAI_EMBEDDING_MODEL` and `LIVE_GOOGLE_EMBEDDING_MODEL`.
