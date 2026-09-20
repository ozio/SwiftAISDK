# Porting Status

Snapshot date: 2026-09-20

SwiftAISDK currently ports the provider-facing parts of Vercel AI SDK into a
SwiftPM library. The package has a broad Swift-native facade, provider registry,
provider implementations, generated provider capability docs, upstream-shaped
parity tests, and a static documentation site.

The repository is distributed under Apache-2.0; the complete terms are in the
root `LICENSE` file.

This file is the readable status page. It replaces the older provider-progress
journals and product-gap checklist. Use the ledgers and generated inventories
for exact evidence.

## Current Shape

- The `AI` facade covers text, streaming text, durable text batches, structured
  output, embeddings, images, unary and asynchronous video, speech, batch and
  streaming transcription, reranking, Files V4 operations, skill uploads,
  middleware, telemetry, warnings, setup and in-band stream retries, aborts,
  tools, approvals, MCP tools, UI messages, chat sessions, agent helpers, and
  provider-neutral realtime sessions.
- Experimental Evaluation V4 is available through `AI.experimentalEvaluate`
  with Choice, Score, and Boolean questions, provider/default-registry model
  resolution, and OpenAI, Anthropic, Google, and Gateway adapters.
- HTTP language-model streaming consumes SSE and Amazon EventStream bodies
  incrementally through `AIStreamingTransport`; first parts can arrive before
  response EOF, and abort or early consumer termination cancels the body read.
  Send-only custom transports remain supported for unary generation and fail
  streaming explicitly instead of falling back to buffered `send`.
- Built-in language streams expose one canonical part-aware text/reasoning
  lifecycle and one terminal part per logical response. Legacy-only custom
  streams are normalized at the facade boundary, while ambiguous mixed-family
  streams fail explicitly. In-band provider errors remain observable without
  turning text-only streams into silent successes.
- Provider coverage spans the official provider-facing `@ai-sdk/*` packages
  tracked in `Docs/ProviderVersionLedger.md`.
- `Docs/ProviderCapabilityMatrix.md` is generated from
  `Sources/SwiftAISDK/Providers/ProviderCapabilityMatrix.swift` and guarded by
  tests.
- Core AI SDK parity is tracked in `Docs/CoreV6Parity.md`.
- Upstream test/spec files are inventoried in `Docs/UpstreamTestInventory.md`.
- Public docs live in `README.md` and `docs-site`.

## Baselines

| Area | Source of truth |
| --- | --- |
| Provider npm baselines | `Docs/ProviderVersionLedger.md` |
| Provider capabilities | `Sources/SwiftAISDK/Providers/ProviderCapabilityMatrix.swift`, generated into `Docs/ProviderCapabilityMatrix.md` |
| Core AI SDK parity | `Docs/CoreV6Parity.md` |
| Upstream test inventory | `Docs/UpstreamTestInventory.md` |
| Latest upstream test diff audit | `Docs/FreshUpstreamTestDiffAudit.md` |

Provider and core package versions were checked against npm registry metadata
on 2026-09-20. The packages changed by this weekly pass were reviewed from
their exact published tarballs; per-package decisions are recorded in
`Docs/UpstreamPackageDiffAudit.md`. The current upstream inventory contains
919 executable test/spec paths in 81 groups. The fresh diff audit separately
classifies all 137 changed executable paths and all 18 changed declaration
test (`test-d`) paths.

## Provider State

The 2026-09-20 weekly pass audits all 50 tracked core and provider/product
rows: 18 are `ported`, two are `covered` by shared behavior, and 27 are
`version-only` package-local dependency or identity synchronization.
`@ai-sdk/react` remains out of scope, while LMNT and Vercel were already
current.

Exact registry-prefix discovery finds 87 live `@ai-sdk/*` names and 38
untracked scoped packages. Two of those are unported providers:
`@ai-sdk/zai@3.0.15` and the newly published evaluation-only
`@ai-sdk/typesafe-ai@3.0.4`. They remain explicit future verticals rather than
being silently added without complete runtime, test, capability, and
documentation coverage.

Core work adds the Evaluation V4 facade and provider adapters; dynamic local
and provider tool callers across generate, stream, and agent orchestration;
abort-aware URL prompt downloads; per-step provider/model identity and
telemetry; final-step structured generation and lossless partial structured
stream output; approval-safe history pruning and preliminary-output chat
handling; charset-aware data URLs, AAC detection, and in-flight video polling
deadlines; and coalesced MCP authorization refresh for concurrent or late stale
401 responses. Continuous realtime now supports the portable server-WebSocket
contract, with OpenAI Live joining xAI as a provider adapter.

Provider work preserves Alibaba thinking history; aligns Bedrock model-family,
strict-schema, web-tool, block-binding, and failure handling; adds Anthropic
20260318 web search/fetch behavior; gives DeepSeek its exact empty-choice
failure; and makes Google JSON Schema conversion and streamed metadata,
grounding, safety, finish, and usage accumulation lossless. TogetherAI handles
the Gemini image exception; Black Forest Labs and Fireworks enforce wall-clock
polling deadlines; ByteDance maps reference-image roles; Quiver implements its
Arrow 2 surface; and Replicate continues polling after synchronous wait expiry.
OpenAI gains current Responses, Evaluation, URL-abort, and Live behavior, while
xAI aligns its Responses and batch surfaces with 5.0.4 and retains the
documented compatibility shim for the removed upstream chat surface.

Deliberate deferred boundaries are browser WebRTC and its client-permission
startup options, provider-backed Responses delegation, non-Live OpenAI
Realtime models, Google Realtime 3.8, the unported Z.AI and Typesafe AI
providers, and JavaScript-only Node/React runtime behavior.

The 2026-09-13 weekly pass audits all 50 tracked core and provider/product
rows: 48 published deltas plus the current `@ai-sdk/lmnt@3.0.36` and
`@ai-sdk/vercel@3.0.30` rows. Twenty-two package deltas contain portable Swift
behavior, one is already covered by the shared runtime, 24 are package-local
version/dependency propagation, and React remains out of scope.

Core work migrates Batch V4 from a language-model-owned text-only protocol to
a provider-owned text/image service with per-request model IDs, typed results,
cancel/list operations, and compatibility shims. Anthropic, OpenAI, and
Gateway expose text batches; Google and xAI expose text and image batches with
their distinct model restrictions. Image retryability, stream tool-choice
enforcement, rerank-index validation, ToolOutputError UI parts, video webhook
failure ordering, and strict GIF/BMP signatures are also current. MCP OAuth
discovery validates initial and redirected URLs, rejects unsafe private and
link-local targets, scopes loopback trust to configured local servers, and
does not redirect credential POSTs.

Provider work preserves OpenAI recursive schema compatibility, async tools,
programmatic denial, Foundry message discriminators, explicit empty-choice
errors, image 2.5 controls, web-search include capabilities, and patch-tool
finish reasons. Gateway warning forwarding and image retryability are current;
xAI supports mixed-model text/image batches. Bedrock endpoint resolution now
matches AWS environment precedence and partition suffixes, while Vertex
performs bounded credential-free tool-result downloads. Alibaba, DeepSeek,
Groq, and Moonshot retain reasoning across empty tool-call arrays; DeepSeek and
Mistral recognize current model families. Anthropic preserves input
transformations. ByteDance, KlingAI, and MiniMax align async video callback and
status lifecycles, and Gladia exposes expanded utterances plus provider
metadata.

The generic upstream callback `runtimeContext` for embeddings/reranking remains
deferred pending a typed Swift callback/telemetry design. Swift also keeps its
existing `downloadURL`/`AIDownloadError` contract instead of adding a second
public helper solely to mirror JavaScript `getTextFromDataUrl`. Exact registry
discovery now finds 86 live `@ai-sdk/*` names; 37 are untracked. Z.AI is the
only untracked provider, while the newly added
`@ai-sdk/harness-github-copilot` package is an out-of-scope agent adapter.

The 2026-09-06 weekly pass audits all 50 tracked core and provider/product
rows: 49 published deltas and the still-current `@ai-sdk/vercel@3.0.30` row.
Seventeen deltas required portable Swift behavior, 31 were already covered by
existing generic behavior or required only identity/baseline synchronization,
and `@ai-sdk/react` remains deliberately out of scope for this SwiftPM port.
Core work adds Files V4 capability discovery, upload, metadata retrieval,
streamed download, and deletion; strict array-output bounds with
source-compatible deferred constructor validation; setup plus post-start stream
retry parity; stronger UI message replacement, approval, and metadata
restoration behavior; embedding
result-count validation; and Batch tools, tool choice, metadata, and raw finish
reason preservation.

Provider work adds Google Batch as the fifth durable batch adapter, including
strict request-key validation and thought-signature round trips; validates the
OpenAI Batch outer response envelope; preserves xAI raw finish reasons through
the batch facade; expands Bedrock structured-output, citation, sanitization,
and replay behavior; tightens Anthropic options, Azure URL normalization, and
media polling redirects; and advances MCP protocol, annotation,
structured-result, pagination, and OAuth parity. Google
Interactions now preserves response history, tool and reasoning items,
compaction state, provider references, media resolution, and system
instructions. Open Responses, OpenAI, and OpenAI-compatible adapters also gain
their current request-validation, model-filtering, transcription, image, and
response-handling deltas. Exact per-package dispositions and upstream evidence
are recorded in `Docs/UpstreamPackageDiffAudit.md` and
`Docs/FreshUpstreamTestDiffAudit.md`.

The 2026-08-31 weekly pass advances 49 of the 50 tracked provider/core rows;
`@ai-sdk/vercel@3.0.30` remains current. Portable core work adds per-call image
results, UTF-8 embedding byte budgets, Batch V4 completion webhooks and full
content/count preservation, typed provider stream errors, approval reasons and
signed persisted-call revalidation, model-visible invalid approval results,
and structured-output finish handling. Provider work covers Alibaba WAN 3,
Bedrock inference-profile/reasoning/guardrail/usage behavior, richer Anthropic
Batch, Baseten/DeepInfra/TogetherAI structured output, ByteDance last-frame
metadata, Cohere/Mistral raw usage, current DeepSeek options and metadata,
Groq reasoning/usage, Hugging Face stream errors, MCP pagination/OAuth
hardening, MiniMax video tiers, Mistral prompt cache affinity, Open Responses
reasoning summaries, OpenAI request/replay/batch fixes, generic compatible
array content and reasoning disablement, Perplexity usage, Prodia warnings,
Gateway callbacks/count validation, and xAI Responses Batch/web-search/ID
handling, including malformed known-event errors and item-local batch failures.
Google and Vertex embedding preflight limits now match the published 100-input,
250-input, and one-input Gemini multimodal contracts.

The same pass keeps scope boundaries explicit. Google Batch, Gemini 3.5 unary
and live transcription, current Google safety/usage/request changes, the shared
Vertex additions, and the broad Moonshot V1/Kimi option/media/metadata delta
are audited but deferred to dedicated provider passes. Open Responses'
experimental extension codec registry and lossless custom-event replay still
need a public Swift design. Body-read `URLError` retryability,
parsed stream-end output, and active UI parts were already covered. Typed
UI-tool schema conversion, automatic denied-chat submission/outcomes,
byte-array approval secrets, true image request splitting/per-call metadata,
and cost aggregation across split Gateway calls remain broader core/media
gaps. `@ai-sdk/zai` needs its own factory, auth/base URL, chat options,
warnings/errors, media conversion, registry/capability row, and focused tests
before it can be represented.

The 2026-08-24 weekly pass advances 45 provider/product baselines plus `ai`,
`@ai-sdk/provider-utils`, and `@ai-sdk/react`; `@ai-sdk/provider` and
`@ai-sdk/vercel` remain current. Portable changes cover empty tool-call IDs,
Bedrock redacted reasoning and modeled stream failures, Cerebras options,
Deepgram 3.1 audio behavior, DeepSeek V4 vision/files, Gateway Batch V4,
ordered mixed batch results, webhook-aware async video, Tako Search, and
Gateway streaming transcription/token minting, Google local schema references and
Gemini 3.7+ reasoning floors, MCP unsuccessful POST/SSE handling, fragmented
Mistral tool calls, OpenAI Responses parallel wrappers, OpenAI-compatible
video/thought-signature/truncated-stream/image-usage behavior, and xAI image
moderation failures. Core changes add direct async-video start/status calls,
safer tool execution and structured streams, and stable text/reasoning part
identity. Google and Vertex Imagen factories remain available for source and
runtime compatibility despite upstream shutdown removal; removing that public
surface needs a deprecation cycle.

The 2026-08-19 focused follow-up adds Fish Audio 3.0.5 speech/transcription and
GMI Cloud 3.0.2 chat as complete provider verticals. It also ports Anthropic's
deferred programmatic-result replay; retry-covering, abort-aware structured
stream timeouts that remain active through client tool execution and typed
output streams; Batch V4 with Anthropic Messages Batch and OpenAI Responses
Batch; async Video V4 with Black Forest Labs and Fal, including native Fal
webhooks and core count splitting; Cartesia Ink 2 streaming transcription; and
provider-neutral Realtime V4 sessions with xAI as the first full adapter.
Shared download handling validates every redirect before following it and
strips provider credentials on cross-origin hops. Open Responses
provider-defined tools were rechecked and are not a Swift gap: upstream 2.0.28
intentionally warns and drops them.

The same follow-up advances 14 newly published patch baselines. Portable
changes include Fireworks JSON Schema structured output, the Gemini 3.7 Flash
`low` thinking floor, OpenAI 4.0.43 Responses `allowedTools` plus the
`computer` tool, MCP 2.0.33 protocol/OAuth hardening, and Bedrock EventStream
failure/EOF parity. OpenAI-compatible raw usage preservation already covers
its 3.0.31 delta; the remaining patch releases are dependency, version, or
forward-compatible model-ID propagation. Exact decisions are in
`Docs/UpstreamPackageDiffAudit.md`.

The 2026-08-17 weekly pass advances 43 provider baselines, the MCP product
baseline, and three changed core snapshots to current npm releases;
`@ai-sdk/provider@4.0.7` remains current. Portable changes cover array-schema
definitions and chat start status, Alibaba and Anthropic multi-turn replay,
Google schemas/errors/strict tools, Vertex Chirp 3 HD speech, scoped MCP OAuth,
Moonshot's owned chat/MFJS behavior, Open Responses and OpenAI continuation,
Gateway errors, and xAI Responses/video/speech capabilities. Exact
package-by-package decisions are recorded in
`Docs/UpstreamPackageDiffAudit.md`.

The 2026-08-10 weekly pass advances all 44 provider/product package baselines
and all four core snapshots to current npm releases. Portable deltas cover
streamed tool-call identity/finalization, default instructions, agent and chat
cancellation settings, Baseten HTTP embeddings and usage, Bedrock empty-message
filtering, Anthropic advisor/stream/replay behavior, MiniMax H3 aspect ratios,
OpenAI-compatible usage, OpenAI Responses correlation/serialization, and FLUX
3 video through the existing unary model contract. Exact per-package decisions
are recorded in `Docs/UpstreamPackageDiffAudit.md`.

The 2026-08-12 transport correction replaces buffered replay in every
streaming-capable built-in language provider with incremental SSE or Amazon
EventStream parsing. It also unifies MCP SSE parsing, validates Bedrock frame
lengths and CRCs, preserves typed non-success HTTP errors before the first
part, and wires consumer termination and aborts through to URLSession. Prodia
and the protocol-default stream remain explicitly unary/simulated.

The 2026-08-13 semantic-stream correction removes paired legacy and part-aware
deltas from built-in providers, normalizes legacy-only custom model streams at
the high-level boundary, closes content lifecycles deterministically, and
defines one built-in terminal outcome per logical response. Cross-surface regressions
cover text and reasoning collection, structured output, UI reduction, tool
loops, in-band errors, thrown failures, and provider terminal behavior.

Exact registry-prefix discovery on 2026-09-13 finds 86 live `@ai-sdk/*`
packages. Swift represents every provider-classified package except
`@ai-sdk/zai@3.0.10`. Of the 37 untracked scoped packages, the other 36 are framework adapters,
harness/sandbox/workflow products, UI bindings, telemetry or development
tooling rather than provider model packages; they need separate product
decisions and shared runtime foundations instead of automatic provider ports.

Do not reopen a provider just because it might have drifted. Reopen it only when
one of these is true:

- npm publishes a newer tracked package version and the port intentionally syncs
  it;
- upstream adds a provider-facing package that SwiftAISDK decides to track;
- a focused test, live smoke test, or user bug report identifies a concrete
  behavior mismatch;
- the shared Swift core contract changes in a way that affects the provider;
- an out-of-scope difference becomes an in-scope product decision.

## Active Product Gaps

| Priority | Gap | Next action |
| --- | --- | --- |
| P0 | Completion evidence can drift as npm packages and upstream tests change. | Before release, rerun package discovery, regenerate upstream inventory, compare ledgers, run full `swift test`, and record the audit. |
| P0 | Live verification is representative, not exhaustive. | Add opt-in live smoke only for distinct transport families or concrete production risks. Keep it disabled by default. |
| P1 | `@ai-sdk/zai@3.0.15` is a published provider and is not represented in Swift. | Port one complete Z.AI language vertical: factory/auth/base URL, current chat options and warnings, structured errors, media conversion, registry/capability evidence, focused tests, and public docs. |
| P1 | `@ai-sdk/typesafe-ai@3.0.4` is a newly published evaluation-only provider and is not represented in Swift. | Reuse the completed Evaluation V4 contract to port the Typesafe AI factory/auth/base URL, Choice/Score/Boolean request and answer mapping, rounding/confidence/usage metadata, validation/errors, registry evidence, tests, and docs as one vertical. |
| P1 | `URLSessionTransport` currently adapts `URLSession.AsyncBytes` into one `Data` value per byte. This preserves minimum latency and correct cancellation, but adds allocation overhead and offers no demand-aware backpressure. | Introduce a cancelable, demand-driven `AIHTTPBody` sequence backed by a delegate-owned `URLSession`, with bounded lossless buffering and explicit high/low watermarks. Keep the injected-session compatibility path until delegate, authentication, cache, metrics, and lifecycle semantics can be preserved. |
| P1 | xAI realtime and OpenAI Live server WebSocket are represented, but browser WebRTC/client permissions, provider-backed Responses delegation, non-Live OpenAI Realtime, Google Realtime 3.8, ElevenLabs realtime STT, and streaming translation remain deferred. | Extend `AIRealtimeModelV4` one complete transport/provider vertical at a time; do not advertise browser or delegation modes until their native lifecycle is implemented and tested. |
| P1 | Batch V4 has Anthropic, OpenAI Responses, Gateway, Google, and xAI adapters. Async Video V4 has Black Forest Labs, Fal, ByteDance, and Gateway adapters, but other capable providers still use unary or internal-polling paths. | Migrate additional batch/video providers incrementally when persisted operation state, native webhook behavior, and provider-specific cancellation semantics can be translated with focused tests. |
| P1 | `@ai-sdk/provider-utils@5.0.45` retains resolver-backed DNS address pinning for validated downloads; Swift validates literal/private hosts and every redirect and removes provider credentials across origins, but does not pin the resolved address. | Add resolver-aware connection pinning at the transport layer before claiming DNS-rebinding parity. |
| P1 | Upstream preserves repeated tool-call IDs across explicit UI stream steps; Swift stream parts do not expose step boundaries. | Add a public step-boundary representation, then scope reducer tool-part identity to the active step with backwards lookup for late results. |
| P1 | Provider option ergonomics are harder to discover than the core facade. | Add compact provider option examples to docs-site for non-obvious schemas and Swift differences. |
| P1 | Tooling is broad but can be more polished. | Improve validation diagnostics, typed result/error surfaces, and provider-defined tool helper docs. |
| P1 | Structured output works, but schema ecosystem parity is intentionally Swift-native. `Output.array` construction remains nonthrowing for source compatibility; invalid bounds are rejected at execution before model work begins. | Keep improving schema adapter ergonomics, repair telemetry, provider-specific structured-output examples, and docs. |
| P1 | UI/agent scope should stay explicit. | Document whether each upstream UI/agent helper is ported, Swift-native, or out of scope before adding adjacent APIs. |

## Live Verification

Default tests use mock transports. Optional live smoke tests are disabled by
default because they require real credentials and can spend money:

```sh
LIVE_AI_TESTS=1 swift test --filter LiveProviderSmoke
```

The live suite reads provider-specific environment variables such as
`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `DEEPSEEK_API_KEY`,
`ASSEMBLYAI_API_KEY`, `ELEVENLABS_API_KEY`, `CARTESIA_API_KEY`, and
`OPENAI_COMPATIBLE_API_KEY`. See `Docs/ProviderCapabilityMatrix.md` for the
current live-smoke notes and model override variables.

Deterministic loopback transport tests gate response EOF and verify that a
semantic delta arrives first, so incremental delivery and network cancellation
do not depend on paid live credentials.

## Release Readiness Checklist

Before calling a porting round release-ready:

- `Scripts/check-upstream-versions.js --discover-packages --discover-kind provider,adapter,core` has been reviewed.
- Changed tracked packages have old-vs-new upstream diffs inspected.
- `Scripts/update-upstream-test-inventory.js` has refreshed
  `Docs/UpstreamTestInventory.md` when upstream tests are part of the pass.
- `Docs/ProviderVersionLedger.md` matches the package versions actually used.
- `Docs/ProviderCapabilityMatrix.md` matches `AIProviderCapabilities`.
- Public docs in README/docs-site match the behavior users now see.
- Focused Swift tests and full `swift test` pass, or skipped verification is
  explicitly recorded.
