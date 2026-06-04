import SwiftAISDK

@main
struct ToolsExample {
    static func main() async throws {
        let weather = AITool(
            name: "weather",
            description: "Get the current weather in a city.",
            parameters: [
                "type": "object",
                "properties": [
                    "city": ["type": "string"],
                ],
                "required": ["city"],
            ]
        ) { arguments in
            let city = arguments["city"]?.stringValue ?? "unknown"
            return [
                "city": .string(city),
                "forecast": "sunny",
                "temperatureCelsius": 24,
            ]
        }

        let provider = try AIProviders.openAI()
        let model = try provider.languageModel("gpt-4.1-mini")

        let answer = try await model.generateText(
            "What should I wear in Tokyo today?",
            tools: LanguageToolOptions([weather], maxSteps: 3)
        )

        print(answer.text)
    }
}
