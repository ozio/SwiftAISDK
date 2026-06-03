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
| `@ai-sdk/alibaba` | Chat request/stream bodies, thinking options, tool calls, provider options/null namespace, usage-only/missing-usage chunks, reasoning text, stream/HTTP errors, unsupported settings, video task flow/errors, abort propagation, and user-agent behavior are covered. |
| `@ai-sdk/amazon-bedrock` | Converse, InvokeModel/Anthropic, Bedrock Mantle, SigV4 signing, event-stream parsing, reasoning/tool-use blocks, structured output, embeddings, image generation/editing, reranking, cache/metadata, unsupported models, region/credential handling, and abort propagation are covered. |
| `@ai-sdk/anthropic` | Messages requests/streams, thinking/redacted thinking, citations, hosted tools, provider-defined tools, file references, beta headers, container/context metadata, warnings, usage, and abort propagation are covered. |
| `@ai-sdk/anthropic-aws` | AWS Anthropic wrapper routes, workspace/API-key headers, base URL/auth differences, unsupported capabilities, model identity, and parity with the tiny upstream wrapper are covered. |
| `@ai-sdk/assemblyai` | Upload, submit, poll, transcript schema, error statuses, provider options, segments, language/duration metadata, abort propagation across all requests, and response metadata are covered. |
| `@ai-sdk/azure` | Azure deployment routing, token provider/API-key auth, chat/responses/image/speech surfaces inherited from OpenAI, aliases, unsupported model families, headers, and user-agent behavior are covered. |
| `@ai-sdk/baseten` | Model API vs dedicated endpoint routing, `/sync` and `/sync/v1` behavior, embedding batching/body shape, model URL validation, headers, response metadata, and abort propagation are covered. |
| `@ai-sdk/black-forest-labs` | Image create/poll/download flow, option schema, prompt upsampling/raw/safety/options mapping, input/output megapixel metadata, warnings, timeout/poll attempts, and abort propagation are covered. |
| `@ai-sdk/bytedance` | Video submit/poll flow, T2V/I2V/R2V option mapping, dimensions/aspect options, warnings, provider metadata, operation IDs, timeout behavior, and abort propagation are covered. |
| `@ai-sdk/cerebras` | Chat request/stream bodies, reasoning transforms, structured response format, tool calls, provider options, finish/usage normalization, stream/HTTP errors, warnings, user agent, and abort propagation are covered. |
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
| `@ai-sdk/moonshotai` | Chat/stream bodies, thinking options, tool calls, provider options, unsupported capabilities, usage variants, stream/HTTP errors, finish mapping, user-agent behavior, and abort propagation are covered. |
| `@ai-sdk/open-responses` | Custom Responses endpoint factory, optional API key/custom headers, provider options namespace, request conversion, function tools/tool choice, structured text format, file/tool-result content conversion, finish/usage mapping, text/reasoning/function-call streaming, failed stream events, warnings, and raw chunks are covered. |
| `@ai-sdk/openai` | Chat, Responses, completions, embeddings, images, speech, transcription, files, skills, tool helpers, provider aliases, organization/project headers, structured output, metadata, warnings, and abort propagation are covered. |
| `@ai-sdk/openai-compatible` | Chat/completion/embedding/image surfaces, route selection, stream parsing, provider surface IDs, warning behavior, provider option passthrough, response metadata, and abort propagation are covered. |
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
| `@ai-sdk/openai` | `3.0.67` | `e12b20e`: package re-read across provider/config/chat/responses/completion/embedding/image/speech/transcription/tools; typed providerOptions, Responses automatic includes, completion/audio/embedding parity gaps, shell skills, and tool-choice behavior closed. |
| `@ai-sdk/openai-compatible` | `2.0.48` | `0badc3c`: package re-read across provider/chat/completion/embedding/image; generic providerOptions namespaces, completion prompt conversion, embedding metadata/default encoding, and generic-vs-specialized passthrough boundaries closed. |
| `@ai-sdk/open-responses` | `1.0.16` | `d0d881f`: package re-read against upstream request/input/stream/finish schemas; file names, rich tool-result content, Open Responses finish mapping, and failed stream events closed. |
| `@ai-sdk/groq` | `3.0.39` | `e67562f`: package re-read across provider/chat/messages/tools/transcription; Groq-specific usage details aligned after existing providerOptions/tool/transcription coverage. |
| `@ai-sdk/mistral` | `3.0.37` | `54733c8`: package re-read across provider/chat/messages/tools/embedding; Mistral finish/error mapping and tool execution-denied output aligned after existing native chat/embedding parity coverage. |
| `@ai-sdk/cohere` | `3.0.36` | `5f0bd7f`: package re-read across provider/chat/prompt/tools/embedding/reranking; Cohere stream error chunks, tool-call argument canonicalization, and execution-denied output aligned after existing native parity coverage. |
| `@ai-sdk/perplexity` | `3.0.33` | `3b96637`: package re-read across provider/language/messages/options/usage/finish schemas; stream parse errors now surface as error parts after existing search/citation/metadata parity coverage. |
| `@ai-sdk/xai` | `3.0.93` | `7d689df`: package re-read across provider/chat/responses/tools/image/video/files; xAI Responses request prep now owns option/input/tool mapping instead of riding the OpenAI-compatible builder, and chat/Responses reasoning option schemas were aligned. |
| `@ai-sdk/deepseek` | `2.0.35` | `e25563e`: package re-read across provider/chat/options/messages/tools/usage/stream; missing usage, tool-result output serialization, stream error parts, and strict first tool-delta validation aligned. |
| `@ai-sdk/cerebras` | `2.0.54` | Current OpenAI-compatible batch: package re-read across provider/chat/options; flat Cerebras error schema, missing usage, stream error parts, and strict first tool-delta validation aligned. |
| `@ai-sdk/moonshotai` | `2.0.23` | Current OpenAI-compatible batch: package re-read across provider/chat/options/usage; generic OpenAI-compatible stream/HTTP error handling and strict first tool-delta validation aligned for MoonshotAI. |
| `@ai-sdk/alibaba` | `1.0.25` | Current OpenAI-compatible batch: package re-read across provider/chat/messages/options/usage/video; chat/video error schemas, null provider namespace, missing usage, stream error parts, and strict first tool-delta validation aligned. |
| `@ai-sdk/replicate` | `2.0.33` | Current media batch: package re-read across provider/image/video/options/errors; versioned/unversioned routes, error schemas, null namespace, video lifecycle messages, polling, downloads, and prefer headers aligned. |
| `@ai-sdk/luma` | `2.0.33` | Current media batch: package re-read across provider/image/options/errors/polling; Luma detail error schema, failure/no-image/timeout messages, nullish provider options, reference image flows, and download behavior aligned. |
| `@ai-sdk/klingai` | `3.0.18` | Current media batch: package re-read across provider/auth/video/options/errors/polling; `{code,message}` error schema, failure/timeout/missing-video messages, T2V/I2V/motion-control bodies, and poll timing aligned. |
| `@ai-sdk/black-forest-labs` | `1.0.34` | Current media batch: package re-read across provider/image/options/errors/polling; BFL error schema, poll status validation, Ready-without-sample message, provider options, metadata, downloads, and timeout attempts aligned. |
| `@ai-sdk/bytedance` | `1.0.14` | Current media batch: published dist re-read across provider/video/options/errors/polling; ARK auth, request body/media mapping, error schema, failed/no-video/missing-task/timeout messages, metadata, and poll behavior aligned. |
| `@ai-sdk/prodia` | `1.0.31` | Current media batch: package re-read across provider/language/image/video/api; Prodia error schema, JSON job wrapper, multipart validation messages, provider metadata, options, and generated file/media flows aligned. |
| `@ai-sdk/deepgram` | `2.0.33` | Current audio batch: package re-read across provider/transcription/speech/options/errors; `{error:{message,code}}` HTTP errors, missing transcription query mappings, speech option cleanup, provider metadata, warnings, and abort propagation aligned. |
| `@ai-sdk/elevenlabs` | `2.0.33` | Current audio batch: package re-read across provider/speech/transcription/options/errors; `{error:{message,code}}` HTTP errors, speech JSON body/query, STT multipart/defaults, validation, metadata, warnings, and abort propagation aligned. |
| `@ai-sdk/assemblyai` | `2.0.33` | Current audio batch: package re-read across provider/transcription/options/errors/upload-submit-poll; `{error:{message,code}}` HTTP errors on upload/submit/poll, submit response handling, status/result schemas, metadata, and abort propagation aligned. |
| `@ai-sdk/gladia` | `2.0.33` | Current transcription batch: package re-read across provider/transcription/options/errors/upload-init-poll; `{error:{message,code}}` HTTP errors on upload/init/poll, upstream lifecycle messages, option schema, status/result schemas, metadata, and abort propagation aligned. |
| `@ai-sdk/revai` | `2.0.33` | Current transcription batch: package re-read across provider/transcription/options/errors/submit-poll-transcript; `{error:{message,code}}` HTTP errors, upstream lifecycle messages, multipart config/options, result schema, metadata, and abort propagation aligned. |
| `@ai-sdk/hume` | `2.0.33` | Current speech batch: package re-read across provider/speech/options/errors; `{error:{message,code}}` HTTP errors, TTS file body, context/voice mappings, output/language warnings, metadata, and abort propagation aligned. |
| `@ai-sdk/lmnt` | `2.0.33` | Current speech batch: package re-read across provider/speech/options/errors; `{error:{message,code}}` HTTP errors, speech bytes body, provider option defaults/nullish fields, format/language/speed mapping, metadata, and abort propagation aligned. |
| `@ai-sdk/azure` | `3.0.69` | Current foundation provider audit: package re-read across provider/tools/metadata; v1/deployment URL building, token-provider auth precedence, OpenAI-inherited language/media surfaces, tools, aliases, and user-agent behavior verified. |
| `@ai-sdk/baseten` | `1.0.51` | Current foundation provider audit: package re-read across provider/chat/embedding/options; Model API vs `/sync`/`/sync/v1`, `/predict` rejection, dedicated embedding body/batching, error schema, and user-agent behavior verified. |
| `@ai-sdk/deepinfra` | `2.0.52` | Current foundation provider audit: package re-read across provider/chat/completion/embedding/image/options; custom root base URL now adds upstream `/openai` and `/inference` prefixes, image/edit bodies, Gemma/Gemini usage correction, and user-agent behavior verified. |
| `@ai-sdk/fireworks` | `2.0.53` | Current final provider audit: package re-read across provider/chat/completion/embedding/image/options; Fireworks error schema, thinking transform, workflow/image-generation/async image routing, polling/downloads, warnings, metadata, and user-agent behavior verified. |
| `@ai-sdk/togetherai` | `2.0.53` | Current final provider audit: package re-read across provider/chat/completion/embedding/image/reranking/options; image warning condition, option schema, rerank request/response shape, env fallback, metadata, and user-agent behavior aligned. |
| `@ai-sdk/voyage` | `1.0.4` | Current final provider audit: package re-read across provider/embedding/reranking/options/errors; native request bodies, provider option schemas, `{detail}` error schema, 128-value preflight, object-document warnings, metadata, and user-agent behavior aligned. |
| `@ai-sdk/mcp` | `1.0.45` | Current MCP protocol-client audit: package re-read across client/transports/OAuth/types/errors; protocol versions, initialize/initialized, tools/resources/templates/prompts, elicitation, HTTP/SSE/Stdio transports, OAuth discovery/PKCE/token/register flows, and abort/close behavior verified. |
| `@ai-sdk/anthropic-aws` | `1.0.3` | `135ceb6`: API-key header precedence and dynamic SigV4 credential-provider parity after package re-read. |
| `@ai-sdk/amazon-bedrock` | `4.0.112` | `e2cb97e`: dynamic SigV4 credentials, Converse JSON response format parity, embeddings provider options/response shapes, image validation/warnings/count limits, and streaming auth parity after package re-read. |
| `@ai-sdk/anthropic` | `3.0.81` | `30c3272`: provider auth/base URL/custom name, tool choice/parallel tool-use, eager stream tool inputs, provider option key merging, and abort propagation after package re-read. |
| `@ai-sdk/google-vertex` | `4.0.141` | `83ef81d`: regional REP hosts, express API-key precedence, embedding options/usage/limit, Veo polling/base64 videos, and subprovider URL parity after package re-read. |
| `@ai-sdk/google` | `3.0.80` | `09bfd11`: Gemini/Imagen/Veo/embeddings parity sweep: providerOptions, multimodal content, editing warnings, video polling/options, metadata, and abort propagation after package re-read. |
| `@ai-sdk/huggingface` | `1.0.50` | `e6ce75a`: provider-defined tools skipped with upstream-style warning after package re-read. |
| `@ai-sdk/fal` | `2.0.34` | `b8ebeaa`: image metadata NSFW/prompt normalization after package re-read. |
| `@ai-sdk/quiverai` | `1.0.0` | Re-read package and local implementation; no safe remaining gap found after existing QuiverAI option/schema/response tests. |
| `@ai-sdk/vercel` | `2.0.50` | Re-read package and local implementation; existing endpoint/header/user-agent/unsupported-family coverage matched the tiny upstream package. |

### Fresh Pass Completion Records

#### `@ai-sdk/mcp`

```text
Package: @ai-sdk/mcp
Baseline: 1.0.45
Upstream inspected: index.ts, types.ts, mcp-client.ts, mcp-transport.ts, mcp-http-transport.ts, mcp-sse-transport.ts, mcp-stdio-transport.ts, oauth.ts, oauth-types.ts, error files.
Swift files inspected: MCPClient.swift, MCPOAuth.swift, MCPClientTests.swift, MCPStdioTransportTests.swift, MCPOAuthTests.swift.
Surfaces checked: exported client API and deprecated aliases mapping, latest/supported protocol versions, initialize handshake and initialized notification, serverInfo/instructions, tool listing/calling and cached definitions, model-output conversion for text/image/resource/unknown content, resource list/read/templates, prompt list/get, capability checks, incoming ping and elicitation/create handling, closed-client behavior, HTTP JSON/SSE transport modes, session IDs, inbound SSE reconnect/Last-Event-ID, 401 OAuth retry, Stdio line-delimited transport, OAuth protected-resource and authorization-server discovery, PKCE authorization URL, token exchange/refresh/register, custom client authentication, OAuth error parsing, abort propagation.
Known Swift differences / out of scope: Swift does not mirror TypeScript's `tools({ schemas })` generic overload or runtime outputSchema validation API; Swift exposes dynamic `AITool` definitions and keeps raw MCP results. Swift keeps stable MCPClientError/AIError cases instead of upstream AISDKError subclasses.
Tests run: swift test --filter 'MCP|OAuth|Stdio'; full swift test in the current final provider audit batch.
Commit evidence: Current MCP protocol-client audit batch.
Reopen only if: mcp npm version changes, MCP protocol version list changes, client/transport/OAuth exported API changes, TS schema overload becomes necessary for Swift ergonomics, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/fireworks`

```text
Package: @ai-sdk/fireworks
Baseline: 2.0.53
Upstream inspected: fireworks-provider.ts, fireworks-image-model.ts, fireworks-image-api.ts, chat/completion/embedding/image option files.
Swift files inspected: OpenAICompatibleProvider.swift, ProviderRegistry.swift, OpenAICompatible.swift, FireworksModels.swift, FireworksProviderTests.swift.
Surfaces checked: provider factory, default base URL, FIREWORKS_API_KEY auth, user-agent suffix, language/completion/embedding OpenAI-compatible routes, Fireworks `{error}` error schema, chat thinking/reasoningHistory transform, image workflow/image_generation/workflows_async routing, async request_id polling, binary downloads, input image/mask warnings, size/aspect warnings, providerOptions namespace, response metadata, abort propagation.
Known Swift differences / out of scope: Swift supports legacy extraBody merging alongside upstream providerOptions. Swift keeps stable AIError cases instead of upstream's exact JS error classes.
Tests run: swift test --filter 'Fireworks|TogetherAI|Voyage'; full swift test in the current final provider audit batch.
Commit evidence: Current final provider audit batch.
Reopen only if: fireworks npm version changes, model backend routing changes, async poll schema changes, option/error schema changes, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/togetherai`

```text
Package: @ai-sdk/togetherai
Baseline: 2.0.53
Upstream inspected: togetherai-provider.ts, togetherai-image-model.ts, reranking/togetherai-reranking-model.ts, chat/completion/embedding/image/reranking option files.
Swift files inspected: OpenAICompatibleProvider.swift, ProviderRegistry.swift, TogetherAIModels.swift, TogetherAIProviderTests.swift.
Surfaces checked: provider factory and aliases, default base URL, TOGETHER_API_KEY plus deprecated TOGETHER_AI_API_KEY auth fallback, user-agent suffix, OpenAI-compatible language/completion/embedding routes, image generation body, upstream size-triggered aspectRatio warning, single image input warning, mask error, providerOptions image schema, reranking `/rerank` body, rankFields mapping, return_documents false, JSON object documents, response/error validation, metadata, abort propagation.
Known Swift differences / out of scope: Swift supports legacy extraBody merging and camelCase image option aliases in addition to upstream providerOptions. Swift keeps stable AIError cases instead of upstream's exact JS error classes.
Tests run: swift test --filter 'Fireworks|TogetherAI|Voyage'; full swift test in the current final provider audit batch.
Commit evidence: Current final provider audit batch.
Reopen only if: togetherai npm version changes, image/rerank option schemas change, deprecated env fallback changes, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/voyage`

```text
Package: @ai-sdk/voyage
Baseline: 1.0.4
Upstream inspected: voyage-provider.ts, voyage-error.ts, voyage-embedding-model.ts, reranking/voyage-reranking-model.ts, embedding/reranking option files.
Swift files inspected: OpenAICompatibleProvider.swift, ProviderRegistry.swift, CohereVoyageModels.swift, CohereMistralVoyageTests.swift, VoyageProviderOptionSchemaTests.swift.
Surfaces checked: provider factory, unsupported language/image surfaces, default base URL, VOYAGE_API_KEY auth, user-agent suffix, embedding/textEmbedding aliases, reranking aliases, embedding request body, providerOptions schema, 128-value preflight rejection before request, reranking request body, object document JSON-string conversion warning, `{detail}` HTTP error schema, response validation, usage/metadata, abort propagation.
Known Swift differences / out of scope: Swift exposes unsupported capabilities through typed AIError instead of upstream NoSuchModelError classes. Swift supports legacy extraBody merging alongside upstream providerOptions.
Tests run: swift test --filter 'Fireworks|TogetherAI|Voyage'; full swift test in the current final provider audit batch.
Commit evidence: Current final provider audit batch.
Reopen only if: voyage npm version changes, embedding/rerank request schemas change, error schema changes, maxEmbeddingsPerCall changes, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/azure`

```text
Package: @ai-sdk/azure
Baseline: 3.0.69
Upstream inspected: azure-openai-provider.ts, azure-openai-tools.ts, azure-openai-provider-metadata.ts, package docs/API files.
Swift files inspected: OpenAICompatibleProvider.swift, ProviderRegistry.swift, OpenAICompatible.swift, AlibabaProdiaAzureQuiverTests.swift.
Surfaces checked: provider factory and aliases, default resource/base URL resolution, v1 vs deployment-based URL building, api-version query, AZURE_API_KEY auth, tokenProvider auth precedence and per-request token calls, user-agent suffix, Responses default model factory, chat/completion/embedding/image/transcription/speech routes inherited from OpenAI, Azure tool helpers, providerOptions namespace, unsupported video/rerank surfaces.
Known Swift differences / out of scope: Swift exposes explicit Swift methods instead of JS callable provider/new-keyword behavior. Swift keeps stable AIError cases instead of upstream's exact JS error classes.
Tests run: swift test --filter 'Azure|Baseten|DeepInfra'; full swift test in the current foundation provider audit batch.
Commit evidence: Current foundation provider audit batch.
Reopen only if: azure npm version changes, URL/auth/tool helper behavior changes, OpenAI-inherited Azure surfaces diverge upstream, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/baseten`

```text
Package: @ai-sdk/baseten
Baseline: 1.0.51
Upstream inspected: baseten-provider.ts, baseten-chat-options.ts, baseten-embedding-options.ts, package docs/API files.
Swift files inspected: OpenAICompatibleProvider.swift, ProviderRegistry.swift, BasetenModels.swift, BasetenProviderTests.swift.
Surfaces checked: provider factory, default Model API base URL, BASETEN_API_KEY bearer auth, user-agent suffix, chat Model API body, custom modelURL `/sync/v1` placeholder model behavior, plain `/sync` fallback to Model API for chat, `/predict` rejection, embedding modelURL requirement, `/sync` and `/sync/v1` embedding routes, dedicated embedding request body, 128-value batching/index adjustment, response metadata, error schema.
Known Swift differences / out of scope: Swift simulates the upstream Baseten performance-client embedding path with direct transport requests so it remains testable and abortable; this preserves request/response shape but not the third-party client's internal implementation object.
Tests run: swift test --filter 'Azure|Baseten|DeepInfra'; full swift test in the current foundation provider audit batch.
Commit evidence: Current foundation provider audit batch.
Reopen only if: baseten npm version changes, modelURL routing changes, performance-client embedding body/batching changes, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/deepinfra`

```text
Package: @ai-sdk/deepinfra
Baseline: 2.0.52
Upstream inspected: deepinfra-provider.ts, deepinfra-chat-language-model.ts, deepinfra-image-model.ts, chat/completion/embedding/image option files.
Swift files inspected: OpenAICompatibleProvider.swift, ProviderRegistry.swift, DeepInfraModels.swift, DeepInfraProviderTests.swift.
Surfaces checked: provider factory and aliases, DEEPINFRA_API_KEY bearer auth, user-agent suffix, root base URL normalization, `/openai` chat/completion/embedding routing, `/inference` image routing, OpenAI-compatible image edit endpoint, custom baseURL/proxy behavior, providerOptions namespace, size/aspect/seed mapping, maxImagesPerCall, image error/response schemas, Gemma/Gemini reasoning usage correction for generate and stream, response metadata.
Known Swift differences / out of scope: Swift supports legacy extraBody merging alongside upstream providerOptions. Swift keeps stable AIError cases instead of upstream's exact JS error classes.
Tests run: swift test --filter 'Azure|Baseten|DeepInfra'; full swift test in the current foundation provider audit batch.
Commit evidence: Current foundation provider audit batch.
Reopen only if: deepinfra npm version changes, baseURL prefix rules change, image/edit schemas change, usage correction logic changes, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/hume`

```text
Package: @ai-sdk/hume
Baseline: 2.0.33
Upstream inspected: hume-provider.ts, hume-error.ts, hume-speech-model.ts, API/config files.
Swift files inspected: AudioProviderModels.swift, OpenAICompatibleProvider.swift, ProviderRegistry.swift, HumeProviderTests.swift.
Surfaces checked: provider factory, default base URL, HUME_API_KEY auth, user-agent suffix, no-arg speech model, default voice, TTS file endpoint, utterance body, output format fallback/warnings, language warning, providerOptions context schema/null namespace, generationId and context utterance/voice mappings, HTTP error schema, metadata, abort propagation.
Known Swift differences / out of scope: Swift still supports extraBody as a legacy escape hatch in addition to upstream providerOptions. Swift keeps stable AIError cases instead of upstream's exact JS error classes.
Tests run: swift test --filter 'Hume|LMNT'; full swift test in the current speech batch.
Commit evidence: Current speech batch.
Reopen only if: hume npm version changes, TTS body/error schema changes, context/voice option schema changes, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/lmnt`

```text
Package: @ai-sdk/lmnt
Baseline: 2.0.33
Upstream inspected: lmnt-provider.ts, lmnt-error.ts, lmnt-speech-model.ts, API/options/config files.
Swift files inspected: AudioProviderModels.swift, OpenAICompatibleProvider.swift, ProviderRegistry.swift, LMNTProviderTests.swift.
Surfaces checked: provider factory, default base URL, LMNT_API_KEY auth, user-agent suffix, speech bytes endpoint, model/voice/text/response_format body, output format fallback/warnings, language passthrough, providerOptions schema/defaults/nullish fields, sampleRate/topP mapping, HTTP error schema, metadata, abort propagation.
Known Swift differences / out of scope: Swift still supports extraBody as a legacy escape hatch in addition to upstream providerOptions. Swift keeps stable AIError cases instead of upstream's exact JS error classes.
Tests run: swift test --filter 'Hume|LMNT'; full swift test in the current speech batch.
Commit evidence: Current speech batch.
Reopen only if: lmnt npm version changes, speech body/error schema changes, provider option defaults change, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/gladia`

```text
Package: @ai-sdk/gladia
Baseline: 2.0.33
Upstream inspected: gladia-provider.ts, gladia-error.ts, gladia-transcription-model.ts, API/config files.
Swift files inspected: AudioProviderModels.swift, OpenAICompatibleProvider.swift, ProviderRegistry.swift, GladiaProviderTests.swift.
Surfaces checked: provider factory, default base URL, GLADIA_API_KEY auth, user-agent suffix, no-arg default model, upload/init/poll lifecycle, providerOptions schema/null namespace, legacy extraBody mapping, nested option key conversion, standard language behavior, result status/result validation, failed/empty/timeout lifecycle messages, HTTP error schema on upload/init/poll, metadata, abort propagation.
Known Swift differences / out of scope: Swift still supports extraBody as a legacy escape hatch in addition to upstream providerOptions. Swift keeps stable AIError cases instead of upstream's exact JS error classes.
Tests run: swift test --filter 'Gladia|RevAI'; full swift test in the current transcription batch.
Commit evidence: Current transcription batch.
Reopen only if: gladia npm version changes, upload/init/poll schemas change, option/error schema changes, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/revai`

```text
Package: @ai-sdk/revai
Baseline: 2.0.33
Upstream inspected: revai-provider.ts, revai-error.ts, revai-transcription-model.ts, API/options/config files.
Swift files inspected: AudioProviderModels.swift, OpenAICompatibleProvider.swift, ProviderRegistry.swift, RevAIProviderTests.swift.
Surfaces checked: provider factory, default base URL, REVAI_API_KEY bearer auth, user-agent suffix, multipart job submit, poll job status, transcript fetch, providerOptions schema/defaults/null namespace, nested summarization/translation config defaults, submission language retention, zero-duration segment behavior, failed/timeout lifecycle messages, HTTP error schema on submit/poll/transcript, metadata, abort propagation.
Known Swift differences / out of scope: Swift still supports extraBody as a legacy escape hatch in addition to upstream providerOptions. Swift keeps stable AIError cases instead of upstream's exact JS error classes.
Tests run: swift test --filter 'Gladia|RevAI'; full swift test in the current transcription batch.
Commit evidence: Current transcription batch.
Reopen only if: revai npm version changes, submit/poll/transcript schemas change, option/error schema changes, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/deepgram`

```text
Package: @ai-sdk/deepgram
Baseline: 2.0.33
Upstream inspected: deepgram-provider.ts, deepgram-error.ts, deepgram-transcription-model.ts, deepgram-speech-model.ts, option/config files.
Swift files inspected: AudioProviderModels.swift, OpenAICompatibleProvider.swift, ProviderRegistry.swift, DeepgramProviderTests.swift.
Surfaces checked: provider factory, default base URL, DEEPGRAM_API_KEY auth, user-agent suffix, raw audio listen upload, transcription query body mapping, default diarize, providerOptions schema/null namespace, speech format parsing, encoding/container/sample_rate/bit_rate cleanup and warnings, unsupported standard speech warnings, metadata, HTTP error schema, abort propagation.
Known Swift differences / out of scope: Swift still supports extraBody as a legacy escape hatch in addition to upstream providerOptions. Swift keeps stable AIError cases instead of upstream's exact JS error classes.
Tests run: swift test --filter 'Deepgram|ElevenLabs|AssemblyAI'; full swift test in the current audio batch.
Commit evidence: Current audio batch.
Reopen only if: deepgram npm version changes, listen/speak option/error schema changes, speech format rules change, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/elevenlabs`

```text
Package: @ai-sdk/elevenlabs
Baseline: 2.0.33
Upstream inspected: elevenlabs-provider.ts, elevenlabs-error.ts, elevenlabs-speech-model.ts, elevenlabs-transcription-model.ts, option/config files.
Swift files inspected: AudioProviderModels.swift, OpenAICompatibleProvider.swift, ProviderRegistry.swift, ElevenLabsProviderTests.swift.
Surfaces checked: provider factory, default base URL, ELEVENLABS_API_KEY auth, user-agent suffix, speech text-to-speech route/query/body, output format aliases, voice settings, pronunciation dictionaries, text normalization fields, enable_logging query, STT multipart route/file/options/defaults, transcription response validation, segments/language/duration, HTTP error schema, metadata, warnings, abort propagation.
Known Swift differences / out of scope: Swift still supports extraBody as a legacy escape hatch in addition to upstream providerOptions. Swift keeps stable AIError cases instead of upstream's exact JS error classes.
Tests run: swift test --filter 'Deepgram|ElevenLabs|AssemblyAI'; full swift test in the current audio batch.
Commit evidence: Current audio batch.
Reopen only if: elevenlabs npm version changes, TTS/STT option/error schema changes, multipart response shape changes, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/assemblyai`

```text
Package: @ai-sdk/assemblyai
Baseline: 2.0.33
Upstream inspected: assemblyai-provider.ts, assemblyai-error.ts, assemblyai-transcription-model.ts, option/config files.
Swift files inspected: AudioProviderModels.swift, OpenAICompatibleProvider.swift, ProviderRegistry.swift, AssemblyAIProviderTests.swift.
Surfaces checked: provider factory, default base URL, ASSEMBLYAI_API_KEY auth, user-agent suffix, upload/submit/poll lifecycle, providerOptions schema/null namespace, submit body mapping, status validation, failed transcription message, final transcript text/words/language/audio_duration mapping, HTTP error schema on upload/submit/poll, metadata, abort propagation.
Known Swift differences / out of scope: Swift still supports extraBody as a legacy escape hatch in addition to upstream providerOptions. Swift keeps stable AIError cases instead of upstream's exact JS error classes.
Tests run: swift test --filter 'Deepgram|ElevenLabs|AssemblyAI'; full swift test in the current audio batch.
Commit evidence: Current audio batch.
Reopen only if: assemblyai npm version changes, upload/submit/poll schemas change, transcript status/result/error schema changes, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/black-forest-labs`

```text
Package: @ai-sdk/black-forest-labs
Baseline: 1.0.34
Upstream inspected: black-forest-labs-provider.ts, black-forest-labs-image-model.ts, black-forest-labs-image-settings.ts.
Swift files inspected: MediaProviderModels.swift, OpenAICompatibleProvider.swift, ProviderRegistry.swift, BlackForestLabsProviderTests.swift.
Surfaces checked: provider factory, default base URL, BFL_API_KEY auth, user-agent suffix, image create/poll/download flow, size/aspect warnings, input image/mask mapping including fill model naming, providerOptions schema/null namespace, prompt/raw/safety/webhook/options mapping, metadata, poll URL id injection, status/state handling, timeout attempt count, HTTP error schema, Ready-without-sample and missing-status handling, abort propagation.
Known Swift differences / out of scope: Swift also accepts BLACK_FOREST_LABS_API_KEY as an alias. Swift keeps stable AIError cases instead of upstream's exact JS error classes.
Tests run: swift test --filter BlackForestLabs; swift test --filter 'BlackForestLabs|ByteDance|Prodia'; full swift test in the current media batch.
Commit evidence: Current media batch.
Reopen only if: black-forest-labs npm version changes, image option/error/poll schema changes, generated image download behavior changes, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/bytedance`

```text
Package: @ai-sdk/bytedance
Baseline: 1.0.14
Upstream inspected: dist/index.mjs from the published package; package tarball has no src files.
Swift files inspected: MediaProviderModels.swift, OpenAICompatibleProvider.swift, ProviderRegistry.swift, ByteDanceProviderTests.swift.
Surfaces checked: provider factory, default ModelArk base URL, ARK_API_KEY auth, unsupported capability routing, video submit/poll flow, prompt/image/reference media content mapping, aspect/duration/seed/resolution mapping, providerOptions schema/null namespace/nullish fields, passthrough behavior, warnings, provider metadata, operation IDs, HTTP error schema, missing task ID, failed task, no video URL, timeout messages, abort propagation.
Known Swift differences / out of scope: Swift exposes extraBody aliases for legacy/snake-case escape hatches beyond upstream providerOptions. Swift keeps stable AIError cases instead of upstream's exact JS error classes.
Tests run: swift test --filter ByteDance; swift test --filter 'BlackForestLabs|ByteDance|Prodia'; full swift test in the current media batch.
Commit evidence: Current media batch.
Reopen only if: bytedance npm version changes, ModelArk task schema/options/error schema changes, media reference mapping changes, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/prodia`

```text
Package: @ai-sdk/prodia
Baseline: 1.0.31
Upstream inspected: prodia-provider.ts, prodia-api.ts, prodia-language-model.ts, prodia-image-model.ts, prodia-video-model.ts, model settings files.
Swift files inspected: MediaProviderModels.swift, OpenAICompatibleProvider.swift, ProviderRegistry.swift, ProdiaProviderTests.swift.
Surfaces checked: provider factory, default base URL, PRODIA_TOKEN auth, user-agent suffix, language multipart img2img endpoint, image JSON job endpoint, video JSON and multipart img2vid endpoints, generated files/media, providerOptions schema/null namespace, warnings, JSON job wrapper, Prodia error schema, multipart boundary/job/output validation messages, provider metadata, response metadata, abort propagation.
Known Swift differences / out of scope: Swift also accepts PRODIA_API_KEY as an alias. Swift keeps stable AIError cases instead of upstream's exact JS error classes.
Tests run: swift test --filter Prodia; swift test --filter 'BlackForestLabs|ByteDance|Prodia'; full swift test in the current media batch.
Commit evidence: Current media batch.
Reopen only if: prodia npm version changes, job multipart/JSON wrapper/error schema changes, generated media response shape changes, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/replicate`

```text
Package: @ai-sdk/replicate
Baseline: 2.0.33
Upstream inspected: replicate-provider.ts, replicate-error.ts, replicate-image-model.ts, replicate-image-settings.ts, replicate-video-model.ts, replicate-video-settings.ts.
Swift files inspected: MediaProviderModels.swift, OpenAICompatibleProvider.swift, ProviderRegistry.swift, ReplicateProviderTests.swift.
Surfaces checked: provider factory, default base URL, REPLICATE_API_TOKEN auth, user-agent suffix, versioned/unversioned prediction routes, image/video request bodies, Flux-2 multi-image inputs, prefer wait headers, providerOptions schema/null namespace/nullish fields, polling, output URL download, response metadata, video failed/canceled/no-output messages, HTTP error schemas, abort propagation.
Known Swift differences / out of scope: Swift also allows `settings.apiKey` as the standard local API-key override. Swift keeps stable `AIError` cases instead of upstream's exact JS error classes.
Tests run: swift test --filter Replicate; full swift test in the current media batch.
Commit evidence: Current media batch.
Reopen only if: replicate npm version changes, prediction routes/error schema/options schema changes, media output format changes, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/luma`

```text
Package: @ai-sdk/luma
Baseline: 2.0.33
Upstream inspected: luma-provider.ts, luma-image-model.ts, luma-image-settings.ts.
Swift files inspected: MediaProviderModels.swift, OpenAICompatibleProvider.swift, ProviderRegistry.swift, LumaProviderTests.swift.
Surfaces checked: provider factory, default base URL, LUMA_API_KEY auth, user-agent suffix, image generation route, submit/poll/download sequence, aspect ratio mapping, unsupported seed/size warnings, reference image/style/character/modify_image flows, providerOptions schema/null namespace/nullish fields, Luma detail error schema, failed/no-image/timeout messages, response metadata, abort propagation.
Known Swift differences / out of scope: Swift keeps stable `AIError` cases instead of upstream's exact JS error classes. Swift supports extraBody as an explicit escape hatch around providerOptions.
Tests run: swift test --filter Luma; full swift test in the current media batch.
Commit evidence: Current media batch.
Reopen only if: luma npm version changes, image generation/error schema/reference image options change, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/klingai`

```text
Package: @ai-sdk/klingai
Baseline: 3.0.18
Upstream inspected: klingai-provider.ts, klingai-auth.ts, klingai-error.ts, klingai-video-model.ts, klingai-video-settings.ts.
Swift files inspected: MediaProviderModels.swift, OpenAICompatibleProvider.swift, ProviderRegistry.swift, KlingAIProviderTests.swift.
Surfaces checked: provider factory, default Singapore base URL, KLINGAI_API_KEY shortcut plus KLINGAI_ACCESS_KEY/KLINGAI_SECRET_KEY JWT auth, user-agent suffix, T2V/I2V/motion-control endpoint detection, model_name derivation, standard prompt/image/aspect/duration mapping, providerOptions schema/null namespace/nullish fields, passthrough options, poll timing, required motion options, unsupported warnings, provider metadata, `{code,message}` HTTP error schema, failed/timeout/no-video/no-valid-url messages, abort propagation.
Known Swift differences / out of scope: Upstream settings expose `accessKey`/`secretKey` separately; Swift's public `ProviderSettings` exposes `apiKey` and environment-based access/secret JWT generation. Swift keeps stable `AIError` cases instead of upstream's exact JS error classes.
Tests run: swift test --filter KlingAI; full swift test in the current media batch.
Commit evidence: Current media batch.
Reopen only if: klingai npm version changes, JWT/auth behavior changes, video body/error/status schema changes, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/cerebras`

```text
Package: @ai-sdk/cerebras
Baseline: 2.0.54
Upstream inspected: cerebras-provider.ts, cerebras-chat-language-model.ts, cerebras-chat-options.ts, cerebras-chat-language-model-options.ts, version.ts.
Swift files inspected: CerebrasModels.swift, OpenAICompatibleProvider.swift, CerebrasProviderTests.swift.
Surfaces checked: provider factory, chat request body, reasoning_content -> reasoning transform, structured JSON response format, structured-output tool-call filtering, provider options, tool choice/tool warnings, finish/usage mapping, flat Cerebras HTTP error schema, stream parse/error chunks, strict first tool-call delta validation, response metadata, user-agent suffix, abort propagation.
Known Swift differences / out of scope: Swift uses static headers rather than upstream async resolvable header functions; Swift text stream part IDs are stable Swift contract IDs rather than upstream-internal labels.
Tests run: swift test --filter Cerebras; full swift test in the current OpenAI-compatible batch.
Reopen only if: cerebras npm version changes, chat/error/stream schema changes, structured-output mixed tool-call behavior changes, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/moonshotai`

```text
Package: @ai-sdk/moonshotai
Baseline: 2.0.23
Upstream inspected: moonshotai-provider.ts, moonshotai-chat-language-model.ts, moonshotai-chat-options.ts, convert-moonshotai-chat-usage.ts, version.ts.
Swift files inspected: OpenAICompatible.swift, OpenAICompatibleProvider.swift, ProviderRegistry.swift, MoonshotAIProviderTests.swift.
Surfaces checked: provider factory aliases, default base URL, API key/header/user-agent handling, includeUsage default, thinking/reasoningHistory transform, provider option schema, tool choice/provider-tool warnings, Moonshot usage conversion, HTTP error.message schema, stream parse/error chunks, strict first tool-call delta validation, unsupported embedding/image capabilities, abort propagation.
Known Swift differences / out of scope: Swift exposes `extraBody` alongside upstream providerOptions and uses static settings dictionaries instead of async resolvable headers.
Tests run: swift test --filter Moonshot; swift test --filter OpenAICompatible; full swift test in the current OpenAI-compatible batch.
Reopen only if: moonshotai npm version changes, thinking/reasoningHistory or usage schemas change, inherited OpenAI-compatible stream semantics change, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/alibaba`

```text
Package: @ai-sdk/alibaba
Baseline: 1.0.25
Upstream inspected: alibaba-provider.ts, alibaba-chat-language-model.ts, alibaba-chat-options.ts, convert-to-alibaba-chat-messages.ts, convert-alibaba-usage.ts, alibaba-error.ts, alibaba-video-model.ts, alibaba-video-settings.ts, version.ts.
Swift files inspected: AlibabaModels.swift, MediaProviderModels.swift, OpenAICompatibleProvider.swift, ProviderRegistry.swift, AlibabaProviderTests.swift.
Surfaces checked: language and video factories, default compatible/native base URLs, API key/header/user-agent handling, chat request body, multimodal message conversion, thinking options, providerOptions.alibaba null namespace and typed schema, tools/tool choice/tool-result serialization, response format, usage/cache-write conversion including missing usage, HTTP error.message schema, stream parse/error chunks, usage-only chunks, strict first tool-call delta validation, video task create/poll flow, video native flat error schema, video provider options/warnings/metadata, abort propagation.
Known Swift differences / out of scope: Swift keeps `extraBody` as a compatibility escape hatch; Swift video polling uses the package's existing abort-aware sleep rather than upstream's JS `delay` helper.
Tests run: swift test --filter Alibaba; full swift test in the current OpenAI-compatible batch.
Reopen only if: alibaba npm version changes, Qwen chat/error/usage schemas change, Wan video native API schema changes, providerOptions schemas change, live smoke or user bug reports a concrete mismatch.
```

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

#### `@ai-sdk/openai`

```text
Package: @ai-sdk/openai
Baseline: 3.0.67
Upstream inspected: openai-provider.ts, openai-config.ts, openai-language-model-capabilities.ts, chat/*, responses/*, completion/*, embedding/*, image/*, speech/*, transcription/*, openai-tools.ts, tool/*.ts, openai-error.ts, version.ts.
Swift files inspected: ProviderRegistry.swift, OpenAICompatibleProvider.swift, OpenAICompatible.swift, OpenAISkills.swift, FileClients.swift, OpenAIChatTests.swift, OpenAIResponsesTests.swift, OpenAIMediaTests.swift, FileAndSkillClientTests.swift, ProviderCapabilityMatrix.swift.
Surfaces checked: factory aliases, default base URL, OPENAI_BASE_URL/OPENAI_API_KEY, organization/project headers, custom provider name/root providerOptions routing, user-agent suffix, language defaulting to Responses, chat, completions, Responses, embeddings, image generation/editing, speech, transcription, files, skills, providerOptions/extraBody merging, provider-defined tools, shell/local-shell/apply-patch/tool-search/MCP/custom/code-interpreter/file-search/web-search/image-generation helpers, tool choice/allowed tools, structured text format, automatic Responses includes, logprobs mapping, multimodal/file inputs, multipart image/audio bodies, usage, metadata, stream lifecycle/raw chunks, warnings, and abort propagation through the shared HTTP path.
Known Swift differences / out of scope: Swift keeps files and skills as first-class provider clients even though the upstream OpenAI provider interface is model-factory focused; Swift settings are static dictionaries rather than upstream async resolvable header functions; upstream generateId/fileIdPrefix customization is not exposed; Swift keeps `OpenAITools.computerUse` as an extension for existing Responses parsing coverage, but upstream `@ai-sdk/openai@3.0.67` does not expose it as an `openaiTools` factory and toolChoice now follows upstream provider-tool allow-list behavior.
Tests run: swift test --filter OpenAI; swift test --filter ResponsesEndpoint && swift test --filter OpenAI; swift test with 898 tests.
Commit evidence: e12b20e.
Reopen only if: openai npm version changes, OpenAI Responses/chat/completion/image/audio/tool schemas change, providerOptions schemas add/remove fields, Swift core tool/media contracts change, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/openai-compatible`

```text
Package: @ai-sdk/openai-compatible
Baseline: 2.0.48
Upstream inspected: openai-compatible-provider.ts, chat/openai-compatible-chat-language-model.ts, chat/openai-compatible-chat-options.ts, chat/openai-compatible-prepare-tools.ts, chat/convert-to-openai-compatible-chat-messages.ts, completion/openai-compatible-completion-language-model.ts, completion/convert-to-openai-compatible-completion-prompt.ts, embedding/openai-compatible-embedding-model.ts, image/openai-compatible-image-model.ts, openai-compatible-error.ts, utils/to-camel-case.ts, index.ts, version.ts.
Swift files inspected: ProviderRegistry.swift, OpenAICompatibleProvider.swift, OpenAICompatible.swift, OpenAICompatibleTests.swift, OpenAICompatibleWarningTests.swift, OpenAICompatibleResponseMetadataTests.swift, OpenAIChatTests.swift, ProviderCapabilityMatrix.md, ProviderVersionLedger.md.
Surfaces checked: generic factory aliases, required name/baseURL, optional API key, custom headers, query params, user-agent suffix, upstream provider surface IDs, chat/completion/embedding/image routing, chat providerOptions namespaces including deprecated openai-compatible/openaiCompatible/raw/camel provider keys, completion providerOptions namespaces and upstream chat-like completion prompt/stop sequence conversion, embedding default encoding_format float, embedding providerMetadata passthrough, image raw/camel provider options and b64_json response_format precedence, warnings for deprecated providerOptions keys and unsupported settings, stream metadata/raw-chunk coverage through existing tests, response metadata, transformRequestBody, includeUsage, abort propagation through shared HTTP transport, and generic providerOptions isolation from specialized OpenAI-compatible-backed provider wrappers such as MoonshotAI.
Known Swift differences / out of scope: Swift exposes `extraBody` as an additional escape hatch beside upstream `providerOptions`; Swift provider settings are static dictionaries rather than upstream async resolvable header functions; upstream `metadataExtractor`, `convertUsage`, `supportedUrls`, and embedding `supportsParallelCalls` hooks are not exposed as public Swift settings yet.
Tests run: swift test --filter OpenAICompatible; swift test --filter moonshotLanguageTransformsThinkingOptions; swift test --filter OpenAI; swift test with 899 tests.
Commit evidence: 0badc3c.
Reopen only if: openai-compatible npm version changes, providerOptions namespace or completion prompt semantics change, embedding/image response schemas change, Swift core adds async settings/hooks for metadataExtractor/convertUsage/supportedUrls/supportsParallelCalls, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/open-responses`

```text
Package: @ai-sdk/open-responses
Baseline: 1.0.16
Upstream inspected: open-responses-provider.ts, open-responses-config.ts, open-responses-options.ts, open-responses-language-model.ts, convert-to-open-responses-input.ts, map-open-responses-finish-reason.ts, open-responses-api.ts.
Swift files inspected: ProviderRegistry.swift, OpenAICompatible.swift, ResponsesEndpointTests.swift, OpenAIResponsesTests.swift, ProviderCapabilityMatrix.swift.
Surfaces checked: custom URL factory, provider ID/providerOptions namespace, optional API key, custom header precedence, versioned user-agent suffix, language-only capability, unsupported capability errors, standard option warnings, reasoning provider options, system instructions, message/file/image input conversion, assistant tool-call replay, tool-result output conversion, function tools, tool choice, JSON schema text format, generate response text/reasoning/tool-call/usage/metadata parsing, Open Responses-specific finish reason mapping, stream-start warnings, text/reasoning/function-call streaming, failed stream events, raw chunks, abort propagation through the shared HTTP request path.
Known Swift differences / out of scope: Swift uses `AIProviders.openResponses(name:url:settings:)` instead of upstream's callable `createOpenResponses(options)` shape; Swift provider settings are static rather than upstream's header resolver function; Swift unsupported non-language capabilities throw `AIError.unsupportedModel`; Swift streams may expose broader response metadata/lifecycle parts where the core contract supports them; upstream `generateId` customization is not exposed by SwiftAISDK for this wrapper.
Tests run: swift test --filter openResponses; swift test --filter ResponsesEndpoint; swift test --filter OpenAIResponses; swift test with 892 tests.
Commit evidence: d0d881f.
Reopen only if: open-responses npm version changes, Open Responses request/input/stream schemas change, Swift core response/tool contracts change, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/groq`

```text
Package: @ai-sdk/groq
Baseline: 3.0.39
Upstream inspected: groq-provider.ts, groq-config.ts, groq-chat-language-model.ts, groq-chat-options.ts, convert-to-groq-chat-messages.ts, groq-prepare-tools.ts, groq-tools.ts, tool/browser-search.ts, groq-browser-search-models.ts, groq-transcription-model.ts, groq-transcription-options.ts, groq-api-types.ts, convert-groq-usage.ts, get-response-metadata.ts, map-groq-finish-reason.ts, groq-error.ts, index.ts, version.ts.
Swift files inspected: ProviderRegistry.swift, OpenAICompatibleProvider.swift, GroqModels.swift, LanguageStreamParsing.swift, Core.swift, GroqProviderTests.swift, ProviderAbortPropagationTests.swift, NativeAudioRequestMetadataTests.swift, NativeAudioResponseMetadataTests.swift, NativeTranscriptionDetailTests.swift, ProviderCapabilityMatrix.md, ProviderVersionLedger.md.
Surfaces checked: provider factory, callable/language/chat routing, transcription routing, unsupported embedding/image capabilities, default base URL, GROQ_API_KEY auth, custom header precedence, user-agent suffix, Groq browserSearch tool helper, browser-search supported model gating, function tools, tool choice, provider-defined tool warnings, providerOptions.groq schema validation/nullish behavior, extraBody legacy namespace behavior, structured output and strict JSON schema behavior, reasoning format/effort, parallel tool calls, service tier, user option, topK/structured-output warnings, system/user/assistant/tool message conversion, image URL and inline image parts, non-image rejection, assistant reasoning/tool-call history, tool-result serialization, generate response text/reasoning/tool calls/finish/metadata, stream lifecycle text/reasoning/tool-call/raw chunks/final usage, Groq-specific usage conversion, transcription multipart body and timestamp_granularities[] fields, transcription providerOptions schema/nullish behavior, transcript response validation/details, response metadata, and abort propagation for chat generate/stream and transcription.
Known Swift differences / out of scope: Swift exposes `extraBody` as an additional compatibility escape hatch beside upstream `providerOptions.groq`; Swift settings are static dictionaries rather than upstream async resolvable header functions; upstream `generateId` customization for missing generate tool-call IDs is not exposed in Swift, while streaming keeps upstream's stricter first-delta ID/name expectations through the shared OpenAI-style stream buffer contract where current tests cover normal Groq chunks.
Tests run: swift test --filter Groq; swift test with 899 tests.
Commit evidence: e67562f.
Reopen only if: groq npm version changes, chat/transcription providerOptions schemas change, browser-search model support changes, usage schema changes, stream tool-call chunk requirements change, Swift core adds async settings/generateId hooks, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/mistral`

```text
Package: @ai-sdk/mistral
Baseline: 3.0.37
Upstream inspected: mistral-provider.ts, mistral-chat-language-model.ts, mistral-chat-options.ts, convert-to-mistral-chat-messages.ts, mistral-chat-prompt.ts, mistral-prepare-tools.ts, mistral-embedding-model.ts, mistral-embedding-options.ts, convert-mistral-usage.ts, get-response-metadata.ts, map-mistral-finish-reason.ts, mistral-error.ts, index.ts, version.ts.
Swift files inspected: ProviderRegistry.swift, OpenAICompatibleProvider.swift, MistralModels.swift, CohereMistralVoyageTests.swift, ProviderAbortPropagationTests.swift, NativeVectorResponseMetadataTests.swift, ProviderCapabilityMatrix.md, ProviderVersionLedger.md.
Surfaces checked: provider factory, callable/language/chat routing, embedding aliases, unsupported image capability, default base URL, MISTRAL_API_KEY auth, custom header precedence, user-agent suffix, chat request body, safe prompt, random seed, reasoning effort, document image/page limits, structured outputs, strict JSON schema, JSON-object instruction injection, unsupported standard warnings, message conversion for system/user/assistant/tool roles, inline images, PDF files, unsupported file rejection, assistant reasoning/prefix handling, tool calls, function tools, provider-defined tool warnings, tool choice required/tool filtering, parallel tool-call gating, generate response text/reasoning/tool calls, finish reason mapping, Mistral-specific usage/cache details, response metadata, stream lifecycle text/reasoning/tool input/raw/finish usage, embedding body/limit/float encoding/usage, and abort propagation for generate/stream.
Known Swift differences / out of scope: Swift exposes `extraBody` as an additional compatibility escape hatch beside upstream providerOptions, including for embeddings; Swift settings are static dictionaries rather than upstream async resolvable header functions; upstream `generateId` customization and `supportedUrls` metadata are not public Swift hooks yet.
Tests run: swift test --filter Mistral; swift test with 900 tests.
Commit evidence: 54733c8.
Reopen only if: mistral npm version changes, chat/embedding providerOptions schemas change, Mistral response/usage schemas change, Swift core adds async settings/generateId/supportedUrls hooks, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/cohere`

```text
Package: @ai-sdk/cohere
Baseline: 3.0.36
Upstream inspected: cohere-provider.ts, cohere-chat-language-model.ts, cohere-chat-options.ts, convert-to-cohere-chat-prompt.ts, cohere-chat-prompt.ts, cohere-prepare-tools.ts, cohere-embedding-model.ts, cohere-embedding-options.ts, reranking/cohere-reranking-model.ts, reranking/cohere-reranking-options.ts, reranking/cohere-reranking-api.ts, convert-cohere-usage.ts, map-cohere-finish-reason.ts, cohere-error.ts, index.ts, version.ts.
Swift files inspected: ProviderRegistry.swift, OpenAICompatibleProvider.swift, CohereVoyageModels.swift, CohereMistralVoyageTests.swift, CohereProviderOptionSchemaTests.swift, ProviderAbortPropagationTests.swift, NativeVectorResponseMetadataTests.swift, ProviderCapabilityMatrix.md, ProviderVersionLedger.md.
Surfaces checked: provider factory, callable/language routing, embedding aliases, reranking/rerankingModel aliases, unsupported image capability, default base URL, COHERE_API_KEY auth, custom header precedence, user-agent suffix, chat request body, frequency/presence penalties, max tokens, temperature, p/topP, k/topK, seed, stop sequences, JSON response_format schema mapping, providerOptions.cohere.thinking schema/defaulting, image URL/inline image prompt conversion, image media type defaults, text and JSON document extraction, unsupported document rejection, assistant/tool message conversion, tool-result serialization, function tools, provider-defined tool warnings, tool choice none/required/tool filtering, generate text/reasoning/tool calls/citations/finish/usage/metadata, stream lifecycle text/reasoning/tool-input/tool-call/error/raw/finish usage, embedding body/limits/float type/default input_type/truncate/output dimension/usage, reranking text/object document conversion/options/response metadata/warnings, and abort propagation for chat generate/stream.
Known Swift differences / out of scope: Swift exposes `extraBody` as an additional compatibility escape hatch beside upstream providerOptions, including embedding/reranking raw passthrough; Swift settings are static dictionaries rather than upstream async resolvable header functions; upstream `generateId` customization for citation source IDs and `supportedUrls` metadata are not public Swift hooks yet; Swift stream parts may include additional compatibility `toolCallDelta` events while preserving upstream tool-input lifecycle.
Tests run: swift test --filter Cohere; swift test with 901 tests.
Commit evidence: 5f0bd7f.
Reopen only if: cohere npm version changes, chat/embedding/reranking providerOptions schemas change, Cohere stream event or usage schemas change, Swift core adds async settings/generateId/supportedUrls hooks, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/perplexity`

```text
Package: @ai-sdk/perplexity
Baseline: 3.0.33
Upstream inspected: perplexity-provider.ts, perplexity-language-model.ts, perplexity-language-model-options.ts, perplexity-language-model-prompt.ts, convert-to-perplexity-messages.ts, convert-perplexity-usage.ts, map-perplexity-finish-reason.ts, index.ts, version.ts.
Swift files inspected: ProviderRegistry.swift, OpenAICompatibleProvider.swift, PerplexityModels.swift, ResponsesEndpointTests.swift, ProviderAbortPropagationTests.swift, ProviderCapabilityMatrix.md, ProviderVersionLedger.md.
Surfaces checked: provider factory, callable/language routing, unsupported embedding/image capabilities, default base URL, PERPLEXITY_API_KEY auth, custom header precedence, user-agent suffix, chat completions route, request body standard options, unsupported topK/stopSequences/seed warnings, JSON schema response_format, providerOptions.perplexity passthrough, transformRequestBody, text/image/PDF message conversion, tool-message rejection, generate response validation, text output, finish reason mapping, usage/reasoning token conversion, citations as URL sources, images/usage/cost provider metadata, response metadata, stream lifecycle text/source/error/raw/finish metadata, stream usage/provider metadata, and abort propagation for generate/stream.
Known Swift differences / out of scope: Swift exposes `extraBody` as an additional compatibility escape hatch beside upstream providerOptions; Swift settings are static dictionaries rather than upstream async resolvable header functions; upstream `generateId` customization for citation source IDs and `supportedUrls` metadata are not public Swift hooks yet; Swift uses deterministic citation IDs and may expose additional `finishMetadata` provider metadata shape through the core stream contract.
Tests run: swift test --filter perplexity; swift test with 902 tests.
Commit evidence: 3b96637.
Reopen only if: perplexity npm version changes, chat/options/message/usage/stream schemas change, Perplexity adds new provider capabilities, Swift core adds async settings/generateId/supportedUrls hooks, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/xai`

```text
Package: @ai-sdk/xai
Baseline: 3.0.93
Upstream inspected: xai-provider.ts, xai-chat-language-model.ts, xai-chat-options.ts, convert-to-xai-chat-messages.ts, xai-prepare-tools.ts, convert-xai-chat-usage.ts, map-xai-finish-reason.ts, responses/xai-responses-language-model.ts, responses/xai-responses-options.ts, responses/convert-to-xai-responses-input.ts, responses/xai-responses-prepare-tools.ts, responses/convert-xai-responses-usage.ts, xai-image-model.ts, xai-image-options.ts, xai-video-model.ts, xai-video-options.ts, tool/*.ts, xai-error.ts, index.ts, version.ts.
Swift files inspected: ProviderRegistry.swift, OpenAICompatibleProvider.swift, OpenAICompatible.swift, XAIResponses.swift, XAIModels.swift, FileClients.swift, XAIChatProviderTests.swift, XAIProviderTests.swift, ResponsesEndpointTests.swift, FileAndSkillClientTests.swift, ProviderCapabilityMatrix.md, ProviderVersionLedger.md.
Surfaces checked: factory aliases, provider IDs, default base URL, XAI_API_KEY auth, custom header precedence, user-agent suffix, unsupported embeddings, chat route, Responses route, image route, video route, files route, provider references, chat providerOptions, Responses providerOptions, reasoning effort schemas, logprobs/topLogprobs, seed, structured JSON formats, search parameters, function tools, xAI provider-defined tools, provider-tool toolChoice warnings, message/input conversion, inline image data, non-image Files API references, tool-result serialization, usage/cache/reasoning token conversion, finish reasons, response metadata, media polling/options/metadata, file metadata/team ID, stream usage/raw/error coverage, and abort propagation through language/media/file paths.
Known Swift differences / out of scope: Swift has no separate non-image URL file content part in the core message contract, so xAI Responses non-image files use Files API provider references (`file_id`) rather than upstream URL file parts; Swift settings are static dictionaries rather than upstream async resolvable header functions; upstream `generateId` customization is not exposed as a public Swift hook.
Tests run: swift test --filter xAI; swift test --filter ResponsesEndpoint; swift test with 903 tests.
Commit evidence: 7d689df.
Reopen only if: xai npm version changes, xAI chat/Responses providerOptions schemas change, xAI tool or media/file schemas change, Swift core adds URL file parts/async settings/generateId hooks, live smoke or user bug reports a concrete mismatch.
```

#### `@ai-sdk/deepseek`

```text
Package: @ai-sdk/deepseek
Baseline: 2.0.35
Upstream inspected: deepseek-provider.ts, chat/deepseek-chat-language-model.ts, chat/deepseek-chat-options.ts, chat/convert-to-deepseek-chat-messages.ts, chat/deepseek-prepare-tools.ts, chat/convert-to-deepseek-usage.ts, chat/map-deepseek-finish-reason.ts, chat/deepseek-chat-api-types.ts, chat/get-response-metadata.ts, index.ts, version.ts.
Swift files inspected: ProviderRegistry.swift, OpenAICompatibleProvider.swift, DeepSeekModels.swift, DeepSeekProviderTests.swift, ProviderAbortPropagationTests.swift, ProviderCapabilityMatrix.md, ProviderVersionLedger.md.
Surfaces checked: factory aliases, provider IDs, default base URL, DEEPSEEK_API_KEY auth, custom header precedence, user-agent suffix, unsupported embedding/image capabilities, chat route, request body standard options, providerOptions.deepseek schema/null handling, thinking/reasoningEffort mapping, topK/seed warnings, JSON response format and schema instruction injection, system/user/assistant/tool message conversion, R1/V4 reasoning history behavior, function tools, provider-defined tool warnings, tool choice mapping, tool-result serialization, generate response text/reasoning/tool calls/finish/usage/metadata, stream lifecycle text/reasoning/tool-input/tool-call/raw/error/finish usage, strict first tool-call delta validation, response metadata, and abort propagation through generate/stream.
Known Swift differences / out of scope: Swift exposes `extraBody` as an additional compatibility escape hatch beside upstream providerOptions; Swift settings are static dictionaries rather than upstream async resolvable header functions; upstream `generateId` customization for generated missing tool-call IDs is not exposed as a public Swift hook, while DeepSeek stream now follows upstream strict first-delta validation before the shared Swift stream buffer can fall back.
Tests run: swift test --filter DeepSeek; swift test with 907 tests.
Commit evidence: e25563e.
Reopen only if: deepseek npm version changes, DeepSeek chat/providerOptions/message/usage/stream schemas change, Swift core adds async settings/generateId hooks, live smoke or user bug reports a concrete mismatch.
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

#### `@ai-sdk/amazon-bedrock`

```text
Package: @ai-sdk/amazon-bedrock
Baseline: 4.0.112
Upstream inspected: bedrock-provider.ts, bedrock-sigv4-fetch.ts, bedrock-chat-language-model.ts, bedrock-chat-options.ts, bedrock-prepare-tools.ts, convert-to-bedrock-chat-messages.ts, bedrock-embedding-model.ts, bedrock-embedding-options.ts, bedrock-image-model.ts, bedrock-image-settings.ts, reranking/bedrock-reranking-model.ts, reranking/bedrock-reranking-options.ts, anthropic/bedrock-anthropic-provider.ts, anthropic/bedrock-anthropic-fetch.ts, anthropic/bedrock-anthropic-options.ts, mantle/bedrock-mantle-provider.ts, mantle/bedrock-mantle-options.ts, event-stream/usage/finish helpers, index.ts, version.ts.
Swift files inspected: AmazonBedrockProvider.swift, AmazonBedrockModels.swift, LanguageStreamParsing.swift, Anthropic.swift, OpenAICompatibleProvider.swift, OpenAICompatible.swift, Core.swift, AI.swift, AmazonBedrockTests.swift.
Surfaces checked: main provider factory and capability routing, Bedrock Anthropic subprovider, Bedrock Mantle chat/responses subprovider, runtime and agent-runtime base URLs, bearer auth, static SigV4 auth, async dynamic credential provider, session-token signing behavior, user-agent suffixes, Converse request bodies, providerOptions.bedrock and providerOptions.amazonBedrock merging, extraBody passthrough filtering, unsupported frequency/presence/seed warnings, responseFormat JSON tool behavior, native Anthropic structured output with thinking, function/provider tools, tool choice, reasoningConfig transforms, document/image inputs and citations, response text/reasoning/tool calls, finish reasons, cache/trace/performance/service-tier metadata, event-stream text/reasoning/tool/raw/metadata/final usage, Titan/Cohere/Nova embedding bodies and response shapes, image text/edit modes, image moderation/no-image errors, aspectRatio warning, Nova Canvas count limit, reranking body/options/response, Bedrock Anthropic invoke/stream/download/structured-output behavior, Mantle OpenAI-compatible routes, and abort propagation through focused existing tests.
Known Swift differences / out of scope: Swift defaults Bedrock region to `us-east-1` when no region/env is supplied, while upstream relies on `AWS_REGION` loading for SigV4 credential resolution and then has fallback URL defaults; Swift settings headers are static dictionaries rather than upstream async Resolvable headers; Swift keeps `extraBody` and both `bedrock`/`amazonBedrock` provider option namespaces as compatibility escape hatches; Swift exposes Bedrock Anthropic and Bedrock Mantle as explicit provider factories instead of npm subpath factory exports; `generateId` customization is not exposed for Bedrock-generated source/tool IDs yet.
Tests run: swift test --filter AmazonBedrock with 28 tests; swift test with 889 tests.
Commit evidence: e2cb97e.
Reopen only if: @ai-sdk/amazon-bedrock npm version changes, Bedrock auth/credential/session-token behavior changes, Converse/InvokeModel/agent-runtime schemas change, embedding/image/reranking providerOptions schemas change, generateId or async header behavior becomes required in Swift core, live smoke or user bug reports a concrete mismatch.
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

The model-provider package deep-pass queue is empty. Packages move back here only
when npm discovery finds a new provider package, an upstream version changes, or
a live/user report identifies a concrete mismatch.

## Needs Explicit Deep Pass

No package is currently waiting for an explicit deep pass.

## Practical Remaining Queue

The remaining product work is now outside the ordinary model-provider sweep:

1. Run a final completion audit against npm provider discovery, the version
   ledger, capability matrix, live smoke, and full tests before declaring the
   overall port complete.
2. Add more live smoke slices only for distinct transport families or concrete
   production risks. Mock parity is intentionally broader than live coverage.

## Completion Audit Snapshot

2026-06-03 completed:

- Current `npm search @ai-sdk --json --searchlimit=250` provider-like packages
  found: `alibaba`, `amazon-bedrock`, `anthropic`, `assemblyai`, `azure`,
  `baseten`, `black-forest-labs`, `bytedance`, `cerebras`, `cohere`,
  `deepgram`, `deepinfra`, `deepseek`, `elevenlabs`, `fal`, `fireworks`,
  `gateway`, `gladia`, `google`, `google-vertex`, `groq`, `huggingface`,
  `hume`, `klingai`, `lmnt`, `luma`, `mcp`, `mistral`, `moonshotai`,
  `open-responses`, `openai`, `openai-compatible`, `perplexity`, `prodia`,
  `replicate`, `revai`, `togetherai`, `vercel`, and `xai`.
- The search also returned non-provider/client packages intentionally outside
  the provider port: `angular`, `codemod`, `devtools`, `langchain`,
  `llamaindex`, `provider`, `provider-utils`, `react`, `rsc`, `solid`,
  `svelte`, `ui-utils`, `valibot`, `vue`, and `workflow`.
- `Docs/ProviderVersionLedger.md` and `AIProviderCapabilities` cover every
  provider-like package above. The ledger additionally tracks provider packages
  that were included in earlier discovery/deep-pass work but did not appear in
  this search result: `anthropic-aws`, `quiverai`, and `voyage`.
- Live smoke with real root credentials passed for representative core facades:
  OpenAI generate/stream/embedding/tool-loop, Anthropic generate/stream/tool-loop,
  and Google generate/stream/embedding/tool-loop.
- Final full-suite result: `swift test` passed with 944 tests.
