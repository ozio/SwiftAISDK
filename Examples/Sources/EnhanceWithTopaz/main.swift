import Foundation
import SwiftAISDK

@main
struct EnhanceWithTopazExample {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 3, ["image", "video"].contains(arguments[0]) else {
            print("Usage: EnhanceWithTopaz <image|video> <source-url> <WIDTHxHEIGHT>")
            return
        }
        let topaz = try AIProviders.topaz()
        if arguments[0] == "image" {
            let result = try await AI.generateImage(
                model: topaz.image("wonder-3.5"),
                request: ImageGenerationRequest(
                    prompt: "", size: arguments[2],
                    files: [ImageInputFile(url: arguments[1])],
                    providerOptions: ["topaz": ["enhancementStrength": "medium", "outputFormat": "png"]]
                )
            )
            print(result.urls.first ?? "No image URL returned")
            print(result.providerMetadata)
        } else {
            let result = try await AI.generateVideo(
                model: topaz.video("proteus"),
                request: VideoGenerationRequest(
                    prompt: "", inputReferences: [ImageInputFile(url: arguments[1])],
                    resolution: arguments[2], providerOptions: ["topaz": ["auto": "Auto"]]
                ),
                poll: VideoGenerationPollOptions(intervalMilliseconds: 5_000, timeoutMilliseconds: 600_000)
            )
            print(result.urls.first ?? "No video URL returned")
            print(result.providerMetadata)
        }
    }
}
