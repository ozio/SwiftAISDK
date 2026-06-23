# Upstream Sync Guide

This is the playbook for keeping SwiftAISDK aligned with the provider-facing
packages in Vercel AI SDK (`@ai-sdk/*`). Keep it short and operational: choose
a small related batch, compare against upstream, port the behavior, test it,
update the inventory, then commit and push.

For package versions, use `Docs/ProviderVersionLedger.md`. For product-level
priorities, use `Docs/ProductGapAudit.md`. For current provider inventory, use
`Sources/SwiftAISDK/Providers/ProviderCapabilityMatrix.swift` and the generated
`Docs/ProviderCapabilityMatrix.md`.

## Current Snapshot

- npm version baseline checked: 2026-06-23
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

## Fast Version Update Workflow

Use this path when the task is "check whether the ported packages have newer
npm versions and port the diffs." It is optimized for small package-version
bumps across many providers.

1. Start with the automation script, not memory. It reads
   `Docs/ProviderVersionLedger.md`, reads the core snapshots from
   `Docs/CoreV6Parity.md`, queries `npm view <package> version`, and prints only
   packages whose checked-in baseline is behind npm latest:

   ```sh
   Scripts/check-upstream-versions.js
   ```

   Useful variants:

   ```sh
   Scripts/check-upstream-versions.js --all
   Scripts/check-upstream-versions.js --json
   Scripts/check-upstream-versions.js --package @ai-sdk/openai
   Scripts/check-upstream-versions.js --providers-only
   Scripts/check-upstream-versions.js --fail-on-outdated
   Scripts/check-upstream-versions.js --discover-packages
   Scripts/check-upstream-versions.js --discover-packages --discover-kind provider,adapter,core
   ```

2. For packages that changed, let the script prepare old-vs-new npm tarball
   diffs. This downloads both package versions, unpacks them, writes
   `upstream.diff`, and creates a package summary template under
   `/tmp/ai-sdk-port-upstream-diffs` by default:

   ```sh
   Scripts/check-upstream-versions.js --package @ai-sdk/openai --prepare-diffs
   Scripts/check-upstream-versions.js --prepare-diffs
   ```

   Use `--work-dir <path>` when you want the diff artifacts somewhere other
   than `/tmp`.

   To force a single package diff after the ledger has already been bumped, use
   explicit versions:

   ```sh
   Scripts/check-upstream-versions.js \
     --package @ai-sdk/openai \
     --from 3.0.69 \
     --to 3.0.74 \
     --prepare-diffs
   ```

   This is useful for re-auditing one package, testing the diff pipeline, or
   rebuilding the upstream artifacts for a review.

3. Read each generated `summary.md` and `upstream.diff` before editing Swift.
   The script intentionally does not rewrite the port: it prepares the exact
   package drift and evidence, then the porting pass still updates behavior,
   tests, and docs package-by-package.

4. Also check whether the upstream npm scope gained new packages:

   ```sh
   Scripts/check-upstream-versions.js --discover-packages
   Scripts/check-upstream-versions.js \
     --discover-packages \
     --discover-kind provider,adapter,core \
     --fail-on-new
   ```

   Discovery compares official `@ai-sdk/*` packages from npm search with the
   provider ledger and core snapshot list. Treat untracked `provider`, `adapter`,
   or `core` rows as a product decision: either add and port the package, or
   document why SwiftAISDK intentionally does not track it. UI/framework,
   tooling, and schema-helper packages can stay out of scope unless Swift adds a
   matching product surface.

5. If the script is unavailable or you need to debug it, the equivalent manual
   ledger read is:

   ```sh
   awk -F'|' '/@ai-sdk\\// { gsub(/`| /, "", $2); gsub(/`| /, "", $3); print $2, $3 }' Docs/ProviderVersionLedger.md
   ```

6. Query npm for all ledger packages and write a working list of packages whose
   latest version differs from the ledger. Do not include unrelated packages
   just because `rg` finds their old numbers in tests or docs.

   ```sh
   while read -r package version; do
     latest=$(npm view "$package" version)
     if [ "$latest" != "$version" ]; then
       printf '%s %s -> %s\n' "$package" "$version" "$latest"
     fi
   done < <(awk -F'|' '/@ai-sdk\\// { gsub(/`| /, "", $2); gsub(/`| /, "", $3); print $2, $3 }' Docs/ProviderVersionLedger.md)
   ```

7. For each changed package, download both tarballs into a throwaway directory
   and diff source, tests, changelog, and dist if source is absent:

   ```sh
   work=/tmp/ai-sdk-port-upstream-diffs
   mkdir -p "$work"
   npm pack <package>@<old> --pack-destination "$work"
   npm pack <package>@<new> --pack-destination "$work"
   mkdir -p "$work/<package-name>-old" "$work/<package-name>-new"
   tar -xzf "$work/<pkg-old>.tgz" -C "$work/<package-name>-old" --strip-components=1
   tar -xzf "$work/<pkg-new>.tgz" -C "$work/<package-name>-new" --strip-components=1
   diff -ru "$work/<package-name>-old/src" "$work/<package-name>-new/src" | less
   ```

   If `src` is missing, diff `dist`, `CHANGELOG.md`, and package tests. Treat
   generated dist-only changes as real when the package publishes no source.

8. Make one short note per package before editing. Include:

   ```text
   <package> <old> -> <new>
   Upstream files changed:
   Swift surfaces to inspect:
   Tests to add/update:
   Docs/version rows to update:
   ```

9. Port package-by-package. For each package, update behavior first, tests
   second, version strings last. This prevents user-agent churn from hiding real
   behavior changes.

10. Common Swift touch points for version bumps:

   - `Sources/SwiftAISDK/Providers/ProviderRegistry.swift`
   - provider-specific files under `Sources/SwiftAISDK/Providers/*Provider.swift`
   - provider/model files under `Sources/SwiftAISDK/Models/*`
   - nearest focused tests under `Tests/SwiftAISDKTests/*`
   - `Docs/ProviderVersionLedger.md`
   - `Docs/ProviderSyncStatus.md`
   - `Sources/SwiftAISDK/Providers/ProviderCapabilityMatrix.swift` and
     `Docs/ProviderCapabilityMatrix.md` only when capabilities/factories changed
   - `Docs/CoreV6Parity.md` only when `ai`, `@ai-sdk/react`, or shared core
     behavior changed

11. Mechanical user-agent/version replacements are allowed after behavior tests
   are in place, but keep the search scoped to `Sources`, `Tests`, and `Docs`:

   ```sh
   rg -n 'ai-sdk/<provider>/<old>|@ai-sdk/<provider>` \\| `<old>' Sources Tests Docs
   ```

   Avoid broad replacements over lockfiles or vendored assets.

12. Run a focused filter covering every changed package plus docs drift tests:

   ```sh
   swift test --filter 'Alibaba|Anthropic|Azure|Gateway|OpenAIResponses|MCP|ByteDance|AmazonBedrock|GoogleVertex|DeepSeek|ProviderCapabilityMatrix'
   ```

   Adjust the filter to the actual package list. Always run full verification
   after the focused filter passes:

   ```sh
   swift test
   ```

13. Before finishing, run:

   ```sh
   git diff --stat
   rg -n '<old-version-1>|<old-version-2>|<old-date>' Sources Tests Docs
   ```

   Some old versions are legitimate for packages that did not change. Check each
   match before editing.

14. In the final summary, list changed package versions, notable behavior
    ports, docs touched, and the exact test commands/results.

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

Run provider sync as a vertical provider batch. Prefer 2-3 related providers per
round when the changes are small or the providers share a transport family
(audio, media, OpenAI-compatible, etc.); use a single provider only for large or
risky packages such as OpenAI, Anthropic, Google, Bedrock, Vertex, Gateway, or
MCP.

1. Pick the provider package or 2-3 related provider packages from
   `Docs/ProviderVersionLedger.md`. Do not start a new batch until the previous
   one is tested, documented, committed, and pushed.
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
10. Commit and push the completed batch before moving to the next batch.

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

   Current live smoke reads `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`,
   `GEMINI_API_KEY`, `DEEPSEEK_API_KEY`, `ASSEMBLYAI_API_KEY`, and
   `OPENAI_COMPATIBLE_API_KEY`. In Xcode, set these as test environment
   variables in the scheme instead of Run/Profile arguments.

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
