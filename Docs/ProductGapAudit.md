# Product Gap Audit

Snapshot date: 2026-05-31
Upstream commit: `ab6d66482d31afe15f4973a51c5f7cfa09c92ea6`

This audit looks at the package from the top down. The provider ports are broad,
but the product is not yet equivalent to the AI SDK experience because the
Swift package mostly exposes low-level provider models.

## Current Shape

The Swift package is a library-only SwiftPM package with one product,
`ai-sdk-port`. Public APIs are concentrated in:

- `Core.swift`: model protocols, request/result structs, stream parts, warnings.
- `ProviderRegistry.swift`: provider factories.
- `Models/*`: provider-specific request/response implementations.
- `Docs/UpstreamSync.md`: provider sync playbook.

The provider registry has broad coverage of official provider packages from the
upstream repository:

```text
alibaba, amazon-bedrock, anthropic, anthropic-aws, assemblyai, azure, baseten,
black-forest-labs, bytedance, cerebras, cohere, deepgram, deepinfra, deepseek,
elevenlabs, fal, fireworks, gateway, gladia, google, google-vertex, groq,
huggingface, hume, klingai, lmnt, luma, mistral, moonshotai, open-responses,
openai, openai-compatible, perplexity, prodia, quiverai, replicate, revai,
togetherai, vercel, voyage, xai
```

That means the biggest missing work is no longer "add the next provider". The
larger gaps are in the SDK layer above providers and in the fidelity of the core
protocol contract.

## Serious Gaps

### 1. No AI SDK facade layer

Upstream `packages/ai/src/index.ts` exports product-level APIs:

```text
generateText, streamText, generateObject, streamObject, embed, embedMany,
generateImage, experimental_generateVideo, experimental_generateSpeech,
experimental_transcribe, rerank, uploadFile, uploadSkill, customProvider,
middleware wrappers, prompt conversion, telemetry, UI streams, agents
```

The Swift package currently asks callers to directly get a provider model and
call methods such as `generate`, `stream`, `embed`, or `generateImage`.

Impact:

- No single Swift equivalent of `generateText` or `streamText`.
- No high-level retry policy, abort/cancellation surface, telemetry hooks, or
  warning logging.
- No automatic tool loop, step results, stop conditions, tool execution, or tool
  approval flow.
- No `embedMany` chunking helper above provider batch limits.
- No object-generation helper with JSON schema prompting and validation.

Recommendation:

Build a small `AI` facade module before doing more warning-level parity. Start
with `generateText`, `streamText`, `embed`, `embedMany`, `generateImage`,
`transcribe`, `generateSpeech`, `generateVideo`, and `rerank` wrappers that call
the existing models. Then add retries, step/tool loop, schema/object generation,
and telemetry in separate rounds.

### 2. Core model contract is lossy compared with upstream v4

Upstream provider v4 model contracts carry richer call options and richer
results. Examples:

- `LanguageModelV4CallOptions` includes `topK`, penalties, `seed`,
  `responseFormat`, `reasoning`, `includeRawChunks`, `abortSignal`, structured
  `providerOptions`, tool choice, and typed function/provider tools.
- `LanguageModelV4StreamPart` has block lifecycle events (`text-start`,
  `text-end`, reasoning start/end), tool input start/delta/end, tool result,
  tool approval requests, files, reasoning files, custom content,
  `stream-start` warnings, response metadata, finish provider metadata, raw
  chunks, and streamed errors.
- Image, speech, transcription, embedding, reranking, file, and skill results
  carry response metadata, provider metadata, warnings, usage, request bodies,
  headers, timestamps, and sometimes segment-level output.

The Swift contract keeps only a compact subset. For example:

- `LanguageModelRequest` has temperature, topP, maxOutputTokens, stopSequences,
  tools as raw `JSONValue`, `extraBody`, and headers.
- `LanguageStreamPart` has text/reasoning deltas, tool-call deltas/final calls,
  source, metadata, raw, and finish, but no stream-start warnings, response
  metadata event, tool input lifecycle, tool results, approval requests, files,
  streamed errors, or per-part provider metadata.
- `TranscriptionResult` only returns text and raw JSON; upstream has segments,
  language, duration, warnings, request/response info, and provider metadata.
- `SpeechResult`, `VideoGenerationResult`, `RerankingResult`, and
  `FileUploadResult` expose much less provider metadata than upstream.

Impact:

- Some provider behavior cannot be faithfully ported without inventing ad hoc
  side channels.
- Stream parity is capped even when provider implementations parse richer data.
- More warning work will continue to leak into special cases unless result
  shapes consistently support upstream result fields.

Recommendation:

Introduce v4-shaped Swift core structs before expanding deeper provider parity:

- richer request options (`topK`, penalties, seed, response format, reasoning,
  providerOptions, abort/cancellation);
- richer stream parts with start/end, response metadata, stream-start warnings,
  tool results/approval, file/custom/error parts, and provider metadata;
- shared response metadata and provider metadata on every result type;
- warnings on every result type that upstream can warn from.

Progress:

- First contract slice added: language requests now carry v4-style sampling,
  response-format, reasoning, raw-chunk, tool-choice, and provider-options
  fields; every model request has a `providerOptions` slot; result types now
  carry shared warnings/provider metadata/response metadata where upstream v4 can
  report them; language streams can represent lifecycle parts, stream-start
  warnings, tool results, tool approval requests, files, custom parts, response
  metadata, and streamed errors. Provider implementations still need follow-up
  passes to populate these fields consistently.

### 3. Tool execution is represented as JSON, not as a Swift product surface

Provider-defined tools exist as builders such as `OpenAITools`,
`AnthropicTools`, `GoogleTools`, `GatewayTools`, `GroqTools`, and `XAITools`.
Generic tools, however, are still raw JSON in `LanguageModelRequest.tools`.

Impact:

- No typed Swift equivalent of upstream `tool(...)`, `dynamicTool(...)`,
  tool input/output validation, or `execute` callbacks.
- No automatic multi-step loop like upstream `generateText`/`streamText`.
- Provider tool calls can be parsed, but user tool results are not a first-class
  conversation primitive.

Recommendation:

Add a Swift `AITool` abstraction and a tool execution pipeline after the facade
exists. Keep provider-defined tools as specialized `AITool` values instead of
plain JSON where possible.

### 4. Object generation and schema validation are missing

Upstream has `generateObject`, `streamObject`, schema adapters, JSON repair, and
object output strategies. Swift currently has raw JSON response-format support
in some provider request builders, but no user-facing object-generation API.

Impact:

- A major AI SDK use case is unavailable even when providers support structured
  outputs.
- Provider-specific schema support cannot be tested end-to-end at product level.

Recommendation:

After `generateText`, add `generateObject` around Swift `Codable` and JSON
Schema. Keep a first pass simple: generate JSON text, decode `Decodable`, return
raw text and validation errors. Add streaming object support later.

### 5. Documentation and product entrypoint are too thin

`README.md` is effectively empty. `UpstreamSync.md` is useful for maintainers,
but it is not a product guide.

Impact:

- A user cannot tell how to install, configure, or call the package.
- Provider coverage looks impressive in tests, but there is no public capability
  matrix or quick-start.

Recommendation:

Add a real README once the facade direction is chosen. It should include:

- install/import;
- provider setup examples;
- `generateText`, streaming, embeddings, images, transcription, speech, video,
  reranking;
- provider options;
- file and skill upload examples;
- a generated provider capability matrix.

## Recommended Next Rounds

1. **Core v4 result/stream contract pass.**
   First slice is in place. Continue wiring providers into the richer fields and
   add missing request/result details where upstream tests prove concrete
   behavior.

2. **Facade pass 1: direct wrappers.**
   Add `AI.generateText`, `AI.streamText`, `AI.embed`, `AI.embedMany`,
   `AI.generateImage`, `AI.transcribe`, `AI.generateSpeech`,
   `AI.generateVideo`, and `AI.rerank` as thin wrappers over existing model
   protocols.

3. **Facade pass 2: retries and cancellation.**
   Port upstream retry semantics and add Swift cancellation/timeout behavior.

4. **Tool loop pass.**
   Add typed tools, tool execution callbacks, step results, stop conditions, and
   tool-result messages.

5. **Object generation pass.**
   Add `generateObject` for `Decodable` plus JSON schema/repair strategy.

6. **README and capability matrix.**
   Turn the package from a provider implementation dump into something a user can
   evaluate and adopt.

Provider micro-parity should continue, but it should be the second track. The
first track should now be the SDK facade and core contract, because those change
what provider behavior can even be represented.
