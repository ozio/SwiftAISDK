# Provider Upstream Test Checklist

Snapshot:

- Upstream package: `@ai-sdk/provider@3.0.10`
- Upstream ref: `vercel/ai@184dc39c2b2cf8cb9302d81f87edcf2f665cfd8c`
- Local package: SwiftAISDK core provider/error types

This file tracks the provider core package from `Docs/TestPortingPlan.md`. Every
upstream provider test file should end in one of these states: `ported`,
`covered-by-existing-platform-test`, `out-of-scope`, or `blocked`.

## File Status

| Upstream file | Status | Swift evidence | Notes |
| --- | --- | --- | --- |
| `packages/provider/src/errors/get-error-message.test.ts` | `ported` | `ProviderErrorMessageTests.swift` | Covers nil, strings, empty strings, Swift error descriptions, custom error descriptions, JSON object/array/null values, numbers, and booleans. JS `undefined` maps to Swift `nil`, and JS Error subclass/toString behavior maps to Swift `CustomStringConvertible` errors. |

## Next Provider Slices

All upstream provider test files are now classified as `ported`.
