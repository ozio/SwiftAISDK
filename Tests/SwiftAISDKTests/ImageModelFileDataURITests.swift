import Foundation
import Testing
@testable import SwiftAISDK

@Test func convertImageModelFileToDataURIReturnsURLAsIsLikeUpstream() throws {
    #expect(try convertImageModelFileToDataURI(ImageInputFile(
        url: "https://example.com/image.png"
    )) == "https://example.com/image.png")

    #expect(try convertImageModelFileToDataURI(ImageInputFile(
        url: "https://example.com/image.png?width=100&height=200"
    )) == "https://example.com/image.png?width=100&height=200")
}

@Test func convertImageModelFileToDataURIConvertsDataToBase64LikeUpstream() throws {
    #expect(try convertImageModelFileToDataURI(ImageInputFile(
        data: Data("Hello".utf8),
        mediaType: "image/png"
    )) == "data:image/png;base64,SGVsbG8=")

    #expect(try convertImageModelFileToDataURI(ImageInputFile(
        data: Data(),
        mediaType: "image/png"
    )) == "data:image/png;base64,")

    #expect(try convertImageModelFileToDataURI(ImageInputFile(
        data: Data("Hello".utf8),
        mediaType: "image/webp"
    )) == "data:image/webp;base64,SGVsbG8=")
}
