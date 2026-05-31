import Foundation
import Testing
@testable import ai_sdk_port

actor RecordingTransport: AITransport {
    private var _requests: [AIHTTPRequest] = []
    private var responses: [AIHTTPResponse]

    init(response: AIHTTPResponse) {
        self.responses = [response]
    }

    init(responses: [AIHTTPResponse]) {
        self.responses = responses
    }

    func requests() -> [AIHTTPRequest] {
        _requests
    }

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        _requests.append(request)
        if responses.count > 1 {
            return responses.removeFirst()
        }
        return responses[0]
    }
}

func jsonResponse(_ json: String) -> AIHTTPResponse {
    AIHTTPResponse(statusCode: 200, headers: ["content-type": "application/json"], body: Data(json.utf8))
}

func sseResponse(_ text: String) -> AIHTTPResponse {
    AIHTTPResponse(statusCode: 200, headers: ["content-type": "text/event-stream"], body: Data(text.utf8))
}

func multipartResponse(parts: [(name: String, contentType: String, body: Data)]) -> AIHTTPResponse {
    let boundary = "test-boundary"
    var body = Data()
    for part in parts {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(part.name)\"\r\n".utf8))
        body.append(Data("Content-Type: \(part.contentType)\r\n\r\n".utf8))
        body.append(part.body)
        body.append(Data("\r\n".utf8))
    }
    body.append(Data("--\(boundary)--\r\n".utf8))
    return AIHTTPResponse(statusCode: 200, headers: ["content-type": "multipart/form-data; boundary=\(boundary)"], body: body)
}

func amazonEventStreamResponse(_ events: [(eventType: String, payload: String)]) -> AIHTTPResponse {
    let body = events.reduce(into: Data()) { data, event in
        data.append(amazonEventStreamFrame(eventType: event.eventType, payload: Data(event.payload.utf8)))
    }
    return AIHTTPResponse(statusCode: 200, headers: ["content-type": "application/vnd.amazon.eventstream"], body: body)
}

private func amazonEventStreamFrame(eventType: String, payload: Data) -> Data {
    var headers = Data()
    appendAmazonStringHeader(name: ":message-type", value: "event", to: &headers)
    appendAmazonStringHeader(name: ":event-type", value: eventType, to: &headers)

    let totalLength = UInt32(12 + headers.count + payload.count + 4)
    var frame = Data()
    appendUInt32(totalLength, to: &frame)
    appendUInt32(UInt32(headers.count), to: &frame)
    appendUInt32(0, to: &frame)
    frame.append(headers)
    frame.append(payload)
    appendUInt32(0, to: &frame)
    return frame
}

private func appendAmazonStringHeader(name: String, value: String, to data: inout Data) {
    let nameData = Data(name.utf8)
    let valueData = Data(value.utf8)
    data.append(UInt8(nameData.count))
    data.append(nameData)
    data.append(7)
    appendUInt16(UInt16(valueData.count), to: &data)
    data.append(valueData)
}

private func appendUInt16(_ value: UInt16, to data: inout Data) {
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8(value & 0xff))
}

private func appendUInt32(_ value: UInt32, to data: inout Data) {
    data.append(UInt8((value >> 24) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8(value & 0xff))
}
