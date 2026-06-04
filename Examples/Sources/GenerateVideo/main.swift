import SwiftAISDK

@main
struct GenerateVideoExample {
    static func main() async throws {
        let provider = try AIProviders.google()
        let model = try provider.videoModel("veo-3.1-generate-preview")

        let result = try await model.generateVideo(
            "A tiny robot walks across a desk and waves.",
            aspectRatio: "16:9",
            durationSeconds: 4
        )

        print(result.urls.first ?? result.base64Videos.first ?? "")
    }
}
