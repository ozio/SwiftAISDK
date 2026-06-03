# Provider Sync Status

Snapshot date: 2026-06-03

This file tracks provider-by-provider sync progress. `ProviderVersionLedger.md`
records npm versions; this file records how far each provider has been swept
against that version. Do not use the full provider inventory as the remaining
work list: most providers already have implementation and parity tests.

## Status Labels

- `fresh deep pass`: recently re-read against the npm package end to end and
  closed concrete request/options/warnings/metadata/route gaps in the same
  round, or explicitly found no safe remaining gap.
- `substantial parity coverage`: implementation has focused parity commits and
  tests for important upstream behavior, but still deserves one final end-to-end
  package pass before marking done.
- `needs explicit deep pass`: implemented or partially covered, but not yet
  tracked as a provider-complete sweep.

## Definition Of Done

Every provider deep pass must satisfy the global checklist and the
provider-specific checklist below. If a checklist item is intentionally out of
scope for SwiftAISDK, record that decision in the provider's evidence notes.

### No Infinite Rework Rule

Once a provider is marked `fresh deep pass`, do not revisit it just because it
"might still have gaps". Reopen it only when one of these happens:

- npm publishes a newer package version and we intentionally choose to sync it;
- a focused test, live smoke test, or user bug report identifies a concrete
  behavior mismatch;
- the Swift core contract changes in a way that affects the provider surface;
- a previously documented out-of-scope difference becomes in scope.

Every fresh deep pass must leave a provider completion record. Without that
record, the pass is not considered done, even if code was committed.

Provider completion record format:

```text
Package:
Baseline:
Upstream inspected:
Swift files inspected:
Surfaces checked:
Known Swift differences / out of scope:
Tests run:
Commit evidence:
Reopen only if:
```

`Known Swift differences / out of scope` must say `None known` when there are no
known differences. This is the confidence line: after a provider has this
record and passes tests, it leaves the active queue.

### Global Provider DoD

- `Version`: npm package version is checked and `ProviderVersionLedger.md` is
  updated if the pass uses a newer version.
- `Factory surface`: factory names, aliases, provider IDs, model IDs, default
  base URLs, environment variables, API-key loading, custom headers, and
  user-agent suffixes match upstream behavior or document a Swift-specific
  difference.
- `Supported capabilities`: language, completion, embedding, image, video,
  speech, transcription, reranking, files, and skills route to the right native
  implementation; unsupported capabilities throw the expected Swift error.
- `Request body`: standard options and provider options map to the upstream
  request shape, including camelCase/snake_case transforms, nullish handling,
  multipart fields, queue bodies, polling bodies, and passthrough fields.
- `Warnings`: unsupported standard settings, deprecated options, ignored inputs,
  provider-defined tools, and provider-specific limitations produce warnings
  equivalent to upstream intent.
- `Response parsing`: finish reasons, usage, token details, provider metadata,
  sources, media metadata, raw values, response headers, timestamps, operation
  IDs, and response bodies are preserved where upstream exposes them.
- `Streaming`: stream lifecycle, reasoning parts, text deltas, tool-call input
  deltas, provider metadata, raw chunks, error handling, and final usage match
  upstream for providers with streaming.
- `Tools`: function tools, provider-defined tools, tool choice, hosted tools,
  approval flows, and tool-result serialization are covered for providers that
  expose them.
- `Abort/retry`: abort signals propagate through create, stream, upload,
  download, and poll requests; retryability and retry-after behavior are covered
  where provider errors expose it.
- `Tests`: add focused mock-transport tests for each closed gap and run at least
  the provider-focused test filter plus full `swift test`.
- `Status`: update this file from `substantial parity coverage` or
  `needs explicit deep pass` to `fresh deep pass`, with commit evidence.

### Provider-Specific DoD

| Package | Provider-specific DoD |
| --- | --- |
| `@ai-sdk/alibaba` | Chat request/stream bodies, thinking options, tool calls, provider options, usage-only chunks, reasoning text, unsupported settings, abort propagation, and user-agent behavior are covered. |
| `@ai-sdk/amazon-bedrock` | Converse, InvokeModel/Anthropic, Bedrock Mantle, SigV4 signing, event-stream parsing, reasoning/tool-use blocks, cache/metadata, unsupported models, region/credential handling, and abort propagation are covered. |
| `@ai-sdk/anthropic` | Messages requests/streams, thinking/redacted thinking, citations, hosted tools, provider-defined tools, file references, beta headers, container/context metadata, warnings, usage, and abort propagation are covered. |
| `@ai-sdk/anthropic-aws` | AWS Anthropic wrapper routes, workspace/API-key headers, base URL/auth differences, unsupported capabilities, model identity, and parity with the tiny upstream wrapper are covered. |
| `@ai-sdk/assemblyai` | Upload, submit, poll, transcript schema, error statuses, provider options, segments, language/duration metadata, abort propagation across all requests, and response metadata are covered. |
| `@ai-sdk/azure` | Azure deployment routing, token provider/API-key auth, chat/responses/image/speech surfaces inherited from OpenAI, aliases, unsupported model families, headers, and user-agent behavior are covered. |
| `@ai-sdk/baseten` | Model API vs dedicated endpoint routing, `/sync` and `/sync/v1` behavior, embedding batching/body shape, model URL validation, headers, response metadata, and abort propagation are covered. |
| `@ai-sdk/black-forest-labs` | Image create/poll/download flow, option schema, prompt upsampling/raw/safety/options mapping, input/output megapixel metadata, warnings, timeout/poll attempts, and abort propagation are covered. |
| `@ai-sdk/bytedance` | Video submit/poll flow, T2V/I2V/R2V option mapping, dimensions/aspect options, warnings, provider metadata, operation IDs, timeout behavior, and abort propagation are covered. |
| `@ai-sdk/cerebras` | Chat request/stream bodies, reasoning transforms, structured response format, tool calls, provider options, finish/usage normalization, warnings, user agent, and abort propagation are covered. |
| `@ai-sdk/cohere` | Chat, stream, embeddings, reranking, documents/images, provider options, tool calls/provider-defined tool warnings, structured output, usage, user agent, and abort propagation are covered. |
| `@ai-sdk/deepgram` | Raw audio transcription, speech query/body mapping, encoding/sample-rate cleanup, provider options, language handling, warnings, response metadata, and abort propagation are covered. |
| `@ai-sdk/deepinfra` | OpenAI-compatible chat/embedding/image behavior, provider-specific user-agent/header behavior, image limits, response metadata, unsupported families, and abort propagation are covered. |
| `@ai-sdk/deepseek` | Chat request/stream bodies, reasoning models, reasoning history stripping/backfill, provider options, warnings, finish/usage mapping, tool calls, and abort propagation are covered. |
| `@ai-sdk/elevenlabs` | Speech and transcription multipart/JSON bodies, voice settings, output formats, provider options, transcription segments/language, response metadata, warnings, and abort propagation are covered. |
| `@ai-sdk/fal` | Image/video/speech/transcription routes, run vs queue endpoints, provider options, deprecated snake_case warnings, NSFW/media metadata, polling, downloads, and abort propagation are covered. |
| `@ai-sdk/fireworks` | OpenAI-compatible language plus native image behavior, image/edit options, Kontext warnings, size/aspect handling, response metadata, headers/user-agent, and abort propagation are covered. |
| `@ai-sdk/gateway` | V3 base URL, auth method headers, API-key/OIDC fallback, Gateway metadata endpoints, language/image/video/rerank surfaces, typed Gateway errors, retryability, and stream errors are covered. |
| `@ai-sdk/gladia` | Upload/initiate/poll result flow, polling statuses, provider options, language handling, transcription segments, response metadata, no-arg factory/custom user-agent, and abort propagation are covered. |
| `@ai-sdk/google` | GenerateContent and Interactions APIs, Gemini/Gemma system handling, tools/provider tools, code execution, grounding/sources, files, embeddings, video, structured output, streams, warnings, and abort propagation are covered. |
| `@ai-sdk/google-vertex` | Regional/project/publisher URL building, OAuth/PAYGO options, Gemini/Imagen/Veo bodies, reference images/masks, function tools, grounding, streams, response metadata, and abort propagation are covered. |
| `@ai-sdk/groq` | Chat/stream and transcription surfaces, reasoning, browser-search/provider-defined tools, structured output, tool calls, provider options, X-Groq-ID validation, usage, warnings, and abort propagation are covered. |
| `@ai-sdk/huggingface` | Responses-style language route, provider option schema, tool/tool-choice handling, provider-defined tool skipping, unsupported capabilities, stream lifecycle, warnings, and abort propagation are covered. |
| `@ai-sdk/hume` | TTS file endpoint, utterances, voice/context/options schema, language/output warnings, model identity, response metadata, and abort propagation are covered. |
| `@ai-sdk/klingai` | T2V/I2V/motion-control routes, JWT/auth/base URL, provider options, poll timing, required motion fields, image/aspect warnings, metadata, timeout, and abort propagation are covered. |
| `@ai-sdk/lmnt` | Speech body, voice/model identity, auth header casing, language/speed/options mapping, warnings, response metadata, and abort propagation are covered. |
| `@ai-sdk/luma` | Image generation/edit/reference flows, polling, character references, null namespace/nullish options, unsupported editing inputs, metadata, timeouts, and abort propagation are covered. |
| `@ai-sdk/mcp` | HTTP/SSE/Stdio transports, OAuth discovery/PKCE/refresh/register flows, resource/template/tool listing, elicitation, reconnects, tool output conversion, errors, and protocol capability checks are covered. |
| `@ai-sdk/mistral` | Chat/stream and embedding surfaces, native request shape, documents/files, structured output controls, tool calls/provider-tool warnings, provider options, usage, and abort propagation are covered. |
| `@ai-sdk/moonshotai` | Chat/stream bodies, thinking options, tool calls, provider options, unsupported capabilities, usage variants, finish mapping, user-agent behavior, and abort propagation are covered. |
| `@ai-sdk/open-responses` | Responses request/stream lifecycle, reasoning, annotations/sources, hosted tools, MCP approvals/results, image generation partials, compaction, apply-patch/code-interpreter parts, errors, and raw chunks are covered. |
| `@ai-sdk/openai` | Chat, Responses, completions, embeddings, images, speech, transcription, files, skills, tool helpers, provider aliases, organization/project headers, structured output, metadata, warnings, and abort propagation are covered. |
| `@ai-sdk/openai-compatible` | Chat/completion/embedding/image/audio/video/rerank surfaces, route selection, stream parsing, provider surface IDs, warning behavior, provider option passthrough, response metadata, and abort propagation are covered. |
| `@ai-sdk/perplexity` | Chat request/stream bodies, search/sources/citations, provider options, unsupported settings, finish/usage validation, response metadata, and abort propagation are covered. |
| `@ai-sdk/prodia` | Language/media routes, streaming generated files, image provider options, size warnings, response validation, headers/user-agent, and abort propagation are covered. |
| `@ai-sdk/quiverai` | SVG generate/vectorize endpoints, provider option schema, reference limits, response schema/usage, SVG base64 conversion, warnings, metadata, and abort propagation are covered. |
| `@ai-sdk/replicate` | Versioned/unversioned prediction routes, image/video inputs, Flux-2 multi-image behavior, provider options, prefer headers, polling, output downloads, metadata, and abort propagation are covered. |
| `@ai-sdk/revai` | Multipart job submit, transcript fetch, provider options, polling/result schema, segments/language/duration, response metadata, user-agent behavior, and abort propagation are covered. |
| `@ai-sdk/togetherai` | Image/reranking/native routes, media validation, reranking documents/query/options, response metadata, headers/user-agent, unsupported capabilities, and abort propagation are covered. |
| `@ai-sdk/vercel` | v0 endpoint, API-key/header/user-agent behavior, language model route, unsupported embeddings/media/audio/rerank capabilities, custom settings, and upstream aliases are covered. |
| `@ai-sdk/voyage` | Embeddings/reranking request bodies, option schema, input batching, response validation, usage/metadata, provider aliases, and abort propagation are covered. |
| `@ai-sdk/xai` | Chat/responses/image/video/files routes, provider references, reasoning/usage, provider options, warnings, tool helpers, file metadata, media polling, and abort propagation are covered. |

## Fresh Deep Pass

| Package | Baseline | Evidence |
| --- | --- | --- |
| `@ai-sdk/gateway` | `3.0.123` | `3294e3d`, `b8f35cb`, `08b36ed`: v3 base URL, headers/user agent, OIDC fallback, typed Gateway errors. |
| `@ai-sdk/anthropic-aws` | `1.0.3` | `135ceb6`: API-key header precedence and dynamic SigV4 credential-provider parity after package re-read. |
| `@ai-sdk/anthropic` | `3.0.81` | `30c3272`: provider auth/base URL/custom name, tool choice/parallel tool-use, eager stream tool inputs, provider option key merging, and abort propagation after package re-read. |
| `@ai-sdk/google-vertex` | `4.0.141` | `83ef81d`: regional REP hosts, express API-key precedence, embedding options/usage/limit, Veo polling/base64 videos, and subprovider URL parity after package re-read. |
| `@ai-sdk/google` | `3.0.80` | `09bfd11`: Gemini/Imagen/Veo/embeddings parity sweep: providerOptions, multimodal content, editing warnings, video polling/options, metadata, and abort propagation after package re-read. |
| `@ai-sdk/huggingface` | `1.0.50` | `e6ce75a`: provider-defined tools skipped with upstream-style warning after package re-read. |
| `@ai-sdk/fal` | `2.0.34` | `b8ebeaa`: image metadata NSFW/prompt normalization after package re-read. |
| `@ai-sdk/quiverai` | `1.0.0` | Re-read package and local implementation; no safe remaining gap found after existing QuiverAI option/schema/response tests. |
| `@ai-sdk/vercel` | `2.0.50` | Re-read package and local implementation; existing endpoint/header/user-agent/unsupported-family coverage matched the tiny upstream package. |

### Fresh Pass Completion Records

#### `@ai-sdk/gateway`

```text
Package: @ai-sdk/gateway
Baseline: 3.0.123
Upstream inspected: gateway provider package, v3 endpoint behavior, auth/header handling, Gateway error envelope behavior.
Swift files inspected: GatewayProvider.swift, GatewayModels.swift, GatewayErrors.swift, HTTP.swift, GatewayTests.swift.
Surfaces checked: provider factory, base URL, API-key auth, Vercel OIDC fallback, auth-method header, user-agent suffix, language/image/video/rerank routing, metadata, typed errors, retryability, retry-after, stream error mapping.
Known Swift differences / out of scope: Async Vercel OIDC refresh/request-context token loading is not modeled because Swift request headers are currently static.
Tests run: GatewayTests-focused tests during the pass, then full swift test in later provider rounds.
Commit evidence: 3294e3d, b8f35cb, 08b36ed.
Reopen only if: gateway npm version changes, Vercel OIDC behavior becomes async-required, Gateway error schema changes, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/anthropic-aws`

```text
Package: @ai-sdk/anthropic-aws
Baseline: 1.0.3
Upstream inspected: anthropic-aws-provider.ts, anthropic-aws-fetch.ts, index.ts, version.ts, plus Anthropic core generateId call sites that the AWS wrapper forwards through.
Swift files inspected: AnthropicAWSProvider.swift, Anthropic.swift, AnthropicTests.swift, AnthropicStreamingAndClientsTests.swift, ProviderRegistryVercelTests.swift.
Surfaces checked: provider factory, callable/chat/messages aliases, model identity, base URL trimming, workspace/API-key headers, API-key precedence over custom x-api-key, default and custom user-agent behavior, static SigV4 signing, async dynamic credential provider, session-token signing header, file and skill helpers, provider reference keys, inherited URL/PDF support, unsupported embeddings/images and broader Swift unsupported model families.
Known Swift differences / out of scope: Swift keeps acronym-style names such as workspaceID/accessKeyID; Swift exposes extra AIProvider families beyond upstream ProviderV3 and marks them unsupported; Anthropic core does not expose upstream generateId customization yet and currently emits deterministic source IDs, which is a cross-cutting Anthropic core follow-up rather than an Anthropic AWS wrapper gap.
Tests run: swift test --filter Anthropic; swift test with 868 tests.
Commit evidence: 135ceb6.
Reopen only if: anthropic-aws npm version changes, AWS wrapper auth/header/signing behavior changes, new wrapper-level settings or model families appear, Anthropic core generateId becomes in-scope, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/anthropic`

```text
Package: @ai-sdk/anthropic
Baseline: 3.0.81
Upstream inspected: anthropic-provider.ts, anthropic-messages-language-model.ts, anthropic-messages-options.ts, anthropic-prepare-tools.ts, convert-to-anthropic-messages-prompt.ts, anthropic-message-metadata.ts, anthropic-messages-api.ts, anthropic-tools.ts, tool helper files, get-cache-control.ts, forward-anthropic-container-id-from-last-step.ts, index.ts, version.ts.
Swift files inspected: Anthropic.swift, OpenAICompatibleProvider.swift, OpenAICompatible.swift, Core.swift, AI.swift, ProviderRegistry.swift, AnthropicTests.swift, AnthropicStreamingAndClientsTests.swift, NativeResponseMetadataTests.swift.
Surfaces checked: provider factory, callable/chat/messages aliases, default and custom base URL, API-key auth, Bearer auth token, explicit apiKey/authToken conflict, custom provider name for language models, custom providerOptions key merging, header/user-agent precedence, unsupported embedding/image/audio/video/rerank surfaces, Messages request body, Gemini-style not applicable, system/messages conversion, URL/image/PDF/file/provider-reference parts, file citation metadata, structured output, thinking/adaptive thinking rules, max-token adjustment, unsupported standard option warnings, metadata/context-management/container/mcp/output-config/speed/inference options, automatic beta headers, file and skill clients, Anthropic provider tools, unsupported provider-tool warnings, tool choice, disable_parallel_tool_use, stream eager_input_streaming defaults and opt-out, hosted tool result parsing, MCP tool result parsing, citations/sources, redacted thinking, compaction metadata, stream lifecycle/deltas/raw chunks/metadata, response metadata, and abort propagation through generate and stream.
Known Swift differences / out of scope: Swift keeps `extraBody` as a legacy escape hatch alongside typed `providerOptions.anthropic`; Swift exposes files/skills as additional provider capabilities even though the upstream ProviderV3 wrapper only exposes language/tools; Swift settings headers are static dictionaries rather than upstream async Resolvable headers; `generateId` customization is not exposed yet for Anthropic source IDs; Swift file/skill provider IDs remain `anthropic.messages`/`anthropic.skills` even when a custom language provider name is configured.
Tests run: swift test --filter Anthropic; swift test with 883 tests.
Commit evidence: 30c3272.
Reopen only if: @ai-sdk/anthropic npm version changes, Messages/Files/Skills/tool schemas change, providerOptions schemas change, generateId or async header behavior becomes required in Swift core, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/google-vertex`

```text
Package: @ai-sdk/google-vertex
Baseline: 4.0.141
Upstream inspected: google-vertex-provider.ts, google-vertex-provider-node.ts, google-vertex-embedding-model.ts, google-vertex-embedding-options.ts, google-vertex-image-model.ts, google-vertex-video-model.ts, google-vertex-video-settings.ts, google-vertex-tools.ts, maas/google-vertex-maas-provider.ts, xai/google-vertex-xai-provider.ts, anthropic/google-vertex-anthropic-provider.ts, index.ts, version.ts.
Swift files inspected: GoogleVertexProvider.swift, GoogleVertexModels.swift, GoogleGenerativeAI.swift, GoogleTools.swift, ProviderRegistry.swift, OpenAICompatibleProvider.swift, Anthropic.swift, Core.swift, AI.swift, GoogleVertexTests.swift, GoogleMediaResponseMetadataTests.swift.
Surfaces checked: default factories, callable/chat/language aliases, Express mode API key auth, API-key header precedence, OAuth/access-token/service-account routing, global/eu/us/regional hosts, custom base URL trimming, user-agent suffix, GenerateContent language bodies/streams/tools/grounding/provider metadata, URL/GCS support inherited by language/Gemini image calls, embedding request options/limit/usage, Imagen generation/edit reference images/masks, Gemini image generation path, Veo long-running operation polling, video URL/base64 outputs, video provider metadata, response metadata, MaaS OpenAI-compatible endpoint, xAI reasoning-effort stripping and usage conversion, Vertex Anthropic rawPredict/streamRawPredict shape and tool subset.
Known Swift differences / out of scope: Swift models Google auth with explicit accessToken/serviceAccount settings instead of node googleAuthOptions/edge GoogleCredentials; settings headers are static dictionaries rather than upstream async Resolvable headers; generateId customization is not exposed yet for Google/Vertex source IDs and media IDs; Swift keeps the public googleVertexMaaS/googleVertexXAI provider IDs already used by the capability matrix even though upstream MaaS package names the OpenAI-compatible wrapper "vertex.maas".
Tests run: swift test --filter GoogleVertex; swift test --filter GoogleMediaResponseMetadataTests; swift test with 869 tests.
Commit evidence: 83ef81d.
Reopen only if: google-vertex npm version changes, Vertex host/base URL rules change, Veo operation schema/polling changes, providerOptions schemas change, MaaS/xAI/Anthropic subprovider wrapper behavior changes, auth model changes become required for Swift, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/google`

```text
Package: @ai-sdk/google
Baseline: 3.0.80
Upstream inspected: google-provider.ts, google-generative-ai-language-model.ts, google-generative-ai-embedding-model.ts, google-generative-ai-embedding-options.ts, google-generative-ai-image-model.ts, google-generative-ai-video-model.ts, google-generative-ai-video-settings.ts, google-generative-ai-interactions-language-model.ts, google-generative-ai-files-api.ts, google-generative-ai-options.ts, google-prepare-tools.ts, tool helpers, index.ts, version.ts.
Swift files inspected: GoogleGenerativeAI.swift, GoogleTools.swift, ProviderRegistry.swift, Core.swift, AI.swift, GoogleGenerativeAITests.swift, GoogleMediaResponseMetadataTests.swift.
Surfaces checked: provider factory, callable/chat/language aliases, embedding/textEmbedding aliases, image/video/interactions/files/tool helpers, API-key/header precedence, user-agent suffix, base URL trimming, GenerateContent request bodies, Gemini/Gemma system handling, structured outputs, provider generation options, safety/cached/labels top-level options, provider-defined tools, tool choice, code execution, grounding metadata and sources, stream lifecycle/tool-call deltas/provider metadata/raw chunks, embeddings batch/single endpoints, embedding outputDimensionality/taskType/multimodal content/max input limit, Imagen generation shape/warnings/provider metadata, Imagen editing rejection, Gemini image file inputs/googleSearch/provider options, Veo long-running create/poll flow, standard image/seed/resolution/duration fields, reference images, video metadata, files resumable upload, Interactions/agents/streams/sources/tool steps, abort propagation through language/stream/embedding/image/video.
Known Swift differences / out of scope: Swift uses static headers rather than upstream async Resolvable headers; Swift keeps `extraBody` as a legacy escape hatch alongside typed `providerOptions.google`; `generateId` customization is not exposed for Google-generated source/tool IDs yet; Swift exposes interactions as explicit `interactionsModel`/`interactionsAgent` helpers rather than upstream's overloaded `interactions(modelIdOrAgent)` call shape.
Tests run: swift test --filter GoogleGenerativeAI; swift test with 877 tests.
Commit evidence: 09bfd11.
Reopen only if: @ai-sdk/google npm version changes, GenerateContent/Interactions/Files/Imagen/Veo/Embedding schemas change, providerOptions schemas change, generateId or async header behavior becomes required in Swift core, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/huggingface`

```text
Package: @ai-sdk/huggingface
Baseline: 1.0.50
Upstream inspected: Hugging Face provider package, responses language model tools handling.
Swift files inspected: HuggingFaceProvider.swift, HuggingFaceModels.swift, HuggingFaceProviderTests.swift.
Surfaces checked: provider factory, responses-style language route, provider option schema, tool/tool-choice mapping, provider-defined tool skipping, warnings, unsupported non-language capabilities, response/stream parsing.
Known Swift differences / out of scope: None known.
Tests run: HuggingFaceProviderTests-focused tests during the pass, then full swift test with 865 tests.
Commit evidence: e6ce75a.
Reopen only if: huggingface npm version changes, provider-defined tool behavior changes, stream schema changes, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/fal`

```text
Package: @ai-sdk/fal
Baseline: 2.0.34
Upstream inspected: fal-image-model.ts, fal-image-options.ts, fal-video-model.ts, fal-speech-model.ts, fal-transcription-model.ts, fal-provider.ts.
Swift files inspected: MediaProviderModels.swift, AudioProviderModels.swift, FalProviderTests.swift, FalMediaProviderTests.swift.
Surfaces checked: image run endpoint, video queue endpoint, speech run endpoint, transcription queue endpoint, provider options, deprecated snake_case warnings, file/data URL conversion, polling, downloads, image/video/audio metadata, NSFW metadata normalization, prompt metadata omission, abort propagation.
Known Swift differences / out of scope: None known for checked surfaces.
Tests run: swift test --filter FalProviderTests; full swift test with 865 tests.
Commit evidence: b8ebeaa plus earlier 1911946 and 0da0ca6.
Reopen only if: fal npm version changes, queue protocol changes, media metadata schema changes, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/quiverai`

```text
Package: @ai-sdk/quiverai
Baseline: 1.0.0
Upstream inspected: quiverai-image-model.ts, quiverai-image-model-options.ts, quiverai-image-settings.ts, quiverai-provider.ts.
Swift files inspected: QuiverAIModels.swift, OpenAICompatibleProvider.swift, ProviderRegistry.swift, QuiverAIProviderTests.swift.
Surfaces checked: image factory aliases, default base URL, API key/env handling, user-agent suffix, SVG generation endpoint, vectorization endpoint, provider option schema, reference limits, response schema, usage, SVG base64 conversion, warnings, unsupported standard image settings.
Known Swift differences / out of scope: None known for checked surfaces.
Tests run: QuiverAIProviderTests coverage exists; full swift test with 865 tests passed after the following Fal round.
Commit evidence: ba2bf36, 895e1e0, 2f94319, e14410c; no-change package re-read after these commits found no safe remaining gap.
Reopen only if: quiverai npm version changes, SVG response schema changes, new operations appear, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/vercel`

```text
Package: @ai-sdk/vercel
Baseline: 2.0.50
Upstream inspected: vercel provider package and tiny provider wrapper surface.
Swift files inspected: VercelProvider.swift, ProviderRegistry.swift, ProviderRegistryVercelTests.swift.
Surfaces checked: factory aliases, default v0 endpoint, API-key/env handling, custom headers, user-agent suffix, language model route, unsupported embedding/image/transcription/speech/video/rerank capabilities.
Known Swift differences / out of scope: None known for checked surfaces.
Tests run: ProviderRegistryVercelTests coverage exists; full swift test with 865 tests passed after the following Fal round.
Commit evidence: 5378d23 plus no-change package re-read after ledger baseline.
Reopen only if: vercel npm version changes, provider wrapper gains new capabilities, endpoint/header behavior changes, live smoke or user bug reports a concrete mismatch.
```

## Substantial Parity Coverage

These are not "untouched". They have concrete parity commits and tests, but are
still queued for a final package-level sweep if we want to stamp them complete.

| Package | Baseline | Existing parity evidence |
| --- | --- | --- |
| `@ai-sdk/open-responses` | `1.0.16` | `b3d4e27`, `fa5e36d`, `6832d59`, `866bd78`, `f8aeb19`, `002a70a`, `c61a3b4`, `998e27b`, `0d6b140`: lifecycle, reasoning, annotations, hosted tools, compaction, apply-patch streaming. |
| `@ai-sdk/openai` | `3.0.67` | `b363c3f`, `1c45140`, `e2ea865`, `b2a1dcc`: provider naming, shell tools, image metadata, user agent; broad OpenAI tests exist. |
| `@ai-sdk/openai-compatible` | `2.0.48` | `7aa1c55`: provider surfaces; broad OpenAI-compatible request/stream/warning tests exist. |
| `@ai-sdk/amazon-bedrock` | `4.0.112` | `85b8875`, `50d2289`, `1acd167`: converse options, Anthropic invoke parity, user agent. |
| `@ai-sdk/groq` | `3.0.39` | `55faaac`, `6627b3d`, `2fe28f0`: option schema, transcription response, chat parity. |
| `@ai-sdk/mistral` | `3.0.37` | `9ea7375`, `d4e5aab`: option schema and chat parity. |
| `@ai-sdk/cohere` | `3.0.36` | `5d2c1d9`, `6b81b90`: option schema and chat parity. |
| `@ai-sdk/perplexity` | `3.0.33` | `361673a`, `cac1cc7`: provider parity, finish/response validation. |
| `@ai-sdk/xai` | `3.0.93` | `b9cbbd3`, `4a63a9f`, `62183f0`, `b6543e7`, `899bb80`, `f5f3639`: image/video/options/responses/files/chat usage/provider refs/user agent. |
| `@ai-sdk/deepseek` | `2.0.35` | `cf03d70`, `9b1abb6`: provider options and reasoning history. |
| `@ai-sdk/cerebras` | `2.0.54` | `7583bf4`, `e271d29`, `7279a9a`: options, structured finish, user agent. |
| `@ai-sdk/moonshotai` | `2.0.23` | `80bcd36`, `2b244c6`, `c58f369`: options, chat parity, user agent. |
| `@ai-sdk/alibaba` | `1.0.25` | `5584aa1`, `24f2732`: provider options and user agent. |
| `@ai-sdk/azure` | `3.0.69` | `eb4119b`, `8026419`: aliases and token provider parity. |
| `@ai-sdk/baseten` | `1.0.51` | `cd81ac4`, `2399a21`: provider URL and embedding behavior. |
| `@ai-sdk/deepinfra` | `2.0.52` | `45b7c7a`, `6eaf86d`: provider parity and user agent. |
| `@ai-sdk/fireworks` | `2.0.53` | `b007be4`, `2ea4fb3`: image provider parity and user agent. |
| `@ai-sdk/togetherai` | `2.0.53` | `7511a6f`, `ee8e15f`, `8a1c02d`: provider/media validation/user agent. |
| `@ai-sdk/replicate` | `2.0.33` | `8daa1f2`, `accb711`: provider options and media headers. |
| `@ai-sdk/luma` | `2.0.33` | `dc57b58`, `b3748dc`, `4ba33a7`: option parsing/options/user agent. |
| `@ai-sdk/klingai` | `3.0.18` | `0427e53`, `231fd57`, `24f2732`: option schema/options/user agent. |
| `@ai-sdk/black-forest-labs` | `1.0.34` | `85a7d8a`, `90e0eea`, `8870500`: option schema/options/user agent. |
| `@ai-sdk/bytedance` | `1.0.14` | `1dc15dd`, `380ceac`: option schema/options. |
| `@ai-sdk/prodia` | `1.0.31` | `d568b7a`, `8f7bee3`, `e1c6a8a`: option schema/options/user agent. |
| `@ai-sdk/deepgram` | `2.0.33` | `1b5240b`, `5bd5ce8`, `035167f`: option schema/options/user agent. |
| `@ai-sdk/elevenlabs` | `2.0.33` | `b28452e`, `f47f502`, `06d534c`: option schema/options/response parity. |
| `@ai-sdk/assemblyai` | `2.0.33` | `12f99f8`, `a8478f5`, `eed6154`: option schema/transcript schema/user agent. |
| `@ai-sdk/gladia` | `2.0.33` | `3556db5`, `d5be7d9`, `5dba70d`: option schema/polling result/transcription parity. |
| `@ai-sdk/revai` | `2.0.33` | `6d53477`, `2bf52ae`, `2766762`, `c721831`: option schema/options/transcript response/user agent. |
| `@ai-sdk/hume` | `2.0.33` | `3a601dd`, `afd5ac3`, `0003f86`, `ab29ac4`: option schema/options/model identity/speech parity. |
| `@ai-sdk/lmnt` | `2.0.33` | `63361fb`, `24606d0`, `e93b4fc`, `d1597d0`: option schema/options/auth casing/user agent. |
| `@ai-sdk/voyage` | `1.0.4` | `d8f3617`, `b805d56`: option schema and response parity. |

## Needs Explicit Deep Pass

| Package | Baseline | Why still here |
| --- | --- | --- |
| `@ai-sdk/mcp` | `1.0.45` | MCP client/transport/OAuth are implemented and tested, but this is a protocol package rather than a model provider and needs its own sweep criteria. |

## Practical Remaining Queue

The realistic remaining provider work is not "all providers". It is:

1. Promote the central heavy providers from `substantial parity coverage` to
   `fresh deep pass`: OpenAI/OpenAI-compatible/Open Responses, Amazon Bedrock.
2. Do final package sweeps for the already-covered language providers:
   Groq, Mistral, Cohere, Perplexity, xAI, DeepSeek, Cerebras, MoonshotAI,
   Alibaba.
3. Do final package sweeps for media/audio providers that already have option
   schema work: Replicate, Luma, KlingAI, Black Forest Labs, ByteDance, Prodia,
   Deepgram, ElevenLabs, AssemblyAI, Gladia, RevAI, Hume, LMNT.
4. Add live smoke slices. Mock parity is broad; live coverage is still narrow.
