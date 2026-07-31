# Porting Status

Snapshot date: 2026-08-01

SwiftAISDK currently ports the provider-facing parts of Vercel AI SDK into a
SwiftPM library. The package has a broad Swift-native facade, provider registry,
provider implementations, generated provider capability docs, upstream-shaped
parity tests, and a static documentation site.

This file is the readable status page. It replaces the older provider-progress
journals and product-gap checklist. Use the ledgers and generated inventories
for exact evidence.

## Current Shape

- The `AI` facade covers text, streaming text, structured output, embeddings,
  images, video, speech, transcription, reranking, file uploads, skill uploads,
  middleware, telemetry, warnings, retries, aborts, tools, approvals, MCP tools,
  UI messages, chat sessions, and agent helpers.
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

Provider and core package version baselines were checked against npm registry
metadata and published tarballs on 2026-08-01. The per-package decisions are
recorded in `Docs/UpstreamPackageDiffAudit.md`.

## Provider State

The 44 tracked provider/product packages in `Docs/ProviderVersionLedger.md`
have Swift evidence in implementation files and focused tests. The 43 model
providers are represented in `Docs/ProviderCapabilityMatrix.md`; MCP is tracked
separately as a product package without a model-capability row. The current pass
audited the published package deltas and ported the applicable provider/core
behavior; the remaining architectural differences are recorded below.

The focused MiniMax follow-up ports the originally requested
`@ai-sdk/minimax@3.0.0` behavior while recording the current `3.0.1` baseline;
the two versions have identical provider source and differ only in version and
dependency propagation. Exact npm registry discovery now finds 43 model-provider
packages with no untracked provider. Registry discovery still finds the
non-provider `@ai-sdk/code-mode@1.0.2`; it is a QuickJS-backed JavaScript tool
runtime rather than a provider-matrix entry.

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
| P1 | Streaming transcription, realtime models, and speech translation from Cartesia, ElevenLabs, Google, and OpenAI are not represented by current Swift protocols. | Design one reusable duplex WebSocket/audio transport and lifecycle surface, then port provider adapters as vertical slices. |
| P1 | Current `ai@7.0.44` supports per-step first-content and semantic inter-chunk timeouts; Swift exposes only a total stream timeout. | Design a structured timeout configuration and per-step timer lifecycle before adding `firstChunkMs`/`chunkMs` parity. |
| P1 | `prepareStep` call-setting overrides and generic provider tool-callers have no faithful shared Swift contract. | Add isolated per-step setting overlays and late-bound provider tool-caller routing before enabling provider-specific automatic callers. |
| P1 | Provider-utils now resolves and pins DNS addresses for validated downloads; Swift validates literal/private hosts and every redirect but does not pin the resolved address. | Add resolver-aware connection pinning at the transport layer before claiming DNS-rebinding parity. |
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
