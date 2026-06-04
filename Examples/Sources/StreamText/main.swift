import SwiftAISDK

@main
struct StreamTextExample {
    static func main() async throws {
        let provider = try AIProviders.openAI()
        let model = try provider.languageModel("gpt-4.1-mini")

        for try await part in model.streamText("Write a short haiku about APIs.") {
            switch part {
            case .textDelta(let text):
                print(text, terminator: "")
            case .finish(let reason, let usage):
                print("\nFinished: \(reason ?? "unknown")")
                print("Tokens: \(usage?.totalTokens ?? 0)")
            default:
                break
            }
        }
    }
}
