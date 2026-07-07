import Foundation

public struct AIProviderCapabilityRow: Equatable, Sendable {
    public var providerID: String
    public var upstreamPackage: String
    public var factoryNames: [String]
    public var supportedCapabilities: Set<ModelCapability>
    public var supportsFileUpload: Bool
    public var supportsSkillUpload: Bool
    public var notes: String?

    public init(
        providerID: String,
        upstreamPackage: String,
        factoryNames: [String],
        supportedCapabilities: Set<ModelCapability>,
        supportsFileUpload: Bool = false,
        supportsSkillUpload: Bool = false,
        notes: String? = nil
    ) {
        self.providerID = providerID
        self.upstreamPackage = upstreamPackage
        self.factoryNames = factoryNames
        self.supportedCapabilities = supportedCapabilities
        self.supportsFileUpload = supportsFileUpload
        self.supportsSkillUpload = supportsSkillUpload
        self.notes = notes
    }

    public func supports(_ capability: ModelCapability) -> Bool {
        supportedCapabilities.contains(capability)
    }
}

public enum AIProviderCapabilities {
    public static let markdownSnapshotDate = "2026-06-23"

    public static let all: [AIProviderCapabilityRow] = [
        providerRow("alibaba", "@ai-sdk/alibaba", ["AIProviders.alibaba"], [.language, .embedding, .video], notes: "Alibaba mirrors upstream 2.0.7: `ALIBABA_API_KEY`, versioned user-agent suffix, chat/language callable aliases, DashScope chat completions with thinking/reasoning mapping, generated fallback IDs for missing tool-call IDs, cache-aware usage, DashScope embedding endpoint with dense and sparse option mapping, video submit/poll flow, wan2.6 legacy video protocol, wan2.7 media/ratio video protocol, provider option validation, warnings, provider metadata, and unsupported image families. ProviderV4 type names, ESM-only packaging, Node 22 engines, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("amazon-bedrock", "@ai-sdk/amazon-bedrock", ["AIProviders.amazonBedrock"], [.language, .embedding, .image, .reranking], notes: "Amazon Bedrock Converse, embeddings, images, and reranking mirror upstream 5.0.12: SigV4 and bearer auth, versioned user-agent suffix, Converse request/stream parsing, provider options under `amazonBedrock`/`bedrock`, service tiers, guardrails, top-level reasoning mapping, reasoning replay metadata, cache points, document citations, rich tool-result content, JSON response tool fallback, Cohere batch embeddings up to 96 inputs, Nova/Titan/Cohere embedding response shapes, and the current `bedrockRerankingConfiguration` rerank request key. ProviderV4 type names, ESM-only packaging, Node 22 engines, optional JS headers config, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("amazon-bedrock.anthropic", "@ai-sdk/amazon-bedrock", ["AIProviders.amazonBedrockAnthropic"], [.language], notes: "Bedrock Anthropic mirrors upstream 5.0.12 invoke-model behavior: Anthropic Messages request conversion, Bedrock auth and user-agent handling, URL/data media resolution, native Anthropic tool helpers, structured-output omissions for unsupported models, event-stream decoding, response metadata, and Bedrock-specific request URLs. JS fetch/header injection hooks remain JS-only."),
        providerRow("bedrock-mantle", "@ai-sdk/amazon-bedrock", ["AIProviders.bedrockMantle"], [.language], notes: "Bedrock Mantle mirrors upstream 5.0.12 chat and responses surfaces with Bedrock Mantle hostnames, SigV4 or bearer auth, OpenAI-compatible request builders, versioned user-agent suffix, and provider metadata. JavaScript module-format exports are not applicable in Swift."),
        providerRow("anthropic", "@ai-sdk/anthropic", ["AIProviders.anthropic"], [.language], files: true, skills: true, notes: "Messages support thinking, citations, cache control, hosted/provider-defined tools, streamed code-execution input subtypes, files, skills, and provider metadata. `thinking: disabled` is forwarded to the Messages API. Files and skills clients add the required Anthropic beta headers."),
        providerRow("anthropic-aws", "@ai-sdk/anthropic-aws", ["AIProviders.anthropicAWS"], [.language], files: true, skills: true),
        providerRow("assemblyai", "@ai-sdk/assemblyai", ["AIProviders.assemblyAI"], [.transcription], notes: "AssemblyAI transcription mirrors upstream 3.0.5: `ASSEMBLYAI_API_KEY`, custom headers, versioned user-agent suffix, `transcription`/`transcriptionModel` aliases, `/v2/upload` plus `/v2/transcript` submit/poll flow, legacy `best` via `speech_model`, current `universal-3-5-pro`/`universal-3-pro`/`universal-2` via `speech_models`, deprecation and migration warnings, providerOptions.assemblyai schema including Universal 3 Pro and GA nested options, millisecond-to-second word segment conversion, audio-intelligence provider metadata, raw final response metadata, AssemblyAI error schema, and unsupported language/embedding/image families. ProviderV4, ESM-only packaging, Node 22 engines, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("azure", "@ai-sdk/azure", ["AIProviders.azure"], [.language, .completion, .embedding, .image, .transcription, .speech], notes: "Azure OpenAI mirrors upstream 4.0.8: `AZURE_API_KEY` or per-request Microsoft Entra token provider auth, `AZURE_RESOURCE_NAME`, versioned user-agent suffix, Responses as default callable/language surface, chat/deepseek/completion/embedding/textEmbedding/image/transcription/speech aliases, Azure provider metadata namespace, deployment-based transcription URLs, Azure OpenAI base URLs with `/v1` and `api-version`, custom non-Azure gateway base URLs used as-is, DeepSeek reasoning mapping without thinking support, OpenAI option namespace mapping, and Azure-specific hosted tool helpers."),
        providerRow("baseten", "@ai-sdk/baseten", ["AIProviders.baseten"], [.language, .embedding], notes: "Chat and embedding endpoints mirror upstream Baseten 2.0.5: `BASETEN_API_KEY`, versioned user-agent suffix, custom Model API base URL, `/sync/v1` chat model URLs, `/sync` or `/sync/v1` embedding model URLs, upstream performance-client body plus 128-input batching, unsupported image models, and string `error` envelope parsing."),
        providerRow("black-forest-labs", "@ai-sdk/black-forest-labs", ["AIProviders.blackForestLabs"], [.image], notes: "Black Forest Labs images mirror upstream 2.0.5: `BFL_API_KEY`, `x-key` auth, custom base URL and headers, versioned user-agent suffix, `image`/`imageModel` aliases, `black-forest-labs.image` provider IDs, current FLUX model IDs, `/v1/{model}` submit URLs, response-supplied polling with trusted `bfl.ai` sibling-host credential forwarding, unauthenticated foreign image download, `providerOptions.blackForestLabs` schema mapping, fill-model `image` input field, warnings for size/aspect-ratio handling, response/provider metadata, and unsupported language/embedding families."),
        providerRow("bytedance", "@ai-sdk/bytedance", ["AIProviders.byteDance"], [.video], notes: "ByteDance Seedance video models mirror upstream ByteDance 2.0.6: `ARK_API_KEY`, versioned user-agent suffix, current Dreamina/Seedance model IDs, prompt/image/frameImages/inputReferences mapping, standard `generateAudio` with provider-option fallback, provider options for watermark/camera/returnLastFrame/serviceTier/draft/reference media/polling, resolution mapping, warnings, polling/error metadata, and unsupported non-video families."),
        providerRow("cerebras", "@ai-sdk/cerebras", ["AIProviders.cerebras"], [.language], notes: "Cerebras chat models mirror upstream Cerebras 3.0.5: `CEREBRAS_API_KEY`, custom base URL and headers, callable provider plus `languageModel`/`chat` aliases, `cerebras.chat` provider IDs, versioned user-agent suffix, current model IDs such as `gpt-oss-120b` and `qwen-3-235b-a22b-thinking-2507`, structured outputs, reasoning transform, structured-output tool-call normalization, flat Cerebras error schema, provider options, and unsupported embedding/image families."),
        providerRow("cohere", "@ai-sdk/cohere", ["AIProviders.cohere"], [.language, .embedding, .reranking], notes: "Cohere mirrors upstream 4.0.5: `COHERE_API_KEY`, custom base URL and headers, versioned user-agent suffix, callable/language aliases, embedding/textEmbedding aliases, reranking aliases, chat `/v2/chat`, embedding `/v2/embed`, reranking `/v2/rerank`, prompt conversion for text/images/documents/tool calls, providerOptions.cohere schemas, top-level reasoning to Cohere `thinking` budget mapping, providerOptions thinking precedence, response format and tool choice mapping, streaming lifecycle/tool-call/reasoning parts, response metadata, embedding/reranking response bodies, object-document reranking warnings, and unsupported non-text document media. ProviderV4 type names, ESM-only packaging, Node 22 engines, TypeScript option export renames, optional JS headers config, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("deepgram", "@ai-sdk/deepgram", ["AIProviders.deepgram"], [.transcription, .speech], notes: "Deepgram transcription and speech mirror upstream 3.0.5: `DEEPGRAM_API_KEY`, `Token` auth, custom headers, versioned user-agent suffix, `transcription`/`transcriptionModel` and `speech`/`speechModel` aliases, `/v1/listen` raw-audio transcription with model/diarize defaults and providerOptions.deepgram query mapping, `/v1/speak` JSON TTS with output format to encoding/container/sample-rate mapping, documented TTS provider options, incompatible audio parameter cleanup warnings, unsupported voice/speed/language/instructions warnings, response metadata, Deepgram error schema, and unsupported language/embedding/image families. ProviderV4, ESM-only packaging, Node 22 engines, experimental streaming transcription types, optional JS headers config, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("deepinfra", "@ai-sdk/deepinfra", ["AIProviders.deepInfra"], [.language, .completion, .embedding, .image], notes: "DeepInfra mirrors upstream 3.0.5: `DEEPINFRA_API_KEY`, bearer auth, custom base URL and headers, versioned user-agent suffix, callable/chat/language aliases, completion/embedding/textEmbedding aliases, image/imageModel aliases, `deepinfra.chat`/`.completion`/`.embedding`/`.image` provider IDs, `/openai/*` language/embedding routes, `/inference/{model}` image generation, OpenAI-compatible multipart image edits, Gemma/Gemini reasoning usage correction, `providerOptions.deepinfra` passthrough, max-one generated image per call, and response metadata."),
        providerRow("deepseek", "@ai-sdk/deepseek", ["AIProviders.deepSeek"], [.language], notes: "DeepSeek chat models mirror upstream DeepSeek 3.0.5: `DEEPSEEK_API_KEY`, custom base URL and headers, callable/language/chat aliases, `deepseek.chat` provider IDs, versioned user-agent suffix, reasoning/thinking mapping, providerOptions.deepseek thinking and reasoningEffort schema, cache-aware usage/provider metadata, JSON response instruction injection, generated fallback IDs for missing generate tool-call IDs, streaming response metadata, stream usage, OpenAI-compatible tool calls including strict mode, DeepSeek V4 assistant reasoning_content rules, DeepSeek error schema, and unsupported embedding/image families. ProviderV4 type names, ESM-only packaging, Node 22 engines, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("elevenlabs", "@ai-sdk/elevenlabs", ["AIProviders.elevenLabs"], [.transcription, .speech, .audioGeneration, .audioTransformation, .dubbing], notes: "ElevenLabs speech and transcription mirror upstream 3.0.6: `ELEVENLABS_API_KEY`, `xi-api-key` auth, custom headers, versioned user-agent suffix, camel-case Swift `AIProviders.elevenLabs` factory, `speech`/`speechModel` and `transcription`/`transcriptionModel` aliases, speech `/v1/text-to-speech/{voice}` request builder with output format aliases, voice settings, pronunciation dictionaries, normalization options and warnings, transcription `/v1/speech-to-text` multipart builder with `scribe_v2`, providerOptions.elevenlabs defaults and schema validation, response text/language/segments/duration, response metadata, ElevenLabs error schema, and unsupported language/embedding/image families. SwiftAISDK additionally exposes locally ported ElevenLabs music, sound effects, voice changer, voice isolator, and dubbing helpers. ProviderV4 type names, ESM-only packaging, Node 22 engines, optional JS headers config, TypeScript export split, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("fal", "@ai-sdk/fal", ["AIProviders.fal"], [.image, .transcription, .speech, .video], notes: "Fal image, transcription, speech, and video models mirror upstream Fal 3.0.6: `FAL_API_KEY`/`FAL_KEY`, `Key` auth, custom base URL and headers, versioned user-agent suffix, image/transcription/speech/video aliases, image `/fal.run/{model}` requests with file and mask data URI mapping, native speech generation plus unauthenticated audio download, queue-based transcription and video polling, same-origin credential forwarding for video response URLs, foreign response URL credential stripping, providerOptions.fal schemas and camelCase-to-snake_case mapping, deprecated image snake_case warnings, video `video/mp4` media type fallback, response/provider metadata, Fal error schema, and unsupported language/embedding families. ProviderV4 type names, ESM-only packaging, Node 22 engines, TypeScript option export splits, optional JS headers config, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("fireworks", "@ai-sdk/fireworks", ["AIProviders.fireworks"], [.language, .completion, .embedding, .image], notes: "Fireworks mirrors upstream Fireworks 3.0.6: `FIREWORKS_API_KEY`, bearer auth, custom base URL and headers, versioned user-agent suffix, callable/chat/language/completion/embedding/textEmbedding/image/imageModel aliases, flat error schema, includeUsage streaming by default, current Kimi K2.6 and Minimax M2 model IDs, thinking/reasoningHistory/promptCacheKey/serviceTier mapping, reasoning_effort minimal/xhigh normalization, sync and async image endpoints, same-origin credential forwarding for async downloads, providerOptions.fireworks passthrough, warnings, and response metadata. ProviderV4, ESM-only packaging, Node 22 engines, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("gateway", "@ai-sdk/gateway", ["AIProviders.gateway"], [.language, .embedding, .image, .transcription, .speech, .video, .reranking], notes: "Gateway mirrors upstream 4.0.12: default `/v4/ai` base URL, `AI_GATEWAY_API_KEY`/`VERCEL_OIDC_TOKEN` auth, team scoping, protocol/auth-method headers, versioned user-agent suffix, language/embedding/image/video/reranking/speech/transcription aliases, v4 model headers, Gateway providerOptions including BYOK/routing/compliance/sort/serviceTier/quota/tags, base64 inline file forwarding, response warnings/provider metadata, model/credits/spend/generation metadata APIs, Gateway error mapping/retryability, and provider tools. Experimental realtime client-secret/WebSocket support, Vercel o11y headers, ProviderV4 type names, ESM-only packaging, Node 22 engines, and workflow serialization helpers are JS/runtime-only gaps."),
        providerRow("gladia", "@ai-sdk/gladia", ["AIProviders.gladia"], [.transcription], notes: "Gladia transcription mirrors upstream 3.0.5: `GLADIA_API_KEY`, `x-gladia-key` auth, custom headers, versioned user-agent suffix, `transcription`/`transcriptionModel` aliases, `/v2/upload` multipart audio upload, `/v2/pre-recorded` initiation, provider-supplied result polling with same-origin credential forwarding, foreign result URL credential stripping, providerOptions.gladia schema and snake_case mapping, result text/language/segments/duration, response/provider metadata, Gladia error schema, lifecycle errors, and unsupported language/embedding/image families. ProviderV4 type names, ESM-only packaging, Node 22 engines, optional JS headers config, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("google.generative-ai", "@ai-sdk/google", ["AIProviders.google"], [.language, .embedding, .image, .speech, .video], files: true, notes: "Google Generative AI mirrors upstream Google 4.0.8 across Gemini language, embeddings, Imagen/Gemini image generation, Gemini TTS speech, Veo video, files, interactions models, and agents. Speech maps Gemini TTS generateContent requests with WAV-wrapped PCM by default, raw PCM opt-in, multi-speaker provider options, response sample-rate metadata, and upstream warnings. Realtime/WebSocket and JS ProviderV4 runtime helpers remain JS-only gaps."),
        providerRow("google.vertex", "@ai-sdk/google-vertex", ["AIProviders.googleVertex"], [.language, .embedding, .image, .speech, .transcription, .video], notes: "Vertex mirrors upstream Google Vertex 5.0.11 across Gemini language, tuned endpoint models, embeddings, Imagen image generation/editing, Gemini TTS speech, Cloud Speech-to-Text transcription, Veo video, and the Vertex Interactions API. Video supports first/last frame images, reference images, and top-level generateAudio precedence. Speech maps Gemini TTS generateContent requests with WAV-wrapped PCM by default, raw PCM opt-in, multi-speaker provider options, sample-rate metadata, and upstream warnings. Node google-auth-library options, workflow serialization, ProviderV4 type names, and ESM-only packaging remain JS-runtime/package-surface concerns."),
        providerRow("googleVertex.maas", "@ai-sdk/google-vertex", ["AIProviders.googleVertexMaaS"], [.language, .completion, .embedding, .image]),
        providerRow("googleVertex.xai", "@ai-sdk/google-vertex", ["AIProviders.googleVertexXAI"], [.language]),
        providerRow("googleVertex.anthropic", "@ai-sdk/google-vertex", ["AIProviders.googleVertexAnthropic"], [.language]),
        providerRow("groq", "@ai-sdk/groq", ["AIProviders.groq"], [.language, .transcription], notes: "Groq mirrors upstream 4.0.5: `GROQ_API_KEY`, custom base URL and headers, versioned user-agent suffix, callable/language aliases, transcription aliases, chat `/openai/v1/chat/completions`, transcription `/openai/v1/audio/transcriptions`, OpenAI-compatible prompt conversion, Qwen/gpt-oss reasoning content, top-level reasoning to reasoning_effort mapping with providerOptions precedence and compatibility warnings, Groq provider options, browser_search provider tool gating, service tiers, structured outputs, stream usage/metadata, tool-call streaming validation, transcription multipart options/validation, response metadata, Groq error schema, and unsupported embedding/image families. ProviderV4 type names, ESM-only packaging, Node 22 engines, TypeScript option export renames, optional JS headers config, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("huggingface", "@ai-sdk/huggingface", ["AIProviders.huggingFace"], [.language], notes: "Hugging Face Responses language models mirror upstream Hugging Face 2.0.5: `HUGGINGFACE_API_KEY`, custom base URL and headers, versioned user-agent suffix, callable/language/responses aliases, `/v1/responses` request builder, providerOptions.huggingface metadata/instructions/strictJsonSchema/reasoningEffort schema, structured text formats, function tools/tool choice, reasoning and MCP/tool-call parsing, streaming lifecycle and metadata, image URL/data file parts including top-level `image` and `image/*` MIME resolution, explicit provider-reference file rejection, and unsupported embedding/image families. ProviderV4 type names, ESM-only packaging, Node 22 engines, default export rename to `huggingFace`, optional JS headers config, TypeScript option export split, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("hume", "@ai-sdk/hume", ["AIProviders.hume"], [.speech], notes: "Hume speech mirrors upstream 3.0.5: `HUME_API_KEY`, `X-Hume-Api-Key` auth, custom headers, versioned user-agent suffix, no-argument `speech`/`speechModel` aliases, default voice ID, `/v0/tts/file`, binary audio responses, mp3/pcm/wav output formats, language warnings, `providerOptions.hume.context` schema mapping, response metadata, and unsupported language/embedding/image families."),
        providerRow("klingai", "@ai-sdk/klingai", ["AIProviders.klingAI"], [.video], notes: "KlingAI video models mirror upstream KlingAI 4.0.6: `KLINGAI_API_KEY`, custom base URL and headers, versioned user-agent suffix, `video`/`videoModel` aliases, JWT bearer auth, text-to-video, image-to-video, reference-to-video multi-image, and motion-control endpoints, first/last `frameImages`, `inputReferences`, top-level `generateAudio` to `sound` mapping with provider-option override behavior, providerOptions.klingai schema and snake_case passthrough, polling, `video/mp4` media type, provider metadata, KlingAI error schema, and warnings for unsupported standard video options. ProviderV4 type names, ESM-only packaging, Node 22 engines, TypeScript option export split, optional JS headers config, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("lmnt", "@ai-sdk/lmnt", ["AIProviders.lmnt"], [.speech], notes: "LMNT speech mirrors upstream 3.0.5: `LMNT_API_KEY`, `x-api-key` auth, custom headers, versioned user-agent suffix, `speech`/`speechModel` aliases, default voice `ava`, `/v1/ai/speech/bytes`, binary audio responses, output format warnings/fallback, `providerOptions.lmnt` speech schema defaults, response metadata, and unsupported language/embedding/image families."),
        providerRow("luma", "@ai-sdk/luma", ["AIProviders.luma"], [.image], notes: "Luma images mirror upstream Luma 3.0.6: `LUMA_API_KEY`, bearer auth, custom base URL and headers, versioned user-agent suffix, `image`/`imageModel` aliases, `luma.image` provider IDs, `photon-1` and `photon-flash-1` model IDs, `/dream-machine/v1/generations/image`, async polling, unauthenticated generated image download, warnings for unsupported size/seed, `providerOptions.luma` referenceType/images/polling schema, URL-only image references, response metadata, and unsupported language/embedding families."),
        providerRow("mistral", "@ai-sdk/mistral", ["AIProviders.mistral"], [.language, .embedding], notes: "Mistral chat and embeddings mirror upstream Mistral 4.0.5: `MISTRAL_API_KEY`, custom base URL and headers, versioned user-agent suffix, callable/language/chat and embedding/textEmbedding aliases, chat `/v1/chat/completions`, embeddings `/v1/embeddings`, structured outputs, JSON-object instruction injection, stop sequences via native `stop`, top-level reasoning mapped to supported Mistral reasoning effort with providerOptions precedence, provider option schema validation, tool/tool-choice mapping, tool-result output conversion, image/PDF user file support, streaming text/reasoning/tool lifecycle, cached-token usage accounting, response metadata, Mistral error schema, and unsupported image/speech/transcription families. ProviderV4 type names, ESM-only packaging, Node 22 engines, optional JS headers config, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("moonshotai", "@ai-sdk/moonshotai", ["AIProviders.moonshotAI"], [.language], notes: "MoonshotAI chat models mirror upstream MoonshotAI 3.0.7: `MOONSHOT_API_KEY`, custom base URL and headers, callable provider plus `languageModel`/`chat` aliases, `moonshotai.chat` provider IDs, versioned user-agent suffix, stream usage by default, current model IDs such as `kimi-k2.5`, `kimi-k2.6`, and `kimi-k2.7-code`, `providerOptions.moonshotai` thinking/reasoningHistory mapping, structured outputs for `kimi-k*` models with top-level `$schema` stripping, Moonshot error schema, and unsupported embedding/image families."),
        providerRow("open-responses.responses", "@ai-sdk/open-responses", ["AIProviders.openResponses"], [.language], notes: "Custom URL factory mirrors upstream open-responses 2.0.5: provider ID is derived from the caller supplied name, optional API key and custom headers receive the versioned user-agent suffix, request building covers file URL/data inputs, rich tool-result content, function tools, tool choice, structured text formats, top-level reasoning effort mapping, providerOptions reasoningSummary, precise denied-tool fallback text, finish reasons, usage, response metadata, and Responses streaming lifecycle parsing. ProviderV4 type names, ESM-only packaging, Node 22 engines, optional JS headers config, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("openai", "@ai-sdk/openai", ["AIProviders.openAI"], [.language, .completion, .embedding, .image, .transcription, .speech], files: true, skills: true, notes: "OpenAI mirrors upstream 4.0.8 across Chat Completions, Responses language models, completions, embeddings, images, speech, transcription, files, skills, hosted Responses tools, provider tool helpers, organization/project headers, structured output, usage details, response/provider metadata, warnings, raw stream chunks, provider references, Responses allowedTools/tool-search/namespace handling, server-side compaction items, retryable pre-output stream failures, and Chat file-part mapping for image/audio/PDF inputs. Realtime/WebSocket models, ProviderV4 type names, ESM-only packaging, Node 22 engines, and workflow serialization helpers remain JS-runtime/package-surface concerns."),
        providerRow("openai-compatible", "@ai-sdk/openai-compatible", ["AIProviders.openAICompatible"], [.language, .completion, .embedding, .image], notes: "Generic OpenAI-compatible factory mirrors upstream 3.0.5: caller supplies provider ID and base URL, custom headers/query params, versioned user-agent suffix, upstream surface IDs, chat/completion/embedding/image models, providerOptions namespace unwrapping with raw and camelCase keys, deprecated raw-key warnings, structured outputs, stream usage, response/provider metadata, and camelCase provider metadata namespace selection when camelCase providerOptions are used. ProviderV4 type names, ESM-only packaging, Node 22 engines, optional JS headers config, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("perplexity", "@ai-sdk/perplexity", ["AIProviders.perplexity"], [.language], notes: "Perplexity chat mirrors upstream Perplexity 4.0.6: `PERPLEXITY_API_KEY`, custom base URL and headers, versioned user-agent suffix, callable/language aliases, `/chat/completions`, text/image/PDF message conversion, JSON schema response format, providerOptions.perplexity passthrough, citations/images/cost metadata, optional and null streaming delta content, reasoning-token usage accounting, Perplexity error schema, and warnings for unsupported topK/stop/seed/custom reasoning while treating provider-default reasoning as a no-op. ProviderV4 type names, ESM-only packaging, Node 22 engines, optional JS headers config, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("prodia", "@ai-sdk/prodia", ["AIProviders.prodia"], [.language, .image, .video], notes: "Prodia language, image, and video models mirror upstream Prodia 2.0.6: `PRODIA_TOKEN`/`PRODIA_API_KEY`, custom base URL and headers, versioned user-agent suffix, language/image/video aliases, `/v2/job?price=true` JSON and multipart job submission, multipart text/image/video responses, language image input MIME detection, providerOptions.prodia schemas, custom reasoning warnings with provider-default no-op, request/response metadata, Prodia job provider metadata including price, Prodia error schema, SSRF-guarded video image downloads, and unsupported embedding/speech/transcription families. ProviderV4 type names, ESM-only packaging, Node 22 engines, TypeScript option export renames, optional JS headers config, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("quiverai", "@ai-sdk/quiverai", ["AIProviders.quiverAI"], [.image], notes: "SVG image generation and vectorization mirror upstream QuiverAI 2.0.5: `QUIVERAI_API_KEY`/`QUIVERAI_BASE_URL`, versioned user-agent suffix, `arrow-1`/`arrow-1.1`/`arrow-1.1-max`, `providerOptions.quiverai` generation and vectorize options, reference limits, warnings for unsupported standard image options, and retryable API error metadata."),
        providerRow("replicate", "@ai-sdk/replicate", ["AIProviders.replicate"], [.image, .video], notes: "Replicate image and video models mirror upstream Replicate 3.0.6: `REPLICATE_API_TOKEN`, custom base URL and headers, versioned user-agent suffix, `image`/`imageModel` and `video`/`videoModel` aliases, versioned and unversioned prediction endpoints, `prefer: wait` headers, image output downloads without credential forwarding, image editing inputs and masks, Flux-2 multi-image input mapping and warnings, loose providerOptions.replicate schemas, video polling with same-origin credential forwarding, provider metadata, `video/mp4` media type, Replicate error schema, and unsupported language/embedding families. ProviderV4 type names, ESM-only packaging, Node 22 engines, TypeScript option export renames, optional JS headers config, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("revai", "@ai-sdk/revai", ["AIProviders.revAI"], [.transcription], notes: "Rev.ai transcription mirrors upstream 3.0.5: `REVAI_API_KEY`, bearer auth, custom headers, versioned user-agent suffix, `transcription`/`transcriptionModel` aliases, `revai.transcription` provider IDs, `/speechtotext/v1/jobs` submit/poll/transcript flow, multipart `media` plus JSON `config`, providerOptions.revai schema/defaults, job/transcript response validation, Rev.ai error schema, text/segment/duration extraction, response metadata, and unsupported language/embedding/image families. ProviderV4, ESM-only packaging, Node 22 engines, experimental streaming transcription types, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("togetherai", "@ai-sdk/togetherai", ["AIProviders.togetherAI"], [.language, .completion, .embedding, .image, .reranking], notes: "TogetherAI mirrors upstream TogetherAI 3.0.6: `TOGETHER_API_KEY` with deprecated `TOGETHER_AI_API_KEY` fallback, versioned user-agent suffix, language/completion/embedding/image/reranking factories, image `n` request mapping despite upstream `maxImagesPerCall = 1`, loose image provider options, reranking `rankFields`, and upstream-focused image/reranking response validation. ProviderV4, ESM-only packaging, Node 22 engines, and workflow serialization helpers are JS-only upstream concerns."),
        providerRow("vercel", "@ai-sdk/vercel", ["AIProviders.vercel"], [.language], notes: "Vercel v0 chat models mirror upstream Vercel 3.0.5: `VERCEL_API_KEY`, custom base URL and headers, callable provider and `languageModel` aliases, `vercel.chat` provider IDs, versioned user-agent suffix, and unsupported embedding/image families."),
        providerRow("voyage", "@ai-sdk/voyage", ["AIProviders.voyage"], [.embedding, .reranking], notes: "Voyage embeddings and reranking mirror upstream Voyage 2.0.5: `VOYAGE_API_KEY`, custom base URL and headers, versioned user-agent suffix, `embedding`/`embeddingModel`/`textEmbedding`/`textEmbeddingModel` aliases, `reranking`/`rerankingModel` aliases, current Voyage 4/3.5/code and rerank model IDs, provider option schema mapping, 128-input embedding preflight, sorted embedding responses by index, nullish embedding usage as zero tokens, object-document reranking warnings, and v4 rerank response validation without required usage."),
        providerRow("xai", "@ai-sdk/xai", ["AIProviders.xAI"], [.language, .image, .transcription, .speech, .video], files: true, notes: "xAI mirrors upstream 4.0.7: `XAI_API_KEY`, custom base URL and headers, versioned user-agent suffix, callable/language Responses default, chat/responses/image/video/files aliases, no-argument `speech`/`speechModel` and `transcription`/`transcriptionModel` aliases, Responses provider options and hosted tools, chat reasoningEffort values `none`/`low`/`medium`/`high`, image generation/editing, video generation/edit/extend/reference modes, `/tts` speech generation with voice/language/output_format/provider options, `/stt` multipart batch transcription with options and word segments, Files API provider references, response metadata, and xAI error schema. Upstream realtime speech-to-speech and WebSocket streaming STT are experimental JS runtime surfaces not yet represented by SwiftAISDK protocols; ProviderV4 type names, ESM-only packaging, Node 22 engines, optional JS headers/WebSocket config, and workflow serialization helpers are JS-only upstream concerns.")
    ]

    public static func row(providerID: String) -> AIProviderCapabilityRow? {
        all.first { $0.providerID == providerID }
    }

    public static func rows(upstreamPackage: String) -> [AIProviderCapabilityRow] {
        all.filter { $0.upstreamPackage == upstreamPackage }
    }

    public static func markdownDocument(snapshotDate: String = markdownSnapshotDate) -> String {
        var lines: [String] = [
            "# Provider Capability Matrix",
            "",
            "Snapshot date: \(snapshotDate)",
            "",
            "This document is generated from `AIProviderCapabilities` in",
            "`Sources/SwiftAISDK/Providers/ProviderCapabilityMatrix.swift`. Update that",
            "file first when adding or changing provider coverage; the drift test will",
            "fail until this document is regenerated from the same source.",
            "",
            "Legend:",
            "",
            "- `L`: language",
            "- `C`: completion",
            "- `E`: embedding",
            "- `I`: image",
            "- `T`: transcription",
            "- `S`: speech",
            "- `AG`: audio generation",
            "- `AT`: audio transformation",
            "- `D`: dubbing",
            "- `V`: video",
            "- `R`: reranking",
            "- `F`: file upload client",
            "- `K`: skill upload client",
            "",
            markdownTable(),
        ]

        let rowsWithNotes = all.filter { $0.notes != nil }
        if !rowsWithNotes.isEmpty {
            lines.append(contentsOf: [
                "",
                "## Provider Notes",
                "",
                "| Provider ID | Note |",
                "| --- | --- |",
            ])

            for row in rowsWithNotes {
                lines.append("| `\(escapeMarkdownTable(row.providerID))` | \(escapeMarkdownTable(row.notes ?? "")) |")
            }
        }

        lines.append(contentsOf: [
            "",
            "## Reality Gates",
            "",
            "Use three gates when judging provider completeness:",
            "",
            "1. The provider appears in `AIProviderCapabilities.all`.",
            "2. Unit tests cover the request and response or stream shape for every",
            "   supported capability in the matrix.",
            "3. At least one opt-in live smoke test exists for representative",
            "   providers and can be run with real keys.",
            "",
            "The live smoke suite is intentionally off by default. Run it with:",
            "",
            "```sh",
            "LIVE_AI_TESTS=1 swift test --filter LiveProviderSmoke",
            "```",
            "",
            "The suite reads `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`,",
            "`DEEPSEEK_API_KEY`, `ASSEMBLYAI_API_KEY`, `ELEVENLABS_API_KEY`,",
            "and `OPENAI_COMPATIBLE_API_KEY`.",
            "When running from Xcode, set them as test environment variables in the",
            "scheme instead of Run/Profile arguments.",
            "Override model IDs with",
            "`LIVE_OPENAI_MODEL`, `LIVE_ANTHROPIC_MODEL`, `LIVE_GOOGLE_MODEL`,",
            "`LIVE_DEEPSEEK_MODEL`, `LIVE_ASSEMBLYAI_MODEL`, `LIVE_OPENAI_COMPATIBLE_MODEL`,",
            "`LIVE_OPENAI_COMPATIBLE_BASE_URL`, `LIVE_ELEVENLABS_SPEECH_MODEL`,",
            "`LIVE_ELEVENLABS_TRANSCRIPTION_MODEL`, and `LIVE_ELEVENLABS_VOICE`.",
            "It covers text generation, text streaming, executable generate/stream tool loops,",
            "OpenAI-compatible generation/streaming/completion/tool loops/object generation,",
            "AssemblyAI transcription, ElevenLabs speech/transcription/audio generation/audio",
            "transformation/dubbing, and representative embeddings.",
            "Embedding checks also read",
            "`LIVE_OPENAI_EMBEDDING_MODEL` and `LIVE_GOOGLE_EMBEDDING_MODEL`.",
            "",
        ])

        return lines.joined(separator: "\n")
    }

    public static func markdownTable() -> String {
        let supportedMarker = "✅"
        let header = (["Upstream package", "Provider ID", "Swift factories"] + capabilityColumns.map(\.label) + ["F", "K"]).asMarkdownTableRow()
        let separator = Array(repeating: "---", count: 3 + capabilityColumns.count + 2).asMarkdownTableRow()
        let rows = all.map { row in
            let values = capabilityColumns.map { column in
                row.supports(column.capability) ? supportedMarker : ""
            }
            let flags = values + [
                row.supportsFileUpload ? supportedMarker : "",
                row.supportsSkillUpload ? supportedMarker : "",
            ]
            return (
                [
                    "`\(escapeMarkdownTable(row.upstreamPackage))`",
                    "`\(escapeMarkdownTable(row.providerID))`",
                    row.factoryNames.map { "`\(escapeMarkdownTable($0))`" }.joined(separator: ", "),
                ] + flags
            ).asMarkdownTableRow()
        }

        return ([header, separator] + rows).joined(separator: "\n")
    }
}

private func providerRow(
    _ providerID: String,
    _ upstreamPackage: String,
    _ factoryNames: [String],
    _ capabilities: Set<ModelCapability>,
    files: Bool = false,
    skills: Bool = false,
    notes: String? = nil
) -> AIProviderCapabilityRow {
    AIProviderCapabilityRow(
        providerID: providerID,
        upstreamPackage: upstreamPackage,
        factoryNames: factoryNames,
        supportedCapabilities: capabilities,
        supportsFileUpload: files,
        supportsSkillUpload: skills,
        notes: notes
    )
}

private let capabilityColumns: [(label: String, capability: ModelCapability)] = [
    ("L", .language),
    ("C", .completion),
    ("E", .embedding),
    ("I", .image),
    ("T", .transcription),
    ("S", .speech),
    ("AG", .audioGeneration),
    ("AT", .audioTransformation),
    ("D", .dubbing),
    ("V", .video),
    ("R", .reranking),
]

private func escapeMarkdownTable(_ value: String) -> String {
    value.replacingOccurrences(of: "|", with: "\\|")
}

private extension Array where Element == String {
    func asMarkdownTableRow() -> String {
        "| \(joined(separator: " | ")) |"
    }
}
