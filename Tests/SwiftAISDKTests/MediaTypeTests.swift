import Foundation
import Testing
@testable import SwiftAISDK

@Test func detectMediaTypeMatchesProviderUtilsSignatures() throws {
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
    let webp = Data([0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50])
    let wav = Data([0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45])
    let pdf = Data([0x25, 0x50, 0x44, 0x46, 0x2D])

    #expect(detectMediaType(data: png, topLevelType: "image") == "image/png")
    #expect(detectMediaType(base64: png.base64EncodedString(), topLevelType: "image") == "image/png")
    #expect(detectMediaType(data: webp, topLevelType: "image") == "image/webp")
    #expect(detectMediaType(data: wav, topLevelType: "image") == nil)
    #expect(detectMediaType(data: wav, topLevelType: "audio") == "audio/wav")
    #expect(detectMediaType(data: pdf, topLevelType: "application") == "application/pdf")
    #expect(detectMediaType(data: pdf) == "application/pdf")
}

@Test func mediaTypeHelpersMatchProviderUtilsRules() throws {
    #expect(topLevelMediaType("image/png") == "image")
    #expect(topLevelMediaType("image/*") == "image")
    #expect(topLevelMediaType("image") == "image")
    #expect(isFullMediaType("image/png"))
    #expect(!isFullMediaType("image/*"))
    #expect(!isFullMediaType("image"))

    #expect(mediaTypeToExtension("audio/mpeg") == "mp3")
    #expect(mediaTypeToExtension("audio/x-wav") == "wav")
    #expect(mediaTypeToExtension("audio/opus") == "ogg")
    #expect(mediaTypeToExtension("audio/mp4") == "m4a")
    #expect(mediaTypeToExtension("nope") == "")
}

@Test func resolveFullMediaTypeDetectsSubtypeForInlineBytes() throws {
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])

    #expect(try resolveFullMediaType(mediaType: "image/jpeg", data: png) == "image/jpeg")
    #expect(try resolveFullMediaType(mediaType: "image", data: png) == "image/png")
    #expect(try resolveFullMediaType(mediaType: "image/*", data: png) == "image/png")
    #expect(throws: AIError.self) {
        _ = try resolveFullMediaType(mediaType: "image", data: Data([0x00, 0x01, 0x02]))
    }
}
