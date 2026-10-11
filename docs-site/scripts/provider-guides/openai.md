## Decisions and current Responses behavior

Use `provider.decisionModel("gpt-6-luna")` with [`AI.experimentalDecide`](../../core/decide/). OpenAI Decisions send `/decisions`, named questions and inline image evidence; the experimental Evaluation entry points remain available through the same native implementation.

GPT-6-sol/luna sampling and logprobs follow the final effective reasoning effort, including configuration updates. Typed tool errors are wrapped as `{ "error": value }` in OpenAI requests. Failed/incomplete web-search results keep error/status metadata in generation, streaming and batch results. Stored assistant references retain structured-output schema breakpoints.

[`Batch downloads`](../../core/batch-text/) accept `ProviderSettings.batchResultDownloads` with a default 64 MiB UTF-8 row limit.
