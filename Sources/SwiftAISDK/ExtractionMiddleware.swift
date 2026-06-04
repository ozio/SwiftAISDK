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

                    continuation.yield(.finish(reason: result.finishReason, usage: result.usage))
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
    let openingTag = "<\(tagName)>"
    let closingTag = "</\(tagName)>"
    let pattern = NSRegularExpression.escapedPattern(for: openingTag)
        + "(.*?)"
        + NSRegularExpression.escapedPattern(for: closingTag)
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
        return nil
    }

    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let matches = regex.matches(in: text, range: range)
    guard !matches.isEmpty else {
        return nil
    }

    let reasoning = matches.compactMap { match -> String? in
        guard let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }.joined(separator: separator)

    var textWithoutReasoning = text
    for match in matches.reversed() {
        guard let matchRange = Range(match.range, in: textWithoutReasoning) else { continue }
        let before = String(textWithoutReasoning[..<matchRange.lowerBound])
        let after = String(textWithoutReasoning[matchRange.upperBound...])
        let joiner = (!before.isEmpty && !after.isEmpty) ? separator : ""
        textWithoutReasoning = before + joiner + after
    }

    return (reasoning: reasoning, text: textWithoutReasoning)
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
                var sawTextPart = false

                func flushExtractedText() {
                    guard sawTextPart else { return }
                    let input = startWithReasoning ? "<\(tagName)>" + textBuffer : textBuffer
                    if let extracted = extractTaggedSections(text: input, tagName: tagName, separator: separator) {
                        if !extracted.reasoning.isEmpty {
                            continuation.yield(.reasoningStart(id: "reasoning-0"))
                            continuation.yield(.reasoningDeltaPart(id: "reasoning-0", delta: extracted.reasoning))
                            continuation.yield(.reasoningEnd(id: "reasoning-0"))
                        }
                        if !extracted.text.isEmpty {
                            continuation.yield(.textStart(id: textID))
                            continuation.yield(.textDeltaPart(id: textID, delta: extracted.text))
                            continuation.yield(.textEnd(id: textID))
                        }
                    } else if !textBuffer.isEmpty {
                        continuation.yield(.textStart(id: textID))
                        continuation.yield(.textDeltaPart(id: textID, delta: textBuffer))
                        continuation.yield(.textEnd(id: textID))
                    }
                    textBuffer = ""
                    sawTextPart = false
                }

                for try await part in stream {
                    switch part {
                    case let .textStart(id, _):
                        textID = id
                        sawTextPart = true
                    case let .textDelta(delta):
                        textBuffer += delta
                        sawTextPart = true
                    case let .textDeltaPart(id, delta, _):
                        textID = id
                        textBuffer += delta
                        sawTextPart = true
                    case .textEnd:
                        break
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
