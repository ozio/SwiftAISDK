import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesParsesFunctionAndHostedToolCalls() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp-1","status":"completed","output":[{"type":"function_call","id":"fc_1","call_id":"call_1","name":"lookup","arguments":"{\\"query\\":\\"weather\\"}"},{"type":"web_search_call","id":"ws_1","status":"completed","action":{"type":"search","query":"weather"}}],"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Use tools.")]))

    #expect(result.text == "")
    #expect(result.finishReason == "tool-calls")
    #expect(result.toolCalls.count == 2)
    #expect(result.toolCalls[0].id == "call_1")
    #expect(result.toolCalls[0].name == "lookup")
    #expect(result.toolCalls[0].arguments == #"{"query":"weather"}"#)
    #expect(result.toolCalls[1].id == "ws_1")
    #expect(result.toolCalls[1].name == "web_search")
    #expect(result.toolCalls[1].providerExecuted == true)
    #expect(result.toolCalls[0].providerMetadata["openai"]?["itemId"]?.stringValue == "fc_1")
    #expect(result.toolResults.count == 1)
    #expect(result.toolResults[0].toolCallID == "ws_1")
    #expect(result.toolResults[0].toolName == "web_search")
    #expect(result.toolResults[0].result["action"]?["type"]?.stringValue == "search")
    #expect(result.toolResults[0].result["action"]?["query"]?.stringValue == "weather")
}

@Test func openAIResponsesGenerateTextContentAndUsageLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_67c97c0203188190a025beb4a75242bc","object":"response","created_at":1741257730,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-4o-2024-07-18","output":[{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"answer text","annotations":[]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":1,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":120,"input_tokens_details":{"cached_tokens":10,"orchestration_input_tokens":40,"orchestration_input_cached_tokens":5},"output_tokens":80,"output_tokens_details":{"reasoning_tokens":25,"orchestration_output_tokens":15},"total_tokens":200},"user":null,"metadata":{}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Hello")]))

    #expect(result.text == "answer text")
    #expect(result.providerMetadata["openai"]?["responseId"]?.stringValue == "resp_67c97c0203188190a025beb4a75242bc")
    #expect(result.usage?.inputTokens == 120)
    #expect(result.usage?.inputTokensCacheRead == 10)
    #expect(result.usage?.inputTokensNoCache == 110)
    #expect(result.usage?.outputTokens == 80)
    #expect(result.usage?.outputReasoningTokens == 25)
    #expect(result.usage?.outputTextTokens == 55)
    #expect(result.usage?.rawValue?["input_tokens_details"]?["orchestration_input_tokens"]?.intValue == 40)
    #expect(result.usage?.rawValue?["input_tokens_details"]?["orchestration_input_cached_tokens"]?.intValue == 5)
    #expect(result.usage?.rawValue?["output_tokens_details"]?["orchestration_output_tokens"]?.intValue == 15)

    guard case let .text(text, providerMetadata) = try #require(result.content.first) else {
        Issue.record("Expected text content part")
        return
    }
    #expect(text == "answer text")
    #expect(providerMetadata["openai"]?["itemId"]?.stringValue == "msg_67c97c02656c81908e080dfdf4a03cd1")
}

@Test func openAIResponsesGenerateReasoningContentWithSummaryLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_reasoning_summary","object":"response","created_at":1741257730,"status":"completed","output":[{"id":"rs_6808709f6fcc8191ad2e2fdd784017b3","type":"reasoning","summary":[{"type":"summary_text","text":"First reasoning step."},{"type":"summary_text","text":"Second reasoning step."}]},{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"answer text","annotations":[]}]}],"reasoning":{"effort":"low","summary":"auto"},"usage":{"input_tokens":34,"input_tokens_details":{"cached_tokens":0},"output_tokens":538,"output_tokens_details":{"reasoning_tokens":320},"total_tokens":572}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("o3-mini")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: ["openai": ["reasoningEffort": "low", "reasoningSummary": "auto"]]
    ))

    #expect(result.text == "answer text")
    #expect(result.content.count == 3)
    guard case let .reasoning(firstReasoning, firstMetadata) = result.content[0],
          case let .reasoning(secondReasoning, secondMetadata) = result.content[1],
          case let .text(text, textMetadata) = result.content[2] else {
        Issue.record("Expected reasoning, reasoning, text content parts")
        return
    }
    #expect(firstReasoning == "First reasoning step.")
    #expect(secondReasoning == "Second reasoning step.")
    #expect(firstMetadata["openai"]?["itemId"]?.stringValue == "rs_6808709f6fcc8191ad2e2fdd784017b3")
    #expect(firstMetadata["openai"]?["reasoningEncryptedContent"] == .null)
    #expect(secondMetadata["openai"]?["itemId"]?.stringValue == "rs_6808709f6fcc8191ad2e2fdd784017b3")
    #expect(text == "answer text")
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_67c97c02656c81908e080dfdf4a03cd1")
}

@Test func openAIResponsesGenerateReasoningEncryptedContentUsingRealFixtureLikeUpstream() async throws {
    let encryptedContent = "gAAAAABpPMlcH0HHEv5_ozHwP5Gxz5ZLE7A8Aw7GK94sa1KWHqXLrAch29KZrZqCzH6PkWnLWTxIZv4TL70DPoKbS_ryNp6d2rC8vS04U7qWLdsbYnsqmPYVCCQ2Rigd84Yh9mgctGTs_w5x7NY3pm5lOxUv5jGHAW20nAMGfpFAAYRjW1aAA7f1CjfcXgm8CgNOc1Mu3L9a-q64LU8taFhc_9-GNBqRD-Gxul4pVXTQ4BlnYwOGOsfctcM_SNxYgYM2gS0pawkltN5250JlO7LaUcteD8E47fpcHGS9hmzDpMGWvIpuksPjzBnVn_R9JJcJSd_rMO8TTrGlXT-Thw_UOdX3aZZLac2OMD_MIkGN4GuGISC674RZlJWi8_x-C-VqdkRm0qsEwYvFp17ykYReCtPocXWtOI1dyVZogyQYO5b6qEmHjPXIFqyoPHLjes_CrWyR7ChVcR_GTJq55lsHfppBevMU4wGbHga6CgaC_dcbGo4ECXPh0HUqs4U7t58JgJcCQ1DX1AygF4cRjKAs4mqTXOR4ruHutmknG61sOuc19FtOyhIadquNd2EBb9pa7Rix5Rk_0cTb1jkUBVH3QknhjjCDvvlp8MIp5jU55ANgI9ZpL3TTVWziTCJLdeLMUpohKggDJ7axs9qdhl3dfdvdhLnN5GimFNxWglWn8ioQ7KMYil9HxGErd47q0GxfFqnuNMfchsLESwCdmGMqsaavEjZjD_bQ_iXASQgmk2FYXo41tsHtrVBzJCFFLhswr1t47b8qb3_pJeevwLeuBfRR56ZKxQLyp35rLGzizSKknkKRrbimGL8L4hSI2ktPlH0JZlBiH7mhsBPSs8W7GhZjMYFUQ3RMBshUjHGx3Tu_iW5pNKkrI_XWDHaCNurXBNYV9Kj23Xj6GAQaFzGn62GpvKbObXFlW941aRuZLPCAhGHRZptxrNZEg_DcVcUrMEPHubEA5YUMSb4iZtszE0FT7kVmYmFU3SR-heOU2umXykQx5wnCoi0FtzWLDSXUbElcex-5k11pIoQH59HQYhfNzogV9p9MO1O9hGRaJkA_RZbUxRVKqDURRjNWzXJb8SdoCcRZSFdv_2WRv5NCt1XHBFcAL8DSa6Mu2y0DR-SW7kpu-yKRa8_R4g9dtweK6JRWZxG_TLxH_JIAwfmbts97zBwC-9pcmnC1UshE6_Z9RwRe3a2OTBNkS6dTHV8WMgM02fVFPhiFmFLj_jGUzxW4uQlWnTorO2-X2C-EcgzOGkEngM6_fhY-ZWTN4xEA6GRoCTSTYEaHq1MPIASasagN6N-NwALyBzLJ3vmwdo6ub5KS1JB4G_knIapiUKaGjVTGXCVG8iVTCrjc-fhrZnnY4yZyQP8RSc33JTIE3fYgPyJ9qwHRYlsH70TVbv0gXmUKCE-woT2nqyqYJMdIwtPWOpAc2lXEr5xeM0mZ3XzuArSP3rogl-p6TZNhrKfzQbMlL3yC9UK_rkShXOoi4MpOmNbnNgRCO2XZ_qO7MTTFqZwaM6VOnX3SStqEaTskoASEz7no-6OmMC7eJRZj1LtUqh2kCQ=="
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_0f35ed53160b395301693cc957829881909359e7f80cdd20b5","object":"response","created_at":1765591383,"status":"completed","background":false,"billing":{"payer":"developer"},"error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5-mini-2025-08-07","output":[{"id":"rs_0f35ed53160b395301693cc95817ac8190b978637daea4987e","type":"reasoning","encrypted_content":"\(encryptedContent)","summary":[{"type":"summary_text","text":"**Reporting final result**\\n\\nThe tool returned 570, and now I need to report this final result. The user asked for a clear breakdown, so I'll include the steps taken: first, I added 12 and 7 to get 19; then, I multiplied 19 by 3 for 57; finally, I multiplied 57 by 10 to arrive at 570. I want to keep it concise, so I'll simply say, \\"Final result: 570,\\" without heavy formatting. Let's finalize that!"}]},{"id":"msg_0f35ed53160b395301693cc95c1d288190997018450969162b","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"12 + 7 = 19\\n19 \\u00d7 3 = 57\\n57 \\u00d7 10 = 570\\n\\nFinal result: 570"}],"role":"assistant"}],"parallel_tool_calls":true,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"high","summary":"detailed"},"safety_identifier":null,"service_tier":"default","store":false,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"function","description":"A minimal calculator for basic arithmetic. Call it once per step.","name":"calculator","parameters":{"type":"object","properties":{"a":{"type":"number","description":"First operand."},"b":{"type":"number","description":"Second operand."},"op":{"type":"string","enum":["add","subtract","multiply","divide"],"default":"add","description":"Arithmetic operation to perform."}},"required":["a","b","op"],"additionalProperties":false},"strict":true}],"top_logprobs":0,"top_p":1,"truncation":"disabled","usage":{"input_tokens":865,"input_tokens_details":{"cached_tokens":0},"output_tokens":163,"output_tokens_details":{"reasoning_tokens":128},"total_tokens":1028},"user":null,"metadata":{}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-mini")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("What is (12 + 7) * 3 * 10? Show the arithmetic.")],
        tools: [
            "codeExecution": [
                "type": "provider",
                "id": "openai.code_interpreter",
                "name": "codeExecution",
                "args": [:]
            ]
        ]
    ))

    #expect(result.content.count == 2)
    guard case let .reasoning(reasoning, reasoningMetadata) = result.content[0],
          case let .text(text, textMetadata) = result.content[1] else {
        Issue.record("Expected reasoning and text content parts")
        return
    }
    #expect(reasoning == """
    **Reporting final result**

    The tool returned 570, and now I need to report this final result. The user asked for a clear breakdown, so I'll include the steps taken: first, I added 12 and 7 to get 19; then, I multiplied 19 by 3 for 57; finally, I multiplied 57 by 10 to arrive at 570. I want to keep it concise, so I'll simply say, "Final result: 570," without heavy formatting. Let's finalize that!
    """)
    #expect(reasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_0f35ed53160b395301693cc95817ac8190b978637daea4987e")
    #expect(reasoningMetadata["openai"]?["reasoningEncryptedContent"]?.stringValue == encryptedContent)
    #expect(text == "12 + 7 = 19\n19 \u{00d7} 3 = 57\n57 \u{00d7} 10 = 570\n\nFinal result: 570")
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_0f35ed53160b395301693cc95c1d288190997018450969162b")
}

@Test func openAIResponsesGenerateReasoningContentWithEmptySummaryLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_reasoning_empty_summary","object":"response","created_at":1741257730,"status":"completed","output":[{"id":"rs_6808709f6fcc8191ad2e2fdd784017b3","type":"reasoning","summary":[]},{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"answer text","annotations":[]}]}],"reasoning":{"effort":"low","summary":"auto"},"usage":{"input_tokens":34,"input_tokens_details":{"cached_tokens":0},"output_tokens":538,"output_tokens_details":{"reasoning_tokens":320},"total_tokens":572}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("o3-mini")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: ["openai": ["reasoningEffort": "low", "reasoningSummary": .null]]
    ))

    #expect(result.text == "answer text")
    #expect(result.content.count == 2)
    guard case let .reasoning(reasoning, reasoningMetadata) = result.content[0],
          case let .text(text, textMetadata) = result.content[1] else {
        Issue.record("Expected reasoning and text content parts")
        return
    }
    #expect(reasoning == "")
    #expect(reasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_6808709f6fcc8191ad2e2fdd784017b3")
    #expect(reasoningMetadata["openai"]?["reasoningEncryptedContent"] == .null)
    #expect(text == "answer text")
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_67c97c02656c81908e080dfdf4a03cd1")

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["reasoning"]?["effort"]?.stringValue == "low")
    #expect(body["reasoning"]?["summary"] == nil)
}

@Test func openAIResponsesGenerateEncryptedReasoningContentWithSummaryLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_encrypted_summary","object":"response","created_at":1741257730,"status":"completed","output":[{"id":"rs_6808709f6fcc8191ad2e2fdd784017b3","type":"reasoning","encrypted_content":"encrypted_reasoning_data_abc123","summary":[{"type":"summary_text","text":"**Exploring burrito origins**\\n\\nThe user is curious about the debate regarding Taqueria La Cumbre and El Farolito."},{"type":"summary_text","text":"**Investigating burrito origins**\\n\\nThere's a fascinating debate about who created the Mission burrito."}]},{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"answer text","annotations":[]}]}],"reasoning":{"effort":"low","summary":"auto"},"usage":{"input_tokens":34,"input_tokens_details":{"cached_tokens":0},"output_tokens":538,"output_tokens_details":{"reasoning_tokens":320},"total_tokens":572}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("o3-mini")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: ["openai": [
            "reasoningEffort": "low",
            "reasoningSummary": "auto",
            "include": ["reasoning.encrypted_content"]
        ]]
    ))

    #expect(result.content.count == 3)
    guard case let .reasoning(firstReasoning, firstMetadata) = result.content[0],
          case let .reasoning(secondReasoning, secondMetadata) = result.content[1],
          case let .text(text, textMetadata) = result.content[2] else {
        Issue.record("Expected reasoning, reasoning, text content parts")
        return
    }
    #expect(firstReasoning == "**Exploring burrito origins**\n\nThe user is curious about the debate regarding Taqueria La Cumbre and El Farolito.")
    #expect(secondReasoning == "**Investigating burrito origins**\n\nThere's a fascinating debate about who created the Mission burrito.")
    #expect(firstMetadata["openai"]?["itemId"]?.stringValue == "rs_6808709f6fcc8191ad2e2fdd784017b3")
    #expect(firstMetadata["openai"]?["reasoningEncryptedContent"]?.stringValue == "encrypted_reasoning_data_abc123")
    #expect(secondMetadata["openai"]?["itemId"]?.stringValue == "rs_6808709f6fcc8191ad2e2fdd784017b3")
    #expect(secondMetadata["openai"]?["reasoningEncryptedContent"]?.stringValue == "encrypted_reasoning_data_abc123")
    #expect(text == "answer text")
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_67c97c02656c81908e080dfdf4a03cd1")

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["reasoning"]?["effort"]?.stringValue == "low")
    #expect(body["reasoning"]?["summary"]?.stringValue == "auto")
    #expect(body["include"]?.arrayValue?.compactMap(\.stringValue) == ["reasoning.encrypted_content"])
}

@Test func openAIResponsesGenerateEncryptedReasoningContentWithEmptySummaryLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_encrypted_empty_summary","object":"response","created_at":1741257730,"status":"completed","output":[{"id":"rs_6808709f6fcc8191ad2e2fdd784017b3","type":"reasoning","encrypted_content":"encrypted_reasoning_data_abc123","summary":[]},{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"answer text","annotations":[]}]}],"reasoning":{"effort":"low","summary":"auto"},"usage":{"input_tokens":34,"input_tokens_details":{"cached_tokens":0},"output_tokens":538,"output_tokens_details":{"reasoning_tokens":320},"total_tokens":572}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("o3-mini")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: ["openai": [
            "reasoningEffort": "low",
            "reasoningSummary": .null,
            "include": ["reasoning.encrypted_content"]
        ]]
    ))

    #expect(result.content.count == 2)
    guard case let .reasoning(reasoning, reasoningMetadata) = result.content[0],
          case let .text(text, textMetadata) = result.content[1] else {
        Issue.record("Expected reasoning and text content parts")
        return
    }
    #expect(reasoning == "")
    #expect(reasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_6808709f6fcc8191ad2e2fdd784017b3")
    #expect(reasoningMetadata["openai"]?["reasoningEncryptedContent"]?.stringValue == "encrypted_reasoning_data_abc123")
    #expect(text == "answer text")
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_67c97c02656c81908e080dfdf4a03cd1")

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["reasoning"]?["effort"]?.stringValue == "low")
    #expect(body["reasoning"]?["summary"] == nil)
    #expect(body["include"]?.arrayValue?.compactMap(\.stringValue) == ["reasoning.encrypted_content"])
}

@Test func openAIResponsesGenerateMultipleReasoningBlocksLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_multiple_reasoning","object":"response","created_at":1741257730,"status":"completed","output":[{"id":"rs_first_6808709f6fcc8191ad2e2fdd784017b3","type":"reasoning","summary":[{"type":"summary_text","text":"**Initial analysis**\\n\\nFirst reasoning block: analyzing the problem structure."},{"type":"summary_text","text":"**Deeper consideration**\\n\\nLet me think about the various approaches available."}]},{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Let me think about this step by step.","annotations":[]}]},{"id":"rs_second_7908809g7gcc9291be3e3fee895028c4","type":"reasoning","summary":[{"type":"summary_text","text":"Second reasoning block: considering alternative approaches."}]},{"id":"msg_final_78d08d03767d92908f25523f5ge51e77","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Based on my analysis, here is the solution.","annotations":[]}]}],"reasoning":{"effort":"medium","summary":"auto"},"usage":{"input_tokens":45,"input_tokens_details":{"cached_tokens":0},"output_tokens":628,"output_tokens_details":{"reasoning_tokens":420},"total_tokens":673}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("o3-mini")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: ["openai": ["reasoningEffort": "medium", "reasoningSummary": "auto"]]
    ))

    #expect(result.content.count == 5)
    guard case let .reasoning(firstReasoning, firstMetadata) = result.content[0],
          case let .reasoning(secondReasoning, secondMetadata) = result.content[1],
          case let .text(firstText, firstTextMetadata) = result.content[2],
          case let .reasoning(thirdReasoning, thirdMetadata) = result.content[3],
          case let .text(finalText, finalTextMetadata) = result.content[4] else {
        Issue.record("Expected reasoning, reasoning, text, reasoning, text content parts")
        return
    }
    #expect(firstReasoning == "**Initial analysis**\n\nFirst reasoning block: analyzing the problem structure.")
    #expect(secondReasoning == "**Deeper consideration**\n\nLet me think about the various approaches available.")
    #expect(thirdReasoning == "Second reasoning block: considering alternative approaches.")
    #expect(firstMetadata["openai"]?["itemId"]?.stringValue == "rs_first_6808709f6fcc8191ad2e2fdd784017b3")
    #expect(firstMetadata["openai"]?["reasoningEncryptedContent"] == .null)
    #expect(secondMetadata["openai"]?["itemId"]?.stringValue == "rs_first_6808709f6fcc8191ad2e2fdd784017b3")
    #expect(secondMetadata["openai"]?["reasoningEncryptedContent"] == .null)
    #expect(thirdMetadata["openai"]?["itemId"]?.stringValue == "rs_second_7908809g7gcc9291be3e3fee895028c4")
    #expect(thirdMetadata["openai"]?["reasoningEncryptedContent"] == .null)
    #expect(firstText == "Let me think about this step by step.")
    #expect(firstTextMetadata["openai"]?["itemId"]?.stringValue == "msg_67c97c02656c81908e080dfdf4a03cd1")
    #expect(finalText == "Based on my analysis, here is the solution.")
    #expect(finalTextMetadata["openai"]?["itemId"]?.stringValue == "msg_final_78d08d03767d92908f25523f5ge51e77")

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["reasoning"]?["effort"]?.stringValue == "medium")
    #expect(body["reasoning"]?["summary"]?.stringValue == "auto")
}

@Test func openAIResponsesGenerateToolCallsLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesUpstreamToolCallsFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesUpstreamFunctionTools()
    ))

    #expect(result.content.count == 2)
    guard case let .toolCall(firstToolCall) = result.content[0],
          case let .toolCall(secondToolCall) = result.content[1] else {
        Issue.record("Expected two tool-call content parts")
        return
    }
    #expect(firstToolCall.id == "call_0NdsJqOS8N3J9l2p0p4WpYU9")
    #expect(firstToolCall.name == "weather")
    #expect(firstToolCall.arguments == #"{"location":"San Francisco"}"#)
    #expect(firstToolCall.providerMetadata["openai"]?["itemId"]?.stringValue == "fc_67caf7f4c1ec8190b27edfb5580cfd31")
    #expect(secondToolCall.id == "call_gexo0HtjUfmAIW4gjNOgyrcr")
    #expect(secondToolCall.name == "cityAttractions")
    #expect(secondToolCall.arguments == #"{"city":"San Francisco"}"#)
    #expect(secondToolCall.providerMetadata["openai"]?["itemId"]?.stringValue == "fc_67caf7f5071c81908209c2909c77af05")
}

@Test func openAIResponsesGenerateToolCallsFinishReasonLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesUpstreamToolCallsFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesUpstreamFunctionTools()
    ))

    #expect(result.finishReason == "tool-calls")
}

@Test func openAIResponsesPreservesNamespaceOnFunctionCallOutputLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_ns","object":"response","created_at":1741257730,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-5.4","output":[{"type":"function_call","id":"fc_ns_1","call_id":"call_ns_1","name":"get_weather","arguments":"{\\"location\\":\\"NYC\\"}","status":"completed","namespace":"weather_ns"}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":1,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":0,"output_tokens":0,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":0},"user":null,"metadata":{}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.4")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesUpstreamFunctionTools()
    ))

    let toolCall = try #require(result.toolCalls.first)
    #expect(toolCall.providerMetadata["openai"]?["itemId"]?.stringValue == "fc_ns_1")
    #expect(toolCall.providerMetadata["openai"]?["namespace"]?.stringValue == "weather_ns")
}

@Test func openAIResponsesDoesNotSetNamespaceWhenAbsentFromFunctionCallOutputLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesUpstreamToolCallsFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: openAIResponsesUpstreamFunctionTools()
    ))

    let toolCall = try #require(result.toolCalls.first)
    #expect(toolCall.providerMetadata["openai"]?["namespace"] == nil)
}

@Test func openAIResponsesSendsAllowedToolsProviderOptionLikeUpstream() async throws {
    let body = try await recordedOpenAIResponsesBody(
        modelID: "gpt-4o",
        tools: openAIResponsesUpstreamFunctionTools(),
        providerOptions: [
            "openai": [
                "allowedTools": ["toolNames": ["weather"], "mode": "auto"]
            ]
        ]
    )

    #expect(Set(body["tools"]?.arrayValue?.compactMap { $0["name"]?.stringValue } ?? []) == Set(["weather", "cityAttractions"]))
    #expect(body["tool_choice"]?["type"]?.stringValue == "allowed_tools")
    #expect(body["tool_choice"]?["mode"]?.stringValue == "auto")
    #expect(body["tool_choice"]?["tools"]?.arrayValue == [
        .object(["type": .string("function"), "name": .string("weather")])
    ])
}

@Test func openAIResponsesSendsAllowedToolsRequiredModeLikeUpstream() async throws {
    let body = try await recordedOpenAIResponsesBody(
        modelID: "gpt-4o",
        tools: openAIResponsesUpstreamFunctionTools(),
        providerOptions: [
            "openai": [
                "allowedTools": [
                    "toolNames": ["weather", "cityAttractions"],
                    "mode": "required"
                ]
            ]
        ]
    )

    #expect(body["tool_choice"]?["type"]?.stringValue == "allowed_tools")
    #expect(body["tool_choice"]?["mode"]?.stringValue == "required")
    #expect(body["tool_choice"]?["tools"]?.arrayValue == [
        .object(["type": .string("function"), "name": .string("weather")]),
        .object(["type": .string("function"), "name": .string("cityAttractions")])
    ])
}

@Test func openAIResponsesAllowedToolsOverridesRequestToolChoiceLikeUpstream() async throws {
    let body = try await recordedOpenAIResponsesBody(
        modelID: "gpt-4o",
        tools: openAIResponsesUpstreamFunctionTools(),
        providerOptions: [
            "openai": [
                "allowedTools": ["toolNames": ["weather"]]
            ]
        ],
        toolChoice: ["type": "required"]
    )

    #expect(body["tool_choice"]?["type"]?.stringValue == "allowed_tools")
    #expect(body["tool_choice"]?["mode"]?.stringValue == "auto")
    #expect(body["tool_choice"]?["tools"]?.arrayValue == [
        .object(["type": .string("function"), "name": .string("weather")])
    ])
}

@Test func openAIResponsesForwardsWebSearchActionQueriesToToolResultLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_queries","object":"response","created_at":1741631111,"status":"completed","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-4o","output":[{"type":"web_search_call","id":"ws_queries","status":"completed","action":{"type":"search","query":"sf news","queries":["sf news","bay area tech"]}},{"type":"message","id":"msg_done","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Here is what I found.","annotations":[]}]}],"usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15},"previous_response_id":null,"parallel_tool_calls":true,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[{"type":"web_search","search_context_size":"medium"}],"top_p":1,"truncation":"disabled","user":null,"metadata":{}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Search news.")],
        tools: ["web_search": OpenAITools.webSearch()]
    ))

    #expect(result.text == "Here is what I found.")
    let webSearchResult = try #require(result.toolResults.first { $0.toolName == "web_search" })
    #expect(webSearchResult.toolCallID == "ws_queries")
    #expect(webSearchResult.result["action"]?["type"]?.stringValue == "search")
    #expect(webSearchResult.result["action"]?["query"]?.stringValue == "sf news")
    #expect(webSearchResult.result["action"]?["queries"]?[0]?.stringValue == "sf news")
    #expect(webSearchResult.result["action"]?["queries"]?[1]?.stringValue == "bay area tech")
}

@Test func openAIResponsesParsesFullResponseSchemaShapesLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_schema_shapes","status":"completed","output":[{"type":"web_search_call","id":"ws_open_page","status":"completed","action":{"type":"open_page","url":"https://example.com/docs","sources":[{"type":"url","url":"https://example.com/docs","title":"Docs"}]}},{"type":"file_search_call","id":"fs_1","status":"completed","queries":["swift ai sdk"],"results":[{"file_id":"file_1","filename":"guide.md","score":0.91,"text":"Relevant chunk","attributes":{"topic":"docs"}}]},{"type":"code_interpreter_call","id":"ci_1","status":"completed","container_id":"cntr_1","code":"print(1)","outputs":[{"type":"logs","logs":"1\\n"}]},{"type":"message","id":"msg_schema","status":"completed","phase":"final_answer","role":"assistant","content":[{"type":"output_text","text":"Done","annotations":[{"type":"url_citation","url":"https://example.com/docs","title":"Docs","start_index":0,"end_index":4}],"logprobs":[{"token":"Done","logprob":-0.01}]}]}],"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Use hosted tools.")]))

    #expect(result.text == "Done")
    #expect(result.sources.count == 1)
    #expect(result.sources[0].url == "https://example.com/docs")
    #expect(result.sources[0].rawValue?["start_index"]?.intValue == 0)
    #expect(result.providerMetadata["openai"]?["logprobs"]?[0]?[0]?["token"]?.stringValue == "Done")

    let webSearchResult = try #require(result.toolResults.first { $0.toolName == "web_search" })
    #expect(webSearchResult.result["action"]?["type"]?.stringValue == "openPage")
    #expect(webSearchResult.result["action"]?["url"]?.stringValue == "https://example.com/docs")
    #expect(webSearchResult.result["sources"]?[0]?["title"]?.stringValue == "Docs")

    let fileSearchResult = try #require(result.toolResults.first { $0.toolName == "file_search" })
    #expect(fileSearchResult.result["queries"]?[0]?.stringValue == "swift ai sdk")
    #expect(fileSearchResult.result["results"]?[0]?["fileId"]?.stringValue == "file_1")
    #expect(fileSearchResult.result["results"]?[0]?["filename"]?.stringValue == "guide.md")
    #expect(fileSearchResult.result["results"]?[0]?["score"]?.doubleValue == 0.91)
    #expect(fileSearchResult.result["results"]?[0]?["text"]?.stringValue == "Relevant chunk")
    #expect(fileSearchResult.result["results"]?[0]?["attributes"]?["topic"]?.stringValue == "docs")

    let codeInterpreterCall = try #require(result.toolCalls.first { $0.name == "code_interpreter" })
    let codeInterpreterInput = try decodeJSONBody(Data(codeInterpreterCall.arguments.utf8))
    #expect(codeInterpreterInput["containerId"]?.stringValue == "cntr_1")
    #expect(codeInterpreterInput["code"]?.stringValue == "print(1)")

    let codeInterpreterResult = try #require(result.toolResults.first { $0.toolName == "code_interpreter" })
    #expect(codeInterpreterResult.result["outputs"]?[0]?["type"]?.stringValue == "logs")
    #expect(codeInterpreterResult.result["outputs"]?[0]?["logs"]?.stringValue == "1\n")
}

@Test func openAIResponsesExtractsLogprobsProviderMetadataLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_67c97c0203188190a025beb4a75242bc","object":"response","created_at":1741257730,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-4o-2024-07-18","output":[{"id":"msg_67c97c02656c81908e080dfdf4a03cd1","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"answer text","annotations":[],"logprobs":[{"token":"Hello","logprob":-0.0009994634,"top_logprobs":[{"token":"Hello","logprob":-0.0009994634},{"token":"Hi","logprob":-0.2}]},{"token":"!","logprob":-0.13410144,"top_logprobs":[{"token":"!","logprob":-0.13410144}]}]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":1,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":345,"input_tokens_details":{"cached_tokens":234},"output_tokens":538,"output_tokens_details":{"reasoning_tokens":123},"total_tokens":572},"user":null,"metadata":{}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: ["openai": ["logprobs": 2]]
    ))

    let logprobs = try #require(result.providerMetadata["openai"]?["logprobs"]?.arrayValue)
    #expect(logprobs.count == 1)
    #expect(logprobs[0][0]?["token"]?.stringValue == "Hello")
    #expect(logprobs[0][0]?["logprob"]?.doubleValue == -0.0009994634)
    #expect(logprobs[0][0]?["top_logprobs"]?[0]?["token"]?.stringValue == "Hello")
    #expect(logprobs[0][0]?["top_logprobs"]?[0]?["logprob"]?.doubleValue == -0.0009994634)
    #expect(logprobs[0][0]?["top_logprobs"]?[1]?["token"]?.stringValue == "Hi")
    #expect(logprobs[0][0]?["top_logprobs"]?[1]?["logprob"]?.doubleValue == -0.2)
    #expect(logprobs[0][1]?["token"]?.stringValue == "!")
    #expect(logprobs[0][1]?["logprob"]?.doubleValue == -0.13410144)
    #expect(logprobs[0][1]?["top_logprobs"]?[0]?["token"]?.stringValue == "!")
    #expect(logprobs[0][1]?["top_logprobs"]?[0]?["logprob"]?.doubleValue == -0.13410144)
}

@Test func openAIResponsesParsesCustomAndComputerUseToolCallsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp-1","status":"completed","output":[{"type":"custom_tool_call","id":"ct_abc123def456","call_id":"call_custom_sql_001","name":"write_sql","input":"SELECT * FROM users WHERE age > 25"},{"type":"computer_call","id":"computer_67cf2b3051e88190b006770db6fdb13d","status":"completed"}],"usage":{"input_tokens":100,"output_tokens":50,"total_tokens":150}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o-mini")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Use tools.")],
        tools: [
            "write_sql": OpenAITools.customTool(name: "write_sql", format: ["type": "grammar", "syntax": "regex", "definition": "SELECT .+"]),
            "computer_use": OpenAITools.computerUse()
        ],
        extraBody: ["toolChoice": ["type": "tool", "toolName": "computer_use"]]
    ))

    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    #expect(body["tool_choice"]?["type"]?.stringValue == "function")
    #expect(body["tool_choice"]?["name"]?.stringValue == "computer_use")

    #expect(result.text == "")
    #expect(result.toolCalls.count == 2)
    #expect(result.toolCalls[0].id == "call_custom_sql_001")
    #expect(result.toolCalls[0].name == "write_sql")
    #expect(result.toolCalls[0].arguments == "\"SELECT * FROM users WHERE age > 25\"")
    #expect(result.toolCalls[0].providerMetadata["openai"]?["itemId"]?.stringValue == "ct_abc123def456")
    #expect(result.toolCalls[1].id == "computer_67cf2b3051e88190b006770db6fdb13d")
    #expect(result.toolCalls[1].name == "computer_use")
    #expect(result.toolCalls[1].arguments == "")
    #expect(result.toolCalls[1].providerExecuted == true)
    #expect(result.toolResults.count == 1)
    #expect(result.toolResults[0].toolCallID == "computer_67cf2b3051e88190b006770db6fdb13d")
    #expect(result.toolResults[0].toolName == "computer_use")
    #expect(result.toolResults[0].result["type"]?.stringValue == "computer_use_tool_result")
    #expect(result.toolResults[0].result["status"]?.stringValue == "completed")
}
@Test func openAIResponsesParsesToolSearchAndMCPResultsLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp-1","status":"completed","output":[{"type":"tool_search_call","id":"tsc_server_1","execution":"server","status":"completed","arguments":{"goal":"Find the weather tool"}},{"type":"tool_search_output","id":"tso_server_1","execution":"server","status":"completed","tools":[{"type":"function","name":"get_weather","description":"Get weather","parameters":{"type":"object","properties":{"location":{"type":"string"}}},"strict":true,"defer_loading":true}]},{"type":"mcp_call","id":"mcp_1","server_label":"docs","name":"search","arguments":"{\\"query\\":\\"swift\\"}","output":"found docs"}],"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.4")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Find a tool and use MCP.")]))

    #expect(result.text == "")
    #expect(result.toolCalls.count == 2)
    #expect(result.toolCalls[0].id == "tsc_server_1")
    #expect(result.toolCalls[0].name == "tool_search")
    #expect(result.toolCalls[0].providerExecuted == true)
    let toolSearchInput = try decodeJSONBody(Data(result.toolCalls[0].arguments.utf8))
    #expect(toolSearchInput["arguments"]?["goal"]?.stringValue == "Find the weather tool")
    #expect(toolSearchInput["call_id"] == .null)
    #expect(result.toolCalls[0].providerMetadata["openai"]?["itemId"]?.stringValue == "tsc_server_1")
    #expect(result.toolCalls[1].id == "mcp_1")
    #expect(result.toolCalls[1].name == "mcp.search")
    #expect(result.toolCalls[1].providerExecuted == true)
    #expect(result.toolCalls[1].dynamic == true)

    #expect(result.toolResults.count == 2)
    #expect(result.toolResults[0].toolCallID == "tsc_server_1")
    #expect(result.toolResults[0].toolName == "tool_search")
    #expect(result.toolResults[0].result["tools"]?[0]?["name"]?.stringValue == "get_weather")
    #expect(result.toolResults[0].providerMetadata["openai"]?["itemId"]?.stringValue == "tso_server_1")
    #expect(result.toolResults[1].toolCallID == "mcp_1")
    #expect(result.toolResults[1].toolName == "mcp.search")
    #expect(result.toolResults[1].dynamic == true)
    #expect(result.toolResults[1].result["type"]?.stringValue == "call")
    #expect(result.toolResults[1].result["serverLabel"]?.stringValue == "docs")
    #expect(result.toolResults[1].result["name"]?.stringValue == "search")
    #expect(result.toolResults[1].result["output"]?.stringValue == "found docs")
    #expect(result.toolResults[1].providerMetadata["openai"]?["itemId"]?.stringValue == "mcp_1")
}
@Test func openAIResponsesParsesMCPApprovalRequests() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp-1","status":"completed","output":[{"type":"mcp_approval_request","id":"mcpr_1","approval_request_id":"approval-1","name":"create_short_url","arguments":"{\\"url\\":\\"https://example.com\\"}"}],"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    let result = try await model.generate(LanguageModelRequest(messages: [.user("Shorten this.")] ))

    #expect(result.text == "")
    #expect(result.toolCalls.count == 1)
    #expect(result.toolCalls[0].id == "id-0")
    #expect(result.toolCalls[0].name == "mcp.create_short_url")
    #expect(result.toolCalls[0].arguments == #"{"url":"https://example.com"}"#)
    #expect(result.toolCalls[0].providerExecuted == true)
    #expect(result.toolCalls[0].dynamic == true)
    #expect(result.toolApprovalRequests.count == 1)
    #expect(result.toolApprovalRequests[0].id == "approval-1")
    #expect(result.toolApprovalRequests[0].toolCallID == "id-0")
    #expect(result.toolApprovalRequests[0].toolName == "mcp.create_short_url")
    #expect(result.toolApprovalRequests[0].arguments == #"{"url":"https://example.com"}"#)
}
