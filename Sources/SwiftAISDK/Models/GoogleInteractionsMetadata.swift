import Foundation

func googleInteractionsText(from raw: JSONValue) -> String {
    (raw["steps"]?.arrayValue ?? []).compactMap { step in
        guard step["type"]?.stringValue == "model_output" else { return nil }
        return step["content"]?.arrayValue?.compactMap { block in
            block["type"]?.stringValue == "text" ? block["text"]?.stringValue : nil
        }.joined()
    }.joined()
}

func googleInteractionsProviderMetadata(from raw: JSONValue) -> [String: JSONValue] {
    var google: [String: JSONValue] = [:]
    if let id = raw["id"] {
        google["interactionId"] = id
    }
    if let serviceTier = raw["service_tier"] {
        google["serviceTier"] = serviceTier
    }
    guard !google.isEmpty else { return [:] }
    return ["google": .object(google)]
}

func googleInteractionsSources(from raw: JSONValue) -> [AISource] {
    var sourceCounter = 0
    var emittedKeys: Set<String> = []
    return googleInteractionsSources(from: raw, sourceCounter: &sourceCounter, emittedKeys: &emittedKeys)
}

func googleInteractionsSources(from raw: JSONValue, sourceCounter: inout Int, emittedKeys: inout Set<String>) -> [AISource] {
    var sources: [AISource] = []

    if let steps = raw["steps"]?.arrayValue {
        for step in steps {
            sources.append(contentsOf: googleInteractionsSources(fromStep: step, sourceCounter: &sourceCounter, emittedKeys: &emittedKeys))
        }
    }

    if let step = raw["step"] {
        sources.append(contentsOf: googleInteractionsSources(fromStep: step, sourceCounter: &sourceCounter, emittedKeys: &emittedKeys))
    }

    if let delta = raw["delta"],
       delta["type"]?.stringValue == "text_annotation" || delta["type"]?.stringValue == "text_annotation_delta" {
        sources.append(contentsOf: googleInteractionsSources(fromAnnotations: delta["annotations"]?.arrayValue, sourceCounter: &sourceCounter, emittedKeys: &emittedKeys))
    }

    return sources
}

func googleInteractionsSources(fromStep step: JSONValue, sourceCounter: inout Int, emittedKeys: inout Set<String>) -> [AISource] {
    var sources: [AISource] = []
    if step["type"]?.stringValue == "model_output" {
        for block in step["content"]?.arrayValue ?? [] where block["type"]?.stringValue == "text" {
            sources.append(contentsOf: googleInteractionsSources(fromAnnotations: block["annotations"]?.arrayValue, sourceCounter: &sourceCounter, emittedKeys: &emittedKeys))
        }
    }
    sources.append(contentsOf: googleInteractionsBuiltinToolResultSources(from: step, sourceCounter: &sourceCounter, emittedKeys: &emittedKeys))
    return sources
}

func googleInteractionsSources(fromAnnotations annotations: [JSONValue]?, sourceCounter: inout Int, emittedKeys: inout Set<String>) -> [AISource] {
    annotations?.compactMap { annotation in
        guard let source = googleInteractionsAnnotationSource(from: annotation, id: "interactions-source-\(sourceCounter)") else {
            return nil
        }
        let key = googleInteractionsSourceKey(source)
        guard !emittedKeys.contains(key) else {
            return nil
        }
        emittedKeys.insert(key)
        sourceCounter += 1
        return source
    } ?? []
}

func googleInteractionsAnnotationSource(from annotation: JSONValue, id: String) -> AISource? {
    switch annotation["type"]?.stringValue {
    case "url_citation":
        guard let url = annotation["url"]?.stringValue, !url.isEmpty else { return nil }
        return AISource(id: id, sourceType: "url", url: url, title: annotation["title"]?.stringValue, rawValue: annotation)
    case "file_citation":
        guard let uri = annotation["url"]?.stringValue ?? annotation["document_uri"]?.stringValue ?? annotation["file_name"]?.stringValue, !uri.isEmpty else {
            return nil
        }
        if googleInteractionsIsHTTP(uri) {
            return AISource(id: id, sourceType: "url", url: uri, title: annotation["file_name"]?.stringValue, rawValue: annotation)
        }
        let filename = annotation["file_name"]?.stringValue ?? googleInteractionsBasename(uri)
        return AISource(
            id: id,
            sourceType: "document",
            title: annotation["file_name"]?.stringValue ?? filename ?? uri,
            mediaType: googleInteractionsDocumentMediaType(uri),
            filename: filename,
            rawValue: annotation
        )
    case "place_citation":
        guard let url = annotation["url"]?.stringValue, !url.isEmpty else { return nil }
        return AISource(id: id, sourceType: "url", url: url, title: annotation["name"]?.stringValue, rawValue: annotation)
    default:
        return nil
    }
}

func googleInteractionsBuiltinToolResultSources(from step: JSONValue, sourceCounter: inout Int, emittedKeys: inout Set<String>) -> [AISource] {
    guard let type = step["type"]?.stringValue else { return [] }
    let rawSources: [AISource]
    switch type {
    case "url_context_result":
        rawSources = (step["result"]?.arrayValue ?? []).compactMap { entry in
            guard let url = entry["url"]?.stringValue, !url.isEmpty else { return nil }
            if let status = entry["status"]?.stringValue, status != "success" { return nil }
            return AISource(id: "interactions-source-\(sourceCounter)", sourceType: "url", url: url, rawValue: entry)
        }
    case "google_search_result":
        rawSources = (step["result"]?.arrayValue ?? []).compactMap { entry in
            guard let url = entry["url"]?.stringValue, !url.isEmpty else { return nil }
            return AISource(id: "interactions-source-\(sourceCounter)", sourceType: "url", url: url, title: entry["title"]?.stringValue, rawValue: entry)
        }
    case "google_maps_result":
        rawSources = (step["result"]?.arrayValue ?? []).flatMap { entry in
            (entry["places"]?.arrayValue ?? []).compactMap { place in
                guard let url = place["url"]?.stringValue, !url.isEmpty else { return nil }
                return AISource(id: "interactions-source-\(sourceCounter)", sourceType: "url", url: url, title: place["name"]?.stringValue, rawValue: place)
            }
        }
    case "file_search_result":
        rawSources = (step["result"]?.arrayValue ?? []).compactMap { entry in
            guard let uri = entry["url"]?.stringValue ?? entry["document_uri"]?.stringValue ?? entry["file_name"]?.stringValue ?? entry["source"]?.stringValue, !uri.isEmpty else {
                return nil
            }
            if googleInteractionsIsHTTP(uri) {
                return AISource(id: "interactions-source-\(sourceCounter)", sourceType: "url", url: uri, title: entry["title"]?.stringValue, rawValue: entry)
            }
            let filename = entry["file_name"]?.stringValue ?? googleInteractionsBasename(uri)
            return AISource(
                id: "interactions-source-\(sourceCounter)",
                sourceType: "document",
                title: entry["title"]?.stringValue ?? entry["file_name"]?.stringValue ?? filename ?? uri,
                mediaType: googleInteractionsDocumentMediaType(uri),
                filename: filename,
                rawValue: entry
            )
        }
    default:
        return []
    }

    var sources: [AISource] = []
    for var source in rawSources {
        source.id = "interactions-source-\(sourceCounter)"
        let key = googleInteractionsSourceKey(source)
        guard !emittedKeys.contains(key) else { continue }
        emittedKeys.insert(key)
        sourceCounter += 1
        sources.append(source)
    }
    return sources
}

func googleInteractionsSourceKey(_ source: AISource) -> String {
    if source.sourceType == "url", let url = source.url {
        return "url:\(url)"
    }
    return "doc:\(source.filename ?? source.title ?? source.id)"
}

func googleInteractionsIsHTTP(_ value: String) -> Bool {
    value.hasPrefix("http://") || value.hasPrefix("https://")
}

func googleInteractionsBasename(_ value: String) -> String? {
    value.split(separator: "/").last.map(String.init)
}

func googleInteractionsDocumentMediaType(_ value: String) -> String {
    let lower = value.lowercased()
    if lower.hasSuffix(".pdf") { return "application/pdf" }
    if lower.hasSuffix(".txt") { return "text/plain" }
    if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") { return "text/markdown" }
    if lower.hasSuffix(".doc") { return "application/msword" }
    if lower.hasSuffix(".docx") { return "application/vnd.openxmlformats-officedocument.wordprocessingml.document" }
    return "application/octet-stream"
}
