# Repository Agent Guide

This repository is a SwiftPM port of the provider-facing Vercel AI SDK surface.
When acting as an agent here, keep code, tests, public docs, and porting status
in sync in the same change.

## Workflow

- Work on the current branch by default. Do not create a branch or PR unless the
  user asks for one.
- Prefer a small, vertical batch: one large provider, one core surface, or a few
  related small providers.
- Before changing behavior, read the nearest Swift implementation, existing
  tests, upstream package source, and upstream tests.
- Port behavior, then tests, then public docs/status docs. Do not leave docs as
  a follow-up when public behavior changes.
- Commit and deploy/push directly from the current branch only when the user
  asks. If rollback is needed, prefer returning to an older commit over adding a
  branch workflow.
- For release-style pushes, bump the release tag first: inspect the latest
  semantic-version tag, create the next appropriate annotated tag on the commit
  being released, then push the branch and tag together.

## Porting Requirements

- Use `Docs/AgentPortingGuide.md` as the operational playbook.
- Use `Docs/PortingStatus.md` for the current product and porting state.
- Use `Docs/ProviderVersionLedger.md` for npm package baselines.
- Use `Docs/ProviderCapabilityMatrix.md` and
  `Sources/SwiftAISDK/Providers/ProviderCapabilityMatrix.swift` for provider
  coverage.
- Use `Docs/UpstreamTestInventory.md` before porting tests from upstream.

Every porting pass must update:

1. Swift runtime behavior.
2. Focused Swift tests translated from upstream behavior.
3. Public docs when public API, provider behavior, examples, result shapes, or
   limitations change.
4. Porting status/version docs when upstream baselines, coverage, or known gaps
   change.

## Verification

- Run the narrowest useful `swift test --filter ...` first.
- Run full `swift test` before calling a behavior port complete.
- For docs-site changes, run:

  ```sh
  npm ci --prefix docs-site
  npm --prefix docs-site run build
  ```

- Optional live checks stay behind `LIVE_AI_TESTS=1`.
