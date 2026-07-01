# Agent Porting Guide

This is the operational guide for agents porting Vercel AI SDK behavior into
SwiftAISDK. The rule is simple: update runtime behavior, tests, public docs, and
status docs together.

## Sources Of Truth

| Artifact | Role |
| --- | --- |
| `Docs/PortingStatus.md` | Current product status, active gaps, release-readiness checklist, and reopen rules. |
| `Docs/ProviderVersionLedger.md` | npm package baselines and Swift evidence index. |
| `Docs/CoreV6Parity.md` | Core `ai`, `@ai-sdk/provider`, `@ai-sdk/provider-utils`, and UI parity decisions. |
| `Docs/ProviderCapabilityMatrix.md` | Generated provider capability table. |
| `Sources/SwiftAISDK/Providers/ProviderCapabilityMatrix.swift` | Machine-readable provider inventory. |
| `Docs/UpstreamTestInventory.md` | Generated upstream test/spec inventory. |
| `README.md` and `docs-site` | Public product documentation. |
| `AGENTS.md` | Repository-level agent rules. |

## Standard Porting Flow

1. Pick a narrow scope: one large provider, one core surface, or a few related
   small providers.
2. Check the current baseline:

   ```sh
   Scripts/check-upstream-versions.js --all
   Scripts/check-upstream-versions.js --discover-packages --discover-kind provider,adapter,core
   ```

3. For changed packages, prepare upstream tarball diffs:

   ```sh
   Scripts/check-upstream-versions.js --package @ai-sdk/openai --prepare-diffs
   Scripts/check-upstream-versions.js --prepare-diffs
   ```

4. Read the generated `summary.md` and `upstream.diff` before editing Swift.
5. Read upstream tests before implementation files. Prefer upstream tests as the
   source of truth for observable behavior.
6. Patch the closest Swift implementation and keep the local architecture
   intact.
7. Add or update focused Swift tests.
8. Update public docs for changed user-facing behavior.
9. Update ledgers/status docs for changed baselines, capabilities, or known
   gaps.
10. Run focused tests, then full verification.

Do not start a new batch until the current batch is implemented, tested,
documented, and committed/pushed if the user asked for that.

## Upstream Reading Order

For a provider package, inspect in this order:

| Open first | Why |
| --- | --- |
| `*.test.ts`, `*.test-d.ts`, `*.spec.ts` | Request bodies, URLs, warnings, aliases, stream lifecycle, unsupported cases, and exact result expectations. |
| `index.ts` | Public exports, names, aliases, tools, and factory shape. |
| `*provider.ts` | Provider ID, base URL, auth, headers, env vars, and model routing. |
| `*language-model*.ts` | Prompt conversion, request body, parsing, tool calls, and streaming. |
| `*embedding*.ts`, `*rerank*.ts` | Batch limits, body shape, usage, and provider options. |
| `*image*.ts`, `*video*.ts`, `*speech*.ts`, `*transcription*.ts` | Media/audio routes, multipart fields, polling, downloads, warnings, and metadata. |
| `*tool*.ts` | Provider-defined tool names, beta headers, schema mapping, and result conversion. |
| Shared helpers under `packages/provider-utils` | Only when the provider imports helper behavior directly. |

If upstream tests and implementation disagree, mirror runtime behavior and add a
Swift test that documents the decision.

## Swift Translation Rules

- Keep provider IDs, factory names, aliases, default base URLs, env vars, auth
  headers, user-agent suffixes, and unsupported-model behavior aligned with
  upstream.
- Prefer typed Swift settings and provider option structs where upstream has a
  schema. Keep `extraBody` as the explicit low-level escape hatch.
- Build request bodies with structured `JSONValue`; avoid string assembly unless
  a provider API requires encoded payloads.
- Preserve text, reasoning, tool calls, sources, files, usage, finish reasons,
  response/request metadata, provider metadata, and raw chunks where upstream
  exposes them.
- Streams should emit lifecycle parts equivalent to upstream where Swift exposes
  the surface.
- Abort signals must flow through direct requests, streams, uploads, downloads,
  polling, retries, and retry sleeps.
- Provider failures should preserve status, headers, body details, and
  retryability through the shared error path.
- JS-only runtime behavior, TypeScript inference helpers, framework hooks,
  browser/Node response plumbing, and codemods are out of scope unless
  SwiftAISDK adds a matching product surface.

## Test Porting Requirements

Every upstream test file that maps to an in-scope Swift surface should end in
one of these states:

- `ported`: behavior is covered by a Swift test.
- `covered-by-existing-platform-test`: only for Swift platform behavior already
  proven by local tests.
- `out-of-scope`: JS/browser/Node/framework/codemod behavior or product surface
  SwiftAISDK does not expose.
- `blocked`: behavior requires a Swift API/product decision.

Translate behavior into idiomatic Swift tests. Do not copy JS structure
mechanically. Preserve Swift API differences, Foundation networking behavior,
Swift concurrency, typed errors, and existing test helpers.

Keep these local test categories even when upstream parity tests exist:

- live smoke tests behind `LIVE_AI_TESTS=1`;
- platform integration tests for stdio/process, Foundation URL handling,
  multipart encoding, Swift cancellation, and OS availability;
- Swift-only public API tests for typed `Codable` output, `Sendable` boundaries,
  provider capability inventory, and Swift metadata wrappers;
- shared test fixtures that are genuinely reused.

When adding translated tests:

- Use focused file names that describe the upstream behavior area.
- Prefer reviewable files under roughly 300-400 lines.
- Split by upstream `describe` block or behavior area, not by mechanical
  `Part1` / `Part2` names.
- Do not delete legacy local assertions until the corresponding upstream file
  has been inspected and classified.
- Record skipped upstream behavior in status/docs when the skip is a product
  decision, not merely an implementation TODO.

Refresh the upstream test inventory when the pass depends on current upstream
test lists:

```sh
Scripts/update-upstream-test-inventory.js
```

## Public Documentation Requirements

Public docs are part of the port. Update README/docs-site when a change affects:

- public API names or overloads;
- provider setup, env vars, base URLs, auth, aliases, or supported capabilities;
- request options, provider options, warnings, or unsupported settings;
- response result shapes, stream parts, metadata, usage, or errors;
- examples users are likely to copy;
- known limitations, Swift-specific differences, or troubleshooting steps.

Use `Docs/ProductDocumentation.md` for the docs quality bar and verification
commands.

## Verification

Run a focused filter that covers the changed package or core area:

```sh
swift test --filter 'OpenAI|OpenAIResponses|ProviderCapabilityMatrix'
```

Then run:

```sh
swift test
```

For docs-site changes:

```sh
npm ci --prefix docs-site
npm --prefix docs-site run build
```

Optional live smoke:

```sh
LIVE_AI_TESTS=1 swift test --filter LiveProviderSmoke
```

## Completion Summary

When finishing a porting pass, summarize:

- upstream package versions or commit inspected;
- Swift runtime behavior changed;
- upstream tests translated or classified out of scope;
- public docs updated;
- status/ledger docs updated;
- exact test commands and results.

