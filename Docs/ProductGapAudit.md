# Product Gap Audit

Snapshot date: 2026-06-03

This document is the product-level gap list for SwiftAISDK. It should stay short
and decision-oriented. Historical provider progress belongs in tests, the
capability matrix, `Docs/ProviderVersionLedger.md`, and `Docs/UpstreamSync.md`;
this file should describe what still prevents the package from feeling like a
complete Swift equivalent of the provider-facing Vercel AI SDK.

## Current Product Shape

SwiftAISDK is now more than a set of low-level provider models:

- `AI.swift` exposes product-level facade calls for text, objects, embeddings,
  images, video, speech, transcription, reranking, file uploads, and skill
  uploads.
- `Core.swift` has v4-shaped language request fields, stream lifecycle parts,
  provider metadata, response metadata, warnings, abort signals, and richer
  token usage.
- `ProviderRegistry.swift` and `ProviderCapabilityMatrix.swift` expose broad
  provider coverage across official `@ai-sdk/*` model-provider packages.
- `Docs/ProviderCapabilityMatrix.md` is generated from
  `AIProviderCapabilities` and guarded by tests.
- `Docs/UpstreamSync.md` contains the provider sync workflow, and
  `Docs/ProviderVersionLedger.md` records npm package version baselines for
  future upstream diffs.

The main product risk is no longer "there is no facade", "there is no core v4
shape", or "provider parity is untracked". Those foundations exist, and the
provider deep-pass queue is empty as of the current snapshot. The current risk is
that live verification and user-facing workflows are still thinner than the mock
test surface.

## Active Gaps

| Priority | Gap | Current evidence | Next concrete pass |
| --- | --- | --- | --- |
| P0 | Final completion evidence must stay explicit. | `Docs/ProviderSyncStatus.md` marks the provider deep-pass queue empty, and the current npm-search provider packages all map to Swift evidence. This can drift when npm adds packages or versions change. | Before declaring a release-ready state, rerun npm discovery, compare it to `Docs/ProviderVersionLedger.md` and `AIProviderCapabilities`, run live smoke plus full `swift test`, and record the audit result. |
| P0 | Live verification is intentionally representative, not exhaustive. | `LiveProviderSmokeTests.swift` covers OpenAI, Anthropic, Gemini, and DeepSeek generate/stream/tool-loop calls with real keys, OpenAI-compatible generate/stream/tool-loop/object calls, AssemblyAI transcription, ElevenLabs speech/transcription, plus representative OpenAI and Gemini embeddings. Most providers are validated through mock transports because media/audio/video live calls are slower, paid, and account-specific. | Add opt-in live smoke slices only when they prove a distinct transport family or a reported production risk: native embeddings/reranking, image/video, files/skills. Keep them cheap and disabled by default. |
| P1 | Provider option ergonomics are still hard to discover. | Provider-specific options exist through `providerOptions` and `extraBody`, but users need to inspect tests or upstream docs to know the valid namespace and fields. | Add per-provider option examples only where Swift differs or where schemas are non-obvious. Prefer compact examples linked from the capability matrix instead of long README sections. |
| P1 | Tooling is functionally broad but not fully product-polished. | `AITool`, dynamic tools, tool loops, approval hooks, MCP tools, and provider-defined tools exist, but typed validation errors and provider-native multimodal `modelOutput` handling still need tightening. | Do a tool-product pass: typed validation diagnostics, richer tool result/error surfaces, provider-defined tool adapters as first-class Swift helpers, and non-OpenAI provider-executed approval mapping where supported upstream. |
| P1 | Object generation has a solid first product surface but still lacks deeper schema ecosystem parity. | `generateObject`, `streamObject`, array/enum/JSON strategies, schema adapters, JSON instructions, callbacks, and validation exist. Provider-specific structured-output behavior is still uneven. | Add provider-by-provider structured-output checks and improve schema adapter ergonomics, repair telemetry, and examples. |
| P1 | UI stream and agent surfaces are not intentionally scoped yet. | The provider-facing and facade layers are in scope; upstream also has UI streams, agent helpers, and frontend integration packages that are not represented as Swift product decisions. | Decide explicitly whether SwiftAISDK ports these surfaces, offers Swift-native alternatives, or declares them out of scope. Document that decision before implementing adjacent APIs. |
| P2 | Documentation is split between useful references and stale narrative. | Capability matrix and upstream sync are useful; this audit had drifted into changelog form before this cleanup. | Keep this file as an active gap list. Move evidence to tests/matrix/sync docs, and update this audit only when priorities change. |

## Not Current Gaps

These used to be major concerns, but they are now foundations to build on rather
than open product gaps:

- Direct facade wrappers exist for the core model families, including media,
  audio, reranking, files, and skills.
- Retry, timeout, cancellation, abort-signal propagation, warning logging, and
  telemetry have first-class Swift surfaces.
- The core language request and stream contracts have v4-shaped fields and
  lifecycle parts.
- Object generation and streaming are present at product level, including typed
  decoding, partial JSON, arrays, enums, no-schema JSON, callbacks, and
  validation errors.
- The provider capability matrix is generated from source and protected by a
  drift test.

If one of these areas regresses, file a concrete bug against the implementation
or tests instead of re-adding it here as a broad "missing layer" statement.

## Evidence Map

Use these files when deciding whether a gap is still real:

| Area | Where to look |
| --- | --- |
| Facade calls, retries, tool loops, object generation, telemetry | `Sources/SwiftAISDK/AI.swift`, `Tests/SwiftAISDKTests/AIFacadeTests.swift`, `Tests/SwiftAISDKTests/AIObjectFacadeTests.swift`, `Tests/SwiftAISDKTests/WarningLoggingTests.swift` |
| Core request/result/stream contract | `Sources/SwiftAISDK/Core.swift`, `Tests/SwiftAISDKTests/CoreContractTests.swift`, `Tests/SwiftAISDKTests/RawChunkStreamTests.swift` |
| Provider inventory and generated docs | `Sources/SwiftAISDK/Providers/ProviderCapabilityMatrix.swift`, `Docs/ProviderCapabilityMatrix.md`, `Tests/SwiftAISDKTests/ProviderCapabilityMatrixTests.swift` |
| Provider sync process and npm version baselines | `Docs/UpstreamSync.md`, `Docs/ProviderVersionLedger.md` |
| Provider-specific parity | Closest provider test file under `Tests/SwiftAISDKTests/*ProviderTests.swift`, or the evidence file listed in `Docs/ProviderVersionLedger.md` and `Docs/ProviderCapabilityMatrix.md` |
| Live smoke coverage | `Tests/SwiftAISDKTests/LiveProviderSmokeTests.swift` |
| MCP bridge | `Sources/SwiftAISDK/MCPClient.swift`, `Sources/SwiftAISDK/MCPOAuth.swift`, `Sources/SwiftAISDK/MCPStdioTransport.swift`, `Tests/SwiftAISDKTests/MCP*Tests.swift` |

## Next Rounds

1. **Final completion audit round.**
   Rerun npm discovery, compare provider-like packages to
   `Docs/ProviderVersionLedger.md` and `AIProviderCapabilities`, run live smoke
   with available keys, run full `swift test`, and record the result in
   `Docs/ProviderSyncStatus.md`.

2. **Targeted provider sync round, only when reopened.**
   When npm publishes a provider update or a concrete bug appears, take one
   large provider or 2-3 related small providers, read current upstream, close
   request/response/stream/tool gaps, add focused tests, then commit and push the
   whole batch.

3. **Live smoke matrix round.**
   Add opt-in live tests behind `LIVE_AI_TESTS=1` and provider-specific env
   checks. Start with cheap text/embedding providers, then media/audio/video
   providers. Prefer skipping unavailable credentials over failing the whole
   live suite.

4. **Provider option examples round.**
   Add compact examples for providers with non-trivial `providerOptions`
   schemas. Link from the capability matrix or a short cookbook so users do not
   need to reverse-engineer test bodies.

5. **Tool product round.**
   Improve validation diagnostics and typed result/error surfaces. Promote
   provider-defined tool helpers where they currently feel like raw JSON escape
   hatches.

6. **Scope decision round for UI streams and agents.**
   Audit upstream UI/agent packages and decide whether SwiftAISDK should port
   them, expose a Swift-native shape, or explicitly defer them.

Provider micro-parity remains important, but it should now run inside this
product framing: every provider pass should either reduce one active product
gap or explicitly document why the remaining difference is out of scope.
