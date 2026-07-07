import Foundation
import Testing
@testable import SwiftAISDK

@Test func deepgramForwardsAbortSignalToTranscriptionAndSpeechRequests() async throws {
    let transcriptionTransport = RecordingTransport(response: jsonResponse(#"{"results":{"channels":[{"alternatives":[{"transcript":"deepgram"}]}]}}"#))
    let transcriptionProvider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: transcriptionTransport))
    let transcriptionModel = try transcriptionProvider.transcriptionModel("nova-3")
    let transcriptionController = AIAbortController()

    _ = try await transcriptionModel.transcribe(AudioTranscriptionRequest(
        audio: Data("wav".utf8),
        mimeType: "audio/wav",
        abortSignal: transcriptionController.signal
    ))

    let transcriptionRequest = try #require(await transcriptionTransport.requests().first)
    #expect(transcriptionRequest.abortSignal === transcriptionController.signal)

    let speechTransport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("audio".utf8)))
    let speechProvider = try AIProviders.deepgram(settings: ProviderSettings(apiKey: "deepgram-key", transport: speechTransport))
    let speechModel = try speechProvider.speechModel("aura-2-helena-en")
    let speechController = AIAbortController()

    _ = try await speechModel.speak(SpeechRequest(text: "hello", abortSignal: speechController.signal))

    let speechRequest = try #require(await speechTransport.requests().first)
    #expect(speechRequest.abortSignal === speechController.signal)
}
@Test func elevenLabsForwardsAbortSignalToTranscriptionAndSpeechRequests() async throws {
    let transcriptionTransport = RecordingTransport(response: jsonResponse(#"{"language_code":"en","language_probability":0.99,"text":"eleven transcript","words":[]}"#))
    let transcriptionProvider = try AIProviders.elevenLabs(settings: ProviderSettings(apiKey: "eleven-key", transport: transcriptionTransport))
    let transcriptionModel = try transcriptionProvider.transcriptionModel("scribe_v1")
    let transcriptionController = AIAbortController()

    _ = try await transcriptionModel.transcribe(AudioTranscriptionRequest(
        audio: Data("mp3".utf8),
        fileName: "clip.mp3",
        mimeType: "audio/mpeg",
        abortSignal: transcriptionController.signal
    ))

    let transcriptionRequest = try #require(await transcriptionTransport.requests().first)
    #expect(transcriptionRequest.abortSignal === transcriptionController.signal)

    let speechTransport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("audio".utf8)))
    let speechProvider = try AIProviders.elevenLabs(settings: ProviderSettings(apiKey: "eleven-key", transport: speechTransport))
    let speechModel = try speechProvider.speechModel("eleven_multilingual_v2")
    let speechController = AIAbortController()

    _ = try await speechModel.speak(SpeechRequest(text: "hello", abortSignal: speechController.signal))

    let speechRequest = try #require(await speechTransport.requests().first)
    #expect(speechRequest.abortSignal === speechController.signal)
}
@Test func lmntForwardsAbortSignalToSpeechRequests() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("audio".utf8)))
    let provider = try AIProviders.lmnt(settings: ProviderSettings(apiKey: "lmnt-key", transport: transport))
    let model = try provider.speechModel("aurora")
    let controller = AIAbortController()

    _ = try await model.speak(SpeechRequest(text: "hello", abortSignal: controller.signal))

    let request = try #require(await transport.requests().first)
    #expect(request.abortSignal === controller.signal)
}
@Test func humeForwardsAbortSignalToSpeechRequests() async throws {
    let transport = RecordingTransport(response: AIHTTPResponse(statusCode: 200, headers: ["content-type": "audio/mpeg"], body: Data("audio".utf8)))
    let provider = try AIProviders.hume(settings: ProviderSettings(apiKey: "hume-key", transport: transport))
    let model = try provider.speechModel("")
    let controller = AIAbortController()

    _ = try await model.speak(SpeechRequest(text: "hello", abortSignal: controller.signal))

    let request = try #require(await transport.requests().first)
    #expect(request.abortSignal === controller.signal)
}
@Test func assemblyAIForwardsAbortSignalToUploadSubmitAndPollRequests() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"upload_url":"https://cdn.example.com/audio.wav"}"#),
        jsonResponse(#"{"id":"assembly-job","status":"queued"}"#),
        jsonResponse(#"{"id":"assembly-job","status":"completed","text":"assembly transcript"}"#)
    ])
    let provider = try AIProviders.assemblyAI(settings: ProviderSettings(apiKey: "assembly-key", transport: transport))
    let model = try provider.transcriptionModel("best")
    let controller = AIAbortController()

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("wav".utf8),
        mimeType: "audio/wav",
        abortSignal: controller.signal
    ))

    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].abortSignal === controller.signal)
    #expect(requests[1].abortSignal === controller.signal)
    #expect(requests[2].abortSignal === controller.signal)
}
@Test func revAIForwardsAbortSignalToSubmitPollAndTranscriptRequests() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"rev-job","status":"in_progress"}"#),
        jsonResponse(#"{"id":"rev-job","status":"transcribed","language":"en"}"#),
        jsonResponse(#"{"monologues":[{"elements":[{"type":"text","value":"rev","ts":0,"end_ts":0.3}]}]}"#)
    ])
    let provider = try AIProviders.revAI(settings: ProviderSettings(apiKey: "rev-key", transport: transport))
    let model = try provider.transcriptionModel("machine")
    let controller = AIAbortController()

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("wav".utf8),
        mimeType: "audio/wav",
        abortSignal: controller.signal
    ))

    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].abortSignal === controller.signal)
    #expect(requests[1].abortSignal === controller.signal)
    #expect(requests[2].abortSignal === controller.signal)
}
@Test func gladiaForwardsAbortSignalToUploadInitiateAndPollRequests() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"audio_url":"https://audio.example.com/file.wav"}"#),
        jsonResponse(#"{"result_url":"https://api.gladia.io/v2/pre-recorded/result/job-123"}"#),
        jsonResponse(#"{"status":"processing"}"#),
        jsonResponse(#"{"status":"done","result":{"metadata":{"audio_duration":0.3},"transcription":{"full_transcript":"gladia","languages":["en"],"utterances":[{"start":0,"end":0.3,"text":"gladia"}]}}}"#)
    ])
    let provider = try AIProviders.gladia(settings: ProviderSettings(apiKey: "gladia-key", transport: transport))
    let model = try provider.transcriptionModel("default")
    let controller = AIAbortController()

    _ = try await model.transcribe(AudioTranscriptionRequest(
        audio: Data("wav".utf8),
        mimeType: "audio/wav",
        abortSignal: controller.signal
    ))

    let requests = await transport.requests()
    #expect(requests.count == 4)
    #expect(requests[0].abortSignal === controller.signal)
    #expect(requests[1].abortSignal === controller.signal)
    #expect(requests[2].abortSignal === controller.signal)
    #expect(requests[3].abortSignal === controller.signal)
}
@Test func replicateImageForwardsAbortSignalToSubmitAndDownloadRequests() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse("""
        {"id":"pred-1","status":"succeeded","output":["https://replicate.example.com/image.png"]}
        """),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("png".utf8))
    ])
    let provider = try AIProviders.replicate(settings: ProviderSettings(apiKey: "replicate-key", transport: transport))
    let model = try provider.imageModel("black-forest-labs/flux-schnell")
    let controller = AIAbortController()

    _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", abortSignal: controller.signal))

    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].abortSignal === controller.signal)
    #expect(requests[1].abortSignal === controller.signal)
}
@Test func blackForestLabsImageForwardsAbortSignalToSubmitPollAndDownloadRequests() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bfl-1","polling_url":"https://api.bfl.ai/v1/get_result"}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://bfl.example.com/image.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("png".utf8))
    ])
    let provider = try AIProviders.blackForestLabs(settings: ProviderSettings(apiKey: "bfl-key", transport: transport))
    let model = try provider.imageModel("flux-pro-1.1")
    let controller = AIAbortController()

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        providerOptions: ["blackForestLabs": .object(["pollIntervalMillis": .number(1)])],
        abortSignal: controller.signal
    ))

    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].abortSignal === controller.signal)
    #expect(requests[1].abortSignal === controller.signal)
    #expect(requests[2].abortSignal === controller.signal)
}
@Test func lumaImageForwardsAbortSignalToSubmitPollAndDownloadRequests() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"lum-1","state":"queued"}"#),
        jsonResponse(#"{"id":"lum-1","state":"completed","assets":{"image":"https://luma.example.com/image.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("png".utf8))
    ])
    let provider = try AIProviders.luma(settings: ProviderSettings(apiKey: "luma-key", transport: transport))
    let model = try provider.imageModel("photon-1")
    let controller = AIAbortController()

    _ = try await model.generateImage(ImageGenerationRequest(
        prompt: "cat",
        providerOptions: ["luma": .object(["pollIntervalMillis": .number(1)])],
        abortSignal: controller.signal
    ))

    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].abortSignal === controller.signal)
    #expect(requests[1].abortSignal === controller.signal)
    #expect(requests[2].abortSignal === controller.signal)
}
@Test func klingAIForwardsAbortSignalToCreateAndPollRequests() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"code":0,"message":"ok","data":{"task_id":"kling-task","task_status":"submitted"}}"#),
        jsonResponse(#"{"code":0,"message":"ok","data":{"task_id":"kling-task","task_status":"succeed","task_result":{"videos":[{"url":"https://kling.example.com/video.mp4"}]}}}"#)
    ])
    let provider = try AIProviders.klingAI(settings: ProviderSettings(apiKey: "kling-token", transport: transport))
    let model = try provider.videoModel("kling-v2.6-t2v")
    let controller = AIAbortController()

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat",
        providerOptions: ["klingai": .object(["pollIntervalMs": .number(1)])],
        abortSignal: controller.signal
    ))

    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].abortSignal === controller.signal)
    #expect(requests[1].abortSignal === controller.signal)
}
@Test func byteDanceForwardsAbortSignalToCreateAndPollRequests() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"id":"bytedance-task"}"#),
        jsonResponse(#"{"id":"bytedance-task","status":"succeeded","content":{"video_url":"https://bytedance.example.com/video.mp4"}}"#)
    ])
    let provider = try AIProviders.byteDance(settings: ProviderSettings(apiKey: "ark-key", transport: transport))
    let model = try provider.videoModel("seedance-1-0-pro-250528")
    let controller = AIAbortController()

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat",
        providerOptions: ["bytedance": .object(["pollIntervalMs": .number(1)])],
        abortSignal: controller.signal
    ))

    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].abortSignal === controller.signal)
    #expect(requests[1].abortSignal === controller.signal)
}
@Test func falForwardsAbortSignalToImageVideoAndTranscriptionRequests() async throws {
    let imageTransport = RecordingTransport(responses: [
        jsonResponse(#"{"image":{"url":"https://fal.example.com/image.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("png".utf8))
    ])
    let imageProvider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: imageTransport))
    let imageModel = try imageProvider.imageModel("fal-ai/qwen-image")
    let imageController = AIAbortController()

    _ = try await imageModel.generateImage(ImageGenerationRequest(prompt: "cat", abortSignal: imageController.signal))

    let imageRequests = await imageTransport.requests()
    #expect(imageRequests.count == 2)
    #expect(imageRequests[0].abortSignal === imageController.signal)
    #expect(imageRequests[1].abortSignal === imageController.signal)

    let videoTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"video-1","response_url":"https://queue.fal.run/fal-ai/luma-dream-machine/requests/video-1"}"#),
        jsonResponse(#"{"video":{"url":"https://fal.example.com/video.mp4"}}"#)
    ])
    let videoProvider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: videoTransport))
    let videoModel = try videoProvider.videoModel("fal-ai/luma-dream-machine")
    let videoController = AIAbortController()

    _ = try await videoModel.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        providerOptions: ["fal": .object(["pollIntervalMs": .number(1), "pollTimeoutMs": .number(1_000)])],
        abortSignal: videoController.signal
    ))

    let videoRequests = await videoTransport.requests()
    #expect(videoRequests.count == 2)
    #expect(videoRequests[0].abortSignal === videoController.signal)
    #expect(videoRequests[1].abortSignal === videoController.signal)

    let transcriptionTransport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"transcription-1"}"#),
        jsonResponse(#"{"text":"fal transcript","chunks":[]}"#)
    ])
    let transcriptionProvider = try AIProviders.fal(settings: ProviderSettings(apiKey: "fal-key", transport: transcriptionTransport))
    let transcriptionModel = try transcriptionProvider.transcriptionModel("fal-ai/wizper")
    let transcriptionController = AIAbortController()

    _ = try await transcriptionModel.transcribe(AudioTranscriptionRequest(
        audio: Data("audio".utf8),
        mimeType: "audio/wav",
        abortSignal: transcriptionController.signal
    ))

    let transcriptionRequests = await transcriptionTransport.requests()
    #expect(transcriptionRequests.count == 2)
    #expect(transcriptionRequests[0].abortSignal === transcriptionController.signal)
    #expect(transcriptionRequests[1].abortSignal === transcriptionController.signal)
}
@Test func googleVideoForwardsAbortSignalToCreateAndPollRequests() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"name":"operations/video-1","done":false}"#),
        jsonResponse(#"{"name":"operations/video-1","done":true,"response":{"generateVideoResponse":{"generatedSamples":[{"video":{"uri":"https://generativelanguage.googleapis.com/files/video-123.mp4?alt=media"}}]}}}"#)
    ])
    let provider = try AIProviders.google(settings: ProviderSettings(apiKey: "gemini-key", transport: transport))
    let model = try provider.videoModel("veo-3.1-generate-preview")
    let controller = AIAbortController()

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        extraBody: ["pollIntervalMs": 0],
        abortSignal: controller.signal
    ))

    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].abortSignal === controller.signal)
    #expect(requests[1].abortSignal === controller.signal)
}
@Test func xAIVideoForwardsAbortSignalToCreateAndPollRequests() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"vid-1"}"#),
        jsonResponse(#"{"status":"done","video":{"url":"https://x.ai/video.mp4","respect_moderation":true}}"#)
    ])
    let provider = try AIProviders.xAI(settings: ProviderSettings(apiKey: "xai-key", transport: transport))
    let model = try provider.videoModel("grok-2-video")
    let controller = AIAbortController()

    _ = try await model.generateVideo(VideoGenerationRequest(
        prompt: "cat running",
        extraBody: ["pollIntervalMs": 0],
        abortSignal: controller.signal
    ))

    let requests = await transport.requests()
    #expect(requests.count == 2)
    #expect(requests[0].abortSignal === controller.signal)
    #expect(requests[1].abortSignal === controller.signal)
}
@Test func deepInfraImageForwardsAbortSignalToGenerationAndEditRequests() async throws {
    let generateTransport = RecordingTransport(response: jsonResponse(#"{"images":["data:image/png;base64,image"]}"#))
    let generateProvider = try AIProviders.deepInfra(settings: ProviderSettings(apiKey: "deepinfra-key", transport: generateTransport))
    let generateModel = try generateProvider.imageModel("black-forest-labs/FLUX-1-schnell")
    let generateController = AIAbortController()

    _ = try await generateModel.generateImage(ImageGenerationRequest(prompt: "cat", abortSignal: generateController.signal))

    let generateRequest = try #require(await generateTransport.requests().first)
    #expect(generateRequest.abortSignal === generateController.signal)

    let editTransport = RecordingTransport(response: jsonResponse(#"{"data":[{"b64_json":"edited"}]}"#))
    let editProvider = try AIProviders.deepInfra(settings: ProviderSettings(apiKey: "deepinfra-key", transport: editTransport))
    let editModel = try editProvider.imageModel("black-forest-labs/FLUX.1-Kontext-dev")
    let editController = AIAbortController()

    _ = try await editModel.generateImage(ImageGenerationRequest(
        prompt: "edit",
        files: [ImageInputFile(data: Data("png".utf8), mediaType: "image/png")],
        abortSignal: editController.signal
    ))

    let editRequest = try #require(await editTransport.requests().first)
    #expect(editRequest.abortSignal === editController.signal)
}
@Test func fireworksAsyncImageForwardsAbortSignalToSubmitPollAndDownloadRequests() async throws {
    let transport = RecordingTransport(responses: [
        jsonResponse(#"{"request_id":"fw-1"}"#),
        jsonResponse(#"{"status":"Ready","result":{"sample":"https://assets.example.com/fireworks.png"}}"#),
        AIHTTPResponse(statusCode: 200, headers: ["content-type": "image/png"], body: Data("png".utf8))
    ])
    let provider = try AIProviders.fireworks(settings: ProviderSettings(apiKey: "fireworks-key", transport: transport))
    let model = try provider.imageModel("accounts/fireworks/models/flux-kontext-pro")
    let controller = AIAbortController()

    _ = try await model.generateImage(ImageGenerationRequest(prompt: "cat", abortSignal: controller.signal))

    let requests = await transport.requests()
    #expect(requests.count == 3)
    #expect(requests[0].abortSignal === controller.signal)
    #expect(requests[1].abortSignal === controller.signal)
    #expect(requests[2].abortSignal === controller.signal)
}
