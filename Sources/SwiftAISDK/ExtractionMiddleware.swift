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

                    if result.providerMetadata.isEmpty {
                        continuation.yield(.finish(reason: result.finishReason, usage: result.usage))
                    } else {
                        continuation.yield(.finishMetadata(
                            reason: result.finishReason,
                            usage: result.usage,
                            providerMetadata: result.providerMetadata
                        ))
                    }
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
                var simpleBuffer = ""
                var blockBuffers: [String: String] = [:]
                var blockStarts: [String: LanguageStreamPart] = [:]

                func flushSimpleBuffer() {
                    guard !simpleBuffer.isEmpty else { return }
                    let transformed = transform(simpleBuffer)
                    simpleBuffer = ""
                    guard !transformed.isEmpty else { return }
                    continuation.yield(.textDelta(transformed))
                }

                for try await part in stream {
                    switch part {
                    case let .textStart(id, providerMetadata):
                        blockStarts[id] = .textStart(id: id, providerMetadata: providerMetadata)
                    case let .textDelta(delta):
                        simpleBuffer += delta
                    case let .textDeltaPart(id, delta, _):
                        blockBuffers[id, default: ""] += delta
                    case let .textEnd(id, providerMetadata):
                        let transformed = transform(blockBuffers[id] ?? "")
                        if let start = blockStarts[id] {
                            continuation.yield(start)
                        }
                        if !transformed.isEmpty {
                            continuation.yield(.textDeltaPart(id: id, delta: transformed))
                        }
                        continuation.yield(.textEnd(id: id, providerMetadata: providerMetadata))
                        blockBuffers[id] = nil
                        blockStarts[id] = nil
                    case .finish:
                        for id in blockBuffers.keys.sorted() {
                            let transformed = transform(blockBuffers[id] ?? "")
                            if let start = blockStarts[id] {
                                continuation.yield(start)
                            }
                            if !transformed.isEmpty {
                                continuation.yield(.textDeltaPart(id: id, delta: transformed))
                            }
                            continuation.yield(.textEnd(id: id))
                        }
                        blockBuffers.removeAll()
                        blockStarts.removeAll()
                        flushSimpleBuffer()
                        continuation.yield(part)
                    default:
                        continuation.yield(part)
                    }
                }
                flushSimpleBuffer()
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
                var sawTextPart = false

                func flushExtractedText() {
                    guard sawTextPart else { return }
                    let input = startWithReasoning ? "<\(tagName)>" + textBuffer : textBuffer
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
                                if !delta.isEmpty {
                                    continuation.yield(.reasoningDeltaPart(id: reasoningID, delta: delta))
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
                                if !delta.isEmpty {
                                    continuation.yield(.textDeltaPart(id: textID, delta: delta))
                                }
                                textSegmentCount += 1
                            }
                        }

                        if !emittedTextStart {
                            continuation.yield(.textStart(id: textID, providerMetadata: textStartMetadata))
                        }
                        continuation.yield(.textEnd(id: textID))
                    } else if !textBuffer.isEmpty {
                        continuation.yield(.textStart(id: textID, providerMetadata: textStartMetadata))
                        continuation.yield(.textDeltaPart(id: textID, delta: textBuffer))
                        continuation.yield(.textEnd(id: textID))
                    } else {
                        continuation.yield(.textStart(id: textID, providerMetadata: textStartMetadata))
                        continuation.yield(.textEnd(id: textID))
                    }
                    textBuffer = ""
                    textStartMetadata = [:]
                    sawTextPart = false
                }

                for try await part in stream {
                    switch part {
                    case let .textStart(id, providerMetadata):
                        textID = id
                        textStartMetadata = providerMetadata
                        sawTextPart = true
                    case let .textDelta(delta):
                        textBuffer += delta
                        sawTextPart = true
                    case let .textDeltaPart(id, delta, _):
                        textID = id
                        textBuffer += delta
                        sawTextPart = true
                    case .textEnd:
                        flushExtractedText()
                    case .finish:
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
