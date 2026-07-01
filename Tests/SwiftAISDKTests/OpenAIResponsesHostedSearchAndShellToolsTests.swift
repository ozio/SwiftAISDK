import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesPreparesLocalShellToolLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use shell.")],
        tools: ["local_shell": OpenAITools.localShell()]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let tool = try #require(body["tools"]?[0])
    #expect(tool["type"]?.stringValue == "local_shell")
}

@Test func openAIResponsesSendsLocalShellRequestBodyLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-codex")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "shell": [
                "type": "provider",
                "id": "openai.local_shell",
                "name": "shell",
                "args": [:]
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "gpt-5-codex")
    #expect(body["include"] == nil)
    #expect(body["input"]?[0]?["role"]?.stringValue == "user")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
    let tool = try #require(body["tools"]?[0])
    #expect(tool["type"]?.stringValue == "local_shell")
}

@Test func openAIResponsesIncludesLocalShellContentLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_68da74aaae58819ca776fbd20244e8df0fdbc19a07110799","object":"response","created_at":1759147178,"status":"completed","background":false,"billing":{"payer":"developer"},"error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5-codex","output":[{"id":"rs_68da74ab2c48819cb435ff526bd1ba1d0fdbc19a07110799","type":"reasoning","summary":[]},{"id":"lsh_68da74abdaec819c9aa19c124308f4600fdbc19a07110799","type":"local_shell_call","status":"completed","action":{"type":"exec","command":["ls"],"env":{},"working_directory":"/root"},"call_id":"call_XWgeTylovOiS8xLNz2TONOgO"}],"parallel_tool_calls":true,"previous_response_id":null,"prompt_cache_key":null,"reasoning":{"effort":"medium","summary":null},"safety_identifier":null,"service_tier":"default","store":true,"temperature":1.0,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[],"top_logprobs":0,"top_p":1.0,"truncation":"disabled","usage":{"input_tokens":407,"input_tokens_details":{"cached_tokens":0},"output_tokens":24,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":431},"user":null,"metadata":{}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-codex")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "shell": [
                "type": "provider",
                "id": "openai.local_shell",
                "name": "shell",
                "args": [:]
            ]
        ]
    ))

    #expect(result.content.count == 2)
    guard case let .reasoning(reasoning, reasoningMetadata) = result.content[0],
          case let .toolCall(toolCall) = result.content[1] else {
        Issue.record("Expected upstream local shell content order")
        return
    }

    #expect(reasoning == "")
    #expect(reasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_68da74ab2c48819cb435ff526bd1ba1d0fdbc19a07110799")
    #expect(toolCall.id == "call_XWgeTylovOiS8xLNz2TONOgO")
    #expect(toolCall.name == "shell")
    #expect(toolCall.providerExecuted == false)
    #expect(toolCall.providerMetadata["openai"]?["itemId"]?.stringValue == "lsh_68da74abdaec819c9aa19c124308f4600fdbc19a07110799")
    let input = try decodeJSONBody(Data(toolCall.arguments.utf8))
    #expect(input["action"]?["type"]?.stringValue == "exec")
    #expect(input["action"]?["command"]?[0]?.stringValue == "ls")
    #expect(input["action"]?["working_directory"]?.stringValue == "/root")
    #expect(input["action"]?["env"]?.objectValue?.isEmpty == true)
}

@Test func openAIResponsesPreparesWebSearchNoOptionsAndExternalAccessFalseLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Search.")],
        tools: [
            "plain_web_search": OpenAITools.webSearch(),
            "restricted_web_search": OpenAITools.webSearch(externalWebAccess: false)
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let tools = try #require(body["tools"]?.arrayValue)
    let webSearchTools = tools.filter { $0["type"]?.stringValue == "web_search" }
    #expect(webSearchTools.count == 2)
    #expect(webSearchTools.contains { $0["external_web_access"] == nil })
    #expect(webSearchTools.contains { $0["external_web_access"]?.boolValue == false })
}

@Test func openAIResponsesSendsWebSearchRequestBodyLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "webSearch": [
                "type": "provider",
                "id": "openai.web_search",
                "name": "webSearch",
                "args": [:]
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "gpt-5-nano")
    #expect(body["include"]?[0]?.stringValue == "web_search_call.action.sources")
    #expect(body["input"]?[0]?["role"]?.stringValue == "user")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
    let tool = try #require(body["tools"]?[0])
    #expect(tool["type"]?.stringValue == "web_search")
}

@Test func openAIResponsesIncludesWebSearchContentLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_0953eda47ee17412006933306199c88195b44f9cf2986e1d5b","object":"response","created_at":1764962401,"status":"completed","background":false,"billing":{"payer":"developer"},"error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5-mini-2025-08-07","output":[{"id":"rs_0953eda47ee1741200693330620ffc8195a85077fdd02c8d2d","type":"reasoning","summary":[]},{"id":"ws_0953eda47ee1741200693330682c988195aaa470a8cc51dfe4","type":"web_search_call","status":"completed","action":{"type":"search","query":"tech news today December 5 2025","sources":[{"type":"url","url":"https://www.theverge.com/podcast/838932/openai-chatgpt-code-red-vergecast"},{"type":"url","url":"https://www.wired.com/story/the-big-interview-2025-recap"},{"type":"url","url":"https://www.barrons.com/articles/stock-movers-7c77880d"},{"type":"url","url":"https://www.investors.com/market-trend/stock-market-today/dow-jones-sp500-nasdaq-inflation-data-ai-stock/"},{"type":"url","url":"https://www.investopedia.com/5-things-to-know-before-the-stock-market-opens-december-5-2025-11862701"},{"type":"url","url":"https://www.investing.com/news/stock-market-news/ai-coding-startup-vercel-raises-300-million-valued-at-93-billion-4264199"},{"type":"url","url":"https://www.finsmes.com/2025/10/vercel-closes-300m-series-f-funding-at-9-3-billion-valuation.html"},{"type":"url","url":"https://vercel.com/blog/series-f"},{"type":"url","url":"https://techstartups.com/2025/12/05/technology-news-today-the-latest-in-tech-ai-startup-news-december-5-2025/"},{"type":"url","url":"https://www.nasdaq.com/press-release/vercel-announces-%24150m-in-series-d-funding-at-a-%242.5b-valuation-to-further-fuel"},{"type":"url","url":"https://www.mexc.com/en-NG/news/77540"},{"type":"url","url":"https://www.theinformation.com/briefings/vercel-lands-unsolicited-investment-offers-9-billion"},{"type":"url","url":"https://www.mexc.com/en-NG/news/us-cloud-platform-vercel-achieves-9-billion-valuation-amid-rapid-growth-in-ai-integration/77540"},{"type":"url","url":"https://www.bloomberg.com/news/articles/2025-09-30/vercel-notches-9-3-billion-valuation-in-latest-ai-funding-round"},{"type":"url","url":"https://www.aol.com/exclusive-vercel-completes-250-million-144101876.html"},{"type":"url","url":"https://www.sentinelone.com/vulnerability-database/cve-2025-49826/"}]}},{"id":"rs_0953eda47ee17412006933306a4f188195b2870a804561da54","type":"reasoning","summary":[]},{"id":"ws_0953eda47ee17412006933306f501c8195b9d3dfba4c547834","type":"web_search_call","status":"completed","action":{"type":"open_page","url":"https://www.theverge.com/podcast/838932/openai-chatgpt-code-red-vergecast"}},{"id":"rs_0953eda47ee174120069333071b0e08195a5b1d1ded4df6f3d","type":"reasoning","summary":[]},{"id":"ws_0953eda47ee1741200693330740e248195a2c77632e480424b","type":"web_search_call","status":"completed","action":{"type":"find_in_page","pattern":"Vercel","url":"https://www.theverge.com/podcast/838932/openai-chatgpt-code-red-vergecast"}},{"id":"rs_0953eda47ee174120069333075d5e48195b354c3bf3d30fb47","type":"reasoning","summary":[]},{"id":"msg_0953eda47ee17412006933308e32f08195bdfb73a410a2abfc","type":"message","status":"completed","content":[{"type":"output_text","annotations":[{"type":"url_citation","end_index":517,"start_index":426,"title":"Why OpenAI declared a code red for ChatGPT | The Verge","url":"https://www.theverge.com/podcast/838932/openai-chatgpt-code-red-vergecast"},{"type":"url_citation","end_index":778,"start_index":647,"title":"Technology News Today – The Latest in Tech, AI & Startup News, December 5, 2025 - Tech Startups","url":"https://techstartups.com/2025/12/05/technology-news-today-the-latest-in-tech-ai-startup-news-december-5-2025/"},{"type":"url_citation","end_index":1047,"start_index":907,"title":"5 Things to Know Before the Stock Market Opens","url":"https://www.investopedia.com/5-things-to-know-before-the-stock-market-opens-december-5-2025-11862701?utm_source=openai"}],"logprobs":[],"text":"Short answer first — yes. I pulled several tech-news pages published today (December 5, 2025) and searched each for the keyword pattern \\"vercel\\". Below is a brief today in tech digest."}],"role":"assistant"}],"parallel_tool_calls":true,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"medium","summary":null},"safety_identifier":null,"service_tier":"default","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"web_search","filters":null,"search_context_size":"medium","user_location":{"type":"approximate","city":null,"country":"US","region":null,"timezone":null}}],"top_logprobs":0,"top_p":1,"truncation":"disabled","usage":{"input_tokens":19681,"input_tokens_details":{"cached_tokens":3712},"output_tokens":3773,"output_tokens_details":{"reasoning_tokens":3136},"total_tokens":23454},"user":null,"metadata":{}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5-nano")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "webSearch": [
                "type": "provider",
                "id": "openai.web_search",
                "name": "webSearch",
                "args": [:]
            ]
        ]
    ))

    #expect(result.content.count == 14)
    guard case let .reasoning(firstReasoning, firstReasoningMetadata) = result.content[0],
          case let .toolCall(searchCall) = result.content[1],
          case let .toolResult(searchResult) = result.content[2],
          case let .reasoning(secondReasoning, secondReasoningMetadata) = result.content[3],
          case let .toolCall(openPageCall) = result.content[4],
          case let .toolResult(openPageResult) = result.content[5],
          case let .reasoning(thirdReasoning, thirdReasoningMetadata) = result.content[6],
          case let .toolCall(findInPageCall) = result.content[7],
          case let .toolResult(findInPageResult) = result.content[8],
          case let .reasoning(fourthReasoning, fourthReasoningMetadata) = result.content[9],
          case let .text(text, textMetadata) = result.content[10],
          case let .source(firstSource) = result.content[11],
          case let .source(secondSource) = result.content[12],
          case let .source(thirdSource) = result.content[13] else {
        Issue.record("Expected upstream web search content order")
        return
    }

    #expect(firstReasoning == "")
    #expect(secondReasoning == "")
    #expect(thirdReasoning == "")
    #expect(fourthReasoning == "")
    #expect(firstReasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_0953eda47ee1741200693330620ffc8195a85077fdd02c8d2d")
    #expect(secondReasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_0953eda47ee17412006933306a4f188195b2870a804561da54")
    #expect(thirdReasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_0953eda47ee174120069333071b0e08195a5b1d1ded4df6f3d")
    #expect(fourthReasoningMetadata["openai"]?["itemId"]?.stringValue == "rs_0953eda47ee174120069333075d5e48195b354c3bf3d30fb47")

    #expect(searchCall.id == "ws_0953eda47ee1741200693330682c988195aaa470a8cc51dfe4")
    #expect(searchCall.name == "webSearch")
    #expect(searchCall.arguments == "{}")
    #expect(searchCall.providerExecuted == true)
    #expect(searchResult.toolCallID == searchCall.id)
    #expect(searchResult.toolName == "webSearch")
    #expect(searchResult.result["action"]?["type"]?.stringValue == "search")
    #expect(searchResult.result["action"]?["query"]?.stringValue == "tech news today December 5 2025")
    #expect(searchResult.result["sources"]?.arrayValue?.count == 16)
    #expect(searchResult.result["sources"]?[0]?["url"]?.stringValue == "https://www.theverge.com/podcast/838932/openai-chatgpt-code-red-vergecast")
    #expect(searchResult.result["sources"]?[7]?["url"]?.stringValue == "https://vercel.com/blog/series-f")

    #expect(openPageCall.id == "ws_0953eda47ee17412006933306f501c8195b9d3dfba4c547834")
    #expect(openPageCall.name == "webSearch")
    #expect(openPageResult.toolCallID == openPageCall.id)
    #expect(openPageResult.toolName == "webSearch")
    #expect(openPageResult.result["action"]?["type"]?.stringValue == "openPage")
    #expect(openPageResult.result["action"]?["url"]?.stringValue == "https://www.theverge.com/podcast/838932/openai-chatgpt-code-red-vergecast")

    #expect(findInPageCall.id == "ws_0953eda47ee1741200693330740e248195a2c77632e480424b")
    #expect(findInPageCall.name == "webSearch")
    #expect(findInPageResult.toolCallID == findInPageCall.id)
    #expect(findInPageResult.toolName == "webSearch")
    #expect(findInPageResult.result["action"]?["type"]?.stringValue == "findInPage")
    #expect(findInPageResult.result["action"]?["pattern"]?.stringValue == "Vercel")

    #expect(text.contains("keyword pattern \"vercel\""))
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_0953eda47ee17412006933308e32f08195bdfb73a410a2abfc")
    #expect(textMetadata["openai"]?["annotations"]?[0]?["title"]?.stringValue == "Why OpenAI declared a code red for ChatGPT | The Verge")
    #expect(firstSource.id == "id-0")
    #expect(firstSource.sourceType == "url")
    #expect(firstSource.title == "Why OpenAI declared a code red for ChatGPT | The Verge")
    #expect(firstSource.url == "https://www.theverge.com/podcast/838932/openai-chatgpt-code-red-vergecast")
    #expect(secondSource.id == "id-1")
    #expect(secondSource.sourceType == "url")
    #expect(secondSource.url == "https://techstartups.com/2025/12/05/technology-news-today-the-latest-in-tech-ai-startup-news-december-5-2025/")
    #expect(thirdSource.id == "id-2")
    #expect(thirdSource.sourceType == "url")
    #expect(thirdSource.url == "https://www.investopedia.com/5-things-to-know-before-the-stock-market-opens-december-5-2025-11862701?utm_source=openai")
}

@Test func openAIResponsesAcceptsWebSearchAPISourcesLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_api_sources","object":"response","created_at":1741631111,"status":"completed","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-4o","output":[{"type":"web_search_call","id":"ws_api_sources","status":"completed","action":{"type":"search","query":"current price of BTC","sources":[{"type":"url","url":"https://example.com?a=1&utm_source=openai"},{"type":"api","name":"oai-finance"}]}},{"type":"message","id":"msg_done","status":"completed","role":"assistant","content":[{"type":"output_text","text":"BTC is trading at ...","annotations":[]}]}],"usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15},"previous_response_id":null,"parallel_tool_calls":true,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[{"type":"web_search","search_context_size":"medium"}],"top_p":1,"truncation":"disabled","user":null,"metadata":{}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "webSearch": [
                "type": "provider",
                "id": "openai.web_search",
                "name": "webSearch",
                "args": [:]
            ]
        ]
    ))

    #expect(result.text == "BTC is trading at ...")
    let toolCall = try #require(result.toolCalls.first { $0.name == "webSearch" })
    #expect(toolCall.id == "ws_api_sources")
    #expect(toolCall.providerExecuted == true)
    let webSearchResult = try #require(result.toolResults.first { $0.toolName == "webSearch" })
    #expect(webSearchResult.toolCallID == "ws_api_sources")
    #expect(webSearchResult.result["action"]?["type"]?.stringValue == "search")
    #expect(webSearchResult.result["action"]?["query"]?.stringValue == "current price of BTC")
    #expect(webSearchResult.result["sources"]?[0]?["type"]?.stringValue == "url")
    #expect(webSearchResult.result["sources"]?[0]?["url"]?.stringValue == "https://example.com?a=1&utm_source=openai")
    #expect(webSearchResult.result["sources"]?[1]?["type"]?.stringValue == "api")
    #expect(webSearchResult.result["sources"]?[1]?["name"]?.stringValue == "oai-finance")
}

@Test func openAIResponsesAcceptsWebSearchCallWithoutActionLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_missing_web_search_action","object":"response","created_at":1741631111,"status":"completed","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-4o","output":[{"type":"web_search_call","id":"ws_missing_action","status":"completed"},{"type":"message","id":"msg_done","status":"completed","role":"assistant","content":[{"type":"output_text","text":"No action payload was returned.","annotations":[]}]}],"usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15},"previous_response_id":null,"parallel_tool_calls":true,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[{"type":"web_search","search_context_size":"medium"}],"top_p":1,"truncation":"disabled","user":null,"metadata":{}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-4o")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "webSearch": [
                "type": "provider",
                "id": "openai.web_search",
                "name": "webSearch",
                "args": [:]
            ]
        ]
    ))

    #expect(result.text == "No action payload was returned.")
    let webSearchResult = try #require(result.toolResults.first { $0.toolName == "webSearch" })
    #expect(webSearchResult.toolCallID == "ws_missing_action")
    #expect(webSearchResult.result == .object([:]))
}

@Test func openAIResponsesDefaultsShellSkillReferenceVersionToLatestLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use a skill.")],
        tools: [
            "shell": OpenAITools.shell(environment: OpenAITools.shellContainerAutoEnvironment(
                skills: [OpenAITools.shellSkillReference(providerReference: ["openai": "skill_abc"])]
            ))
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let skill = try #require(body["tools"]?[0]?["environment"]?["skills"]?[0])
    #expect(skill["type"]?.stringValue == "skill_reference")
    #expect(skill["skill_id"]?.stringValue == "skill_abc")
    #expect(skill["version"]?.stringValue == "latest")
}

@Test func openAIResponsesSendsShellRequestBodyLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "shell": [
                "type": "provider",
                "id": "openai.shell",
                "name": "shell",
                "args": [:]
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "gpt-5.1")
    #expect(body["include"] == nil)
    #expect(body["input"]?[0]?["role"]?.stringValue == "user")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
    let tool = try #require(body["tools"]?[0])
    #expect(tool["type"]?.stringValue == "shell")
}

@Test func openAIResponsesIncludesShellContentLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_0f0d479976b1e9a600692f61be5948819783b655c7a54af2a2","object":"response","created_at":1764712894,"status":"completed","background":false,"billing":{"payer":"developer"},"error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.1-2025-11-13","output":[{"id":"sh_0f0d479976b1e9a600692f61bec0e08197a0864dc5ddf1d38c","type":"shell_call","status":"completed","action":{"commands":["cd ~ && pwd","cd ~/Desktop && pwd","cd ~/Desktop && echo 'THIS WORKS!' > dec1.txt && ls -l dec1.txt && cat dec1.txt"],"max_output_length":9907,"timeout_ms":null},"call_id":"call_udkLUvR8lWvG8cDO2B6GNpvZ"}],"parallel_tool_calls":true,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"none","summary":null},"safety_identifier":null,"service_tier":"default","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"shell"}],"top_logprobs":0,"top_p":1,"truncation":"disabled","usage":{"input_tokens":157,"input_tokens_details":{"cached_tokens":0},"output_tokens":73,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":230},"user":null,"metadata":{}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "shell": [
                "type": "provider",
                "id": "openai.shell",
                "name": "shell",
                "args": [:]
            ]
        ]
    ))

    #expect(result.content.count == 1)
    guard case let .toolCall(toolCall) = result.content[0] else {
        Issue.record("Expected upstream shell tool-call content")
        return
    }

    #expect(toolCall.id == "call_udkLUvR8lWvG8cDO2B6GNpvZ")
    #expect(toolCall.name == "shell")
    #expect(toolCall.providerExecuted == false)
    #expect(toolCall.providerMetadata["openai"]?["itemId"]?.stringValue == "sh_0f0d479976b1e9a600692f61bec0e08197a0864dc5ddf1d38c")
    let input = try decodeJSONBody(Data(toolCall.arguments.utf8))
    #expect(input["action"]?["commands"]?[0]?.stringValue == "cd ~ && pwd")
    #expect(input["action"]?["commands"]?[1]?.stringValue == "cd ~/Desktop && pwd")
    #expect(input["action"]?["commands"]?[2]?.stringValue == "cd ~/Desktop && echo 'THIS WORKS!' > dec1.txt && ls -l dec1.txt && cat dec1.txt")
    #expect(input["action"]?["max_output_length"] == nil)
    #expect(input["action"]?["timeout_ms"] == nil)
}

@Test func openAIResponsesSendsShellContainerRequestBodyLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "shell": [
                "type": "provider",
                "id": "openai.shell",
                "name": "shell",
                "args": [
                    "environment": [
                        "type": "containerAuto"
                    ]
                ]
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["model"]?.stringValue == "gpt-5.2")
    #expect(body["input"]?[0]?["role"]?.stringValue == "user")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
    let tool = try #require(body["tools"]?[0])
    #expect(tool["type"]?.stringValue == "shell")
    #expect(tool["environment"]?["type"]?.stringValue == "container_auto")
}

@Test func openAIResponsesIncludesShellContainerContentLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse("""
    {"id":"resp_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f","object":"response","created_at":1771009000,"status":"completed","background":false,"billing":{"payer":"developer"},"completed_at":1771009005,"error":null,"frequency_penalty":0,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.2-2025-12-11","output":[{"id":"sh_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e50","type":"shell_call","status":"completed","action":{"commands":["echo 'Hello from container!' && uname -a"],"max_output_length":null,"timeout_ms":null},"call_id":"call_abc123def456ghi789jkl012","environment":{"type":"container_reference","container_id":"cntr_aabbccdd11223344556677889900aabb"}},{"id":"sho_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e51","type":"shell_call_output","status":"completed","call_id":"call_abc123def456ghi789jkl012","max_output_length":null,"output":[{"outcome":{"type":"exit","exit_code":0},"stderr":"","stdout":"Hello from container!\\nLinux container-host 6.1.0 #1 SMP x86_64 GNU/Linux\\n"}]},{"id":"msg_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e52","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"The command ran successfully in the container. Here's the output:\\n\\n- The echo command printed: \\"Hello from container!\\"\\n- The system is running Linux (kernel 6.1.0) on an x86_64 architecture."}],"role":"assistant"}],"parallel_tool_calls":true,"presence_penalty":0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"none","summary":null},"safety_identifier":null,"service_tier":"default","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"shell","environment":{"type":"container_reference","container_id":"cntr_aabbccdd11223344556677889900aabb"}}],"top_logprobs":0,"top_p":1,"truncation":"disabled","usage":{"input_tokens":200,"input_tokens_details":{"cached_tokens":0},"output_tokens":120,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":320},"user":null,"metadata":{}}
    """))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "shell": [
                "type": "provider",
                "id": "openai.shell",
                "name": "shell",
                "args": [
                    "environment": [
                        "type": "containerAuto"
                    ]
                ]
            ]
        ]
    ))

    #expect(result.content.count == 3)
    guard case let .toolCall(toolCall) = result.content[0],
          case let .toolResult(toolResult) = result.content[1],
          case let .text(text, textMetadata) = result.content[2] else {
        Issue.record("Expected upstream shell container content order")
        return
    }

    #expect(toolCall.id == "call_abc123def456ghi789jkl012")
    #expect(toolCall.name == "shell")
    #expect(toolCall.providerExecuted == true)
    #expect(toolCall.providerMetadata["openai"]?["itemId"]?.stringValue == "sh_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e50")
    let input = try decodeJSONBody(Data(toolCall.arguments.utf8))
    #expect(input["action"]?["commands"]?[0]?.stringValue == "echo 'Hello from container!' && uname -a")
    #expect(input["action"]?["max_output_length"] == nil)
    #expect(input["action"]?["timeout_ms"] == nil)

    #expect(toolResult.toolCallID == "call_abc123def456ghi789jkl012")
    #expect(toolResult.toolName == "shell")
    #expect(toolResult.result["output"]?[0]?["outcome"]?["type"]?.stringValue == "exit")
    #expect(toolResult.result["output"]?[0]?["outcome"]?["exitCode"]?.intValue == 0)
    #expect(toolResult.result["output"]?[0]?["stderr"]?.stringValue == "")
    #expect(toolResult.result["output"]?[0]?["stdout"]?.stringValue == "Hello from container!\nLinux container-host 6.1.0 #1 SMP x86_64 GNU/Linux\n")

    #expect(text.contains("The command ran successfully in the container."))
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e52")
}

@Test func openAIResponsesSendsShellContainerMultiturnRequestBodyLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesShellContainerMultiturnFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2")

    _ = try await model.generate(LanguageModelRequest(
        messages: openAIResponsesShellContainerMultiturnMessages(),
        tools: [
            "shell": [
                "type": "provider",
                "id": "openai.shell",
                "name": "shell",
                "args": [
                    "environment": [
                        "type": "containerAuto"
                    ]
                ]
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    try #require(input.count == 5)
    #expect(input[0]["role"]?.stringValue == "user")
    #expect(input[0]["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(input[0]["content"]?[0]?["text"]?.stringValue == "Run uname -a")
    #expect(input[1]["type"]?.stringValue == "item_reference")
    #expect(input[1]["id"]?.stringValue == "sh_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e50")
    #expect(input[2]["type"]?.stringValue == "shell_call_output")
    #expect(input[2]["call_id"]?.stringValue == "call_abc123def456ghi789jkl012")
    #expect(input[2]["output"]?[0]?["outcome"]?["type"]?.stringValue == "exit")
    #expect(input[2]["output"]?[0]?["outcome"]?["exit_code"]?.intValue == 0)
    #expect(input[2]["output"]?[0]?["stderr"]?.stringValue == "")
    #expect(input[2]["output"]?[0]?["stdout"]?.stringValue == "Linux container-host 6.1.0 #1 SMP x86_64 GNU/Linux\n")
    #expect(input[3]["type"]?.stringValue == "item_reference")
    #expect(input[3]["id"]?.stringValue == "msg_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e52")
    #expect(input[4]["role"]?.stringValue == "user")
    #expect(input[4]["content"]?[0]?["text"]?.stringValue == "What architecture do you run in?")
    #expect(body["model"]?.stringValue == "gpt-5.2")
    #expect(body["tools"]?[0]?["type"]?.stringValue == "shell")
    #expect(body["tools"]?[0]?["environment"]?["type"]?.stringValue == "container_auto")
}

@Test func openAIResponsesReturnsShellContainerMultiturnTextLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesShellContainerMultiturnFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2")

    let result = try await model.generate(LanguageModelRequest(
        messages: openAIResponsesShellContainerMultiturnMessages(),
        tools: [
            "shell": [
                "type": "provider",
                "id": "openai.shell",
                "name": "shell",
                "args": [
                    "environment": [
                        "type": "containerAuto"
                    ]
                ]
            ]
        ]
    ))

    #expect(result.content.count == 1)
    guard case let .text(text, providerMetadata) = result.content[0] else {
        Issue.record("Expected upstream shell container multiturn text content")
        return
    }
    #expect(text == "`x86_64` (64-bit x86 / AMD64).")
    #expect(providerMetadata["openai"]?["itemId"]?.stringValue == "msg_0fc28e14d2bb7565006994e621f78481919e9fa42a95ce6b6c")
}

@Test func openAIResponsesSendsShellLocalMultiturnRequestBodyLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesShellLocalMultiturnFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2")

    _ = try await model.generate(LanguageModelRequest(
        messages: openAIResponsesShellLocalMultiturnMessages(),
        tools: [
            "shell": [
                "type": "provider",
                "id": "openai.shell",
                "name": "shell",
                "args": [:]
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let input = try #require(body["input"]?.arrayValue)
    try #require(input.count == 5)
    #expect(input[0]["role"]?.stringValue == "user")
    #expect(input[0]["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(input[0]["content"]?[0]?["text"]?.stringValue == "Run uname -a")
    #expect(input[1]["type"]?.stringValue == "item_reference")
    #expect(input[1]["id"]?.stringValue == "sh_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e50")
    #expect(input[2]["type"]?.stringValue == "shell_call_output")
    #expect(input[2]["call_id"]?.stringValue == "call_abc123def456ghi789jkl012")
    #expect(input[2]["output"]?[0]?["outcome"]?["type"]?.stringValue == "exit")
    #expect(input[2]["output"]?[0]?["outcome"]?["exit_code"]?.intValue == 0)
    #expect(input[2]["output"]?[0]?["stderr"]?.stringValue == "")
    #expect(input[2]["output"]?[0]?["stdout"]?.stringValue == "Darwin mac-host 24.6.0 Darwin Kernel Version 24.6.0 root:xnu-11417.60.45.601.5~1/RELEASE_ARM64_T6041 arm64\n")
    #expect(input[3]["type"]?.stringValue == "item_reference")
    #expect(input[3]["id"]?.stringValue == "msg_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e52")
    #expect(input[4]["role"]?.stringValue == "user")
    #expect(input[4]["content"]?[0]?["text"]?.stringValue == "What architecture do you run in?")
    #expect(body["model"]?.stringValue == "gpt-5.2")
    #expect(body["tools"]?[0]?["type"]?.stringValue == "shell")
    #expect(body["tools"]?[0]?["environment"] == nil)
}

@Test func openAIResponsesReturnsShellLocalMultiturnTextLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesShellLocalMultiturnFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2")

    let result = try await model.generate(LanguageModelRequest(
        messages: openAIResponsesShellLocalMultiturnMessages(),
        tools: [
            "shell": [
                "type": "provider",
                "id": "openai.shell",
                "name": "shell",
                "args": [:]
            ]
        ]
    ))

    #expect(result.content.count == 1)
    guard case let .text(text, providerMetadata) = result.content[0] else {
        Issue.record("Expected upstream shell local multiturn text content")
        return
    }
    #expect(text == "`arm64` (Apple Silicon).")
    #expect(providerMetadata["openai"]?["itemId"]?.stringValue == "msg_06a97f431a8c75fa006994e832264081908b782fc114dcad69")
}

@Test func openAIResponsesSendsShellEnvironmentRequestBodyLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesShellSkillsFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "shell": [
                "type": "provider",
                "id": "openai.shell",
                "name": "shell",
                "args": [
                    "environment": [
                        "type": "containerAuto"
                    ]
                ]
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    #expect(body["input"]?[0]?["role"]?.stringValue == "user")
    #expect(body["input"]?[0]?["content"]?[0]?["type"]?.stringValue == "input_text")
    #expect(body["input"]?[0]?["content"]?[0]?["text"]?.stringValue == "Hello")
    #expect(body["model"]?.stringValue == "gpt-5.2")
    #expect(body["tools"]?[0]?["type"]?.stringValue == "shell")
    #expect(body["tools"]?[0]?["environment"]?["type"]?.stringValue == "container_auto")
}

@Test func openAIResponsesIncludesShellEnvironmentContentLikeUpstream() async throws {
    let transport = RecordingTransport(response: openAIResponsesShellSkillsFixtureResponse())
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.2")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Hello")],
        tools: [
            "shell": [
                "type": "provider",
                "id": "openai.shell",
                "name": "shell",
                "args": [
                    "environment": [
                        "type": "containerAuto"
                    ]
                ]
            ]
        ]
    ))

    #expect(result.content.count == 5)
    guard case let .toolCall(firstCall) = result.content[0],
          case let .toolResult(firstResult) = result.content[1],
          case let .toolCall(secondCall) = result.content[2],
          case let .toolResult(secondResult) = result.content[3],
          case let .text(text, textMetadata) = result.content[4] else {
        Issue.record("Expected upstream shell environment content order")
        return
    }

    #expect(firstCall.id == "call_KPDqtcOSQeaV3UKcb30ZfeqD")
    #expect(firstCall.name == "shell")
    #expect(firstCall.providerExecuted == true)
    #expect(firstCall.providerMetadata["openai"]?["itemId"]?.stringValue == "sh_01b6b3812d7541bd00698f71a351a08196acffc9543b76a179")
    #expect(try decodeJSONBody(Data(firstCall.arguments.utf8))["action"]?["commands"]?[0]?.stringValue == "ls -R /home/oai/skills/island-rescue-ab6238cd308ce72a5ae69fd3ba1e3aeb")
    #expect(firstResult.toolCallID == "call_KPDqtcOSQeaV3UKcb30ZfeqD")
    #expect(firstResult.toolName == "shell")
    #expect(firstResult.result["output"]?[0]?["outcome"]?["exitCode"]?.intValue == 0)
    #expect(firstResult.result["output"]?[0]?["stderr"]?.stringValue == "")
    #expect(firstResult.result["output"]?[0]?["stdout"]?.stringValue == "/home/oai/skills/island-rescue-ab6238cd308ce72a5ae69fd3ba1e3aeb:\nSKILL.md\n")

    #expect(secondCall.id == "call_5RmHRaiiFm8rPqUBqqXjG4WA")
    #expect(secondCall.name == "shell")
    #expect(secondCall.providerExecuted == true)
    #expect(secondCall.providerMetadata["openai"]?["itemId"]?.stringValue == "sh_01b6b3812d7541bd00698f71a4c0e88196b89199531ef2ee07")
    #expect(try decodeJSONBody(Data(secondCall.arguments.utf8))["action"]?["commands"]?[0]?.stringValue == "sed -n '1,200p' /home/oai/skills/island-rescue-ab6238cd308ce72a5ae69fd3ba1e3aeb/SKILL.md")
    #expect(secondResult.toolCallID == "call_5RmHRaiiFm8rPqUBqqXjG4WA")
    #expect(secondResult.toolName == "shell")
    #expect(secondResult.result["output"]?[0]?["outcome"]?["exitCode"]?.intValue == 0)
    #expect(secondResult.result["output"]?[0]?["stderr"]?.stringValue == "")
    #expect(secondResult.result["output"]?[0]?["stdout"]?.stringValue?.contains("name: island-rescue") == true)

    #expect(text == openAIResponsesShellSkillsResponseText())
    #expect(textMetadata["openai"]?["itemId"]?.stringValue == "msg_01b6b3812d7541bd00698f71a5de488196b6ae435d1a54ed9c")
}

