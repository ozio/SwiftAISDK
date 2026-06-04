import SwiftAISDK

struct Summary: Decodable, Sendable {
    var title: String
    var bullets: [String]
}

@main
struct StructuredOutputExample {
    static func main() async throws {
        let schema = AIJSONSchema<Summary>(
            [
                "type": "object",
                "properties": [
                    "title": ["type": "string"],
                    "bullets": [
                        "type": "array",
                        "items": ["type": "string"],
                    ],
                ],
                "required": ["title", "bullets"],
            ],
            name: "summary"
        )

        let provider = try AIProviders.openAI()
        let model = try provider.languageModel("gpt-4.1-mini")

        let result = try await AI.generateObject(
            model: model,
            prompt: "Summarize the SwiftAISDK README.",
            schema: schema
        )

        print(result.object.title)
    }
}
