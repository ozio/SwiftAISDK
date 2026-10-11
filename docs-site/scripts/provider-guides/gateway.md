## Decisions, embeddings, and bounded batches

Use `decisionModel(...)` with [Decision](../../core/decide/); legacy Evaluation factories use the new `/decision-model` envelope while retaining Swift call signatures. Embedding calls forward generic dimensions. Provider/model catalogs accept decision entries as open strings.

Both provider-owned and language-model batch result routes use `ProviderSettings.batchResultDownloads`, defaulting to a 64 MiB limit per UTF-8 row. Oversized rows fail with `AIDownloadError` and cancel the producer.

When xAI/SpaceXAI diarization is requested but no nested raw speaker evidence is returned, transcription adds an unsupported-option warning. Existing provider metadata remains available for callers that receive speaker evidence.
