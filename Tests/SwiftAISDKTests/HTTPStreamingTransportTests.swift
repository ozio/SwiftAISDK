import Foundation
import Testing
@testable import SwiftAISDK

@Test func requireStreamingTransportRejectsSendOnlyTransport() {
    let transport = SendOnlyHTTPTransport()

    #expect(throws: AIError.invalidArgument(
        argument: "transport",
        message: "test-provider streaming requires a transport conforming to AIStreamingTransport."
    )) {
        _ = try requireStreamingTransport(transport, providerID: "test-provider")
    }
}

@Test func urlSessionStreamingTransportRejectsOversizedContentLengthBeforeReturningBody() async {
    let transport = makeURLProtocolTransport(OversizedStreamingURLProtocol.self)

    await expectStreamingDownloadError(containing: "Content-Length: 4") {
        _ = try await transport.stream(AIHTTPRequest(
            method: "GET",
            url: URL(string: "https://example.com/stream")!,
            maxResponseBytes: 3
        ))
    }
}

@Test func urlSessionStreamingTransportEnforcesCumulativeResponseLimit() async throws {
    let transport = makeURLProtocolTransport(CumulativeStreamingURLProtocol.self)
    let response = try await transport.stream(AIHTTPRequest(
        method: "GET",
        url: URL(string: "https://example.com/stream")!,
        maxResponseBytes: 3
    ))

    await expectStreamingDownloadError(containing: "exceeded maximum size of 3 bytes") {
        for try await _ in response.body {}
    }
}

@Test func urlSessionTransportCompletesNormallyWithNonAbortedSignal() async throws {
    let transport = makeURLProtocolTransport(SuccessfulStreamingURLProtocol.self)
    let sendController = AIAbortController()
    let sendResponse = try await transport.send(AIHTTPRequest(
        method: "GET",
        url: URL(string: "https://example.com/send")!,
        abortSignal: sendController.signal
    ))
    #expect(String(decoding: sendResponse.body, as: UTF8.self) == "ok")

    let streamController = AIAbortController()
    let streamResponse = try await transport.stream(AIHTTPRequest(
        method: "GET",
        url: URL(string: "https://example.com/stream")!,
        abortSignal: streamController.signal
    ))
    var streamBody = Data()
    for try await chunk in streamResponse.body {
        streamBody.append(chunk)
    }
    #expect(String(decoding: streamBody, as: UTF8.self) == "ok")
}

@Test func urlSessionTransportSendRemainsAbortableAfterResponseHeaders() async throws {
    let probe = URLProtocolProbe()
    HangingSendURLProtocol.probe = probe
    defer { HangingSendURLProtocol.probe = nil }
    let transport = makeURLProtocolTransport(HangingSendURLProtocol.self)
    let controller = AIAbortController()
    let task = Task {
        try await transport.send(AIHTTPRequest(
            method: "GET",
            url: URL(string: "https://example.com/hanging")!,
            abortSignal: controller.signal
        ))
    }

    #expect(await waitUntil { probe.didStart })
    controller.abort(reason: "stop send", reasonName: "AbortError")

    do {
        _ = try await task.value
        Issue.record("Expected send to abort.")
    } catch let error as AIAbortError {
        #expect(error.reason == "stop send")
        #expect(error.reasonName == "AbortError")
    } catch {
        Issue.record("Expected AIAbortError, got \(error).")
    }
    #expect(await waitUntil { probe.didStop })
}

@Test func urlSessionTransportPullsStreamingRequestBodyInOrder() async throws {
    let probe = URLProtocolBodyProbe()
    StreamedRequestURLProtocol.probe = probe
    defer { StreamedRequestURLProtocol.probe = nil }
    let transport = makeURLProtocolTransport(StreamedRequestURLProtocol.self)
    let body = AsyncThrowingStream<Data, Error> { continuation in
        continuation.yield(Data("one".utf8))
        continuation.yield(Data("-two".utf8))
        continuation.finish()
    }

    let response = try await transport.send(AIHTTPRequest(
        url: URL(string: "https://example.com/upload")!,
        bodyStream: body
    ))

    #expect(response.statusCode == 200)
    #expect(String(decoding: probe.body, as: UTF8.self) == "one-two")
}

@Test func urlSessionStreamingTransportSelectsRedirectPolicyDelegate() throws {
    #expect(urlSessionTaskDelegate(followRedirects: true) == nil)
    let delegate = try #require(
        urlSessionTaskDelegate(followRedirects: false) as? NoRedirectURLSessionDelegate
    )
    let originalURL = URL(string: "https://example.com/redirect")!
    let destinationURL = URL(string: "https://example.com/final")!
    let session = URLSession(configuration: .ephemeral)
    let task = session.dataTask(with: originalURL)
    let response = HTTPURLResponse(
        url: originalURL,
        statusCode: 302,
        httpVersion: nil,
        headerFields: ["Location": destinationURL.absoluteString]
    )!
    let capture = RedirectCapture()

    delegate.urlSession(
        session,
        task: task,
        willPerformHTTPRedirection: response,
        newRequest: URLRequest(url: destinationURL)
    ) { capture.record($0) }

    #expect(capture.wasCalled)
    #expect(capture.request == nil)
}

@Test func deleteFromAPISendsDeleteWithHeadersAndAbortSignal() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"deleted":true}"#))
    let controller = AIAbortController()
    let result = try await deleteFromAPI(
        url: URL(string: "https://api.example.com/files/file-1")!,
        transport: transport,
        headers: ["Authorization": "Bearer test"],
        abortSignal: controller.signal
    )

    #expect(result.response.statusCode == 200)
    let request = try #require(await transport.requests().first)
    #expect(request.method == "DELETE")
    #expect(request.headers["Authorization"] == "Bearer test")
    #expect(request.abortSignal === controller.signal)
    #expect(!request.followRedirects)
}

@Test func binaryStreamHelperPassesBodyThroughAndRejectsMissingBody() async throws {
    let body = AsyncThrowingStream<Data, Error> { continuation in
        continuation.yield(Data([1, 2, 3, 4]))
        continuation.finish()
    }
    let transport = BinarySequenceTransport(responses: [AIHTTPStreamResponse(
        statusCode: 200,
        headers: ["content-type": "application/octet-stream"],
        body: body
    )])
    let result = try await getBinaryStreamFromAPI(
        url: URL(string: "https://api.example.com/files/file-1/content")!,
        transport: transport,
        providerID: "test.files",
        trustedOrigin: "https://api.example.com",
        credentialedOrigin: "https://api.example.com"
    )
    var bytes = Data()
    for try await chunk in result.response.body { bytes.append(chunk) }
    #expect(bytes == Data([1, 2, 3, 4]))

    let cancellationProbe = BinaryBodyCancellationProbe()
    let missing = BinarySequenceTransport(responses: [AIHTTPStreamResponse(
        statusCode: 200,
        body: AsyncThrowingStream { _ in },
        bodyAvailable: false,
        cancelBody: { cancellationProbe.record() }
    )])
    await #expect(throws: AIError.invalidResponse(
        provider: "test.files",
        message: "File download response body is missing."
    )) {
        _ = try await getBinaryStreamFromAPI(
            url: URL(string: "https://api.example.com/files/file-1/content")!,
            transport: missing,
            providerID: "test.files",
            trustedOrigin: "https://api.example.com"
        )
    }
    #expect(cancellationProbe.wasCancelled)
}

@Test func readResponseWithSizeLimitAlwaysReleasesTheBodyProducer() async throws {
    let contentLengthProbe = BinaryBodyCancellationProbe()
    let contentLengthResponse = AIHTTPStreamResponse(
        statusCode: 400,
        headers: ["content-length": "5"],
        body: AsyncThrowingStream { _ in },
        cancelBody: { contentLengthProbe.record() }
    )
    await #expect(throws: AIDownloadError.self) {
        _ = try await readResponseWithSizeLimit(
            response: contentLengthResponse,
            url: "https://example.com/error",
            maxBytes: 4
        )
    }
    #expect(contentLengthProbe.wasCancelled)

    let drainedProbe = BinaryBodyCancellationProbe()
    let drainedResponse = AIHTTPStreamResponse(
        statusCode: 400,
        body: AsyncThrowingStream { continuation in
            continuation.yield(Data("error".utf8))
            continuation.finish()
        },
        cancelBody: { drainedProbe.record() }
    )
    #expect(try await readResponseWithSizeLimit(
        response: drainedResponse,
        url: "https://example.com/error"
    ) == Data("error".utf8))
    #expect(drainedProbe.wasCancelled)
}

@Test func binaryStreamHelperFollowsSafeRedirectAndStripsCredentialsCrossOrigin() async throws {
    let redirectProbe = BinaryBodyCancellationProbe()
    let transport = BinarySequenceTransport(responses: [
        AIHTTPStreamResponse(
            statusCode: 302,
            headers: ["location": "https://cdn.example.com/file-1"],
            body: AsyncThrowingStream { _ in },
            cancelBody: { redirectProbe.record() }
        ),
        AIHTTPStreamResponse(
            statusCode: 200,
            body: AsyncThrowingStream { continuation in
                continuation.yield(Data("ok".utf8))
                continuation.finish()
            }
        )
    ])

    _ = try await getBinaryStreamFromAPI(
        url: URL(string: "https://api.example.com/files/file-1/content")!,
        transport: transport,
        providerID: "test.files",
        headers: [
            "authorization": "Bearer secret",
            "x-custom": "private",
            "user-agent": "test-agent"
        ],
        trustedOrigin: "https://api.example.com",
        credentialedOrigin: "https://api.example.com"
    )

    let requests = await transport.recordedRequests()
    #expect(requests.map(\.url.absoluteString) == [
        "https://api.example.com/files/file-1/content",
        "https://cdn.example.com/file-1"
    ])
    #expect(requests[0].headers["authorization"] == "Bearer secret")
    #expect(requests[1].headers == ["user-agent": "test-agent"])
    #expect(redirectProbe.wasCancelled)
}

private struct SendOnlyHTTPTransport: AITransport {
    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        AIHTTPResponse(statusCode: 200)
    }
}

private actor BinarySequenceTransport: AIStreamingTransport {
    private var responses: [AIHTTPStreamResponse]
    private var requests: [AIHTTPRequest] = []

    init(responses: [AIHTTPStreamResponse]) {
        self.responses = responses
    }

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        AIHTTPResponse(statusCode: 500)
    }

    func stream(_ request: AIHTTPRequest) async throws -> AIHTTPStreamResponse {
        requests.append(request)
        return responses.removeFirst()
    }

    func recordedRequests() -> [AIHTTPRequest] { requests }
}

private final class BinaryBodyCancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var wasCancelled: Bool { lock.withLock { cancelled } }

    func record() {
        lock.withLock { cancelled = true }
    }
}

private func makeURLProtocolTransport(_ protocolClass: AnyClass) -> URLSessionTransport {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [protocolClass]
    return URLSessionTransport(session: URLSession(configuration: configuration))
}

private func expectStreamingDownloadError(
    containing expectedMessage: String,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected AIDownloadError.")
    } catch let error as AIDownloadError {
        #expect(error.message.contains(expectedMessage))
    } catch {
        Issue.record("Expected AIDownloadError, got \(error).")
    }
}

private func waitUntil(
    attempts: Int = 100,
    condition: @escaping @Sendable () -> Bool
) async -> Bool {
    for _ in 0..<attempts {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return condition()
}

private final class URLProtocolProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var stopped = false
    private var paths: [String] = []

    var didStart: Bool {
        lock.withLock { started }
    }

    var didStop: Bool {
        lock.withLock { stopped }
    }

    var requestPaths: [String] {
        lock.withLock { paths }
    }

    func recordStart(path: String) {
        lock.withLock {
            started = true
            paths.append(path)
        }
    }

    func recordStop() {
        lock.withLock { stopped = true }
    }

}

private final class URLProtocolBodyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedBody = Data()

    var body: Data { lock.withLock { recordedBody } }

    func record(_ data: Data) {
        lock.withLock { recordedBody = data }
    }
}

private final class RedirectCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var called = false
    private var redirectedRequest: URLRequest?

    var wasCalled: Bool {
        lock.withLock { called }
    }

    var request: URLRequest? {
        lock.withLock { redirectedRequest }
    }

    func record(_ request: URLRequest?) {
        lock.withLock {
            called = true
            redirectedRequest = request
        }
    }
}

private final class OversizedStreamingURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Length": "4"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("data".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class CumulativeStreamingURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("four".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class SuccessfulStreamingURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("ok".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class StreamedRequestURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var probe: URLProtocolBodyProbe?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var data = Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 16)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        Self.probe?.record(data)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("ok".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class HangingSendURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var probe: URLProtocolProbe?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.probe?.recordStart(path: request.url?.path ?? "")
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data([0x78]))
    }

    override func stopLoading() {
        Self.probe?.recordStop()
    }
}
