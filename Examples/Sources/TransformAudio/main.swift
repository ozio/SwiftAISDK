import Foundation
import SwiftAISDK

@main
struct TransformAudioExample {
    static func main() async {
        do {
            let provider = try AIProviders.elevenLabs()
            let speech = try provider.speechModel("eleven_multilingual_v2")
            let source = try await AI.generateSpeech(
                "Swift AI voice tools smoke test. This source clip is long enough for isolation.",
                using: speech,
                voice: "21m00Tcm4TlvDq8ikWAM",
                format: "mp3_32",
                providerOptions: ["elevenlabs": ["languageCode": "en"]]
            )

            let changer = try provider.voiceChangerModel()
            let changed = try await AI.transformAudio(
                audio: source.audio,
                using: changer,
                fileName: "voice.mp3",
                mimeType: source.contentType ?? "audio/mpeg",
                voice: "21m00Tcm4TlvDq8ikWAM",
                format: "mp3_32"
            )
            print("Changed voice bytes: \(changed.audio.count)")

            let isolator = try provider.voiceIsolatorModel()
            let isolated = try await AI.transformAudio(
                audio: source.audio,
                using: isolator,
                fileName: "voice.mp3",
                mimeType: source.contentType ?? "audio/mpeg",
                providerOptions: ["elevenlabs": ["fileFormat": "other"]]
            )
            print("Isolated voice bytes: \(isolated.audio.count)")
        } catch {
            print("Audio transformation failed: \(error)")
        }
    }
}
