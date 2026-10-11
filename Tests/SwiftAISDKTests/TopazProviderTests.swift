import Foundation
import Testing
@testable import SwiftAISDK

/// Translated from the provider, image and video tests in @ai-sdk/topaz 3.0.0.
@Suite(.serialized)
struct TopazProviderTests {
    private let image = ImageInputFile(data: Data([1, 2, 3, 4]), mediaType: "image/png")
    private let video = ImageInputFile(data: Data([1, 2, 3, 4, 5, 6, 7, 8]), mediaType: "video/mp4")
    private let source: JSONValue = ["width": 1920, "height": 1080, "duration": 10, "frameRate": 30, "frameCount": 300]

    private func provider(_ transport: any AITransport, baseURL: String? = nil, headers: [String: String] = [:]) throws -> OpenAICompatibleProvider {
        try AIProviders.topaz(settings: ProviderSettings(apiKey: "test-key", baseURL: baseURL, headers: headers, transport: transport))
    }

    private func imageTransport(statuses: [String] = [#"{"status":"Completed","credits":2,"output_width":4000,"output_height":3000,"output_format":"png"}"#]) -> RecordingTransport {
        RecordingTransport(responses: [jsonResponse(#"{"process_id":"proc-123","source_id":"src-1","eta":5}"#)]
            + statuses.map { jsonResponse($0) }
            + [jsonResponse(#"{"download_url":"https://cdn.topazlabs.example.com/out.png"}"#),
               AIHTTPResponse(statusCode: 200, headers: ["x-download": "ready"], body: Data([0x89, 0x50, 0x4e, 0x47, 1, 2]))])
    }

    private func imageRequest(options: [String: JSONValue] = [:]) -> ImageGenerationRequest {
        ImageGenerationRequest(prompt: "", files: [image], providerOptions: ["topaz": .object(["pollIntervalMillis": 1].merging(options) { _, new in new })])
    }

    private func videoRequest(options: [String: JSONValue]? = nil) -> VideoGenerationRequest {
        VideoGenerationRequest(prompt: "", inputReferences: [video], providerOptions: ["topaz": .object(options ?? ["source": source])])
    }

    private func start(_ transport: any AITransport, request: VideoGenerationRequest? = nil, modelID: String = "starlight-precise-2.6") async throws -> VideoGenerationOperationStartResult {
        let model = try provider(transport).video(modelID)
        return try await AI.startVideo(model: model, request: request ?? videoRequest(), retryPolicy: .none)
    }

    private func videoTransport(_ created: String = #"{"requestId":"req-123","uploadUrls":["https://uploads.topazlabs.example.com/video"]}"#, uploadStatus: Int = 200) -> RecordingTransport {
        RecordingTransport(responses: [jsonResponse(created), AIHTTPResponse(statusCode: uploadStatus), AIHTTPResponse(statusCode: 204)])
    }

    @Test func factoriesAndCapabilities() async throws {
        let p = try provider(RecordingTransport(response: jsonResponse("{}")))
        #expect(p.providerID == "topaz")
        #expect(p.supportedCapabilities == [.image, .video])
        let image = try #require(try p.image("wonder-3.5") as? TopazImageModel)
        #expect(image.providerID == "topaz.image")
        #expect(image.modelID == "wonder-3.5")
        #expect(image.maxImagesPerCall == 1)
        #expect(await (image as any ImageModel).supportsFileInputs == true)
        #expect(await (image as any ImageModel).supportsMaskInputs == false)
        let video = try #require(try p.video("proteus") as? TopazVideoModel)
        #expect(video.providerID == "topaz.video")
        #expect(video.maxVideosPerCall == 1)
        #expect(!video.supportsUnaryVideoGeneration)
        #expect(!video.supportsVideoGenerationWebhooks)
        #expect(throws: AIError.unsupportedModel(provider: "topaz", capability: .language, modelID: "any")) { try p.languageModel("any") }
        #expect(throws: AIError.unsupportedModel(provider: "topaz", capability: .embedding, modelID: "any")) { try p.embeddingModel("any") }
    }

    @Test func environmentKeyAndMissingCredentials() async throws {
        #expect(throws: AIError.missingAPIKey(provider: "topaz", environmentVariables: ["TOPAZ_API_KEY"])) {
            try AIProviders.topaz(settings: ProviderSettings(environment: [:]))
        }
        let transport = RecordingTransport(response: jsonResponse(#"{"status":"processing"}"#))
        let p = try AIProviders.topaz(settings: ProviderSettings(environment: ["TOPAZ_API_KEY": "environment-key"], transport: transport))
        _ = try await AI.getVideoStatus(model: p.video("proteus"), operation: ["requestId": "env"], retryPolicy: .none)
        #expect(await transport.requests().first?.headers["x-api-key"] == "environment-key")
    }

    @Test func customBaseURLHeadersAndVersionedUserAgent() async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"status":"processing"}"#))
        let p = try provider(transport, baseURL: "https://proxy.example.com/topaz/", headers: ["X-Custom": "custom-value", "User-Agent": "App/1.0"])
        _ = try await AI.getVideoStatus(model: p.video("proteus"), operation: ["requestId": "req-1"], headers: ["X-Call": "call-value"], retryPolicy: .none)
        let request = try #require(await transport.requests().first)
        #expect(request.url.absoluteString == "https://proxy.example.com/topaz/video/req-1/status")
        #expect(request.headers["x-api-key"] == "test-key")
        #expect(request.headers["accept"] == "application/json")
        #expect(request.headers["x-custom"] == "custom-value")
        #expect(request.headers["x-call"] == "call-value")
        #expect(request.headers["user-agent"] == "App/1.0 ai-sdk-topaz/3.0.5")
    }

    @Test func customAndCallHeadersOverrideCaseInsensitively() async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"status":"processing"}"#))
        let p = try provider(transport, headers: ["X-API-Key": "configured-key", "Accept": "custom/type"])
        _ = try await AI.getVideoStatus(model: p.video("proteus"), operation: ["requestId": "req"], retryPolicy: .none)
        _ = try await AI.getVideoStatus(model: p.video("proteus"), operation: ["requestId": "req"], headers: ["X-API-Key": "call-key", "Accept": "call/type"], retryPolicy: .none)
        let requests = await transport.requests()
        #expect(requests[0].headers["x-api-key"] == "configured-key")
        #expect(requests[0].headers["accept"] == "custom/type")
        #expect(requests[1].headers["x-api-key"] == "call-key")
        #expect(requests[1].headers["accept"] == "call/type")
        #expect(requests[1].headers.keys.filter { $0.lowercased() == "x-api-key" }.count == 1)
    }

    @Test func imageFacadePreservesURLInputsAndProviderOptionPrecedence() async throws {
        let transport = imageTransport()
        var request = imageRequest(options: ["outputWidth": 1024])
        request.files = [ImageInputFile(url: "https://example.com/input.png")]
        request.extraBody = ["topaz": ["outputWidth": 512, "outputHeight": 768]]
        let result = try await AI.generateImage(model: provider(transport).image("wonder-3.5"), request: request, retryPolicy: .none)
        #expect(result.base64Images.count == 1)
        #expect(result.calls.count == 1)
        let body = String(decoding: try #require(await transport.requests().first?.body), as: UTF8.self)
        #expect(body.contains("name=\"source_url\""))
        #expect(body.contains("name=\"output_width\"\r\n\r\n1024"))
        #expect(body.contains("name=\"output_height\"\r\n\r\n768"))
    }

    @Test func imageDownloadRedirectWithholdsAllCustomCredentials() async throws {
        let transport = RecordingTransport(responses: [
            jsonResponse(#"{"process_id":"p"}"#), jsonResponse(#"{"status":"Completed"}"#),
            jsonResponse(#"{"download_url":"https://api.topazlabs.com/object"}"#),
            AIHTTPResponse(statusCode: 302, headers: ["location": "https://cdn.example.com/out.png"]),
            AIHTTPResponse(statusCode: 200, body: Data([1, 2]))
        ])
        var request = imageRequest()
        request.headers = ["X-Call-Secret": "call-secret"]
        _ = try await provider(transport, headers: ["X-Custom-Secret": "provider-secret"]).image("wonder-3.5").generateImage(request)
        let requests = await transport.requests()
        #expect(requests[3].headers["x-api-key"] == "test-key")
        #expect(requests[3].headers["x-call-secret"] == "call-secret")
        #expect(requests[4].headers.keys.allSatisfy { $0.lowercased() == "user-agent" })
        #expect(!requests[3].followRedirects && !requests[4].followRedirects)
    }

    @Test func inFlightImageStatusTimesOutAndCancelsBeforeItFinishes() async throws {
        let transport = TopazStalledStatusTransport()
        defer { transport.release() }
        do {
            _ = try await provider(transport).image("wonder-3.5").generateImage(imageRequest(options: ["pollTimeoutMillis": 1_000]))
            Issue.record("Expected timeout")
        } catch { #expect(String(describing: error).contains("did not finish within 1000ms")) }
        #expect(transport.signal?.isAborted == true)
        #expect(transport.signal?.reasonName == "TimeoutError")
        #expect(!transport.didFinish)
        #expect(transport.didCancel)
    }

    @Test func imageSubmitPollDownloadAndMetadata() async throws {
        let transport = imageTransport()
        let before = Date()
        let result = try await provider(transport).image("wonder-3.5").generateImage(imageRequest())
        #expect(result.base64Images == [Data([0x89, 0x50, 0x4e, 0x47, 1, 2]).base64EncodedString()])
        #expect(result.warnings.isEmpty)
        #expect(result.responseMetadata.modelID == "wonder-3.5")
        #expect(try #require(result.responseMetadata.timestamp) >= before)
        #expect(result.responseMetadata.headers["x-download"] == "ready")
        #expect(result.providerMetadata == ["topaz": ["images": [["processId": "proc-123", "credits": 2, "width": 4000, "height": 3000, "format": "png"]]]])
        let requests = await transport.requests()
        #expect(requests.map(\.method) == ["POST", "GET", "GET", "GET"])
        #expect(requests[0].url.path == "/image/v1/enhance-gen/async")
        let body = String(decoding: try #require(requests[0].body), as: UTF8.self)
        #expect(body.contains("\r\nWonder 3.5\r\n"))
        #expect(body.contains("filename=\"image.png\""))
        #expect(body.contains("Content-Type: image/png"))
        #expect(requests.prefix(3).allSatisfy { $0.headers["x-api-key"] == "test-key" })
        #expect(requests[3].headers["x-api-key"] == nil)
    }

    @Test func imageFieldsAndDimensionPrecedence() async throws {
        let transport = imageTransport()
        var request = imageRequest(options: [
            "outputWidth": 8000, "outputHeight": 6000, "outputFormat": "jpeg", "cropToFill": true,
            "webhookUrl": "https://example.com/hook", "enhancementStrength": "medium", "grain": true,
            "grainDensity": 0.25, "grainModel": "gaussian", "grainSize": 2, "grainStrength": 0.75,
            "inputWidth": 1000, "inputHeight": 800, "unknownOption": "ignored"
        ])
        request.size = "4000x3000"
        _ = try await provider(transport).image("wonder-3.5").generateImage(request)
        let body = String(decoding: try #require(await transport.requests().first?.body), as: UTF8.self)
        for (key, value) in ["output_width": "8000", "output_height": "6000", "output_format": "jpeg", "crop_to_fill": "true", "webhook_url": "https://example.com/hook", "enhancementStrength": "medium", "grain": "true", "grainDensity": "0.25", "grainModel": "gaussian", "grainSize": "2", "grainStrength": "0.75", "inputWidth": "1000", "inputHeight": "800"] {
            #expect(body.contains("name=\"\(key)\"\r\n\r\n\(value)\r\n"))
        }
        #expect(!body.contains("pollIntervalMillis"))
        #expect(!body.contains("unknownOption"))
    }

    @Test func imageURLInputSizeFallbackAndRawModelName() async throws {
        let transport = imageTransport()
        var request = imageRequest()
        request.files = [ImageInputFile(url: "https://example.com/input.png")]
        request.size = "4000x3000"
        _ = try await provider(transport).image("Future Wonder").generateImage(request)
        let requests = await transport.requests()
        #expect(requests.count == 4)
        let body = String(decoding: try #require(requests.first?.body), as: UTF8.self)
        #expect(body.contains("\r\nFuture Wonder\r\n"))
        #expect(body.contains("name=\"source_url\"\r\n\r\nhttps://example.com/input.png"))
        #expect(body.contains("name=\"output_width\"\r\n\r\n4000"))
        #expect(body.contains("name=\"output_height\"\r\n\r\n3000"))
        #expect(!body.contains("filename="))
    }

    @Test func imageWarningsPreserveUpstreamOrder() async throws {
        let transport = imageTransport()
        var request = imageRequest()
        request.prompt = "make it pretty"
        request.aspectRatio = "16:9"; request.seed = 42; request.count = 2
        request.mask = image; request.files.append(image)
        let result = try await provider(transport).image("wonder-3.5").generateImage(request)
        #expect(result.warnings.compactMap(\.feature) == ["prompt", "aspectRatio", "seed", "mask", "n", "files"])
    }

    @Test func imageUnknownAndNullStatusesKeepPollingAndNullMetadataIsOmitted() async throws {
        let transport = imageTransport(statuses: [#"{"status":"Pending"}"#, #"{"status":null}"#, #"{"status":"future-state"}"#, #"{"status":"Completed","credits":null}"#])
        let result = try await provider(transport).image("wonder-3.5").generateImage(imageRequest())
        #expect(await transport.requests().count == 7)
        #expect(result.providerMetadata == ["topaz": ["images": [["processId": "proc-123"]]]])
    }

    @Test(arguments: ["Failed", "Cancelled"])
    func imageTerminalFailureDoesNotCancelAgain(status: String) async throws {
        let transport = imageTransport(statuses: ["{\"status\":\"\(status)\"}"])
        do {
            _ = try await provider(transport).image("wonder-3.5").generateImage(imageRequest())
            Issue.record("Expected terminal failure")
        } catch { #expect(String(describing: error).contains("\(status.lowercased()) for process proc-123")) }
        #expect(await transport.requests().map(\.method) == ["POST", "GET"])
    }

    @Test func imageTimeoutCancelsAbandonedJob() async throws {
        let transport = RecordingTransport(responses: [jsonResponse(#"{"process_id":"proc-123"}"#), jsonResponse(#"{"status":"Processing"}"#), AIHTTPResponse(statusCode: 204)])
        do {
            _ = try await provider(transport).image("wonder-3.5").generateImage(imageRequest(options: ["pollTimeoutMillis": 1, "pollIntervalMillis": 100]))
            Issue.record("Expected timeout")
        } catch { #expect(String(describing: error).contains("did not finish within 1ms")) }
        let cancel = try #require(await transport.requests().last)
        #expect(cancel.method == "DELETE")
        #expect(cancel.url.path == "/image/v1/cancel/proc-123")
        #expect(cancel.headers["x-api-key"] == "test-key")
        #expect(cancel.abortSignal == nil)
    }

    @Test func imageCallerAbortCancelsWithoutAbortedSignal() async throws {
        let controller = AIAbortController()
        let transport = TopazAbortingTransport(controller: controller)
        var request = imageRequest()
        request.abortSignal = controller.signal
        await #expect(throws: (any Error).self) {
            try await provider(transport).image("wonder-3.5").generateImage(request)
        }
        let requests = await transport.requests
        #expect(requests.last?.method == "DELETE")
        #expect(requests.last?.abortSignal == nil)
    }

    @Test func missingImageInputRejectsBeforeRequest() async throws {
        let transport = RecordingTransport(response: jsonResponse("{}"))
        await #expect(throws: AIError.self) {
            try await provider(transport).image("wonder-3.5").generateImage(ImageGenerationRequest(prompt: ""))
        }
        #expect(await transport.requests().isEmpty)
    }

    @Test(arguments: ["missing-process", "missing-download", "bad-status-type", "bad-credits-type"])
    func malformedImageResponsesFail(stage: String) async throws {
        let responses: [AIHTTPResponse]
        switch stage {
        case "missing-process": responses = [jsonResponse("{}")]
        case "missing-download": responses = [jsonResponse(#"{"process_id":"p"}"#), jsonResponse(#"{"status":"Completed"}"#), jsonResponse("{}")]
        case "bad-status-type": responses = [jsonResponse(#"{"process_id":"p"}"#), jsonResponse(#"{"status":5}"#)]
        default: responses = [jsonResponse(#"{"process_id":"p"}"#), jsonResponse(#"{"status":"Completed","credits":"2"}"#)]
        }
        await #expect(throws: AIError.self) { try await provider(RecordingTransport(responses: responses)).image("wonder-3.5").generateImage(imageRequest()) }
    }

    @Test(arguments: [
        (#"{"detail":[{"msg":"model is required"}]}"#, "model is required"),
        (#"{"code":402,"message":"Insufficient credits"}"#, "Insufficient credits"),
        (#"{"detail":"frameCount must be positive"}"#, "frameCount must be positive"),
        (#"{"message":"Invalid input","errorCode":"INVALID_INPUT","errors":[{"msg":"frameCount is required"},{"msg":"resolution is required"}]}"#, "Invalid input (INVALID_INPUT): frameCount is required; resolution is required"),
        (#"{"message":"Not enough credits","errorCode":"INSUFFICIENT_CREDITS"}"#, "Not enough credits (INSUFFICIENT_CREDITS)"),
        (#"{"error":"fallback"}"#, "fallback")
    ])
    func structuredAPIErrorsRetainWireBodyAndDetails(body: String, message: String) async throws {
        let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 402, headers: ["x-request-id": "err-1"], body: Data(body.utf8)))
        do {
            _ = try await provider(transport).image("wonder-3.5").generateImage(imageRequest())
            Issue.record("Expected API failure")
        } catch AIError.apiCall(let error) {
            #expect(error.message == message)
            #expect(error.responseBody == body)
            #expect(error.statusCode == 402)
            #expect(error.responseHeaders["x-request-id"] == "err-1")
            #expect(!error.isRetryable)
        }
    }

    @Test func videoUploadsBytesAndReportsInitialEstimate() async throws {
        let transport = videoTransport(#"{"requestId":"req-123","uploadUrls":["https://uploads.topazlabs.example.com/video"],"estimates":{"cost":[12,15],"time":[60,90]}}"#)
        let result = try await start(transport)
        #expect(result.operation == ["requestId": "req-123", "outputContainer": "mp4"])
        #expect(result.warnings.isEmpty)
        #expect(result.providerMetadata == ["topaz": ["requestId": "req-123", "estimatedCredits": [12, 15]]])
        #expect(try decodeJSONBody(encodeJSONBody(result.operation)) == result.operation)
        let requests = await transport.requests()
        #expect(requests.map(\.method) == ["POST", "PUT"])
        #expect(requests[0].url.path == "/video/express")
        #expect(requests[0].headers["x-api-key"] == "test-key")
        #expect(requests[1].body == video.data)
        #expect(requests[1].headers["content-type"] == "video/mp4")
        #expect(requests[1].headers["user-agent"] == "ai-sdk-topaz/3.0.5")
        #expect(requests[1].headers["x-api-key"] == nil)
        #expect(!requests[1].followRedirects)
        let body = try decodeJSONBody(#require(requests[0].body))
        #expect(body["source"] == ["container": "mp4", "size": 8, "duration": 10, "frameCount": 300, "frameRate": 30, "resolution": ["width": 1920, "height": 1080]])
        #expect(body["output"] == ["resolution": ["width": 1920, "height": 1080], "frameRate": 30, "audioCodec": "AAC", "audioTransfer": "Copy", "container": "mp4"])
        #expect(body["filters"] == [["model": "slp-2.6"]])
    }

    @Test(arguments: [("proteus", "prob-4"), ("starlight-precise-2.6", "slp-2.6"), ("slp-2.5", "slp-2.5")])
    func videoModelAliases(model: String, wire: String) async throws {
        let transport = videoTransport()
        _ = try await start(transport, modelID: model)
        #expect(try decodeJSONBody(#require(await transport.requests().first?.body))["filters"]?[0]?["model"] == .string(wire))
    }

    @Test func videoDerivesFrameCountAndHonorsOutputOptionsAndFilterOverrides() async throws {
        let transport = videoTransport()
        var request = videoRequest(options: [
            "source": ["width": 1280, "height": 720, "duration": 4, "frameRate": 25],
            "output": ["width": 3840, "height": 2160, "frameRate": 60, "audioCodec": "PCM", "audioTransfer": "None", "container": "mov", "videoEncoder": "ProRes", "videoProfile": "422 HQ", "videoBitrate": "20m", "audioBitrate": "192k", "cropToFit": false],
            "sharpness": 3.5, "videoCodec": "prores", "watermark": false,
            "filter": ["sharpness": 1, "experimentalSetting": "on"],
            "additionalFilters": [["model": "apo-8", "fps": 60]]
        ])
        request.resolution = "2000x1000"; request.fps = 50
        _ = try await start(transport, request: request)
        let body = try decodeJSONBody(#require(await transport.requests().first?.body))
        #expect(body["source"]?["frameCount"] == 100)
        #expect(body["output"] == ["resolution": ["width": 3840, "height": 2160], "frameRate": 60, "audioCodec": "PCM", "audioTransfer": "None", "container": "mov", "videoEncoder": "ProRes", "videoProfile": "422 HQ", "videoBitrate": "20m", "audioBitrate": "192k", "cropToFit": false])
        #expect(body["filters"] == [["model": "slp-2.6", "sharpness": 1, "experimentalSetting": "on", "videoCodec": "prores", "watermark": false], ["model": "apo-8", "fps": 60]])
    }

    @Test func expressVideoNeedsOnlyOutputResolutionAndInfersURLContainer() async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"requestId":"req-123"}"#))
        var request = videoRequest(options: ["sharpness": 3, "output": ["audioTransfer": "None"]])
        request.inputReferences = [ImageInputFile(url: "https://media.example.com/input.QT?token=x")]
        request.resolution = "3840x2160"
        let result = try await start(transport, request: request)
        #expect(result.operation["outputContainer"] == "mov")
        #expect(await transport.requests().count == 1)
        let body = try decodeJSONBody(#require(await transport.requests().first?.body))
        #expect(body["source"] == ["container": "mov", "external": ["provider": "s3", "presignedUrl": "https://media.example.com/input.QT?token=x"]])
        #expect(body["output"] == ["resolution": ["width": 3840, "height": 2160], "audioTransfer": "None", "container": "mov"])
        #expect(body["filters"] == [["model": "slp-2.6", "sharpness": 3]])
    }

    @Test func expressBytesAndDeclaredContainerDoNotRequireSourceMetadata() async throws {
        let transport = videoTransport()
        var request = videoRequest(options: ["source": ["container": "mov"]])
        request.resolution = "1280x720"; request.fps = 60
        _ = try await start(transport, request: request)
        let requests = await transport.requests()
        let body = try decodeJSONBody(#require(requests.first?.body))
        #expect(body["source"] == ["container": "mov", "size": 8])
        #expect(body["output"]?["frameRate"] == 60)
        #expect(requests[1].headers["content-type"] == "video/quicktime")
    }

    @Test func videoWarningsAndFirstVideoSelection() async throws {
        let transport = videoTransport()
        var request = videoRequest()
        request.prompt = "sharpen"; request.aspectRatio = "16:9"; request.seed = 7
        request.durationSeconds = 5; request.generateAudio = true; request.count = 2
        request.frameImages = [VideoFrameImage(image: image, frameType: .firstFrame)]
        request.inputReferences = [image, video, video]
        let model = try #require(try provider(transport).video("proteus") as? TopazVideoModel)
        let result = try await model.startVideoGeneration(VideoGenerationOperationStartRequest(request: request))
        #expect(result.warnings.compactMap(\.feature) == ["prompt", "aspectRatio", "seed", "duration", "generateAudio", "frameImages", "n", "inputReferences"])
        #expect(await transport.requests()[1].body == video.data)
    }

    @Test(arguments: [("partial", "Source metadata must be complete. Missing: source.height, source.duration, source.frameRate."), ("no-video", "require an input video"), ("image-only", "not a still image"), ("container", "Could not map the media type"), ("resolution", "needs the output resolution")])
    func invalidVideoInputFailsBeforeNetwork(kind: String, expected: String) async throws {
        let transport = videoTransport()
        var request = videoRequest()
        switch kind {
        case "partial": request.providerOptions = ["topaz": ["source": ["width": 1920]]]
        case "no-video": request.inputReferences = []
        case "image-only": request.inputReferences = []; request.image = image
        case "container": request.inputReferences = [ImageInputFile(data: Data([1]), mediaType: "video/ogg")]
        default: request.providerOptions = [:]
        }
        do { _ = try await start(transport, request: request); Issue.record("Expected invalid input") }
        catch { #expect(String(describing: error).contains(expected)) }
        #expect(await transport.requests().isEmpty)
    }

    @Test(arguments: [("ProRes", "mov"), ("AV1", "mp4"), ("VP9", "mp4")])
    func encoderOverridesRequestedContainer(encoder: String, expected: String) async throws {
        let transport = videoTransport()
        let result = try await start(transport, request: videoRequest(options: ["source": source, "output": ["videoEncoder": .string(encoder), "container": "webm"]]))
        #expect(result.operation["outputContainer"] == .string(expected))
    }

    @Test(arguments: ["missing-url", "upload-error", "unsafe-url", "redirect"])
    func videoCleanupPreservesOriginalFailure(kind: String) async throws {
        let url = kind == "unsafe-url" ? "http://127.0.0.1/internal" : "https://uploads.topazlabs.example.com/video"
        let created = kind == "missing-url" ? #"{"requestId":"req-123"}"# : "{\"requestId\":\"req-123\",\"uploadUrls\":[\"\(url)\"]}"
        let transport = videoTransport(created, uploadStatus: kind == "redirect" ? 307 : 503)
        do { _ = try await start(transport); Issue.record("Expected start failure") }
        catch AIError.apiCall(let error) {
            #expect(["upload-error", "redirect"].contains(kind))
            #expect(error.statusCode == (kind == "redirect" ? 307 : 503))
            #expect(error.isRetryable == (kind != "redirect"))
        } catch { #expect(["missing-url", "unsafe-url"].contains(kind)) }
        let requests = await transport.requests()
        #expect(requests.last?.method == "DELETE")
        #expect(requests.last?.url.path == "/video/req-123")
        #expect(requests.last?.headers["x-api-key"] == "test-key")
        #expect(requests.last?.abortSignal == nil)
        #expect(!requests.contains { $0.url.host == "127.0.0.1" })
    }

    @Test func completedVideoReportsCheapestSettledCreditsAndMediaType() async throws {
        let transport = RecordingTransport(response: jsonResponse(#"{"status":"complete","progress":100,"outputSize":"12345","estimates":{"cost":[20,16],"time":[60,90]},"download":{"url":"https://cdn.example.com/out.mov","expiresAt":1767229200000}}"#, headers: ["x-status": "ready"]))
        let status = try await AI.getVideoStatus(model: provider(transport).video("proteus"), operation: ["requestId": "req-123", "outputContainer": "mov"], retryPolicy: .none)
        guard case .completed(let result) = status else { Issue.record("Expected completion"); return }
        #expect(result.urls == ["https://cdn.example.com/out.mov"])
        #expect(result.mediaType == "video/quicktime")
        #expect(result.responseMetadata.headers["x-status"] == "ready")
        #expect(result.providerMetadata == ["topaz": ["requestId": "req-123", "credits": 16, "estimatedCredits": [20, 16], "outputSize": "12345", "expiresAt": 1767229200000]])
    }

    @Test(arguments: ["requested", "accepted", "initializing", "preprocessing", "processing", "postprocessing", "canceling", "sideways"])
    func videoIntermediateAndUnknownStatesRemainPending(value: String) async throws {
        let transport = RecordingTransport(response: jsonResponse("{\"status\":\"\(value)\"}"))
        let status = try await AI.getVideoStatus(model: provider(transport).video("proteus"), operation: ["requestId": "req-123"], retryPolicy: .none)
        guard case .pending = status else { Issue.record("Expected pending"); return }
    }

    @Test(arguments: ["failed", "canceled"])
    func failedVideoStatusPreservesCode(value: String) async throws {
        let transport = RecordingTransport(response: jsonResponse("{\"status\":\"\(value)\",\"errorCode\":\"CREDIT_DIFFERENCE\",\"message\":\"Estimate changed after upload\"}"))
        let status = try await AI.getVideoStatus(model: provider(transport).video("proteus"), operation: ["requestId": "req-123"], retryPolicy: .none)
        guard case let .failed(message, metadata, _) = status else { Issue.record("Expected failure"); return }
        #expect(message == "Topaz video request req-123 \(value) (CREDIT_DIFFERENCE): Estimate changed after upload")
        #expect(metadata == ["topaz": ["requestId": "req-123", "errorCode": "CREDIT_DIFFERENCE"]])
    }

    @Test func videoFacadeAutomaticallyPollsAsyncOnlyModelAndMergesMetadata() async throws {
        let transport = RecordingTransport(responses: [jsonResponse(#"{"requestId":"req-facade","estimates":{"cost":[3,4]}}"#), jsonResponse(#"{"status":"processing"}"#), jsonResponse(#"{"status":"complete","download":{"url":"https://cdn.example.com/out.mp4"}}"#)])
        var request = videoRequest()
        request.inputReferences = [ImageInputFile(url: "https://example.com/input.mp4")]
        let result = try await AI.generateVideo(model: provider(transport).video("proteus"), request: request, retryPolicy: .none, poll: VideoGenerationPollOptions(intervalMilliseconds: 0))
        #expect(result.urls == ["https://cdn.example.com/out.mp4"])
        #expect(result.providerMetadata["topaz"]?["credits"] == nil)
        #expect(result.operationID == "req-facade")
        #expect(await transport.requests().map(\.method) == ["POST", "GET", "GET"])
    }

    @Test(arguments: [#"{"status":"complete"}"#, #"{"status":4}"#, #"{"estimates":{"cost":["1"]}}"#, #"{"download":{"url":4}}"#, #"{"outputSize":true}"#])
    func malformedVideoStatusFails(body: String) async throws {
        let transport = RecordingTransport(response: jsonResponse(body))
        await #expect(throws: AIError.self) { try await AI.getVideoStatus(model: provider(transport).video("proteus"), operation: ["requestId": "req"], retryPolicy: .none) }
    }

    @Test(arguments: [("grainDensity", JSONValue.number(1.1)), ("grainSize", .number(0)), ("enhancementStrength", .string("extreme")), ("outputWidth", .number(1.5)), ("outputHeight", .number(32001)), ("grain", .null), ("pollIntervalMillis", .number(0)), ("pollTimeoutMillis", .number(1e30))])
    func invalidImageOptionsFailBeforeSubmission(key: String, value: JSONValue) async throws {
        let transport = imageTransport()
        await #expect(throws: AIError.self) { try await provider(transport).image("wonder-3.5").generateImage(imageRequest(options: [key: value])) }
        #expect(await transport.requests().isEmpty)
    }

    @Test(arguments: [("sharpness", JSONValue.number(0)), ("compression", .number(2)), ("grain", .number(0.2)), ("videoBitDepth", .number(0)), ("videoType", .string("wrong")), ("source", .object(["width": -1])), ("output", .object(["audioCodec": "mp3"])), ("filter", .array([JSONValue]())), ("additionalFilters", .array([.string("invalid")]))])
    func invalidVideoOptionsFailBeforeSubmission(key: String, value: JSONValue) async throws {
        let transport = videoTransport()
        await #expect(throws: AIError.self) { try await start(transport, request: videoRequest(options: ["source": source].merging([key: value]) { _, new in new })) }
        #expect(await transport.requests().isEmpty)
    }
}

private actor TopazAbortingTransport: AITransport {
    let controller: AIAbortController
    var requests: [AIHTTPRequest] = []
    init(controller: AIAbortController) { self.controller = controller }
    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        requests.append(request)
        if request.method == "POST" { return jsonResponse(#"{"process_id":"proc-123"}"#) }
        if request.method == "GET" { controller.abort(reason: "caller stopped") }
        return jsonResponse(#"{"status":"Processing"}"#)
    }
}

private final class TopazStalledStatusTransport: AITransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private var capturedSignal: AIAbortSignal?
    private var finished = false
    private var cancelled = false
    var signal: AIAbortSignal? { lock.withLock { capturedSignal } }
    var didFinish: Bool { lock.withLock { finished } }
    var didCancel: Bool { lock.withLock { cancelled } }
    func release() {
        let pending = lock.withLock {
            released = true
            let pending = continuation
            continuation = nil
            return pending
        }
        pending?.resume()
    }
    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        if request.method == "POST" { return jsonResponse(#"{"process_id":"stalled"}"#) }
        if request.method == "DELETE" {
            lock.withLock { cancelled = true }
            return AIHTTPResponse(statusCode: 204)
        }
        lock.withLock { capturedSignal = request.abortSignal }
        await withCheckedContinuation { pending in
            let alreadyReleased = lock.withLock {
                if released { return true }
                continuation = pending
                return false
            }
            if alreadyReleased { pending.resume() }
            else { DispatchQueue.global().asyncAfter(deadline: .now() + 5) { self.release() } }
        }
        lock.withLock { finished = true }
        return jsonResponse(#"{"status":"Completed"}"#)
    }
}
