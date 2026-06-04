import Foundation

struct MultipartResponsePart {
    var name: String?
    var fileName: String?
    var contentType: String?
    var body: Data
    var json: JSONValue?
}

func parseMultipartResponse(_ response: AIHTTPResponse) throws -> [MultipartResponsePart] {
    guard let contentType = response.headers.first(where: { $0.key.caseInsensitiveCompare("content-type") == .orderedSame })?.value,
          let boundaryRange = contentType.range(of: "boundary=") else {
        throw AIError.invalidResponse(provider: "multipart", message: "Response missing multipart boundary.")
    }
    let boundary = String(contentType[boundaryRange.upperBound...])
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        .split(separator: ";", maxSplits: 1)
        .first
        .map(String.init) ?? ""
    let marker = Data("--\(boundary)".utf8)
    let delimiter = Data("\r\n\r\n".utf8)
    let lineBreak = Data("\r\n".utf8)
    let ranges = response.body.ranges(of: marker)
    guard ranges.count >= 2 else { return [] }

    return ranges.indices.dropLast().compactMap { index in
        var part = response.body[ranges[index].upperBound..<ranges[index + 1].lowerBound]
        if part.starts(with: lineBreak) {
            part.removeFirst(lineBreak.count)
        }
        if part.starts(with: Data("--".utf8)) {
            return nil
        }
        while part.last == 10 || part.last == 13 {
            part.removeLast()
        }
        guard let separator = part.range(of: delimiter) else { return nil }
        let headerData = part[part.startIndex..<separator.lowerBound]
        var bodyData = Data(part[separator.upperBound..<part.endIndex])
        if bodyData.count >= 2,
           bodyData[bodyData.count - 2] == 13,
           bodyData[bodyData.count - 1] == 10 {
            bodyData.removeLast(2)
        }
        let headerText = String(data: headerData, encoding: .utf8) ?? ""
        let headers = Dictionary(uniqueKeysWithValues: headerText.split(separator: "\r\n").compactMap { line -> (String, String)? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return (String(line[..<colon]).lowercased(), String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
        })
        let disposition = headers["content-disposition"] ?? ""
        func dispositionValue(_ key: String) -> String? {
            disposition.components(separatedBy: ";").compactMap { part -> String? in
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("\(key)=") else { return nil }
                return trimmed.dropFirst("\(key)=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }.first
        }
        let name = dispositionValue("name")
        let fileName = dispositionValue("filename")
        let jsonData: Data
        if headers["content-type"]?.localizedCaseInsensitiveContains("json") == true,
           let text = String(data: bodyData, encoding: .utf8) {
            jsonData = Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        } else {
            jsonData = bodyData
        }
        let json = try? decodeJSONBody(jsonData)
        return MultipartResponsePart(name: name, fileName: fileName, contentType: headers["content-type"], body: bodyData, json: json)
    }
}

func multipartRawValue(_ parts: [MultipartResponsePart]) -> JSONValue {
    .object([
        "parts": .array(parts.map { part in
            .object([
                "name": part.name.map(JSONValue.string),
                "fileName": part.fileName.map(JSONValue.string),
                "contentType": part.contentType.map(JSONValue.string),
                "base64": part.contentType?.hasPrefix("image/") == true || part.contentType?.hasPrefix("video/") == true ? .string(part.body.base64EncodedString()) : nil,
                "json": part.json
            ])
        })
    ])
}

extension Data {
    func ranges(of needle: Data) -> [Range<Data.Index>] {
        guard !needle.isEmpty else { return [] }
        var ranges: [Range<Data.Index>] = []
        var searchStart = startIndex
        while searchStart < endIndex,
              let range = self[searchStart..<endIndex].range(of: needle) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }
}
