# Upstream Sync Guide

This package ports provider-facing core functionality from Vercel AI SDK
(`@ai-sdk/*`) into Swift.

## Current Upstream Snapshot

- npm provider search checked on 2026-05-31 with:

  ```sh
  curl -s 'https://registry.npmjs.org/-/v1/search?text=%40ai-sdk%2F&size=250' \
    | jq -r '.objects[].package | select(.name|startswith("@ai-sdk/")) | [.name,.version,.description] | @tsv'
  ```

- Vercel AI SDK source checked from:

  ```sh
  git clone --depth=1 https://github.com/vercel/ai.git /tmp/vercel-ai-sdk-upstream
  git -C /tmp/vercel-ai-sdk-upstream log -1 --format='%h %cI %s'
  ```

- Snapshot used for this pass:

  ```text
  ab6d664 2026-05-29T17:54:18-07:00 Version Packages (canary) (#15714)
  ```

## Provider Selection Rule

Treat an `@ai-sdk/*` package as in scope when its npm short description says it is
a provider or exposes provider models. Exclude UI/adapters/dev packages such as
`react`, `vue`, `angular`, `svelte`, `rsc`, `mcp`, `langchain`, `llamaindex`,
`valibot`, `codemod`, and `devtools` unless the Swift package later gains a UI
or adapter layer.

The current Swift registry covers:

`openai`, `anthropic`, `anthropic-aws`, `google`, `azure`, `gateway`, `mistral`, `xai`,
`deepseek`, `togetherai`, `cohere`, `amazon-bedrock`, `groq`, `perplexity`,
`fireworks`, `replicate`, `deepgram`, `elevenlabs`, `fal`, `deepinfra`,
`baseten`, `cerebras`, `vercel`, `alibaba`, `hume`, `lmnt`, `revai`, `gladia`,
`moonshotai`, `assemblyai`, `black-forest-labs`, `huggingface`, `prodia`,
`open-responses`, `luma`, `openai-compatible`, `klingai`, `bytedance`,
`voyage`, and `quiverai`.

## Where To Look Upstream

For every provider package, start with these files:

```text
/tmp/vercel-ai-sdk-upstream/packages/<provider>/src/*provider.ts
/tmp/vercel-ai-sdk-upstream/packages/<provider>/src/index.ts
/tmp/vercel-ai-sdk-upstream/packages/<provider>/src/*language-model*.ts
/tmp/vercel-ai-sdk-upstream/packages/<provider>/src/*embedding*.ts
/tmp/vercel-ai-sdk-upstream/packages/<provider>/src/*image*.ts
/tmp/vercel-ai-sdk-upstream/packages/<provider>/src/*transcription*.ts
/tmp/vercel-ai-sdk-upstream/packages/<provider>/src/*speech*.ts
/tmp/vercel-ai-sdk-upstream/packages/<provider>/src/*video*.ts
/tmp/vercel-ai-sdk-upstream/packages/<provider>/src/*.test.ts
```

Read in this order:

1. `*provider.ts`: default base URL, auth header, env var names, supported
   model factories, aliases, and unsupported model behavior.
2. Model implementation files: endpoint path, request conversion, response
   parsing, usage metadata, finish reasons, streaming event format.
3. Tests: these are the best executable examples of exact request bodies and
   edge cases. Port tests before or alongside behavior changes.

Useful search:

```sh
rg -n 'baseURL|environmentVariableName|headers|new .*Model|NoSuchModelError' \
  /tmp/vercel-ai-sdk-upstream/packages/<provider>/src
```

## Where To Change Swift Code

- `Sources/ai-sdk-port/Core.swift`
  Shared public request/result types and model/provider protocols. The language
  result surface includes visible `text`, optional `reasoning`, `toolCalls`,
  `sources`, raw JSON, and provider metadata. Sources mirror upstream
  `LanguageModelV4Source` for URL/document citations and carry optional
  provider metadata plus the raw source part for provider-specific fields.
  `LanguageStreamPart.source` is the streaming counterpart used by providers
  that emit source chunks, while `LanguageStreamPart.metadata` carries provider
  metadata-only deltas such as Bedrock reasoning signatures or trace/service
  tier metadata. `AIProvider` also exposes upstream-style Swift aliases:
  `provider(modelID)`, `chat`, `embedding`, `textEmbeddingModel`,
  `textEmbedding`, `image`, `transcription`, `speech`, `video`, and
  `reranking`, all forwarding to the canonical `*Model` methods. Concrete
  providers override aliases where upstream uses a non-default route: OpenAI,
  Azure, and xAI-style providers keep `chat` on chat-completions and
  `responses` on Responses, while Anthropic exposes `messages`.

- `Sources/ai-sdk-port/HTTP.swift`
  Transport abstraction, URLSession implementation, JSON encode/decode helpers,
  env var helper, and common usage parsing.

- `Sources/ai-sdk-port/Models/OpenAICompatible.swift`
  OpenAI-compatible chat, completions, responses, embeddings, images, speech,
  streaming SSE, and multipart transcription request/response logic. Use this
  when upstream providers wrap `@ai-sdk/openai-compatible` or hit OpenAI-shaped
  APIs. OpenAI's default `languageModel` is wired to the Responses API, matching
  upstream; explicit `chatModel` / `chat` remain available for
  `/chat/completions`, and `completion` / `responses` mirror upstream aliases.
  Chat-compatible requests follow upstream `openai-compatible-prepare-tools.ts`
  / `openai-chat-prepare-tools.ts`: Swift function tools become
  `{ type: "function", function: ... }` entries, `strict` is lifted into the
  function object, provider-defined tools are ignored for chat-compatible APIs,
  and `toolChoice` maps to `tool_choice`.
  Chat-compatible response parsing follows upstream
  `openai-compatible-chat-language-model.ts`: non-streaming
  `message.tool_calls[]` are exposed as `TextGenerationResult.toolCalls`, empty
  text is accepted when the model only returns tool calls, `tool_calls` /
  `function_call` finish reasons normalize to `tool-calls`, streaming
  `delta.tool_calls[]` are buffered by `index`, exposed as
  `LanguageStreamPart.toolCallDelta`, and flushed as final
  `LanguageStreamPart.toolCall` values before finish. OpenAI-compatible chat
  and completion streaming follow upstream's `includeUsage` provider setting by
  sending `stream_options.include_usage`, and completions use native SSE
  streaming instead of the default generate-then-yield fallback. Custom
  OpenAI-compatible providers also carry upstream `queryParams` through
  `ProviderSettings.queryParams`, appending them to chat, completion,
  embedding, and image model URLs. `supportsStructuredOutputs` is mirrored for
  chat models: Swift `extraBody.responseFormat` with `{ type: "json" }` maps
  to `json_object` by default and to upstream `json_schema` when a schema is
  present and structured outputs are enabled. `transformRequestBody` is exposed
  as a Swift closure and applied to chat generate/stream request bodies after
  the standard OpenAI-compatible argument mapping, matching upstream proxy
  provider behavior. Nested provider options follow upstream namespace
  precedence for custom OpenAI-compatible providers: deprecated
  `openai-compatible`, `openaiCompatible`, raw provider names such as
  `test-provider`, and camelCase provider names such as `testProvider` are
  unwrapped where the upstream model supports them. Custom OpenAI-compatible
  image generation follows upstream by forcing `response_format: b64_json` on
  `/images/generations` after provider options are applied, and enforces the
  upstream `maxImagesPerCall` limit of 10 before sending requests. Official
  OpenAI/Azure image models use upstream's model-specific max image table
  (`dall-e-3` and unknown deployment IDs default to 1; `dall-e-2`,
  `gpt-image-*`, and `chatgpt-image-latest` allow 10). The shared embedding
  model mirrors upstream `maxEmbeddingsPerCall`: default 2048, with a Swift
  override exposed on `ProviderSettings` / `AIProviders.openAICompatible`.
  Responses input conversion maps Swift text/image/PDF content into
  `input_text`, `input_image`, and `input_file` parts, and maps common upstream
  provider options such as `previousResponseId`, `parallelToolCalls`,
  `serviceTier`, `reasoningEffort`, and `reasoningSummary`. OpenAI-backed
  chat, Responses, completions, embeddings, image, speech, and transcription
  paths unwrap nested `openai` provider options like upstream
  `providerOptions.openai`, and image / transcription paths map upstream
  camelCase provider options into API fields such as `output_format`,
  `output_compression`, and
  `timestamp_granularities[]`; image calls switch to multipart
  `/images/edits` when `ImageGenerationRequest.files` is set, including
  repeated `image` parts and optional `mask`. OpenAI speech defaults `voice`
  and `response_format`. The shared Responses model normalizes upstream finish
  reasons for both generate and stream paths (`completed -> stop`,
  `max_output_tokens -> length`, `content_filter -> content-filter`, and
  `tool_calls -> tool-calls`). Responses tools follow upstream
  `openai-responses-prepare-tools.ts`: Swift function tools are sent as
  Responses `function` entries, while provider-defined sentinels with
  `id: "openai.*"` map to hosted tools such as `web_search`,
  `web_search_preview`, `file_search`, `code_interpreter`,
  `image_generation`, `mcp`, shell/local-shell, `custom`, and `tool_search`;
  `OpenAITools` provides Swift builders for those upstream `openai.tools`
  factories, and `toolChoice` maps to Responses `tool_choice`, including
  hosted and custom tool selection. Responses output parsing follows
  `openai-responses-language-model.ts` for the main tool-call surfaces:
  `function_call` and `custom_tool_call` output items become
  `TextGenerationResult.toolCalls`, hosted calls such as `web_search_call`,
  `file_search_call`, `image_generation_call`, `code_interpreter_call`,
  `tool_search_call`, shell/local-shell, and `apply_patch_call` are preserved
  as provider-executed tool calls where applicable, and streaming
  `response.output_item.added`, `response.function_call_arguments.delta`,
  `response.custom_tool_call_input.delta`, and `response.output_item.done`
  produce tool-call delta/final stream parts. HuggingFace language models now
  use a native Responses implementation matching `packages/huggingface/src`:
  the dedicated Swift provider mirrors upstream `huggingface-provider.ts`
  (`providerID` `huggingface`, model provider `huggingface.responses`,
  `responsesModel` alias, `HUGGINGFACE_API_KEY` auth), and the model maps
  router `/responses`, `input_text`/`input_image` prompt parts, nested
  `huggingface` provider options for `metadata`, `instructions`, and
  `reasoningEffort`, response annotations as URL `AISource` values, reasoning
  output, and `function_call`/`mcp_call`/`mcp_list_tools` output items.
  Custom Open Responses providers created through `AIProviders.openResponses`
  also force the Responses body shape against the exact configured POST
  endpoint, matching `@ai-sdk/open-responses`. Fireworks chat uses this
  implementation with the upstream transform for `thinking`, `reasoningHistory`,
  and Fireworks' three-level `reasoning_effort` mapping.

- `Sources/ai-sdk-port/Models/MistralModels.swift`
  Native Mistral chat and embedding implementations. Chat maps Mistral content
  parts for text/image/PDF, `safe_prompt`, `random_seed`, document limits, and
  SSE text/reasoning chunks. Upstream-style nested `mistral` provider options
  are unwrapped for chat and embedding request bodies. Tools follow upstream
  `mistral-prepare-tools.ts`:
  Swift `tools` are sent as OpenAI-style function tool entries,
  `toolChoice: required`/`tool` maps to Mistral `tool_choice: any`, forced tool
  choice filters the tool list, and `parallel_tool_calls` is only sent when
  tools are present. Response-side tool calls follow
  `mistral-chat-language-model.ts`: non-streaming `message.tool_calls[]` fill
  `TextGenerationResult.toolCalls`, and streaming `delta.tool_calls[]` emits
  tool-call delta/final stream parts before the normalized `tool-calls` finish.
  Embeddings enforce the upstream 32-input limit and send `encoding_format:
  float`.

- `Sources/ai-sdk-port/Models/Anthropic.swift`
  Anthropic Messages request conversion and response parsing. Compare with
  upstream `anthropic-language-model.ts`,
  `anthropic-language-model-options.ts`, `convert-to-anthropic-prompt.ts`, and
  `map-anthropic-stop-reason.ts`. The Swift port maps common provider options
  from camelCase to Anthropic API fields (`topK`, `thinking.budgetTokens`,
  `metadata.userId`, `contextManagement`, `mcpServers`, `taskBudget`,
  `inferenceGeo`, and `cacheControl`), applies upstream thinking sampling rules,
  converts image/PDF/text parts into Anthropic content blocks, maps function
  tools into `input_schema` entries, and maps `AnthropicTools` provider-defined
  helpers through upstream `anthropic-prepare-tools.ts` shapes including
  `anthropic-beta` headers. `GoogleVertexAnthropicTools` exposes the supported
  Vertex Anthropic subset from upstream `google-vertex-anthropic-provider.ts`.
  Response-side
  tool calls follow `anthropic-language-model.ts`: `tool_use` blocks become
  `TextGenerationResult.toolCalls`, `server_tool_use` and `mcp_tool_use` are
  preserved as provider-executed tool calls, `tool_use` stop reasons normalize
  to `tool-calls`, and streaming `content_block_start` /
  `input_json_delta` / `content_block_stop` events produce tool-call delta and
  final stream parts. Text-block citations and streaming `citations_delta`
  events map to `AISource` document or URL sources with
  `providerMetadata.anthropic` citation offsets/page numbers/cited text, and
  `web_search_tool_result` blocks also emit URL sources with Anthropic page-age
  metadata.

- `Sources/ai-sdk-port/Providers/AnthropicAWSProvider.swift`
  Claude Platform on AWS wrapper corresponding to upstream
  `@ai-sdk/anthropic-aws`. It reuses the native Anthropic Messages model but
  applies the AWS base URL, `anthropic-workspace-id`, API-key auth via
  `ANTHROPIC_AWS_API_KEY`/`x-api-key`, or SigV4 signing with service
  `aws-external-anthropic` for AWS credential flows.

- `Sources/ai-sdk-port/Models/GoogleGenerativeAI.swift`
  Google Gemini `generateContent`, embedding conversion, and native Google
  language tool-call support. Request-side tool preparation is shared with
  Vertex through `Models/GoogleTools.swift`, following upstream
  `google-prepare-tools.ts`: Swift function tools become Gemini
  `functionDeclarations`, common Google provider-defined tools
  (`google_search`, `url_context`, `code_execution`, `file_search`, Vertex RAG,
  Maps, and enterprise web search) map to native Google tool entries, and
  `GoogleTools` / `GoogleVertexTools` mirror upstream `google.tools` and
  `googleVertex.tools` builders for those provider-defined tools. `toolChoice`
  becomes `toolConfig.functionCallingConfig` rather than leaking
  into the raw request body. `functionCall` parts from non-streaming candidates
  populate `TextGenerationResult.toolCalls`, `STOP` normalizes to `tool-calls`
  when tool calls are present, and streaming `functionCall` parts / Gemini
  `partialArgs` are buffered into tool-call delta/final stream parts. Gemini
  `groundingMetadata.groundingChunks` now follows upstream `extractSources`:
  web/image/maps chunks become URL `AISource` values, retrieved RAG/file-search
  chunks become URL or document sources, and streaming chunks emit deduplicated
  `LanguageStreamPart.source` values. Imagen
  image models use `/models/{modelID}:predict` with `instances`
  and `parameters`; when `ImageGenerationRequest.files` is set,
  Imagen switches to the upstream edit shape with `referenceImages`, optional
  `REFERENCE_TYPE_MASK`, `editMode`, `editConfig.baseSteps`, and mask dilation
  options. Gemini image models use
  `/models/{modelID}:generateContent` with `responseModalities: ["IMAGE"]`;
  Veo video models use `/models/{modelID}:predictLongRunning` and poll the
  returned operation, appending the API key to generated file URLs like
  upstream. The same file also contains the Google Interactions language model
  exposed through `GoogleGenerativeAIProvider.interactionsModel(_:)` and
  `interactionsAgent(_:)`: it posts to `/interactions`, pins
  `Api-Revision: 2026-05-20`, converts Swift messages into `user_input` /
  `model_output` steps, maps generation/provider options into
  `generation_config` and snake_case fields, polls non-terminal agent
  responses, parses `function_call` steps into `TextGenerationResult.toolCalls`,
  maps Interactions annotations and built-in tool-result steps into `AISource`
  URL/document sources, preserves interaction id/service tier under
  `providerMetadata.google`, and maps Interactions SSE `step.start` /
  `arguments_delta` / `step.stop` function-call events plus text annotations
  into tool-call delta/final and deduplicated source stream parts.

- `Sources/ai-sdk-port/Models/GenericMediaModels.swift`
  JSON-oriented image, transcription, and speech fallback models used by
  providers whose APIs are not OpenAI-shaped yet.

- `Sources/ai-sdk-port/Models/CohereVoyageModels.swift`
  Native Cohere and Voyage implementations. Cohere maps upstream `/chat`,
  `/embed`, and `/rerank` request shapes, including Cohere SSE text/reasoning
  deltas, and unwraps nested `cohere` provider options for chat reasoning,
  embedding, and reranking options. Cohere tool calls follow
  `cohere-chat-language-model.ts`:
  non-streaming `message.tool_calls[]` populate `TextGenerationResult.toolCalls`,
  `"null"`/empty arguments normalize to `{}`, and streaming
  `tool-call-start` / `tool-call-delta` / `tool-call-end` events produce
  tool-call delta/final stream parts. Cohere `message.citations[]` are exposed
  as document `AISource` values with `providerMetadata.cohere`, matching
  upstream source content parts. Non-image Swift file/data content parts are
  lifted into the Cohere `documents: [{ data: { text, title? } }]` RAG payload,
  while image files stay inline as `image_url` parts. Voyage maps `/embeddings` and `/rerank`,
  including response ordering by embedding index, nested `voyage` provider
  options, and upstream `returnDocuments` reranking option mapping.

- `Sources/ai-sdk-port/Models/TogetherAIModels.swift`
  Native TogetherAI image and reranking implementations. Image generation uses
  width/height, `response_format: base64`, upstream image provider options
  such as `steps`/`guidance`, and Swift-friendly aliases for
  `negative_prompt`, `disable_safety_checker`, and `image_url`; nested
  `togetherai`/`togetherAI` provider options are unwrapped like upstream
  `providerOptions.togetherai`. Input files are converted to `image_url`
  reference/data-URI values like upstream; masks are rejected because TogetherAI
  does not support mask-based edits. Reranking uses `/rerank` with `top_n`,
  `rank_fields`, and `return_documents: false` by default.

- `Sources/ai-sdk-port/Models/DeepInfraModels.swift`
  Native DeepInfra image implementation. Chat/completions/embeddings use the
  OpenAI-compatible `/openai` base, while image generation swaps to
  `/v1/inference/{modelID}` and strips data-URL base64 prefixes from returned
  images. When `ImageGenerationRequest.files` is set, it follows upstream edit
  mode and posts multipart form data to `/openai/images/edits`, including
  repeated `image` parts, optional `mask`, size/count, and scalar provider
  options. Nested `deepinfra` provider options are unwrapped for both JSON
  generation and multipart edit requests, matching upstream
  `providerOptions.deepinfra`.

- `Sources/ai-sdk-port/Models/PerplexityModels.swift`
  Native Perplexity chat implementation. It uses `/chat/completions` but maps
  upstream Perplexity request quirks: no `stop` forwarding, image/PDF multipart
  content conversion, provider options through `extraBody`, citations/images/
  search/cost metadata preserved in `rawValue`, citations exposed as
  `TextGenerationResult.sources` / `LanguageStreamPart.source`, and streaming
  usage carried to the finish part.

- `Sources/ai-sdk-port/Models/BasetenModels.swift`
  Baseten-specific embedding behavior. Chat uses the OpenAI-compatible model
  API, but embeddings require `ProviderSettings.baseURL` to point at a Baseten
  dedicated `/sync` or `/sync/v1` model URL; `/sync` is normalized to
  `/sync/v1/embeddings`, matching upstream's `modelURL` flow.

- `Sources/ai-sdk-port/Models/GroqModels.swift`
  Native Groq chat/transcription behavior. Chat maps Groq provider options
  such as `reasoningFormat`, `reasoningEffort`, `parallelToolCalls`, and
  `serviceTier`, accepts upstream-style nested `groq` provider options without
  leaking that object into the JSON body, and emits streaming `reasoningDelta`
  parts from Groq chunks.
  Tool preparation follows upstream `groq-prepare-tools.ts`: Swift function
  tools are converted to OpenAI-style function entries, `toolChoice` maps to
  Groq `tool_choice`, and the provider-defined `groq.browser_search` sentinel
  maps to `{ type: "browser_search" }` only for upstream-supported models
  (`openai/gpt-oss-20b` and `openai/gpt-oss-120b`).
  `GroqTools.browserSearch()` mirrors upstream `groq.tools.browserSearch()`
  for building that provider-defined sentinel. Response-side tool calls
  follow `groq-chat-language-model.ts`: non-streaming `message.tool_calls[]`
  populate `TextGenerationResult.toolCalls`, streaming `delta.tool_calls[]`
  are buffered by `index` for fragmented JSON arguments, and `tool_calls` /
  `function_call` finish reasons normalize to `tool-calls`.
  Transcription maps Groq's
  camelCase provider options into multipart fields like `response_format` and
  `timestamp_granularities[]`, including when those options arrive under the
  nested `groq` provider-options key.

- `Sources/ai-sdk-port/Models/DeepSeekModels.swift`
  Native DeepSeek chat behavior. Streams request
  `stream_options.include_usage`, emits `reasoningDelta` from
  `reasoning_content`, maps `reasoningEffort` to DeepSeek's provider values,
  sends empty `reasoning_content` on assistant turns for DeepSeek V4 models,
  and follows `deepseek-chat-language-model.ts` for response-side tool calls:
  non-streaming `message.tool_calls[]` populate
  `TextGenerationResult.toolCalls`, streaming `delta.tool_calls[]` are buffered
  by `index` for fragmented arguments, `tool_calls` normalizes to
  `tool-calls`, and `insufficient_system_resource` normalizes to `error`.
  `OpenAICompatibleProvider.chatModel` routes DeepSeek's explicit chat factory
  here, matching upstream `provider.chat = createLanguageModel`.

- `Sources/ai-sdk-port/Models/CerebrasModels.swift`
  Native Cerebras chat behavior. It maps assistant `reasoning_content` history
  to the `reasoning` field Cerebras expects, mirrors upstream
  `supportsStructuredOutputs` by mapping Swift `extraBody.responseFormat` into
  `response_format.json_schema`, emits streaming reasoning deltas, and follows
  `cerebras-chat-language-model.ts` for captured tool calls:
  non-streaming `message.tool_calls[]` and streaming `delta.tool_calls[]`
  populate Swift tool-call result/stream parts, while the mixed GLM structured
  output case drops repeated tool calls after JSON text is present and
  normalizes the `tool_calls` finish reason to `stop`.
  `OpenAICompatibleProvider.chatModel` routes Cerebras' explicit chat factory
  here, matching upstream `provider.chat = createLanguageModel`.

- `Sources/ai-sdk-port/Models/FireworksModels.swift`
  Native Fireworks image implementation. It follows upstream's per-model URL
  backend map: `/image_generation/{modelID}` for legacy image models,
  `/workflows/{modelID}/text_to_image` for synchronous workflow models, and
  `/workflows/{modelID}` plus `/get_result` polling for async Kontext models.
  Sync and async image payloads are binary and are returned as base64 images in
  Swift.

- `Sources/ai-sdk-port/Models/QuiverAIModels.swift`
  Native QuiverAI SVG image implementation. It follows upstream's
  `quiverai-image-model.ts`: `generate` posts JSON to `/svgs/generations`,
  reference images become `references` URL/base64 objects with the upstream
  4-image or `arrow-1.1-max` 16-image limit, and `vectorize` posts a single
  image reference to `/svgs/vectorizations`. Returned SVG text is exposed as
  base64 image bytes while the raw response keeps QuiverAI metadata and usage.

- `Sources/ai-sdk-port/Models/XAIModels.swift`
  Native xAI image/video implementations. `languageModel` is wired to the
  Responses endpoint by default, matching upstream; image generation sends
  `response_format: b64_json` and downloads URL image outputs into returned
  bytes/base64 when needed, switches to `/images/edits` when `files` are
  present, unwraps nested `xai` options, and maps edit images to xAI `image` or
  `images` URL objects. Video generation creates a request then polls
  `/videos/{request_id}` with upstream mode autodetection for `videoUrl` edits,
  `extend-video`, and reference-to-video requests.

- `Sources/ai-sdk-port/Models/AlibabaModels.swift`
  Native Alibaba/DashScope chat implementation. It follows upstream's
  OpenAI-compatible URL with Alibaba-specific message conversion: user turns are
  always content arrays, image URLs/data URLs map to `image_url` parts, thinking
  provider options map from camelCase to `enable_thinking` and
  `thinking_budget`, streaming waits for the final usage-only chunk before
  yielding the finish part, and response-side tool calls follow
  `alibaba-chat-language-model.ts`: non-streaming `message.tool_calls[]`
  populate `TextGenerationResult.toolCalls`, streaming `delta.tool_calls[]`
  are buffered by `index` for fragmented arguments, and `tool_calls` /
  `function_call` finish reasons normalize to `tool-calls`.

- MoonshotAI chat remains in `OpenAICompatible.swift` with the upstream request
  transform for nested `moonshotai` provider options,
  `thinking.budgetTokens`, `reasoningHistory`, and Moonshot usage conversion
  when responses omit `total_tokens`.

- `Sources/ai-sdk-port/Models/AudioProviderModels.swift`
  Provider-shaped audio implementations. Deepgram uses raw `/v1/listen` audio
  upload and `/v1/speak` binary TTS with upstream camelCase-to-query mappings
  for transcription and speech media options, unwraps nested `deepgram`
  provider options, and preserves upstream speech output-format cleanup when
  provider options change encoding/container/sample-rate combinations;
  AssemblyAI, Rev.ai, and Gladia implement
  upload/submit/poll transcription job lifecycles, unwrap nested
  `assemblyai`/`revai`/`gladia` provider options, with AssemblyAI and Gladia
  provider options mapped from upstream camelCase names into API snake_case;
  LMNT unwraps nested `lmnt` options and maps `sampleRate`/`topP` speech
  options, Hume unwraps nested `hume` options and maps `context`, `speed`, and
  utterance description fields, and ElevenLabs
  uses its binary speech endpoint with nested `elevenlabs` provider options,
  merged `speed`/`voiceSettings`, pronunciation locators, context text/request
  IDs, normalization settings, `enableLogging`, and output-format aliases;
  ElevenLabs also maps multipart `/v1/speech-to-text` including nested
  transcription options. Fal speech unwraps nested `fal` provider options,
  posts to `https://fal.run/{modelID}`, and downloads the returned audio URL;
  Fal transcription unwraps nested `fal` options, queues the base64 audio at
  `https://queue.fal.run/fal-ai/{modelID}`, and polls the request endpoint.

- `Sources/ai-sdk-port/Models/MediaProviderModels.swift`
  Provider-shaped image/video implementations. Replicate uses model prediction
  endpoints, keeps wait/polling options client-side (`prefer: wait=N`,
  `pollIntervalMs`, `pollTimeoutMs`), downloads image outputs into returned
  bytes/base64, maps image edit `files`/`mask` into URL/data-URI inputs,
  supports Flux-2 `input_image` / `input_image_N` reference inputs, unwraps
  nested `replicate` provider options, and uses prediction polling for video
  with upstream fields such as `resolution -> size`, `fps`, `seed`, image
  input, `guidance_scale`, SVD-specific options, and MiniMax
  `prompt_optimizer`; Fal uses direct run image calls with upstream option
  mapping, maps image edit `files`/`mask` to `image_url`/`image_urls` and
  `mask_url`, unwraps nested `fal` provider options, supports both `images`
  and single `image` responses, downloads generated image/audio URLs without
  leaking provider authorization, and uses queue/response-url video calls with
  client-side polling options plus upstream fields such as image input, `loop`,
  `motionStrength`, `resolution`, `negativePrompt`, and `promptOptimizer`;
  Black Forest Labs follows upstream
  `black-forest-labs-image-model.ts`: size is reduced to `aspect_ratio` and
  dimensions are forwarded as `width`/`height`, camelCase provider options are
  mapped to API fields, nested `blackForestLabs` provider options are
  unwrapped, `files` and `mask` are converted to BFL input image fields
  (`image` for fill models, `input_image` otherwise), polling options stay
  client-side, and the generated sample URL is downloaded into returned image
  bytes/base64. KlingAI follows upstream `klingai-video-model.ts`: detect
  T2V/I2V/motion-control from the model suffix, map nested `klingai` options
  into the API's snake_case fields, keep `pollIntervalMs`/`pollTimeoutMs`
  client-side, require `videoUrl`/`characterOrientation`/`mode` for
  motion-control, and support I2V/motion image reference fields through Swift
  `extraBody` because the local `VideoGenerationRequest` has no standard
  image slot yet. ByteDance follows upstream `bytedance-video-model.ts`:
  nested `bytedance` options are unwrapped, prompt/image/reference
  image/video/audio inputs are written to the multimodal `content` array with
  upstream roles, resolution strings are normalized to ByteDance's
  `480p`/`720p`/`1080p` buckets, and polling options stay client-side.
  Alibaba video follows upstream `alibaba-video-model.ts`: nested `alibaba`
  options are unwrapped, T2V/I2V/R2V modes are derived from the model ID,
  I2V `image`/`imageUrl` becomes `input.img_url`, R2V `referenceUrls` becomes
  `input.reference_urls`, resolution maps to I2V `resolution` or T2V/R2V
  `size`, and polling options stay client-side. Luma follows upstream
  `luma-image-model.ts`: submit/poll to
  `/dream-machine/v1/generations/image`, keep polling options client-side,
  unwrap nested `luma` provider options, map URL-based `files` or legacy
  `images` configs into current `image` / `style` / `character` /
  `modify_image` reference request fields, reject mask/base64 editing inputs
  like upstream, and download the final asset URL into returned bytes/base64.
  KlingAI and ByteDance implement video
  task/poll lifecycles; Prodia uses multipart job responses for language,
  image, and video with nested `prodia` provider options normalized to
  upstream job config fields; Alibaba uses DashScope native async video tasks
  alongside the native chat model in `AlibabaModels.swift`. Luma is image-only,
  matching upstream.

- `Sources/ai-sdk-port/Providers/VercelProvider.swift`
  Vercel v0 provider wrapper. Follow upstream
  `packages/vercel/src/vercel-provider.ts`: public provider ID remains
  `vercel`, only language/chat models are exposed, the model implementation is
  the shared OpenAI-compatible chat path with provider ID `vercel.chat`, base
  URL `https://api.v0.dev/v1`, and API-key loading from `VERCEL_API_KEY`.

- `Sources/ai-sdk-port/Models/GatewayModels.swift`
  Vercel AI Gateway model endpoints. These intentionally do not use
  OpenAI-compatible paths; upstream sends to `/language-model`,
  `/embedding-model`, `/image-model`, `/video-model`, `/reranking-model`,
  `/speech-model`, and `/transcription-model` with `ai-*-model-id` headers.
  Language requests now mirror more of upstream `gateway-language-model.ts`:
  Swift file content becomes V4 `file` parts with `data.type` set to `url` or
  `data`, Swift function tools become V4 `{ type: "function", inputSchema }`
  entries, provider-defined `gateway.*` tools are passed through as
  `{ type: "provider", id, name, args }`, and `toolChoice` is normalized to V4
  object form. Generate responses accept V4 `content` as either a single object
  or an array, including `tool-call` and `source` parts, while streams parse
  standard V4 `text-delta`, `reasoning-delta`, `source`, `tool-input-*`, and
  `tool-call` chunks into Swift stream parts. Image requests follow
  `gateway-image-model.ts` for `files` and `mask`: inline Swift `Data` is
  base64-encoded into `{ type: "file", mediaType, data }`, URL inputs become
  `{ type: "url", url }`, and `providerOptions`/routing options remain in the
  body. Embeddings map upstream `usage.tokens` onto `TokenUsage.totalTokens`.
  Video generation follows the Gateway SSE contract closely enough to surface
  `{ type: "error", message, statusCode }` events as thrown HTTP errors instead
  of silently returning an empty video result. Provider management methods now
  mirror upstream `getAvailableModels`, `getCredits`, `getSpendReport`, and
  `getGenerationInfo`, using `/config`, origin-level `/v1/credits`,
  `/v1/report`, and `/v1/generation` endpoints with snake_case query/response
  mapping. `GatewayTools.perplexitySearch` and
  `GatewayTools.parallelSearch` mirror upstream `gateway.tools` helpers by
  building provider-executed `gateway.perplexity_search` and
  `gateway.parallel_search` tool declarations with upstream-compatible
  camelCase argument keys.

- `Sources/ai-sdk-port/Models/LanguageStreamParsing.swift`
  Shared streaming chunk parsing for Anthropic SSE, Google/Vertex
  `streamGenerateContent?alt=sse`, Gateway JSON SSE, and Bedrock AWS
  EventStream frames.

- `Sources/ai-sdk-port/Providers/OpenAICompatibleProvider.swift`
  Provider implementation classes, auth header construction, Anthropic/Google/
  Azure special provider wiring. Azure mirrors upstream's
  `createAzure`: default `languageModel`/callable behavior uses the Responses
  API at `{baseURL}/v1/responses?api-version=...`, `chatModel` explicitly uses
  `/v1/chat/completions`, and `useDeploymentBasedURLs` switches model calls to
  `{baseURL}/deployments/{deploymentId}{path}?api-version=...` for legacy
  deployment-based flows. Azure Responses and Completions preserve upstream's
  provider-option namespace behavior: nested `azure` options are preferred over
  nested `openai` where upstream's OpenAI provider does the same. Azure
  image/speech/transcription reuse the OpenAI media option mapping in
  `OpenAICompatible.swift`. `AzureOpenAITools` mirrors the hosted tool subset
  exported by upstream `azureOpenaiTools`.

- `Sources/ai-sdk-port/Providers/GatewayProvider.swift`
  Gateway auth/team headers plus metadata/management helpers for available
  models, credits, spend reports, and generation lookups.

- `Sources/ai-sdk-port/Providers/AmazonBedrockProvider.swift`
  Bedrock provider wiring, bearer-token fallback, AWS credential loading, and
  SigV4 request signing. Compare with upstream
  `amazon-bedrock-provider.ts` and `amazon-bedrock-sigv4-fetch.ts`.

- `Sources/ai-sdk-port/Models/AmazonBedrockModels.swift`
  Bedrock Runtime model implementations: Converse for language models,
  InvokeModel for embeddings/images, and Agent Runtime reranking. Converse
  request conversion maps Swift `data` parts to upstream Bedrock image/document
  blocks by MIME type, treats non-image data as `document` with generated
  `document-N` names, applies `amazonBedrock`/`bedrock.citations.enabled` to
  document citation config, and forwards provider options such as
  `guardrailConfig`, `serviceTier`, and `additionalModelRequestFields` without
  leaking provider namespaces into the request body. Converse response parsing
  follows `amazon-bedrock-chat-language-model.ts` for basic tool-use surfaces:
  non-streaming `toolUse` blocks populate
  `TextGenerationResult.toolCalls`, streaming `contentBlockStart` /
  `contentBlockDelta.delta.toolUse.input` / `contentBlockStop` events emit
  tool-call delta/final stream parts, and Bedrock stop reasons normalize
  (`tool_use -> tool-calls`, `end_turn` / `stop_sequence -> stop`,
  guardrail/content filtering -> `content-filter`). Bedrock
  `reasoningContent.reasoningText` now fills `TextGenerationResult.reasoning`
  and stream `reasoningDelta`; reasoning signatures/redacted data plus
  `trace`, `performanceConfig`, `serviceTier`, stop sequence, and cache usage
  metadata map to `providerMetadata.amazonBedrock` / `providerMetadata.bedrock`
  or streaming `LanguageStreamPart.metadata`, following upstream provider
  metadata aliases. Bedrock image generation follows
  `amazon-bedrock-image-model.ts` for Nova Canvas text/image edit requests:
  `negativeText`, `style`, `quality`, `cfgScale`, and `seed` map into the
  appropriate Bedrock params/config, while `files`/`mask` plus `taskType` or
  `maskPrompt` produce `INPAINTING`, `OUTPAINTING`, `BACKGROUND_REMOVAL`, or
  `IMAGE_VARIATION` request bodies.

- `Sources/ai-sdk-port/Providers/GoogleVertexProvider.swift`
  Vertex provider wiring: express API key mode, OAuth bearer mode, service
  account JWT exchange, and project/location base URL construction. It also
  exposes upstream's OpenAI-compatible Vertex MaaS and Vertex xAI partner-model
  endpoints through `AIProviders.googleVertexMaaS` and
  `AIProviders.googleVertexXAI`; both use
  `/v1/projects/{project}/locations/{location}/endpoints/openapi`, while the xAI
  wrapper strips `reasoning_effort` like upstream. It also exposes
  `AIProviders.googleVertexAnthropic`, reusing the Anthropic Messages model but
  targeting `publishers/anthropic/models/{model}:rawPredict` and adding
  `anthropic_version: vertex-2023-10-16` to the request body. Compare
  with upstream `google-vertex-provider.ts`, `google-vertex-provider-base.ts`,
  `maas/google-vertex-maas-provider.ts`,
  `xai/google-vertex-xai-provider.ts`,
  `anthropic/google-vertex-anthropic-provider.ts`, and
  `edge/google-vertex-auth-edge.ts`.

- `Sources/ai-sdk-port/Models/GoogleVertexModels.swift`
  Vertex model paths: Gemini `:generateContent`, embeddings/images `:predict`,
  and video `:predictLongRunning`. Gemini language responses reuse the shared
  Google `functionCall` / `partialArgs` tool-call parser, upstream
  finish-reason normalization, and shared `google-prepare-tools.ts`
  request-side function/provider tool mapping through
  `Models/GoogleTools.swift`. It also reuses the shared Google grounding
  source extractor for `TextGenerationResult.sources` and stream source parts.
  Imagen generation mirrors upstream
  `google-vertex-image-model.ts`, including nested `googleVertex` / legacy
  `vertex` provider options, direct `negativePrompt` / safety / watermark
  parameters, and edit mode via `ImageGenerationRequest.files` plus optional
  `mask`. URL-based edit images are rejected before HTTP like upstream because
  Vertex edit requires bytes.

- `Sources/ai-sdk-port/Models/FileClients.swift`
  File upload clients. OpenAI-compatible providers use multipart `/files`
  uploads, Anthropic adds the files beta header, and Google uses the Gemini
  resumable upload start/upload/poll flow.

- `Sources/ai-sdk-port/Models/OpenAISkills.swift`
  Skills upload clients. Mirrors upstream `OpenAISkills.uploadSkill` and
  `AnthropicSkills.uploadSkill`: multipart `files[]` upload to `/skills`,
  provider references, version metadata, OpenAI's unsupported `displayTitle`
  warning, and Anthropic's `display_title` field plus skills beta header and
  version metadata fetch.

- `Sources/ai-sdk-port/Providers/ProviderRegistry.swift`
  Public factory surface mirroring `createX()` / default provider exports from
  npm packages. Add new provider packages here first.

- `Tests/ai-sdk-portTests/ai_sdk_portTests.swift`
  Focused request-shape tests. Every provider-specific upstream change should
  get at least one request URL/header/body test before deeper integration tests.

## Porting Checklist

1. Refresh npm provider list and compare with `AIProviders`.
2. Pull/fetch `vercel/ai` and record the commit hash in this document.
3. For a provider change, port auth/base URL/model factory changes into
   `ProviderRegistry.swift` or the provider class.
4. Port request conversion and response parsing into the matching model file.
5. Add tests that assert URL, auth headers, JSON body, parsed text/media, and
   usage metadata.
6. Run:

   ```sh
   swift build
   swift test
   ```

## Known Gaps To Close Next

This pass establishes the broad provider registry and real request execution for
OpenAI-compatible, Anthropic, Google, embeddings, image, transcription, speech,
OpenAI-compatible SSE streaming, OpenAI/Groq-style multipart transcription,
upstream-style provider factory aliases,
Gateway model endpoint paths, Bedrock SigV4/Converse/InvokeModel request paths,
Bedrock Converse image/document request conversion and document citation config,
Bedrock Converse tool-use/reasoning/provider-metadata parsing for
generate/stream paths, Bedrock Nova Canvas image option/edit-mode mapping,
Google Vertex auth/base URL/model request paths, Vertex MaaS/xAI partner-model
OpenAI-compatible endpoints, Vertex Anthropic `rawPredict`, file uploads for
OpenAI/xAI-compatible, Anthropic, Google, and Gateway providers, and streaming
text/reasoning/source/tool-call/finish deltas for Anthropic, Google, Vertex,
Gateway, and Bedrock.
Anthropic fidelity now includes provider-option request mapping, PDF/text
document content blocks, function tool schema forwarding, upstream
`AnthropicTools` provider-defined tool builders with beta-header propagation,
the supported `GoogleVertexAnthropicTools` subset, extended-thinking request
rules, reasoning stream deltas, tool-use/server-tool parsing, citation source
extraction for generate/stream paths, web-search result sources, upstream
stop-reason normalization, `messages` factory alias coverage, and Skills upload with `display_title`,
`anthropic-beta: skills-2025-10-02`, and latest-version metadata fetch.
Google Generative AI fidelity now includes native Gemini function/provider tool
request mapping plus `GoogleTools` / `GoogleVertexTools` helper coverage,
`toolChoice` -> `toolConfig` mapping, function-call parsing for generate/stream
paths, grounding source extraction for web/RAG/file-search/maps/image chunks,
native Imagen image generation and edit requests,
Gemini image-generation via `generateContent`, and Veo
long-running video operation polling. Google Vertex Gemini uses the same
request-side tool mapper and grounding source extraction. Google Interactions fidelity now includes
model and agent factories, request conversion, API revision headers, basic
polling, usage parsing, function-call generate/stream parsing, and text/finish
streaming, source extraction from annotations/built-in tool results, and
interaction id/service-tier provider metadata.
OpenAI fidelity now defaults language models to `/responses`, keeps explicit
chat-completions via `chatModel` / `chat`, maps chat-compatible function tools and
`tool_choice`, maps multimodal Responses input parts and common Responses
provider options, normalizes Responses finish reasons in generate and stream
paths, streams Responses text/reasoning/finish events, and maps Responses
function/provider tools into upstream hosted tool request shapes. `OpenAITools`
now covers upstream `openai.tools` hosted-tool builders. OpenAI and Azure alias
fidelity now includes `completion` and `responses` endpoint routing.
OpenAI-compatible fidelity now includes native completion SSE streaming and
`includeUsage` request mapping for chat/completion stream calls, plus
`queryParams` URL mapping and structured-output `responseFormat` mapping for
custom OpenAI-compatible providers. Custom chat request-body transforms are
also supported for proxy-style OpenAI-compatible providers, and nested
provider-option namespaces are unwrapped with upstream raw/camelCase
precedence. Custom OpenAI-compatible image generation now forces upstream's
`b64_json` response format and enforces the 10-image call limit, while
OpenAI/Azure image models use upstream's model-specific 1-or-10 image limits.
Shared OpenAI-compatible embeddings enforce upstream's 2048-value default batch
limit and custom override before sending HTTP requests.
OpenAI media fidelity now maps image/transcription provider options, supports
multipart image edits, and uses upstream speech defaults.
OpenAI Skills fidelity now includes multipart `files[]` upload to `/skills`,
provider-reference/metadata response mapping, and the upstream unsupported
`displayTitle` warning.
Gateway fidelity now includes provider management methods for available
models, credits, spend reports, and generation info, including origin-level
management URLs and snake_case-to-Swift response mapping. Gateway tool helper
fidelity now includes Swift builders for upstream `gateway.tools.parallelSearch`
and `gateway.tools.perplexitySearch`.
Vercel provider fidelity now uses a dedicated wrapper so language models report
`vercel.chat` like upstream, while unsupported model families throw with the
public `vercel` provider ID.
Anthropic AWS fidelity now covers the Claude Platform on AWS provider wrapper,
workspace header, API-key auth, and SigV4 signing over the existing Anthropic
Messages implementation.
Azure fidelity now follows upstream v1 Responses defaults, explicit chat
completions, custom API-version query handling, deployment-based URL mode, and
OpenAI-backed media option mapping. Azure Responses prefer nested `azure`
provider options with fallback to nested `openai`, and Azure Completions expose
the completion model surface while merging nested `openai` then `azure`
provider options. Azure hosted-tool fidelity now includes the upstream
`azureOpenaiTools` subset through `AzureOpenAITools`.
Native Cohere fidelity now includes chat, chat SSE, response-side tool calls,
file-to-document RAG extraction, citation sources, embeddings, reranking, and
nested `cohere` provider options;
native Voyage fidelity now includes embeddings, reranking, and nested `voyage`
provider options.
Native Mistral fidelity now includes chat, chat SSE text/reasoning chunks, PDF/
image content parts, tool/tool-choice request mapping, upstream finish-reason
normalization, embeddings, and nested `mistral` provider options.
Native TogetherAI fidelity now includes image generation option normalization
and reranking, including nested `togetherai` provider options, in addition to
the OpenAI-compatible chat/completion/embedding paths.
Native QuiverAI fidelity now includes SVG generation/vectorization with
upstream option mapping and reference-image limits.
xAI fidelity now defaults language calls to `/responses` and includes native
image/video request lifecycles, image-edit inputs, nested image/video provider
options, reference-to-video mapping, plus `/files` upload through the shared
file client.
DeepInfra fidelity now includes native image generation and multipart image
edit mode, with nested `deepinfra` provider options, in addition to
OpenAI-compatible chat/completion/embedding paths.
Fireworks fidelity now includes native binary/workflow/async-workflow image
generation, nested `fireworks` provider options, input-image mapping for
Kontext/edit-style workflows, plus chat request transforms for
thinking/reasoning options.
HuggingFace fidelity now uses a dedicated provider wrapper and native upstream
Responses model, including `huggingface.responses` model IDs, request input
conversion, nested provider options, annotation sources, reasoning
output/streaming, and function/MCP output items.
Open Responses compatibility now sends Responses-shaped input to the exact
configured POST endpoint instead of falling back through chat-completions
conversion.
OpenAI/Azure fidelity now includes nested `openai` provider-option unwrapping
for OpenAI-backed chat, Responses, completions, embeddings, image
generation/editing, speech, and transcription paths.
Perplexity fidelity now includes native message conversion for text/image/PDF
parts, citations mapped onto `AISource` for generate and stream paths,
citation/image/search/cost metadata retention, and streaming usage propagation.
Baseten fidelity now uses Bearer auth, keeps chat on the Model APIs, and
requires a dedicated `/sync` or `/sync/v1` model URL for embeddings.
Groq fidelity now includes native chat option mapping, nested `groq`
provider-option unwrapping, streaming reasoning deltas with `x_groq` usage
propagation, upstream `groq.tools.browserSearch()` helper coverage, and
transcription provider option multipart mapping.
DeepSeek fidelity now includes native reasoning streams, stream usage options,
DeepSeek V4 assistant reasoning placeholders, reasoning-effort mapping, and
response-side tool calls for generate and stream paths, including explicit
`chatModel` routing to the native DeepSeek model.
Cerebras fidelity now includes assistant reasoning-history request transforms,
standard structured `responseFormat` mapping, streaming reasoning deltas,
response-side tool calls, and structured-output tool-call repeat
suppression/finish normalization, including explicit `chatModel` routing to
the native Cerebras model.
MoonshotAI fidelity now includes the upstream nested provider-option
unwrapping, thinking/reasoning-history request transform, and usage conversion
for responses that omit `total_tokens`.
Audio provider fidelity now includes Deepgram transcription/speech with nested
provider-option unwrapping and speech media-query cleanup,
AssemblyAI/Rev.ai/Gladia transcription job lifecycles plus nested provider
option unwrapping, and LMNT/Hume speech nested provider options and
generation endpoints. ElevenLabs fidelity now includes native speech and
transcription with nested `elevenlabs` option mapping; Fal fidelity now includes
native speech and queued transcription with nested `fal` option unwrapping.
ElevenLabs registry surface intentionally does not advertise language or
embedding models, matching upstream `elevenlabs-provider.ts`; if npm's short
description says otherwise, treat the provider source as authoritative.
Image/video provider fidelity now includes Replicate image/video, Fal
image/video, Black Forest Labs image request option mapping plus binary result
download, Luma image request/reference option mapping plus binary result
download, KlingAI video, ByteDance video, Alibaba chat/video, and Prodia
language/image/video request lifecycles. Replicate now includes image edit
inputs, Flux-2 multi-image references, nested provider options, and video
provider-option normalization. Fal now includes image edit inputs, multi-image
edit mode, nested provider options, and video provider-option normalization.
BFL now includes upstream `files`/`mask` image input mapping, nested
`blackForestLabs` provider options, size-to-dimensions forwarding, fill-model
`image` field handling, and input image count validation.
KlingAI now includes nested provider options, upstream T2V/I2V/motion-control
field mapping, motion-control validation, I2V/motion reference image mapping,
and client-side polling overrides.
ByteDance now includes nested provider options, reference media content roles,
resolution normalization, service-tier/draft/audio/camera option mapping, and
client-side polling overrides.
Alibaba video now includes nested provider options, upstream T2V/I2V/R2V input
mapping, resolution/seed/audio/watermark parameters, and client-side polling
overrides.
Prodia language/image/video now unwrap nested provider options and map only
upstream-supported job config fields such as language `aspectRatio`, image
`stylePreset`/`loras`/`progressive`, and video `resolution`/`seed`.
Luma now includes current reference-field names, `files`-based URL references,
nested provider options, and upstream edit-input validation.
Alibaba chat fidelity now includes response-side tool calls for generate and
stream paths, including fragmented streaming arguments and upstream
`tool-calls` finish normalization.

The next fidelity pass should connect remaining provider-specific image/video
options, provider file-management methods beyond upload if upstream expands that
surface, and the remaining provider-specific request options from each upstream
test suite.
