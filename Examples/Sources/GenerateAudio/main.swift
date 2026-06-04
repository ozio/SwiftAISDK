import Foundation
import SwiftAISDK

@main
struct GenerateAudioExample {
    static func main() async {
        do {
            let provider = try AIProviders.elevenLabs()

            let soundEffects = try provider.soundEffectsModel()
            let click = try await AI.generateAudio(
                "A single soft interface click.",
                using: soundEffects,
                durationSeconds: 0.5,
                format: "mp3_32",
                providerOptions: ["elevenlabs": ["promptInfluence": 0.3]]
            )
            print("Generated sound effect bytes: \(click.audio.count)")

            let music = try provider.musicModel()
            let cue = try await AI.generateAudio(
                "Three seconds of quiet instrumental piano, no vocals.",
                using: music,
                durationSeconds: 3,
                format: "mp3_32",
                providerOptions: ["elevenlabs": ["forceInstrumental": true]]
            )
            print("Generated music bytes: \(cue.audio.count)")
        } catch {
            print("Audio generation failed: \(error)")
        }
    }
}
