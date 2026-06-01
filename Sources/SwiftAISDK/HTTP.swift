import Foundation

public struct AIHTTPRequest: Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: String = "POST", url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct AIHTTPResponse: Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
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
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: urlRequest)
        let httpResponse = response as? HTTPURLResponse
        let headers = httpResponse?.allHeaderFields.reduce(into: [String: String]()) { partial, element in
            guard let key = element.key as? String else { return }
            partial[key] = String(describing: element.value)
        } ?? [:]
        return AIHTTPResponse(statusCode: httpResponse?.statusCode ?? 0, headers: headers, body: data)
    }

    public func stream(_ request: AIHTTPRequest) async throws -> AIHTTPStreamResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let (bytes, response) = try await session.bytes(for: urlRequest)
        let httpResponse = response as? HTTPURLResponse
        let headers = httpResponse?.allHeaderFields.reduce(into: [String: String]()) { partial, element in
            guard let key = element.key as? String else { return }
            partial[key] = String(describing: element.value)
        } ?? [:]
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
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        )
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
