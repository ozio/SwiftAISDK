## Awaitable lifecycle and restored tools

`await session.stopAndWait()` waits for active send/reconnect consumer tasks to settle;
`await session.dispose()` also calls the transport's defaultable `close()`.
Existing synchronous `stop()` remains available. Cancellation suppresses an
automatic follow-up even when a restored or superseded stream settles later.
Custom transports own the completion of asynchronous producers that ignore
cancellation: the public stream contract has no producer-completion handle.

Use `AIUIMessageToolSchema` with schema-aware `validateUIMessages` or
`validateUIMessagesForAgent`. Async overloads accept `refineToolInput` callbacks
and check the preserved pre-refinement approval input before refinement.
DirectAIChatTransport bridges current tool refiners and output converters.

Agent normalization records `unavailableStaticToolCallIDs` for removed static
tools. Successful missing-tool outputs become an omission message; dynamic
outputs, errors and tools restored with a current converter keep their intended
model representation. Browser HTTP/WebSocket framing and explicit UI stream
step boundaries remain separate deferred surfaces.
