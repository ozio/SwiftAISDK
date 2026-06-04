import SwiftAISDK

struct ConsoleTelemetry: Telemetry.Integration {
    func record(_ event: Telemetry.Event) async {
        print("\(event.kind.rawValue) \(event.operationID) \(event.providerID)")
    }
}

@main
struct TelemetryExample {
    static func main() async throws {
        let provider = try AIProviders.openAI()
        let model = try provider.languageModel("gpt-4.1-mini")

        let result = try await model.generateText(
            "Summarize this release note.",
            options: LanguageGenerationOptions(
                telemetry: Telemetry.Options(
                    functionID: "release.summary",
                    metadata: [
                        "tenant": .string("acme"),
                        "source": .string("docs"),
                    ],
                    integrations: [ConsoleTelemetry()]
                )
            )
        )

        print(result.text)
    }
}
