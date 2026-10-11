## Haiku 5.5, decisions, and stream metadata

Haiku 5.5 supports adaptive thinking, xhigh effort and a 128k maximum output. Budget thinking is converted to adaptive with a compatibility warning; sampling is rejected. Explicit disabled thinking remains valid at supported effort levels. Unsupported models no longer warn for an explicit `strict: false` tool.

Streaming consumers can inspect `.custom(kind: "anthropic.message_start", ...)` for initial provider usage and response identity. Replaying `anthropic.fallback` adds the required server-side fallback beta. `decisionModel(...)` uses the native structured-output adapter; see [Decision](../../core/decide/).

Set `ProviderSettings.batchResultDownloads` to bound downloaded JSONL rows. Unicode custom header values remain on Anthropic AWS/Bedrock requests but are excluded from canonical signed headers.
