# Provider Utils Upstream Test Checklist

Snapshot: `@ai-sdk/provider-utils@5.0.1`, upstream commit `a7c23e5f9562644b39a0c6b1c8fa71c4fd9dfd95`.

Rule for this checklist: keep Swift/iOS/macOS-only tests only when they validate platform integration. For pure provider-utils behavior, prefer upstream-shaped parity tests and use this file to track which upstream tests are ported, blocked, or intentionally out of scope.

## Ported

- `packages/provider-utils/src/add-additional-properties-to-json-schema.test.ts` - covered in `JSONSchemaTransformationTests.swift`.
- `packages/provider-utils/src/as-array.test.ts` - covered in `ProviderUtilsUpstreamParityTests.swift`.
- `packages/provider-utils/src/create-tool-name-mapping.test.ts` - covered in `ProviderUtilsUpstreamParityTests.swift` using the local JSON provider-tool representation.
- `packages/provider-utils/src/convert-image-model-file-to-data-uri.test.ts` - covered as Swift `convertImageModelFileToDataURI` in `ImageModelFileDataURITests.swift`; upstream base64-string input is Swift-inapplicable because local `ImageInputFile` stores binary file payloads as `Data`.
- `packages/provider-utils/src/convert-to-form-data.test.ts` - covered as Swift `convertToMultipartFormData` in `MultipartFormDataTests.swift`; JS `Blob` maps to local `MultipartFormDataFile`, and JS `undefined` maps to optional `nil`.
- `packages/provider-utils/src/delayed-promise.test.ts` - covered as Swift `AIDelayedPromise` in `ProviderUtilsUpstreamParityTests.swift`.
- `packages/provider-utils/src/delay.test.ts` - covered in `ProviderUtilsUpstreamParityTests.swift`; JS `DOMException AbortError` maps to Swift `AIAbortError`.
- `packages/provider-utils/src/detect-media-type.test.ts` - covered in `MediaTypeTests.swift` for bytes/base64 signatures, top-level filters, ID3 stripping, and helper rules.
- `packages/provider-utils/src/download-blob.test.ts` - portable behavior is covered by `downloadURL` / `validateDownloadURL` in `DownloadURLValidationTests.swift` and `readResponseWithSizeLimit` in `HTTPResponseSizeLimitTests.swift`; JS `Blob`, global `fetch`, Web Stream body `cancel()`, and browser opaque-redirect fallback are Swift-inapplicable.
- `packages/provider-utils/src/extract-lines.test.ts` - covered in `ProviderUtilsUpstreamParityTests.swift`.
- `packages/provider-utils/src/fetch-with-validated-redirects.test.ts` - covered through local `downloadURL(..., transport:)` redirect validation in `DownloadURLValidationTests.swift`; JS browser opaque-redirect fallback and redirect body `cancel()` assertions are Swift-inapplicable.
- `packages/provider-utils/src/filter-nullable.test.ts` - covered in `ProviderUtilsUpstreamParityTests.swift`.
- `packages/provider-utils/src/generate-id.test.ts` - length/default/uniqueness cases covered in `ProviderUtilsUpstreamParityTests.swift`; the JS separator error branch is API-shape-inapplicable because Swift `createIdGenerator` is intentionally non-throwing and uses typed parameters.
- `packages/provider-utils/src/inject-json-instruction.test.ts` - covered in `ProviderUtilsUpstreamParityTests.swift`; JS `null` optional-parameter case is not represented because Swift uses `nil` defaults.
- `packages/provider-utils/src/is-json-serializable.test.ts` - covered in `JSONParsingTests.swift` with Swift runtime equivalents for non-serializable values.
- `packages/provider-utils/src/is-provider-reference.test.ts` - covered in `ProviderReferenceTests.swift`.
- `packages/provider-utils/src/is-same-origin.test.ts` - covered in `ProviderUtilsUpstreamParityTests.swift`.
- `packages/provider-utils/src/is-url-supported.test.ts` - covered in `ProviderUtilsUpstreamParityTests.swift`.
- `packages/provider-utils/src/map-reasoning-to-provider.test.ts` - covered in `ProviderUtilsUpstreamParityTests.swift`; upstream `details` maps to local `AIWarning.message`.
- `packages/provider-utils/src/media-type-to-extension.test.ts` - covered in `MediaTypeTests.swift`.
- `packages/provider-utils/src/normalize-headers.test.ts` - covered in `HeaderUtilsTests.swift`; `Headers` object cases are Swift-inapplicable, tuple/record/nil cases are covered.
- `packages/provider-utils/src/parse-json.test.ts` - covered in `JSONParsingTests.swift` for parse errors, validation errors, safe parse raw values, and parsability; Zod transform cases are Swift schema-system-specific and tracked below.
- `packages/provider-utils/src/read-response-with-size-limit.test.ts` - covered as Swift `readResponseWithSizeLimit` and default `URLSessionTransport.send` response limiting in `HTTPResponseSizeLimitTests.swift`; Web Stream `cancel()` / nullable body assertions are Swift-inapplicable because local stream responses use `AsyncThrowingStream<Data, Error>` with a non-optional body.
- `packages/provider-utils/src/remove-undefined-entries.test.ts` - covered as Swift `removeNilEntries` in `ProviderUtilsUpstreamParityTests.swift`.
- `packages/provider-utils/src/resolve-full-media-type.test.ts` - covered in `MediaTypeTests.swift` for inline data; URL-source error wording is API-shape-inapplicable unless Swift later adds the same untyped URL file-part helper shape.
- `packages/provider-utils/src/resolve-provider-reference.test.ts` - covered in `ProviderReferenceTests.swift`.
- `packages/provider-utils/src/secure-json-parse.test.ts` - covered in `JSONParsingTests.swift`.
- `packages/provider-utils/src/streaming-tool-call-tracker.test.ts` - covered as standalone Swift `AIStreamingToolCallTracker` in `StreamingToolCallTrackerTests.swift`; existing provider-specific stream buffers remain to be migrated separately if we decide to consolidate implementation.
- `packages/provider-utils/src/strip-file-extension.test.ts` - covered in `ProviderUtilsUpstreamParityTests.swift`.
- `packages/provider-utils/src/validate-types.test.ts` - covered in `JSONParsingTests.swift` via Swift-equivalent `parseJSON`/`safeParseJSON` schema validation, including typed error value/schema and safe raw value preservation.
- `packages/provider-utils/src/validate-download-url.test.ts` - covered in `DownloadURLValidationTests.swift`, including reserved IPv4/IPv6, embedded IPv4, NAT64, trailing-dot hostname, and non-dotted IPv4 cases.
- `packages/provider-utils/src/with-user-agent-suffix.test.ts` - covered in `HeaderUtilsTests.swift`; `Headers` object cases are Swift-inapplicable, tuple/record/nil cases are covered.

## Pending Pure Swift Ports

- None currently classified. Reopen this section when a remaining upstream provider-utils test file maps to an existing Swift API without a product/API-design decision.

## Pending Async / HTTP / Stream Ports

- None currently classified. Reopen this section when a remaining upstream provider-utils test file maps to an existing Swift API without a product/API-design decision.

## Pending Type / Tool Runtime Ports

- None currently classified. Reopen this section when a remaining upstream provider-utils test file maps to an existing Swift API without a product/API-design decision.

## Out Of Scope Or Requires Separate Design

- `packages/provider-utils/src/cancel-response-body.test.ts` - JS fetch/Web Streams socket-pool cleanup helper for `Response.body?.cancel()`. SwiftAISDK streams are represented as `AsyncThrowingStream<Data, Error>` and cancellation is owned by `URLSessionTransport` / stream termination rather than a standalone response-body cancel API.
- `packages/provider-utils/src/convert-async-iterator-to-readable-stream.test.ts` - JS `ReadableStream` adapter and reader cancellation semantics. SwiftAISDK uses `AsyncSequence` / `AsyncThrowingStream` directly and has no local Web Streams compatibility layer to port this onto.
- `packages/provider-utils/src/get-from-api.test.ts` - JS fetch helper composition over `ResponseHandler<T>`, global/default `fetch`, Zod response schemas, runtime user-agent detection, and DOM abort errors. SwiftAISDK covers the portable pieces through `AITransport` request tests, `HeaderUtilsTests.swift`, `JSONParsingTests.swift`, `apiCallError(provider:response:)`, and provider/facade abort propagation tests rather than a standalone `getFromApi` API.
- `packages/provider-utils/src/get-runtime-environment-user-agent.test.ts` - JS runtime detection.
- `packages/provider-utils/src/handle-fetch-error.test.ts` - Node/browser/Bun `fetch` network-error normalization. SwiftAISDK uses Foundation/URLSession and typed `AIAbortError` / `AIAPICallError`; URLSession transport error mapping should be handled as a platform-specific design instead of porting JS error-code strings.
- `packages/provider-utils/src/is-browser-runtime.test.ts` - JS browser/runtime detection.
- `packages/provider-utils/src/parse-json.test.ts` Zod transform/coercion subcases - Swift validation does not use Zod transforms.
- `packages/provider-utils/src/response-handler.test.ts` - JS `ResponseHandler<T>` factory API is tied to fetch `Response`, nullable Web Streams bodies, and Zod schemas. SwiftAISDK covers the portable pieces through `readResponseWithSizeLimit`, `JSONParsingTests.swift` (`value`/`rawValue` and invalid JSON), and `apiCallError(provider:response:)` header/body preservation rather than exposing a standalone response-handler factory.
- `packages/provider-utils/src/resolve.test.ts` - JS `Resolvable<T>` Promise/function/raw-value helper has no direct Swift public API. Swift async closures and throwing behavior are exercised through concrete provider/facade APIs rather than a standalone `resolve` helper.
- `packages/provider-utils/src/schema.test.ts` Zod v4, StandardSchema, `asSchema`, and lazy schema adapter subcases - SwiftAISDK exposes explicit `AIJSONSchema` / `AIObjectSchema` instead of JS Zod/StandardSchema adapters. The portable JSON schema enforcement pieces are covered by `JSONSchemaTransformationTests.swift`, `JSONParsingTests.swift`, and object facade schema tests.
- `packages/provider-utils/src/serialize-model-options.test.ts` - JS workflow serialization helper filters functions/classes/promises from provider config and synchronously resolves `headers` functions. SwiftAISDK does not expose an equivalent workflow model serialization boundary; provider baseURL/header behavior is covered in provider-specific request tests.
- `packages/provider-utils/src/types/executable-tool.test.ts` - TypeScript compile-time narrowing around optional `execute` and JS `tool(...)` construction. Swift `AITool` always has an executable closure, and concrete execution/context behavior is covered through facade/tool execution tests.
- `packages/provider-utils/src/types/execute-tool.test.ts` - JS standalone `executeTool` helper supports class `this` binding and async-generator preliminary/final output. SwiftAISDK's tool runtime executes value-type `AITool.executeWithContext` through `executeToolCalls` / facades; streaming preliminary tool output is represented by provider stream parts, not executable tool async generators.
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parse-def.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/array.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/bigint.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/branded.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/catch.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/date.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/default.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/effects.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/intersection.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/map.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/native-enum.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/nullable.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/number.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/object.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/optional.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/pipe.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/promise.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/readonly.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/record.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/set.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/string.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/tuple.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/parsers/union.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/refs.test.ts`
- `packages/provider-utils/src/to-json-schema/zod3-to-json-schema/zod3-to-json-schema.test.ts`
