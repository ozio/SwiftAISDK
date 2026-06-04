import SwiftAISDK

@main
struct ErrorHandlingExample {
    static func main() async throws {
        let provider = try AIProviders.openAI()
        let model = try provider.languageModel("gpt-4.1-mini")

        do {
            let result = try await model.generateText(
                "Summarize this document.",
                options: LanguageGenerationOptions(
                    retryPolicy: AIRetryPolicy(maxRetries: 1)
                )
            )
            print(result.text)
        } catch let error as AIAbortError {
            print("Cancelled: \(error.reason ?? "no reason")")
        } catch let error as AIError {
            switch error {
            case .missingAPIKey(let provider, let variables):
                print("\(provider) needs one of: \(variables.joined(separator: ", "))")
            case .unsupportedModel(let provider, let capability, let modelID):
                print("\(provider) cannot use \(modelID) for \(capability.rawValue)")
            case .invalidArgument(let argument, let message):
                print("Invalid \(argument): \(message)")
            case .apiCall(let apiError):
                print("\(apiError.provider) HTTP \(apiError.statusCode): \(apiError.responseBody)")
                print(apiError.responseHeaders)
            case .invalidResponse(let provider, let message):
                print("\(provider) returned an invalid response: \(message)")
            case .gateway(let gatewayError):
                print("Gateway \(gatewayError.statusCode): \(gatewayError.message)")
            case .invalidURL(let url):
                print("Invalid URL: \(url)")
            case .timeout(let durationNanoseconds):
                print("Timed out after \(durationNanoseconds) ns")
            }
        } catch {
            print("Unexpected error: \(error)")
        }
    }
}
