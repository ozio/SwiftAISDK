# Test Porting Plan

This plan defines how to replace the hand-written SwiftAISDK parity tests with
tests translated from the upstream Vercel AI SDK test suite while keeping the
tests that prove Swift/platform integration.

Current snapshot:

- Local Swift tests: 1027 `@Test` functions in `Tests/SwiftAISDKTests`.
- Upstream inventory: `Docs/UpstreamTestInventory.md`, generated from Vercel AI
  SDK commit `184dc39c2b2cf8cb9302d81f87edcf2f665cfd8c`.
- Upstream test/spec files: 657 total, 46 package groups tracked locally.
- SwiftPM currently has one test target: `SwiftAISDKTests`.

## Policy

Upstream tests should become the source of truth for provider and core AI SDK
behavior. Existing local tests should remain only when they cover one of these
surfaces:

1. Swift platform behavior that upstream JavaScript tests cannot validate:
   Foundation URL handling, process/stdio transport, Swift concurrency and
   cancellation propagation, multipart/file encoding through Swift APIs, and
   platform availability.
2. Swift-only public API surface: typed `Codable` output, Swift native facade
   overloads, `Sendable`/actor boundaries, response metadata wrappers, and
   provider capability inventory.
3. Opt-in real integration smoke tests that verify credentials, network paths,
   and provider behavior against live services.

Everything else should be treated as legacy parity coverage. Legacy tests should
not be deleted until the corresponding upstream test file has been inspected and
its behavior has either been ported to Swift or explicitly marked out of scope.

## Keep

Keep these local test groups as permanent Swift/platform coverage, though some
individual assertions may move or shrink after upstream parity tests land.

| Local tests | Keep reason | Notes |
| --- | --- | --- |
| `LiveProviderSmokeTests.swift` | Opt-in live service coverage, real credentials, real network behavior. | Keep outside the default parity gate. It complements upstream unit tests rather than replacing them. |
| `MCPStdioTransportTests.swift` | OS process and stdio behavior under `#if os(macOS) || os(Linux)`. | This is platform transport coverage. Upstream MCP stdio tests should still be translated where behavior overlaps. |
| `ProviderAbortPropagationTests.swift`, `ProviderAbortPropagationMediaTests.swift` | Swift `AIAbortController`, async stream cancellation, polling cancellation, and HTTP transport propagation. | Upstream has abort behavior, but JS `AbortController` is not enough to prove Swift cancellation paths. |
| `DownloadURLValidationTests.swift` | Swift `URL`, Foundation networking, redirect and SSRF guard behavior. | Also port upstream `packages/ai/src/util/download/download.test.ts` and provider-utils URL tests; keep only Swift-specific gaps after that. |
| `Native*MetadataTests.swift`, `GoogleMediaResponseMetadataTests.swift`, `OpenAICompatibleResponseMetadataTests.swift` | Swift response metadata wrappers and result models. | Not platform-dependent, but Swift-only public API that upstream cannot cover directly. |
| `ProviderCapabilityMatrixTests.swift`, `ProviderReferenceTests.swift` | SwiftAISDK inventory/reference guarantees. | Keep as local product invariants. |
| `TestSupport.swift`, `AIFacadeTestSupport.swift`, `AIObjectFacadeTestSupport.swift`, `MCPClientTestSupport.swift`, `MCPOAuthTestSupport.swift` | Shared Swift test fixtures. | Keep and reuse for translated upstream tests. |

## Quarantine Then Replace

These local tests mostly assert AI SDK behavior that should be driven by
translated upstream tests. Keep them during migration, but once their upstream
checklist is covered they should be moved out of the default suite or deleted.

| Local tests | Upstream source to translate |
| --- | --- |
| `AIFacade*.swift`, `AIObjectFacade*.swift`, `AIChatSessionTests.swift`, `AIObjectGenerationSessionTests.swift`, `AIAgentTests.swift` | `packages/ai/src/generate-*`, `packages/ai/src/ui`, `packages/ai/src/agent`, `packages/ai/src/text-stream`, `packages/ai/src/ui-message-stream` |
| `AIModelResolutionTests.swift`, `CustomProviderTests.swift`, `CoreContractTests.swift`, `FileAndSkillClientTests.swift`, `MiddlewareTests.swift`, `SpecializedMiddlewareTests.swift`, `WarningLoggingTests.swift`, `RawChunkStreamTests.swift` | `packages/ai/src/model`, `packages/ai/src/registry`, `packages/ai/src/middleware`, `packages/ai/src/logger`, `packages/ai/src/upload-*` |
| `HeaderUtilsTests.swift`, `JSONParsingTests.swift`, `JSONSchemaTransformationTests.swift`, `MediaTypeTests.swift` | `packages/provider-utils/src/*`, `packages/provider/src/errors/get-error-message.test.ts` |
| `MCPClientTests.swift`, `MCPHTTPTransportStreamingTests.swift`, `MCPOAuthTests.swift`, `MCPOAuthFlowTests.swift` | `packages/mcp/src/tool/*`, `packages/mcp/src/util/oauth.util.test.ts` |
| Provider test files: `Alibaba*`, `AmazonBedrock*`, `Anthropic*`, `AssemblyAI*`, `Baseten*`, `BlackForestLabs*`, `ByteDance*`, `Cerebras*`, `Cohere*`, `Deep*`, `ElevenLabs*`, `Fal*`, `Fireworks*`, `Gateway*`, `Gladia*`, `Google*`, `GoogleVertex*`, `Groq*`, `HuggingFace*`, `Hume*`, `KlingAI*`, `LMNT*`, `Luma*`, `MoonshotAI*`, `OpenAI*`, `OpenAICompatible*`, `ResponsesEndpoint*`, `Prodia*`, `QuiverAI*`, `Replicate*`, `RevAI*`, `TogetherAI*`, `Voyage*`, `XAI*`, `ProviderRegistryVercelTests.swift` | Matching upstream package groups in `Docs/UpstreamTestInventory.md` |

## Upstream Tests To Take

Take all tracked upstream package groups from `Docs/UpstreamTestInventory.md`,
but translate behavior into Swift rather than copying JS structure. Prioritize
in this order:

1. Core semantics: `ai`, `provider`, `provider-utils`.
2. Protocol/infrastructure: `mcp`, `openai-compatible`, `open-responses`.
3. High-risk providers: `openai`, `anthropic`, `google`, `google-vertex`,
   `amazon-bedrock`, `gateway`, `xai`.
4. Media and async/polling providers: `fal`, `replicate`, `luma`, `klingai`,
   `black-forest-labs`, `bytedance`, `prodia`, `elevenlabs`, `deepgram`,
   `assemblyai`, `gladia`, `revai`, `hume`, `lmnt`.
5. Smaller language/vector providers: `cohere`, `mistral`, `groq`,
   `deepseek`, `cerebras`, `moonshotai`, `perplexity`, `alibaba`, `baseten`,
   `deepinfra`, `fireworks`, `togetherai`, `voyage`, `quiverai`,
   `huggingface`, `vercel`.

For each package, create a checklist from the upstream file list. Every upstream
file should end in one of these states:

- `ported`: behavior covered by a Swift test.
- `covered-by-existing-platform-test`: only for the keep list above.
- `out-of-scope`: JS/browser/Node/framework/codemod behavior or a product
  surface SwiftAISDK does not expose.
- `blocked`: behavior requires a Swift API/product decision.

## Upstream Tests To Skip By Default

Do not port these upstream groups unless SwiftAISDK adds a matching product
surface:

- Framework adapters: `angular`, `react`, `vue`, `svelte`, `rsc`.
- Codemods and tooling: `codemod`, `devtools`, `test-server`, `tui`.
- Agent harness products not exposed by SwiftAISDK: `harness*`,
  `workflow*`, `sandbox-*`, `policy-opa`.
- Adapter packages not currently tracked: `langchain`, `llamaindex`.
- Example e2e tests under `examples/ai-functions`; use them only as live smoke
  inspiration.

Within tracked packages, skip or rewrite JS-runtime assertions that only test
Node/browser primitives such as `process.env`, `window`, `document`, native JS
`Blob`/`FormData`, server `Response` piping, or OpenTelemetry Node channels.
If the behavior matters in Swift, write an equivalent Foundation/Swift
concurrency assertion instead.

## Migration Shape

1. Add test grouping before moving files:
   - `Tests/SwiftAISDKTests/Upstream/<PackageGroup>/<UpstreamArea>/...`:
     translated upstream behavior. Mirror the upstream package/file first, then
     split oversized files by upstream `describe` block or stable behavior area,
     not by mechanical `Part1` / `Part2` numbering.
   - `Tests/SwiftAISDKTests/PlatformIntegration/...`: permanent Swift/platform
     and live smoke coverage.
   - `Tests/SwiftAISDKTests/LegacyParity/...`: current local behavior tests
     waiting for upstream checklist replacement.
2. Keep shared fixtures next to the group that owns them. If support is used
   only by one upstream package/file, put it under that package directory; keep
   target-wide helpers in the test target root only when they are genuinely
   generic.
3. Target file size should stay reviewable. Prefer files under roughly 300-400
   lines; split earlier when a file covers unrelated upstream `describe` blocks.
4. Start with one package, preferably `@ai-sdk/anthropic` because it is already
   updated to `4.0.1` and has 11 upstream test files.
5. For that package, port upstream tests file-by-file and annotate skipped cases
   in the package sync report.
6. Only after the package checklist is complete, move the old local provider
   tests to `LegacyParity` or delete duplicate assertions.
7. Repeat package-by-package. Avoid bulk deletion across providers because the
   current local tests contain bug-regression coverage from previous ports.

## First Package Pilot

Pilot on `@ai-sdk/anthropic`:

- Upstream files: 11, listed in `Docs/UpstreamTestInventory.md`.
- Package checklist: `Docs/AnthropicUpstreamTestChecklist.md`.
- Local files to compare: `AnthropicTests.swift`,
  `AnthropicRequestMappingAndToolsTests.swift`, `AnthropicStreamingAndClientsTests.swift`.
- Keep from local Anthropic tests only if it proves Swift-specific transport,
  abort/cancellation, response metadata wrapping, or a documented local
  adaptation.
- Translate upstream tests for provider factory/auth, files, skills, usage,
  prompt conversion, tool preparation, schema sanitization, error mapping, and
  language model generate/stream behavior.
