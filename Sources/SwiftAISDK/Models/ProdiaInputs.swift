import Foundation

func prodiaPrompt(from messages: [AIMessage]) -> String {
    let system = messages.first(where: { $0.role == .system })?.combinedText ?? ""
    let user = messages.reversed().first(where: { $0.role == .user })?.combinedText ?? ""
    if system.isEmpty { return user }
    if user.isEmpty { return system }
    return "\(system)\n\(user)"
}

func prodiaInputImage(from messages: [AIMessage], transport: AITransport, abortSignal: AIAbortSignal?) async throws -> (data: Data, mimeType: String)? {
    guard let user = messages.reversed().first(where: { $0.role == .user }) else { return nil }
    for part in user.content {
        switch part {
        case let .data(mimeType, data) where topLevelMediaType(mimeType) == "image",
             let .file(mimeType, data, _) where topLevelMediaType(mimeType) == "image":
            return (data, prodiaResolvedImageMediaType(mediaType: mimeType, data: data))
        case let .imageURL(urlString):
            let response = try await downloadURL(urlString, transport: transport, abortSignal: abortSignal)
            guard (200..<300).contains(response.statusCode) else {
                throw httpStatusError(provider: "prodia.language", response: response)
            }
            let mediaType = response.headers.first { $0.key.caseInsensitiveCompare("content-type") == .orderedSame }?.value ?? "image/png"
            return (response.body, prodiaResolvedImageMediaType(mediaType: mediaType, data: response.body))
        case .text, .data, .file, .providerReference, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
            continue
        }
    }
    return nil
}

func prodiaVideoInputImage(from image: ImageInputFile, transport: AITransport, abortSignal: AIAbortSignal?) async throws -> (data: Data, mimeType: String) {
    if let data = image.data {
        let mediaType = image.mediaType ?? detectMediaType(data: data, topLevelType: "image") ?? "image/png"
        return (data, prodiaResolvedImageMediaType(mediaType: mediaType, data: data))
    }
    guard let url = image.url else {
        throw AIError.invalidArgument(argument: "image", message: "Prodia video image input requires data or URL.")
    }
    let response = try await downloadURL(url, transport: transport, abortSignal: abortSignal)
    guard (200..<300).contains(response.statusCode) else {
        throw httpStatusError(provider: "prodia.video", response: response)
    }
    let mediaType = image.mediaType
        ?? response.headers.first { $0.key.caseInsensitiveCompare("content-type") == .orderedSame }?.value
        ?? detectMediaType(data: response.body, topLevelType: "image")
        ?? "image/png"
    return (response.body, prodiaResolvedImageMediaType(mediaType: mediaType, data: response.body))
}

func prodiaResolvedImageMediaType(mediaType: String, data: Data) -> String {
    if isFullMediaType(mediaType) {
        return mediaType
    }
    return detectMediaType(data: data, topLevelType: topLevelMediaType(mediaType)) ?? "image/png"
}

func mediaExtension(_ mimeType: String) -> String {
    switch mimeType.lowercased() {
    case "image/jpeg", "image/jpg":
        return ".jpg"
    case "image/webp":
        return ".webp"
    case "image/png":
        return ".png"
    case "video/mp4":
        return ".mp4"
    default:
        return ""
    }
}
