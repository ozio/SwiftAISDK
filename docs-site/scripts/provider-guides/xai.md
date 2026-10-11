## Streaming transcription and current image options

`streamingTranscriptionModel(_:webSocketTransport:)` uses an injectable WebSocket transport. Audio format, sample rate, VAD, partial/final utterances, multi-channel input, finish metadata and producer cancellation follow the published xAI streaming contract. `opus` is also accepted for batch transcription. The requested model ID is retained by transcription factories.

Image capabilities recognize `grok-imagine-image-2.0`; options add 1.5k resolution and auto quality. X Search permits up to 20 allowed/excluded handles. Portable reasoning `max` maps to the provider's highest effort. Existing realtime sessions and Responses calls keep their separate native APIs.
