import Foundation

func basetenDefaultChatModelID(config: ModelHTTPConfig) -> String {
    config.modelURL?.contains("/sync/v1") == true ? "placeholder" : "chat"
}

func basetenChatConfig(from config: ModelHTTPConfig) throws -> ModelHTTPConfig {
    if let modelURL = config.modelURL {
        if modelURL.contains("/predict") {
            throw AIError.invalidArgument(argument: "modelURL", message: "Not supported. You must use a /sync/v1 endpoint for chat models.")
        }
        if modelURL.contains("/sync/v1") {
            return config.withBaseURL(modelURL).withProviderID("baseten.chat")
        }
    }
    return config.withProviderID("baseten.chat")
}

func basetenEmbeddingConfigurationError(modelURL: String?) -> AIError {
    guard let modelURL else {
        return AIError.invalidArgument(argument: "modelURL", message: "No model URL provided for embeddings. Please set modelURL option for embeddings.")
    }
    if modelURL.contains("/predict") || !modelURL.contains("/sync") {
        return AIError.invalidArgument(argument: "modelURL", message: "Not supported. You must use a /sync or /sync/v1 endpoint for embeddings.")
    }
    return AIError.invalidArgument(argument: "modelURL", message: "No model URL provided for embeddings. Please set modelURL option for embeddings.")
}

func deepInfraRootBaseURL(_ baseURL: String) -> String {
    let normalized = withoutTrailingSlash(baseURL)
    if normalized.hasSuffix("/openai") {
        return String(normalized.dropLast("/openai".count))
    }
    if normalized.hasSuffix("/inference") {
        return String(normalized.dropLast("/inference".count))
    }
    return normalized
}

func deepInfraOpenAIURL(root: String, path: String, queryParams: [String: String]) throws -> URL {
    let string = "\(root)/openai\(path)"
    guard !queryParams.isEmpty else { return try requireURL(string) }
    guard var components = URLComponents(string: string) else { throw AIError.invalidURL(string) }
    var items = components.queryItems ?? []
    for key in queryParams.keys.sorted() {
        items.append(URLQueryItem(name: key, value: queryParams[key]))
    }
    components.queryItems = items
    guard let url = components.url else { throw AIError.invalidURL(string) }
    return url
}
