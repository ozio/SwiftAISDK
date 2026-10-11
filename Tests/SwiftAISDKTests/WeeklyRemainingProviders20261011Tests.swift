import Foundation
import Testing
@testable import SwiftAISDK

@Suite("WeeklyRemainingProviders20261011Tests")
struct WeeklyRemainingProviders20261011Tests {
    @Test func embeddingDimensionsUseGenericDefaultsAndProviderOverrides() async throws {
        let alibaba = RecordingTransport(response: jsonResponse(#"{"output":{"embeddings":[{"text_index":0,"embedding":[1]}]}}"#))
        let alibabaModel = try AIProviders.alibaba(settings: .init(apiKey: "key", transport: alibaba)).embeddingModel("text-embedding-v4")
        _ = try await alibabaModel.embed(.init(values: ["one"], dimensions: 768))
        _ = try await alibabaModel.embed(.init(values: ["two"], dimensions: 768, providerOptions: ["alibaba": ["dimension": 1024]]))
        let alibabaRequests = await alibaba.requests()
        #expect(try weeklyRequestJSON(alibabaRequests[0])["parameters"]?["dimension"] == 768)
        #expect(try weeklyRequestJSON(alibabaRequests[1])["parameters"]?["dimension"] == 1024)

        let voyage = RecordingTransport(response: jsonResponse(#"{"data":[{"index":0,"embedding":[1]}]}"#))
        let voyageModel = try AIProviders.voyage(settings: .init(apiKey: "key", transport: voyage)).embeddingModel("voyage-3")
        _ = try await voyageModel.embed(.init(values: ["one"], dimensions: 768))
        _ = try await voyageModel.embed(.init(values: ["two"], dimensions: 768, providerOptions: ["voyage": ["outputDimension": 1024]]))
        let voyageRequests = await voyage.requests()
        #expect(try weeklyRequestJSON(voyageRequests[0])["output_dimension"] == 768)
        #expect(try weeklyRequestJSON(voyageRequests[1])["output_dimension"] == 1024)

        let perplexity = RecordingTransport(response: jsonResponse(#"{"data":[{"embedding":"AQ=="}]}"#))
        let perplexityModel = try AIProviders.perplexity(settings: .init(apiKey: "key", transport: perplexity)).embeddingModel("pplx-embed-v1")
        _ = try await perplexityModel.embed(.init(values: ["one"], dimensions: 768))
        _ = try await perplexityModel.embed(.init(values: ["two"], dimensions: 768, providerOptions: ["perplexity": ["dimensions": 1024]]))
        let perplexityRequests = await perplexity.requests()
        #expect(try weeklyRequestJSON(perplexityRequests[0])["dimensions"] == 768)
        #expect(try weeklyRequestJSON(perplexityRequests[1])["dimensions"] == 1024)

        let gateway = RecordingTransport(response: jsonResponse(#"{"embeddings":[[1]]}"#))
        _ = try await AIProviders.gateway(settings: .init(apiKey: "key", transport: gateway)).embeddingModel("openai/text-embedding-3-small").embed(.init(values: ["one"], dimensions: 768))
        #expect(try weeklyRequestJSON(try #require(await gateway.requests().first))["dimensions"] == 768)
    }

    @Test(arguments: ["xhigh", "max"]) func deepSeekHighestReasoningEffortUsesPublishedMax(_ reasoning: String) async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"done"},"finish_reason":"stop"}]}"#))
        let model = try AIProviders.deepSeek(settings: .init(apiKey: "key", transport: transport)).languageModel("deepseek-reasoner")
        _ = try await model.generate(.init(messages: [.user("test")], reasoning: reasoning))
        #expect(try weeklyRequestJSON(try #require(await transport.requests().first))["reasoning_effort"] == "max")
    }

    @Test func alibabaMaxReasoningUsesNinetyFivePercentBudget() async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"choices":[{"message":{"content":"done"},"finish_reason":"stop"}]}"#))
        let model = try AIProviders.alibaba(settings: .init(apiKey: "key", transport: transport)).languageModel("qwen3-max")
        _ = try await model.generate(.init(messages: [.user("test")], maxOutputTokens: 10_000, reasoning: "max"))
        #expect(try weeklyRequestJSON(try #require(await transport.requests().first))["thinking_budget"] == 15_565)
    }

    @Test func perplexityMaxMapsToXhighAndUnknownReasoningIsOmittedWithWarning() async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-agent","created_at":1710000000,"model":"sonar","object":"response","status":"completed","output":[{"type":"message","id":"msg-1","content":[{"type":"output_text","text":"done","annotations":[]}]}]}"#))
        let model = try AIProviders.perplexity(settings: .init(apiKey: "key", transport: transport)).languageModel("sonar")
        _ = try await model.generate(.init(messages: [.user("test")], reasoning: "max"))
        let unsupported = try await model.generate(.init(messages: [.user("test")], reasoning: "unknown"))
        let requests = await transport.requests()
        #expect(try weeklyRequestJSON(requests[0])["reasoning"]?["effort"] == "xhigh")
        #expect(try weeklyRequestJSON(requests[1])["reasoning"] == nil)
        #expect(unsupported.warnings.contains { $0.feature == "reasoning" && $0.type == "unsupported" })
    }

    @Test func elevenLabsWordMetadataPreservesSpeakerEvidence() async throws {
        let raw = #"{"text":"hello","language_code":"eng","language_probability":0.99,"words":[{"text":"hello","start":0,"end":1,"type":"word","speaker_id":"speaker_0","logprob":-0.01}]}"#
        let transport = RecordingTransport(response: jsonResponse(raw))
        let result = try await AIProviders.elevenLabs(settings: .init(apiKey: "key", transport: transport)).transcriptionModel("scribe_v2").transcribe(.init(audio: Data([1]), mimeType: "audio/wav", providerOptions: ["elevenlabs": ["diarize": true]]))
        #expect(result.providerMetadata["elevenlabs"]?["words"] == (try secureJSONParse(raw))["words"])
        #expect(result.segments == [.init(text: "hello", startSecond: 0, endSecond: 1)])
    }

    @Test(arguments: ["xai", "spacexai"]) func gatewayDiarizationWarningChecksAllRawNestedSpeakerFields(_ namespace: String) async throws {
        let transport = RecordingTransport(responses: [
            jsonResponse(#"{"text":"hello","segments":[{"text":"hello","startSecond":0,"endSecond":1}],"providerMetadata":{"xai":{"speaker":null}}}"#),
            jsonResponse(#"{"text":"hello","providerMetadata":{"xai":{"words":[{"speaker":0}]}}}"#),
            jsonResponse(#"{"text":"hello"}"#)
        ])
        let provider = try AIProviders.gateway(settings: .init(apiKey: "key", transport: transport))
        let model = try provider.transcriptionModel("\(namespace)/grok-stt")
        let warning = try await model.transcribe(.init(audio: Data([1]), providerOptions: [namespace: ["diarize": true]]))
        #expect(warning.warnings.map(\.feature) == ["providerOptions.xai.diarize"])
        let evidence = try await model.transcribe(.init(audio: Data([1]), providerOptions: [namespace: ["diarize": true]]))
        #expect(evidence.warnings.isEmpty)
        #expect(evidence.providerMetadata["xai"]?["words"]?[0]?["speaker"] == 0)
        let notRequested = try await model.transcribe(.init(audio: Data([1])))
        #expect(notRequested.warnings.isEmpty)
    }

    @Test(arguments: [true, false]) func gatewayBatchLimitsApplyToLanguageAndProviderRoutes(_ serviceRoute: Bool) async throws {
        let transport = WeeklyGatewayBatchTransport(chunks: [Data("{\"id\":\"é".utf8), Data(repeating: 0x61, count: 32)])
        var settings = ProviderSettings(apiKey: "key", transport: transport)
        settings.batchResultDownloads = .init(maxLineBytes: 16)
        let provider = try AIProviders.gateway(settings: settings)
        do {
            if serviceRoute {
                let stream = try await provider.experimentalBatch().getBatchResults(.init(batchID: "batch_1"))
                for try await _ in stream {}
            } else {
                let model = try #require(try provider.languageModel("openai/gpt-6-luna") as? any BatchLanguageModel)
                for try await _ in try await model.getBatchResults(.init(batchID: "batch_1")) {}
            }
            Issue.record("Expected per-row limit")
        } catch let error as AIDownloadError {
            #expect(error.message.contains("16 bytes"))
        }
        #expect(transport.cancellations.value > 0)
    }

    @Test func gatewayManyShortRowsInLargeChunkRemainValidWithBomAndCrlf() async throws {
        let line = #"{"id":"one","status":"cancelled"}"#
        let transport = WeeklyGatewayBatchTransport(chunks: [Data(("\u{FEFF}" + line + "\r\n\n" + line).utf8)])
        var settings = ProviderSettings(apiKey: "key", transport: transport)
        settings.batchResultDownloads = .init(maxLineBytes: line.utf8.count + 4)
        let provider = try AIProviders.gateway(settings: settings)
        var count = 0
        for try await _ in try await provider.experimentalBatch().getBatchResults(.init(batchID: "batch_1")) { count += 1 }
        #expect(count == 2)
        #expect(transport.cancellations.value > 0)
    }

    @Test func decisionRegistryAndCustomProviderPreserveOldCapabilityRouting() throws {
        let gateway = try AIProviders.gateway(settings: .init(apiKey: "key", environment: [:]))
        let registry = AIProviderRegistry(providers: ["judge": gateway], separator: "/")
        #expect(try registry.decisionModel("judge/openai/gpt-6-luna").modelID == "openai/gpt-6-luna")
        let custom = AICustomProvider(decisionModels: ["judge": .model(try gateway.decisionModel("openai/gpt-6-luna"))])
        #expect(custom.supportedCapabilities == [.decision])
        #expect(try custom.decisionModel("judge").modelID == "openai/gpt-6-luna")
        #expect(throws: AIError.self) { _ = try custom.decisionModel("missing") }
        #expect(throws: AIProviderRegistryError.self) { _ = try registry.decisionModel("unknown/id") }
    }
}

private func weeklyRequestJSON(_ request: AIHTTPRequest) throws -> JSONValue {
    try decodeJSONBody(try #require(request.body))
}
private final class WeeklyGatewayCounter: @unchecked Sendable {
    let lock = NSLock(); var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
private final class WeeklyGatewayBatchTransport: AIStreamingTransport, @unchecked Sendable {
    let chunks: [Data]
    let cancellations = WeeklyGatewayCounter()
    init(chunks: [Data]) { self.chunks = chunks }
    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse { .init(statusCode: 200, body: Data()) }
    func stream(_ request: AIHTTPRequest) async throws -> AIHTTPStreamResponse {
        let chunks = self.chunks, counter = cancellations
        return .init(statusCode: 200, body: AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }; continuation.finish()
        }, cancelBody: { counter.increment() })
    }
}
