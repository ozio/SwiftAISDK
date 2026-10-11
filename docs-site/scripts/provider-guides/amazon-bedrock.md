## Reasoning, dimensions, and Haiku 5.5

Explicit disabled reasoning removes unused effort and budget fields. Explicit provider effort/budget overrides portable defaults; type/display-only settings still derive missing values. Portable `max` remains max for supported families and maps to high with a warning for Nova 2.

Titan, Cohere and Nova embeddings accept top-level dimensions unless the provider-specific dimensions override them. Haiku 5.5 uses the JSON tool fallback where Bedrock native structured output is unsupported; explicit `strict: false` does not warn. SigV4 excludes non-ASCII header values from signed headers while retaining outgoing values.
