import Foundation
import Testing
@testable import SwiftAISDK

@Test func detectMediaTypeMatchesProviderUtilsSignatures() throws {
    let gif = Data([0x47, 0x49, 0x46, 0xFF, 0xFF])
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xFF])
    let webp = Data([0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50])
    let bmp = Data([0x42, 0x4D, 0xFF, 0xFF])
    let tiffLittleEndian = Data([0x49, 0x49, 0x2A, 0x00, 0xFF])
    let tiffBigEndian = Data([0x4D, 0x4D, 0x00, 0x2A, 0xFF])
    let avif = Data([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66, 0xFF])
    let heic = Data([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63, 0xFF])
    let mp3 = Data([0xFF, 0xFB])
    let wav = Data([0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45])
    let ogg = Data([0x4F, 0x67, 0x67, 0x53])
    let flac = Data([0x66, 0x4C, 0x61, 0x43])
    let aac = Data([0x40, 0x15, 0x00, 0x00])
    let audioWebm = Data([0x1A, 0x45, 0xDF, 0xA3])
    let videoMp4 = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70])
    let quicktime = Data([0x00, 0x00, 0x00, 0x14, 0x66, 0x74, 0x79, 0x70, 0x71, 0x74])
    let pdf = Data([0x25, 0x50, 0x44, 0x46, 0x2D])

    #expect(detectMediaType(data: gif, topLevelType: "image") == "image/gif")
    #expect(detectMediaType(base64: gif.base64EncodedString(), topLevelType: "image") == "image/gif")
    #expect(detectMediaType(data: png, topLevelType: "image") == "image/png")
    #expect(detectMediaType(base64: png.base64EncodedString(), topLevelType: "image") == "image/png")
    #expect(detectMediaType(data: jpeg, topLevelType: "image") == "image/jpeg")
    #expect(detectMediaType(data: webp, topLevelType: "image") == "image/webp")
    #expect(detectMediaType(data: bmp, topLevelType: "image") == "image/bmp")
    #expect(detectMediaType(data: tiffLittleEndian, topLevelType: "image") == "image/tiff")
    #expect(detectMediaType(data: tiffBigEndian, topLevelType: "image") == "image/tiff")
    #expect(detectMediaType(data: avif, topLevelType: "image") == "image/avif")
    #expect(detectMediaType(data: heic, topLevelType: "image") == "image/heic")
    #expect(detectMediaType(data: wav, topLevelType: "image") == nil)
    #expect(detectMediaType(data: mp3, topLevelType: "audio") == "audio/mpeg")
    #expect(detectMediaType(data: wav, topLevelType: "audio") == "audio/wav")
    #expect(detectMediaType(base64: wav.base64EncodedString(), topLevelType: "audio") == "audio/wav")
    #expect(detectMediaType(data: webp, topLevelType: "audio") == nil)
    #expect(detectMediaType(data: ogg, topLevelType: "audio") == "audio/ogg")
    #expect(detectMediaType(data: flac, topLevelType: "audio") == "audio/flac")
    #expect(detectMediaType(data: aac, topLevelType: "audio") == "audio/aac")
    #expect(detectMediaType(data: audioWebm, topLevelType: "audio") == "audio/webm")
    #expect(detectMediaType(data: videoMp4, topLevelType: "video") == "video/mp4")
    #expect(detectMediaType(data: audioWebm, topLevelType: "video") == "video/webm")
    #expect(detectMediaType(data: quicktime, topLevelType: "video") == "video/mp4")
    #expect(detectMediaType(data: webp, topLevelType: "video") == "video/x-msvideo")
    #expect(detectMediaType(data: pdf, topLevelType: "application") == "application/pdf")
    #expect(detectMediaType(data: pdf) == "application/pdf")
    #expect(detectMediaType(data: Data([0x00, 0x01, 0x02]), topLevelType: "image") == nil)
    #expect(detectMediaType(data: png, topLevelType: "text") == nil)
}

@Test func detectMediaTypeStripsID3TagsLikeUpstream() throws {
    let mp3WithID3 = Data([
        0x49, 0x44, 0x33,
        0x03, 0x00,
        0x00,
        0x00, 0x00, 0x00, 0x0A,
        0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
        0xFF, 0xFB, 0x00, 0x00
    ])

    #expect(detectMediaType(data: mp3WithID3, topLevelType: "audio") == "audio/mpeg")
    #expect(detectMediaType(base64: mp3WithID3.base64EncodedString(), topLevelType: "audio") == "audio/mpeg")
}

@Test func mediaTypeHelpersMatchProviderUtilsRules() throws {
    #expect(topLevelMediaType("image/png") == "image")
    #expect(topLevelMediaType("image/*") == "image")
    #expect(topLevelMediaType("image") == "image")
    #expect(topLevelMediaType("image/") == "image")
    #expect(topLevelMediaType("") == "")
    #expect(topLevelMediaType("/") == "")
    #expect(isFullMediaType("image/png"))
    #expect(!isFullMediaType("image/*"))
    #expect(!isFullMediaType("image"))
    #expect(!isFullMediaType("image/"))
    #expect(!isFullMediaType(""))
    #expect(!isFullMediaType("/"))

    #expect(mediaTypeToExtension("audio/mpeg") == "mp3")
    #expect(mediaTypeToExtension("audio/mp3") == "mp3")
    #expect(mediaTypeToExtension("audio/wav") == "wav")
    #expect(mediaTypeToExtension("audio/x-wav") == "wav")
    #expect(mediaTypeToExtension("audio/webm") == "webm")
    #expect(mediaTypeToExtension("audio/opus") == "ogg")
    #expect(mediaTypeToExtension("audio/mp4") == "m4a")
    #expect(mediaTypeToExtension("audio/x-m4a") == "m4a")
    #expect(mediaTypeToExtension("audio/flac") == "flac")
    #expect(mediaTypeToExtension("audio/aac") == "aac")
    #expect(mediaTypeToExtension("AUDIO/MPEG") == "mp3")
    #expect(mediaTypeToExtension("AUDIO/MP3") == "mp3")
    #expect(mediaTypeToExtension("nope") == "")
}

@Test func resolveFullMediaTypeDetectsSubtypeForInlineBytes() throws {
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])

    #expect(try resolveFullMediaType(mediaType: "image/jpeg", data: png) == "image/jpeg")
    #expect(try resolveFullMediaType(mediaType: "image", data: png) == "image/png")
    #expect(try resolveFullMediaType(mediaType: "image/*", data: png) == "image/png")
    #expect(try resolveFullMediaType(mediaType: "application", data: Data([0x25, 0x50, 0x44, 0x46])) == "application/pdf")
    #expect(throws: AIError.self) {
        _ = try resolveFullMediaType(mediaType: "image", data: Data([0x00, 0x01, 0x02]))
    }
    #expect(throws: AIError.self) {
        _ = try resolveFullMediaType(mediaType: "text", data: Data("hello".utf8))
    }
}
