# Upstream Sync Guide

This is the playbook for keeping SwiftAISDK aligned with the provider-facing
packages in Vercel AI SDK (`@ai-sdk/*`). Keep it short and operational: choose
one surface, compare against upstream, port the behavior, test it, update the
inventory, then commit and push.

For package versions, use `Docs/ProviderVersionLedger.md`. For product-level
priorities, use `Docs/ProductGapAudit.md`. For current provider inventory, use
`Sources/SwiftAISDK/Providers/ProviderCapabilityMatrix.swift` and the generated
`Docs/ProviderCapabilityMatrix.md`.

## Current Snapshot

- npm version baseline checked: 2026-06-03
- Version ledger: `Docs/ProviderVersionLedger.md`
- Upstream checkout path: `/tmp/vercel-ai-sdk-upstream`
- Last broad upstream commit used during the audit:

  ```text
  43e84c8e3 2026-06-01T13:12:00-07:00 Version Packages (canary) (#15748)
  ```

- Package product: library-only SwiftPM package (`SwiftAISDK`)
- Full verification command: `swift test`

Before a substantial provider pass, refresh either the npm package tarball or
the upstream checkout and record the exact version/commit used.

## Source Of Truth

| Artifact | Role | Update when |
| --- | --- | --- |
| `Sources/SwiftAISDK/Providers/ProviderRegistry.swift` | Public factories, aliases, auth, base URLs, and provider-level capability sets. | Factory names, auth, default URLs, aliases, or supported model families change. |
| `Sources/SwiftAISDK/Providers/ProviderCapabilityMatrix.swift` | Machine-readable provider inventory. | Provider capabilities, files, skills, or factories change. |
| `Docs/ProviderCapabilityMatrix.md` | Generated human provider/capability table. | Regenerate whenever `AIProviderCapabilities` changes. |
| `Docs/ProviderVersionLedger.md` | npm package version baseline and Swift evidence index. | A provider package version is checked or a provider pass changes evidence. |
| `Docs/ProductGapAudit.md` | Product-level priorities and active gaps. | A gap is closed, reprioritized, or newly discovered. |
| `Tests/SwiftAISDKTests/*` | Behavioral evidence. | Every provider or core behavior change. |
| `Tests/SwiftAISDKTests/LiveProviderSmokeTests.swift` | Opt-in real-provider smoke checks. | Representative live coverage changes. |

The matrix is the product inventory. A provider is not covered unless registry,
matrix, generated docs, and focused tests agree.

## Round Workflow

Run provider sync as one vertical provider pass at a time.

1. Pick exactly one provider package from `Docs/ProviderVersionLedger.md`, unless
   the change is truly cross-cutting.
2. Refresh the upstream source:

   ```sh
   npm view <package> version
   npm pack <package>@<version> --pack-destination /tmp
   ```

   Or, when the local checkout is the better source:

   ```sh
   git -C /tmp/vercel-ai-sdk-upstream pull --ff-only
   git -C /tmp/vercel-ai-sdk-upstream log -1 --format='%h %cI %s'
   ```

3. Read upstream tests before implementation files.
4. Compare factory/auth/base URL, model families, request body shape, warnings,
   provider option schemas, response metadata, provider metadata, usage, stream
   lifecycle, abort propagation, and unsupported-family behavior.
5. Patch the closest Swift provider/model files. Keep `providerOptions.<name>`
   typed and schema-shaped where upstream has a schema; keep `extraBody` as the
   explicit low-level escape hatch.
6. Add focused Swift tests in the closest split test file.
7. Run a narrow test filter, then `swift test`.
8. Update `AIProviderCapabilities` and regenerate
   `Docs/ProviderCapabilityMatrix.md` if coverage changed.
9. Update `Docs/ProviderVersionLedger.md` and this guide only when their facts
   changed.
10. Commit and push before moving to the next provider.

## Definition Of Done

A provider pass is complete only when the touched provider surface satisfies the
checks below or documents a concrete known gap:

- Public factory names, JS-style aliases, default model constructors, provider
  IDs, base URLs, environment variables, and auth/header behavior match
  upstream.
- Every upstream model surface exposed by the package is represented or
  explicitly out of scope: language, responses, embeddings, reranking, image,
  video, transcription, speech, files, and skills.
- Request preparation covers standard settings, provider options, deprecated
  option namespaces, structured outputs, provider-defined tools, tool choice,
  multipart fields, polling bodies, and unsupported-setting warnings.
- Generate and stream parsing preserve text, reasoning, tool calls, sources,
  files, usage, finish reasons, raw values, response/request metadata, provider
  metadata, and raw chunks where upstream exposes them.
- Streams emit v4 lifecycle parts where upstream does: stream start, text and
  reasoning start/delta/end, tool input start/delta/end, sources, errors, and
  finish metadata.
- Abort signals are forwarded through direct requests, stream requests,
  multipart uploads, submit/poll loops, downloads, and retry sleeps.
- Error mapping preserves provider status, headers, and body details through the
  shared HTTP error path.
- Focused Swift tests cover request shape, warnings, response parsing, stream
  lifecycle, metadata, abort propagation, and at least one unsupported-model or
  invalid-response case where upstream has equivalent behavior.
- Low-cost live smoke coverage is added or updated when usable credentials are
  available.

## Upstream Reading Order

Look in the unpacked npm tarball or in
`/tmp/vercel-ai-sdk-upstream/packages/<provider>/src`.

| Open first | Why |
| --- | --- |
| `*.test.ts`, `*.test-d.ts`, `*.spec.ts` | Exact request bodies, URLs, warnings, aliases, and unsupported cases. |
| `index.ts` | Public names, aliases, exported tools, and default factory. |
| `*provider.ts` | Provider ID, base URL, env vars, headers, and model routing. |
| `*language-model*.ts` | Chat/messages/responses body conversion, parsing, and streaming. |
| `*embedding*.ts` | Endpoint, batch limits, token usage, and provider options. |
| `*image*.ts` | Generation/editing body shape and output media parsing. |
| `*transcription*.ts` | Multipart fields, audio response shape, and timestamp options. |
| `*speech*.ts` | Audio format, voice defaults, and response bytes. |
| `*video*.ts` | Job creation, polling, status mapping, assets, and `n`/Swift `count` behavior. |
| `*tool*.ts` | Provider-defined tool names, beta headers, and schema mapping. |
| Shared helpers under `packages/provider-utils` | Only when the provider imports helper behavior directly. |

Prefer upstream tests as the source of truth. If tests and implementation
disagree, mirror runtime behavior and add a Swift test that documents the
decision.

## Useful Commands

Discover official provider packages:

```sh
npm search "@ai-sdk" --json --searchlimit=250 \
  | jq -r '.[].name' \
  | rg '^@ai-sdk/' \
  | sort
```

Show changed upstream package directories since a pin:

```sh
git -C /tmp/vercel-ai-sdk-upstream diff --name-only <old-pin>..HEAD -- packages \
  | rg '^packages/[^/]+/src/' \
  | cut -d/ -f2 \
  | sort -u
```

Find upstream factory/auth/model routing:

```sh
rg -n 'create|provider|baseURL|baseUrl|headers|apiKey|environmentVariableName|NoSuchModelError|new .*Model' \
  /tmp/vercel-ai-sdk-upstream/packages/<provider>/src
```

Find upstream request/stream/tool behavior:

```sh
rg -n 'prepare|convert|providerOptions|providerDefinedTool|tool_choice|stream|usage|finishReason|reasoning' \
  /tmp/vercel-ai-sdk-upstream/packages/<provider>/src
```

Find the matching Swift surface:

```sh
rg -n '<provider>|providerID|baseURL|extraBody|providerOptions' Sources Tests
```

## Swift Map

| Area | Files |
| --- | --- |
| Core protocols and request/response shapes | `Sources/SwiftAISDK/Core.swift` |
| AI facade, retries, tool loops, object generation, telemetry plumbing | `Sources/SwiftAISDK/AI.swift` |
| Middleware wrappers | `Sources/SwiftAISDK/Middleware.swift` |
| JSON and schema helpers | `Sources/SwiftAISDK/JSONValue.swift`, `Sources/SwiftAISDK/JSONParsing.swift`, `Sources/SwiftAISDK/JSONSchemaValidator.swift` |
| HTTP transport, multipart, SSE/EventStream parsing | `Sources/SwiftAISDK/HTTP.swift` |
| Public provider registry | `Sources/SwiftAISDK/Providers/ProviderRegistry.swift` |
| Provider inventory | `Sources/SwiftAISDK/Providers/ProviderCapabilityMatrix.swift`, `Docs/ProviderCapabilityMatrix.md` |
| Provider models | `Sources/SwiftAISDK/Models/*` |
| Files and skills clients | `Sources/SwiftAISDK/Models/FileClients.swift`, `Sources/SwiftAISDK/Models/OpenAISkills.swift` |
| MCP bridge | `Sources/SwiftAISDK/MCPClient.swift`, `Sources/SwiftAISDK/MCPOAuth.swift`, `Sources/SwiftAISDK/MCPStdioTransport.swift` |
| Tests | `Tests/SwiftAISDKTests/*.swift` |

Naming note: most model files follow `*Models.swift`, `*Tools.swift`, or
`*Skills.swift`, but `OpenAICompatible.swift`, `Anthropic.swift`, and
`GoogleGenerativeAI.swift` are intentionally broader historical groupings. Treat
those names as grouping choices, not as proof that a provider surface is
missing.

## Translation Rules

| Upstream concept | Swift rule |
| --- | --- |
| Factory spelling | Prefer idiomatic Swift casing, but keep public JS spellings such as `openai`, `xai`, `revai`, `moonshotai`, and `anthropicAws` when upstream exposes them. |
| Provider ID | Match upstream provider IDs, including capability suffixes such as `.chat`, `.responses`, `.embedding`, `.image`, `.files`, or `.skills`. |
| Settings | Extend `ProviderSettings` or the provider-specific settings type before adding ad hoc parameters. |
| Base URL | Preserve upstream defaults and env fallbacks; tests should assert the final URL. |
| Auth headers | Preserve header names, bearer/API-key prefixes, user-agent suffixes, and provider-specific custom-header override behavior. |
| Request body | Build structured `JSONValue` dictionaries; avoid string assembly except where the provider API requires encoded payloads. |
| Provider options | Read the upstream namespace (`openai`, `anthropic`, `google`, etc.), validate/strip typed options where upstream does, and avoid leaking provider-specific options into unrelated providers. |
| Raw escape hatch | Keep `extraBody` as explicit low-level passthrough; do not use it to hide typed provider behavior. |
| Tools | Keep provider-defined tool builders beside the provider. Preserve `modelOutput ?? result` for follow-up tool messages where the provider wire format can carry model-facing output. |
| Streaming | Reuse shared SSE/EventStream parsers where possible. Emit `.raw(...)` only when `includeRawChunks` is true. |
| Metadata | Populate `AIRequestMetadata`, `AIResponseMetadata`, and `providerMetadata` where upstream exposes equivalent data. Sanitize request metadata so auth headers and inline media bytes are not stored. |
| Warnings | Return upstream-style warnings when Swift exposes the ignored setting. Assert ignored settings do not leak into request bodies. |
| Downloads | Use `downloadURL(...)`/`validateDownloadURL(...)` for SDK-managed remote media/file fetches and preserve byte-limit behavior. |
| Unsupported models | Throw `AIError.unsupportedModel` instead of silently routing to another capability. |
| Errors | Convert provider failures into `AIError` with the concrete surface provider ID and preserved response metadata. |

## Product Gates

Use these gates before calling a surface complete:

1. `AIProviderCapabilities` lists the upstream package, Swift factories,
   supported model capabilities, files, and skills.
2. Mock transport tests assert request URLs, bodies, headers, warnings, and
   response/stream parsing for each changed capability.
3. Live smoke can be run when credentials are available:

   ```sh
   LIVE_AI_TESTS=1 swift test --filter LiveProviderSmoke
   ```

   Current live smoke reads `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, and
   `GEMINI_API_KEY`, or the ignored root files `openai-api-key.txt`,
   `claude-api-key.txt`, and `gemini-api-key.txt`.

4. README, `Docs/ProviderCapabilityMatrix.md`, `Docs/ProviderVersionLedger.md`,
   and `Docs/ProductGapAudit.md` tell the same story as the code.

## Pre-Commit Checklist

- Public factories and aliases match upstream exports.
- Supported capabilities match upstream model methods.
- `AIProviderCapabilities` and generated `Docs/ProviderCapabilityMatrix.md`
  match any registry change.
- `Docs/ProviderVersionLedger.md` records the package version used for the pass.
- Provider IDs, base URL, env var names, auth headers, and query parameters
  match upstream.
- Request conversion is covered for normal calls plus tools, provider options,
  reasoning, media, and structured output where applicable.
- Response parsing covers text, tool calls, reasoning, sources, warnings, finish
  reason, usage, and provider metadata where applicable.
- Streaming covers deltas, lifecycle parts, usage, finish events, raw chunks,
  and provider error events where upstream exposes them.
- Focused tests cover at least one request and one response/stream for each new
  or changed surface.
- `swift test` passes, or the skipped verification is explicitly documented.
- Commit and push the completed round.
