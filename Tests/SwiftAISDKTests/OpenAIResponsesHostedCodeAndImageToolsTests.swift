import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesPreparesCodeInterpreterContainersLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Run code.")],
        tools: [
            "auto_code_interpreter": OpenAITools.codeInterpreter(),
            "container_code_interpreter": OpenAITools.codeInterpreter(container: "container-123"),
            "files_code_interpreter": OpenAITools.codeInterpreter(container: ["fileIds": ["file-1", "file-2", "file-3"]]),
            "empty_files_code_interpreter": OpenAITools.codeInterpreter(container: ["fileIds": []]),
            "undefined_files_code_interpreter": OpenAITools.codeInterpreter(container: [:])
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let tools = try #require(body["tools"]?.arrayValue)
    let codeTools = tools.filter { $0["type"]?.stringValue == "code_interpreter" }
    #expect(codeTools.count == 5)
    #expect(codeTools.contains { $0["container"]?["type"]?.stringValue == "auto" && $0["container"]?["file_ids"] == nil })
    #expect(codeTools.contains { $0["container"]?.stringValue == "container-123" })
    #expect(codeTools.contains { $0["container"]?["file_ids"]?[2]?.stringValue == "file-3" })
    #expect(codeTools.contains { $0["container"]?["file_ids"]?.arrayValue?.isEmpty == true })
}

@Test func openAIResponsesSendsCodeInterpreterRequestBodyLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-code-interpreter","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "codeExecution": [
                "type": "provider",
                "id": "openai.code_interpreter",
                "name": "codeExecution",
                "args": [:]
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["include"]?.arrayValue?.compactMap(\.stringValue) == ["code_interpreter_call.outputs"])
    #expect(body["input"]?[0]?["role"]?.stringValue == "user")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
    #expect(body["model"]?.stringValue == "gpt-5-nano")
    #expect(body["tools"]?.arrayValue == [
        .object([
            "container": .object(["type": .string("auto")]),
            "type": .string("code_interpreter")
        ])
    ])
}

@Test func openAIResponsesIncludesCodeInterpreterContentAndAnnotationsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_024ee52fc1900767006903bf276a60819395647a8a01d4a3d8","object":"response","created_at":1761853223,"status":"completed","background":false,"billing":{"payer":"developer"},"error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5-nano-2025-08-07","output":[{"id":"rs_024ee52fc1900767006903bf2cf8348193be2e9dedeedfd7eb","type":"reasoning","summary":[]},{"id":"ci_024ee52fc1900767006903bf34e2b08193a689f71dcc3724f7","type":"code_interpreter_call","status":"completed","code":"import random\\r\\n\\r\\ntrials = 10000\\r\\nsums = []\\r\\nfor _ in range(trials):\\r\\n    die1 = random.randint(1,6)\\r\\n    die2 = random.randint(1,6)\\r\\n    sums.append(die1 + die2)\\r\\ntotal_sum = sum(sums)\\r\\nlen(sums), total_sum\\n","container_id":"cntr_6903bf2c0470819090b2b1e63e0b66800c139a5d654a42ec","outputs":[{"type":"logs","logs":"(10000, 70024)"}]},{"id":"rs_024ee52fc1900767006903bf381cec8193a48068baa82e17a3","type":"reasoning","summary":[]},{"id":"ci_024ee52fc1900767006903bf38f1f08193a0b46ddc935fa028","type":"code_interpreter_call","status":"completed","code":"filename = \\"/mnt/data/two_dice_sums_10000.txt\\"\\r\\nwith open(filename, \\"w\\") as f:\\r\\n    for s in sums:\\r\\n        f.write(str(s) + \\"\\\\n\\")\\r\\n    f.write(\\"TOTAL: \\" + str(total_sum) + \\"\\\\n\\")\\r\\nfilename, os.path.getsize(filename)\\n","container_id":"cntr_6903bf2c0470819090b2b1e63e0b66800c139a5d654a42ec","outputs":[]},{"id":"rs_024ee52fc1900767006903bf3ddb0881939e1af28db8fb9f17","type":"reasoning","summary":[]},{"id":"ci_024ee52fc1900767006903bf3e05b48193bbb2367cbc9a299e","type":"code_interpreter_call","status":"completed","code":"import os\\r\\nfilename = \\"/mnt/data/two_dice_sums_10000.txt\\"\\r\\nwith open(filename, \\"w\\") as f:\\r\\n    for s in sums:\\r\\n        f.write(str(s) + \\"\\\\n\\")\\r\\n    f.write(\\"TOTAL: \\" + str(total_sum) + \\"\\\\n\\")\\r\\nos.path.getsize(filename), filename\\n","container_id":"cntr_6903bf2c0470819090b2b1e63e0b66800c139a5d654a42ec","outputs":[{"type":"logs","logs":"(21680, '/mnt/data/two_dice_sums_10000.txt')"}]},{"id":"rs_024ee52fc1900767006903bf40cd488193b3a36868bf31054a","type":"reasoning","summary":[]},{"id":"msg_024ee52fc1900767006903bf43b66081939b669e0ce1deb286","type":"message","status":"completed","content":[{"type":"output_text","annotations":[{"type":"container_file_citation","container_id":"cntr_6903bf2c0470819090b2b1e63e0b66800c139a5d654a42ec","end_index":236,"file_id":"cfile_6903bf45e3288191af3d56e6d23c3a4d","filename":"two_dice_sums_10000.txt","start_index":195}],"logprobs":[],"text":"I ran 10,000 trials of rolling two dice and summed the results.\\n\\n- Total sum across all 10,000 rolls: 70024\\n- Per-trial sums were saved to a file. You can download it here:\\n  [Download the file](sandbox:/mnt/data/two_dice_sums_10000.txt)\\n\\nThe file contains 10,000 lines (one sum per line) followed by a final line with the total, e.g., \\"TOTAL: 70024\\".\\n\\nIf you\\u2019d like the file in a different format (CSV, JSON) or with only the total, I can adjust and re-upload."}],"role":"assistant"}],"parallel_tool_calls":true,"previous_response_id":null,"prompt_cache_key":null,"reasoning":{"effort":"medium","summary":null},"safety_identifier":null,"service_tier":"default","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"code_interpreter","container":{"type":"auto"}}],"top_logprobs":0,"top_p":1,"truncation":"disabled","usage":{"input_tokens":2283,"input_tokens_details":{"cached_tokens":0},"output_tokens":1928,"output_tokens_details":{"reasoning_tokens":1792},"total_tokens":4211},"user":null,"metadata":{}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "codeExecution": [
                "type": "provider",
                "id": "openai.code_interpreter",
                "name": "codeExecution",
                "args": [:]
            ]
        ]
    ))

    #expect(result.content.count == 12)
    guard case let .reasoning(firstReasoning, firstReasoningMetadata) = result.content[0],
          case let .toolCall(firstToolCall) = result.content[1],
          case let .toolResult(firstToolResult) = result.content[2],
          case let .reasoning(secondReasoning, secondReasoningMetadata) = result.content[3],
          case let .toolCall(secondToolCall) = result.content[4],
          case let .toolResult(secondToolResult) = result.content[5],
          case let .reasoning(thirdReasoning, thirdReasoningMetadata) = result.content[6],
          case let .toolCall(thirdToolCall) = result.content[7],
          case let .toolResult(thirdToolResult) = result.content[8],
          case let .reasoning(fourthReasoning, fourthReasoningMetadata) = result.content[9],
          case let .text(text, textMetadata) = result.content[10],
          case let .source(source) = result.content[11] else {
        Issue.record("Expected upstream code interpreter content order")
        return
    }

    #expect(firstReasoning == "")
    #expect(secondReasoning == "")
    #expect(thirdReasoning == "")
    #expect(fourthReasoning == "")
    #expect(firstReasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_024ee52fc1900767006903bf2cf8348193be2e9dedeedfd7eb")
    #expect(secondReasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_024ee52fc1900767006903bf381cec8193a48068baa82e17a3")
    #expect(thirdReasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_024ee52fc1900767006903bf3ddb0881939e1af28db8fb9f17")
    #expect(fourthReasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_024ee52fc1900767006903bf40cd488193b3a36868bf31054a")

    #expect(firstToolCall.id == "ci_024ee52fc1900767006903bf34e2b08193a689f71dcc3724f7")
    #expect(firstToolCall.name == "codeExecution")
    #expect(firstToolCall.providerExecuted == true)
    #expect(firstToolCall.arguments.contains(#""containerId":"cntr_6903bf2c0470819090b2b1e63e0b66800c139a5d654a42ec""#))
    #expect(firstToolCall.arguments.contains(#""code":"import random\r\n\r\ntrials = 10000"#))
    #expect(firstToolResult.toolCallID == firstToolCall.id)
    #expect(firstToolResult.toolName == "codeExecution")
    #expect(firstToolResult.result["outputs"]?[0]?["logs"]?.stringValue == "(10000, 70024)")

    #expect(secondToolCall.id == "ci_024ee52fc1900767006903bf38f1f08193a0b46ddc935fa028")
    #expect(secondToolCall.name == "codeExecution")
    #expect(secondToolResult.toolCallID == secondToolCall.id)
    #expect(secondToolResult.toolName == "codeExecution")
    #expect(secondToolResult.result["outputs"]?.arrayValue?.isEmpty == true)

    #expect(thirdToolCall.id == "ci_024ee52fc1900767006903bf3e05b48193bbb2367cbc9a299e")
    #expect(thirdToolCall.name == "codeExecution")
    #expect(thirdToolResult.toolCallID == thirdToolCall.id)
    #expect(thirdToolResult.toolName == "codeExecution")
    #expect(thirdToolResult.result["outputs"]?[0]?["logs"]?.stringValue == "(21680, '/mnt/data/two_dice_sums_10000.txt')")

    #expect(text.contains("Total sum across all 10,000 rolls: 70024"))
    #expect(text.contains("[Download the file](sandbox:/mnt/data/two_dice_sums_10000.txt)"))
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_024ee52fc1900767006903bf43b66081939b669e0ce1deb286")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["file_id"]?.stringValue == "cfile_6903bf45e3288191af3d56e6d23c3a4d")

    #expect(source.sourceType == "document")
    #expect(source.id == "id-0")
    #expect(source.filename == "two_dice_sums_10000.txt")
    #expect(source.mediaType == "text/plain")
    #expect(source.providerMetadata["openai"]?["containerId"]?.stringValue == "cntr_6903bf2c0470819090b2b1e63e0b66800c139a5d654a42ec")
    #expect(source.providerMetadata["openai"]?["fileId"]?.stringValue == "cfile_6903bf45e3288191af3d56e6d23c3a4d")
}

@Test func openAIResponsesPreparesCodeInterpreterToolChoiceLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Run code.")],
        tools: ["code_interpreter": OpenAITools.codeInterpreter()],
        extraBody: ["toolChoice": ["type": "tool", "toolName": "code_interpreter"]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["tool_choice"]?["type"]?.stringValue == "code_interpreter")
    #expect(body["tools"]?[0]?["type"]?.stringValue == "code_interpreter")
    #expect(body["tools"]?[0]?["container"]?["type"]?.stringValue == "auto")
}

@Test func openAIResponsesPreparesImageGenerationOptionsAndToolChoiceLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Create an image.")],
        tools: [
            "image_generation": OpenAITools.imageGeneration(
                background: "opaque",
                moderation: "auto",
                outputCompression: 100,
                outputFormat: "png",
                quality: "high",
                size: "1536x1024"
            )
        ],
        extraBody: ["toolChoice": ["type": "tool", "toolName": "image_generation"]]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["tool_choice"]?["type"]?.stringValue == "image_generation")
    let tool = try #require(body["tools"]?[0])
    #expect(tool["type"]?.stringValue == "image_generation")
    #expect(tool["background"]?.stringValue == "opaque")
    #expect(tool["moderation"]?.stringValue == "auto")
    #expect(tool["output_compression"]?.intValue == 100)
    #expect(tool["output_format"]?.stringValue == "png")
    #expect(tool["quality"]?.stringValue == "high")
    #expect(tool["size"]?.stringValue == "1536x1024")
}

@Test func openAIResponsesSendsImageGenerationRequestBodyLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "generateImage": [
                "type": "provider",
                "id": "openai.image_generation",
                "name": "generateImage",
                "args": [
                    "outputFormat": "webp",
                    "quality": "low",
                    "size": "1024x1024",
                    "partialImages": 2
                ]
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "gpt-5-nano")
    #expect(body["include"] == nil)
    #expect(body["input"]?[0]?["role"]?.stringValue == "user")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
    let tool = try #require(body["tools"]?[0])
    #expect(tool["type"]?.stringValue == "image_generation")
    #expect(tool["output_format"]?.stringValue == "webp")
    #expect(tool["partial_images"]?.intValue == 2)
    #expect(tool["quality"]?.stringValue == "low")
    #expect(tool["size"]?.stringValue == "1024x1024")
}

@Test func openAIResponsesIncludesImageGenerationContentLikeUpstream() async throws {
    let generatedImage = "UklGRoitEQBXRUJQVlA4TEGzEAAv/8P/AM1AbNtGkITZhU4fH9J/wTOT+xIi+j8BuT4kABkCibNAZrlwIPyQ7W/bH5L2RHMzMBKgXmfZeYi9tLtrrQkZvN1yXHLLgG71gPkpDxmI/gc03YFulQR...AA9lhA0Y9rVdqQs/W4w/MOxeRW5+R1/UXmmNVi9yQ7x/vG0q2VRk01seZIuj5OmRYhD+yY82dZqMH1BCueTeOcNfGKxQ=="
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_0a33d15155cb126d0068c96c54970481958484dea31f07926d","object":"response","created_at":1758030932,"status":"completed","background":false,"error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5-nano-2025-08-07","output":[{"id":"rs_0a33d15155cb126d0068c96c5527808195a933b468ccb5dfd9","type":"reasoning","summary":[]},{"id":"ig_0a33d15155cb126d0068c96c59bc14819599154c9988b82996","type":"image_generation_call","status":"completed","background":"opaque","output_format":"webp","quality":"low","result":"\(generatedImage)","revised_prompt":"A cute fluffy cat sitting on a sunlit windowsill, warm sunlight, soft fur, expressive eyes, photorealistic style.","size":"1024x1024"},{"id":"rs_0a33d15155cb126d0068c96c6c0ef48195bc73e30faf832ba3","type":"reasoning","summary":[]},{"id":"msg_0a33d15155cb126d0068c96c723ed88195b1405bc370bb8a65","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":""}],"role":"assistant"}],"parallel_tool_calls":true,"previous_response_id":null,"prompt_cache_key":null,"reasoning":{"effort":"medium","summary":null},"safety_identifier":null,"service_tier":"default","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"image_generation","background":"auto","moderation":"auto","n":1,"output_compression":100,"output_format":"webp","quality":"low","size":"1024x1024"}],"top_logprobs":0,"top_p":1,"truncation":"disabled","usage":{"input_tokens":3151,"input_tokens_details":{"cached_tokens":0},"output_tokens":1970,"output_tokens_details":{"reasoning_tokens":1920},"total_tokens":5121},"user":null,"metadata":{}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "generateImage": [
                "type": "provider",
                "id": "openai.image_generation",
                "name": "generateImage",
                "args": [
                    "outputFormat": "webp",
                    "quality": "low",
                    "size": "1024x1024",
                    "partialImages": 2
                ]
            ]
        ]
    ))

    #expect(result.content.count == 5)
    guard case let .reasoning(firstReasoning, firstReasoningMetadata) = result.content[0],
          case let .toolCall(toolCall) = result.content[1],
          case let .toolResult(toolResult) = result.content[2],
          case let .reasoning(secondReasoning, secondReasoningMetadata) = result.content[3],
          case let .text(text, textMetadata) = result.content[4] else {
        Issue.record("Expected upstream image generation content order")
        return
    }

    #expect(firstReasoning == "")
    #expect(firstReasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_0a33d15155cb126d0068c96c5527808195a933b468ccb5dfd9")
    #expect(secondReasoning == "")
    #expect(secondReasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_0a33d15155cb126d0068c96c6c0ef48195bc73e30faf832ba3")
    #expect(toolCall.id == "ig_0a33d15155cb126d0068c96c59bc14819599154c9988b82996")
    #expect(toolCall.name == "generateImage")
    #expect(toolCall.arguments == "{}")
    #expect(toolCall.providerExecuted == true)
    #expect(toolResult.toolCallID == toolCall.id)
    #expect(toolResult.toolName == "generateImage")
    #expect(toolResult.result["result"]?.stringValue == generatedImage)
    #expect(text == "")
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_0a33d15155cb126d0068c96c723ed88195b1405bc370bb8a65")
}

