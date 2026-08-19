import Foundation
import Testing
@testable import SwiftAISDK

@Test func streamingTranscriptionFoundationSendsChunksAndFinishes() async throws {
    let pipe = AIStreamingAudioInput.makeStream()

    #expect(pipe.writer.send(Data([1, 2])) == .enqueued)
    #expect(pipe.writer.send(Data([3])) == .enqueued)
    pipe.writer.finish()

    var received: [Data] = []
    for try await chunk in pipe.input {
        received.append(chunk)
    }

    #expect(received == [Data([1, 2]), Data([3])])
    #expect(pipe.writer.send(Data([4])) == .terminated)
}

@Test func streamingTranscriptionFoundationPropagatesInputCancellation() async {
    let pipe = AIStreamingAudioInput.makeStream()
    pipe.writer.cancel(reason: "microphone stopped", reasonName: "AbortError")

    do {
        for try await _ in pipe.input {}
        Issue.record("Expected the cancelled input to throw")
    } catch let error as AIAbortError {
        #expect(error.reason == "microphone stopped")
        #expect(error.reasonName == "AbortError")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(pipe.writer.send(Data([1])) == .terminated)
}

@Test func streamingTranscriptionFoundationPreservesWebSocketHeadersAndSubprotocols() throws {
    let request = AIDuplexWebSocketRequest(
        url: try #require(URL(string: "wss://example.com/realtime")),
        headers: [
            "Authorization": "Bearer token",
            "X-Custom": "custom-value"
        ],
        protocols: ["realtime", "json"]
    )

    let urlRequest = urlSessionWebSocketURLRequest(from: request)

    #expect(urlRequest.url == request.url)
    #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    #expect(urlRequest.value(forHTTPHeaderField: "X-Custom") == "custom-value")
    #expect(urlRequest.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") == "realtime, json")
}

@Test func streamingTranscriptionFoundationHonorsExplicitSubprotocolHeader() throws {
    let request = AIDuplexWebSocketRequest(
        url: try #require(URL(string: "wss://example.com/realtime")),
        headers: ["Sec-WebSocket-Protocol": "caller-selected"],
        protocols: ["ignored-default"]
    )

    let urlRequest = urlSessionWebSocketURLRequest(from: request)
    #expect(urlRequest.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") == "caller-selected")
}
