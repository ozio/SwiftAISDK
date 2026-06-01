# Upstream Sync Guide

This is the working map for keeping this Swift package aligned with the
provider-facing packages in Vercel AI SDK (`@ai-sdk/*`). Use it as a playbook:
refresh upstream, choose one provider surface, port the behavior, add focused
tests, update the matrix, then commit and push the round.

## Current Snapshot

- npm provider search checked: 2026-06-01
- Discovery command:

  ```sh
  npm search "@ai-sdk" --json --searchlimit=250
  ```

- Upstream checkout: `/tmp/vercel-ai-sdk-upstream`
- Upstream commit pinned for this pass:

  ```text
  ab6d664 2026-05-29T17:54:18-07:00 Version Packages (canary) (#15714)
  ```

- Swift package: library-only SwiftPM package (`SwiftAISDK`)
- Verification command: `swift test`

## Sync Manifest

| Artifact | Purpose | Update When |
| --- | --- | --- |
| `Sources/SwiftAISDK/Providers/ProviderRegistry.swift` | Public provider factories, aliases, auth, base URLs, and provider-level capability sets. | A provider package is added, removed, renamed, or changes supported model families. |
| `Sources/SwiftAISDK/Providers/ProviderCapabilityMatrix.swift` | Machine-readable product coverage for provider packages, Swift factories, capabilities, files, and skills. | Any provider capability or factory changes. |
| `Docs/ProviderCapabilityMatrix.md` | Generated human-readable coverage table and live-smoke instructions. | The source matrix changes; keep it equal to `AIProviderCapabilities.markdownDocument()`. |
| `Tests/SwiftAISDKTests/*` | Wire-shape, response, stream, warning, and registry evidence. | Every behavior port. |
| `Tests/SwiftAISDKTests/LiveProviderSmokeTests.swift` | Opt-in real-provider health checks. | Representative live coverage changes. |

Treat the matrix as the product inventory, not as marketing copy. A provider is
not "covered" unless the registry, source matrix, generated document, and tests
agree.

## What Counts As In Scope

Port official `@ai-sdk/*` packages that are provider/model surfaces. Ignore UI,
framework adapters, schema helpers, tracing/dev tooling, and community packages
unless this Swift package explicitly grows those layers.

In scope provider packages:

```text
@ai-sdk/alibaba
@ai-sdk/amazon-bedrock
@ai-sdk/anthropic
@ai-sdk/anthropic-aws
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
@ai-sdk/react, vue, angular, svelte, solid, rsc, langchain, llamaindex,
valibot, codemod, devtools, workflow, provider, provider-utils, ui-utils, otel
```

`@ai-sdk/mcp` is not a model provider, but it is in scope for the Swift core
tool bridge. Keep `MCPClient` aligned with `packages/mcp/src/tool/mcp-client.ts`
when upstream changes initialize, tool discovery, tool execution, resources,
prompts, or elicitation behavior.

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

3. Pick exactly one provider package for a provider-complete pass, unless the
   change is truly cross-cutting.
4. Read upstream tests before implementation files.
5. Port behavior in the closest existing Swift provider/model file.
6. Add focused tests in the closest split test file.
7. Run a narrow test filter, then `swift test`.
8. Update `AIProviderCapabilities` and `Docs/ProviderCapabilityMatrix.md` if
   provider coverage changed.
9. Update this guide if provider coverage, known gaps, or porting rules changed.
10. Commit and push the round.

Keep rounds small, but finish the chosen provider before moving to another
provider. A provider-complete pass may touch multiple capabilities for that
provider; avoid mixing unrelated provider fixes into the same commit.

## Provider-Complete Definition of Done

For each provider package, work through this checklist before calling the pass
complete:

- Public factory names, aliases, default model constructors, provider IDs, base
  URLs, environment variables, and auth/header behavior match upstream.
- Every upstream model surface exposed by the provider is represented in Swift
  or explicitly listed as a known gap: language, responses, embeddings,
  reranking, image, video, transcription, speech, files, and skills.
- Request preparation matches upstream for standard call settings, provider
  options, deprecated option namespaces, structured outputs, provider-defined
  tools, tool choice, multipart fields, polling bodies, and unsupported-setting
  warnings.
- Generate and stream parsing preserve text, reasoning, tool calls, sources,
  files, usage, finish reasons, raw values, response/request metadata, provider
  metadata, and raw chunks where upstream exposes them.
- Streams emit v4 lifecycle parts where upstream does: stream start, text and
  reasoning start/delta/end, tool input start/delta/end, sources, errors, and
  finish metadata.
- Abort signals are forwarded through direct requests, stream requests,
  multipart uploads, submit/poll loops, downloads, and retry sleeps.
- Error mapping preserves provider status, headers, and body details through the
  shared HTTP error path.
- Focused Swift tests cover request shape, warnings, response parsing, stream
  lifecycle, metadata, abort propagation, and at least one unsupported-model or
  invalid-response case where upstream has equivalent behavior.
- Live smoke coverage is added or updated when the provider has usable local
  credentials and a low-cost representative call.
- `Docs/ProductGapAudit.md`, this guide, and the capability matrix describe the
  final provider state and any remaining known gaps.

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
| Core protocols and request/response shapes | `Sources/SwiftAISDK/Core.swift` |
| Middleware wrappers | `Sources/SwiftAISDK/Middleware.swift` |
| JSON model used by request builders | `Sources/SwiftAISDK/JSONValue.swift` |
| HTTP transport, multipart, SSE/EventStream parsing | `Sources/SwiftAISDK/HTTP.swift` |
| Public provider registry | `Sources/SwiftAISDK/Providers/ProviderRegistry.swift` |
| Custom provider composition | `Sources/SwiftAISDK/Providers/CustomProvider.swift` |
| Provider capability matrix | `Sources/SwiftAISDK/Providers/ProviderCapabilityMatrix.swift`, `Docs/ProviderCapabilityMatrix.md` |
| OpenAI chat, responses, compatible models | `Sources/SwiftAISDK/Models/OpenAI*.swift`, `Sources/SwiftAISDK/Providers/OpenAICompatibleProvider.swift` |
| Anthropic and Bedrock/Vertex Anthropic behavior | `Sources/SwiftAISDK/Models/Anthropic.swift`, `Sources/SwiftAISDK/Providers/AnthropicAWSProvider.swift` |
| Google Gemini and Vertex Gemini behavior | `Sources/SwiftAISDK/Models/Google*.swift`, `Sources/SwiftAISDK/Providers/GoogleVertexProvider.swift` |
| Gateway behavior and management APIs | `Sources/SwiftAISDK/Models/GatewayModels.swift`, `Sources/SwiftAISDK/Providers/GatewayProvider.swift` |
| Bedrock native, Bedrock Anthropic, Mantle | `Sources/SwiftAISDK/Models/AmazonBedrockModels.swift`, `Sources/SwiftAISDK/Providers/AmazonBedrockProvider.swift` |
| Media and audio providers | `Sources/SwiftAISDK/Models/*Media*.swift`, `Sources/SwiftAISDK/Models/*Audio*.swift` |
| Files and skills clients | `Sources/SwiftAISDK/Models/FileClients.swift`, `Sources/SwiftAISDK/Models/OpenAISkills.swift` |
| Tests | `Tests/SwiftAISDKTests/*.swift`, including opt-in live checks in `LiveProviderSmokeTests.swift` |

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
| Custom provider | Upstream `customProvider(...)` maps to Swift `customProvider(...)` and `AIProviders.customProvider(...)`. Keep local model maps preferred over fallback providers, expose files/skills when locally supplied or when the fallback conforms to `AIFileProvider`/`AISkillsProvider`, and throw `AIError.unsupportedModel` when no model route exists. |
| Provider registry | Upstream `createProviderRegistry(...)` maps to Swift `createProviderRegistry(...)`, `experimentalCreateProviderRegistry(...)`, and `AIProviders.providerRegistry(...)`. Split combined IDs on the configured separator, route every model family to the selected provider, expose `files(providerID)`/`skills(providerID)`, apply `languageModelMiddleware` and `imageModelMiddleware` to routed models, and use `AIProviderRegistryError` for missing separators, missing providers, and unsupported files/skills. Upstream global default-provider resolution maps to `AIDefaultProvider` plus `AI.resolve*Model(...)` and string `AI` facade overloads. |
| Middleware | Upstream `wrapLanguageModel(...)`, `wrapImageModel(...)`, and `wrapEmbeddingModel(...)` map to Swift model-specific middleware structs, request transforms, operation wrappers, provider/model ID overrides, and upstream middleware ordering. Upstream `wrapProvider(...)` maps to Swift `wrapProvider(...)` for language, image, and embedding models. Upstream specialized helpers map to Swift `defaultSettingsMiddleware(...)`, `defaultEmbeddingSettingsMiddleware(...)`, `extractJsonMiddleware(...)`, `extractReasoningMiddleware(...)`, `simulateStreamingMiddleware(...)`, and `addToolInputExamplesMiddleware(...)`. |
| Factory spelling | Prefer idiomatic Swift casing for primary names, but also expose upstream JS spellings such as `openai`, `xai`, `revai`, `moonshotai`, and `anthropicAws` when they differ. |
| Provider ID | Match upstream provider IDs, including capability suffixes such as `.chat`, `.responses`, `.embedding`, `.image`, `.files`, or `.skills` when upstream uses them. |
| Settings object | Prefer extending `ProviderSettings` or the provider-specific settings type over ad hoc parameters. |
| Base URL | Preserve upstream defaults and env fallbacks. Tests should assert the final URL. |
| Auth headers | Preserve header names, bearer/API-key prefixes, and provider-specific override behavior. |
| Request body | Build structured `JSONValue` dictionaries. Avoid string assembly except for provider APIs that require encoded payloads. |
| Provider options | Read the upstream namespace (`openai`, `anthropic`, `google`, `amazonBedrock`, etc.) and strip provider-only options before forwarding generic extra body fields. |
| Download URLs | Upstream `validateDownloadUrl(...)`, redirect hardening, and `readResponseWithSizeLimit(...)` map to Swift `validateDownloadURL(...)`, `downloadURL(...)`, `AIHTTPRequest.maxResponseBytes`, and `AIDefaultMaxDownloadSize`. Use the shared helper for SDK-managed downloads of provider-returned or user-provided media/file URLs; it allows `http`, `https`, and inline `data:` URLs while blocking localhost, `.local`, private IPv4, link-local/cloud metadata IPv4, private/link-local IPv6, and IPv4-mapped private IPv6 before transport execution and again on `AIHTTPResponse.url` after URLSession redirects. URLSession-backed downloads should check `Content-Length` early and abort incremental reads that exceed the configured byte limit. |
| Tools | Keep provider-defined tool builders beside the provider model. Test both tool schema and required beta/header behavior. Upstream `dynamicTool(...)` maps to `AITool.dynamic(...)`, which is sent as a normal function tool but marks calls/results as dynamic. Upstream tool `execute` options map to `AIToolExecutionContext`; `AI.generateText`/`AI.streamText` pass the request `AIAbortSignal`, messages, and tool call ID into tool execution while preserving the legacy `execute(arguments)` closure for simple tools. Upstream tool `toModelOutput` maps to `AITool.toModelOutput`; `AI.generateText`/`AI.streamText` preserve raw `result` and store model-facing `modelOutput` on `AIToolResult`, and provider serializers should prefer `modelOutput ?? result` for follow-up tool messages. Upstream `@ai-sdk/mcp` maps through `MCPClient`: initialize, `tools/list`, `tools/call`, cached `toolsFromDefinitions`, dynamic `AITool` conversion with MCP metadata and MCP content-to-model-output conversion, resources, resource templates, prompts, and client-side `elicitation/create` handling via `MCPElicitationRequest`/`MCPElicitResult`. Upstream `experimental_refineToolInput` maps to `AITool.refineArguments` before a Swift tool's execute callback. Refined Swift tool arguments are validated against the tool JSON Schema before execution; extend `AIJSONSchemaValidator` when upstream schema coverage grows. Upstream `toolApproval` maps to the Swift `toolApproval` callback on `AI.generateText` and `AI.streamText`, using `AIToolApprovalStatus` for automatic approve/deny and user-approval stops. For provider-executed approvals, preserve native provider IDs and wire formats; OpenAI Responses maps `mcp_approval_request` to `AIToolApprovalRequest` and `AIToolApprovalResponse(providerExecuted: true)` back to `mcp_approval_response`. |
| Streaming | Reuse `HTTP.swift` parsers where possible. Add provider adapters only for genuinely different wire formats such as AWS EventStream. |
| Media/audio multipart | Use structured multipart helpers and assert fields, filenames, MIME type, and endpoint path. |
| Warnings | Return upstream-style warnings on result types when Swift exposes the same setting. Include `feature`, `setting`, and `message` fields when upstream does, and assert that unsupported settings do not leak into request bodies. Upstream `AI_SDK_LOG_WARNINGS` maps to `AIWarningLogging`: default stderr logging, custom `AIWarningLogger`, disabled logging, and Swift task-scoped overrides while preserving result warnings. |
| Unsupported models | Throw `AIError.unsupportedModel` instead of silently routing to another capability. |

## Implementation Index

| Provider surface | Upstream package/files | Swift entry points | Main tests |
| --- | --- | --- | --- |
| Model resolution | `packages/ai/src/model/resolve-model.ts` | `AIDefaultProvider`, `AI.resolveLanguageModel(...)`, `AI.resolveEmbeddingModel(...)`, `AI.resolveImageModel(...)`, `AI.resolveTranscriptionModel(...)`, `AI.resolveSpeechModel(...)`, `AI.resolveVideoModel(...)`, `AI.resolveRerankingModel(...)`, string-model `AI` facade overloads | `AIModelResolutionTests.swift` |
| OpenAI Chat | `@ai-sdk/openai`, chat model files | `AIProviders.openAI`, `OpenAICompatibleChatModel`, OpenAI tools | `OpenAIChatTests.swift`, `OpenAIMediaTests.swift` |
| OpenAI Responses | `@ai-sdk/openai`, responses model/tool files | `AIProviders.openAI`, `OpenAICompatibleResponsesModel`, `OpenAITools` | `OpenAIResponsesTests.swift`, `ResponsesEndpointTests.swift`, `NativeReasoningProviderTests.swift` |
| OpenAI Files/Skills | `@ai-sdk/openai` file and skill clients | `OpenAIFileClient`, `OpenAISkillsClient` | `FileAndSkillClientTests.swift` |
| Azure OpenAI | `@ai-sdk/azure` | `AIProviders.azureOpenAI`, `AzureOpenAIProvider`, `AzureOpenAITools` | `AlibabaProdiaAzureQuiverTests.swift`, `OpenAIResponsesTests.swift` |
| OpenAI-compatible providers | `@ai-sdk/openai-compatible`, `deepseek`, `togetherai`, `groq`, `perplexity`, `fireworks`, `deepinfra`, `baseten`, `cerebras`, `moonshotai` | `OpenAICompatibleProvider`, provider-specific registry helpers | `OpenAICompatibleTests.swift`, `ProviderRegistryVercelTests.swift`, `CohereMistralVoyageTests.swift` |
| Groq | `@ai-sdk/groq/src/groq-chat-language-model.ts`, `groq-prepare-tools.ts`, `groq-transcription-model.ts` | `AIProviders.groq`, `GroqLanguageModel`, `GroqTranscriptionModel`, `GroqTools`. Chat maps sampling, seed, reasoning effort/format, service tier, parallel tools, structured outputs, function tools, browser search, response metadata, text/reasoning/tool stream lifecycle parts, raw chunks, and abort signals. Transcription maps standard Swift language/prompt plus upstream-style `providerOptions.groq` (`language`, `prompt`, `responseFormat`, `temperature`, `timestampGranularities`) into multipart fields, preserves safe request/response metadata, verbose segments/language/duration, and forwards abort signals. | `GroqProviderTests.swift`, `ProviderAbortPropagationTests.swift`, `NativeAudioRequestMetadataTests.swift`, `NativeTranscriptionDetailTests.swift` |
| DeepSeek | `@ai-sdk/deepseek/src/chat/deepseek-chat-language-model.ts`, `convert-to-deepseek-chat-messages.ts`, `deepseek-prepare-tools.ts`, `convert-to-deepseek-usage.ts` | `AIProviders.deepSeek`, `AIProviders.deepseek`, `DeepSeekLanguageModel`. Chat maps text-only user messages, drops unsupported file/image parts with warnings, injects upstream JSON instructions, maps top-level reasoning with compatibility warnings, passes `providerOptions.deepseek.reasoningEffort` through, maps thinking, sampling, function tools/tool choice, cache/reasoning token usage, response/provider metadata, raw chunks, stream lifecycle parts, and abort signals. | `DeepSeekProviderTests.swift`, `ProviderAbortPropagationTests.swift` |
| Cerebras | `@ai-sdk/cerebras/src/cerebras-chat-language-model.ts`, `cerebras-provider.ts`, plus shared `@ai-sdk/openai-compatible` chat/prepare-tools/usage logic | `AIProviders.cerebras`, `CerebrasLanguageModel`. Chat follows the upstream OpenAI-compatible surface with Cerebras request-body transform (`reasoning_content` history becomes `reasoning`), sampling/user/seed/penalty fields, `providerOptions.cerebras`/`openaiCompatible` reasoning effort and verbosity, function tools/tool choice, provider-tool warnings, strict structured outputs with recursive JSON Schema normalization, mixed structured-output/tool-call finish normalization, response/provider metadata, rich cache/reasoning token usage, raw chunks, stream lifecycle parts, and abort signals. | `CerebrasProviderTests.swift`, `ProviderAbortPropagationTests.swift` |
| xAI | `@ai-sdk/xai` | `AIProviders.xAI`, `XAITools`, `XAIImageModel`, `XAIVideoModel`, `XAIFileClient`, OpenAI-compatible chat/responses models with xAI surface IDs | `OpenAICompatibleTests.swift`, `ResponsesEndpointTests.swift`, `NativeMediaProviderTests.swift`, `FileAndSkillClientTests.swift` |
| Anthropic | `@ai-sdk/anthropic` | `AIProviders.anthropic`, `AnthropicLanguageModel` with `anthropic.messages`, `AnthropicTools`, files on `anthropic.messages`, skills on `anthropic.skills` | `AnthropicTests.swift`, `AnthropicStreamingAndClientsTests.swift` |
| Anthropic AWS | `packages/anthropic-aws/src` | `AIProviders.anthropicAWS`, `AnthropicAWSProvider`, messages/files on `anthropic-aws.messages`, skills on `anthropic-aws.skills` | `AnthropicTests.swift`, `AnthropicStreamingAndClientsTests.swift` |
| Amazon Bedrock native | `@ai-sdk/amazon-bedrock` | `AIProviders.amazonBedrock`, `AmazonBedrockLanguageModel`, `AmazonBedrockEmbeddingModel`, `AmazonBedrockImageModel`, `AmazonBedrockRerankingModel`; SigV4 request cloning must preserve `AIAbortSignal` | `AmazonBedrockTests.swift`, `ProviderAbortPropagationTests.swift` |
| Bedrock Anthropic | `@ai-sdk/amazon-bedrock/src/anthropic/*` | `AIProviders.amazonBedrockAnthropic`, `AmazonBedrockAnthropicProvider`, `AmazonBedrockAnthropicLanguageModel` | `AmazonBedrockTests.swift` |
| Bedrock Mantle | `@ai-sdk/amazon-bedrock/src/mantle/*` | `AIProviders.bedrockMantle`, `AIProviders.amazonBedrockMantle`, OpenAI-compatible chat/responses models with AWS auth | `AmazonBedrockTests.swift` |
| Google Gemini | `@ai-sdk/google` | `AIProviders.google`, `GoogleGenerativeAIModel`, `GoogleTools`; language/embedding/image/video/files use `google.generative-ai`, interactions use `google.generative-ai.interactions`; GenerateContent tool calls preserve `providerMetadata.google.thoughtSignature` and replay it on assistant tool-call history; video and interactions polling forward `AIAbortSignal` | `GoogleGenerativeAITests.swift`, `ProviderAbortPropagationTests.swift` |
| Google Vertex | `@ai-sdk/google-vertex` | `AIProviders.googleVertex`, `GoogleVertexProvider` with `google.vertex.chat`, `.embedding`, `.image`, `.video`; `GoogleVertexAnthropicProvider`, `GoogleVertexTools`, `GoogleVertexAnthropicTools`; provider request builders forward `AIAbortSignal` | `GoogleVertexTests.swift`, `ProviderAbortPropagationTests.swift` |
| AI Gateway | `@ai-sdk/gateway` | `AIProviders.gateway`, `GatewayProvider`, `GatewayTools`, `GatewayManagementClient` | `GatewayTests.swift` |
| Mistral, Cohere, Voyage | `@ai-sdk/mistral`, `@ai-sdk/cohere`, `@ai-sdk/voyage` | Provider-specific Swift models plus registry helpers. Mistral maps v4 sampling warnings, seed, JSON response format, reasoning effort, function tools/tool choice, response metadata, stream lifecycle parts, abort signals, assistant `tool_calls`, and role `tool` messages with upstream-style `modelOutput ?? result` content. Cohere chat maps v4 sampling, JSON response format, thinking, function tools/tool choice, response metadata, stream lifecycle parts, and abort signals to the native `/v2/chat` API. | `CohereMistralVoyageTests.swift`, `ProviderAbortPropagationTests.swift` |
| Vercel | `@ai-sdk/vercel` | `AIProviders.vercel`, Vercel chat model | `ProviderRegistryVercelTests.swift` |
| Hugging Face | `@ai-sdk/huggingface` | `AIProviders.huggingFace`, responses language model | `ProviderRegistryVercelTests.swift`, `ResponsesEndpointTests.swift` |
| Fireworks, DeepInfra, TogetherAI, Baseten, MoonshotAI | provider packages with OpenAI-compatible cores plus native media/rerank pieces | OpenAI-compatible chat/completion/embedding with upstream surface IDs such as `fireworks.chat`, `deepinfra.embedding`, `togetherai.completion`, plus native image/rerank models. TogetherAI accepts `TOGETHER_API_KEY` plus the deprecated `TOGETHER_AI_API_KEY`, maps image seed/provider options/reference-image warnings/mask rejection, and reranking can send upstream-style JSON object documents with `rankFields`. Baseten uses `ProviderSettings.modelURL` for dedicated `/sync` or `/sync/v1` model endpoints, rejects `/predict`, requests chat only from `/sync/v1`, and keeps embeddings on `/sync[/v1]/v1/embeddings`. MoonshotAI chat requests stream usage by default and maps provider-specific cache/reasoning usage into rich `TokenUsage` fields. Fireworks async image submit/poll/download forwards `AIAbortSignal`. | `NativeMediaProviderTests.swift`, `NativeReasoningProviderTests.swift`, `OpenAICompatibleTests.swift`, `ProviderAbortPropagationTests.swift` |
| Replicate and fal | `@ai-sdk/replicate`, `@ai-sdk/fal` | Provider-specific media models; submit, polling, and download requests forward `AIAbortSignal`. Replicate maps standard image options (`aspectRatio`, `seed`) and standard video options (`image`, `resolution`, `fps`, `seed`) alongside `providerOptions.replicate`, preserves image warnings for ignored inputs, and attaches prediction metadata for videos. fal maps standard image options (`size`, `aspectRatio`, `seed`, `count`, files, masks), standard video options (`image`, `aspectRatio`, `durationSeconds`, `seed`), `providerOptions.fal` for image/video/speech/transcription, upstream image/video provider metadata, deprecated image snake_case warnings, multi-image warnings, speech output-format warnings, and queue polling for video/transcription. | `ReplicateFalTests.swift`, `FalProviderTests.swift`, `ProviderAbortPropagationTests.swift` |
| Alibaba, Prodia, Quiver, Luma, Kling, ByteDance | `@ai-sdk/alibaba`, `prodia`, `quiverai`, `luma`, `klingai`, `bytedance` | Alibaba has native chat plus video: chat maps top-level sampling/seed/reasoning/JSON response format, function tools/tool choice, assistant tool calls, tool-result history, response metadata, stream lifecycle parts, and abort signals; video uses provider-specific DashScope async tasks. Prodia/Quiver/Luma/Kling/ByteDance remain provider-specific media/video models. | `AlibabaProdiaAzureQuiverTests.swift`, `ImageVideoProviderTests.swift`, `NativeMediaProviderTests.swift`, `ProviderAbortPropagationTests.swift` |
| Black Forest Labs | `@ai-sdk/black-forest-labs` | Native image provider | `ImageVideoProviderTests.swift`, `NativeMediaProviderTests.swift` |
| Deepgram, ElevenLabs, Hume, LMNT, RevAI, Gladia, AssemblyAI | Audio provider packages | Provider-specific transcription/speech models. Deepgram maps `providerOptions.deepgram` for transcription and speech, keeps raw-audio listen requests, validates TTS encoding/container/sample-rate/bit-rate combinations with upstream-style warnings, warns that TTS voices are selected through the model ID, warns for unsupported standard speech `speed`, `language`, and `instructions`, and forwards abort signals for both surfaces. ElevenLabs maps `providerOptions.elevenlabs` for speech and transcription, including TTS voice settings, pronunciation dictionaries, text normalization, logging query flags, speech-to-text diarization, speaker counts, timestamp granularity, and file format fields, and forwards abort signals for both surfaces. LMNT maps `providerOptions.lmnt` speech options, keeps `model` and provider `format` ignored like upstream, warns/falls back to `mp3` for unsupported standard output formats, and forwards abort signals. Hume maps `providerOptions.hume` speech context, preserves context utterance voice objects while translating `trailingSilence`, warns/falls back to `mp3` for unsupported output formats, and forwards abort signals. AssemblyAI maps `providerOptions.assemblyai`, submits upload URLs to `/v2/transcript`, maps upstream transcript option keys, keeps final GET response metadata and transcription details, and forwards abort signals across upload, submit, and poll requests. Rev.ai maps `providerOptions.revai`, submits multipart media/config jobs, preserves transcript response metadata/details, and forwards abort signals across submit, status polling, and transcript fetch. Gladia maps `providerOptions.gladia`, uploads media with upstream-style `audio.<media extension>` filenames, initiates `/v2/pre-recorded`, preserves final result metadata/details, and forwards abort signals across upload, initiation, and result polling. | `AssemblyAIProviderTests.swift`, `DeepgramProviderTests.swift`, `ElevenLabsProviderTests.swift`, `GladiaProviderTests.swift`, `HumeProviderTests.swift`, `LMNTProviderTests.swift`, `ProviderAbortPropagationTests.swift`, `RevAIProviderTests.swift` |
| Custom provider and registry composition | `packages/ai/src/registry/custom-provider.ts`, `provider-registry.ts` | `customProvider(...)`, `createProviderRegistry(...)`, `experimentalCreateProviderRegistry(...)`, `AIProviders.customProvider(...)`, `AIProviders.providerRegistry(...)`, `AICustomProvider`, `AIProviderRegistry`, `AIFileProvider`, `AISkillsProvider` | `CustomProviderTests.swift` |
| Model middleware | `packages/ai/src/middleware/wrap-language-model.ts`, `wrap-image-model.ts`, `wrap-embedding-model.ts`, `wrap-provider.ts`, `default-settings-middleware.ts`, `default-embedding-settings-middleware.ts`, `extract-json-middleware.ts`, `extract-reasoning-middleware.ts`, `simulate-streaming-middleware.ts`, `add-tool-input-examples-middleware.ts` | `AILanguageModelMiddleware`, `AIImageModelMiddleware`, `AIEmbeddingModelMiddleware`, `wrapLanguageModel(...)`, `wrapImageModel(...)`, `wrapEmbeddingModel(...)`, `wrapProvider(...)`, `defaultSettingsMiddleware(...)`, `defaultEmbeddingSettingsMiddleware(...)`, `extractJsonMiddleware(...)`, `extractReasoningMiddleware(...)`, `simulateStreamingMiddleware(...)`, `addToolInputExamplesMiddleware(...)` | `MiddlewareTests.swift`, `SpecializedMiddlewareTests.swift` |

## Cross-Cutting Surfaces

| Surface | Current rule |
| --- | --- |
| Provider-defined tools | Tool builders live near their provider: `OpenAITools`, `AzureOpenAITools`, `AnthropicTools`, `GoogleTools`, `GoogleVertexTools`, `GoogleVertexAnthropicTools`, `GatewayTools`, `GroqTools`, `XAITools`. |
| JSON Schema normalization | Upstream `packages/provider-utils/src/add-additional-properties-to-json-schema.ts` maps to `addAdditionalPropertiesToJSONSchema(...)`. Strict OpenAI-compatible and Cerebras structured response formats apply it recursively to object schemas before sending `response_format`; callers that pass `strictJsonSchema: false` keep the raw schema unchanged. |
| JSON parsing | Upstream `secure-json-parse.ts`, `parse-json.ts`, and `is-json-serializable.ts` map to `secureJSONParse(...)`, `parseJSON(...)`, `safeParseJSON(...)`, `isParsableJSON(...)`, `isJSONSerializable(...)`, `AIJSONParseError`, and `AIJSONParseResult`. `decodeJSONBody(...)` uses the secure parser so provider responses and stream events reject `__proto__` and `constructor.prototype` payloads like upstream provider-utils. |
| Media type helpers | Upstream `detect-media-type.ts`, `resolve-full-media-type.ts`, and `media-type-to-extension.ts` map to `detectMediaType(...)`, `resolveFullMediaType(...)`, `topLevelMediaType(...)`, `isFullMediaType(...)`, and `mediaTypeToExtension(...)`. Google GenerateContent and Interactions resolve top-level inline media types such as `image` or `image/*` from bytes before sending provider requests. |
| Header helpers | Upstream `normalize-headers.ts`, `combine-headers.ts`, and `with-user-agent-suffix.ts` map to `normalizeHeaders(...)`, `normalizeHeaderEntries(...)`, `combineHeaders(...)`, and `withUserAgentSuffix(...)`. Existing provider request builders still preserve historical Swift header casing where tests assert it; use the helpers for new shared header code and migrate broad provider paths deliberately. |
| Provider references | Upstream `is-provider-reference.ts` and `resolve-provider-reference.ts` map to `AIProviderReference`, `isProviderReference(...)`, `resolveProviderReference(...)`, and `AINoSuchProviderReferenceError`. `FileUploadResult` and `SkillUploadResult` expose `providerID(for:)` convenience resolution over their `providerReference` maps. |
| Download URL safety | SDK-managed downloads now validate remote URLs through `downloadURL(...)`/`validateDownloadURL(...)`, mirroring `@ai-sdk/provider-utils`. Provider output downloads and URL-backed image/file fallbacks reject local/private targets before transport execution, reject unsafe final redirect targets when `AIHTTPResponse.url` is set, and pass `AIHTTPRequest.maxResponseBytes` so URLSession enforces the upstream 2 GiB default while reading. Keep new download helpers on that path and add tests for direct validation, redirect validation, byte-limit validation, and one provider integration. |
| MCP client | `MCPClient` mirrors `@ai-sdk/mcp` for initialize, tool listing, tool calls, cached tool definitions, conversion to dynamic `AITool`, MCP content-to-model-output conversion for text/image/unknown content parts, resource listing/reading, resource templates, prompt listing/getting, and incoming `elicitation/create` requests. MCP dynamic tools honor `AIToolExecutionContext.abortSignal`; aborted executions fail before `tools/call`, and active MCP HTTP calls forward `MCPRequestOptions.abortSignal` into `AIHTTPRequest`. `MCPHTTPTransport` covers Streamable HTTP request/response semantics: protocol-version headers, JSON and SSE responses, `mcp-session-id` persistence, DELETE session termination, inbound SSE requests answered through `setRequestHandler`, bounded inbound SSE reconnects, and `last-event-id` resumption. Use `AIStreamingTransport` for true long-lived SSE; `URLSessionTransport` implements it, while plain `AITransport` keeps buffered fallback parsing. `MCPStdioTransport` mirrors the official `@ai-sdk/mcp/mcp-stdio` local-server transport on macOS/Linux: command/args/env/cwd process spawning, newline-delimited JSON-RPC over stdin/stdout, response matching by `id`, and incoming server requests answered through the existing request handler. `MCPOAuthProvider` covers bearer token headers, token invalidation on 401, `resource_metadata` extraction from `WWW-Authenticate`, authorization recovery, and one retry. `MCPOAuthDiscovery` covers protected-resource metadata, path-aware/root fallback, OAuth/OIDC authorization-server metadata, OIDC S256 PKCE validation, and retry without MCP protocol headers after transport failures. `MCPOAuth` covers PKCE authorization URL creation, authorization-code exchange, refresh-token exchange, OAuth server error parsing, client auth selection, custom token endpoint client authentication hooks, dynamic client registration, and `MCPOAuthClientProvider` orchestration with resource selection, callback state validation, refresh, redirect, and OAuth error invalidation/retry. Deeper provider-native multimodal model-output serialization remains a follow-up MCP pass. |
| Provider registry aliases | `AIProviders` keeps Swift-style factories and upstream JS spellings for mismatched names, so `openAI`/`openai`, `xAI`/`xai`, `revAI`/`revai`, and similar pairs construct the same provider IDs. |
| Custom provider and registry | `customProvider(...)` mirrors upstream local-model maps plus fallback routing for language, embedding, image, transcription, speech, video, reranking, files, and skills. `createProviderRegistry(...)` mirrors upstream separator routing for `provider:model` IDs, provider-scoped files/skills, language middleware on routed language models, and image middleware on routed image models. `AIDefaultProvider` lets string model IDs resolve through a caller-supplied default provider or through the Gateway fallback. |
| Model middleware | `wrapLanguageModel(...)`, `wrapImageModel(...)`, and `wrapEmbeddingModel(...)` apply request transforms before provider calls and wrap operations in upstream order, with the first middleware outside and transforms flowing left to right. `defaultSettingsMiddleware(...)` and `defaultEmbeddingSettingsMiddleware(...)` apply Swift defaults only when request values are absent and deep-merge JSON provider options. Specialized language middleware covers JSON fence extraction, XML-tag reasoning extraction, simulated streams from generate calls, and tool input examples folded into descriptions. `wrapProvider(...)` applies middleware to language, image, and embedding models created by a provider. `createProviderRegistry(...)` accepts language and image middleware for routed models. |
| Tool headers and beta flags | Match upstream tests. Anthropic-on-Bedrock uses body `anthropic_beta`; regular Anthropic uses headers. |
| OpenAI-compatible providers | Share the compatible model implementation, but keep provider-specific defaults, path quirks, headers, tools, provider IDs, and response metadata explicit. Chat/completion/responses generation, streaming, embeddings, images, speech, and transcription preserve upstream-style response headers and JSON bodies through `AIResponseMetadata` where the provider returns them. Chat/completion/responses also lift upstream provider metadata into the root provider namespace: chat accepted/rejected prediction token counts and content logprobs, completion logprobs, and Responses response IDs, service tier, and output logprobs. Chat streams emit v4-shaped text/reasoning lifecycle parts while keeping legacy `.textDelta`/`.reasoningDelta`; Chat and Responses tool streams emit both legacy `.toolCallDelta` chunks and v4-shaped `.toolInputStart/.toolInputDelta/.toolInputEnd` lifecycle parts before the final `.toolCall`. Transcription models should also map upstream verbose fields (`segments`, `language`, `duration`) into `TranscriptionResult` whenever returned. |
| OpenAI/Azure provider IDs | Root providers stay `openai` and `azure`, but concrete models use upstream surface IDs: `openai.responses`, `openai.chat`, `openai.completion`, `openai.embedding`, `openai.image`, `openai.transcription`, `openai.speech`, `openai.files`, `openai.skills`; Azure uses the same pattern except embeddings is `azure.embeddings`. |
| xAI provider IDs and files | Root provider stays `xai`, concrete surfaces use `xai.responses`, `xai.chat`, `xai.image`, `xai.video`, and `xai.files`. xAI file uploads use `team_id` from provider options, do not send OpenAI's `purpose` field, forward `AIAbortSignal`, and preserve upload response metadata. xAI video create/poll requests forward `AIAbortSignal`. |
| Provider options | Preserve upstream namespaces and avoid leaking provider-specific options into unrelated providers. |
| OpenAI-compatible warnings | Chat, completion, embedding, and image models return deprecated warnings for raw provider option keys such as `openai-compatible` or `test-provider`, pointing callers to the camelCase keys. Image models also return unsupported warnings for top-level `aspectRatio` and `seed`; these settings are intentionally not forwarded to OpenAI-style image endpoints. |
| Core v4 contract | Core request/result/stream types now have v4-shaped slots for provider options, response metadata, provider metadata, warnings, stream lifecycle parts, tool results/approval requests, files, custom parts, streamed errors, upstream-style abort signals through `AIAbortController`/`AIAbortSignal`, tool execution context through `AIToolExecutionContext`, and richer token-usage details for cache/read, text/reasoning, and raw provider usage. Provider passes should populate or propagate these fields when upstream exposes equivalent data. OpenAI-compatible chat/responses, Anthropic, Google GenerateContent/Interactions, native Bedrock, Gateway, Mistral, Cohere, Groq, DeepSeek, Cerebras, Alibaba, and Hugging Face Responses streaming now populate tool input start/delta/end parts while keeping final tool calls for existing consumers. OpenAI-compatible chat and Perplexity emit text lifecycle parts; OpenAI-compatible chat, Mistral, Cohere, Groq, DeepSeek, Cerebras, Alibaba, and Hugging Face Responses also emit text/reasoning start-delta-end lifecycle parts. Perplexity, MoonshotAI, Mistral, Cohere, Groq, DeepSeek, Cerebras, Alibaba, and Hugging Face language calls now forward abort signals; Perplexity, Mistral, Groq, DeepSeek, Alibaba, and Hugging Face also return upstream-style unsupported warnings for unsupported standard settings. Streaming providers must only emit `.raw(...)` chunks when `LanguageModelRequest.includeRawChunks` is true, matching upstream `includeRawChunks`. When adding provider helpers, keep abort propagation explicit through builder, signing, polling, and download steps. |
| Native response metadata | Use `aiResponseMetadata(...)` when native providers can expose upstream response metadata. It derives IDs/model IDs from provider JSON, preserves response headers and raw JSON bodies, and uses the current call time when the provider body has no `created` timestamp. Anthropic language, Perplexity language, Mistral chat language, Cohere chat language, Groq chat language, DeepSeek chat language, Cerebras chat language, Alibaba chat language, Hugging Face Responses language, Google Generative AI language/embedding/image/video/files, Google Vertex language/embedding/image/video, OpenAI-compatible multipart files, xAI files, OpenAI/Anthropic skill uploads, native embedding/reranking surfaces for Cohere, Voyage, Mistral, Baseten, Gateway, Amazon Bedrock, TogetherAI, and generic JSON reranking wrappers, native media surfaces for Replicate, fal, Fireworks, DeepInfra, TogetherAI, xAI, QuiverAI, generic JSON image/video wrappers, and native audio/transcription surfaces for Deepgram, ElevenLabs, LMNT, Hume, AssemblyAI, Rev.ai, Gladia, and Groq preserve metadata on results; language streams emit response metadata before model deltas. For submit/poll flows, attach metadata from the final provider result response when that JSON becomes the result `rawValue`; for submit/download flows, attach metadata from the provider submit response rather than the SDK-managed asset download. |
| Native request metadata | Populate `AIRequestMetadata` where the Swift result shape exposes it and upstream returns request bodies. Native embedding and reranking models for OpenAI-compatible, Google Generative AI, Google Vertex, Cohere, Voyage, Mistral, Baseten, Gateway, Amazon Bedrock, TogetherAI, and generic JSON reranking wrappers preserve the JSON body sent to the provider without provider auth headers; `AI.embed`, chunked `AI.embedMany`, and `AI.rerank` also fill a safe facade-level request snapshot when a custom model returns no metadata. Native image/video models preserve provider JSON bodies or safe request snapshots on `ImageGenerationResult` and `VideoGenerationResult`; sanitize inline/base64 media payloads through `aiRequestMetadata(...)`, preserving encoded byte length rather than raw image bytes. `AI.generateImage`, `AI.generateVideo`, `AI.transcribe`, `AI.generateSpeech`, `AI.uploadFile`, and `AI.uploadSkill` fill safe facade-level request snapshots when custom models or clients return no metadata. Native speech models for Deepgram, ElevenLabs, LMNT, Hume, fal, OpenAI-compatible speech, Gateway speech, and generic JSON speech preserve the JSON body sent to the provider without provider auth headers. OpenAI-compatible and Groq multipart transcription preserve safe form metadata (`model`, filename, MIME type, language/prompt/options) without embedding audio bytes; OpenAI-compatible multipart file uploads, Google resumable file uploads, xAI file uploads, and OpenAI/Anthropic skill uploads preserve safe form metadata such as filename/path, media type, byte length, display title, purpose, scalar provider options, and request headers without storing raw uploaded file bytes. Multipart file clients return `AIWarning(type: "unsupported", feature: ...)` when caller options are intentionally not forwarded, e.g. `displayName` or unsupported `purpose`. Gateway and generic JSON transcription preserve their JSON request bodies because those APIs already send base64 audio JSON. |
| Transcription detail fields | Upstream transcription results expose `segments`, `language`, and `durationInSeconds` when providers return word/segment/utterance timing. Keep provider parsers aligned for Deepgram words, ElevenLabs words, Groq/OpenAI-compatible verbose JSON segments, AssemblyAI final transcript words, Rev.ai monologue elements, Gladia utterances, fal standard segments, Gateway transcription JSON, and generic JSON transcription wrappers. |
| AI facade | `AI.generateText`, `AI.streamText`, `AI.generateObject`, `AI.streamObject`, `AI.embed`, `AI.embedMany`, `AI.generateImage`, `AI.transcribe`, `AI.generateSpeech`, `AI.generateVideo`, `AI.rerank`, `AI.uploadFile`, and `AI.uploadSkill` are product-level wrappers over the model/client protocols. Model-taking facades also have string-model overloads that resolve through an explicit provider or `AIDefaultProvider`. Non-streaming facade calls use `AIRetryPolicy` with upstream-style default `maxRetries: 2` for retryable transient errors, optional per-attempt timeout, `Retry-After` header handling, telemetry lifecycle events, explicit `AIAbortSignal` cancellation, result response metadata including upload-file/upload-skill metadata, and warning logging through `AIWarningLogging`; `generateObject` emits object-specific telemetry under `ai.generateObject`; `streamText` and `streamObject` accept direct stream timeouts, retry retryable start failures before the first emitted part, emit telemetry start/retry/end/error events, and log collected warnings when the stream completes. `streamText` and `streamObject` also record consumer cancellation as abort telemetry events. `AI.generateText` and `AI.streamText` can execute typed `AITool` callbacks across multiple steps, pass `AIToolExecutionContext` with abort signal/messages/tool call ID, mark dynamic tool calls/results, refine and JSON-Schema-validate parsed tool arguments before execution, run Swift tool approval policy, append assistant tool-call/tool-result messages, emit step/tool telemetry events, and accept `MCPClient`-discovered dynamic tools. OpenAI Responses provider-executed MCP approvals round-trip through `AIToolApprovalRequest`/`AIToolApprovalResponse`. `AI.generateObject` sets JSON response-format hints, decodes `Decodable` results, accepts raw `JSONValue` schemas or reusable `AIObjectSchema` adapters, can inject upstream-style JSON system instructions through `AIJSONInstruction`, validates final JSON against the supplied schema, emits object lifecycle callbacks through `AIObjectGenerationCallbacks` including `onError`, and throws `AIObjectGenerationError` for parse/schema/decode failures. `AI.generateObjectArray`, `AI.streamObjectArray`, `AI.generateEnum`, `AI.streamEnum`, `AI.generateJSON`, and `AI.streamJSON` mirror upstream's array, enum, and no-schema output strategies. `AI.streamObject` streams JSON text deltas, best-effort partial `JSONValue` objects, typed partial `Decodable` values when possible, emits stream lifecycle callbacks including `onError`, and returns a schema-validated final decoded object. Telemetry integrations can wrap language model calls and tool execution through `executeLanguageModelCall` and `executeTool`, matching upstream's tracing-context hooks. |
| Retry policy | Keep retry and timeout behavior at the product/facade layer, not in low-level provider models. Retry transient HTTP statuses 408, 409, 429, and 5xx plus network `URLError`s; do not retry validation/auth/client errors or `AIError.timeout`. Preserve Swift task cancellation by using cancellable sleeps, `Task.checkCancellation()`, cancelling timeout race tasks, forwarding stream termination cancellation, honoring `AIAbortSignal` during retry attempts and sleeps, and recording `streamText`/`streamObject` cancellation as telemetry abort rather than error. Provider HTTP errors should be thrown through `httpStatusError(provider:response:)` so response headers are retained; facade retries honor case-insensitive `Retry-After` headers using either delta seconds or HTTP-date values. |
| Telemetry | Map upstream `telemetry`/`experimental_telemetry` to `AITelemetryOptions`, `AITelemetryIntegration`, and `AITelemetry.register(...)`. Per-call integrations override global integrations; `isEnabled: false` disables event dispatch and execute wrapping. Current Swift events cover non-streaming facade and stream facade start, retry, end, error, and abort lifecycle events, including `ai.generateObject` object output events, plus `stepStart`, `stepEnd`, `toolStart`, `toolEnd`, and `toolError` for `generateText`/`streamText` tool loops, with input/output recording flags, function ID, metadata, usage, warnings, provider metadata, and response metadata. `AITelemetryIntegration.executeLanguageModelCall` wraps language model generate/stream calls; `executeTool` wraps Swift tool execution, composing integrations in upstream order with the last integration outermost. |
| Object generation | Keep `AI.generateObject` and `AI.streamObject` aligned with upstream object output: request native JSON response formats when the provider supports them, optionally inject upstream-style JSON instructions with `AIJSONInstruction` for providers that need prompt-level fallback guidance, call `AIObjectGenerationCallbacks` around the object step for both non-streaming and streaming object calls, parse/repair raw text into JSON, then validate through Swift decoding and `AIJSONSchemaValidator`. Object failures should stay typed through `AIObjectGenerationError` with strategy, kind, path, text, and repair-attempt metadata; `onError` receives the text, finish reason, usage, warnings, provider metadata, and response metadata collected before the failure. `AIObjectSchema` mirrors upstream's flexible schema adapter role, with `AIJSONSchema` as the raw JSON Schema adapter. Array output wraps the element schema as an object with an `elements` array, enum output wraps allowed values as an object with a `result` string, and no-schema output requests JSON without a schema and returns raw `JSONValue`; each strategy has non-streaming and streaming facade variants. Strict OpenAI-compatible and Cerebras structured outputs normalize object schemas with `addAdditionalPropertiesToJSONSchema(...)`, matching the provider-utils rule that recursively sets `additionalProperties: false` for object schema nodes. Cerebras also maps call-level `LanguageModelRequest.responseFormat` to `response_format`, preserving the upstream mixed structured-output/tool-call normalization that drops repeated tool calls once JSON text is present. Mistral structured outputs follow upstream defaults: `structuredOutputs` is enabled, `strictJsonSchema` defaults to false, schema calls use `response_format.type=json_schema`, and no-schema JSON calls use `json_object` plus a JSON system instruction. Cohere structured outputs map call-level JSON response formats to native `response_format.type=json_object` with the raw schema payload. Groq structured outputs follow upstream defaults too: `structuredOutputs` is enabled, `strictJsonSchema` defaults to true, schema calls use `response_format.type=json_schema`, disabled structured outputs fall back to `json_object` and return an unsupported warning, and the control options are not forwarded as provider body fields. DeepSeek structured outputs use `response_format.type=json_object`, inject `Return JSON.` or `Return JSON that conforms to the following schema: ...` as an upstream-style system message, and return a compatibility warning for schema injection. Google GenerateContent and Google Vertex structured outputs set `generationConfig.responseMimeType=application/json`, convert JSON Schema to the provider's OpenAPI-compatible `responseSchema`, and omit that schema when `structuredOutputs` is false. Google Interactions maps call-level JSON response formats into `response_format` text entries, appends provider-defined response-format entries, and emits a warning while dropping call-level structured output for agent calls. Perplexity structured outputs map call-level JSON response formats into `response_format.type=json_schema` with the raw schema payload, matching upstream's native Sonar request shape. Hugging Face Responses structured outputs map call-level JSON schemas into `text.format.type=json_schema`, preserve name/description, and default `strictJsonSchema` to false unless caller provider options enable it. Current streaming support emits text deltas, repaired partial `JSONValue` objects, typed partial `Decodable` values when possible, stream lifecycle callbacks, and final decoded objects/arrays/enums/JSON values. Future passes should add richer adapter integrations and provider-specific structured-output parity. |
| Tool-result messages | `AIContentPart.toolCall` and `AIContentPart.toolResult` are the cross-provider representation for multi-step tool execution. When touching provider message conversion, preserve provider-native wire shapes for assistant tool calls and tool results instead of flattening them to text. OpenAI-compatible chat/responses, Anthropic, Google/Vertex, Bedrock, Gateway, and Mistral now prefer `modelOutput ?? result` where their wire formats can carry model-facing tool output. |
| Auth and provider settings | Mirror upstream env var names, base URL fallbacks, and header strategy. OpenAI settings include `OPENAI_BASE_URL`, organization, and project headers. |
| AWS providers | Keep SigV4 service name, region, path encoding, and EventStream parsing covered by tests. |
| Error behavior | Convert provider errors into `AIError` with the surface provider ID that failed. |

## Product Reality Gates

Use these gates before calling a surface complete:

1. **Inventory:** `AIProviderCapabilities` lists the upstream package, Swift
   factory names, supported model capabilities, file upload, and skill upload.
2. **Mock conformance:** Swift tests assert request URLs/bodies/headers and
   response or stream parsing for each listed capability.
3. **Live smoke:** representative first-party providers can be checked with:

   ```sh
   LIVE_AI_TESTS=1 swift test --filter LiveProviderSmoke
   ```

   The live suite reads API keys from environment variables first, then from the
   ignored root files `openai-api-key.txt`, `claude-api-key.txt`, and
   `gemini-api-key.txt`. The suite covers text generation, text streaming,
   executable generate/stream tool loops, and representative embeddings. Language model IDs can
   be overridden with `LIVE_OPENAI_MODEL`, `LIVE_ANTHROPIC_MODEL`, and
   `LIVE_GOOGLE_MODEL`; embedding model IDs can be overridden with
   `LIVE_OPENAI_EMBEDDING_MODEL` and `LIVE_GOOGLE_EMBEDDING_MODEL`.

4. **Docs:** README and `Docs/ProviderCapabilityMatrix.md` point users to the
   same capability story as the code. The provider matrix document is generated
   by `AIProviderCapabilities.markdownDocument()` and guarded by
   `providerCapabilityMatrixDocumentationMatchesGeneratedMarkdown()`.

## Pre-Commit Checklist

- Public factory and aliases match upstream exports.
- Supported capabilities match upstream model methods.
- `AIProviderCapabilities` matches the registry and any new provider/client
  surfaces, and `Docs/ProviderCapabilityMatrix.md` matches
  `AIProviderCapabilities.markdownDocument()`.
- Provider IDs match upstream, including capability suffixes where present.
- Default base URL, env var names, auth headers, and query parameters match.
- Request body conversion is covered for normal generation plus tools,
  provider options, reasoning, media, and structured output where applicable.
- Response parsing covers text, tool calls, reasoning, sources, warnings,
  finish reason, usage, and provider metadata where applicable.
- Streaming covers deltas, tool-call chunks, tool input lifecycle parts, usage,
  finish events, and provider error events.
- Provider-defined tools include upstream name/type/schema mapping and beta
  header/body behavior.
- Focused tests cover at least one request and one response/stream for each new
  or changed surface.
- If live behavior changed for OpenAI, Anthropic, or Gemini, run or explicitly
  defer `LIVE_AI_TESTS=1 swift test --filter LiveProviderSmoke`.
- `swift test` passes.
- This guide's snapshot, index, or known gaps are updated if the pass changed
  provider coverage or product-level SDK surfaces.

## Known Gaps And Next Passes

- Product-level gaps are tracked in `Docs/ProductGapAudit.md`. Treat that file
  as the higher-level map when choosing between more provider micro-parity and a
  broader SDK/core pass.
- Continue comparing upstream provider test suites for small model-specific
  request flags, provider IDs, warnings, and error normalization.
- Continue auditing OpenAI and Azure model-specific request defaults now that
  capability-specific provider IDs are aligned.
- Bedrock Anthropic supports invoke and streaming paths; deeper parity can still
  expand around model-specific exclusions and structured output details.
- Keep file-management and skill clients aligned if upstream adds operations
  beyond the current OpenAI-oriented clients.
- Continue middleware parity with telemetry hooks and any registry-level
  middleware surface upstream adds beyond language/image routing.
- Refresh npm search before each substantial provider pass so newly published
  official providers are not missed.
