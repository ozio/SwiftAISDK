# Fresh Upstream Test Diff Audit

Snapshot date: 2026-10-04

Baseline: `vercel/ai@18b2b32deeea8982bd252996b0616fd1d9730b83`.
Current: `vercel/ai@15f1a4d0531ac641a4a4d9cc602c0536c1906834`.
The inventory has 976 executable test/spec files in 82 groups, up from 948.
This diff contains 210 executable paths and nine declaration-test paths.
Published old/latest npm tarballs, not unpublished monorepo work, determine the
behavior baseline. Each candidate test path below is accounted for separately;
declaration tests check TypeScript types and are not counted as executed Swift tests.

Diff command:

```sh
git diff --name-status 18b2b32deeea8982bd252996b0616fd1d9730b83..15f1a4d0531ac641a4a4d9cc602c0536c1906834 -- packages examples
```

Keep executable names ending in `.test.ts`, `.test.tsx`, `.test.mts`,
`.spec.ts`, `.spec.tsx`, `.spec.mts`; separately retain paths containing `test-d`.
`UpstreamPackageDiffAudit.md` contains each package's exact version and source
disposition. Native translations are in the four `Weekly*20261004Tests.swift`
files, shared tracker tests and existing affected provider/core suites.

Dispositions: 68 out-of-scope, 102 ported, 11 covered, 7 partial, 6 deferred, 22 identity-only, 3 announced.

## Executable paths

| Change | Upstream path | Decision | Swift evidence / boundary |
| --- | --- | --- | --- |
| `A` | `examples/ai-functions/src/lib/create-model-id-alias-fetch.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/ai/src/agent/create-agent-ui-stream.test.ts` | `ported` | WeeklyImageAndCore/WeeklyCoreAudioMCP regressions cover the native image, tool-search, audio, metadata or agent conversion behavior; declaration tests are reviewed separately. |
| `M` | `packages/ai/src/embed/embed-many.test.ts` | `covered` | Native value/dictionary/file/iterator semantics already cover the published correction; focused existing regressions and full suite retained. |
| `M` | `packages/ai/src/generate-image/generate-image.test.ts` | `ported` | WeeklyImageAndCore/WeeklyCoreAudioMCP regressions cover the native image, tool-search, audio, metadata or agent conversion behavior; declaration tests are reviewed separately. |
| `M` | `packages/ai/src/generate-speech/generate-speech.test.ts` | `ported` | WeeklyImageAndCore/WeeklyCoreAudioMCP regressions cover the native image, tool-search, audio, metadata or agent conversion behavior; declaration tests are reviewed separately. |
| `A` | `packages/ai/src/generate-speech/generated-audio-file.test.ts` | `covered` | Native value/dictionary/file/iterator semantics already cover the published correction; focused existing regressions and full suite retained. |
| `M` | `packages/ai/src/generate-text/prune-messages.test.ts` | `covered` | Native value/dictionary/file/iterator semantics already cover the published correction; focused existing regressions and full suite retained. |
| `M` | `packages/ai/src/generate-text/smooth-stream.test.ts` | `ported` | WeeklyImageAndCore/WeeklyCoreAudioMCP regressions cover the native image, tool-search, audio, metadata or agent conversion behavior; declaration tests are reviewed separately. |
| `A` | `packages/ai/src/generate-text/validate-tool-approvals.node.test.ts` | `covered` | Native value/dictionary/file/iterator semantics already cover the published correction; focused existing regressions and full suite retained. |
| `M` | `packages/ai/src/generate-video/generate-video.test.ts` | `covered` | Native value/dictionary/file/iterator semantics already cover the published correction; focused existing regressions and full suite retained. |
| `M` | `packages/ai/src/middleware/extract-reasoning-middleware.test.ts` | `covered` | Native value/dictionary/file/iterator semantics already cover the published correction; focused existing regressions and full suite retained. |
| `M` | `packages/ai/src/middleware/wrap-image-model.test.ts` | `ported` | WeeklyImageAndCore/WeeklyCoreAudioMCP regressions cover the native image, tool-search, audio, metadata or agent conversion behavior; declaration tests are reviewed separately. |
| `M` | `packages/ai/src/model/as-image-model-v4.test.ts` | `ported` | WeeklyImageAndCore/WeeklyCoreAudioMCP regressions cover the native image, tool-search, audio, metadata or agent conversion behavior; declaration tests are reviewed separately. |
| `M` | `packages/ai/src/registry/provider-registry.test.ts` | `covered` | Native value/dictionary/file/iterator semantics already cover the published correction; focused existing regressions and full suite retained. |
| `M` | `packages/ai/src/telemetry/create-telemetry-dispatcher.test.ts` | `ported` | WeeklyImageAndCore/WeeklyCoreAudioMCP regressions cover the native image, tool-search, audio, metadata or agent conversion behavior; declaration tests are reviewed separately. |
| `M` | `packages/ai/src/telemetry/tracing-channel-publisher.test.ts` | `out-of-scope` | Node HTTP/SSE/diagnostics-channel adapter; Swift returns AsyncSequence rather than a browser HTTP response. |
| `M` | `packages/ai/src/telemetry/tracing-channel.test.ts` | `out-of-scope` | Node HTTP/SSE/diagnostics-channel adapter; Swift returns AsyncSequence rather than a browser HTTP response. |
| `M` | `packages/ai/src/tool-search/prepare-tool-search.test.ts` | `ported` | WeeklyImageAndCore/WeeklyCoreAudioMCP regressions cover the native image, tool-search, audio, metadata or agent conversion behavior; declaration tests are reviewed separately. |
| `M` | `packages/ai/src/tool-search/tool-search.test.ts` | `ported` | WeeklyImageAndCore/WeeklyCoreAudioMCP regressions cover the native image, tool-search, audio, metadata or agent conversion behavior; declaration tests are reviewed separately. |
| `M` | `packages/ai/src/transcribe/stream-transcribe.test.ts` | `ported` | WeeklyImageAndCore/WeeklyCoreAudioMCP regressions cover the native image, tool-search, audio, metadata or agent conversion behavior; declaration tests are reviewed separately. |
| `M` | `packages/ai/src/transcribe/transcribe.test.ts` | `ported` | WeeklyImageAndCore/WeeklyCoreAudioMCP regressions cover the native image, tool-search, audio, metadata or agent conversion behavior; declaration tests are reviewed separately. |
| `A` | `packages/ai/src/ui-message-stream/create-sse-stream-with-keep-alive.test.ts` | `out-of-scope` | Node HTTP/SSE/diagnostics-channel adapter; Swift returns AsyncSequence rather than a browser HTTP response. |
| `M` | `packages/ai/src/ui-message-stream/create-ui-message-stream-response.test.ts` | `out-of-scope` | Node HTTP/SSE/diagnostics-channel adapter; Swift returns AsyncSequence rather than a browser HTTP response. |
| `M` | `packages/ai/src/ui-message-stream/create-ui-message-stream.test.ts` | `partial` | Native partial text/tool-input seeding and superseded approvals are tested; browser rawInput wire-state/HTTP resume/explicit step identity remain deferred. |
| `M` | `packages/ai/src/ui-message-stream/pipe-ui-message-stream-to-response.test.ts` | `out-of-scope` | Node HTTP/SSE/diagnostics-channel adapter; Swift returns AsyncSequence rather than a browser HTTP response. |
| `M` | `packages/ai/src/ui-message-stream/read-ui-message-stream.test.ts` | `partial` | Native partial text/tool-input seeding and superseded approvals are tested; browser rawInput wire-state/HTTP resume/explicit step identity remain deferred. |
| `M` | `packages/ai/src/ui/chat.test.ts` | `partial` | Native partial text/tool-input seeding and superseded approvals are tested; browser rawInput wire-state/HTTP resume/explicit step identity remain deferred. |
| `M` | `packages/ai/src/ui/convert-to-model-messages.test.ts` | `ported` | WeeklyImageAndCore/WeeklyCoreAudioMCP regressions cover the native image, tool-search, audio, metadata or agent conversion behavior; declaration tests are reviewed separately. |
| `M` | `packages/ai/src/ui/http-chat-transport.test.ts` | `deferred` | No native HTTPChatTransport/resumable HTTP route exists; do not claim browser reconnect parity. |
| `M` | `packages/ai/src/ui/last-assistant-message-is-complete-with-tool-calls.test.ts` | `partial` | Native partial text/tool-input seeding and superseded approvals are tested; browser rawInput wire-state/HTTP resume/explicit step identity remain deferred. |
| `M` | `packages/ai/src/ui/process-ui-message-stream.test.ts` | `partial` | Native partial text/tool-input seeding and superseded approvals are tested; browser rawInput wire-state/HTTP resume/explicit step identity remain deferred. |
| `M` | `packages/ai/src/ui/validate-ui-messages.test.ts` | `partial` | Native partial text/tool-input seeding and superseded approvals are tested; browser rawInput wire-state/HTTP resume/explicit step identity remain deferred. |
| `A` | `packages/ai/src/util/set-own.test.ts` | `covered` | Native value/dictionary/file/iterator semantics already cover the published correction; focused existing regressions and full suite retained. |
| `M` | `packages/ai/src/util/write-to-server-response.test.ts` | `out-of-scope` | Node HTTP/SSE/diagnostics-channel adapter; Swift returns AsyncSequence rather than a browser HTTP response. |
| `M` | `packages/alibaba/src/alibaba-embedding-model.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `M` | `packages/amazon-bedrock/src/amazon-bedrock-chat-language-model-options.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/amazon-bedrock/src/amazon-bedrock-chat-language-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/amazon-bedrock/src/amazon-bedrock-image-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/amazon-bedrock/src/amazon-bedrock-prepare-tools.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/amazon-bedrock/src/amazon-bedrock-provider.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/amazon-bedrock/src/amazon-bedrock-sigv4-fetch.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/amazon-bedrock/src/anthropic/amazon-bedrock-anthropic-provider.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/amazon-bedrock/src/inject-fetch-headers.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/amazon-bedrock/src/mantle/bedrock-mantle-provider.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `A` | `packages/amazon-bedrock/src/region-validation.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `A` | `packages/amazon-bedrock/src/resolve-amazon-bedrock-base-url.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/angular/src/lib/chat.ng.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/anthropic-aws/src/anthropic-aws-fetch.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `A` | `packages/anthropic-aws/src/region-validation.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/anthropic/src/anthropic-batch.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/anthropic/src/anthropic-language-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/anthropic/src/convert-to-anthropic-prompt.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/assemblyai/src/assemblyai-transcription-model.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `A` | `packages/azure/src/azure-mai-transcription-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/azure/src/azure-openai-provider.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `A` | `packages/azure/src/azure-speech-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `A` | `packages/azure/src/azure-transcription-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/baseten/src/baseten-provider.unit.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `M` | `packages/black-forest-labs/src/black-forest-labs-image-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/black-forest-labs/src/black-forest-labs-provider.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/bytedance/src/bytedance-image-model.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `M` | `packages/cartesia/src/cartesia-speech-model.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `M` | `packages/cartesia/src/cartesia-transcription-model.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `M` | `packages/cerebras/src/cerebras-provider.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `M` | `packages/cohere/src/cohere-embedding-model.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `M` | `packages/deepgram/src/deepgram-speech-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/deepgram/src/deepgram-transcription-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/deepinfra/src/deepinfra-image-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/deepseek/src/chat/convert-to-deepseek-usage.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/devtools/src/db.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/devtools/src/integration.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/elevenlabs/src/elevenlabs-speech-model.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `M` | `packages/elevenlabs/src/elevenlabs-transcription-model.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `M` | `packages/fal/src/fal-image-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/fireworks/src/fireworks-image-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/fish-audio/src/fish-audio-speech-model.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `M` | `packages/fish-audio/src/fish-audio-transcription-model.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `M` | `packages/gateway/src/gateway-fetch-metadata.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/gateway/src/gateway-provider-options.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/gateway/src/gateway-provider.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/gateway/src/gateway-speech-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/gateway/src/gateway-transcription-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/gladia/src/gladia-transcription-model.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `M` | `packages/gmicloud/src/gmicloud-provider.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `M` | `packages/google-vertex/src/edge/google-vertex-auth-edge.test.ts` | `covered` | Swift-native OAuth transport uses its existing URL/header types; browser edge credential behavior has no separate target. |
| `M` | `packages/google-vertex/src/gemini-transcription/google-vertex-gemini-transcription-model.test.ts` | `deferred` | Vertex Gemini transcription adapter remains absent; Chirp and speech are separate implemented routes. |
| `M` | `packages/google-vertex/src/google-vertex-cloud-tts-speech-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/google-vertex/src/google-vertex-embedding-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/google-vertex/src/google-vertex-image-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `A` | `packages/google-vertex/src/google-vertex-location-validation.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/google-vertex/src/google-vertex-transcription-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/google/src/google-embedding-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/google/src/google-image-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/google/src/google-language-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/google/src/google-provider.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/google/src/google-speech-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/google/src/realtime/google-realtime-event-mapper.test.ts` | `deferred` | Gemini transcription/Realtime adapter remains a dedicated native provider vertical. |
| `M` | `packages/google/src/transcription/google-transcription-model.test.ts` | `deferred` | Gemini transcription/Realtime adapter remains a dedicated native provider vertical. |
| `M` | `packages/groq/src/groq-chat-language-model.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `M` | `packages/groq/src/groq-transcription-model.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `M` | `packages/harness-acp/src/acp-auth.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-acp/src/acp-harness.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `A` | `packages/harness-acp/src/v1/bridge/canonical-json-fingerprint.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-acp/src/v1/bridge/host-tool-correlation.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-acp/src/v1/bridge/host-tool-mcp-http.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `A` | `packages/harness-acp/src/v1/bridge/host-tool-relay-authorization.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-acp/src/v1/bridge/host-tool-relay-client.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-acp/src/v1/bridge/host-tool-relay.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-acp/src/v1/bridge/permission-controller.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-acp/src/v1/bridge/profile-values.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-acp/src/v1/bridge/protocol-configuration.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-acp/src/v1/implementation.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-claude-code/src/bridge/create-emit-stream-event.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-claude-code/src/bridge/index.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-claude-code/src/claude-code-bridge-protocol.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-claude-code/src/claude-code-harness.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-cline/src/cline-session.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-codex/src/bridge/create-emit-stream-event.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-codex/src/codex-harness.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-codex/src/codex-instructions.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-cursor/src/cursor-harness.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-deepagents/src/deepagents-harness.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-fx/src/fx-harness.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-github-copilot/src/github-copilot-harness.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-grok-build/src/grok-build-harness.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-opencode/src/bridge/index.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-opencode/src/opencode-auth.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-opencode/src/opencode-harness.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-pi/src/pi-auth.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness-pi/src/pi-session.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness/src/agent/create-harness-sandbox-template.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness/src/agent/harness-agent.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness/src/agent/internal/run-prompt.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness/src/agent/internal/sandbox-bootstrap.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness/src/agent/internal/turn-telemetry.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness/src/agent/observability/file-reporter.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness/src/agent/telemetry-integration.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `A` | `packages/harness/src/errors/harness-history-unavailable-error.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/harness/src/utils/credential-forwarding.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/hume/src/hume-speech-model.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `M` | `packages/langchain/src/adapter.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/langchain/src/utils.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/luma/src/luma-image-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `A` | `packages/mcp/src/index.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/mcp/src/tool/mcp-client.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/mcp/src/tool/mcp-sse-transport.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `A` | `packages/mcp/src/tool/oauth-credential-invalidation.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/mcp/src/tool/oauth.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/minimax/src/minimax-provider.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `A` | `packages/mistral/src/map-mistral-finish-reason.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/mistral/src/mistral-chat-language-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/mistral/src/mistral-embedding-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/mistral/src/mistral-speech-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/mistral/src/mistral-transcription-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/open-responses/src/open-responses-extension.test.ts` | `deferred` | Bare extension codec registry and registration/type-collision tests need the existing missing native registry. |
| `M` | `packages/open-responses/src/responses/open-responses-language-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/openai-compatible/src/chat/convert-to-openai-compatible-chat-messages.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/openai-compatible/src/chat/openai-compatible-chat-language-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/openai-compatible/src/image/openai-compatible-image-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/openai-compatible/src/openai-compatible-provider.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/openai/src/chat/openai-chat-language-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/openai/src/completion/openai-completion-language-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/openai/src/embedding/openai-embedding-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/openai/src/image/openai-image-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/openai/src/normalize-openai-json-schema.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/openai/src/openai-language-model-capabilities.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/openai/src/speech/openai-speech-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/openai/src/transcription/openai-transcription-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `A` | `packages/otel/src/finish-reason-status.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/otel/src/legacy-open-telemetry.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/otel/src/open-telemetry.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/perplexity/src/perplexity-embedding-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/perplexity/src/perplexity-language-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/prodia/src/prodia-image-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/prodia/src/prodia-provider.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/provider-utils/src/get-from-api.test.ts` | `covered` | Native transport/header dictionaries already represent the reviewed helper behavior; package identity synchronized. |
| `M` | `packages/provider-utils/src/get-runtime-environment-user-agent.test.ts` | `covered` | Native transport/header dictionaries already represent the reviewed helper behavior; package identity synchronized. |
| `A` | `packages/provider-utils/src/is-valid-hostname-part.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `A` | `packages/provider-utils/src/streaming-tool-call-argument-state.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/provider-utils/src/streaming-tool-call-tracker.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/provider-utils/src/transcription-stream-envelope.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/quiverai/src/quiverai-generate-image.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/quiverai/src/quiverai-image-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/quiverai/src/quiverai-language-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/quiverai/src/quiverai-provider.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/react/src/use-chat.ui.test.tsx` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/replicate/src/replicate-image-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/revai/src/revai-transcription-model.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `M` | `packages/svelte/src/chat.svelte.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/togetherai/src/togetherai-image-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `A` | `packages/topaz/src/topaz-image-model.test.ts` | `announced` | New untracked image/video enhancement provider; three fixtures reviewed, no automatic implementation. |
| `A` | `packages/topaz/src/topaz-provider.test.ts` | `announced` | New untracked image/video enhancement provider; three fixtures reviewed, no automatic implementation. |
| `A` | `packages/topaz/src/topaz-video-model.test.ts` | `announced` | New untracked image/video enhancement provider; three fixtures reviewed, no automatic implementation. |
| `M` | `packages/tui/src/tui/layout.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/tui/src/tui/markdown.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `A` | `packages/tui/src/tui/sanitize-terminal-text.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `A` | `packages/tui/src/tui/terminal-renderer-security.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `A` | `packages/tui/src/util/print-stream.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/typesafe-ai/src/typesafe-ai-evaluation-model.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `M` | `packages/voyage/src/voyage-embedding-model.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |
| `M` | `packages/vue/src/chat.vue.ui.test.tsx` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/workflow-harness/src/run-harness-agent-output.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/workflow/src/do-stream-step.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/workflow/src/stream-text-iterator.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `A` | `packages/workflow/src/workflow-agent-transform.test.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `M` | `packages/xai/src/xai-image-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/xai/src/xai-provider.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/xai/src/xai-speech-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/xai/src/xai-transcription-model.test.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/zai/src/zai-provider.test.ts` | `identity-only` | Exact headers/model-ID fixtures reviewed; version/prefix assertions updated, existing provider builder/parser/stream coverage retained. |

## Declaration-only paths

| Change | Upstream path | Decision | Swift evidence / boundary |
| --- | --- | --- | --- |
| `A` | `packages/ai/src/telemetry/speech-telemetry.test-d.ts` | `ported` | WeeklyImageAndCore/WeeklyCoreAudioMCP regressions cover the native image, tool-search, audio, metadata or agent conversion behavior; declaration tests are reviewed separately. |
| `M` | `packages/ai/src/tool-search/tool-search.test-d.ts` | `ported` | WeeklyImageAndCore/WeeklyCoreAudioMCP regressions cover the native image, tool-search, audio, metadata or agent conversion behavior; declaration tests are reviewed separately. |
| `A` | `packages/ai/src/types/image-model.test-d.ts` | `ported` | WeeklyImageAndCore/WeeklyCoreAudioMCP regressions cover the native image, tool-search, audio, metadata or agent conversion behavior; declaration tests are reviewed separately. |
| `M` | `packages/ai/src/ui/ui-messages.test-d.ts` | `partial` | Native partial text/tool-input seeding and superseded approvals are tested; browser rawInput wire-state/HTTP resume/explicit step identity remain deferred. |
| `M` | `packages/gateway/src/gateway-provider-options.test-d.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/harness/src/agent/harness-agent-settings.test-d.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `A` | `packages/harness/src/v1/harness-v1-message.test-d.ts` | `out-of-scope` | Framework/harness/workflow/tooling or React surface absent from this Swift provider package. |
| `A` | `packages/mcp/src/index.test-d.ts` | `ported` | Published provider behavior translated in WeeklyProviders/WeeklyAzureAudio/WeeklyImageAndCore tests plus affected existing provider suites. |
| `M` | `packages/open-responses/src/open-responses-extension.test-d.ts` | `deferred` | Bare extension codec registry and registration/type-collision tests need the existing missing native registry. |
