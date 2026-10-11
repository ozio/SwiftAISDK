## Request transforms with warnings

```swift
var settings = ProviderSettings(apiKey: "...")
settings.transformRequestBodyWithWarnings = { body, warnings in
    var body = body
    if body.removeValue(forKey: "seed") != nil {
        warnings.append(.init(type: "unsupported", feature: "seed", message: "The proxy ignores seeds."))
    }
    return body
}
```

The existing `transformRequestBody` callback remains available and runs first. The new callback can report changes alongside the transformed request. Normal request/response metadata and warning results include the resulting transformation.

The standard `AIProviders.openAICompatible(..., transformRequestBodyWithWarnings:)` overload also accepts this two-argument callback. It preserves the existing factory overloads and the optional earlier one-argument transform.
