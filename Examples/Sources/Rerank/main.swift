import SwiftAISDK

@main
struct RerankExample {
    static func main() async throws {
        let provider = try AIProviders.cohere()
        let model = try provider.rerankingModel("rerank-v3.5")

        let result = try await model.rerank(
            query: "Which document explains provider options?",
            documents: [
                "Provider options carry provider-specific settings.",
                "Streaming text emits lifecycle parts.",
                "Embeddings convert strings into vectors.",
            ],
            topK: 2
        )

        for item in result.results {
            print("index: \(item.index), score: \(item.score)")
        }
    }
}
