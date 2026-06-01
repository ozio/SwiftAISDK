import Foundation

private struct MediaTypeSignature: Sendable {
    var mediaType: String
    var bytesPrefix: [UInt8?]
}

private let imageMediaTypeSignatures: [MediaTypeSignature] = [
    MediaTypeSignature(mediaType: "image/gif", bytesPrefix: [0x47, 0x49, 0x46]),
    MediaTypeSignature(mediaType: "image/png", bytesPrefix: [0x89, 0x50, 0x4E, 0x47]),
    MediaTypeSignature(mediaType: "image/jpeg", bytesPrefix: [0xFF, 0xD8]),
    MediaTypeSignature(mediaType: "image/webp", bytesPrefix: [0x52, 0x49, 0x46, 0x46, nil, nil, nil, nil, 0x57, 0x45, 0x42, 0x50]),
    MediaTypeSignature(mediaType: "image/bmp", bytesPrefix: [0x42, 0x4D]),
    MediaTypeSignature(mediaType: "image/tiff", bytesPrefix: [0x49, 0x49, 0x2A, 0x00]),
    MediaTypeSignature(mediaType: "image/tiff", bytesPrefix: [0x4D, 0x4D, 0x00, 0x2A]),
    MediaTypeSignature(mediaType: "image/avif", bytesPrefix: [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66]),
    MediaTypeSignature(mediaType: "image/heic", bytesPrefix: [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63])
]

private let documentMediaTypeSignatures: [MediaTypeSignature] = [
    MediaTypeSignature(mediaType: "application/pdf", bytesPrefix: [0x25, 0x50, 0x44, 0x46])
]

private let audioMediaTypeSignatures: [MediaTypeSignature] = [
    MediaTypeSignature(mediaType: "audio/mpeg", bytesPrefix: [0xFF, 0xFB]),
    MediaTypeSignature(mediaType: "audio/mpeg", bytesPrefix: [0xFF, 0xFA]),
    MediaTypeSignature(mediaType: "audio/mpeg", bytesPrefix: [0xFF, 0xF3]),
    MediaTypeSignature(mediaType: "audio/mpeg", bytesPrefix: [0xFF, 0xF2]),
    MediaTypeSignature(mediaType: "audio/mpeg", bytesPrefix: [0xFF, 0xE3]),
    MediaTypeSignature(mediaType: "audio/mpeg", bytesPrefix: [0xFF, 0xE2]),
    MediaTypeSignature(mediaType: "audio/wav", bytesPrefix: [0x52, 0x49, 0x46, 0x46, nil, nil, nil, nil, 0x57, 0x41, 0x56, 0x45]),
    MediaTypeSignature(mediaType: "audio/ogg", bytesPrefix: [0x4F, 0x67, 0x67, 0x53]),
    MediaTypeSignature(mediaType: "audio/flac", bytesPrefix: [0x66, 0x4C, 0x61, 0x43]),
    MediaTypeSignature(mediaType: "audio/aac", bytesPrefix: [0x40, 0x15, 0x00, 0x00]),
    MediaTypeSignature(mediaType: "audio/mp4", bytesPrefix: [0x66, 0x74, 0x79, 0x70]),
    MediaTypeSignature(mediaType: "audio/webm", bytesPrefix: [0x1A, 0x45, 0xDF, 0xA3])
]

private let videoMediaTypeSignatures: [MediaTypeSignature] = [
    MediaTypeSignature(mediaType: "video/mp4", bytesPrefix: [0x00, 0x00, 0x00, nil, 0x66, 0x74, 0x79, 0x70]),
    MediaTypeSignature(mediaType: "video/webm", bytesPrefix: [0x1A, 0x45, 0xDF, 0xA3]),
    MediaTypeSignature(mediaType: "video/quicktime", bytesPrefix: [0x00, 0x00, 0x00, 0x14, 0x66, 0x74, 0x79, 0x70, 0x71, 0x74]),
    MediaTypeSignature(mediaType: "video/x-msvideo", bytesPrefix: [0x52, 0x49, 0x46, 0x46])
]

public func detectMediaType(data: Data, topLevelType: String? = nil) -> String? {
    detectMediaType(bytes: Array(stripID3TagsIfPresent(data)), topLevelType: topLevelType)
}

public func detectMediaType(base64: String, topLevelType: String? = nil) -> String? {
    let prefix = String(stripID3TagsIfPresent(base64).prefix(24))
    guard let data = Data(base64Encoded: prefix) else {
        return nil
    }
    return detectMediaType(bytes: Array(data), topLevelType: topLevelType)
}

public func topLevelMediaType(_ mediaType: String) -> String {
    guard let slashIndex = mediaType.firstIndex(of: "/") else {
        return mediaType
    }
    return String(mediaType[..<slashIndex])
}

public func isFullMediaType(_ mediaType: String) -> Bool {
    guard let slashIndex = mediaType.firstIndex(of: "/") else {
        return false
    }
    let subtype = mediaType[mediaType.index(after: slashIndex)...]
    return !subtype.isEmpty && subtype != "*"
}

public func mediaTypeToExtension(_ mediaType: String) -> String {
    let subtype = mediaType.lowercased().split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first.map(String.init) ?? ""
    switch subtype {
    case "mpeg": return "mp3"
    case "x-wav": return "wav"
    case "opus": return "ogg"
    case "mp4", "x-m4a": return "m4a"
    default: return subtype
    }
}

public func resolveFullMediaType(mediaType: String, data: Data) throws -> String {
    if isFullMediaType(mediaType) {
        return mediaType
    }
    if let detected = detectMediaType(data: data, topLevelType: topLevelMediaType(mediaType)) {
        return detected
    }
    throw AIError.invalidArgument(
        argument: "mediaType",
        message: "File of media type \"\(mediaType)\" must specify subtype since it could not be auto-detected."
    )
}

private func detectMediaType(bytes: [UInt8], topLevelType: String?) -> String? {
    let signatures: [MediaTypeSignature]
    switch topLevelType {
    case nil:
        signatures = imageMediaTypeSignatures + documentMediaTypeSignatures + audioMediaTypeSignatures + videoMediaTypeSignatures
    case "image":
        signatures = imageMediaTypeSignatures
    case "audio":
        signatures = audioMediaTypeSignatures
    case "video":
        signatures = videoMediaTypeSignatures
    case "application":
        signatures = documentMediaTypeSignatures
    default:
        signatures = []
    }

    return signatures.first { signature in
        bytes.count >= signature.bytesPrefix.count
            && signature.bytesPrefix.enumerated().allSatisfy { index, byte in
                byte == nil || bytes[index] == byte
            }
    }?.mediaType
}

private func stripID3TagsIfPresent(_ data: Data) -> Data {
    guard data.count > 10,
          data[data.startIndex] == 0x49,
          data[data.index(after: data.startIndex)] == 0x44,
          data[data.index(data.startIndex, offsetBy: 2)] == 0x33 else {
        return data
    }
    let bytes = Array(data)
    let id3Size = (Int(bytes[6] & 0x7F) << 21)
        | (Int(bytes[7] & 0x7F) << 14)
        | (Int(bytes[8] & 0x7F) << 7)
        | Int(bytes[9] & 0x7F)
    return data.dropFirst(min(data.count, id3Size + 10))
}

private func stripID3TagsIfPresent(_ base64: String) -> String {
    guard base64.hasPrefix("SUQz"),
          let data = Data(base64Encoded: base64) else {
        return base64
    }
    return stripID3TagsIfPresent(data).base64EncodedString()
}
