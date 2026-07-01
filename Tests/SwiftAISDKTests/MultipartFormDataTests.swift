import Foundation
import Testing
@testable import SwiftAISDK

@Test func convertToMultipartFormDataAddsStringValues() {
    let body = multipartBodyText(convertToMultipartFormData([
        "model": .string("gpt-image-1"),
        "prompt": .string("A cute cat")
    ]))

    #expect(body.contains(#"name="model""#))
    #expect(body.contains("\r\n\r\ngpt-image-1\r\n"))
    #expect(body.contains(#"name="prompt""#))
    #expect(body.contains("\r\n\r\nA cute cat\r\n"))
}

@Test func convertToMultipartFormDataAddsNumberValuesAsStrings() {
    let body = multipartBodyText(convertToMultipartFormData([
        "n": .number(2),
        "seed": .number(42)
    ]))

    #expect(body.contains(#"name="n""#))
    #expect(body.contains("\r\n\r\n2\r\n"))
    #expect(body.contains(#"name="seed""#))
    #expect(body.contains("\r\n\r\n42\r\n"))
}

@Test func convertToMultipartFormDataAddsFileValues() {
    let body = multipartBodyText(convertToMultipartFormData([
        "image": .file(MultipartFormDataFile(fileName: "blob", mimeType: "image/png", data: Data("test".utf8)))
    ]))

    #expect(body.contains(#"name="image"; filename="blob""#))
    #expect(body.contains("Content-Type: image/png"))
    #expect(body.contains("\r\n\r\ntest\r\n"))
}

@Test func convertToMultipartFormDataSkipsNullAndNilValues() {
    let body = multipartBodyText(convertToMultipartFormData([
        "model": .string("gpt-image-1"),
        "mask": .null,
        "size": nil
    ]))

    #expect(body.contains(#"name="model""#))
    #expect(!body.contains(#"name="mask""#))
    #expect(!body.contains(#"name="size""#))
}

@Test func convertToMultipartFormDataAddsSingleElementArraysWithoutBracketSuffix() {
    let body = multipartBodyText(convertToMultipartFormData([
        "image": .array([
            .file(MultipartFormDataFile(fileName: "image.png", mimeType: "image/png", data: Data("test".utf8)))
        ])
    ]))

    #expect(body.contains(#"name="image"; filename="image.png""#))
    #expect(!body.contains(#"name="image[]""#))
}

@Test func convertToMultipartFormDataAddsMultiElementArraysWithBracketSuffix() {
    let body = multipartBodyText(convertToMultipartFormData([
        "image": .array([
            .file(MultipartFormDataFile(fileName: "one.png", mimeType: "image/png", data: Data("test1".utf8))),
            .file(MultipartFormDataFile(fileName: "two.jpg", mimeType: "image/jpeg", data: Data("test2".utf8)))
        ])
    ]))

    #expect(!body.contains(#"name="image";"#))
    #expect(multipartPartCount(named: "image[]", in: body) == 2)
    #expect(body.contains(#"filename="one.png""#))
    #expect(body.contains(#"filename="two.jpg""#))
}

@Test func convertToMultipartFormDataCanDisableArrayBracketSuffix() {
    let body = multipartBodyText(convertToMultipartFormData(
        [
            "image": .array([
                .file(MultipartFormDataFile(fileName: "one.png", mimeType: "image/png", data: Data("test1".utf8))),
                .file(MultipartFormDataFile(fileName: "two.jpg", mimeType: "image/jpeg", data: Data("test2".utf8)))
            ])
        ],
        useArrayBrackets: false
    ))

    #expect(!body.contains(#"name="image[]""#))
    #expect(multipartPartCount(named: "image", in: body) == 2)
}

@Test func convertToMultipartFormDataSkipsEmptyArrays() {
    let body = multipartBodyText(convertToMultipartFormData([
        "model": .string("test"),
        "images": .array([])
    ]))

    #expect(body.contains(#"name="model""#))
    #expect(!body.contains(#"name="images""#))
    #expect(!body.contains(#"name="images[]""#))
}

@Test func convertToMultipartFormDataAddsStringArraysWithBracketSuffix() {
    let body = multipartBodyText(convertToMultipartFormData([
        "tags": .array([.string("cat"), .string("cute"), .string("animal")])
    ]))

    #expect(multipartPartCount(named: "tags[]", in: body) == 3)
    #expect(body.contains("\r\n\r\ncat\r\n"))
    #expect(body.contains("\r\n\r\ncute\r\n"))
    #expect(body.contains("\r\n\r\nanimal\r\n"))
}

@Test func convertToMultipartFormDataHandlesMixedValues() {
    let body = multipartBodyText(convertToMultipartFormData([
        "model": .string("gpt-image-1"),
        "prompt": .string("Edit this image"),
        "image": .array([
            .file(MultipartFormDataFile(fileName: "blob", mimeType: "image/png", data: Data("image data".utf8)))
        ]),
        "mask": .null,
        "n": .number(1),
        "size": .string("1024x1024"),
        "quality": .string("high")
    ]))

    #expect(body.contains(#"name="model""#))
    #expect(body.contains(#"name="prompt""#))
    #expect(body.contains(#"name="image"; filename="blob""#))
    #expect(!body.contains(#"name="mask""#))
    #expect(body.contains(#"name="n""#))
    #expect(body.contains(#"name="size""#))
    #expect(body.contains(#"name="quality""#))
}

private func multipartBodyText(_ form: MultipartFormData) -> String {
    var form = form
    return String(data: form.finalize(), encoding: .utf8) ?? ""
}

private func multipartPartCount(named name: String, in body: String) -> Int {
    body.components(separatedBy: #"name="\#(name)""#).count - 1
}
