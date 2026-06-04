import Foundation

public typealias AIIdGenerator = @Sendable () -> String

public func cosineSimilarity(_ vector1: [Double], _ vector2: [Double]) throws -> Double {
    guard vector1.count == vector2.count else {
        throw AIError.invalidArgument(
            argument: "vector1,vector2",
            message: "Vectors must have the same length."
        )
    }

    guard !vector1.isEmpty else {
        return 0
    }

    var magnitudeSquared1 = 0.0
    var magnitudeSquared2 = 0.0
    var dotProduct = 0.0

    for index in vector1.indices {
        let value1 = vector1[index]
        let value2 = vector2[index]
        magnitudeSquared1 += value1 * value1
        magnitudeSquared2 += value2 * value2
        dotProduct += value1 * value2
    }

    guard magnitudeSquared1 != 0, magnitudeSquared2 != 0 else {
        return 0
    }

    return dotProduct / (sqrt(magnitudeSquared1) * sqrt(magnitudeSquared2))
}

public func cosineSimilarity(_ vector1: [Float], _ vector2: [Float]) throws -> Double {
    try cosineSimilarity(vector1.map(Double.init), vector2.map(Double.init))
}

public func generateId() -> String {
    createIdGenerator()()
}

public func createIdGenerator(
    prefix: String? = nil,
    separator: String = "-",
    size: Int = 16,
    alphabet: String = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
) -> AIIdGenerator {
    precondition(size >= 0, "size must be greater than or equal to zero.")
    precondition(!alphabet.isEmpty, "alphabet must not be empty.")
    if prefix != nil, alphabet.contains(separator) {
        preconditionFailure("separator must not be part of alphabet.")
    }
    let characters = Array(alphabet)

    return {
        var id = ""
        id.reserveCapacity(size)
        for _ in 0..<size {
            id.append(characters[Int.random(in: 0..<characters.count)])
        }
        if let prefix {
            return "\(prefix)\(separator)\(id)"
        }
        return id
    }
}

public func simulateReadableStream<Element: Sendable>(
    chunks: [Element],
    initialDelayNanoseconds: UInt64? = 0,
    chunkDelayNanoseconds: UInt64? = 0
) -> AsyncThrowingStream<Element, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                for (index, chunk) in chunks.enumerated() {
                    try Task.checkCancellation()
                    let delay = index == 0 ? initialDelayNanoseconds : chunkDelayNanoseconds
                    if let delay {
                        try await Task.sleep(nanoseconds: delay)
                    }
                    continuation.yield(chunk)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { _ in task.cancel() }
    }
}

public enum AISmoothStreamChunking: Sendable {
    case word
    case line
}

public typealias AISmoothStreamChunkDetector = @Sendable (_ buffer: String) throws -> String?

public func smoothStream(
    _ stream: AsyncThrowingStream<LanguageStreamPart, Error>,
    delayNanoseconds: UInt64? = 10_000_000,
    chunking: AISmoothStreamChunking = .word
) -> AsyncThrowingStream<LanguageStreamPart, Error> {
    smoothStream(
        stream,
        delayNanoseconds: delayNanoseconds,
        detectChunk: detector(for: chunking)
    )
}

public func smoothStream(
    _ stream: AsyncThrowingStream<LanguageStreamPart, Error>,
    delayNanoseconds: UInt64? = 10_000_000,
    detectChunk: @escaping AISmoothStreamChunkDetector
) -> AsyncThrowingStream<LanguageStreamPart, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            var buffer = ""
            var activeKind: SmoothStreamPartKind?
            var activeID: String?
            var activeProviderMetadata: [String: JSONValue] = [:]

            do {
                func flushBuffer() {
                    guard !buffer.isEmpty, let activeKind else { return }
                    continuation.yield(activeKind.part(
                        text: buffer,
                        id: activeID,
                        providerMetadata: activeProviderMetadata
                    ))
                    buffer = ""
                    activeProviderMetadata = [:]
                }

                for try await part in stream {
                    try Task.checkCancellation()
                    guard let smoothable = SmoothableStreamPart(part) else {
                        flushBuffer()
                        continuation.yield(part)
                        continue
                    }

                    if (activeKind != smoothable.kind || activeID != smoothable.id) && !buffer.isEmpty {
                        flushBuffer()
                    }

                    activeKind = smoothable.kind
                    activeID = smoothable.id
                    buffer += smoothable.text
                    if !smoothable.providerMetadata.isEmpty {
                        activeProviderMetadata.merge(smoothable.providerMetadata) { _, new in new }
                    }

                    while let match = try detectChunk(buffer) {
                        guard !match.isEmpty else {
                            throw AIError.invalidArgument(
                                argument: "detectChunk",
                                message: "Chunk detector must return a non-empty string."
                            )
                        }
                        guard buffer.hasPrefix(match) else {
                            throw AIError.invalidArgument(
                                argument: "detectChunk",
                                message: "Chunk detector must return a prefix of the current buffer."
                            )
                        }
                        continuation.yield(smoothable.kind.part(
                            text: match,
                            id: smoothable.id,
                            providerMetadata: activeProviderMetadata
                        ))
                        buffer.removeFirst(match.count)
                        if let delayNanoseconds {
                            try await Task.sleep(nanoseconds: delayNanoseconds)
                        }
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { _ in task.cancel() }
    }
}

private enum SmoothStreamPartKind: Equatable {
    case text
    case reasoning

    init?(_ part: LanguageStreamPart) {
        switch part {
        case .textDelta, .textDeltaPart:
            self = .text
        case .reasoningDelta, .reasoningDeltaPart:
            self = .reasoning
        default:
            return nil
        }
    }

    func part(text: String, id: String?, providerMetadata: [String: JSONValue]) -> LanguageStreamPart {
        switch self {
        case .text:
            if let id {
                return .textDeltaPart(id: id, delta: text, providerMetadata: providerMetadata)
            }
            return .textDelta(text)
        case .reasoning:
            if let id {
                return .reasoningDeltaPart(id: id, delta: text, providerMetadata: providerMetadata)
            }
            return .reasoningDelta(text)
        }
    }
}

private struct SmoothableStreamPart {
    var kind: SmoothStreamPartKind
    var id: String?
    var text: String
    var providerMetadata: [String: JSONValue]
}

private extension SmoothableStreamPart {
    init?(_ part: LanguageStreamPart) {
        switch part {
        case let .textDelta(delta):
            self.init(kind: .text, id: nil, text: delta, providerMetadata: [:])
        case let .textDeltaPart(id, delta, providerMetadata):
            self.init(kind: .text, id: id, text: delta, providerMetadata: providerMetadata)
        case let .reasoningDelta(delta):
            self.init(kind: .reasoning, id: nil, text: delta, providerMetadata: [:])
        case let .reasoningDeltaPart(id, delta, providerMetadata):
            self.init(kind: .reasoning, id: id, text: delta, providerMetadata: providerMetadata)
        default:
            return nil
        }
    }
}

private func detector(for chunking: AISmoothStreamChunking) -> AISmoothStreamChunkDetector {
    switch chunking {
    case .word:
        return regexDetector(#"\S+\s+"#)
    case .line:
        return regexDetector(#"\n+"#)
    }
}

private func regexDetector(_ pattern: String) -> AISmoothStreamChunkDetector {
    let regex = try? NSRegularExpression(pattern: pattern)
    return { buffer in
        guard !buffer.isEmpty, let regex else { return nil }
        let range = NSRange(buffer.startIndex..<buffer.endIndex, in: buffer)
        guard let match = regex.firstMatch(in: buffer, range: range) else {
            return nil
        }
        guard let matchRange = Range(match.range, in: buffer) else {
            return nil
        }
        return String(buffer[..<matchRange.lowerBound]) + String(buffer[matchRange])
    }
}
