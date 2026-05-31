# Upstream Sync Guide

This is the working map for keeping this Swift package aligned with the
provider-facing packages in Vercel AI SDK (`@ai-sdk/*`). Use it as a playbook:
refresh upstream, choose one provider surface, port the behavior, add focused
tests, update the matrix, then commit and push the round.

## Current Snapshot

- npm provider search checked: 2026-05-31
- Discovery command:

  ```sh
  npm search "@ai-sdk" --json --searchlimit=250
  ```

- Upstream checkout: `/tmp/vercel-ai-sdk-upstream`
- Upstream commit pinned for this pass:

  ```text
  ab6d664 2026-05-29T17:54:18-07:00 Version Packages (canary) (#15714)
  ```

- Swift package: library-only SwiftPM package (`ai-sdk-port`)
- Verification command: `swift test`

## What Counts As In Scope

Port official `@ai-sdk/*` packages that are provider/model surfaces. Ignore UI,
framework adapters, schema helpers, tracing/dev tooling, and community packages
unless this Swift package explicitly grows those layers.

In scope provider packages:

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
@ai-sdk/open-responses
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

Out of scope by default:

```text
@ai-sdk/react, vue, angular, svelte, solid, rsc, mcp, langchain, llamaindex,
valibot, codemod, devtools, workflow, provider, provider-utils, ui-utils, otel
```

## Round Workflow

1. Refresh discovery:

   ```sh
   npm search "@ai-sdk" --json --searchlimit=250 \
     | jq -r '.[].name' \
     | rg '^@ai-sdk/'
   ```

2. Refresh upstream and record the pinned commit:

   ```sh
   git -C /tmp/vercel-ai-sdk-upstream pull --ff-only
   git -C /tmp/vercel-ai-sdk-upstream log -1 --format='%h %cI %s'
   ```

3. Pick one provider surface or one cross-cutting surface.
4. Read upstream tests before implementation files.
5. Port behavior in the closest existing Swift provider/model file.
6. Add focused tests in the closest split test file.
7. Run a narrow test filter, then `swift test`.
8. Update this guide if provider coverage, known gaps, or porting rules changed.
9. Commit and push the round.

Keep rounds small. A good round changes one provider, one capability, or one
shared behavior such as streaming, provider options, or provider IDs.

## Upstream Triage Commands

List official upstream package directories:

```sh
find /tmp/vercel-ai-sdk-upstream/packages -maxdepth 2 -type d -name src \
  | sed 's#/tmp/vercel-ai-sdk-upstream/packages/##; s#/src$##' \
  | sort
```

Show which provider packages changed since a previous pin:

```sh
git -C /tmp/vercel-ai-sdk-upstream diff --name-only <old-pin>..HEAD -- packages \
  | rg '^packages/[^/]+/src/' \
  | cut -d/ -f2 \
  | sort -u
```

Find provider factories, auth, model factories, and unsupported routes:

```sh
rg -n 'create|provider|baseURL|baseUrl|headers|apiKey|environmentVariableName|NoSuchModelError|new .*Model' \
  /tmp/vercel-ai-sdk-upstream/packages/<provider>/src
```

Find request/stream/tool behavior:

```sh
rg -n 'prepare|convert|providerOptions|providerDefinedTool|tool_choice|stream|usage|finishReason|reasoning' \
  /tmp/vercel-ai-sdk-upstream/packages/<provider>/src
```

Find Swift implementation and tests for the same surface:

```sh
rg -n '<provider>|providerID|baseURL|extraBody|providerOptions' Sources Tests
```

## Upstream Reading Order

Look in `/tmp/vercel-ai-sdk-upstream/packages/<provider>/src`.

| Open first | Why |
| --- | --- |
| `*.test.ts`, `*.test-d.ts`, `*.spec.ts` | Exact request bodies, URLs, warnings, aliases, and unsupported cases. |
| `index.ts` | Public names, aliases, exported tools, default factory. |
| `*provider.ts` | Provider ID, base URL, auth env vars, headers, model factory routing. |
| `*language-model*.ts` | Chat/messages/responses body conversion, parsing, streaming. |
| `*embedding*.ts` | Endpoint, batch limits, token usage, provider options. |
| `*image*.ts` | Generation/editing body shape and output media parsing. |
| `*transcription*.ts` | Multipart fields, audio response shape, timestamp options. |
| `*speech*.ts` | Audio format, voice defaults, response bytes. |
| `*video*.ts` | Job creation, polling, status mapping, assets. |
| `*tool*.ts` | Provider-defined tool names, beta headers, schema mapping. |
| Shared helpers under `packages/provider-utils` | Only when a provider imports helper behavior directly. |

Prefer upstream tests as the source of truth when implementation code is layered
or generated. If tests and implementation disagree, mirror runtime behavior and
add a Swift test that documents the decision.

## Provider Worksheet

Use this mini-template for every provider pass:

```text
Provider/package:
Upstream commit:
Upstream files read:
Swift files changed:
Capabilities touched:
Factory names/aliases:
Provider IDs:
Base URL/env/auth:
Request body differences:
Response/stream differences:
Provider-defined tools:
Unsupported-model behavior:
Swift tests added/updated:
Known gaps left:
```

## Swift Architecture Map

| Swift area | Files |
| --- | --- |
| Core protocols and request/response shapes | `Sources/ai-sdk-port/Core.swift` |
| JSON model used by request builders | `Sources/ai-sdk-port/JSONValue.swift` |
| HTTP transport, multipart, SSE/EventStream parsing | `Sources/ai-sdk-port/HTTP.swift` |
| Public provider registry | `Sources/ai-sdk-port/Providers/ProviderRegistry.swift` |
| OpenAI chat, responses, compatible models | `Sources/ai-sdk-port/Models/OpenAI*.swift`, `Sources/ai-sdk-port/Providers/OpenAICompatibleProvider.swift` |
| Anthropic and Bedrock/Vertex Anthropic behavior | `Sources/ai-sdk-port/Models/Anthropic.swift`, `Sources/ai-sdk-port/Providers/AnthropicAWSProvider.swift` |
| Google Gemini and Vertex Gemini behavior | `Sources/ai-sdk-port/Models/Google*.swift`, `Sources/ai-sdk-port/Providers/GoogleVertexProvider.swift` |
| Gateway behavior and management APIs | `Sources/ai-sdk-port/Models/GatewayModels.swift`, `Sources/ai-sdk-port/Providers/GatewayProvider.swift` |
| Bedrock native, Bedrock Anthropic, Mantle | `Sources/ai-sdk-port/Models/AmazonBedrockModels.swift`, `Sources/ai-sdk-port/Providers/AmazonBedrockProvider.swift` |
| Media and audio providers | `Sources/ai-sdk-port/Models/*Media*.swift`, `Sources/ai-sdk-port/Models/*Audio*.swift` |
| Files and skills clients | `Sources/ai-sdk-port/Models/FileClients.swift`, `Sources/ai-sdk-port/Models/OpenAISkills.swift` |
| Tests | `Tests/ai-sdk-portTests/*.swift` |

Tests are split by provider or feature surface. Add new coverage to the closest
existing file instead of rebuilding a large monolithic test.

Naming note: most model files now follow `*Models.swift`, `*Tools.swift`, or
`*Skills.swift`, but a few older family files are intentionally broader.
`OpenAICompatible.swift` is the shared engine for OpenAI-compatible language,
embedding, image, speech, transcription, and tool behavior. `Anthropic.swift`
currently includes Anthropic tools plus native, Vertex, and Bedrock Anthropic
model behavior. `GoogleGenerativeAI.swift` contains the direct Gemini family.
Treat those names as historical grouping, not as proof that a surface is
missing. When one of those files grows during a future provider pass, split only
the touched surface into the newer naming pattern.

## Translation Rules

| Upstream concept | Swift porting rule |
| --- | --- |
| Provider factory | Add or update an `AIProviders.<name>` entry point. Keep upstream aliases when they are public. |
| Provider ID | Match upstream provider IDs, including capability suffixes such as `.chat`, `.responses`, `.embedding`, `.image`, `.files`, or `.skills` when upstream uses them. |
| Settings object | Prefer extending `ProviderSettings` or the provider-specific settings type over ad hoc parameters. |
| Base URL | Preserve upstream defaults and env fallbacks. Tests should assert the final URL. |
| Auth headers | Preserve header names, bearer/API-key prefixes, and provider-specific override behavior. |
| Request body | Build structured `JSONValue` dictionaries. Avoid string assembly except for provider APIs that require encoded payloads. |
| Provider options | Read the upstream namespace (`openai`, `anthropic`, `google`, `amazonBedrock`, etc.) and strip provider-only options before forwarding generic extra body fields. |
| Tools | Keep provider-defined tool builders beside the provider model. Test both tool schema and required beta/header behavior. |
| Streaming | Reuse `HTTP.swift` parsers where possible. Add provider adapters only for genuinely different wire formats such as AWS EventStream. |
| Media/audio multipart | Use structured multipart helpers and assert fields, filenames, MIME type, and endpoint path. |
| Unsupported models | Throw `AIError.unsupportedModel` instead of silently routing to another capability. |

## Implementation Index

| Provider surface | Upstream package/files | Swift entry points | Main tests |
| --- | --- | --- | --- |
| OpenAI Chat | `@ai-sdk/openai`, chat model files | `AIProviders.openAI`, `OpenAICompatibleChatModel`, OpenAI tools | `OpenAIChatTests.swift`, `OpenAIMediaTests.swift` |
| OpenAI Responses | `@ai-sdk/openai`, responses model/tool files | `AIProviders.openAI`, `OpenAICompatibleResponsesModel`, `OpenAITools` | `OpenAIResponsesTests.swift`, `ResponsesEndpointTests.swift`, `NativeReasoningProviderTests.swift` |
| OpenAI Files/Skills | `@ai-sdk/openai` file and skill clients | `OpenAIFileClient`, `OpenAISkillsClient` | `FileAndSkillClientTests.swift` |
| Azure OpenAI | `@ai-sdk/azure` | `AIProviders.azureOpenAI`, `AzureOpenAIProvider`, `AzureOpenAITools` | `AlibabaProdiaAzureQuiverTests.swift`, `OpenAIResponsesTests.swift` |
| OpenAI-compatible providers | `@ai-sdk/openai-compatible`, `deepseek`, `togetherai`, `groq`, `perplexity`, `fireworks`, `deepinfra`, `baseten`, `cerebras`, `moonshotai` | `OpenAICompatibleProvider`, provider-specific registry helpers | `OpenAICompatibleTests.swift`, `ProviderRegistryVercelTests.swift`, `CohereMistralVoyageTests.swift` |
| xAI | `@ai-sdk/xai` | `AIProviders.xAI`, `XAITools`, OpenAI-compatible chat/responses models | `OpenAICompatibleTests.swift` |
| Anthropic | `@ai-sdk/anthropic` | `AIProviders.anthropic`, `AnthropicLanguageModel`, `AnthropicTools` | `AnthropicTests.swift`, `AnthropicStreamingAndClientsTests.swift` |
| Anthropic AWS | `packages/anthropic-aws/src` | `AIProviders.anthropicAWS`, `AnthropicAWSProvider` | `AnthropicStreamingAndClientsTests.swift` |
| Amazon Bedrock native | `@ai-sdk/amazon-bedrock` | `AIProviders.amazonBedrock`, `AmazonBedrockLanguageModel`, `AmazonBedrockEmbeddingModel`, `AmazonBedrockImageModel`, `AmazonBedrockRerankingModel` | `AmazonBedrockTests.swift` |
| Bedrock Anthropic | `@ai-sdk/amazon-bedrock/src/anthropic/*` | `AIProviders.amazonBedrockAnthropic`, `AmazonBedrockAnthropicProvider`, `AmazonBedrockAnthropicLanguageModel` | `AmazonBedrockTests.swift` |
| Bedrock Mantle | `@ai-sdk/amazon-bedrock/src/mantle/*` | `AIProviders.bedrockMantle`, `AIProviders.amazonBedrockMantle`, OpenAI-compatible chat/responses models with AWS auth | `AmazonBedrockTests.swift` |
| Google Gemini | `@ai-sdk/google` | `AIProviders.google`, `GoogleGenerativeAIModel`, `GoogleTools` | `GoogleGenerativeAITests.swift` |
| Google Vertex | `@ai-sdk/google-vertex` | `AIProviders.googleVertex`, `GoogleVertexProvider`, `GoogleVertexAnthropicProvider`, `GoogleVertexTools`, `GoogleVertexAnthropicTools` | `GoogleVertexTests.swift` |
| AI Gateway | `@ai-sdk/gateway` | `AIProviders.gateway`, `GatewayProvider`, `GatewayTools`, `GatewayManagementClient` | `GatewayTests.swift` |
| Mistral, Cohere, Voyage | `@ai-sdk/mistral`, `@ai-sdk/cohere`, `@ai-sdk/voyage` | Provider-specific Swift models plus registry helpers | `CohereMistralVoyageTests.swift` |
| Vercel | `@ai-sdk/vercel` | `AIProviders.vercel`, Vercel chat and image models | `ProviderRegistryVercelTests.swift` |
| Hugging Face | `@ai-sdk/huggingface` | `AIProviders.huggingFace`, image model | `ProviderRegistryVercelTests.swift` |
| Replicate and fal | `@ai-sdk/replicate`, `@ai-sdk/fal` | Provider-specific media models | `ReplicateFalTests.swift` |
| Alibaba, Prodia, Quiver, Luma, Kling, ByteDance | `@ai-sdk/alibaba`, `prodia`, `quiverai`, `luma`, `klingai`, `bytedance` | Provider-specific media/video models | `AlibabaProdiaAzureQuiverTests.swift`, `ImageVideoProviderTests.swift`, `NativeMediaProviderTests.swift` |
| Black Forest Labs | `@ai-sdk/black-forest-labs` | Native image provider | `ImageVideoProviderTests.swift`, `NativeMediaProviderTests.swift` |
| Deepgram, ElevenLabs, Hume, LMNT, RevAI, Gladia, AssemblyAI | Audio provider packages | Provider-specific transcription/speech models | `AudioProviderTests.swift` |

## Cross-Cutting Surfaces

| Surface | Current rule |
| --- | --- |
| Provider-defined tools | Tool builders live near their provider: `OpenAITools`, `AzureOpenAITools`, `AnthropicTools`, `GoogleTools`, `GoogleVertexTools`, `GoogleVertexAnthropicTools`, `GatewayTools`, `GroqTools`, `XAITools`. |
| Tool headers and beta flags | Match upstream tests. Anthropic-on-Bedrock uses body `anthropic_beta`; regular Anthropic uses headers. |
| OpenAI-compatible providers | Share the compatible model implementation, but keep provider-specific defaults, path quirks, headers, tools, and provider IDs explicit. |
| Provider options | Preserve upstream namespaces and avoid leaking provider-specific options into unrelated providers. |
| Auth and provider settings | Mirror upstream env var names, base URL fallbacks, and header strategy. OpenAI settings include `OPENAI_BASE_URL`, organization, and project headers. |
| AWS providers | Keep SigV4 service name, region, path encoding, and EventStream parsing covered by tests. |
| Error behavior | Convert provider errors into `AIError` with the surface provider ID that failed. |

## Pre-Commit Checklist

- Public factory and aliases match upstream exports.
- Supported capabilities match upstream model methods.
- Provider IDs match upstream, including capability suffixes where present.
- Default base URL, env var names, auth headers, and query parameters match.
- Request body conversion is covered for normal generation plus tools,
  provider options, reasoning, media, and structured output where applicable.
- Response parsing covers text, tool calls, reasoning, sources, warnings,
  finish reason, usage, and provider metadata where applicable.
- Streaming covers deltas, tool-call chunks, usage, finish events, and provider
  error events.
- Provider-defined tools include upstream name/type/schema mapping and beta
  header/body behavior.
- Focused tests cover at least one request and one response/stream for each new
  or changed surface.
- `swift test` passes.
- This guide's snapshot, index, or known gaps are updated if the pass changed
  provider coverage.

## Known Gaps And Next Passes

- Continue comparing upstream provider test suites for small model-specific
  request flags, provider IDs, warnings, and error normalization.
- Keep OpenAI and Azure surface IDs aligned with upstream capability-specific
  IDs (`.chat`, `.responses`, `.completion`, `.embedding`, `.image`,
  `.transcription`, `.speech`, `.files`, `.skills`).
- Bedrock Anthropic supports invoke and streaming paths; deeper parity can still
  expand around model-specific exclusions and structured output details.
- Keep file-management and skill clients aligned if upstream adds operations
  beyond the current OpenAI-oriented clients.
- Refresh npm search before each substantial provider pass so newly published
  official providers are not missed.
