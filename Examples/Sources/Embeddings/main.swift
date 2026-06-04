import SwiftAISDK

@main
struct EmbeddingsExample {
    static func main() async throws {
        let provider = try AIProviders.openAI()
        let model = try provider.embeddingModel("text-embedding-3-small")

        let result = try await model.embed(
            "Swift makes API boundaries explicit.",
            dimensions: 512
        )

        print(result.embeddings.first ?? [])
    }
}
