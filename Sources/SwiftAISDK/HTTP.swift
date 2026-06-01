import Foundation

public struct AIHTTPRequest: Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
    public var abortSignal: AIAbortSignal?
    public var maxResponseBytes: Int?

    public init(method: String = "POST", url: URL, headers: [String: String] = [:], body: Data? = nil, abortSignal: AIAbortSignal? = nil, maxResponseBytes: Int? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.abortSignal = abortSignal
        self.maxResponseBytes = maxResponseBytes
    }
}

public let AIDefaultMaxDownloadSize = 2 * 1024 * 1024 * 1024

public struct AIDownloadError: Error, Equatable, CustomStringConvertible, Sendable {
    public var url: String
    public var message: String

    public init(url: String, message: String) {
        self.url = url
        self.message = message
    }

    public var description: String {
        "Failed to download \(url): \(message)"
    }
}

public struct AIHTTPResponse: Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data
    public var url: URL?

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data(), url: URL? = nil) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.url = url
    }

    public func jsonValue() throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: body)
    }

    public var bodyText: String {
        String(data: body, encoding: .utf8) ?? ""
    }

    public func headerValue(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public protocol AITransport: Sendable {
    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse
}

public struct AIHTTPStreamResponse: Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: AsyncThrowingStream<Data, Error>

    public init(statusCode: Int, headers: [String: String] = [:], body: AsyncThrowingStream<Data, Error>) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    public func headerValue(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

public protocol AIStreamingTransport: AITransport {
    func stream(_ request: AIHTTPRequest) async throws -> AIHTTPStreamResponse
}

public final class URLSessionTransport: AIStreamingTransport, @unchecked Sendable {
    public static let shared = URLSessionTransport()
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        try request.abortSignal?.throwIfAborted()
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        let preparedRequest = urlRequest

        if let maxResponseBytes = request.maxResponseBytes {
            let (bytes, response): (URLSession.AsyncBytes, URLResponse)
            if let abortSignal = request.abortSignal {
                (bytes, response) = try await raceAbortSignal(abortSignal) {
                    try await self.session.bytes(for: preparedRequest)
                }
            } else {
                (bytes, response) = try await session.bytes(for: preparedRequest)
            }
            return try await limitedHTTPResponse(bytes: bytes, response: response, request: request, maxResponseBytes: maxResponseBytes)
        }

        let (data, response): (Data, URLResponse)
        if let abortSignal = request.abortSignal {
            (data, response) = try await raceAbortSignal(abortSignal) {
                try await self.session.data(for: preparedRequest)
            }
        } else {
            (data, response) = try await session.data(for: preparedRequest)
        }
        let httpResponse = response as? HTTPURLResponse
        let headers = httpHeaders(from: httpResponse)
        return AIHTTPResponse(statusCode: httpResponse?.statusCode ?? 0, headers: headers, body: data, url: response.url)
    }

    public func stream(_ request: AIHTTPRequest) async throws -> AIHTTPStreamResponse {
        try request.abortSignal?.throwIfAborted()
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        let preparedRequest = urlRequest

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        if let abortSignal = request.abortSignal {
            (bytes, response) = try await raceAbortSignal(abortSignal) {
                try await self.session.bytes(for: preparedRequest)
            }
        } else {
            (bytes, response) = try await session.bytes(for: preparedRequest)
        }
        let httpResponse = response as? HTTPURLResponse
        let headers = httpHeaders(from: httpResponse)
        return AIHTTPStreamResponse(
            statusCode: httpResponse?.statusCode ?? 0,
            headers: headers,
            body: AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await byte in bytes {
                            try Task.checkCancellation()
                            continuation.yield(Data([byte]))
                        }
                        continuation.finish()
                    } catch is CancellationError where request.abortSignal?.isAborted == true {
                        continuation.finish(throwing: AIAbortError(reason: request.abortSignal?.reason))
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                let registration = request.abortSignal?.addAbortHandler { _ in
                    task.cancel()
                }
                continuation.onTermination = { _ in
                    registration?.cancel()
                    task.cancel()
                }
            }
        )
    }
}

private func limitedHTTPResponse(
    bytes: URLSession.AsyncBytes,
    response: URLResponse,
    request: AIHTTPRequest,
    maxResponseBytes: Int
) async throws -> AIHTTPResponse {
    let httpResponse = response as? HTTPURLResponse
    let headers = httpHeaders(from: httpResponse)
    let urlText = request.url.absoluteString
    if let contentLength = httpResponse?.value(forHTTPHeaderField: "content-length"),
       let length = Int(contentLength.trimmingCharacters(in: .whitespacesAndNewlines)),
       length > maxResponseBytes {
        throw AIDownloadError(
            url: urlText,
            message: "Download exceeded maximum size of \(maxResponseBytes) bytes (Content-Length: \(length))."
        )
    }

    var data = Data()
    let expectedLength = response.expectedContentLength > 0 ? Int(response.expectedContentLength) : 0
    data.reserveCapacity(min(maxResponseBytes, expectedLength))
    var totalBytes = 0
    for try await byte in bytes {
        try Task.checkCancellation()
        totalBytes += 1
        if totalBytes > maxResponseBytes {
            throw AIDownloadError(
                url: urlText,
                message: "Download exceeded maximum size of \(maxResponseBytes) bytes."
            )
        }
        data.append(byte)
    }

    return AIHTTPResponse(statusCode: httpResponse?.statusCode ?? 0, headers: headers, body: data, url: response.url)
}

private func httpHeaders(from response: HTTPURLResponse?) -> [String: String] {
    response?.allHeaderFields.reduce(into: [String: String]()) { partial, element in
        guard let key = element.key as? String else { return }
        partial[key] = String(describing: element.value)
    } ?? [:]
}

private func raceAbortSignal<Output: Sendable>(
    _ abortSignal: AIAbortSignal,
    operation: @escaping @Sendable () async throws -> Output
) async throws -> Output {
    try abortSignal.throwIfAborted()
    return try await withThrowingTaskGroup(of: Output.self) { group in
        defer { group.cancelAll() }
        group.addTask {
            try await operation()
        }
        group.addTask {
            let reason = await abortSignal.waitUntilAborted()
            throw AIAbortError(reason: reason)
        }

        guard let result = try await group.next() else {
            throw CancellationError()
        }
        return result
    }
}

extension Dictionary where Key == String, Value == String {
    func mergingHeaders(_ other: [String: String]) -> [String: String] {
        merging(other) { _, new in new }
    }
}

func encodeJSONBody(_ value: JSONValue) throws -> Data {
    try JSONEncoder().encode(value)
}

func decodeJSONBody(_ data: Data) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: data)
}

func requireURL(_ string: String) throws -> URL {
    guard let url = URL(string: string) else { throw AIError.invalidURL(string) }
    return url
}

/// Mirrors upstream provider-utils download URL validation before fetching
/// provider-returned or user-provided remote assets.
public func validateDownloadURL(_ string: String) throws -> URL {
    guard let url = URL(string: string),
          let scheme = url.scheme?.lowercased(),
          !scheme.isEmpty else {
        throw AIError.invalidURL(string)
    }

    if scheme == "data" {
        return url
    }

    guard scheme == "http" || scheme == "https" else {
        throw AIError.invalidArgument(argument: "url", message: "URL scheme must be http, https, or data, got \(scheme):")
    }

    guard let rawHost = url.host, !rawHost.isEmpty else {
        throw AIError.invalidArgument(argument: "url", message: "URL must have a hostname.")
    }

    let host = rawHost.lowercased()
    if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".localhost") {
        throw AIError.invalidArgument(argument: "url", message: "URL with hostname \(host) is not allowed.")
    }

    if let ipv4 = ipv4Bytes(host) {
        if isPrivateIPv4(ipv4) {
            throw AIError.invalidArgument(argument: "url", message: "URL with IP address \(host) is not allowed.")
        }
        return url
    }

    if let ipv6 = ipv6Bytes(host), isPrivateIPv6(ipv6) {
        throw AIError.invalidArgument(argument: "url", message: "URL with IPv6 address \(host) is not allowed.")
    }

    return url
}

func downloadURL(
    _ string: String,
    transport: AITransport,
    headers: [String: String] = [:],
    abortSignal: AIAbortSignal? = nil,
    maxBytes: Int = AIDefaultMaxDownloadSize
) async throws -> AIHTTPResponse {
    let url = try validateDownloadURL(string)
    let response = try await transport.send(AIHTTPRequest(method: "GET", url: url, headers: headers, abortSignal: abortSignal, maxResponseBytes: maxBytes))
    if let finalURL = response.url, finalURL != url {
        _ = try validateDownloadURL(finalURL.absoluteString)
    }
    if response.body.count > maxBytes {
        throw AIDownloadError(
            url: string,
            message: "Download exceeded maximum size of \(maxBytes) bytes."
        )
    }
    return response
}

private func ipv4Bytes(_ host: String) -> [UInt8]? {
    let parts = host.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return nil }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(4)
    for part in parts {
        guard let value = UInt8(part), String(value) == part else { return nil }
        bytes.append(value)
    }
    return bytes
}

private func isPrivateIPv4(_ bytes: [UInt8]) -> Bool {
    guard bytes.count == 4 else { return false }
    let first = bytes[0]
    let second = bytes[1]
    if first == 0 { return true }
    if first == 10 { return true }
    if first == 127 { return true }
    if first == 169 && second == 254 { return true }
    if first == 172 && (16...31).contains(second) { return true }
    if first == 192 && second == 168 { return true }
    return false
}

private func ipv6Bytes(_ host: String) -> [UInt8]? {
    let normalized = host.lowercased()
    guard normalized.contains(":") else { return nil }
    let sides = normalized.components(separatedBy: "::")
    guard sides.count <= 2 else { return nil }

    let left = parseIPv6Hextets(sides[0])
    guard let left else { return nil }
    let right = sides.count == 2 ? parseIPv6Hextets(sides[1]) : []
    guard let right else { return nil }

    let hextetCount = left.count + right.count
    let missingCount: Int
    if sides.count == 2 {
        guard hextetCount < 8 else { return nil }
        missingCount = 8 - hextetCount
    } else {
        guard hextetCount == 8 else { return nil }
        missingCount = 0
    }

    let hextets = left + Array(repeating: UInt16(0), count: missingCount) + right
    guard hextets.count == 8 else { return nil }
    return hextets.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xff)] }
}

private func parseIPv6Hextets(_ value: String) -> [UInt16]? {
    guard !value.isEmpty else { return [] }
    var parts = value.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    if let last = parts.last, last.contains(".") {
        guard let ipv4 = ipv4Bytes(last) else { return nil }
        parts.removeLast()
        parts.append(String(format: "%02x%02x", ipv4[0], ipv4[1]))
        parts.append(String(format: "%02x%02x", ipv4[2], ipv4[3]))
    }

    var hextets: [UInt16] = []
    hextets.reserveCapacity(parts.count)
    for part in parts {
        guard !part.isEmpty,
              part.count <= 4,
              let value = UInt16(part, radix: 16) else {
            return nil
        }
        hextets.append(value)
    }
    return hextets
}

private func isPrivateIPv6(_ bytes: [UInt8]) -> Bool {
    guard bytes.count == 16 else { return false }
    if bytes.allSatisfy({ $0 == 0 }) { return true }
    if bytes.prefix(15).allSatisfy({ $0 == 0 }) && bytes[15] == 1 { return true }
    if (bytes[0] & 0xfe) == 0xfc { return true }
    if bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80 { return true }
    if bytes.prefix(10).allSatisfy({ $0 == 0 }),
       bytes[10] == 0xff,
       bytes[11] == 0xff {
        return isPrivateIPv4(Array(bytes[12...15]))
    }
    return false
}

func httpStatusError(provider: String, response: AIHTTPResponse) -> AIError {
    httpStatusError(
        provider: provider,
        statusCode: response.statusCode,
        body: response.bodyText,
        headers: response.headers
    )
}

func httpStatusError(
    provider: String,
    statusCode: Int,
    body: String,
    headers: [String: String] = [:]
) -> AIError {
    guard !headers.isEmpty else {
        return .httpStatus(provider: provider, statusCode: statusCode, body: body)
    }
    return .httpStatusWithHeaders(
        provider: provider,
        statusCode: statusCode,
        body: body,
        headers: headers
    )
}

func withoutTrailingSlash(_ value: String) -> String {
    var result = value
    while result.hasSuffix("/") {
        result.removeLast()
    }
    return result
}

func environmentValue(_ names: [String]) -> String? {
    let environment = ProcessInfo.processInfo.environment
    return names.lazy.compactMap { environment[$0] }.first
}

func userAgent(_ providerID: String) -> String {
    "SwiftAISDK/\(providerID)"
}

func tokenUsage(from raw: JSONValue) -> TokenUsage? {
    guard let usage = raw["usage"] else { return nil }
    return TokenUsage(
        inputTokens: usage["prompt_tokens"]?.intValue ?? usage["input_tokens"]?.intValue,
        outputTokens: usage["completion_tokens"]?.intValue ?? usage["output_tokens"]?.intValue,
        totalTokens: usage["total_tokens"]?.intValue
    )
}

struct ServerSentEvent: Equatable {
    var event: String?
    var id: String?
    var data: String
}

func parseServerSentEvents(_ data: Data) -> [ServerSentEvent] {
    let text = String(data: data, encoding: .utf8) ?? ""
    var events: [ServerSentEvent] = []
    var eventName: String?
    var eventID: String?
    var dataLines: [String] = []

    func flush() {
        guard !dataLines.isEmpty else {
            eventName = nil
            eventID = nil
            return
        }
        events.append(ServerSentEvent(event: eventName, id: eventID, data: dataLines.joined(separator: "\n")))
        eventName = nil
        eventID = nil
        dataLines.removeAll()
    }

    for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(rawLine)
        if line.isEmpty {
            flush()
        } else if line.hasPrefix("event:") {
            eventName = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("id:") {
            eventID = String(line.dropFirst("id:".count)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            dataLines.append(String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces))
        }
    }
    flush()
    return events
}

struct MultipartFormData {
    var boundary: String = "SwiftAISDK-\(UUID().uuidString)"
    private var body = Data()

    mutating func appendField(name: String, value: String) {
        appendBoundary()
        body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        body.append(Data(value.utf8))
        body.append(Data("\r\n".utf8))
    }

    mutating func appendFile(name: String, fileName: String, mimeType: String, data: Data) {
        appendBoundary()
        body.append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    mutating func finalize() -> Data {
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    private mutating func appendBoundary() {
        body.append(Data("--\(boundary)\r\n".utf8))
    }
}

func jsonScalarString(_ value: JSONValue) -> String? {
    switch value {
    case let .string(string):
        return string
    case let .number(number):
        return number.rounded() == number ? String(Int(number)) : String(number)
    case let .bool(bool):
        return String(bool)
    case .null, .array, .object:
        return nil
    }
}
