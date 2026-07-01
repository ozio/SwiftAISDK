import Foundation

extension AIResultContentPart {
    var responseMessagePart: AIContentPart? {
        switch self {
        case let .text(text, providerMetadata):
            return .text(text, providerMetadata: providerMetadata)
        case let .reasoning(text, providerMetadata):
            return .reasoning(text, providerMetadata: providerMetadata)
        case .source:
            return nil
        case let .file(file):
            if let data = file.data {
                return .file(
                    mimeType: file.mediaType,
                    data: data,
                    filename: file.filename,
                    providerMetadata: file.providerMetadata
                )
            }
            if let url = file.url {
                return .imageURL(url, providerMetadata: file.providerMetadata)
            }
            return nil
        case let .reasoningFile(file):
            return .reasoningFile(file)
        case let .custom(value, providerMetadata):
            return .custom(value, providerMetadata: providerMetadata)
        case let .toolCall(call):
            return .toolCall(call)
        case let .toolResult(result):
            return .toolResult(result)
        case let .toolApprovalRequest(request):
            return .toolApprovalRequest(request)
        case let .toolApprovalResponse(response):
            return .toolApprovalResponse(response)
        }
    }
}

extension TextGenerationResult {
    var responseMessageContentParts: [AIContentPart] {
        content.compactMap(\.responseMessagePart)
    }

    mutating func refreshDerivedContent() {
        files = resultFiles(from: content)
        sources = resultSources(from: content)
        toolCalls = resultToolCalls(from: content)
        toolResults = resultToolResults(from: content)
        toolApprovalRequests = resultToolApprovalRequests(from: content)
        toolApprovalResponses = resultToolApprovalResponses(from: content)
    }

    mutating func replaceToolCallContent(with calls: [AIToolCall]) {
        guard !calls.isEmpty else { return }
        var remaining = calls
        content = content.map { part in
            guard case let .toolCall(call) = part,
                  let index = remaining.firstIndex(where: { $0.id == call.id }) else {
                return part
            }
            let replacement = remaining.remove(at: index)
            return .toolCall(replacement)
        }
    }

    mutating func appendGeneratedToolContent(
        approvalRequests: [AIToolApprovalRequest],
        approvalResponses: [AIToolApprovalResponse],
        toolResults: [AIToolResult]
    ) {
        let respondedApprovalIDs = Set(approvalResponses.map(\.id))
        let respondedApprovalRequests = approvalRequests.filter { respondedApprovalIDs.contains($0.id) }
        let pendingApprovalRequests = approvalRequests.filter { !respondedApprovalIDs.contains($0.id) }

        content.append(contentsOf: respondedApprovalRequests.map(AIResultContentPart.toolApprovalRequest))
        content.append(contentsOf: approvalResponses.map(AIResultContentPart.toolApprovalResponse))
        content.append(contentsOf: toolResults.map(AIResultContentPart.toolResult))
        content.append(contentsOf: pendingApprovalRequests.map(AIResultContentPart.toolApprovalRequest))
        refreshDerivedContent()
    }

    mutating func ensureResponseMessages(toolsByName: [String: AITool] = [:]) async throws {
        guard responseMessages.isEmpty else { return }
        responseMessages = try await toResponseMessages(
            content: responseMessageContentParts,
            toolsByName: toolsByName
        )
    }
}

func makeResponseMessages(from content: [AIResultContentPart]) async throws -> [AIMessage] {
    try await toResponseMessages(content: content.compactMap(\.responseMessagePart))
}
