# Upstream Sync Guide

This is the working map for keeping this Swift package aligned with the
provider-facing packages in Vercel AI SDK (`@ai-sdk/*`). Use it as a playbook:
refresh upstream, choose one provider surface, port the behavior, add focused
tests, update the matrix, then commit and push the round.

## Current Snapshot

- npm provider search checked: 2026-06-02
- Discovery command:

  ```sh
  npm search "@ai-sdk" --json --searchlimit=250
  ```

- Upstream checkout: `/tmp/vercel-ai-sdk-upstream`
- Upstream commit pinned for this pass:

  ```text
  43e84c8e3 2026-06-01T13:12:00-07:00 Version Packages (canary) (#15748)
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

## Provider Round Playbook

Run provider sync as one vertical provider pass at a time. Do not bounce between
providers for unrelated warnings, stream parts, and tool gaps; finish the
selected provider's request shape, warnings, parsing, streams, docs, and live
smoke evidence before moving to the next provider:

1. Open the upstream package sources and tests listed in the provider row.
2. Compare provider factory/auth/base URL, model families, request body shape,
   warnings, option schemas, response metadata, provider metadata, usage, abort
   propagation, and upstream unsupported-family behavior.
3. Patch Swift code using the upstream option schema for `providerOptions.*`.
   Keep `extraBody` as the raw low-level escape hatch only where this Swift SDK
   already exposes one.
4. Add focused tests that fail on the discovered gap, including unsupported or
   rejected options when upstream has a schema.
5. Run focused tests, then `swift test`, then the opt-in live smoke suite when
   real keys are available.
6. Update this manifest only after the behavior is implemented and tested.
7. Commit and push the round before moving to the next provider.

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
| `*video*.ts` | Job creation, polling, status mapping, assets, and standard `n`/Swift `count` handling. |
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
| OpenAI Chat/Image | `@ai-sdk/openai`, chat and image model files | `AIProviders.openAI`, `OpenAICompatibleChatModel`, `OpenAICompatibleImageModel`, OpenAI tools. Image generation/edit results expose upstream-style OpenAI usage and `providerMetadata.openai.images` metadata, including revised prompts, created/model-option fields, and distributed image/text token details. | `OpenAIChatTests.swift`, `OpenAIMediaTests.swift` |
| OpenAI Responses | `@ai-sdk/openai`, responses model/tool files | `AIProviders.openAI`, `OpenAICompatibleResponsesModel`, `OpenAITools`. Streams preserve upstream text lifecycle parts for Responses message items, including `providerMetadata.openai.itemId` and Codex-style `phase` values such as `commentary` and `final_answer`, while keeping legacy text deltas. Reasoning item streams now mirror upstream `reasoning-start`/`reasoning-delta`/`reasoning-end` lifecycle IDs (`item_id:summary_index`) and provider metadata, including encrypted reasoning content on start/final end where upstream exposes it. Generate and stream calls now map Responses output-text annotations into `AISource` values for `url_citation`, `file_citation`, `container_file_citation`, and `file_path`, and stream `textEnd` metadata carries upstream annotation arrays. `contextManagement` maps to upstream `context_management` compaction requests, and streamed compaction output items emit `.custom` parts with `providerMetadata.openai.type/itemId/encryptedContent`. Hosted/custom tool output now mirrors upstream content shape for function/custom item metadata, provider-executed web-search results, computer-use tool calls/results, `tool_search_call`/`tool_search_output` ID pairing, MCP call/results, code-interpreter input lifecycle streams, image-generation partial results, apply-patch diff/delete-file input lifecycle streams, and `computer_use` request/tool-choice mapping through `OpenAITools.computerUse`. | `OpenAIResponsesTests.swift`, `ResponsesEndpointTests.swift` |
| OpenAI Files/Skills | `@ai-sdk/openai` file and skill clients | `OpenAIFileClient`, `OpenAISkillsClient` | `FileAndSkillClientTests.swift` |
| Azure OpenAI | `@ai-sdk/azure` | `AIProviders.azureOpenAI`, `AzureOpenAIProvider`, `AzureOpenAITools` | `AlibabaProdiaAzureQuiverTests.swift`, `OpenAIResponsesTests.swift` |
| OpenAI-compatible providers | `@ai-sdk/openai-compatible`, `deepseek`, `togetherai`, `groq`, `perplexity`, `fireworks`, `deepinfra`, `baseten`, `cerebras`, `moonshotai` | `OpenAICompatibleProvider`, provider-specific registry helpers | `OpenAICompatibleTests.swift`, `ProviderRegistryVercelTests.swift`, `CohereMistralVoyageTests.swift` |
| Groq | `@ai-sdk/groq/src/groq-chat-language-model.ts`, `groq-chat-language-model-options.ts`, `groq-prepare-tools.ts`, `groq-transcription-model.ts`, `groq-transcription-model-options.ts` | `AIProviders.groq`, `GroqLanguageModel`, `GroqTranscriptionModel`, `GroqTools`. Chat maps sampling, seed, reasoning effort/format, service tier, parallel tools, structured outputs, function tools, browser search, response metadata, text/reasoning/tool stream lifecycle parts, raw chunks, abort signals, and schema-validated `providerOptions.groq` for upstream chat options with enum/type checks, optional-field null rejection, unsupported-key stripping, null provider namespace no-op, and top-level reasoning fallback. Transcription maps standard Swift language/prompt plus schema-validated upstream `providerOptions.groq` (`language`, `prompt`, `responseFormat`, `temperature`, `timestampGranularities`) into multipart fields with nullish omission, range/type validation, unsupported-key stripping, null provider namespace no-op, upstream `audio.<media extension>` upload filenames, strict `x_groq.id`/verbose segment response validation, safe request/response metadata, verbose segments/language/duration, and abort signals while keeping `extraBody.groq` as the low-level escape hatch. | `GroqProviderTests.swift`, `ProviderAbortPropagationTests.swift`, `NativeAudioRequestMetadataTests.swift`, `NativeTranscriptionDetailTests.swift` |
| DeepSeek | `@ai-sdk/deepseek/src/chat/deepseek-chat-language-model.ts`, `convert-to-deepseek-chat-messages.ts`, `deepseek-prepare-tools.ts`, `convert-to-deepseek-usage.ts` | `AIProviders.deepSeek`, `AIProviders.deepseek`, `DeepSeekLanguageModel`. Chat maps text-only user messages, drops unsupported file/image parts with warnings, injects upstream JSON instructions, maps top-level reasoning with compatibility warnings, schema-validates `providerOptions.deepseek` (`thinking`, `reasoningEffort`) with enum/type checks, unknown-key stripping, nested `thinking` filtering, and null provider namespace no-op over raw `extraBody`, maps thinking, sampling, function tools/tool choice, cache/reasoning token usage, response/provider metadata, raw chunks, stream lifecycle parts, and abort signals. | `DeepSeekProviderTests.swift`, `ProviderAbortPropagationTests.swift` |
| Cerebras | `@ai-sdk/cerebras/src/cerebras-chat-language-model.ts`, `cerebras-provider.ts`, plus shared `@ai-sdk/openai-compatible` chat/prepare-tools/usage logic | `AIProviders.cerebras`, `CerebrasLanguageModel`. Chat follows the upstream OpenAI-compatible surface with Cerebras request-body transform (`reasoning_content` history becomes `reasoning`), sampling/user/seed/penalty fields, schema-validated `providerOptions.cerebras`/`openaiCompatible` typed options (`user`, `reasoningEffort`, `textVerbosity`, `strictJsonSchema`) with null/non-object rejection, null provider namespace no-op, and unknown raw passthrough preservation, function tools/tool choice, provider-tool warnings, strict structured outputs with recursive JSON Schema normalization, mixed structured-output/tool-call finish normalization, response/provider metadata, rich cache/reasoning token usage, raw chunks, stream lifecycle parts, and abort signals. | `CerebrasProviderTests.swift`, `ProviderAbortPropagationTests.swift` |
| xAI | `@ai-sdk/xai/src/xai-provider.ts`, `xai-chat-language-model.ts`, `responses/xai-responses-language-model.ts`, `xai-image-model.ts`, `xai-video-model.ts`, `files/xai-files-api.ts`, `tool/*` | `AIProviders.xAI`, `XAITools`, `XAIImageModel`, `XAIVideoModel`, `XAIFileClient`, OpenAI-compatible chat/responses models with xAI surface IDs. Chat uses the upstream xAI chat wire shape rather than the generic OpenAI-compatible body for xAI-specific fields: `maxOutputTokens` maps to `max_completion_tokens`, `seed` is forwarded, unsupported `topK`/penalties/stop sequences return warnings and are omitted, call-level JSON response formats map to xAI `json_schema`/`json_object`, schema-validated `providerOptions.xai` chat options (`reasoningEffort`, `logprobs`, `topLogprobs`, `parallel_function_calling`, `searchParameters`) strip unknown typed keys, reject invalid enum/range/source values, translate live-search camelCase fields to snake_case, treat null namespace as raw `extraBody` no-op, and keep raw `extraBody.xai` as the escape hatch. Chat message conversion now supports uploaded file provider references through `AIContentPart.providerReference`, resolves the `xai` file ID into `{type:"file", file:{file_id}}`, and throws a typed missing-reference error when no xAI reference is present. Chat usage also follows upstream xAI accounting for cached input tokens, non-inclusive cache reports, and output reasoning tokens in both generate and stream finish usage. Responses maps native xAI hosted tools and schema-validates `providerOptions.xai` response options (`reasoningEffort`, `reasoningSummary`, `logprobs`, `topLogprobs`, `store`, `previousResponseId`, `include`) with upstream enum/range/nullish behavior, unknown-key stripping, null namespace no-op over raw `extraBody`, `top_logprobs`/reasoning/previous-response key translation, and encrypted reasoning include injection when `store` is false. Image generation uses `/images/generations` or `/images/edits`, maps standard `aspectRatio`, schema-validates `providerOptions.xai` image options with upstream unknown-key stripping, keeps raw `extraBody.xai` as the low-level escape hatch, maps data-URI edit inputs, upstream unsupported `size`/`seed`/`mask` warnings, xAI image provider metadata, URL download fallback, response metadata, and abort signals. Video generation maps `/videos/generations`, `/videos/edits`, and `/videos/extensions`, mode fallback from `videoUrl`/`referenceImageUrls`, schema-validates known video options while preserving upstream passthrough fields, supports upstream nullish `resolution`/polling options, standard image inputs, standard resolution mapping (`1280x720` to `720p`, `854x480`/`640x480` to `480p`), edit/extension unsupported warnings and omitted fields, xAI request/progress/cost provider metadata, polling response metadata, and abort signals. Files upload xAI `team_id` from schema-validated `providerOptions.xai.teamId`, reject invalid `teamId`/`filePath`, treat a null namespace as raw `extraBody` no-op, omit OpenAI purpose/unrelated options, and preserve safe metadata. | `OpenAICompatibleTests.swift`, `ResponsesEndpointTests.swift`, `XAIChatProviderTests.swift`, `XAIProviderTests.swift`, `FileAndSkillClientTests.swift`, `ProviderAbortPropagationTests.swift` |
| Anthropic | `@ai-sdk/anthropic`, especially `convert-to-anthropic-prompt.ts`, `anthropic-language-model.ts`, `anthropic-prepare-tools.ts`, files/skills clients, and `tool/*` | `AIProviders.anthropic`, `AnthropicLanguageModel` with `anthropic.messages`, `AnthropicTools`, files on `anthropic.messages`, skills on `anthropic.skills`. Messages map uploaded file provider references through `AIContentPart.providerReference`, resolve the `anthropic` file ID into image/document `{source:{type:"file",file_id}}` blocks, add `files-api-2025-04-14`, and throw typed missing-reference errors. Language requests now read upstream-style `providerOptions.anthropic` for known Anthropic options and route `anthropicBeta` into the `anthropic-beta` header rather than the JSON body, while keeping raw `extraBody` as the low-level escape hatch. MCP servers, context management/compact edits, container skills, task budgets, and fast mode add their upstream beta headers automatically. Standard unsupported settings, temperature clamping, schema-less JSON response formats, thinking/sampling conflicts, container skills without code execution, and `temperature` plus `topP` return upstream-style warnings; ignored fields are omitted from request bodies, schema response formats map to `output_config.format`, and streams emit `.streamStart(warnings:)`. Streams preserve upstream text/reasoning content-block lifecycle parts, including `signature_delta` and `redacted_thinking` provider metadata, while keeping legacy deltas. Provider-executed tool result blocks for web search/fetch, code execution, tool search, advisor, and MCP emit upstream-shaped `AIToolResult` values in generate and stream paths. Generate results and stream finish metadata expose normalized Anthropic provider metadata for raw usage, stop sequence, code-execution/skills containers, and context-management applied edits. | `AnthropicTests.swift`, `AnthropicStreamingAndClientsTests.swift` |
| Anthropic AWS | `packages/anthropic-aws/src` | `AIProviders.anthropicAWS`, `AnthropicAWSProvider`, messages/files on `anthropic-aws.messages`, skills on `anthropic-aws.skills`; messages resolve uploaded `anthropic-aws` provider references into Anthropic file-source blocks and carry the same files beta. | `AnthropicTests.swift`, `AnthropicStreamingAndClientsTests.swift` |
| Amazon Bedrock native | `@ai-sdk/amazon-bedrock` | `AIProviders.amazonBedrock`, `AmazonBedrockLanguageModel`, `AmazonBedrockEmbeddingModel`, `AmazonBedrockImageModel`, `AmazonBedrockRerankingModel`; Converse maps native function `toolConfig`/`toolChoice`, providerOptions namespaces `amazonBedrock` and `bedrock`, topK, service tiers, guardrails, additional model request fields, Anthropic/OpenAI/Nova reasoningConfig variants, Anthropic thinking sampling warnings, request warnings on stream start, provider metadata, reasoning, tool-use streams, and SigV4 request cloning with `AIAbortSignal`. | `AmazonBedrockTests.swift`, `ProviderAbortPropagationTests.swift` |
| Bedrock Anthropic | `@ai-sdk/amazon-bedrock/src/anthropic/*` | `AIProviders.amazonBedrockAnthropic`, `AmazonBedrockAnthropicProvider`, `AmazonBedrockAnthropicLanguageModel` | `AmazonBedrockTests.swift` |
| Bedrock Mantle | `@ai-sdk/amazon-bedrock/src/mantle/*` | `AIProviders.bedrockMantle`, `AIProviders.amazonBedrockMantle`, OpenAI-compatible chat/responses models with AWS auth | `AmazonBedrockTests.swift` |
| Google Gemini | `@ai-sdk/google` | `AIProviders.google`, `GoogleGenerativeAIModel`, `GoogleTools`; language/embedding/image/video/files use `google.generative-ai`, interactions use `google.generative-ai.interactions`; GenerateContent maps structured response formats, standard `topK`/penalty/seed settings, top-level reasoning to Gemini thinking config, scoped `providerOptions.google`, Gemini `serviceTier`, function tools, provider-defined tools, and tool choice. It returns upstream-style warnings for unsupported Google provider tools, pre-Gemini-3 function/provider tool mixing, non-Vertex `vertex_rag_store`, incompatible Vertex-only options, and reasoning compatibility; typed provider options strip unknown keys, unsupported tools/provider-only control fields are omitted from request bodies, Gemma system prompts are prepended to first user content instead of sent as `systemInstruction`, stream-start carries warnings, `providerMetadata.google.thoughtSignature` is preserved/replayed, Gemini 3 missing-signature replays inject Google's `skip_thought_signature_validator` sentinel with a warning, provider-executed `executableCode`/`codeExecutionResult` and `toolCall`/`toolResponse` parts map to Swift tool calls/results, streaming `inlineData` maps to `AIStreamFile`, and GenerateContent provider metadata preserves safety ratings, prompt feedback, grounding/url context metadata, finish messages, and service tier for generate and stream finishes. Video and interactions polling forward `AIAbortSignal`. | `GoogleGenerativeAITests.swift`, `ProviderAbortPropagationTests.swift` |
| Google Vertex | `@ai-sdk/google-vertex` | `AIProviders.googleVertex`, `GoogleVertexProvider` with `google.vertex.chat`, `.embedding`, `.image`, `.video`; `GoogleVertexAnthropicProvider`, `GoogleVertexTools`, `GoogleVertexAnthropicTools`; Vertex GenerateContent shares Google structured response, standard sampling, reasoning/thinking config, Gemma system-prompt placement, rich tool/code-execution parsing, Gemini 3 thought-signature sentinel replay, provider metadata extraction, provider-tool warning, request-omission, and stream-start warning behavior while reading `providerOptions.googleVertex`, legacy `vertex`, and fallback `google`; it maps `sharedRequestType`/`requestType` to Vertex PayGo headers, warns and drops Gemini-only `serviceTier`, preserves Vertex auth/base URL/request builders, and forwards `AIAbortSignal`. | `GoogleVertexTests.swift`, `ProviderAbortPropagationTests.swift` |
| AI Gateway | `@ai-sdk/gateway` | `AIProviders.gateway`, `GatewayProvider`, `GatewayTools`, `GatewayManagementClient` | `GatewayTests.swift` |
| Mistral | `@ai-sdk/mistral/src/mistral-provider.ts`, `mistral-chat-language-model.ts`, `mistral-chat-language-model-options.ts`, `convert-to-mistral-chat-messages.ts`, `mistral-prepare-tools.ts`, `mistral-embedding-model.ts`, `mistral-embedding-options.ts`, `mistral-error.ts` | `AIProviders.mistral`, `MistralLanguageModel`, `MistralEmbeddingModel`. Chat maps v4 sampling warnings, seed, JSON response format, reasoning effort, function tools/tool choice, response metadata, stream lifecycle parts, abort signals, assistant `tool_calls`, and role `tool` messages with upstream-style `modelOutput ?? result` content. Language `providerOptions.mistral` is schema-validated against upstream chat options with type/enum checks, optional-field null rejection, unsupported-key stripping, structured-output control handling, and raw `extraBody` as the low-level passthrough escape hatch. Embedding uses native `/embeddings`, provider ID `mistral.embedding`, `MISTRAL_API_KEY`, 32-input limit, float encoding, token usage, and request/response metadata. | `CohereMistralVoyageTests.swift`, `ProviderAbortPropagationTests.swift` |
| Cohere | `@ai-sdk/cohere/src/cohere-provider.ts`, `cohere-chat-language-model.ts`, `cohere-chat-language-model-options.ts`, `cohere-embedding-model.ts`, `cohere-embedding-model-options.ts`, `reranking/cohere-reranking-model.ts`, `reranking/cohere-reranking-model-options.ts`, `cohere-error.ts` | `AIProviders.cohere`, `CohereLanguageModel`, `CohereEmbeddingModel`, `CohereRerankingModel`. Chat maps v4 sampling, JSON response format, reasoning/thinking, function tools/tool choice, response metadata, stream lifecycle parts, and abort signals to the native `/v2/chat` API. Language `providerOptions.cohere` is schema-validated against upstream chat options (`thinking` only) with nested type/number checks, unsupported-key stripping, optional-field null rejection, top-level reasoning fallback, and raw `extraBody` as the low-level passthrough escape hatch. Embedding and reranking use native `/embed` and `/rerank`, provider IDs `cohere.textEmbedding` and `cohere.reranking`, `COHERE_API_KEY`, 96-input embedding limit, float embedding output, token usage, request/response metadata, schema-validated upstream `providerOptions.cohere` (`inputType`/`truncate`/`outputDimension` and `maxTokensPerDoc`/`priority`), upstream snake_case option mapping, raw `extraBody` passthrough, and upstream-style object-document stringification warnings for reranking. Current Swift core has no part-level providerOptions slot, so upstream `cohereImagePartProviderOptions.detail` is documented as a known API-shape gap rather than silently mapped. | `CohereMistralVoyageTests.swift`, `CohereProviderOptionSchemaTests.swift`, `ProviderAbortPropagationTests.swift` |
| Voyage | `@ai-sdk/voyage/src/voyage-provider.ts`, `voyage-embedding-model.ts`, `voyage-embedding-model-options.ts`, `reranking/voyage-reranking-model.ts`, `reranking/voyage-reranking-model-options.ts`, `voyage-error.ts` | `AIProviders.voyage`, `VoyageEmbeddingModel`, `VoyageRerankingModel`. Embedding and reranking use the native `/embeddings` and `/rerank` endpoints, provider IDs `voyage.embedding` and `voyage.reranking`, `VOYAGE_API_KEY`, 128-input embedding limit, sorted embedding output, token usage, request/response metadata, schema-validated upstream `providerOptions.voyage` (`inputType` nullable enum, `truncation`, `outputDimension`, `outputDtype`, `returnDocuments`), unsupported-key stripping, optional-field null rejection except the upstream nullable `inputType`, upstream snake_case option mapping, raw `extraBody` passthrough, and upstream-style object-document stringification warnings for reranking. | `CohereMistralVoyageTests.swift`, `VoyageProviderOptionSchemaTests.swift` |
| Vercel | `@ai-sdk/vercel/src/vercel-provider.ts`, `vercel-chat-options.ts` | `AIProviders.vercel`, `VercelProvider`. Language maps the upstream callable/chat model wrapper over OpenAI-compatible chat, default base URL `https://api.v0.dev/v1`, provider ID `vercel.chat`, v0 chat model IDs, `ai-sdk/vercel` user-agent suffix, and upstream header order: `VERCEL_API_KEY` is still required/loaded before custom headers can override `Authorization`. Embedding/text-embedding and image model factories throw unsupported errors like upstream `NoSuchModelError`; Swift also rejects other non-language families through the common provider surface. | `ProviderRegistryVercelTests.swift` |
| Hugging Face | `@ai-sdk/huggingface/src/huggingface-provider.ts`, `huggingface-config.ts`, `huggingface-error.ts`, `responses/huggingface-responses-language-model.ts`, `responses/convert-to-huggingface-responses-messages.ts`, `responses/huggingface-responses-language-model-options.ts`, `responses/huggingface-responses-prepare-tools.ts`, `responses/convert-huggingface-responses-usage.ts` | `AIProviders.huggingFace`, `AIProviders.huggingface`, `HuggingFaceProvider`, `HuggingFaceResponsesLanguageModel`. Language maps the upstream callable/responses wrapper, default router URL `/v1/responses`, `HUGGINGFACE_API_KEY`, provider ID `huggingface.responses`, response message/image conversion, unsupported non-image file parts, structured output `text.format`, schema-validated `providerOptions.huggingface` (`metadata`, `instructions`, `strictJsonSchema`, `reasoningEffort`) with type checks, optional-field null rejection, unsupported-key stripping, and raw `extraBody` as the low-level passthrough escape hatch. Function tools include upstream top-level descriptions where the Swift schema supplies one, tool choice maps `auto`/`required`/named `tool` and ignores `none` like upstream, and language calls preserve unsupported setting warnings, response metadata/provider metadata, usage, SSE text/reasoning/tool lifecycle parts, and unsupported embedding/image families. | `ProviderRegistryVercelTests.swift`, `HuggingFaceProviderTests.swift` |
| Fireworks, DeepInfra, Baseten, MoonshotAI | provider packages with OpenAI-compatible cores plus native media pieces | OpenAI-compatible chat/completion/embedding with upstream surface IDs such as `fireworks.chat`, `deepinfra.embedding`, plus native image models where upstream defines them. Fireworks image generation maps standard aspect ratio/seed/count and upstream size splitting, warns for unsupported size/aspect-ratio combinations, ignores extra input images/masks with upstream warnings, keeps nested `providerOptions.fireworks` as a request-body override layer over raw `extraBody`, forwards `AIAbortSignal` across async submit/poll/download requests, preserves download response metadata for async image outputs, and mirrors upstream async poll error messages. DeepInfra chat mirrors upstream's Gemma/Gemini usage correction when reasoning tokens exceed completion tokens for generate and stream results. DeepInfra image generation uses the upstream `/inference/{model}` endpoint, maps standard aspect ratio/seed/count and upstream size splitting, caps image generation at one image per call, keeps nested `providerOptions.deepinfra` as a request-body override layer over raw `extraBody` for generation and edit multipart requests, and resolves URL edit files through safe downloads. Baseten preserves `ProviderSettings.modelURL` separately from `baseURL`: chat uses `/sync/v1` as a dedicated OpenAI-compatible endpoint, rejects `/predict`, falls back to the default Model API for plain `/sync` like upstream, keeps embeddings on `/sync[/v1]/v1/embeddings`, and strips nested Baseten embedding provider options because upstream defines an empty embedding options schema. MoonshotAI chat requests stream usage by default, schema-validates `providerOptions.moonshotai`/`moonshotAI` thinking and `reasoningHistory`, maps those fields to upstream `thinking.budget_tokens` and `reasoning_history`, maps provider-specific cache/reasoning usage into rich `TokenUsage` fields, and returns an empty usage object when upstream omits usage to mirror its converter's null/undefined case. | `FireworksProviderTests.swift`, `DeepInfraProviderTests.swift`, `BasetenProviderTests.swift`, `MoonshotAIProviderTests.swift`, `NativeMediaProviderTests.swift`, `OpenAICompatibleTests.swift`, `ProviderAbortPropagationTests.swift` |
| TogetherAI | `@ai-sdk/togetherai/src/togetherai-provider.ts`, `togetherai-image-model.ts`, `togetherai-image-model-options.ts`, `reranking/togetherai-reranking-model.ts`, `reranking/togetherai-reranking-model-options.ts` | `AIProviders.togetherAI`, `AIProviders.togetherai`, OpenAI-compatible chat/completion/embedding models plus `TogetherAIImageModel` and `TogetherAIRerankingModel`. The provider accepts `TOGETHER_API_KEY` plus deprecated `TOGETHER_AI_API_KEY`; image generation maps seed/count/size with upstream `parseInt`-style dimension splitting, base64 response format, single reference image handling, aspect-ratio warnings, mask rejection, schema-scoped `providerOptions.togetherai` validation with upstream passthrough image options, request/response metadata, and abort signals. Reranking maps native `/rerank`, JSON object documents, schema-validated `rankFields` from `providerOptions.togetherai`, strips unknown schema provider options, keeps `return_documents=false`, response metadata, and abort signals while keeping raw `extraBody` as the low-level escape hatch. | `TogetherAIProviderTests.swift`, `NativeMediaResponseMetadataTests.swift`, `NativeVectorResponseMetadataTests.swift`, `ProviderAbortPropagationTests.swift` |
| Replicate | `@ai-sdk/replicate/src/replicate-provider.ts`, `replicate-image-model.ts`, `replicate-image-model-options.ts`, `replicate-video-model.ts`, `replicate-video-model-options.ts` | `AIProviders.replicate`, `ReplicateImageModel`, and `ReplicateVideoModel`. Image generation maps versioned and unversioned prediction endpoints, standard `size`/`aspectRatio`/`seed`/`count`, Flux-2 multi-image fields and warnings, mask/data-URI inputs, sync `prefer` wait headers, schema-validated `providerOptions.replicate` with upstream loose passthrough and nullish semantics, safe output downloads, response metadata, and abort signals. Video generation maps versioned and unversioned prediction endpoints, standard `image`/`aspectRatio`/`resolution`/`durationSeconds`/`fps`/`seed`, schema-validated upstream video options with nullish known-option omission and unknown passthrough, polling options, final prediction metadata, response metadata, and abort signals while keeping raw `extraBody.replicate` as the low-level escape hatch. | `ReplicateProviderTests.swift`, `NativeMediaResponseMetadataTests.swift`, `ProviderAbortPropagationTests.swift` |
| fal | `@ai-sdk/fal/src/fal-provider.ts`, `fal-image-model.ts`, `fal-image-model-options.ts`, `fal-video-model.ts`, `fal-video-model-options.ts`, `fal-speech-model.ts`, `fal-speech-model-options.ts`, `fal-transcription-model.ts`, `fal-transcription-model-options.ts` | `AIProviders.fal`, `FalImageModel`, `FalVideoModel`, `FalSpeechModel`, and `FalTranscriptionModel`. Image maps `https://fal.run/{model}`, standard `size`/`aspectRatio`/`seed`/`count`, files/masks, safe image downloads, upstream metadata, multi-image warnings, schema-scoped `providerOptions.fal` with deprecated snake_case mapping/warnings, nullish known-option omission, and passthrough unknown fields. Video maps queue submit/poll endpoints, standard `image`/`aspectRatio`/`durationSeconds`/`seed`, provider metadata, schema-scoped video options with known nullish omission and passthrough unknown fields, polling options, and abort signals. Speech maps standard `voice`/`speed`, URL/hex output selection, schema-validated loose speech options (`voice_setting`, `audio_setting`, `language_boost`, `pronunciation_dict`), language/output-format warnings, submit/download metadata, and abort signals. Transcription maps queue submit/poll, base64 audio URL, upstream defaults for typed `providerOptions.fal` (`language`, `diarize`, `chunkLevel`, `version`, `batchSize`), unknown-key stripping for typed options, chunks/language/duration, response metadata, and abort signals while keeping raw `extraBody.fal` as the low-level escape hatch. | `FalProviderTests.swift`, `FalMediaProviderTests.swift`, `ProviderAbortPropagationTests.swift` |
| Alibaba | `@ai-sdk/alibaba/src/alibaba-provider.ts`, `alibaba-chat-language-model.ts`, `alibaba-chat-language-model-options.ts`, `convert-to-alibaba-chat-messages.ts`, `convert-alibaba-usage.ts`, `alibaba-video-model.ts`, `alibaba-video-model-options.ts` | `AIProviders.alibaba`, `AlibabaLanguageModel`, `AlibabaVideoModel`. Chat maps top-level sampling/seed/reasoning/JSON response format, strict schema-scoped `providerOptions.alibaba` (`enableThinking`, positive `thinkingBudget`, `parallelToolCalls`) with unsupported-key stripping, function tools/tool choice, provider-tool and unsupported part warnings, assistant tool-call history, tool-result messages, rich cache/read/write and reasoning token usage, response metadata, raw chunks, stream lifecycle parts, and abort signals. Video maps DashScope async submit/poll endpoints, standard `image`, `resolution`, `seed`, `durationSeconds`, `count`/upstream `n` warnings, schema-scoped video options (`negativePrompt`, `audioUrl`, `promptExtend`, `shotType`, `watermark`, `audio`, `referenceUrls`, polling options`) with nullish omission and known-field validation, unsupported `aspectRatio`/`fps` warnings, final task provider metadata, response metadata, and abort signals while keeping raw `extraBody.alibaba` as the low-level escape hatch. | `AlibabaProviderTests.swift`, `ProviderAbortPropagationTests.swift` |
| Prodia | `@ai-sdk/prodia/src/prodia-language-model.ts`, `prodia-language-model-options.ts`, `prodia-image-model.ts`, `prodia-image-model-options.ts`, `prodia-video-model.ts`, `prodia-video-model-options.ts`, `prodia-api.ts` | `AIProviders.prodia`, `ProdiaLanguageModel`, `ProdiaImageModel`, `ProdiaVideoModel`. Language uses the upstream multipart `/job?price=true` flow, prompts from system plus latest user text, image input multipart upload with top-level image MIME detection/fallback, zod-parity `providerOptions.prodia.aspectRatio` enum validation with unknown option stripping, unsupported LLM warnings, generated image file stream parts, job provider metadata, response metadata, and abort signals. Image maps standard `size`/`seed`, zod-parity `providerOptions.prodia` width/height/steps/style preset/LoRAs/progressive validation and unknown stripping, invalid-size warnings, multipart output parsing, job provider metadata, response metadata, and abort signals. Video maps prompt/seed, zod-parity `providerOptions.prodia.resolution` string validation and unknown stripping, txt2vid JSON jobs, img2vid multipart image jobs, job provider metadata, response metadata, and abort signals while keeping `extraBody.prodia` as the low-level escape hatch. | `ProdiaProviderTests.swift`, `ProviderAbortPropagationTests.swift` |
| QuiverAI | `@ai-sdk/quiverai/src/quiverai-provider.ts`, `quiverai-image-model.ts`, `quiverai-image-model-options.ts` | `AIProviders.quiverAI`, `AIProviders.quiverai`, `QuiverAIImageModel`. Image generation maps upstream `/svgs/generations` and `/svgs/vectorizations`, canonical model IDs, zod-parity `providerOptions.quiverai` validation for operation/instructions/sampling/token/vectorize options with type/range/enum checks, unknown option stripping, and null accepted only for nullable `presencePenalty`, standard unsupported `size`/`aspectRatio`/`seed`/`mask` warnings, reference-image limits (`4` normally, `16` for `arrow-1.1-max`), SVG payloads, usage tokens, image provider metadata, `QUIVERAI_BASE_URL`, response metadata, and abort signals while keeping `extraBody.quiverai` as the low-level escape hatch. | `QuiverAIProviderTests.swift`, `ProviderAbortPropagationTests.swift` |
| Luma | `@ai-sdk/luma/src/luma-provider.ts`, `luma-image-model.ts`, `luma-image-model-options.ts` | `AIProviders.luma`, `LumaImageModel`. Image generation maps upstream Dream Machine submit/poll/download flow, top-level `aspectRatio`, `providerOptions.luma` validated known fields (`referenceType`, `images`, `pollIntervalMillis`, `maxPollAttempts`) plus upstream passthrough request options, null provider namespace as a no-op over `extraBody`, URL-only reference images for `image`/`style`/`character`/`modify_image`, unsupported `size`/`seed` warnings, upstream numeric polling semantics including zero polling attempts, upstream response metadata from the submit response headers while keeping the completed generation JSON as `rawValue`, `LUMA_API_KEY`, and abort signals across submit, poll, and download requests while keeping `extraBody.luma` as the low-level escape hatch. | `LumaProviderTests.swift`, `ProviderAbortPropagationTests.swift` |
| KlingAI | `@ai-sdk/klingai/src/klingai-provider.ts`, `klingai-auth.ts`, `klingai-video-model.ts`, `klingai-video-model-options.ts` | `AIProviders.klingAI`, `AIProviders.klingai`, `KlingAIVideoModel`. Video generation maps upstream text-to-video, image-to-video, and motion-control suffix routing; `providerOptions.klingai` validates known camelCase fields for mode, polling, negative prompts, camera, multi-shot, voice, element, mask, watermark, and motion-control settings while preserving upstream passthrough for unknown keys, treating a null namespace as a no-op and rejecting non-object namespaces like upstream `parseProviderOptions`; standard image/duration/aspect ratio behavior follows mode-specific upstream warnings, including `count`/upstream `n` when more than one video is requested; polling waits the configured interval before each status request including the first one, matching upstream delay semantics; results preserve task/video provider metadata, response metadata, `KLINGAI_ACCESS_KEY`/`KLINGAI_SECRET_KEY` JWT auth, and abort signals for create/poll requests while keeping `extraBody.klingai` as the low-level escape hatch with legacy snake_case aliases. | `KlingAIProviderTests.swift`, `ProviderAbortPropagationTests.swift` |
| ByteDance | `@ai-sdk/bytedance/src/bytedance-provider.ts`, `bytedance-video-model.ts`, `bytedance-video-settings.ts`, `bytedance-config.ts` | `AIProviders.byteDance`, `AIProviders.bytedance`, `ByteDanceVideoModel`. Video generation maps upstream submit/poll flow, standard `aspectRatio`, `durationSeconds`, `seed`, `resolution`, `count`/upstream `n` warnings, standard `image` data URI input, `providerOptions.bytedance` validated known camelCase fields for reference media, output options, polling, and service tier plus upstream passthrough for unknown keys, treating a null namespace as a no-op and rejecting non-object namespaces like upstream `parseProviderOptions`; unsupported `fps` warnings, upstream `ARK_API_KEY` authentication, final task provider metadata, response metadata, and abort signals for create/poll requests while keeping `extraBody.bytedance` as the low-level escape hatch with legacy snake_case media aliases and resolution mapping. | `ByteDanceProviderTests.swift`, `ProviderAbortPropagationTests.swift` |
| Black Forest Labs | `@ai-sdk/black-forest-labs/src/black-forest-labs-provider.ts`, `black-forest-labs-image-model.ts`, `black-forest-labs-image-model-options.ts`, `black-forest-labs-image-settings.ts` | `AIProviders.blackForestLabs`, `BlackForestLabsImageModel`. Image generation maps upstream submit/poll/download flow, standard `size`/`aspectRatio`/`seed`, URL/base64 input images and masks, `providerOptions.blackForestLabs` with upstream strict schema validation for prompt/image/size/sampling/output/webhook/polling options, unsupported-key filtering, null namespace no-op, and non-object namespace rejection like upstream `parseProviderOptions`; upstream size warnings, max-attempt polling timeout semantics, final image provider metadata, download response metadata, `BFL_API_KEY`/`BLACK_FOREST_LABS_API_KEY`, and abort signals across submit, poll, and download requests while keeping `extraBody.blackForestLabs` as the low-level escape hatch. | `BlackForestLabsProviderTests.swift`, `ProviderAbortPropagationTests.swift` |
| Deepgram | `@ai-sdk/deepgram/src/deepgram-provider.ts`, `deepgram-transcription-model.ts`, `deepgram-transcription-model-options.ts`, `deepgram-speech-model.ts`, `deepgram-speech-model-options.ts`, `deepgram-error.ts` | `AIProviders.deepgram`, `DeepgramTranscriptionModel`, `DeepgramSpeechModel`. Transcription maps raw-audio `/v1/listen`, model/default diarization, schema-validated `providerOptions.deepgram` using the upstream serializer allow-list, ignores the standard Swift `language` shortcut like upstream, transcript text/segments/language/duration, response metadata, `DEEPGRAM_API_KEY`, and abort signals. Speech maps `/v1/speak`, output format to encoding/container/sample-rate with upstream's per-encoding sample-rate allow-lists and unknown-format no-op behavior, schema-validated `providerOptions.deepgram` through the upstream TTS option schema, null provider namespace no-op, incompatible encoding/container/sample-rate/bit-rate warnings, unsupported standard voice/speed/language/instructions warnings, request/response metadata, and abort signals while keeping `extraBody.deepgram` as the low-level escape hatch. | `DeepgramProviderTests.swift`, `NativeAudioRequestMetadataTests.swift`, `NativeAudioResponseMetadataTests.swift`, `NativeTranscriptionDetailTests.swift`, `ProviderAbortPropagationTests.swift` |
| ElevenLabs | `@ai-sdk/elevenlabs/src/elevenlabs-provider.ts`, `elevenlabs-config.ts`, `elevenlabs-speech-model.ts`, `elevenlabs-speech-model-options.ts`, `elevenlabs-transcription-model.ts`, `elevenlabs-transcription-model-options.ts`, `elevenlabs-error.ts` | `AIProviders.elevenLabs`, `AIProviders.elevenlabs`, `ElevenLabsSpeechModel`, `ElevenLabsTranscriptionModel`. Speech maps `/v1/text-to-speech/{voice}`, default voice/output format, exact case-sensitive upstream output-format aliases, standard `language`/`speed`, upstream unsupported `instructions` warning, TTS voice settings, pronunciation dictionaries, text normalization, request ID context, logging query flags, schema-validated `providerOptions.elevenlabs`, null provider namespace no-op, request/response metadata, `ELEVENLABS_API_KEY`, and abort signals. Transcription maps multipart `/v1/speech-to-text`, upstream `audio.<media extension>` upload filenames, model/default diarization, language from `providerOptions.elevenlabs.languageCode` (not the standard Swift shortcut), tag-audio-events/timestamp/file-format provider-option defaults, speaker counts, text/segments/language/duration, response metadata, schema-validated `providerOptions.elevenlabs`, null provider namespace no-op, and abort signals while keeping `extraBody.elevenlabs` as the low-level escape hatch. | `ElevenLabsProviderTests.swift`, `NativeAudioRequestMetadataTests.swift`, `NativeAudioResponseMetadataTests.swift`, `NativeTranscriptionDetailTests.swift`, `ProviderAbortPropagationTests.swift` |
| LMNT | `@ai-sdk/lmnt/src/lmnt-provider.ts`, `lmnt-config.ts`, `lmnt-speech-model.ts`, `lmnt-speech-model-options.ts`, `lmnt-error.ts` | `AIProviders.lmnt`, `LMNTSpeechModel`. Speech maps `/v1/ai/speech/bytes`, default voice `ava`, model ID body field, exact case-sensitive standard output formats with upstream fallback warning, standard `speed` and `language`, schema-validated `providerOptions.lmnt` (`sampleRate`, `topP`, `temperature`, `seed`, `conversational`, `length`, `speed`) including upstream nullish/default semantics, null provider namespace no-op, keeps provider `model` and `format` schema-checked but ignored like upstream, request/response metadata, `LMNT_API_KEY`, and abort signals while keeping `extraBody.lmnt` as the low-level escape hatch. | `LMNTProviderTests.swift`, `NativeAudioRequestMetadataTests.swift`, `NativeAudioResponseMetadataTests.swift`, `ProviderAbortPropagationTests.swift` |
| Hume | `@ai-sdk/hume/src/hume-provider.ts`, `hume-config.ts`, `hume-speech-model.ts`, `hume-speech-model-options.ts`, `hume-error.ts` | `AIProviders.hume`, `HumeSpeechModel`. Speech maps `/v0/tts/file`, default Hume voice ID/provider, standard `speed` and `instructions` into the first utterance, exact case-sensitive standard output formats with upstream fallback warning, upstream unsupported `language` warning, schema-validated `providerOptions.hume.context` with upstream nullish omission, null provider namespace no-op, required generation/utterance branches, nested key filtering, enum voice providers, context `generationId` and context utterances with `trailingSilence` translated to `trailing_silence`, request/response metadata, `HUME_API_KEY`, and abort signals while keeping `extraBody.hume` as the low-level escape hatch. | `HumeProviderTests.swift`, `NativeAudioRequestMetadataTests.swift`, `NativeAudioResponseMetadataTests.swift`, `ProviderAbortPropagationTests.swift` |
| RevAI | `@ai-sdk/revai/src/revai-provider.ts`, `revai-config.ts`, `revai-transcription-model.ts`, `revai-transcription-model-options.ts`, `revai-error.ts` | `AIProviders.revAI`, `AIProviders.revai`, `RevAITranscriptionModel`. Transcription maps multipart `/speechtotext/v1/jobs`, upstream `audio.<media extension>` media file naming, `config.transcriber`, standard Swift `language`, schema-validated `providerOptions.revai` with upstream defaults, null omission, null provider namespace no-op, nested object filtering, required translation targets, and enum validation, failed submission/status handling, upstream poll-before-delay cadence, transcript text/segments/language/duration, final transcript response metadata, `REVAI_API_KEY`, and abort signals across submit, status polling, and transcript fetch while keeping `extraBody.revai` as the low-level escape hatch. | `RevAIProviderTests.swift`, `NativeAudioResponseMetadataTests.swift`, `NativeTranscriptionDetailTests.swift`, `ProviderAbortPropagationTests.swift` |
| Gladia | `@ai-sdk/gladia/src/gladia-provider.ts`, `gladia-config.ts`, `gladia-transcription-model.ts`, `gladia-transcription-model-options.ts`, `gladia-error.ts` | `AIProviders.gladia`, `GladiaTranscriptionModel`. Transcription maps upload `/v2/upload`, initiation `/v2/pre-recorded`, result-url polling, upstream-style `audio.<media extension>` upload filenames, standard Swift `language`, schema-validated `providerOptions.gladia` with null omission, null provider namespace no-op, nested key filtering, required nested config fields, enum validation, nested option key translation for vocabulary/code-switching/callback/subtitles/diarization/translation/summarization/spelling, strict polling status/result validation, empty final result errors, final result provider metadata/details, response metadata, `GLADIA_API_KEY`, and abort signals across upload, initiation, and result polling while keeping `extraBody.gladia` as the low-level escape hatch. | `GladiaProviderTests.swift`, `NativeAudioResponseMetadataTests.swift`, `NativeTranscriptionDetailTests.swift`, `ProviderAbortPropagationTests.swift` |
| AssemblyAI | `@ai-sdk/assemblyai/src/assemblyai-provider.ts`, `assemblyai-config.ts`, `assemblyai-transcription-model.ts`, `assemblyai-transcription-model-options.ts`, `assemblyai-transcription-settings.ts`, `assemblyai-error.ts` | `AIProviders.assemblyAI`, `AIProviders.assemblyai`, `AssemblyAITranscriptionModel`. Transcription maps binary upload `/v2/upload`, submit `/v2/transcript`, final transcript polling, upstream `speech_model`, standard Swift `language`, schema-validated `providerOptions.assemblyai` with upstream nullish omission, null provider namespace no-op, integer/min/max validation, string-array validation, custom-spelling required `from`/`to` validation and nested key filtering, upstream transcript option key translation, strict submit/poll/final transcript validation, 3s poll cadence, upstream-style final error messages, transcript text/words/language/duration, final GET response metadata/details, `ASSEMBLYAI_API_KEY`, and abort signals across upload, submit, and poll requests while keeping `extraBody.assemblyai` as the low-level escape hatch. | `AssemblyAIProviderTests.swift`, `NativeAudioResponseMetadataTests.swift`, `NativeTranscriptionDetailTests.swift`, `ProviderAbortPropagationTests.swift` |
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
| OpenAI-compatible providers | Share the compatible model implementation, but keep provider-specific defaults, path quirks, headers, tools, provider IDs, and response metadata explicit. Chat/completion/responses generation, streaming, embeddings, images, speech, and transcription preserve upstream-style response headers and JSON bodies through `AIResponseMetadata` where the provider returns them. Chat/completion/responses also lift upstream provider metadata into the root provider namespace: chat accepted/rejected prediction token counts and content logprobs, completion logprobs, and Responses response IDs, service tier, and output logprobs. Chat streams emit v4-shaped text/reasoning lifecycle parts while keeping legacy `.textDelta`/`.reasoningDelta`; Responses streams emit v4 text lifecycle parts for message items and v4 reasoning lifecycle parts for reasoning items, including encrypted reasoning metadata where upstream exposes it. Responses output-text annotations map into source parts/results and text lifecycle provider metadata; Responses context-management compaction maps into native request fields and custom stream parts. Chat and Responses tool streams emit both legacy `.toolCallDelta` chunks and v4-shaped `.toolInputStart/.toolInputDelta/.toolInputEnd` lifecycle parts before the final `.toolCall`, and Responses hosted tool streams should emit upstream-shaped `.toolResult` parts for provider-executed results such as `computer_use`, result-only tool-search outputs, MCP calls, image-generation partial images, code-interpreter outputs, and apply-patch operations. Transcription models should also map upstream verbose fields (`segments`, `language`, `duration`) into `TranscriptionResult` whenever returned. |
| OpenAI/Azure provider IDs | Root providers stay `openai` and `azure`, but concrete models use upstream surface IDs: `openai.responses`, `openai.chat`, `openai.completion`, `openai.embedding`, `openai.image`, `openai.transcription`, `openai.speech`, `openai.files`, `openai.skills`; Azure uses the same pattern except embeddings is `azure.embeddings`. |
| xAI provider IDs and files | Root provider stays `xai`, concrete surfaces use `xai.responses`, `xai.chat`, `xai.image`, `xai.video`, and `xai.files`. xAI file uploads use `team_id` from schema-validated `providerOptions.xai.teamId`, keep null provider namespace as a no-op over raw `extraBody`, do not send OpenAI's `purpose` field, forward `AIAbortSignal`, and preserve upload response metadata. xAI video create/poll requests forward `AIAbortSignal`. |
| Provider options | Preserve upstream namespaces and avoid leaking provider-specific options into unrelated providers. |
| OpenAI-compatible warnings | Chat, completion, embedding, and image models return deprecated warnings for raw provider option keys such as `openai-compatible` or `test-provider`, pointing callers to the camelCase keys. Image models also return unsupported warnings for top-level `aspectRatio` and `seed`; these settings are intentionally not forwarded to OpenAI-style image endpoints. |
| Core v4 contract | Core request/result/stream types now have v4-shaped slots for provider options, response metadata, provider metadata, warnings, stream lifecycle parts, tool results/approval requests, files, custom parts, streamed errors, upstream-style abort signals through `AIAbortController`/`AIAbortSignal`, tool execution context through `AIToolExecutionContext`, and richer token-usage details for cache/read, text/reasoning, and raw provider usage. Provider passes should populate or propagate these fields when upstream exposes equivalent data. OpenAI-compatible chat/responses, Anthropic, Google GenerateContent/Interactions, native Bedrock, Gateway, Mistral, Cohere, Groq, DeepSeek, Cerebras, Alibaba, and Hugging Face Responses streaming now populate tool input start/delta/end parts while keeping final tool calls for existing consumers. OpenAI-compatible chat, OpenAI Responses, and Perplexity emit text lifecycle parts; OpenAI-compatible chat, OpenAI Responses reasoning items, Mistral, Cohere, Groq, DeepSeek, Cerebras, Alibaba, and Hugging Face Responses also emit text/reasoning start-delta-end lifecycle parts. Perplexity, MoonshotAI, Mistral, Cohere, Groq, DeepSeek, Cerebras, Alibaba, and Hugging Face language calls now forward abort signals; Perplexity, Mistral, Groq, DeepSeek, Alibaba, and Hugging Face also return upstream-style unsupported warnings for unsupported standard settings. Streaming providers must only emit `.raw(...)` chunks when `LanguageModelRequest.includeRawChunks` is true, matching upstream `includeRawChunks`. When adding provider helpers, keep abort propagation explicit through builder, signing, polling, and download steps. |
| Native response metadata | Use `aiResponseMetadata(...)` when native providers can expose upstream response metadata. It derives IDs/model IDs from provider JSON, preserves response headers and raw JSON bodies, and uses the current call time when the provider body has no `created` timestamp. Anthropic language, Perplexity language, Mistral chat language, Cohere chat language, Groq chat language, DeepSeek chat language, Cerebras chat language, Alibaba chat language, Hugging Face Responses language, Google Generative AI language/embedding/image/video/files, Google Vertex language/embedding/image/video, OpenAI-compatible multipart files, xAI files, OpenAI/Anthropic skill uploads, native embedding/reranking surfaces for Cohere, Voyage, Mistral, Baseten, Gateway, Amazon Bedrock, TogetherAI, and generic JSON reranking wrappers, native media surfaces for Replicate, fal, Fireworks, DeepInfra, TogetherAI, xAI, QuiverAI, generic JSON image/video wrappers, and native audio/transcription surfaces for Deepgram, ElevenLabs, LMNT, Hume, AssemblyAI, Rev.ai, Gladia, and Groq preserve metadata on results; language streams emit response metadata before model deltas. For submit/poll flows, attach metadata from the final provider result response when that JSON becomes the result `rawValue`, except where upstream explicitly returns submit response headers such as Luma image generation. For submit/download flows, mirror each upstream model: Fireworks async image outputs use the final download response metadata, while providers that expose submit metadata as their provider result should keep that submit response. |
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
