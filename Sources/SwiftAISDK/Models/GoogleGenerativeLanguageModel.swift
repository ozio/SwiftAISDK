import Foundation

public final class GoogleGenerativeLanguageModel: LanguageModel, @unchecked Sendable {
    public let providerID: String
    public let modelID: String
    private let config: ModelHTTPConfig

    init(modelID: String, config: ModelHTTPConfig) {
        self.providerID = config.providerID
        self.modelID = modelID
        self.config = config
    }

    public func generate(_ request: LanguageModelRequest) async throws -> TextGenerationResult {
        let prepared = try Self.generateContentBody(for: request, modelID: modelID)
        let response = try await config.sendJSONResponse(
            path: "/models/\(modelID):generateContent",
            modelID: modelID,
            body: prepared.body,
            headers: request.headers.mergingHeaders(prepared.headers),
            abortSignal: request.abortSignal
        )
        let raw = response.json
        let text = googleGenerateContentText(from: raw)
        let toolCalls = googleGenerateContentToolCalls(from: raw)
        let toolResults = googleGenerateContentToolResults(from: raw)
        guard text != nil || !toolCalls.isEmpty || !toolResults.isEmpty else {
            throw AIError.invalidResponse(provider: providerID, message: "No candidate text found in Google response.")
        }
        return TextGenerationResult(
            text: text ?? "",
            finishReason: googleGenerateContentFinishReason(raw["candidates"]?[0]?["finishReason"]?.stringValue, hasToolCalls: !toolCalls.isEmpty),
            usage: googleGenerateContentUsage(from: raw),
            toolCalls: toolCalls,
            toolResults: toolResults,
            sources: googleGenerateContentSources(from: raw),
            providerMetadata: googleGenerateContentProviderMetadata(from: raw),
            rawValue: raw,
            warnings: prepared.warnings,
            responseMetadata: googleGenerateContentResponseMetadata(from: raw, response: response.response, modelID: modelID)
        )
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<LanguageStreamPart, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let prepared = try Self.generateContentBody(for: request, modelID: modelID, isStreaming: true)
                    let httpRequest = try config.request(
                        path: "/models/\(modelID):streamGenerateContent?alt=sse",
                        modelID: modelID,
                        body: prepared.body,
                        headers: request.headers.mergingHeaders(prepared.headers),
                        abortSignal: request.abortSignal
                    )
                    let response = try await config.streamRequest(httpRequest)
                    guard (200..<300).contains(response.statusCode) else {
                        throw apiCallError(provider: providerID, response: try await bufferedHTTPResponse(from: response, request: httpRequest))
                    }
                    var state = GoogleGenerateContentStreamState(
                        response: httpResponseHead(from: response, request: httpRequest),
                        includeRawChunks: request.includeRawChunks,
                        modelID: modelID,
                        warnings: prepared.warnings
                    )
                    for try await event in serverSentEvents(from: response.body) {
                        if event.data == "[DONE]" { break }
                        let raw = try decodeJSONBody(Data(event.data.utf8))
                        for part in state.apply(raw) {
                            continuation.yield(part)
                        }
                    }
                    for part in state.finish() {
                        continuation.yield(part)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private static func generateContentBody(for request: LanguageModelRequest, modelID: String, isStreaming: Bool = false) throws -> GoogleGenerateContentPreparedCall {
        let preparedOptions = googlePrepareGenerateContentOptions(
            from: request,
            modelID: modelID,
            providerID: "google.generative-ai",
            isVertexProvider: false
        )
        var options = preparedOptions.options
        let responseFormat = googleResolvedResponseFormat(request: request, options: &options)
        var warnings = preparedOptions.warnings
        let systemText = request.messages
            .filter { $0.role == .system }
            .map(\.combinedText)
            .joined(separator: "\n")
        let rawContents = try request.messages
            .filter { $0.role != .system }
            .map { try googleGenerateContentMessageJSON($0, modelID: modelID, warnings: &warnings) }
        let preparedMessages = googleContentsWithSystemInstruction(systemText: systemText, contents: rawContents, modelID: modelID)

        var generationConfig: [String: JSONValue] = [:]
        googleApplyStandardGenerationSettings(request, to: &generationConfig)
        try googleApplyResponseFormat(responseFormat, options: options, to: &generationConfig)
        googleApplyProviderGenerationOptions(options, to: &generationConfig)

        var body: [String: JSONValue] = ["contents": .array(preparedMessages.contents)]
        if let systemInstruction = preparedMessages.systemInstruction {
            body["systemInstruction"] = systemInstruction
        }
        if !generationConfig.isEmpty { body["generationConfig"] = .object(generationConfig) }
        if let preparedTools = try googlePrepareTools(from: request.tools, toolChoice: options["toolChoice"], modelID: modelID, isVertexProvider: false) {
            warnings.append(contentsOf: preparedTools.warnings)
            if !preparedTools.tools.isEmpty {
                body["tools"] = .array(preparedTools.tools)
            }
            if let toolConfig = googleToolConfigWithProviderOptions(preparedTools.toolConfig, options: options, isStreaming: isStreaming, isVertexProvider: false) {
                body["toolConfig"] = toolConfig
            }
        } else if let toolConfig = googleToolConfigWithProviderOptions(nil, options: options, isStreaming: isStreaming, isVertexProvider: false) {
            body["toolConfig"] = toolConfig
        }
        body.merge(googleTopLevelGenerateContentOptions(options)) { _, new in new }
        body.merge(googleExtraBodyWithoutToolChoice(options)) { _, new in new }
        return GoogleGenerateContentPreparedCall(body: .object(body), warnings: warnings, headers: preparedOptions.headers)
    }

}

struct GoogleGenerateContentPreparedCall {
    var body: JSONValue
    var warnings: [AIWarning]
    var headers: [String: String]
}

extension GoogleGenerativeLanguageModel {
    static func imageGenerationContentBody(prompt: String, aspectRatio: String?, files: [ImageInputFile] = []) throws -> [String: JSONValue] {
        var generationConfig: [String: JSONValue] = ["responseModalities": .array(["IMAGE"])]
        if let aspectRatio {
            generationConfig["imageConfig"] = .object(["aspectRatio": .string(aspectRatio)])
        }
        var parts: [JSONValue] = []
        if !prompt.isEmpty {
            parts.append(.object(["text": .string(prompt)]))
        }
        for file in files {
            if let url = file.url {
                parts.append(.object([
                    "fileData": .object([
                        "fileUri": .string(url),
                        "mimeType": .string(file.mediaType ?? "image/*")
                    ])
                ]))
            } else if let data = file.data {
                parts.append(.object([
                    "inlineData": .object([
                        "mimeType": .string(try resolveFullMediaType(mediaType: file.mediaType ?? "image/*", data: data)),
                        "data": .string(data.base64EncodedString())
                    ])
                ]))
            }
        }
        return [
            "contents": .array([
                .object([
                    "role": .string("user"),
                    "parts": .array(parts.isEmpty ? [.object(["text": .string("")])] : parts)
                ])
            ]),
            "generationConfig": .object(generationConfig)
        ]
    }
}

let googleSkipThoughtSignatureValidator = "skip_thought_signature_validator"

func googleGenerateContentMessageJSON(
    _ message: AIMessage,
    modelID: String,
    includeFunctionCallIDs: Bool = true,
    warnings: inout [AIWarning]
) throws -> JSONValue {
    let role = message.role == .assistant ? "model" : "user"
    var parts: [JSONValue] = []
    var modelResponseHasSignedFunctionCall = false
    for part in message.content {
        if case let .toolCall(call) = part {
            let thoughtSignature = googleThoughtSignature(from: call.providerMetadata)
            let isServerToolCall = googleServerToolMetadata(from: call.providerMetadata) != nil
            let shouldSkipMissingSignatureMitigation = message.role == .assistant
                && !isServerToolCall
                && thoughtSignature == nil
                && modelResponseHasSignedFunctionCall
            parts.append(googleGenerateContentToolCallPart(
                call,
                modelID: modelID,
                includeFunctionCallIDs: includeFunctionCallIDs,
                skipMissingSignatureMitigation: shouldSkipMissingSignatureMitigation,
                warnings: &warnings
            ))
            if message.role == .assistant, !isServerToolCall, thoughtSignature != nil {
                modelResponseHasSignedFunctionCall = true
            }
            continue
        }
        parts.append(contentsOf: try googleGenerateContentParts(
            part,
            modelID: modelID,
            includeFunctionCallIDs: includeFunctionCallIDs,
            warnings: &warnings
        ))
    }
    return .object(["role": .string(role), "parts": .array(parts)])
}

func googleGenerateContentParts(
    _ part: AIContentPart,
    modelID: String,
    includeFunctionCallIDs: Bool = true,
    warnings: inout [AIWarning]
) throws -> [JSONValue] {
    switch part {
    case let .text(text, _):
        return [.object(["text": .string(text)])]
    case let .reasoning(text, _):
        return [.object(["text": .string(text)])]
    case let .imageURL(url, _):
        return [.object(["fileData": .object(["fileUri": .string(url)])])]
    case let .data(mimeType, data, _), let .file(mimeType, data, _, _):
        let resolvedMimeType = try resolveFullMediaType(mediaType: mimeType, data: data)
        return [.object([
            "inlineData": .object([
                "mimeType": .string(resolvedMimeType),
                "data": .string(data.base64EncodedString())
            ])
        ])]
    case let .providerReference(_, reference, _, _):
        return [.object(["fileData": .object(["fileUri": .string((try? resolveProviderReference(reference, provider: "google")) ?? reference.values.first ?? "")])])]
    case let .toolCall(call):
        return [googleGenerateContentToolCallPart(
            call,
            modelID: modelID,
            includeFunctionCallIDs: includeFunctionCallIDs,
            warnings: &warnings
        )]
    case let .toolResult(result):
        return googleGenerateContentToolResultParts(
            result,
            modelID: modelID,
            includeFunctionCallIDs: includeFunctionCallIDs
        )
    case .reasoningFile, .custom, .toolApprovalRequest, .toolApprovalResponse:
        return [.object(["text": .string("")])]
    }
}

func googleGenerateContentToolCallPart(
    _ call: AIToolCall,
    modelID: String,
    includeFunctionCallIDs: Bool = true,
    skipMissingSignatureMitigation: Bool = false,
    warnings: inout [AIWarning]
) -> JSONValue {
    let thoughtSignature = googleThoughtSignature(from: call.providerMetadata)
    let effectiveThoughtSignature: JSONValue?
    if thoughtSignature == nil,
       googleMessageTargetIsGemini3(modelID),
       !skipMissingSignatureMitigation {
        effectiveThoughtSignature = .string(googleSkipThoughtSignatureValidator)
        warnings.append(googleMissingThoughtSignatureWarning(toolName: call.name))
    } else {
        effectiveThoughtSignature = thoughtSignature
    }

    var output: [String: JSONValue]
    if let serverTool = googleServerToolMetadata(from: call.providerMetadata) {
        output = [
            "toolCall": .object([
                "toolType": .string(serverTool.type),
                "id": .string(serverTool.id),
                "args": googleToolArguments(call.arguments)
            ])
        ]
    } else {
        var functionCall: [String: JSONValue] = [
            "name": .string(call.name),
            "args": googleToolArguments(call.arguments)
        ]
        if includeFunctionCallIDs {
            functionCall["id"] = .string(call.id)
        }
        output = [
            "functionCall": .object(functionCall)
        ]
    }
    if let effectiveThoughtSignature {
        output["thoughtSignature"] = effectiveThoughtSignature
    }
    return .object(output)
}

func googleGenerateContentToolResultParts(
    _ result: AIToolResult,
    modelID: String,
    includeFunctionCallIDs: Bool = true
) -> [JSONValue] {
    if let serverTool = googleServerToolMetadata(from: result.providerMetadata) {
        var output: [String: JSONValue] = [
            "toolResponse": .object([
                "toolType": .string(serverTool.type),
                "id": .string(serverTool.id),
                "response": result.modelOutput ?? result.result
            ])
        ]
        if let thoughtSignature = googleThoughtSignature(from: result.providerMetadata) {
            output["thoughtSignature"] = thoughtSignature
        }
        return [.object(output)]
    }

    let output = result.modelOutput ?? result.result
    if output["type"]?.stringValue == "content",
       let value = output["value"]?.arrayValue {
        return googleGenerateContentToolResultContentParts(
            toolName: result.toolName,
            toolCallID: result.toolCallID,
            content: value,
            supportsFunctionResponseParts: googleMessageTargetIsGemini3(modelID),
            includeFunctionCallIDs: includeFunctionCallIDs
        )
    }

    var functionResponse: [String: JSONValue] = [
        "name": .string(result.toolName),
        "response": output
    ]
    if includeFunctionCallIDs {
        functionResponse["id"] = .string(result.toolCallID)
    }
    return [.object([
        "functionResponse": .object(functionResponse)
    ])]
}

func googleGenerateContentToolResultContentParts(
    toolName: String,
    toolCallID: String,
    content: [JSONValue],
    supportsFunctionResponseParts: Bool,
    includeFunctionCallIDs: Bool = true
) -> [JSONValue] {
    var textParts: [String] = []
    var inlineParts: [JSONValue] = []
    var legacyParts: [JSONValue] = []

    for contentPart in content {
        switch contentPart["type"]?.stringValue {
        case "text":
            textParts.append(contentPart["text"]?.stringValue ?? "")
        case "file", "image-data", "file-data":
            if let inlineData = googleInlineDataFromToolContent(contentPart) {
                if supportsFunctionResponseParts {
                    inlineParts.append(inlineData)
                } else {
                    legacyParts.append(.object(inlineData.objectValue ?? [:]))
                    legacyParts.append(.object(["text": .string("Tool executed successfully and returned this file as a response")]))
                }
            } else {
                textParts.append(googleJSONString(contentPart) ?? String(describing: contentPart))
            }
        default:
            textParts.append(googleJSONString(contentPart) ?? String(describing: contentPart))
        }
    }

    if !supportsFunctionResponseParts, !legacyParts.isEmpty {
        if !textParts.isEmpty {
            var functionResponse: [String: JSONValue] = [
                "name": .string(toolName),
                "response": .object(["name": .string(toolName), "content": .string(textParts.joined(separator: "\n"))])
            ]
            if includeFunctionCallIDs {
                functionResponse["id"] = .string(toolCallID)
            }
            legacyParts.insert(.object([
                "functionResponse": .object(functionResponse)
            ]), at: 0)
        }
        return legacyParts
    }

    var response: [String: JSONValue] = [
        "name": .string(toolName),
        "response": .object([
            "name": .string(toolName),
            "content": .string(textParts.isEmpty ? "Tool executed successfully." : textParts.joined(separator: "\n"))
        ])
    ]
    if includeFunctionCallIDs {
        response["id"] = .string(toolCallID)
    }
    if !inlineParts.isEmpty {
        response["parts"] = .array(inlineParts)
    }
    return [.object(["functionResponse": .object(response)])]
}

func googleInlineDataFromToolContent(_ contentPart: JSONValue) -> JSONValue? {
    if let mediaType = contentPart["mediaType"]?.stringValue,
       let data = contentPart["data"]?["data"]?.stringValue ?? contentPart["data"]?.stringValue {
        return .object(["inlineData": .object(["mimeType": .string(mediaType), "data": .string(data)])])
    }
    return nil
}

func googleMessageTargetIsGemini3(_ modelID: String) -> Bool {
    googleModelCapabilities(for: modelID).usesGemini3Features
}

func googleMissingThoughtSignatureWarning(toolName: String) -> AIWarning {
    AIWarning(
        type: "other",
        message: "Replayed `functionCall` part for a Gemini 3 model without a `thoughtSignature` (tool: `\(toolName)`). Injected the documented `skip_thought_signature_validator` sentinel to keep the request from failing with HTTP 400. The likely cause is application code that drops `providerOptions.google.thoughtSignature` when persisting or serializing assistant tool-call messages. See https://ai.google.dev/gemini-api/docs/thought-signatures."
    )
}

func googleToolArguments(_ arguments: String) -> JSONValue {
    (try? decodeJSONBody(Data(arguments.utf8))) ?? .object([:])
}

func googleJSONString(_ value: JSONValue) -> String? {
    guard let data = try? encodeJSONBody(value) else { return nil }
    return String(data: data, encoding: .utf8)
}
