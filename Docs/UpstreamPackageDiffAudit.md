# Upstream Package Diff Audit

Snapshot date: 2026-08-01

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

## Tracked Package Results

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

## Verification

| Check | Result |
| --- | --- |
| `node Scripts/check-upstream-versions.js --all --json` | Passed after the ledger update: 47 tracked packages, zero outdated rows, and zero registry errors. |
| `node Scripts/check-upstream-versions.js --discover-packages --all --json` | Passed: 76 live `@ai-sdk/*` packages, 43 classified model providers, and `@ai-sdk/minimax@3.0.0` as the only untracked model provider. The registry-only packages without descriptions resolve as `@ai-sdk/specification@0.0.0` and `@ai-sdk/test-server@2.0.1`. |
| `node Scripts/check-upstream-versions.js --all --prepare-diffs --work-dir /tmp/ai-sdk-port-upstream-diffs-20260801.KTahaI` | Before updating the ledger, produced 47 separate `upstream.diff`/`summary.md` pairs from 94 published npm tarballs. |
| `swift test --filter providerCapabilityMatrixDocumentationMatchesGeneratedMarkdown` | Passed: 1 focused generated-documentation parity test. |
| `swift test` | Passed after the final MCP, KlingAI, and Mistral review fixes: 2,220 tests in 3 suites. |
| `npm ci --prefix docs-site` and `npm --prefix docs-site run build` | Passed; the docs build generated 84 pages. |
| `git diff --check` | Passed. |

## Registry Discovery

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
