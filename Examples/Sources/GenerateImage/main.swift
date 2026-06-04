import SwiftAISDK

@main
struct GenerateImageExample {
    static func main() async throws {
        let provider = try AIProviders.openAI()
        let model = try provider.imageModel("gpt-image-1")

        let result = try await model.generateImage(
            "A small watercolor robot reading Swift code.",
            size: "1024x1024",
            count: 1
        )

        print(result.urls.first ?? result.base64Images.first ?? "")
    }
}
