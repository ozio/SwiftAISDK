# Product Documentation

SwiftAISDK should be documented as a usable Swift package, not as a pile of
ported methods. Public documentation must explain what the product does, how the
major workflows behave, what providers return, and where Swift intentionally
differs from the TypeScript AI SDK.

## Public Surfaces

| Surface | Role | Update when |
| --- | --- | --- |
| `README.md` | Fast orientation, install, quick start, and links to the deeper docs. | A new user would otherwise miss the package shape or the right next link. |
| `docs-site/src/content/docs` | User-facing product docs: guides, cookbook, providers, reference, parity, and troubleshooting. | Public API, examples, provider behavior, result shapes, errors, or limitations change. |
| `Docs/ProviderCapabilityMatrix.md` | Generated provider and capability table. | `AIProviderCapabilities` changes. |
| `docs-site/src/content/docs/reference/generated` | Generated symbol/reference docs. | Public Swift symbols change and docs generation is run. |
| `Examples` | Runnable examples that prove guide code. | A documented workflow needs compile-checked sample code. |

## What Belongs In Public Docs

Good product docs include:

- the user goal and the Swift entry point;
- runnable Swift snippets;
- the important request options and defaults;
- the shape of the returned result, stream parts, warnings, metadata, or errors;
- provider-specific differences when they affect user code;
- links to deeper reference instead of long method catalogs.

Avoid duplicating every test assertion in public docs. Put precise parity and
version evidence in `Docs/PortingStatus.md`, `Docs/ProviderVersionLedger.md`,
`Docs/CoreV6Parity.md`, and tests.

## Required Guide Coverage

The package docs should cover these product areas:

- install and quick start;
- generate text and stream text;
- structured output with `Output`, object, array, enum, and JSON strategies;
- tools, approvals, provider-defined tools, and MCP tools;
- embeddings, reranking, images, video, speech, transcription, audio generation,
  audio transformation, dubbing, file uploads, and skill uploads;
- provider setup, environment variables, provider options, and capability
  discovery;
- middleware, retries, aborts, telemetry, warnings, metadata, and errors;
- chat/UI message helpers and Swift-native agent surfaces;
- troubleshooting and live smoke testing.

## Documentation Definition Of Done

A change that affects public behavior is complete only when:

1. README still points users to the right docs.
2. docs-site has a guide, provider page, cookbook entry, or troubleshooting note
   for the changed user-facing behavior.
3. Result shapes, stream parts, warnings, metadata, and known limitations are
   described where users will look for them.
4. Generated docs are refreshed when generated sources change.
5. Porting/status docs are updated when upstream baselines or known gaps change.

Verification commands:

```sh
swift build
swift test
npm ci --prefix docs-site
npm --prefix docs-site run build
```

For docs-only changes, run the docs-site build at minimum. For behavior changes,
run focused Swift tests first and full `swift test` before finishing.

