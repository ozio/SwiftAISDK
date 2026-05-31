# Upstream Sync Guide

This document is the map for keeping the Swift package aligned with the
provider-facing parts of Vercel AI SDK (`@ai-sdk/*`). It is intentionally a
working guide, not a historical changelog.

## Current Snapshot

- npm provider search checked: 2026-05-31
- Command used: `npm search "@ai-sdk" --json --searchlimit=100`
- Upstream source checkout: `/tmp/vercel-ai-sdk-upstream`
- Upstream commit used for the current pass:

  ```text
  ab6d664 2026-05-29T17:54:18-07:00 Version Packages (canary) (#15714)
  ```

- Swift verification command: `swift test`

## Scope Rule

Port official `@ai-sdk/*` packages when the npm package is provider/model
oriented. Exclude UI, framework adapters, schema helpers, dev tooling, and
third-party community packages unless the Swift package grows that layer.

In scope:

```text
@ai-sdk/alibaba
@ai-sdk/amazon-bedrock
@ai-sdk/anthropic
@ai-sdk/assemblyai
@ai-sdk/azure
@ai-sdk/baseten
@ai-sdk/black-forest-labs
@ai-sdk/bytedance
@ai-sdk/cerebras
@ai-sdk/cohere
@ai-sdk/deepgram
@ai-sdk/deepinfra
@ai-sdk/deepseek
@ai-sdk/elevenlabs
@ai-sdk/fal
@ai-sdk/fireworks
@ai-sdk/gateway
@ai-sdk/gladia
@ai-sdk/google
@ai-sdk/google-vertex
@ai-sdk/groq
@ai-sdk/huggingface
@ai-sdk/hume
@ai-sdk/klingai
@ai-sdk/lmnt
@ai-sdk/luma
@ai-sdk/mistral
@ai-sdk/moonshotai
@ai-sdk/openai
@ai-sdk/openai-compatible
@ai-sdk/perplexity
@ai-sdk/prodia
@ai-sdk/quiverai
@ai-sdk/replicate
@ai-sdk/revai
@ai-sdk/togetherai
@ai-sdk/vercel
@ai-sdk/voyage
@ai-sdk/xai
```

Out of scope by default: `@ai-sdk/react`, `vue`, `angular`, `svelte`, `rsc`,
`mcp`, `langchain`, `llamaindex`, `valibot`, `codemod`, `devtools`, and
similar adapter/tooling packages.

## Refresh Workflow

1. Refresh package discovery:

   ```sh
   npm search "@ai-sdk" --json --searchlimit=100
   ```

2. Refresh upstream:

   ```sh
   git -C /tmp/vercel-ai-sdk-upstream pull --ff-only
   git -C /tmp/vercel-ai-sdk-upstream log -1 --format='%h %cI %s'
   ```

3. For each changed provider, inspect `src/index.ts`, `*provider.ts`,
   model files, tool files, and tests.
4. Port request body conversion, endpoint selection, headers/auth, response
   parsing, streaming events, model aliases, and unsupported-model behavior.
5. Add focused Swift tests next to the existing provider tests.
6. Update this document's matrix when a provider surface changes.
7. Run `swift test`, then commit and push the round.

## Upstream Reading Order

Look in `/tmp/vercel-ai-sdk-upstream/packages/<provider>/src`.

| Upstream file | What to copy into Swift |
| --- | --- |
| `index.ts` | Public exports, factory names, aliases |
| `*provider.ts` | Base URL, auth env vars, headers, model factories |
| `*language-model*.ts` | Chat/generate request body, response parsing, streaming |
| `*embedding*.ts` | Embedding endpoint, input mapping, token usage |
| `*image*.ts` | Image generation/editing request and output media parsing |
| `*transcription*.ts` | Audio transcription endpoint and response shape |
| `*speech*.ts` | Speech endpoint and audio response handling |
| `*video*.ts` | Video job creation, polling, and asset response handling |
| `*tool*.ts` | Provider-defined tool schemas, beta headers, name/type mapping |
| `*.test.ts` | Exact request/response examples to mirror in Swift tests |

Useful searches:

```sh
rg -n 'baseURL|environmentVariableName|headers|new .*Model|NoSuchModelError' \
  /tmp/vercel-ai-sdk-upstream/packages/<provider>/src

rg -n 'providerDefinedTool|prepareTools|tool_choice|stream|usage' \
  /tmp/vercel-ai-sdk-upstream/packages/<provider>/src
```

## Swift Architecture Map

| Swift area | Files |
| --- | --- |
| Core protocols and request/response shapes | `Sources/ai-sdk-port/Core.swift` |
| HTTP transport, multipart, SSE/EventStream parsing | `Sources/ai-sdk-port/HTTP.swift` |
| Public provider registry | `Sources/ai-sdk-port/Providers/ProviderRegistry.swift` |
| OpenAI chat, responses, compatible providers | `Sources/ai-sdk-port/Models/OpenAI*.swift` |
| Anthropic and Bedrock/Vertex Anthropic behavior | `Sources/ai-sdk-port/Models/Anthropic.swift` |
| Google Gemini and Vertex Gemini behavior | `Sources/ai-sdk-port/Models/Google*.swift` |
| Gateway behavior and management APIs | `Sources/ai-sdk-port/Models/GatewayModels.swift`, `Sources/ai-sdk-port/Providers/GatewayProvider.swift` |
| Bedrock native models | `Sources/ai-sdk-port/Models/AmazonBedrockModels.swift` |
| Image, video, audio, file, and skill clients | `Sources/ai-sdk-port/Models/*Media*.swift`, `Sources/ai-sdk-port/Models/*Audio*.swift`, `Sources/ai-sdk-port/Models/FileClients.swift`, `Sources/ai-sdk-port/Models/OpenAISkills.swift` |
| Provider entry points | `Sources/ai-sdk-port/Providers/*.swift` |
| Tests | `Tests/ai-sdk-portTests/*.swift` |

Tests are split by provider or feature surface. Keep new tests in the closest
existing file instead of recreating a monolithic test suite.

## Provider Coverage Matrix

| Provider surface | Upstream package/files | Swift entry points | Main tests |
| --- | --- | --- | --- |
| OpenAI Chat | `@ai-sdk/openai`, chat model files | `AIProviders.openai`, `OpenAIChatLanguageModel`, `OpenAIProvider` | `OpenAIChatTests.swift`, `OpenAIMediaTests.swift` |
| OpenAI Responses | `@ai-sdk/openai`, responses model/tool files | `OpenAIResponsesLanguageModel`, `OpenAITools` | `OpenAIResponsesTests.swift`, `ResponsesEndpointTests.swift`, `NativeReasoningProviderTests.swift` |
| Azure OpenAI | `@ai-sdk/azure` | `AIProviders.azureOpenAI`, `AzureOpenAIProvider`, `AzureOpenAITools` | `AlibabaProdiaAzureQuiverTests.swift`, `OpenAIResponsesTests.swift` |
| OpenAI-compatible providers | `@ai-sdk/openai-compatible`, `deepseek`, `togetherai`, `groq`, `perplexity`, `fireworks`, `deepinfra`, `baseten`, `cerebras`, `moonshotai` | `OpenAICompatibleProvider`, provider-specific registry helpers | `OpenAICompatibleTests.swift`, `ProviderRegistryVercelTests.swift`, `CohereMistralVoyageTests.swift` |
| xAI | `@ai-sdk/xai` | `AIProviders.xai`, `XAITools`, OpenAI-compatible chat/responses models | `OpenAICompatibleTests.swift` |
| Anthropic | `@ai-sdk/anthropic` | `AIProviders.anthropic`, `AnthropicLanguageModel`, `AnthropicTools` | `AnthropicTests.swift`, `AnthropicStreamingAndClientsTests.swift` |
| Anthropic AWS | `@ai-sdk/anthropic` AWS provider surface | `AIProviders.anthropicAWS`, `AnthropicAWSProvider` | `AnthropicStreamingAndClientsTests.swift` |
| Bedrock Anthropic | `@ai-sdk/amazon-bedrock/src/anthropic/*` | `AIProviders.amazonBedrockAnthropic`, `AmazonBedrockAnthropicProvider`, `AmazonBedrockAnthropicLanguageModel` | `AmazonBedrockTests.swift` |
| Google Gemini | `@ai-sdk/google` | `AIProviders.google`, `GoogleGenerativeAIModel`, `GoogleTools` | `GoogleGenerativeAITests.swift` |
| Google Vertex | `@ai-sdk/google-vertex` | `AIProviders.googleVertex`, `GoogleVertexProvider`, `GoogleVertexAnthropicProvider`, `GoogleVertexTools`, `GoogleVertexAnthropicTools` | `GoogleVertexTests.swift` |
| AI Gateway | `@ai-sdk/gateway` | `AIProviders.gateway`, `GatewayProvider`, `GatewayTools`, `GatewayManagementClient` | `GatewayTests.swift` |
| Amazon Bedrock native | `@ai-sdk/amazon-bedrock` | `AIProviders.amazonBedrock`, `AmazonBedrockLanguageModel`, `AmazonBedrockEmbeddingModel`, `AmazonBedrockImageModel`, `AmazonBedrockRerankingModel` | `AmazonBedrockTests.swift` |
| Mistral, Cohere, Voyage | `@ai-sdk/mistral`, `@ai-sdk/cohere`, `@ai-sdk/voyage` | Provider-specific Swift providers and models | `CohereMistralVoyageTests.swift` |
| Vercel | `@ai-sdk/vercel` | `AIProviders.vercel`, Vercel chat and image models | `ProviderRegistryVercelTests.swift` |
| Hugging Face | `@ai-sdk/huggingface` | `AIProviders.huggingFace`, image model | `ProviderRegistryVercelTests.swift` |
| Replicate and fal | `@ai-sdk/replicate`, `@ai-sdk/fal` | Provider-specific media models | `ReplicateFalTests.swift` |
| Alibaba, Prodia, Quiver, Luma, Kling, ByteDance | `@ai-sdk/alibaba`, `prodia`, `quiverai`, `luma`, `klingai`, `bytedance` | Provider-specific media/video models | `AlibabaProdiaAzureQuiverTests.swift`, `ImageVideoProviderTests.swift`, `NativeMediaProviderTests.swift` |
| Black Forest Labs | `@ai-sdk/black-forest-labs` | Native image provider | `ImageVideoProviderTests.swift`, `NativeMediaProviderTests.swift` |
| Deepgram, ElevenLabs, Hume, LMNT, RevAI, Gladia, AssemblyAI | Audio provider packages | Provider-specific transcription/speech models | `AudioProviderTests.swift` |
| Files and Skills | Upstream OpenAI file/skills surfaces | `OpenAIFileClient`, `OpenAISkillsClient` | `FileAndSkillClientTests.swift` |

## Cross-Cutting Surfaces

| Surface | Swift implementation notes |
| --- | --- |
| Provider-defined tools | Tool builders live near the provider they belong to: `OpenAITools`, `AzureOpenAITools`, `AnthropicTools`, `GoogleTools`, `GoogleVertexTools`, `GoogleVertexAnthropicTools`, `GatewayTools`, `GroqTools`, `XAITools`. |
| Tool headers and beta flags | Keep beta header/body behavior close to upstream tests. Anthropic-on-Bedrock uses body `anthropic_beta`; regular Anthropic uses headers. |
| Streaming | Prefer central parsers in `HTTP.swift` when possible. Bedrock Anthropic converts AWS EventStream `chunk.bytes` payloads back into Anthropic event lines before reuse. |
| OpenAI-compatible providers | Share the compatible model implementation, but keep provider-specific defaults, path quirks, headers, and tools explicit in provider setup. |
| Provider options | Preserve upstream option namespaces and wire them into request body conversion without leaking unknown options into unrelated providers. |
| Auth | Mirror upstream env var names and header strategy. Tests should assert the final header for each provider family. |
| Unsupported models | Provider methods should throw unsupported-model errors rather than silently routing to the wrong model kind. |

## Porting Checklist

- Public factory added to `AIProviders`.
- Provider class exposes the same supported model methods and aliases as upstream.
- Default base URL, env var names, and auth headers match upstream.
- Request body matches upstream tests for normal generation, tools, provider
  options, reasoning, media, and structured output where applicable.
- Response parsing covers text, tool calls, reasoning, sources, warnings,
  finish reason, and usage metadata.
- Streaming covers deltas, tool-call chunks, usage, finish events, and provider
  error events.
- Provider-defined tools include upstream type/name/schema mapping and beta
  header/body behavior.
- Focused tests cover at least one request body and one response for each new
  or changed surface.
- `swift test` passes.
- Matrix and snapshot notes are updated before committing.

## Known Gaps And Next Passes

- Continue comparing upstream provider test suites for small model-specific
  request flags and error normalization behavior.
- Bedrock Anthropic now supports invoke and streaming paths; deeper upstream
  parity can still be expanded around model-specific exclusions and structured
  output details.
- Keep file-management and skill surfaces aligned if upstream adds new
  operations beyond the current OpenAI-oriented clients.
- Refresh npm search before each substantial provider pass so newly published
  official providers are not missed.
