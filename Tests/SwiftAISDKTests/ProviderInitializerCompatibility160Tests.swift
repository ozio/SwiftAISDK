import Foundation
import Testing
@testable import SwiftAISDK

@Suite("ProviderInitializerCompatibility160")
struct ProviderInitializerCompatibility160Tests {
    @Test func googleVertexLegacyInitializerForwardsNewDownloadDefault() {
        let transport = RecordingTransport(response: jsonResponse("{}"))
        let date = Date(timeIntervalSince1970: 1_725_000_000)
        let serviceAccount = GoogleServiceAccountCredentials(
            clientEmail: "service@example.com",
            privateKey: "private-key",
            privateKeyID: "key-id"
        )

        let settings = GoogleVertexProviderSettings(
            project: "project-id",
            location: "us-central1",
            apiKey: "api-key",
            accessToken: "access-token",
            serviceAccount: serviceAccount,
            baseURL: "https://vertex.example.com",
            headers: ["x-test": "legacy"],
            transport: transport,
            date: { date }
        )

        #expect(settings.project == "project-id")
        #expect(settings.location == "us-central1")
        #expect(settings.apiKey == "api-key")
        #expect(settings.accessToken == "access-token")
        #expect(settings.serviceAccount?.clientEmail == "service@example.com")
        #expect(settings.baseURL == "https://vertex.example.com")
        #expect(settings.toolResultDownloads == nil)
        #expect(settings.headers == ["x-test": "legacy"])
        #expect(settings.date() == date)
    }

    @Test func openAICompatibleLegacyInitializerForwardsBatchDefault() throws {
        let provider = try OpenAICompatibleProvider(
            providerID: "compat",
            defaultBaseURL: "https://api.example.com/v1",
            authorization: .none,
            supportedCapabilities: [.language],
            settings: ProviderSettings(
                transport: RecordingTransport(response: jsonResponse("{}"))
            ),
            routesLikeOpenAI: false,
            userAgentSuffix: "compat/1.0",
            usesOpenAICompatibleSurfaceIDs: true
        )

        #expect(provider.providerID == "compat")
        #expect(provider.supportedCapabilities == [.language])
        #expect(try provider.chatModel("model").providerID == "compat.chat")
        #expect(throws: AIError.invalidArgument(
            argument: "providerID",
            message: "Provider-owned batches are supported only by OpenAI and xAI providers."
        )) {
            try provider.experimentalBatch()
        }
    }
}
