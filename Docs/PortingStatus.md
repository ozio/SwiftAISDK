# Porting Status

Snapshot date: 2026-08-24

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
  streaming transcription, reranking, file uploads, skill uploads, middleware,
  telemetry, warnings, retries, aborts, tools, approvals, MCP tools, UI
  messages, chat sessions, agent helpers, and provider-neutral realtime
  sessions.
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
on 2026-08-24. The packages changed by this weekly pass were reviewed from
their exact published tarballs; per-package decisions are recorded in
`Docs/UpstreamPackageDiffAudit.md`.

## Provider State

The 46 tracked provider/product packages in `Docs/ProviderVersionLedger.md`
have Swift evidence in implementation files and focused tests. All 45 model
providers are represented in `Docs/ProviderCapabilityMatrix.md`; MCP is tracked
separately as a product package without a model-capability row. The current pass
audited the published package deltas and ported the applicable provider/core
behavior; the remaining architectural differences are recorded below.

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

Exact registry-prefix discovery on 2026-08-24 finds 81 live `@ai-sdk/*`
packages and 45 model providers. All 45 model providers are now represented.
No new unported model provider appeared. The other 32 untracked packages are
framework adapters, harness/sandbox/workflow products, UI bindings, telemetry
or development tooling rather than provider model packages; they need separate
product decisions and shared runtime foundations instead of automatic provider
ports.

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
| P1 | `URLSessionTransport` currently adapts `URLSession.AsyncBytes` into one `Data` value per byte. This preserves minimum latency and correct cancellation, but adds allocation overhead and offers no demand-aware backpressure. | Introduce a cancelable, demand-driven `AIHTTPBody` sequence backed by a delegate-owned `URLSession`, with bounded lossless buffering and explicit high/low watermarks. Keep the injected-session compatibility path until delegate, authentication, cache, metrics, and lifecycle semantics can be preserved. |
| P1 | Duplex audio, Cartesia Ink 2 and Gateway streaming transcription, provider-neutral Realtime V4 sessions, and xAI realtime are represented, but ElevenLabs realtime STT, Google/OpenAI streaming translation, and full non-xAI speech-session adapters are not. | Reuse `AIDuplexWebSocketTransport`, `AIRealtimeModelV4`, and the streaming-audio lifecycle for the next provider verticals without hiding provider-specific session semantics. |
| P1 | Batch V4 has Anthropic, OpenAI Responses, and Gateway adapters; async Video V4 has Black Forest Labs, Fal, ByteDance, and Gateway adapters, but other capable providers still use unary or internal-polling paths. | Migrate additional batch/video providers incrementally when persisted operation state, native webhook behavior, and provider-specific cancellation semantics can be translated with focused tests. |
| P1 | `prepareStep` call-setting overrides and generic provider tool-callers across generate, stream, and agent orchestration have no faithful shared Swift contract. | Add isolated per-step setting overlays and late-bound provider tool-caller routing before enabling provider-specific automatic callers. |
| P1 | `@ai-sdk/provider-utils@5.0.29` retains resolver-backed DNS address pinning for validated downloads; Swift validates literal/private hosts and every redirect and removes provider credentials across origins, but does not pin the resolved address. | Add resolver-aware connection pinning at the transport layer before claiming DNS-rebinding parity. |
| P1 | Upstream preserves repeated tool-call IDs across explicit UI stream steps; Swift stream parts do not expose step boundaries. | Add a public step-boundary representation, then scope reducer tool-part identity to the active step with backwards lookup for late results. |
| P1 | Provider option ergonomics are harder to discover than the core facade. | Add compact provider option examples to docs-site for non-obvious schemas and Swift differences. |
| P1 | Tooling is broad but can be more polished. | Improve validation diagnostics, typed result/error surfaces, and provider-defined tool helper docs. |
| P1 | Structured output works, but schema ecosystem parity is intentionally Swift-native. | Keep improving schema adapter ergonomics, repair telemetry, provider-specific structured-output examples, and docs. |
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
