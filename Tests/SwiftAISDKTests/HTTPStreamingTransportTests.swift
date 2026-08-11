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

private struct SendOnlyHTTPTransport: AITransport {
    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        AIHTTPResponse(statusCode: 200)
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
