import Foundation
import SwiftAISDK

@main
struct GenerateSpeechExample {
    static func main() async throws {
        let provider = try AIProviders.openAI()
        let model = try provider.speechModel("gpt-4o-mini-tts")

        let result = try await model.generateSpeech(
            "Welcome to the SwiftAISDK demo.",
            voice: "alloy",
            format: "mp3",
            speed: 1.0
        )

        try result.audio.write(to: URL(fileURLWithPath: "welcome.mp3"))
    }
}
