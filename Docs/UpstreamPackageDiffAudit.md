# Upstream Package Diff Audit

Snapshot date: 2026-08-17

This audit records the published npm tarball comparison used by the weekly
SwiftAISDK upstream check. Every tracked package was packed at both the prior
ledger version and the current npm `latest` version, then reviewed separately.

Status meanings:

- `ported`: portable runtime behavior and focused Swift coverage changed.
- `covered`: the published change is already represented by the current Swift
  architecture, or only expands string model IDs accepted by Swift.
- `deferred`: the package adds a product surface that needs a shared public
  Swift design before provider-specific code is useful.
- `version-only`: published source behavior is unchanged apart from dependency,
  build, changelog, or version propagation.

## 2026-08-17 Tracked Package Results

Fresh npm metadata reported 47 changed rows among the 48 tracked packages;
`@ai-sdk/provider@4.0.7` was unchanged. The old and current published tarballs
for every changed package were unpacked into a temporary workspace and reviewed
separately. Published packages omit test sources, so the repository test and
fixture delta from `74abcdfb6a41` through `86892f3f6b4d` was audited separately
in `Docs/FreshUpstreamTestDiffAudit.md`.

| Package | Previous | Current | Result |
| --- | ---: | ---: | --- |
| `ai` | `7.0.58` | `7.0.66` | `ported/covered/no-swift-action` — array output schemas preserve root `definitions` and `$defs`, and chat remains submitted through metadata-only start snapshots, including resumed snapshots that already contain parts. Reasoning part IDs, resume isolation, provider assignment without reranking, and cancellation semantics are already covered; declaration emit, React state cloning, and callback-promise propagation are JavaScript-specific. |
| `@ai-sdk/provider` | `4.0.7` | `4.0.7` | `covered` — unchanged on npm. |
| `@ai-sdk/provider-utils` | `5.0.25` | `5.0.27` | `covered/no-swift-action` — Swift's bounded reader preserves its original size-limit error independently of response cancellation, and importing SwiftAISDK does not depend on a JavaScript global `fetch`. |
| `@ai-sdk/react` | `4.0.61` | `4.0.69` | `no-swift-action` — `useChat`, `useCompletion`, and `useObject` render-store state changes have no SwiftUI/React hook analogue in this package. |
| `@ai-sdk/alibaba` | `2.0.29` | `2.0.32` | `ported` — replayed assistant messages omit historical reasoning from ordinary content while retaining the provider's dedicated reasoning field; reasoning-only assistant turns are omitted entirely. |
| `@ai-sdk/amazon-bedrock` | `5.0.50` | `5.0.57` | `version-only`; the published source delta is release/dependency propagation. |
| `@ai-sdk/anthropic` | `4.0.36` | `4.0.39` | `ported` — caller metadata is retained for client and server tools and web-search results, survives replay in later turns, maps aliased provider-tool names before choosing the wire result shape, and remains attached to streamed tool calls. |
| `@ai-sdk/anthropic-aws` | `2.0.28` | `2.0.31` | `covered/version-only` — package-local source is unchanged and the Swift provider inherits shared Anthropic replay behavior. |
| `@ai-sdk/assemblyai` | `3.0.25` | `3.0.27` | `version-only`. |
| `@ai-sdk/azure` | `4.0.37` | `4.0.43` | `covered/version-only` — package-local behavior is unchanged; shared Responses behavior is audited under `@ai-sdk/openai`. |
| `@ai-sdk/baseten` | `2.1.6` | `2.1.8` | `version-only`. |
| `@ai-sdk/black-forest-labs` | `2.0.26` | `2.0.28` | `version-only`. |
| `@ai-sdk/bytedance` | `2.0.27` | `2.0.29` | `version-only`. |
| `@ai-sdk/cartesia` | `3.0.20` | `3.0.22` | `version-only`. |
| `@ai-sdk/cerebras` | `3.0.28` | `3.0.30` | `covered` — current model-name unions and examples changed; Swift model IDs are forward-compatible strings. |
| `@ai-sdk/cohere` | `4.0.25` | `4.0.27` | `version-only`. |
| `@ai-sdk/deepgram` | `3.0.25` | `3.0.27` | `version-only`. |
| `@ai-sdk/deepinfra` | `3.0.28` | `3.0.30` | `version-only`. |
| `@ai-sdk/deepseek` | `3.0.26` | `3.0.28` | `version-only`. |
| `@ai-sdk/elevenlabs` | `3.0.26` | `3.0.28` | `version-only`. |
| `@ai-sdk/fal` | `3.0.26` | `3.0.28` | `version-only`. |
| `@ai-sdk/fireworks` | `3.0.30` | `3.0.32` | `version-only`. |
| `@ai-sdk/gateway` | `4.0.46` | `4.0.52` | `ported/covered` — `GatewayError.cause` exposes the normalized `AIAPICallError`, preserving nested structured bodies (including numbers beyond Swift `Int` range), status, headers, and raw failures; new Gemini 3.7 Flash and Grok 4.6/xhigh settings remain covered by string model IDs and provider-option pass-through. |
| `@ai-sdk/gladia` | `3.0.25` | `3.0.27` | `version-only`. |
| `@ai-sdk/google` | `4.0.39` | `4.0.44` | `ported/covered` — primitive JSON Schema enum/const values use Gemini's OpenAPI wire form with nullable/type validation, detailed Google error bodies remain available, forced strict/named tools use `ANY`, and strict automatic tools retain `VALIDATED`. Gemini 3.7 Flash is accepted by the existing string model surface. |
| `@ai-sdk/google-vertex` | `5.0.48` | `5.0.54` | `ported` — Chirp 3 HD Cloud Text-to-Speech is available through the Vertex speech factory, including endpoint, voice, audio, warnings, metadata, and strict successful-response validation; shared Google and Anthropic changes are inherited. |
| `@ai-sdk/groq` | `4.0.26` | `4.0.28` | `version-only`. |
| `@ai-sdk/huggingface` | `2.0.28` | `2.0.30` | `version-only`. |
| `@ai-sdk/hume` | `3.0.25` | `3.0.27` | `version-only`. |
| `@ai-sdk/klingai` | `4.0.27` | `4.0.29` | `version-only`. |
| `@ai-sdk/lmnt` | `3.0.25` | `3.0.27` | `version-only`. |
| `@ai-sdk/luma` | `3.0.26` | `3.0.28` | `version-only`. |
| `@ai-sdk/mcp` | `2.0.29` | `2.0.32` | `ported` — OAuth reads challenge and Protected Resource Metadata scopes, selects challenge scope first, rejects relative challenge metadata URLs, and forwards the selected value to authorization while preserving source compatibility for existing providers. |
| `@ai-sdk/minimax` | `3.0.12` | `3.0.15` | `version-only`. |
| `@ai-sdk/mistral` | `4.0.27` | `4.0.29` | `version-only`. |
| `@ai-sdk/moonshotai` | `3.0.31` | `3.0.35` | `ported` — the owned chat request converter supports video/data and `ms://` references, rejects unsupported audio/PDF input, maps preserved reasoning to `thinking.keep`, exposes current reasoning/cache/safety options, normalizes tool schemas for MFJS, and serializes text/JSON/content/denied tool outputs by their model-output semantics. |
| `@ai-sdk/open-responses` | `2.0.25` | `2.0.28` | `ported` — manual history preserves reasoning, item order, annotations, and part IDs; provider-native reasoning effort is mapped and unsupported provider-defined tools warn instead of disappearing. Successful-body provider errors retain their message/status semantics, reasoning-only output is accepted, missing output is descriptive, and summary deltas no longer duplicate reasoning text. |
| `@ai-sdk/openai` | `4.0.36` | `4.0.42` | `ported` — Responses supports explicit compaction triggers and reconstructs storage-disabled shell calls, keeps function calls paired with outputs across previous-response continuation, and avoids duplicate MCP approval references. |
| `@ai-sdk/openai-compatible` | `3.0.28` | `3.0.30` | `version-only` in the published package. Swift's unfiltered `JSONValue` usage payload already preserves provider-specific top-level and nested raw fields exercised by the newer repository fixture. |
| `@ai-sdk/perplexity` | `4.0.27` | `4.0.29` | `version-only`. |
| `@ai-sdk/prodia` | `2.0.26` | `2.0.28` | `version-only`. |
| `@ai-sdk/quiverai` | `2.0.25` | `2.0.27` | `version-only`. |
| `@ai-sdk/replicate` | `3.0.26` | `3.0.28` | `version-only`. |
| `@ai-sdk/revai` | `3.0.25` | `3.0.27` | `version-only`. |
| `@ai-sdk/togetherai` | `3.0.29` | `3.0.31` | `version-only`. |
| `@ai-sdk/vercel` | `3.0.28` | `3.0.30` | `version-only`. |
| `@ai-sdk/voyage` | `2.0.25` | `2.0.27` | `version-only`. |
| `@ai-sdk/xai` | `4.0.33` | `4.0.40` | `ported` — xAI adds the Responses image-generation tool with custom aliases, prompt/error results, and deduplicated progress/output-item streaming lifecycle; priority service-tier metadata; Grok 4.6 `xhigh`; model-gated reasoning effort and Responses reasoning summaries; Imagine Video 1.5/1080p and reference voices with terminal errors taking precedence over stale URLs; and nullish-safe timestamped speech/transcription options, pronunciation replacements, trace/usage metadata, and provider error decoding. |

### 2026-08-17 Registry Discovery

The exact npm registry prefix contains 81 live `@ai-sdk/*` packages; `npm
search --json` returns 65 and misses 16 exact-prefix names. Classification of
the unfiltered set yields 45 model-provider packages and 36 schema, UI,
tooling, harness, sandbox, workflow, or adapter packages.

Exact registry-prefix package list, sorted by package name:

```text
@ai-sdk/alibaba
@ai-sdk/amazon-bedrock
@ai-sdk/angular
@ai-sdk/anthropic
@ai-sdk/anthropic-aws
@ai-sdk/assemblyai
@ai-sdk/azure
@ai-sdk/baseten
@ai-sdk/black-forest-labs
@ai-sdk/bytedance
@ai-sdk/cartesia
@ai-sdk/cerebras
@ai-sdk/code-mode
@ai-sdk/codemod
@ai-sdk/cohere
@ai-sdk/deepgram
@ai-sdk/deepinfra
@ai-sdk/deepseek
@ai-sdk/devtools
@ai-sdk/durable-agent
@ai-sdk/elevenlabs
@ai-sdk/fal
@ai-sdk/fireworks
@ai-sdk/fish-audio
@ai-sdk/gateway
@ai-sdk/gladia
@ai-sdk/gmicloud
@ai-sdk/google
@ai-sdk/google-vertex
@ai-sdk/groq
@ai-sdk/harness
@ai-sdk/harness-acp
@ai-sdk/harness-claude-code
@ai-sdk/harness-cline
@ai-sdk/harness-codex
@ai-sdk/harness-deepagents
@ai-sdk/harness-grok-build
@ai-sdk/harness-opencode
@ai-sdk/harness-pi
@ai-sdk/huggingface
@ai-sdk/hume
@ai-sdk/klingai
@ai-sdk/langchain
@ai-sdk/llamaindex
@ai-sdk/lmnt
@ai-sdk/luma
@ai-sdk/mcp
@ai-sdk/minimax
@ai-sdk/mistral
@ai-sdk/moonshotai
@ai-sdk/open-responses
@ai-sdk/openai
@ai-sdk/openai-compatible
@ai-sdk/otel
@ai-sdk/perplexity
@ai-sdk/policy-opa
@ai-sdk/prodia
@ai-sdk/provider
@ai-sdk/provider-utils
@ai-sdk/quiverai
@ai-sdk/react
@ai-sdk/replicate
@ai-sdk/revai
@ai-sdk/rsc
@ai-sdk/sandbox-just-bash
@ai-sdk/sandbox-vercel
@ai-sdk/solid
@ai-sdk/specification
@ai-sdk/svelte
@ai-sdk/swarm
@ai-sdk/test-server
@ai-sdk/togetherai
@ai-sdk/tui
@ai-sdk/ui-utils
@ai-sdk/valibot
@ai-sdk/vercel
@ai-sdk/voyage
@ai-sdk/vue
@ai-sdk/workflow
@ai-sdk/workflow-harness
@ai-sdk/xai
```

The 16 names omitted by `npm search --json` were
`@ai-sdk/durable-agent`, `@ai-sdk/gmicloud`, `@ai-sdk/harness`,
`@ai-sdk/harness-acp`, `@ai-sdk/harness-claude-code`,
`@ai-sdk/harness-cline`, `@ai-sdk/harness-codex`,
`@ai-sdk/harness-grok-build`, `@ai-sdk/harness-opencode`,
`@ai-sdk/harness-pi`, `@ai-sdk/sandbox-just-bash`,
`@ai-sdk/sandbox-vercel`, `@ai-sdk/specification`, `@ai-sdk/swarm`,
`@ai-sdk/test-server`, and `@ai-sdk/vercel`.

SwiftAISDK implements 43 model-provider packages. Two are intentionally not
auto-ported by this automation:

- `@ai-sdk/fish-audio@3.0.5` remains the previously reported gap. Its
  `3.0.3 -> 3.0.5` delta is dependency-only; the port still needs S1/S2/S2.1
  binary speech, multipart transcription, authentication, options, warnings,
  provider metadata/errors, registry/capability rows, docs, and tests.
- `@ai-sdk/gmicloud@3.0.1` is new since the previous run. A port needs an
  OpenAI-compatible chat provider with `GMI_CLOUD_APIKEY`, the default
  `https://api.gmi-serving.com/v1` endpoint, `gmicloud.chat` identity,
  streaming usage, nested `error.details` decoding, model aliases, registry
  and capability rows, public docs, and translated tests.

The other new registry name is non-provider
`@ai-sdk/harness-cline@1.0.0`; it is a coding-agent harness and is outside the
provider-facing SwiftAISDK product scope.

### 2026-08-17 Verification

- `node Scripts/check-upstream-versions.js --all --json --fail-on-outdated`:
  48 tracked packages current, zero drift and zero registry errors.
- Exact npm registry-prefix metadata: 81 live `@ai-sdk/*` packages; the
  independent `npm search --json` result contained 65.
- Focused Swift tests: 148 core/MCP/Alibaba/Anthropic/Moonshot/OpenAI/Open
  Responses tests, 144 Google/Vertex/Gateway tests, 50 xAI tests, 15 final
  Open Responses tests, 15 Gateway/Vertex/error-formatting regressions, 31 MCP
  OAuth/HTTP authorization tests, 2 resumed-chat tests, 2 Moonshot/Anthropic
  alias/output regressions, and 4 provider-capability matrix tests all passed
  with zero failures.
- `swift test`: 2,392 tests across 3 suites passed with zero failures.
- `npm ci --prefix docs-site`: completed successfully.
- `npm --prefix docs-site run check`: 4 files checked with zero errors,
  warnings, or hints.
- `npm --prefix docs-site run build`: 85 pages built successfully and indexed
  by Pagefind.
- `git diff --check`: passed.

## 2026-08-10 Tracked Package Results

All 48 tracked packages changed. Their 96 published npm tarballs were unpacked
and compared separately under
`/tmp/ai-sdk-port-upstream-diffs-20260810.M2anYQ`; published packages omit test
sources, so changed upstream tests were also reviewed between repository commit
`3bc0d4f40df7` and `74abcdfb6a41`.

| Package | Previous | Current | Result |
| --- | ---: | ---: | --- |
| `ai` | `7.0.48` | `7.0.58` | `ported/deferred` — default instructions, agent default timeout, reconnect abort propagation, and shared stream/tool tracking are ported. Batch V4 and the generic async-video start/status/webhook surface remain a shared public-API gap. |
| `@ai-sdk/provider` | `4.0.4` | `4.0.7` | `covered/deferred` — adaptive aspect ratios already pass through as strings; Batch V4 and async Video V4 need the shared protocols above. |
| `@ai-sdk/provider-utils` | `5.0.18` | `5.0.25` | `ported/covered` — streamed calls now correlate by ID, then index, then latest and finalize only on flush; `Data`, non-stateful Swift regexes, and typed schemas already cover or avoid the remaining JS-only changes. |
| `@ai-sdk/react` | `4.0.51` | `4.0.61` | `covered` — the source change is React/useSyncExternalStore-specific throttling with no Swift render-subscription analogue. |
| `@ai-sdk/alibaba` | `2.0.22` | `2.0.29` | `ported/covered` — the shared streamed tool-call identity fix is ported; loose usage/raw-field behavior is already covered. Async video operations remain behind the shared surface while unary submit/poll remains available. |
| `@ai-sdk/amazon-bedrock` | `5.0.40` | `5.0.50` | `ported` — assistant turns left empty after unsigned-reasoning filtering are now omitted from Converse requests. |
| `@ai-sdk/anthropic` | `4.0.27` | `4.0.36` | `ported/deferred` — advisor token caps/stop reasons, message-start splice protection, and complete code-execution replay are ported; Messages Batch waits on the shared batch contract. |
| `@ai-sdk/anthropic-aws` | `2.0.19` | `2.0.28` | `covered` — package-local source is unchanged and the provider inherits the shared Anthropic behavior. |
| `@ai-sdk/assemblyai` | `3.0.18` | `3.0.25` | `version-only`. |
| `@ai-sdk/azure` | `4.0.28` | `4.0.37` | `version-only`; OpenAI dependency behavior is audited separately. |
| `@ai-sdk/baseten` | `2.0.20` | `2.1.6` | `ported` — embeddings now use OpenAI-compatible HTTP options without synthesized performance-client headers, chat streams request usage, and both Baseten error envelopes are preserved. |
| `@ai-sdk/black-forest-labs` | `2.0.18` | `2.0.26` | `ported` — FLUX 3 video request modes, polling, credential trust, warnings, results, settled cost, and provider metadata are exposed through the existing unary Swift video contract. |
| `@ai-sdk/bytedance` | `2.0.20` | `2.0.27` | `covered/deferred` — unary request/poll/error behavior remains covered; splitting it into start/status operations and moving polling controls to core waits on async Video V4. |
| `@ai-sdk/cartesia` | `3.0.12` | `3.0.20` | `deferred` — new Ink2 encodings are for the already-recorded duplex WebSocket transcription surface; batch REST behavior is unchanged. |
| `@ai-sdk/cerebras` | `3.0.20` | `3.0.28` | `ported` — inherits the shared non-contiguous/reused/missing streamed tool index fix. |
| `@ai-sdk/cohere` | `4.0.18` | `4.0.25` | `version-only`. |
| `@ai-sdk/deepgram` | `3.0.18` | `3.0.25` | `version-only`. |
| `@ai-sdk/deepinfra` | `3.0.20` | `3.0.28` | `version-only`. |
| `@ai-sdk/deepseek` | `3.0.19` | `3.0.26` | `ported` — inherits the shared streamed tool-call identity fix without collapsing reused or absent indexes. |
| `@ai-sdk/elevenlabs` | `3.0.19` | `3.0.26` | `version-only`. |
| `@ai-sdk/fal` | `3.0.19` | `3.0.26` | `covered/deferred` — unary queue polling remains covered; webhook operation state and core-owned polling wait on async Video V4. |
| `@ai-sdk/fireworks` | `3.0.22` | `3.0.30` | `version-only`. |
| `@ai-sdk/gateway` | `4.0.37` | `4.0.46` | `covered/deferred` — current unary video and media routing remain covered; callback/start/status and stable start idempotency wait on async Video V4. |
| `@ai-sdk/gladia` | `3.0.18` | `3.0.25` | `version-only`. |
| `@ai-sdk/google` | `4.0.31` | `4.0.39` | `covered/deferred` — unary Veo polling remains covered; async operations and renamed duplex speech translation need their shared protocol surfaces. |
| `@ai-sdk/google-vertex` | `5.0.38` | `5.0.48` | `covered/deferred` — existing Vertex submit/poll mapping is unchanged; the new start/status split waits on async Video V4. |
| `@ai-sdk/groq` | `4.0.19` | `4.0.26` | `ported` — inherits the shared streamed tool-call tracker correction. |
| `@ai-sdk/huggingface` | `2.0.20` | `2.0.28` | `version-only`. |
| `@ai-sdk/hume` | `3.0.18` | `3.0.25` | `version-only`. |
| `@ai-sdk/klingai` | `4.0.20` | `4.0.27` | `covered/deferred` — request, status and terminal parsing stay covered by unary polling; public start/status operations wait on async Video V4. |
| `@ai-sdk/lmnt` | `3.0.18` | `3.0.25` | `version-only`. |
| `@ai-sdk/luma` | `3.0.19` | `3.0.26` | `version-only`. |
| `@ai-sdk/mcp` | `2.0.22` | `2.0.29` | `version-only`. |
| `@ai-sdk/minimax` | `3.0.2` | `3.0.12` | `ported` — H3 text-to-video now defaults and falls back to `16:9` while frame/reference ratio behavior is preserved. |
| `@ai-sdk/mistral` | `4.0.20` | `4.0.27` | `version-only`. |
| `@ai-sdk/moonshotai` | `3.0.23` | `3.0.31` | `version-only`. |
| `@ai-sdk/open-responses` | `2.0.18` | `2.0.25` | `version-only`. |
| `@ai-sdk/openai` | `4.0.27` | `4.0.36` | `ported/deferred` — output-schema tool results are JSON strings and streaming output indexes retain stable item IDs. Text Batch and duplex speech translation wait on shared protocols; `serviceTier: fast` already passes through. |
| `@ai-sdk/openai-compatible` | `3.0.20` | `3.0.28` | `ported` — output text-token usage is clamped at zero when reasoning exceeds completion totals; streamed tool identity uses the shared fix. |
| `@ai-sdk/perplexity` | `4.0.20` | `4.0.27` | `version-only`. |
| `@ai-sdk/prodia` | `2.0.19` | `2.0.26` | `covered` — the only source change is a TypeScript alias/non-nullability refinement. |
| `@ai-sdk/quiverai` | `2.0.18` | `2.0.25` | `version-only`. |
| `@ai-sdk/replicate` | `3.0.19` | `3.0.26` | `covered/deferred` — unary submit/poll remains available; webhook/status operations and trusted result-URL state wait on async Video V4. |
| `@ai-sdk/revai` | `3.0.18` | `3.0.25` | `version-only`. |
| `@ai-sdk/togetherai` | `3.0.21` | `3.0.29` | `version-only`. |
| `@ai-sdk/vercel` | `3.0.20` | `3.0.28` | `version-only`. |
| `@ai-sdk/voyage` | `2.0.18` | `2.0.25` | `version-only`. |
| `@ai-sdk/xai` | `4.0.25` | `4.0.33` | `covered/deferred` — unary create/poll remains covered; operation APIs and richer async failure state wait on async Video V4. |

### 2026-08-10 Registry Discovery

The exact npm registry prefix contains 79 live `@ai-sdk/*` packages, while
`npm search` returns only 65. There are 44 model-provider packages: the 43
already tracked providers plus new `@ai-sdk/fish-audio@3.0.3`. Fish Audio was
first published after the prior run and is intentionally not implemented by
this automation. A port needs provider/auth setup, S1/S2 binary speech over
`POST /v1/tts`, multipart batch transcription over `POST /v1/asr`, voice and
prosody options, warnings, `{status,message}` errors, metadata, registry and
capability rows, public docs, and translated tests. Its upstream WebSocket TTS
and MessagePack zero-shot cloning are themselves outside the published unary
model surface.

Two other packages created since the prior run, `@ai-sdk/harness-acp` and
`@ai-sdk/harness-grok-build`, are harness adapters rather than model providers.
The complete unfiltered discovery was reviewed so registry entries with absent
or unusual descriptions were not silently missed by provider-only heuristics.

### 2026-08-10 Verification

| Check | Result |
| --- | --- |
| `node Scripts/check-upstream-versions.js --all --json --fail-on-outdated` | Passed after the ledger update: 48 tracked packages, zero outdated rows, and zero registry errors. |
| `node Scripts/check-upstream-versions.js --discover-packages --all --json` plus exact registry-prefix metadata review | Passed: 79 live `@ai-sdk/*` packages, 44 model providers, and new `@ai-sdk/fish-audio@3.0.3` as the only untracked model provider. |
| Published old/new package diff preparation under `/tmp/ai-sdk-port-upstream-diffs-20260810.M2anYQ` | Audited all 48 changed packages from 96 published npm tarballs in separate diffs. |
| Focused Swift tests | Passed: 507 combined Anthropic, OpenAI Responses, Black Forest Labs, MiniMax, agent/chat/middleware, and streamed-tool tests; 19 Baseten/Bedrock/shared-stream tests; capability-matrix parity; and the final BFL elapsed-time and Anthropic stable-wire regressions. |
| `swift test` | Passed: 2,275 tests in 3 suites. |
| `npm ci --prefix docs-site` and `npm --prefix docs-site run check` | Passed: Astro reported zero errors, warnings, or hints. `npm ci` reported 8 dependency advisories (1 low, 7 high). |
| `npm --prefix docs-site run build` | Passed: 85 static pages built. |
| `git diff --check` | Passed. |

## 2026-08-03 Tracked Package Results

Published tarballs for every changed row were downloaded into
`/tmp/ai-sdk-port-upstream-diffs-20260803.4ZCm5R` and compared separately.
The common `5fc7da5`/`93b2acd` release train centralizes empty usage and
response-metadata helpers without changing observable result shapes. Runtime
and focused-test expectations now use each package's current versioned
user-agent suffix.

| Package | Previous | Current | Result |
| --- | ---: | ---: | --- |
| `ai` | `7.0.44` | `7.0.48` | `deferred/covered` — `experimental_toolCallers` now reaches `streamText` and `ToolLoopAgent`, but still needs the shared Swift caller graph already recorded for `generateText`. Streaming-only timeout warnings cannot occur until Swift exposes structured timeout fields; the clarified no-output contract is already covered by `AINoOutputError`. |
| `@ai-sdk/provider` | `4.0.4` | `4.0.4` | `covered` — npm latest is unchanged. |
| `@ai-sdk/provider-utils` | `5.0.16` | `5.0.18` | `covered/deferred` — shared empty-usage and response-metadata factories preserve existing Swift result shapes; the JavaScript tool-caller marker change belongs to the deferred caller abstraction. |
| `@ai-sdk/react` | `4.0.47` | `4.0.51` | `version-only` — dependency propagation; no React source contract changed. |
| `@ai-sdk/alibaba` | `2.0.20` | `2.0.22` | `version-only`. |
| `@ai-sdk/amazon-bedrock` | `5.0.38` | `5.0.40` | `covered` — empty language-usage creation moved to the shared helper with the same fields and nullability. |
| `@ai-sdk/anthropic` | `4.0.26` | `4.0.27` | `version-only`. |
| `@ai-sdk/anthropic-aws` | `2.0.17` | `2.0.19` | `version-only`. |
| `@ai-sdk/assemblyai` | `3.0.16` | `3.0.18` | `version-only`. |
| `@ai-sdk/azure` | `4.0.26` | `4.0.28` | `version-only`; the shared OpenAI dependency changes are audited in their own rows. |
| `@ai-sdk/baseten` | `2.0.18` | `2.0.20` | `version-only`. |
| `@ai-sdk/black-forest-labs` | `2.0.16` | `2.0.18` | `version-only`. |
| `@ai-sdk/bytedance` | `2.0.18` | `2.0.20` | `version-only`. |
| `@ai-sdk/cartesia` | `3.0.10` | `3.0.12` | `version-only`. |
| `@ai-sdk/cerebras` | `3.0.18` | `3.0.20` | `version-only`. |
| `@ai-sdk/cohere` | `4.0.16` | `4.0.18` | `covered` — empty usage construction was centralized without a wire/result change. |
| `@ai-sdk/deepgram` | `3.0.16` | `3.0.18` | `version-only`. |
| `@ai-sdk/deepinfra` | `3.0.18` | `3.0.20` | `version-only`. |
| `@ai-sdk/deepseek` | `3.0.17` | `3.0.19` | `covered` — empty usage and response metadata now call shared helpers with equivalent output. |
| `@ai-sdk/elevenlabs` | `3.0.17` | `3.0.19` | `version-only`; realtime transcription remains the existing shared WebSocket gap. |
| `@ai-sdk/fal` | `3.0.17` | `3.0.19` | `version-only`. |
| `@ai-sdk/fireworks` | `3.0.19` | `3.0.22` | `ported` — chat, completion, and embedding structured `{ error: { message, ... } }` envelopes now preserve the provider message while retaining legacy string errors. The image model keeps its unchanged generic HTTP-error body handling. |
| `@ai-sdk/gateway` | `4.0.33` | `4.0.37` | `ported/covered` — provider routing accepts `has: ["vision"]`; generated model-ID/settings changes remain covered by forward-compatible Swift string IDs. |
| `@ai-sdk/gladia` | `3.0.16` | `3.0.18` | `version-only`. |
| `@ai-sdk/google` | `4.0.29` | `4.0.31` | `covered` — empty usage construction moved to the shared helper with no observable change. |
| `@ai-sdk/google-vertex` | `5.0.36` | `5.0.38` | `version-only`; shared Google behavior is covered by the `@ai-sdk/google` row. |
| `@ai-sdk/groq` | `4.0.17` | `4.0.19` | `covered` — empty usage and response metadata helper refactors preserve existing output. |
| `@ai-sdk/huggingface` | `2.0.18` | `2.0.20` | `covered` — empty usage helper refactor is behavior-equivalent. |
| `@ai-sdk/hume` | `3.0.16` | `3.0.18` | `version-only`. |
| `@ai-sdk/klingai` | `4.0.18` | `4.0.20` | `version-only`. |
| `@ai-sdk/lmnt` | `3.0.16` | `3.0.18` | `version-only`. |
| `@ai-sdk/luma` | `3.0.17` | `3.0.19` | `version-only`. |
| `@ai-sdk/mcp` | `2.0.20` | `2.0.22` | `version-only`. |
| `@ai-sdk/minimax` | `3.0.1` | `3.0.2` | `ported` — MiniMax-H3 video adds text-to-video, first/last-frame, and reference-to-video request/poll/result behavior while retaining the Anthropic-compatible language surface. |
| `@ai-sdk/mistral` | `4.0.18` | `4.0.20` | `covered` — empty usage and response metadata helper refactors preserve the current Swift behavior. |
| `@ai-sdk/moonshotai` | `3.0.21` | `3.0.23` | `covered` — empty usage helper refactor is behavior-equivalent. |
| `@ai-sdk/open-responses` | `2.0.16` | `2.0.18` | `version-only`. |
| `@ai-sdk/openai` | `4.0.25` | `4.0.27` | `ported/covered` — file upload expiry is serialized as `expires_after[anchor]=created_at` plus `expires_after[seconds]`; chat metadata keeps zero-valued Azure content-filter timestamps absent while generic OpenAI-compatible providers continue preserving explicit epoch timestamps; remaining usage/metadata changes are behavior-preserving shared-helper refactors. |
| `@ai-sdk/openai-compatible` | `3.0.18` | `3.0.20` | `covered` — empty usage and response metadata helper refactors retain prior result shapes. |
| `@ai-sdk/perplexity` | `4.0.18` | `4.0.20` | `covered` — shared usage/metadata helpers preserve existing quantized embedding and language behavior. |
| `@ai-sdk/prodia` | `2.0.17` | `2.0.19` | `version-only`. |
| `@ai-sdk/quiverai` | `2.0.16` | `2.0.18` | `version-only`. |
| `@ai-sdk/replicate` | `3.0.17` | `3.0.19` | `version-only`. |
| `@ai-sdk/revai` | `3.0.16` | `3.0.18` | `version-only`. |
| `@ai-sdk/togetherai` | `3.0.19` | `3.0.21` | `version-only`. |
| `@ai-sdk/vercel` | `3.0.18` | `3.0.20` | `version-only`. |
| `@ai-sdk/voyage` | `2.0.16` | `2.0.18` | `version-only`. |
| `@ai-sdk/xai` | `4.0.23` | `4.0.25` | `covered` — response metadata conversion moved to the shared helper with the same timestamp and identifiers. |

### 2026-08-03 Verification

| Check | Result |
| --- | --- |
| `node Scripts/check-upstream-versions.js --all --json` | Passed after the ledger update: 48 tracked packages, zero outdated rows, and zero registry errors. |
| `node Scripts/check-upstream-versions.js --discover-packages --all --json` | Passed against exact registry-prefix metadata: 76 live `@ai-sdk/*` packages, 43 model providers, and zero untracked model providers. |
| `node Scripts/check-upstream-versions.js --all --prepare-diffs --work-dir /tmp/ai-sdk-port-upstream-diffs-20260803.4ZCm5R` | Audited 47 changed packages from 94 published npm tarballs in separate diffs; `@ai-sdk/provider@4.0.4` was the only unchanged tracked package. |
| Focused Swift tests | Passed: 59 combined MiniMax, Fireworks, Gateway, OpenAI files/metadata, and capability-matrix tests, followed by 4 stream-metadata regressions after the full-suite review. |
| `swift test` | Passed: 2,243 tests in 3 suites. |
| `npm ci --prefix docs-site` and `npm --prefix docs-site run check` | Passed: Astro reported zero errors, warnings, or hints. |
| `npm --prefix docs-site run build` | Passed: 85 static pages built. |
| `git diff --check` | Passed. |

## 2026-08-01 Tracked Package Results

| Package | Previous | Current | Result |
| --- | ---: | ---: | --- |
| `ai` | `7.0.37` | `7.0.44` | `ported/deferred` — response-model telemetry attribution, provider-executed invalid-tool handling, and empty-delta provider metadata are covered by focused regressions. Per-step call-setting overlays, generic provider tool-callers, and speech translation remain explicit shared-core work. |
| `@ai-sdk/provider` | `4.0.3` | `4.0.4` | `deferred` — the new experimental streaming speech-translation model contract depends on a reusable duplex audio/WebSocket surface. |
| `@ai-sdk/provider-utils` | `5.0.12` | `5.0.16` | `deferred` — Swift keeps literal/private-address and redirect validation, but the new Node connector also pins the validated DNS answer. Equivalent DNS resolution pinning needs a transport-level design; workflow serialization and JS WebSocket helpers have no direct Swift surface. |
| `@ai-sdk/react` | `4.0.40` | `4.0.47` | `version-only` — dependency propagation; no portable React source contract changed. |
| `@ai-sdk/alibaba` | `2.0.16` | `2.0.20` | `version-only`. |
| `@ai-sdk/amazon-bedrock` | `5.0.32` | `5.0.38` | `ported` — Converse video MIME/source mapping, strict-tool warnings, and non-native structured-output fallback with ordinary tools. |
| `@ai-sdk/anthropic` | `4.0.21` | `4.0.25` | `deferred` — code-execution tools now use the generic provider tool-caller contract; record-guard refactoring is JavaScript-only. Existing manual `allowedCallers` wire support remains available. |
| `@ai-sdk/anthropic-aws` | `2.0.13` | `2.0.17` | `version-only`; it inherits the Anthropic tool-caller decision. |
| `@ai-sdk/assemblyai` | `3.0.12` | `3.0.16` | `version-only`. |
| `@ai-sdk/azure` | `4.0.21` | `4.0.26` | `ported` — inherits OpenAI Responses web-search `blockedDomains` request mapping; the remaining package delta is dependency propagation. |
| `@ai-sdk/baseten` | `2.0.14` | `2.0.18` | `version-only`. |
| `@ai-sdk/black-forest-labs` | `2.0.12` | `2.0.16` | `version-only`. |
| `@ai-sdk/bytedance` | `2.0.14` | `2.0.18` | `version-only`. |
| `@ai-sdk/cartesia` | `3.0.6` | `3.0.10` | `version-only`. |
| `@ai-sdk/cerebras` | `3.0.14` | `3.0.18` | `version-only`. |
| `@ai-sdk/cohere` | `4.0.12` | `4.0.16` | `version-only`. |
| `@ai-sdk/deepgram` | `3.0.12` | `3.0.16` | `version-only`. |
| `@ai-sdk/deepinfra` | `3.0.14` | `3.0.18` | `version-only`. |
| `@ai-sdk/deepseek` | `3.0.13` | `3.0.17` | `version-only`. |
| `@ai-sdk/elevenlabs` | `3.0.13` | `3.0.17` | `deferred` — Scribe v2 Realtime is a duplex WebSocket transcription surface; batch transcription is unchanged. |
| `@ai-sdk/fal` | `3.0.13` | `3.0.17` | `version-only`. |
| `@ai-sdk/fireworks` | `3.0.15` | `3.0.19` | `version-only`. |
| `@ai-sdk/gateway` | `4.0.28` | `4.0.33` | `covered` — only TypeScript model-ID unions changed; Swift accepts forward-compatible string IDs. The added realtime ID belongs to the existing realtime gap. |
| `@ai-sdk/gladia` | `3.0.12` | `3.0.16` | `version-only`. |
| `@ai-sdk/google` | `4.0.24` | `4.0.29` | `ported/deferred` — Interactions forwards `topK`/`seed`, emits the complete standard-setting warnings, and Google Files omits the upload POST `Content-Length`. Gemini Live speech translation remains deferred with the shared translation surface. |
| `@ai-sdk/google-vertex` | `5.0.31` | `5.0.36` | `version-only`; shared Google Interactions behavior is covered by the `@ai-sdk/google` port. |
| `@ai-sdk/groq` | `4.0.13` | `4.0.17` | `ported` — transcription supports raw `text` response format and falls back from `segments` to word timestamps. |
| `@ai-sdk/huggingface` | `2.0.14` | `2.0.18` | `version-only`. |
| `@ai-sdk/hume` | `3.0.12` | `3.0.16` | `version-only`. |
| `@ai-sdk/klingai` | `4.0.13` | `4.0.18` | `ported` — single API-key and legacy access/secret-key authentication now follow upstream trimming and precedence rules while preserving custom Authorization overrides. |
| `@ai-sdk/lmnt` | `3.0.12` | `3.0.16` | `version-only`. |
| `@ai-sdk/luma` | `3.0.13` | `3.0.17` | `version-only`. |
| `@ai-sdk/mcp` | `2.0.16` | `2.0.20` | `ported` — initialization and ordinary requests accept abort, timeout, and maximum-total-timeout options with minimum-timeout semantics and initialization cleanup. |
| `@ai-sdk/mistral` | `4.0.14` | `4.0.18` | `ported` — assistant reasoning preserves typed thinking blocks and Voxtral batch transcription maps options, validation, segments, usage, and provider metadata. |
| `@ai-sdk/moonshotai` | `3.0.17` | `3.0.21` | `version-only`. |
| `@ai-sdk/open-responses` | `2.0.12` | `2.0.16` | `version-only`. |
| `@ai-sdk/openai` | `4.0.20` | `4.0.25` | `ported/deferred` — Responses web-search blocked domains are mapped. Generic provider tool-callers, early live `response.in_progress` acknowledgement, and realtime speech translation require shared core/transport work. |
| `@ai-sdk/openai-compatible` | `3.0.14` | `3.0.18` | `version-only`. |
| `@ai-sdk/perplexity` | `4.0.13` | `4.0.18` | `ported` — native quantized embeddings add 512-value preflight, signed/binary base64 decoding, dimensions/encoding options, usage, cost metadata, response metadata, and embedding aliases. |
| `@ai-sdk/prodia` | `2.0.13` | `2.0.17` | `version-only`. |
| `@ai-sdk/quiverai` | `2.0.12` | `2.0.16` | `version-only`. |
| `@ai-sdk/replicate` | `3.0.13` | `3.0.17` | `version-only`. |
| `@ai-sdk/revai` | `3.0.12` | `3.0.16` | `version-only`. |
| `@ai-sdk/togetherai` | `3.0.15` | `3.0.19` | `ported` — chat and completion streams request usage by default. |
| `@ai-sdk/vercel` | `3.0.14` | `3.0.18` | `version-only`. |
| `@ai-sdk/voyage` | `2.0.12` | `2.0.16` | `version-only`. |
| `@ai-sdk/xai` | `4.0.18` | `4.0.23` | `ported` — Responses warnings include unsupported sampling penalties, and video polling treats empty or malformed HTTP 202 bodies as pending. |

## Initial Weekly Verification

These results are the snapshot that identified MiniMax before the approved
follow-up port below. They are retained as the evidence for the original
47-package weekly audit, rather than a statement about registry state after the
follow-up.

| Check | Result |
| --- | --- |
| `node Scripts/check-upstream-versions.js --all --json` | Passed after the ledger update: 47 tracked packages, zero outdated rows, and zero registry errors. |
| `node Scripts/check-upstream-versions.js --discover-packages --all --json` | Passed: 76 live `@ai-sdk/*` packages, 43 classified model providers, and `@ai-sdk/minimax@3.0.0` as the only untracked model provider. The registry-only packages without descriptions resolve as `@ai-sdk/specification@0.0.0` and `@ai-sdk/test-server@2.0.1`. |
| `node Scripts/check-upstream-versions.js --all --prepare-diffs --work-dir /tmp/ai-sdk-port-upstream-diffs-20260801.KTahaI` | Before updating the ledger, produced 47 separate `upstream.diff`/`summary.md` pairs from 94 published npm tarballs. |
| `swift test --filter providerCapabilityMatrixDocumentationMatchesGeneratedMarkdown` | Passed: 1 focused generated-documentation parity test. |
| `swift test` | Passed after the final MCP, KlingAI, and Mistral review fixes: 2,220 tests in 3 suites. |
| `npm ci --prefix docs-site` and `npm --prefix docs-site run build` | Passed; the docs build generated 84 pages. |
| `git diff --check` | Passed. |

## Initial Weekly Registry Discovery

An exact npm replication-registry prefix query returned 76 live
`@ai-sdk/*` packages and 43 model-provider packages. The repository's tracked
provider set contains 42 model providers.

New provider:

- `@ai-sdk/minimax@3.0.0`, first published 2026-07-29. It is a language-only
  Anthropic Messages adapter using `https://api.minimax.io/anthropic/v1`,
  `MINIMAX_API_KEY`, MiniMax model IDs, and adaptive/disabled thinking options.
  A port should reuse the Anthropic message/request/stream parser, add a
  dedicated provider factory and capability row, and translate the published
  configuration and reasoning fixtures. It is intentionally not implemented
  by this discovery task.

New non-provider package:

- `@ai-sdk/code-mode@1.0.1` supplies a QuickJS-backed JavaScript tool-calling
  runtime. It is not a model provider and is not automatically added to the
  Swift provider matrix.

The local `npm search` helper returned only 63 prefix packages and missed
MiniMax, so exact registry prefix metadata remains required for provider
discovery.

## MiniMax Follow-up

The approved follow-up ports the provider reported above. Although the request
named `@ai-sdk/minimax@3.0.0`, npm had published `3.0.1` before implementation
started, so SwiftAISDK records the current version while retaining exact 3.0.0
behavior.

- MiniMax `3.0.0` and `3.0.1` have byte-identical source, declarations, and
  README content. The direct delta is package/version propagation, the
  versioned user-agent, Anthropic `4.0.25` to `4.0.26`, and provider-utils
  `5.0.16` to `5.0.17`.
- Anthropic `4.0.26` adds `display: summarized` when generic top-level reasoning
  maps to adaptive thinking. Swift ports that shared request change and the
  ordered generate-content parser used by MiniMax, including signed/redacted
  reasoning, tool/source placement, citation metadata, and compaction.
- `MiniMaxProvider` adds `MINIMAX_API_KEY`, the Anthropic-compatible base URL
  and headers, `minimax.messages` identity, callable/language/chat access,
  empty URL capabilities, unsupported-family errors, and shared Anthropic
  request, stream, error, usage, response-metadata, and telemetry behavior.
- Both published MiniMax test files are translated in
  `MiniMaxProviderTests.swift`, with extra streaming and configuration
  regressions. The capability matrix, ledger, public README, docs site, and
  upstream test inventory are registered in the same change.
- A fresh exact registry-prefix query still returns 76 live `@ai-sdk/*`
  packages and 43 model providers, now with zero untracked model providers;
  `@ai-sdk/minimax@3.0.1` is classified as tracked.

### MiniMax Follow-up Verification

| Check | Result |
| --- | --- |
| `node Scripts/check-upstream-versions.js --package @ai-sdk/minimax --package @ai-sdk/anthropic --all --json` | Passed: MiniMax `3.0.1` and Anthropic `4.0.26` are current, with zero registry errors. |
| `node Scripts/check-upstream-versions.js --discover-packages --discover-kind provider --all --json` | Passed: 43 live model providers and zero untracked model providers. |
| `swift test --filter MiniMax` | Passed: 7 focused MiniMax tests. |
| `swift test` | Passed: 2,227 tests in 3 suites. |
| `npm ci --prefix docs-site` and `npm --prefix docs-site run build` | Passed; the docs build generated 85 pages, including `/providers/minimax/`. |
| `git diff --check` | Passed. |
