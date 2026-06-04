import Foundation

public enum ModelCapability: String, Hashable, Codable, CaseIterable, Sendable {
    case language
    case completion
    case embedding
    case image
    case transcription
    case speech
    case video
    case reranking
}

public enum MessageRole: String, Codable, Hashable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public enum AIContentPart: Equatable, Hashable, Sendable {
    case text(String)
    case imageURL(String)
    case data(mimeType: String, data: Data)
    case file(mimeType: String, data: Data, filename: String? = nil)
    case providerReference(mimeType: String, reference: AIProviderReference)
    case toolCall(AIToolCall)
    case toolResult(AIToolResult)
    case toolApprovalRequest(AIToolApprovalRequest)
    case toolApprovalResponse(AIToolApprovalResponse)

    public var text: String? {
        if case let .text(value) = self { value } else { nil }
    }

    public var filePayload: (mimeType: String, data: Data, filename: String?)? {
        switch self {
        case let .data(mimeType, data):
            return (mimeType, data, nil)
        case let .file(mimeType, data, filename):
            return (mimeType, data, filename)
        case .text, .imageURL, .providerReference, .toolCall, .toolResult, .toolApprovalRequest, .toolApprovalResponse:
            return nil
        }
    }
}

public struct AIMessage: Equatable, Hashable, Sendable {
    public var role: MessageRole
    public var content: [AIContentPart]
    public var reasoning: String?

    public init(role: MessageRole, content: [AIContentPart], reasoning: String? = nil) {
        self.role = role
        self.content = content
        self.reasoning = reasoning
    }

    public static func system(_ text: String) -> AIMessage {
        AIMessage(role: .system, content: [.text(text)])
    }

    public static func user(_ text: String) -> AIMessage {
        AIMessage(role: .user, content: [.text(text)])
    }

    public static func assistant(_ text: String, reasoning: String? = nil) -> AIMessage {
        AIMessage(role: .assistant, content: [.text(text)], reasoning: reasoning)
    }

    public static func assistant(
        text: String = "",
        reasoning: String? = nil,
        toolCalls: [AIToolCall],
        toolApprovalRequests: [AIToolApprovalRequest] = []
    ) -> AIMessage {
        AIMessage(
            role: .assistant,
            content: (text.isEmpty ? [] : [.text(text)])
                + toolCalls.map(AIContentPart.toolCall)
                + toolApprovalRequests.map(AIContentPart.toolApprovalRequest),
            reasoning: reasoning
        )
    }

    public static func toolResult(_ result: AIToolResult) -> AIMessage {
        AIMessage(role: .tool, content: [.toolResult(result)])
    }

    public static func toolResponses(
        approvalResponses: [AIToolApprovalResponse] = [],
        toolResults: [AIToolResult] = []
    ) -> AIMessage {
        AIMessage(
            role: .tool,
            content: approvalResponses.map(AIContentPart.toolApprovalResponse)
                + toolResults.map(AIContentPart.toolResult)
        )
    }

    public var combinedText: String {
        content.compactMap(\.text).joined(separator: "\n")
    }
}

