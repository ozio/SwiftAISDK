import Foundation

func audioProviderHTTPStatusError(provider: String, response: AIHTTPResponse) -> AIError {
    let body = audioProviderErrorMessage(from: response.body) ?? response.bodyText
    return apiCallError(
        provider: provider,
        statusCode: response.statusCode,
        body: body,
        headers: response.headers
    )
}

func audioProviderErrorMessage(from data: Data) -> String? {
    guard
        let json = try? JSONSerialization.jsonObject(with: data),
        let object = json as? [String: Any],
        let error = object["error"] as? [String: Any],
        let message = error["message"] as? String
    else {
        return nil
    }
    return message
}

func mapKeys(_ values: [String: JSONValue], _ mapping: [String: String]) -> [String: JSONValue] {
    var output: [String: JSONValue] = [:]
    for (key, value) in values {
        output[mapping[key] ?? key] = value
    }
    return output
}

func queryString(_ values: [String: String]) -> String {
    values
        .sorted { $0.key < $1.key }
        .map { "\(urlQueryEncode($0.key))=\(urlQueryEncode($0.value))" }
        .joined(separator: "&")
}

func urlQueryEncode(_ value: String) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: ":#[]@!$&'()*+,;=/")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

extension Dictionary where Key == String, Value == String {
    var contentType: String? {
        first { $0.key.caseInsensitiveCompare("content-type") == .orderedSame }?.value
    }
}
