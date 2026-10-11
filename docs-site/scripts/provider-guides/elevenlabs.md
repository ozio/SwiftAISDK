## Speaker evidence in batch transcription

Scribe transcription defaults to diarization enabled and sends one explicit `diarize` multipart field. Set `providerOptions.elevenlabs.diarize` to false to disable it. Returned words, including speaker IDs, are preserved in `providerMetadata["elevenlabs"]["words"]` alongside normalized segments.
