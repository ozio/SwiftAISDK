import Foundation
import SwiftAISDK

@main
struct TranscribeAudioExample {
    static func main() async throws {
        let provider = try AIProviders.openAI()
        let model = try provider.transcriptionModel("gpt-4o-transcribe")
        let audio = try Data(contentsOf: URL(fileURLWithPath: "meeting.wav"))

        let result = try await model.transcribe(
            audio: audio,
            fileName: "meeting.wav",
            mimeType: "audio/wav",
            language: "en",
            prompt: "The speakers discuss Swift package design."
        )

        print(result.text)
    }
}
