import Foundation

func aiResponseMetadata(from raw: JSONValue? = nil, response: AIHTTPResponse, modelID: String? = nil) -> AIResponseMetadata {
    AIResponseMetadata(
        id: raw?["id"]?.stringValue ?? raw?["name"]?.stringValue,
        timestamp: raw?["created"]?.doubleValue.map { Date(timeIntervalSince1970: $0) } ?? Date(),
        modelID: raw?["model"]?.stringValue ?? modelID,
        headers: response.headers,
        body: raw
    )
}
