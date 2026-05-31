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
- `ProviderCapabilityMatrix.swift`: machine-readable provider/package
  capability coverage.
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

### 1. AI SDK facade layer is still partial

Upstream `packages/ai/src/index.ts` exports product-level APIs:

```text
generateText, streamText, generateObject, streamObject, embed, embedMany,
generateImage, experimental_generateVideo, experimental_generateSpeech,
experimental_transcribe, rerank, uploadFile, uploadSkill, customProvider,
middleware wrappers, prompt conversion, telemetry, UI streams, agents
```

The Swift package now has an `AI` facade for the common calls, but deeper
product behavior still trails upstream.

Impact:

- Facade calls now have a retry policy for transient errors, but richer
  cancellation/timeout surfaces, telemetry hooks, and warning logging still need
  follow-up work.
- Tool execution exists for `generateText`, but stop conditions, approval flow,
  dynamic tools, stream-side tool execution, and provider-defined tool wrapping
  still need follow-up work.
- Object generation exists for `Decodable` results, and `streamObject` can now
  stream JSON text deltas, best-effort partial JSON objects, and a final decoded
  object. Typed partials, richer schema adapters, typed validation errors, and
  advanced output strategies still need follow-up work.

Recommendation:

Continue growing the `AI` facade above provider models: cancellation,
timeouts, telemetry, stream-side tool execution, richer schema/object
generation, and middleware should be separate product rounds.

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
Generic low-level provider requests can still pass raw JSON tools through
`LanguageModelRequest.tools`, but the facade now also exposes typed executable
tools.

Impact:

- `dynamicTool(...)`, typed input/output validation, approval flow, and
  stop-condition policies are still missing.
- Automatic multi-step execution exists for `AI.generateText`, but not yet for
  `AI.streamText`.
- Tool-result messages are now first-class in core, but provider passes should
  keep tightening wire-format parity.

Recommendation:

Build on the new `AITool` abstraction: add dynamic tools, validation hooks,
approval requests, stop conditions, and stream-side execution. Keep
provider-defined tools as specialized `AITool` values instead of plain JSON
where possible.

### 4. Object generation and schema validation are partial

Upstream has `generateObject`, `streamObject`, schema adapters, JSON repair, and
object output strategies. Swift now has `AI.generateObject` for `Decodable`
types and `AI.streamObject` for streaming text deltas, partial `JSONValue`
objects, and a final decoded object, backed by provider JSON response-format
hints.

Impact:

- Basic object generation, partial JSON object streaming, and final-object
  streaming are available at product level.
- Typed partial object streams, array/enum/no-schema output strategies, schema
  adapter protocols, and typed validation error surfaces are still unavailable.
- Provider-specific schema support has first end-to-end coverage, but needs
  broader provider passes.

Recommendation:

Extend object generation beyond the first Swift-native slices: add typed partial
object streams, schema adapter protocols, richer validation errors,
array/enum/no-schema strategies, and JSON instruction injection for providers
without native response formats.

### 5. Product reality is not fully gated yet

The README, upstream sync guide, and provider capability matrix now make the
current product shape visible, but the verification gates are still uneven.

Impact:

- Provider breadth is visible through `AIProviderCapabilities`, but matrix rows
  still depend on humans updating the static source when a provider pass changes.
- Mock transport tests prove wire shape, but live provider health is only covered
  by an opt-in smoke suite for representative first-party providers.
- A user can start from the README, but there is not yet a generated matrix or
  per-provider cookbook.

Recommendation:

Keep turning documentation into executable product evidence:

- generate the markdown capability matrix from `AIProviderCapabilities`;
- expand live smoke coverage by provider family without making it default CI;
- add per-provider quick-start snippets only where the SDK surface differs;
- keep `UpstreamSync.md` as a short manifest/checklist, with detailed evidence
  in the matrix and tests.

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
   First slice is in place, including upload-file and upload-skill wrappers.
   Follow-up work should add richer result objects, cancellation/timeout
   behavior, and streaming orchestration.

3. **Facade pass 2: retries and cancellation.**
   First retry slice is in place with `AIRetryPolicy` and default
   `maxRetries: 2` for product-level calls. Next passes should add request
   timeouts, richer cancellation controls, retry-after header support, and
   streaming retry behavior.

4. **Tool loop pass.**
   First `generateText` slice is in place with typed `AITool`, execute
   callbacks, step results, and tool-result messages. Next passes should add
   validation, dynamic tools, approval/stop-condition policies, provider-defined
   tool wrappers, and stream-side tool execution.

5. **Object generation pass.**
   First `AI.generateObject` slice is in place for `Decodable` plus JSON
   schema hints and repair callbacks. `AI.streamObject` now emits text deltas,
   best-effort partial `JSONValue` objects, and final `Decodable` output. Next
   passes should add typed partials, schema adapter protocols, richer validation
   errors, and array/enum/no-schema strategies.

6. **README and capability matrix.**
   README now has a quick-start and facade/tool/object examples. A first
   machine-readable provider capability matrix and opt-in live smoke harness are
   in place. Next pass should generate the markdown table from source and add
   deeper provider-option examples.

Provider micro-parity should continue, but it should be the second track. The
first track should now be the SDK facade and core contract, because those change
what provider behavior can even be represented.
