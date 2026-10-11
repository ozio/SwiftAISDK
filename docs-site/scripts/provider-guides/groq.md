## JSON output with function tools

Groq can combine `.json(schema: ...)` with application function tools using a collision-safe synthetic JSON response tool. Its arguments become JSON text while real application calls retain their lifecycle. Generation and streams omit the synthetic call and conversational prose. An explicit application tool choice is preserved; `none` selects the response tool. Portable reasoning `max` maps to high.
