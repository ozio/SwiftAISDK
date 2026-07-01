# SwiftAISDK Documentation

This directory contains the maintenance and status documentation for
SwiftAISDK. User-facing guides live in `README.md` and `docs-site`.

## Start Here

| Need | Read |
| --- | --- |
| Use the package | `README.md`, then `docs-site/src/content/docs/getting-started/quickstart.mdx` |
| Understand public docs ownership | `Docs/ProductDocumentation.md` |
| Check current porting status | `Docs/PortingStatus.md` |
| Port upstream code or tests | `Docs/AgentPortingGuide.md` |
| Check provider capability coverage | `Docs/ProviderCapabilityMatrix.md` |
| Check npm package baselines | `Docs/ProviderVersionLedger.md` |
| Check core AI SDK parity | `Docs/CoreV6Parity.md` |
| Inspect upstream test inventory | `Docs/UpstreamTestInventory.md` |

## Document Roles

- `ProductDocumentation.md` is the public-docs contract: what belongs in
  README, docs-site, generated reference, examples, and troubleshooting.
- `PortingStatus.md` is the readable status page for product gaps, package
  baselines, provider coverage, live verification, and reopen rules.
- `AgentPortingGuide.md` is the exact process for future agents. It includes the
  required test-porting and public-documentation steps.
- `ProviderCapabilityMatrix.md` is generated from
  `AIProviderCapabilities`. Edit the Swift source first, then regenerate.
- `ProviderVersionLedger.md` is the package-version ledger. It is not a task
  queue.
- `UpstreamTestInventory.md` is generated from the Vercel AI SDK monorepo and is
  intentionally large.
- `FreshUpstreamTestDiffAudit.md` is a short working log for the latest
  upstream test diff audit.

Historical provider-by-provider narratives and one-off checklist files have
been folded into the status and agent guide. The durable evidence should live in
tests, generated inventories, and the version/capability ledgers.

