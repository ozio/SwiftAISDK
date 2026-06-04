import Foundation
import SwiftAISDK

@main
struct DubbingExample {
    static func main() async {
        do {
            let provider = try AIProviders.elevenLabs()
            let speech = try provider.speechModel("eleven_multilingual_v2")
            let source = try await AI.generateSpeech(
                "Hello from Swift AI.",
                using: speech,
                voice: "21m00Tcm4TlvDq8ikWAM",
                format: "mp3_32",
                providerOptions: ["elevenlabs": ["languageCode": "en"]]
            )

            let dubbing = try provider.dubbing()
            let created = try await dubbing.create(DubbingCreateRequest(
                file: source.audio,
                fileName: "source.mp3",
                mimeType: source.contentType ?? "audio/mpeg",
                name: "SwiftAISDK dubbing example",
                sourceLanguage: "en",
                targetLanguage: "es",
                numSpeakers: 1,
                watermark: true,
                extraBody: ["disableVoiceCloning": true]
            ))
            let status = try await dubbing.get(created.dubbingID)
            print("Dubbing \(created.dubbingID) status: \(status.status)")
        } catch {
            print("Dubbing failed: \(error)")
        }
    }
}
