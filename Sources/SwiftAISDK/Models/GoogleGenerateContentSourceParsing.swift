import Foundation

func googleGroundingChunkSource(from chunk: JSONValue, index: Int) -> AISource? {
    if let web = chunk["web"], let uri = web["uri"]?.stringValue {
        return AISource(
            id: "grounding-\(index)",
            sourceType: "url",
            url: uri,
            title: web["title"]?.stringValue,
            rawValue: chunk
        )
    }

    if let image = chunk["image"], let sourceURI = image["sourceUri"]?.stringValue {
        return AISource(
            id: "grounding-\(index)",
            sourceType: "url",
            url: sourceURI,
            title: image["title"]?.stringValue,
            rawValue: chunk
        )
    }

    if let retrievedContext = chunk["retrievedContext"] {
        if let uri = retrievedContext["uri"]?.stringValue {
            if uri.hasPrefix("http://") || uri.hasPrefix("https://") {
                return AISource(
                    id: "grounding-\(index)",
                    sourceType: "url",
                    url: uri,
                    title: retrievedContext["title"]?.stringValue,
                    rawValue: chunk
                )
            }

            let filename = googleFilename(from: uri)
            return AISource(
                id: "grounding-\(index)",
                sourceType: "document",
                title: retrievedContext["title"]?.stringValue ?? "Unknown Document",
                mediaType: googleMediaType(for: filename),
                filename: filename,
                rawValue: chunk
            )
        }

        if let fileSearchStore = retrievedContext["fileSearchStore"]?.stringValue {
            return AISource(
                id: "grounding-\(index)",
                sourceType: "document",
                title: retrievedContext["title"]?.stringValue ?? "Unknown Document",
                mediaType: "application/octet-stream",
                filename: googleFilename(from: fileSearchStore),
                rawValue: chunk
            )
        }
    }

    if let maps = chunk["maps"], let uri = maps["uri"]?.stringValue {
        return AISource(
            id: "grounding-\(index)",
            sourceType: "url",
            url: uri,
            title: maps["title"]?.stringValue,
            rawValue: chunk
        )
    }

    return nil
}

func googleFilename(from uri: String) -> String? {
    uri.split(separator: "/").last.map(String.init)
}

func googleMediaType(for filename: String?) -> String {
    guard let filename = filename?.lowercased() else {
        return "application/octet-stream"
    }
    if filename.hasSuffix(".pdf") {
        return "application/pdf"
    }
    if filename.hasSuffix(".txt") {
        return "text/plain"
    }
    if filename.hasSuffix(".docx") {
        return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    }
    if filename.hasSuffix(".doc") {
        return "application/msword"
    }
    if filename.hasSuffix(".md") || filename.hasSuffix(".markdown") {
        return "text/markdown"
    }
    return "application/octet-stream"
}

func googleSourceDeduplicationKey(_ source: AISource) -> String {
    if source.sourceType == "url", let url = source.url {
        return "url:\(url)"
    }
    return "document:\(source.filename ?? source.title ?? source.id)"
}

struct GoogleGenerateContentToolCallBuffer {
    var id: String?
    var name: String?
    var arguments: [String: JSONValue] = [:]
    var inputStarted = false
    var providerMetadata: [String: JSONValue] = [:]
    var rawValue: JSONValue?
}

struct GoogleGenerateContentStreamingToolCalls {
    private var buffers: [Int: GoogleGenerateContentToolCallBuffer] = [:]
    private var activeIndex: Int = 0

    mutating func apply(functionCall: JSONValue, rawValue: JSONValue) -> [LanguageStreamPart] {
        if functionCall.objectValue?.isEmpty == true {
            return []
        }

        let index: Int
        if functionCall["name"]?.stringValue != nil {
            index = buffers.isEmpty ? 0 : activeIndex + (buffers[activeIndex]?.name == nil ? 0 : 1)
            activeIndex = index
        } else {
            index = activeIndex
        }

        var buffer = buffers[index] ?? GoogleGenerateContentToolCallBuffer()
        if let id = functionCall["id"]?.stringValue {
            buffer.id = id
        }
        if let name = functionCall["name"]?.stringValue {
            buffer.name = name
        }
        if let providerMetadata = googleThoughtSignatureProviderMetadata(from: rawValue)["google"] {
            buffer.providerMetadata["google"] = providerMetadata
        }
        buffer.rawValue = rawValue

        var emitted: [LanguageStreamPart] = []
        let id = buffer.id ?? "tool-call-\(index)"
        if !buffer.inputStarted, let name = buffer.name {
            emitted.append(.toolInputStart(id: id, name: name, providerMetadata: buffer.providerMetadata))
            buffer.inputStarted = true
        }
        if let args = functionCall["args"] {
            let arguments = googleGenerateContentArguments(args)
            buffer.arguments = args.objectValue ?? [:]
            emitted.append(.toolCallDelta(id: buffer.id, name: buffer.name, argumentsDelta: arguments, index: index))
            if buffer.inputStarted {
                emitted.append(.toolInputDelta(id: id, delta: arguments, providerMetadata: buffer.providerMetadata))
            }
        }
        if let partialArgs = functionCall["partialArgs"]?.arrayValue {
            for partialArg in partialArgs {
                guard let path = partialArg["jsonPath"]?.stringValue else { continue }
                let value = googlePartialArgValue(partialArg)
                googleSetPartialArgument(path: path, value: value, in: &buffer.arguments)
                let argumentsDelta = googleGenerateContentArguments(.object(buffer.arguments))
                emitted.append(.toolCallDelta(id: buffer.id, name: buffer.name, argumentsDelta: argumentsDelta, index: index))
                if buffer.inputStarted {
                    emitted.append(.toolInputDelta(id: id, delta: argumentsDelta, providerMetadata: buffer.providerMetadata))
                }
            }
        }

        buffers[index] = buffer
        return emitted
    }

    mutating func finishedParts() -> [LanguageStreamPart] {
        var parts: [LanguageStreamPart] = []
        for index in buffers.keys.sorted() {
            guard var buffer = buffers[index], let name = buffer.name else { continue }
            let id = buffer.id ?? "tool-call-\(index)"
            if !buffer.inputStarted {
                parts.append(.toolInputStart(id: id, name: name, providerMetadata: buffer.providerMetadata))
                buffer.inputStarted = true
                buffers[index] = buffer
            }
            parts.append(.toolInputEnd(id: id, providerMetadata: buffer.providerMetadata))
            parts.append(.toolCall(AIToolCall(
                id: buffer.id ?? "tool-call-\(index)",
                name: name,
                arguments: googleGenerateContentArguments(.object(buffer.arguments)),
                providerMetadata: buffer.providerMetadata,
                rawValue: buffer.rawValue
            )))
        }
        return parts
    }
}
