import Foundation

enum ResponsesRequestMode: Equatable, Sendable {
    case openAICompatible
    case openResponses(providerOptionsName: String)
}

func openAICompatibleResponseMetadata(from raw: JSONValue? = nil, response: AIHTTPResponse, modelID: String? = nil) -> AIResponseMetadata {
    AIResponseMetadata(
        id: raw?["id"]?.stringValue,
        timestamp: raw?["created"]?.doubleValue.map { Date(timeIntervalSince1970: $0) },
        modelID: raw?["model"]?.stringValue ?? modelID,
        headers: response.headers,
        body: raw
    )
}

func openAIResponsesStreamResponseMetadata(from raw: JSONValue, response: AIHTTPResponse, modelID: String? = nil) -> AIResponseMetadata {
    let createdAt = raw["created_at"]?.doubleValue ?? raw["created"]?.doubleValue
    return AIResponseMetadata(
        id: raw["id"]?.stringValue,
        timestamp: createdAt.map { Date(timeIntervalSince1970: $0) },
        modelID: raw["model"]?.stringValue ?? modelID,
        headers: response.headers,
        body: raw
    )
}

func openAICompatibleProviderMetadataNamespace(_ providerID: String) -> String {
    openAIBackedProviderRoot(providerID) ?? openAICompatibleProviderRoot(providerID)
}

func openAICompatibleNamespacedProviderMetadata(_ metadata: [String: JSONValue], providerID: String) -> [String: JSONValue] {
    guard !metadata.isEmpty else { return [:] }
    return [openAICompatibleProviderMetadataNamespace(providerID): .object(metadata)]
}

func openAICompatibleMergeProviderMetadata(_ source: [String: JSONValue], into target: inout [String: JSONValue]) {
    for (key, value) in source {
        if case let .object(existing) = target[key],
           case let .object(incoming) = value {
            target[key] = .object(existing.merging(incoming) { _, new in new })
        } else {
            target[key] = value
        }
    }
}

func openAICompatibleChatProviderMetadata(from raw: JSONValue, choice: JSONValue?, providerID: String) -> [String: JSONValue] {
    var metadata: [String: JSONValue] = [:]
    if let accepted = raw["usage"]?["completion_tokens_details"]?["accepted_prediction_tokens"] {
        metadata["acceptedPredictionTokens"] = accepted
    }
    if let rejected = raw["usage"]?["completion_tokens_details"]?["rejected_prediction_tokens"] {
        metadata["rejectedPredictionTokens"] = rejected
    }
    if let logprobs = choice?["logprobs"]?["content"] {
        metadata["logprobs"] = logprobs
    }
    return openAICompatibleNamespacedProviderMetadata(metadata, providerID: providerID)
}

func openAICompatibleCompletionProviderMetadata(from choice: JSONValue?, providerID: String) -> [String: JSONValue] {
    var metadata: [String: JSONValue] = [:]
    if let logprobs = choice?["logprobs"] {
        metadata["logprobs"] = logprobs
    }
    return openAICompatibleNamespacedProviderMetadata(metadata, providerID: providerID)
}

func openAIResponsesProviderMetadata(from raw: JSONValue, providerID: String) -> [String: JSONValue] {
    var metadata: [String: JSONValue] = [:]
    if let responseID = raw["id"] {
        metadata["responseId"] = responseID
    }
    if let serviceTier = raw["service_tier"] {
        metadata["serviceTier"] = serviceTier
    }
    let logprobs = openAIResponsesOutputLogprobs(from: raw)
    if !logprobs.isEmpty {
        metadata["logprobs"] = .array(logprobs)
    }
    return openAICompatibleNamespacedProviderMetadata(metadata, providerID: providerID)
}

func openAIResponsesProviderMetadataByPreservingResponseID(_ providerMetadata: [String: JSONValue], responseID: JSONValue?, providerID: String) -> [String: JSONValue] {
    guard let responseID else {
        return providerMetadata
    }
    let namespace = openAICompatibleProviderMetadataNamespace(providerID)
    var namespaceMetadata = providerMetadata[namespace]?.objectValue ?? [:]
    namespaceMetadata["responseId"] = responseID
    var updated = providerMetadata
    updated[namespace] = .object(namespaceMetadata)
    return updated
}

func openAIResponsesProviderMetadataByApplyingStreamLogprobs(
    _ providerMetadata: [String: JSONValue],
    streamOutputLogprobs: [JSONValue],
    providerID: String
) -> [String: JSONValue] {
    guard !streamOutputLogprobs.isEmpty else {
        return providerMetadata
    }
    let namespace = openAICompatibleProviderMetadataNamespace(providerID)
    var namespaceMetadata = providerMetadata[namespace]?.objectValue ?? [:]
    namespaceMetadata["logprobs"] = .array(streamOutputLogprobs)
    var updated = providerMetadata
    updated[namespace] = .object(namespaceMetadata)
    return updated
}

func openAIResponsesOutputLogprobs(from raw: JSONValue) -> [JSONValue] {
    raw["output"]?.arrayValue?.flatMap { item in
        item["content"]?.arrayValue?.compactMap { content in
            content["logprobs"]
        } ?? []
    } ?? []
}

func openAIResponsesTextProviderMetadata(itemID: String, phase: JSONValue?, annotations: [JSONValue] = [], providerID: String) -> [String: JSONValue] {
    var metadata: [String: JSONValue] = ["itemId": .string(itemID)]
    if let phase {
        metadata["phase"] = phase
    }
    if !annotations.isEmpty {
        metadata["annotations"] = .array(annotations.map(openAIResponsesTextAnnotationProviderMetadata))
    }
    return openAICompatibleNamespacedProviderMetadata(metadata, providerID: providerID)
}

func openAIResponsesTextAnnotationProviderMetadata(_ annotation: JSONValue) -> JSONValue {
    guard annotation["type"]?.stringValue == "container_file_citation",
          var object = annotation.objectValue else {
        return annotation
    }
    object["index"] = nil
    return .object(object)
}

func openAIResponsesReasoningProviderMetadata(itemID: String, encryptedContent: JSONValue? = nil, includeEncryptedContent: Bool = false, providerID: String) -> [String: JSONValue] {
    var metadata: [String: JSONValue] = ["itemId": .string(itemID)]
    if includeEncryptedContent {
        metadata["reasoningEncryptedContent"] = encryptedContent ?? .null
    }
    return openAICompatibleNamespacedProviderMetadata(metadata, providerID: providerID)
}

func openAIResponsesCompactionProviderMetadata(itemID: String, encryptedContent: JSONValue?, providerID: String) -> [String: JSONValue] {
    var metadata: [String: JSONValue] = [
        "type": .string("compaction"),
        "itemId": .string(itemID)
    ]
    if let encryptedContent {
        metadata["encryptedContent"] = encryptedContent
    }
    return openAICompatibleNamespacedProviderMetadata(metadata, providerID: providerID)
}

func openAIResponsesItemProviderMetadata(itemID: String?, providerID: String, extra: [String: JSONValue] = [:]) -> [String: JSONValue] {
    var metadata = extra
    if let itemID {
        metadata["itemId"] = .string(itemID)
    }
    return openAICompatibleNamespacedProviderMetadata(metadata, providerID: providerID)
}

func openAIResponsesToolInputEndProviderMetadata(from item: JSONValue, providerID: String) -> [String: JSONValue] {
    guard item["type"]?.stringValue == "function_call",
          let namespace = item["namespace"] else {
        return [:]
    }
    return openAICompatibleNamespacedProviderMetadata(["namespace": namespace], providerID: providerID)
}

enum OpenAIResponsesReasoningSummaryState {
    case active
    case canConclude
    case concluded
}

struct OpenAIResponsesActiveReasoning {
    var encryptedContent: JSONValue?
    var summaryParts: [Int: OpenAIResponsesReasoningSummaryState]
}

func openAIResponsesSources(from raw: JSONValue, providerID: String) -> [AISource] {
    var sourceCounter = 0
    return raw["output"]?.arrayValue?.flatMap { item -> [AISource] in
        guard item["type"]?.stringValue == "message" else { return [] }
        return item["content"]?.arrayValue?.flatMap { content in
            openAIResponsesSources(fromAnnotations: content["annotations"]?.arrayValue ?? [], providerID: providerID, sourceCounter: &sourceCounter)
        } ?? []
    } ?? []
}

func openAIResponsesSources(fromAnnotations annotations: [JSONValue], providerID: String, sourceCounter: inout Int) -> [AISource] {
    annotations.compactMap { annotation in
        defer { sourceCounter += 1 }
        return openAIResponsesSource(from: annotation, id: "id-\(sourceCounter)", providerID: providerID)
    }
}

func openAIResponsesSource(from annotation: JSONValue, id: String, providerID: String) -> AISource? {
    switch annotation["type"]?.stringValue {
    case "url_citation":
        guard let url = annotation["url"]?.stringValue, !url.isEmpty else { return nil }
        return AISource(
            id: id,
            sourceType: "url",
            url: url,
            title: annotation["title"]?.stringValue,
            rawValue: annotation
        )
    case "file_citation":
        guard let fileID = annotation["file_id"]?.stringValue else { return nil }
        let filename = annotation["filename"]?.stringValue
        var metadata: [String: JSONValue] = [
            "type": .string("file_citation"),
            "fileId": .string(fileID)
        ]
        if let index = annotation["index"] {
            metadata["index"] = index
        }
        return AISource(
            id: id,
            sourceType: "document",
            title: filename,
            mediaType: "text/plain",
            filename: filename,
            providerMetadata: openAICompatibleNamespacedProviderMetadata(metadata, providerID: providerID),
            rawValue: annotation
        )
    case "container_file_citation":
        guard let fileID = annotation["file_id"]?.stringValue else { return nil }
        let filename = annotation["filename"]?.stringValue
        var metadata: [String: JSONValue] = [
            "type": .string("container_file_citation"),
            "fileId": .string(fileID)
        ]
        if let containerID = annotation["container_id"] {
            metadata["containerId"] = containerID
        }
        return AISource(
            id: id,
            sourceType: "document",
            title: filename,
            mediaType: "text/plain",
            filename: filename,
            providerMetadata: openAICompatibleNamespacedProviderMetadata(metadata, providerID: providerID),
            rawValue: annotation
        )
    case "file_path":
        guard let fileID = annotation["file_id"]?.stringValue else { return nil }
        var metadata: [String: JSONValue] = [
            "type": .string("file_path"),
            "fileId": .string(fileID)
        ]
        if let index = annotation["index"] {
            metadata["index"] = index
        }
        return AISource(
            id: id,
            sourceType: "document",
            title: fileID,
            mediaType: "application/octet-stream",
            filename: fileID,
            providerMetadata: openAICompatibleNamespacedProviderMetadata(metadata, providerID: providerID),
            rawValue: annotation
        )
    default:
        return nil
    }
}
