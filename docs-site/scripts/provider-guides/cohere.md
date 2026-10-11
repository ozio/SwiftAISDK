## Embedding formats and usage

Cohere embeddings accept output dimensions 256, 512, 768, 1024, 1536 and 2048. `providerOptions.cohere.embeddingType` selects float (default), int8, uint8, binary or ubinary; the parser requires the matching response array. Packed binary values remain numeric bytes rather than being unpacked. Provider dimensions override generic request dimensions.

Input cache-read usage is recorded separately and subtracted from uncached input tokens, while raw provider usage remains available in generation and streaming.
