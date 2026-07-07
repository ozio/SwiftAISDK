import Foundation

public enum OpenAITools {
    public static func applyPatch() -> JSONValue {
        providerTool(id: "openai.apply_patch", name: "apply_patch")
    }

    public static func customTool(name: String, description: String? = nil, format: JSONValue? = nil) -> JSONValue {
        providerTool(id: "openai.custom", name: name, args: JSONValue.object([
            "description": description.map(JSONValue.string),
            "format": format
        ]).objectValue ?? [:])
    }

    public static func codeInterpreter(container: JSONValue? = nil) -> JSONValue {
        providerTool(id: "openai.code_interpreter", name: "code_interpreter", args: JSONValue.object([
            "container": container
        ]).objectValue ?? [:])
    }

    public static func computerUse(displayWidth: Int? = nil, displayHeight: Int? = nil, environment: String? = nil, extraArgs: [String: JSONValue] = [:]) -> JSONValue {
        var args = extraArgs
        if let displayWidth { args["displayWidth"] = .number(Double(displayWidth)) }
        if let displayHeight { args["displayHeight"] = .number(Double(displayHeight)) }
        if let environment { args["environment"] = .string(environment) }
        return providerTool(id: "openai.computer_use", name: "computer_use", args: args)
    }

    public static func fileSearch(vectorStoreIDs: [String], maxNumResults: Int? = nil, ranking: JSONValue? = nil, filters: JSONValue? = nil) -> JSONValue {
        providerTool(id: "openai.file_search", name: "file_search", args: JSONValue.object([
            "vectorStoreIds": .array(vectorStoreIDs),
            "maxNumResults": maxNumResults.map { .number(Double($0)) },
            "ranking": ranking,
            "filters": filters
        ]).objectValue ?? [:])
    }

    public static func imageGeneration(
        background: String? = nil,
        inputFidelity: String? = nil,
        inputImageMask: JSONValue? = nil,
        model: String? = nil,
        moderation: String? = nil,
        outputCompression: Int? = nil,
        outputFormat: String? = nil,
        partialImages: Int? = nil,
        quality: String? = nil,
        size: String? = nil
    ) -> JSONValue {
        providerTool(id: "openai.image_generation", name: "image_generation", args: JSONValue.object([
            "background": background.map(JSONValue.string),
            "inputFidelity": inputFidelity.map(JSONValue.string),
            "inputImageMask": inputImageMask,
            "model": model.map(JSONValue.string),
            "moderation": moderation.map(JSONValue.string),
            "outputCompression": outputCompression.map { .number(Double($0)) },
            "outputFormat": outputFormat.map(JSONValue.string),
            "partialImages": partialImages.map { .number(Double($0)) },
            "quality": quality.map(JSONValue.string),
            "size": size.map(JSONValue.string)
        ]).objectValue ?? [:])
    }

    public static func localShell() -> JSONValue {
        providerTool(id: "openai.local_shell", name: "local_shell")
    }

    public static func shell(environment: JSONValue? = nil) -> JSONValue {
        providerTool(id: "openai.shell", name: "shell", args: JSONValue.object([
            "environment": environment
        ]).objectValue ?? [:])
    }

    public static func shellContainerAutoEnvironment(
        fileIDs: [String] = [],
        memoryLimit: String? = nil,
        networkPolicy: JSONValue? = nil,
        skills: [JSONValue] = []
    ) -> JSONValue {
        JSONValue.object([
            "type": .string("containerAuto"),
            "fileIds": fileIDs.isEmpty ? nil : .array(fileIDs),
            "memoryLimit": memoryLimit.map(JSONValue.string),
            "networkPolicy": networkPolicy,
            "skills": skills.isEmpty ? nil : .array(skills)
        ])
    }

    public static func shellContainerReferenceEnvironment(containerID: String) -> JSONValue {
        JSONValue.object([
            "type": .string("containerReference"),
            "containerId": .string(containerID)
        ])
    }

    public static func shellLocalEnvironment(skills: [JSONValue] = []) -> JSONValue {
        JSONValue.object([
            "type": .string("local"),
            "skills": skills.isEmpty ? nil : .array(skills)
        ])
    }

    public static func shellDisabledNetworkPolicy() -> JSONValue {
        ["type": "disabled"]
    }

    public static func shellAllowlistNetworkPolicy(allowedDomains: [String], domainSecrets: [JSONValue] = []) -> JSONValue {
        JSONValue.object([
            "type": .string("allowlist"),
            "allowedDomains": .array(allowedDomains),
            "domainSecrets": domainSecrets.isEmpty ? nil : .array(domainSecrets)
        ])
    }

    public static func shellDomainSecret(domain: String, name: String, value: String) -> JSONValue {
        [
            "domain": .string(domain),
            "name": .string(name),
            "value": .string(value)
        ]
    }

    public static func shellSkillReference(skillID: String, version: String? = nil) -> JSONValue {
        JSONValue.object([
            "type": .string("skillReference"),
            "skillId": .string(skillID),
            "version": version.map(JSONValue.string)
        ])
    }

    public static func shellSkillReference(providerReference: [String: String], version: String? = nil) -> JSONValue {
        JSONValue.object([
            "type": .string("skillReference"),
            "providerReference": .object(providerReference.mapValues(JSONValue.string)),
            "version": version.map(JSONValue.string)
        ])
    }

    public static func shellInlineSkill(name: String, description: String, base64ZipData: String) -> JSONValue {
        [
            "type": "inline",
            "name": .string(name),
            "description": .string(description),
            "source": [
                "type": "base64",
                "mediaType": "application/zip",
                "data": .string(base64ZipData)
            ]
        ]
    }

    public static func shellLocalSkill(name: String, description: String, path: String) -> JSONValue {
        [
            "name": .string(name),
            "description": .string(description),
            "path": .string(path)
        ]
    }

    public static func webSearchPreview(searchContextSize: String? = nil, userLocation: JSONValue? = nil) -> JSONValue {
        providerTool(id: "openai.web_search_preview", name: "web_search_preview", args: JSONValue.object([
            "searchContextSize": searchContextSize.map(JSONValue.string),
            "userLocation": userLocation
        ]).objectValue ?? [:])
    }

    public static func webSearch(
        filters: JSONValue? = nil,
        externalWebAccess: Bool? = nil,
        searchContextSize: String? = nil,
        userLocation: JSONValue? = nil
    ) -> JSONValue {
        providerTool(id: "openai.web_search", name: "web_search", args: JSONValue.object([
            "filters": filters,
            "externalWebAccess": externalWebAccess.map(JSONValue.bool),
            "searchContextSize": searchContextSize.map(JSONValue.string),
            "userLocation": userLocation
        ]).objectValue ?? [:])
    }

    public static func mcp(
        serverLabel: String,
        allowedTools: JSONValue? = nil,
        authorization: String? = nil,
        connectorID: String? = nil,
        headers: JSONValue? = nil,
        requireApproval: JSONValue? = nil,
        serverDescription: String? = nil,
        serverURL: String? = nil
    ) -> JSONValue {
        providerTool(id: "openai.mcp", name: "mcp", args: JSONValue.object([
            "serverLabel": .string(serverLabel),
            "allowedTools": allowedTools,
            "authorization": authorization.map(JSONValue.string),
            "connectorId": connectorID.map(JSONValue.string),
            "headers": headers,
            "requireApproval": requireApproval,
            "serverDescription": serverDescription.map(JSONValue.string),
            "serverUrl": serverURL.map(JSONValue.string)
        ]).objectValue ?? [:])
    }

    public static func toolSearch(execution: JSONValue? = nil, description: String? = nil, parameters: JSONValue? = nil) -> JSONValue {
        providerTool(id: "openai.tool_search", name: "tool_search", args: JSONValue.object([
            "execution": execution,
            "description": description.map(JSONValue.string),
            "parameters": parameters
        ]).objectValue ?? [:])
    }

    static func providerTool(id: String, name: String, args: [String: JSONValue] = [:]) -> JSONValue {
        .object([
            "type": .string("provider"),
            "id": .string(id),
            "name": .string(name),
            "args": .object(args)
        ])
    }
}

public enum AzureOpenAITools {
    public static func codeInterpreter(container: JSONValue? = nil) -> JSONValue {
        OpenAITools.codeInterpreter(container: container)
    }

    public static func fileSearch(vectorStoreIDs: [String], maxNumResults: Int? = nil, ranking: JSONValue? = nil, filters: JSONValue? = nil) -> JSONValue {
        OpenAITools.fileSearch(vectorStoreIDs: vectorStoreIDs, maxNumResults: maxNumResults, ranking: ranking, filters: filters)
    }

    public static func imageGeneration(
        background: String? = nil,
        inputFidelity: String? = nil,
        inputImageMask: JSONValue? = nil,
        model: String? = nil,
        moderation: String? = nil,
        outputCompression: Int? = nil,
        outputFormat: String? = nil,
        partialImages: Int? = nil,
        quality: String? = nil,
        size: String? = nil
    ) -> JSONValue {
        OpenAITools.imageGeneration(
            background: background,
            inputFidelity: inputFidelity,
            inputImageMask: inputImageMask,
            model: model,
            moderation: moderation,
            outputCompression: outputCompression,
            outputFormat: outputFormat,
            partialImages: partialImages,
            quality: quality,
            size: size
        )
    }

    public static func webSearch(filters: JSONValue? = nil, externalWebAccess: Bool? = nil, searchContextSize: String? = nil, userLocation: JSONValue? = nil) -> JSONValue {
        OpenAITools.webSearch(filters: filters, externalWebAccess: externalWebAccess, searchContextSize: searchContextSize, userLocation: userLocation)
    }

    public static func webSearchPreview(searchContextSize: String? = nil, userLocation: JSONValue? = nil) -> JSONValue {
        OpenAITools.webSearchPreview(searchContextSize: searchContextSize, userLocation: userLocation)
    }
}

public enum AuthorizationStyle: Equatable, Hashable, Sendable {
    case bearer(environmentVariables: [String])
    case token(environmentVariables: [String])
    case apiKeyHeader(name: String, prefix: String? = nil, environmentVariables: [String])
    case none
}

public struct ProviderSettings: Sendable {
    public var apiKey: String?
    public var authToken: String?
    public var baseURL: String?
    public var modelURL: String?
    public var organization: String?
    public var project: String?
    public var headers: [String: String]
    public var queryParams: [String: String]
    public var environment: [String: String]?
    public var transport: any AITransport
    public var includeUsage: Bool
    public var supportsStructuredOutputs: Bool
    public var maxEmbeddingsPerCall: Int?
    public var transformRequestBody: (@Sendable ([String: JSONValue]) -> [String: JSONValue])?
    public var name: String?

    public init(
        apiKey: String? = nil,
        authToken: String? = nil,
        baseURL: String? = nil,
        modelURL: String? = nil,
        organization: String? = nil,
        project: String? = nil,
        headers: [String: String] = [:],
        queryParams: [String: String] = [:],
        environment: [String: String]? = nil,
        transport: any AITransport = URLSessionTransport.shared,
        includeUsage: Bool = false,
        supportsStructuredOutputs: Bool = false,
        maxEmbeddingsPerCall: Int? = nil,
        transformRequestBody: (@Sendable ([String: JSONValue]) -> [String: JSONValue])? = nil,
        name: String? = nil
    ) {
        self.apiKey = apiKey
        self.authToken = authToken
        self.baseURL = baseURL
        self.modelURL = modelURL
        self.organization = organization
        self.project = project
        self.headers = headers
        self.queryParams = queryParams
        self.environment = environment
        self.transport = transport
        self.includeUsage = includeUsage
        self.supportsStructuredOutputs = supportsStructuredOutputs
        self.maxEmbeddingsPerCall = maxEmbeddingsPerCall
        self.transformRequestBody = transformRequestBody
        self.name = name
    }

    func environmentValue(_ names: [String]) -> String? {
        if let environment {
            return names.lazy.compactMap { environment[$0] }.first
        }
        return SwiftAISDK.environmentValue(names)
    }
}

struct ModelHTTPConfig: @unchecked Sendable {
    var providerID: String
    var baseURL: String
    var modelURL: String?
    var headers: [String: String]
    var transport: any AITransport
    var includeUsage: Bool
    var queryParams: [String: String]
    var supportsStructuredOutputs: Bool
    var maxEmbeddingsPerCall: Int?
    var transformRequestBody: (@Sendable ([String: JSONValue]) -> [String: JSONValue])?
    var responsesRequestMode: ResponsesRequestMode
    var openAIBackedProviderRoot: String?
    var usesGenericOpenAICompatibleProviderOptions: Bool
    var deepSeekSupportsThinking: Bool
    var url: @Sendable (String, String) throws -> URL

    init(
        providerID: String,
        baseURL: String,
        modelURL: String? = nil,
        headers: [String: String],
        transport: any AITransport,
        includeUsage: Bool = false,
        queryParams: [String: String] = [:],
        supportsStructuredOutputs: Bool = false,
        maxEmbeddingsPerCall: Int? = nil,
        transformRequestBody: (@Sendable ([String: JSONValue]) -> [String: JSONValue])? = nil,
        responsesRequestMode: ResponsesRequestMode = .openAICompatible,
        openAIBackedProviderRoot: String? = nil,
        usesGenericOpenAICompatibleProviderOptions: Bool = false,
        deepSeekSupportsThinking: Bool = true,
        url: (@Sendable (String, String) throws -> URL)? = nil
    ) {
        self.providerID = providerID
        let normalizedBaseURL = withoutTrailingSlash(baseURL)
        self.baseURL = normalizedBaseURL
        self.modelURL = modelURL.map(withoutTrailingSlash)
        self.headers = headers
        self.transport = transport
        self.includeUsage = includeUsage
        self.queryParams = queryParams
        self.supportsStructuredOutputs = supportsStructuredOutputs
        self.maxEmbeddingsPerCall = maxEmbeddingsPerCall
        self.transformRequestBody = transformRequestBody
        self.responsesRequestMode = responsesRequestMode
        self.openAIBackedProviderRoot = openAIBackedProviderRoot
        self.usesGenericOpenAICompatibleProviderOptions = usesGenericOpenAICompatibleProviderOptions
        self.deepSeekSupportsThinking = deepSeekSupportsThinking
        self.url = url ?? { _, path in
            try openAICompatibleURL("\(normalizedBaseURL)\(path)", queryParams: queryParams)
        }
    }

    func request(path: String, modelID: String, body: JSONValue, headers requestHeaders: [String: String] = [:], abortSignal: AIAbortSignal? = nil) throws -> AIHTTPRequest {
        try rawRequest(
            path: path,
            modelID: modelID,
            body: try encodeJSONBody(body),
            contentType: "application/json",
            headers: requestHeaders,
            abortSignal: abortSignal
        )
    }

    func rawRequest(path: String, modelID: String, body: Data, contentType: String?, headers requestHeaders: [String: String] = [:], abortSignal: AIAbortSignal? = nil) throws -> AIHTTPRequest {
        var headers = self.headers.mergingHeaders(requestHeaders)
        if let contentType {
            headers["content-type"] = headers["content-type"] ?? contentType
        }
        headers["user-agent"] = headers["user-agent"] ?? userAgent(providerID)
        return AIHTTPRequest(
            method: "POST",
            url: try url(modelID, path),
            headers: headers,
            body: body,
            abortSignal: abortSignal
        )
    }

    func sendJSON(path: String, modelID: String, body: JSONValue, headers: [String: String] = [:], abortSignal: AIAbortSignal? = nil) async throws -> JSONValue {
        try await sendJSONResponse(path: path, modelID: modelID, body: body, headers: headers, abortSignal: abortSignal).json
    }

    func sendJSONResponse(path: String, modelID: String, body: JSONValue, headers: [String: String] = [:], abortSignal: AIAbortSignal? = nil) async throws -> (json: JSONValue, response: AIHTTPResponse) {
        let response = try await transport.send(request(path: path, modelID: modelID, body: body, headers: headers, abortSignal: abortSignal))
        guard (200..<300).contains(response.statusCode) else {
            throw apiCallError(provider: providerID, response: response)
        }
        return (try response.jsonValue(), response)
    }

    func withProviderID(_ providerID: String) -> ModelHTTPConfig {
        ModelHTTPConfig(
            providerID: providerID,
            baseURL: baseURL,
            modelURL: modelURL,
            headers: headers,
            transport: transport,
            includeUsage: includeUsage,
            queryParams: queryParams,
            supportsStructuredOutputs: supportsStructuredOutputs,
            maxEmbeddingsPerCall: maxEmbeddingsPerCall,
            transformRequestBody: transformRequestBody,
            responsesRequestMode: responsesRequestMode,
            openAIBackedProviderRoot: openAIBackedProviderRoot,
            usesGenericOpenAICompatibleProviderOptions: usesGenericOpenAICompatibleProviderOptions,
            deepSeekSupportsThinking: deepSeekSupportsThinking,
            url: url
        )
    }

    func withDeepSeekSupportsThinking(_ supportsThinking: Bool) -> ModelHTTPConfig {
        ModelHTTPConfig(
            providerID: providerID,
            baseURL: baseURL,
            modelURL: modelURL,
            headers: headers,
            transport: transport,
            includeUsage: includeUsage,
            queryParams: queryParams,
            supportsStructuredOutputs: supportsStructuredOutputs,
            maxEmbeddingsPerCall: maxEmbeddingsPerCall,
            transformRequestBody: transformRequestBody,
            responsesRequestMode: responsesRequestMode,
            openAIBackedProviderRoot: openAIBackedProviderRoot,
            usesGenericOpenAICompatibleProviderOptions: usesGenericOpenAICompatibleProviderOptions,
            deepSeekSupportsThinking: supportsThinking,
            url: url
        )
    }

    func withBaseURL(_ baseURL: String) -> ModelHTTPConfig {
        ModelHTTPConfig(
            providerID: providerID,
            baseURL: baseURL,
            modelURL: modelURL,
            headers: headers,
            transport: transport,
            includeUsage: includeUsage,
            queryParams: queryParams,
            supportsStructuredOutputs: supportsStructuredOutputs,
            maxEmbeddingsPerCall: maxEmbeddingsPerCall,
            transformRequestBody: transformRequestBody,
            responsesRequestMode: responsesRequestMode,
            openAIBackedProviderRoot: openAIBackedProviderRoot,
            usesGenericOpenAICompatibleProviderOptions: usesGenericOpenAICompatibleProviderOptions
        )
    }
}
