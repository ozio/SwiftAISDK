import Foundation

public func extractJsonMiddleware(
    transform: (@Sendable (_ text: String) -> String)? = nil
) -> AILanguageModelMiddleware {
    let transformText = transform ?? defaultExtractJSONTransform
    return AILanguageModelMiddleware(
        wrapGenerate: { context in
            var result = try await context.doGenerate()
            result.text = transformText(result.text)
            return result
        },
        wrapStream: { context in
            transformTextStream(context.doStream(), transform: transformText)
        }
    )
}

public func extractJSONMiddleware(
    transform: (@Sendable (_ text: String) -> String)? = nil
) -> AILanguageModelMiddleware {
    extractJsonMiddleware(transform: transform)
}

public func extractReasoningMiddleware(
    tagName: String,
    separator: String = "\n",
    startWithReasoning: Bool = false
) -> AILanguageModelMiddleware {
    AILanguageModelMiddleware(
        wrapGenerate: { context in
            var result = try await context.doGenerate()
            let input = startWithReasoning ? "<\(tagName)>" + result.text : result.text
            guard let extracted = extractTaggedSections(text: input, tagName: tagName, separator: separator) else {
                return result
            }
            result.text = extracted.text
            result.reasoning = appendSeparated(result.reasoning, extracted.reasoning, separator: separator)
            return result
        },
        wrapStream: { context in
            extractReasoningStream(
                context.doStream(),
                tagName: tagName,
                separator: separator,
                startWithReasoning: startWithReasoning
            )
        }
    )
}

public func simulateStreamingMiddleware() -> AILanguageModelMiddleware {
    AILanguageModelMiddleware(wrapStream: { context in
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await context.doGenerate()
                    var id = 0

                    continuation.yield(.streamStart(warnings: result.warnings))
                    if result.responseMetadata != AIResponseMetadata() {
                        continuation.yield(.responseMetadata(result.responseMetadata))
                    }

                    if !result.reasoning.isEmpty {
                        let partID = String(id)
                        continuation.yield(.reasoningStart(id: partID))
                        continuation.yield(.reasoningDeltaPart(id: partID, delta: result.reasoning))
                        continuation.yield(.reasoningEnd(id: partID))
                        id += 1
                    }

                    if !result.text.isEmpty {
                        let partID = String(id)
                        continuation.yield(.textStart(id: partID))
                        continuation.yield(.textDeltaPart(id: partID, delta: result.text))
                        continuation.yield(.textEnd(id: partID))
                        id += 1
                    }

                    for source in result.sources {
                        continuation.yield(.source(source))
                    }
                    for toolCall in result.toolCalls {
                        continuation.yield(.toolCall(toolCall))
                    }
                    for approvalRequest in result.toolApprovalRequests {
                        continuation.yield(.toolApprovalRequest(approvalRequest))
                    }
                    for approvalResponse in result.toolApprovalResponses {
                        continuation.yield(.toolApprovalResponse(approvalResponse))
                    }
                    for toolResult in result.toolResults {
                        continuation.yield(.toolResult(toolResult))
                    }

                    continuation.yield(.finishMetadata(
                        reason: result.finishReason,
                        usage: result.usage,
                        providerMetadata: result.providerMetadata
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    })
}

func defaultExtractJSONTransform(_ text: String) -> String {
    text
        .replacingOccurrences(of: #"^```(?:json)?\s*\n?"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\n?```\s*$"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func transformTextStream(
    _ stream: AsyncThrowingStream<LanguageStreamPart, Error>,
    transform: @escaping @Sendable (String) -> String
) -> AsyncThrowingStream<LanguageStreamPart, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                var blockBuffers: [String: String] = [:]
                var blockStarts: [String: LanguageStreamPart] = [:]
                var blockDeltaMetadata: [String: [String: JSONValue]] = [:]

                func sortedBlockIDs() -> [String] {
                    blockBuffers.keys.sorted { lhs, rhs in
                        let leftNumber = Int(lhs)
                        let rightNumber = Int(rhs)
                        if let leftNumber, let rightNumber, leftNumber != rightNumber {
                            return leftNumber < rightNumber
                        }
                        return lhs < rhs
                    }
                }

                func flushBlocks() {
                    for id in sortedBlockIDs() {
                        let transformed = transform(blockBuffers[id] ?? "")
                        let deltaMetadata = blockDeltaMetadata[id] ?? [:]
                        continuation.yield(blockStarts[id] ?? .textStart(id: id))
                        if !transformed.isEmpty || !deltaMetadata.isEmpty {
                            continuation.yield(.textDeltaPart(
                                id: id,
                                delta: transformed,
                                providerMetadata: deltaMetadata
                            ))
                        }
                        continuation.yield(.textEnd(id: id))
                    }
                    blockBuffers.removeAll()
                    blockStarts.removeAll()
                    blockDeltaMetadata.removeAll()
                }

                for try await part in canonicalLanguageStream(stream, providerID: "extract-json-middleware") {
                    switch part {
                    case let .textStart(id, providerMetadata):
                        blockStarts[id] = .textStart(id: id, providerMetadata: providerMetadata)
                        blockBuffers[id, default: ""] += ""
                    case let .textDeltaPart(id, delta, providerMetadata):
                        blockBuffers[id, default: ""] += delta
                        blockDeltaMetadata[id, default: [:]].merge(providerMetadata) { _, new in new }
                    case let .textEnd(id, providerMetadata):
                        let transformed = transform(blockBuffers[id] ?? "")
                        let deltaMetadata = blockDeltaMetadata[id] ?? [:]
                        continuation.yield(blockStarts[id] ?? .textStart(id: id))
                        if !transformed.isEmpty || !deltaMetadata.isEmpty {
                            continuation.yield(.textDeltaPart(
                                id: id,
                                delta: transformed,
                                providerMetadata: deltaMetadata
                            ))
                        }
                        continuation.yield(.textEnd(id: id, providerMetadata: providerMetadata))
                        blockBuffers[id] = nil
                        blockStarts[id] = nil
                        blockDeltaMetadata[id] = nil
                    case .finishMetadata:
                        flushBlocks()
                        continuation.yield(part)
                    default:
                        continuation.yield(part)
                    }
                }
                flushBlocks()
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

func extractTaggedSections(
    text: String,
    tagName: String,
    separator: String
) -> (reasoning: String, text: String)? {
    guard let segments = extractTaggedSegments(text: text, tagName: tagName) else {
        return nil
    }

    let reasoning = segments.compactMap { segment -> String? in
        if case let .reasoning(value) = segment { return value }
        return nil
    }.joined(separator: separator)
    let textWithoutReasoning = segments.compactMap { segment -> String? in
        if case let .text(value) = segment { return value }
        return nil
    }.joined(separator: separator)

    return (reasoning: reasoning, text: textWithoutReasoning)
}

private enum ExtractedTaggedSegment {
    case reasoning(String)
    case text(String)
}

private func extractTaggedSegments(text: String, tagName: String) -> [ExtractedTaggedSegment]? {
    let openingTag = "<\(tagName)>"
    let closingTag = "</\(tagName)>"
    let pattern = NSRegularExpression.escapedPattern(for: openingTag)
        + "(.*?)"
        + NSRegularExpression.escapedPattern(for: closingTag)
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
        return nil
    }

    let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
    let matches = regex.matches(in: text, range: fullRange)
    guard !matches.isEmpty else {
        return nil
    }

    var segments: [ExtractedTaggedSegment] = []
    var cursor = text.startIndex

    for match in matches {
        guard let matchRange = Range(match.range, in: text),
              let reasoningRange = Range(match.range(at: 1), in: text) else {
            continue
        }

        if cursor < matchRange.lowerBound {
            let textSegment = String(text[cursor..<matchRange.lowerBound])
            if !textSegment.isEmpty {
                segments.append(.text(textSegment))
            }
        }

        segments.append(.reasoning(String(text[reasoningRange])))
        cursor = matchRange.upperBound
    }

    if cursor < text.endIndex {
        let textSegment = String(text[cursor..<text.endIndex])
        if !textSegment.isEmpty {
            segments.append(.text(textSegment))
        }
    }

    return segments
}

func appendSeparated(_ existing: String, _ next: String, separator: String) -> String {
    guard !existing.isEmpty else { return next }
    guard !next.isEmpty else { return existing }
    return existing + separator + next
}

func extractReasoningStream(
    _ stream: AsyncThrowingStream<LanguageStreamPart, Error>,
    tagName: String,
    separator: String,
    startWithReasoning: Bool
) -> AsyncThrowingStream<LanguageStreamPart, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                var textBuffer = ""
                var textID = "0"
                var textStartMetadata: [String: JSONValue] = [:]
                var textDeltaMetadata: [String: JSONValue] = [:]
                var textEndMetadata: [String: JSONValue] = [:]
                var sawTextPart = false

                func flushExtractedText() {
                    guard sawTextPart else { return }
                    let input = startWithReasoning ? "<\(tagName)>" + textBuffer : textBuffer
                    var pendingDeltaMetadata = textDeltaMetadata
                    func takeDeltaMetadata() -> [String: JSONValue] {
                        defer { pendingDeltaMetadata = [:] }
                        return pendingDeltaMetadata
                    }
                    if let segments = extractTaggedSegments(text: input, tagName: tagName) {
                        var reasoningIndex = 0
                        var reasoningSegmentCount = 0
                        var textSegmentCount = 0
                        var emittedTextStart = false

                        for segment in segments {
                            switch segment {
                            case let .reasoning(reasoning):
                                let reasoningID = "reasoning-\(reasoningIndex)"
                                continuation.yield(.reasoningStart(id: reasoningID))
                                let delta = (reasoningSegmentCount > 0 ? separator : "") + reasoning
                                let providerMetadata = takeDeltaMetadata()
                                if !delta.isEmpty || !providerMetadata.isEmpty {
                                    continuation.yield(.reasoningDeltaPart(
                                        id: reasoningID,
                                        delta: delta,
                                        providerMetadata: providerMetadata
                                    ))
                                }
                                continuation.yield(.reasoningEnd(id: reasoningID))
                                reasoningIndex += 1
                                reasoningSegmentCount += 1
                            case let .text(text):
                                if !emittedTextStart {
                                    continuation.yield(.textStart(id: textID, providerMetadata: textStartMetadata))
                                    emittedTextStart = true
                                }
                                let delta = (textSegmentCount > 0 ? separator : "") + text
                                let providerMetadata = takeDeltaMetadata()
                                if !delta.isEmpty || !providerMetadata.isEmpty {
                                    continuation.yield(.textDeltaPart(
                                        id: textID,
                                        delta: delta,
                                        providerMetadata: providerMetadata
                                    ))
                                }
                                textSegmentCount += 1
                            }
                        }

                        if !emittedTextStart {
                            continuation.yield(.textStart(id: textID, providerMetadata: textStartMetadata))
                        }
                        if !pendingDeltaMetadata.isEmpty {
                            continuation.yield(.textDeltaPart(
                                id: textID,
                                delta: "",
                                providerMetadata: takeDeltaMetadata()
                            ))
                        }
                        continuation.yield(.textEnd(id: textID, providerMetadata: textEndMetadata))
                    } else if !textBuffer.isEmpty {
                        continuation.yield(.textStart(id: textID, providerMetadata: textStartMetadata))
                        continuation.yield(.textDeltaPart(
                            id: textID,
                            delta: textBuffer,
                            providerMetadata: takeDeltaMetadata()
                        ))
                        continuation.yield(.textEnd(id: textID, providerMetadata: textEndMetadata))
                    } else {
                        continuation.yield(.textStart(id: textID, providerMetadata: textStartMetadata))
                        if !pendingDeltaMetadata.isEmpty {
                            continuation.yield(.textDeltaPart(
                                id: textID,
                                delta: "",
                                providerMetadata: takeDeltaMetadata()
                            ))
                        }
                        continuation.yield(.textEnd(id: textID, providerMetadata: textEndMetadata))
                    }
                    textBuffer = ""
                    textStartMetadata = [:]
                    textDeltaMetadata = [:]
                    textEndMetadata = [:]
                    sawTextPart = false
                }

                for try await part in canonicalLanguageStream(stream, providerID: "extract-reasoning-middleware") {
                    switch part {
                    case let .textStart(id, providerMetadata):
                        textID = id
                        textStartMetadata = providerMetadata
                        sawTextPart = true
                    case let .textDeltaPart(id, delta, providerMetadata):
                        textID = id
                        textBuffer += delta
                        textDeltaMetadata.merge(providerMetadata) { _, new in new }
                        sawTextPart = true
                    case let .textEnd(_, providerMetadata):
                        textEndMetadata = providerMetadata
                        flushExtractedText()
                    case .finishMetadata:
                        flushExtractedText()
                        continuation.yield(part)
                    default:
                        continuation.yield(part)
                    }
                }
                flushExtractedText()
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
