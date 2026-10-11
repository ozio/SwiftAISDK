## Conversations API

```swift
let mistral = try AIProviders.mistral()
let model = try mistral.conversation("mistral-small-latest")
let result = try await model.generate(.init(
    messages: [.user("Find recent astronomy news.")],
    tools: ["web_search": MistralTools.webSearch()]
))
print(result.text)
```

`conversation(...)` uses `/conversations` with typed Mistral options, system instructions, file/image input, function and provider tools, sources, usage and streaming event conversion. `MistralTools.webSearchPremium()` exposes premium search. Every call is stateless (`store=false`) and replays the full prompt; conversation or agent continuation IDs are not exposed. Existing `languageModel(...)` and `chatModel(...)` retain Chat Completions.

A schema plus application tools on Chat Completions uses the synthetic JSON tool; its arguments become output text without hiding real application calls. Generic embedding dimensions are forwarded unless provider-specific dimensions override them.
