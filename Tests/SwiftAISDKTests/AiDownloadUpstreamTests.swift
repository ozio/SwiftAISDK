import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiDownloadDownloadsDataSuccessfullyAndMatchesExpectedBytesLikeUpstream() async throws {
    let expectedBytes = Data([1, 2, 3, 4, 5, 6, 7, 8])
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        headers: ["content-type": "application/octet-stream"],
        body: expectedBytes,
        url: URL(string: "http://example.com/file")!
    ))

    let result = try await downloadURL("http://example.com/file", transport: transport)

    #expect(result.body == expectedBytes)
    #expect(result.headerValue("content-type") == "application/octet-stream")

    let requests = await transport.requests()
    #expect(requests.count == 1)
    #expect(requests[0].method == "GET")
    #expect(requests[0].url.absoluteString == "http://example.com/file")
    #expect(requests[0].maxResponseBytes == AIDefaultMaxDownloadSize)
}

@Test func aiDownloadAllowsInlineDataURLsLikeUpstream() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        body: Data("should-not-fetch".utf8)
    ))

    let result = try await downloadURL("data:text/plain;base64,aGVsbG8=", transport: transport)

    #expect(result.body == Data("hello".utf8))
    #expect(result.headerValue("content-type") == "text/plain")
    #expect(await transport.requests().isEmpty)
}

@Test func aiDownloadPassesAbortSignalToFetchTransportLikeUpstream() async throws {
    let controller = AIAbortController()
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        headers: ["content-type": "application/octet-stream"],
        body: Data([1, 2, 3]),
        url: URL(string: "http://example.com/file")!
    ))

    _ = try await downloadURL(
        "http://example.com/file",
        transport: transport,
        abortSignal: controller.signal
    )

    let requests = await transport.requests()
    #expect(requests.count == 1)
    #expect(requests[0].abortSignal === controller.signal)
}

@Test func aiDownloadRejectsPrivateIPv4AndLocalhostLikeUpstream() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(
        statusCode: 200,
        body: Data("should-not-fetch".utf8)
    ))

    for url in [
        "http://127.0.0.1/file",
        "http://10.0.0.1/file",
        "http://169.254.169.254/latest/meta-data/",
        "http://localhost/file"
    ] {
        await #expect(throws: Error.self) {
            _ = try await downloadURL(url, transport: transport)
        }
    }

    #expect(await transport.requests().isEmpty)
}
