import Foundation
import Testing
@testable import SwiftAISDK


func recordedOpenAIResponsesBody(
    modelID: String = "gpt-5.1",
    tools: [String: JSONValue],
    extraBody: [String: JSONValue] = [:],
    providerOptions: [String: JSONValue] = [:],
    toolChoice: JSONValue? = nil
) async throws -> [String: JSONValue] {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel(modelID)

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use tools.")],
        tools: tools,
        toolChoice: toolChoice,
        providerOptions: providerOptions,
        extraBody: extraBody
    ))

    let request = try #require((await transport.requests()).first)
    let body = try decodeJSONBody(try #require(request.body))
    return try #require(body.objectValue)
}

func openAIResponsesFixtureData(_ filename: String) throws -> Data {
    let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/OpenAIResponses/\(filename)")
    return try Data(contentsOf: fixtureURL)
}

func openAIResponsesFixtureJSON(_ filename: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: openAIResponsesFixtureData(filename))
}

func openAIResponsesFixtureResponse(_ filename: String) throws -> AIHTTPResponse {
    AIHTTPResponse(
        statusCode: 200,
        headers: ["content-type": "application/json"],
        body: try openAIResponsesFixtureData(filename)
    )
}

func openAIResponsesUpstreamFunctionTools() -> [String: JSONValue] {
    [
        "weather": [
            "type": "object",
            "description": "Get the weather in a location",
            "properties": [
                "location": [
                    "type": "string",
                    "description": "The location to get the weather for"
                ]
            ],
            "required": ["location"],
            "additionalProperties": false
        ],
        "cityAttractions": [
            "type": "object",
            "properties": [
                "city": ["type": "string"]
            ],
            "required": ["city"],
            "additionalProperties": false
        ]
    ]
}

func openAIResponsesUpstreamToolCallsFixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_67c97c0203188190a025beb4a75242bc","object":"response","created_at":1741257730,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-4o-2024-07-18","output":[{"type":"function_call","id":"fc_67caf7f4c1ec8190b27edfb5580cfd31","call_id":"call_0NdsJqOS8N3J9l2p0p4WpYU9","name":"weather","arguments":"{\\"location\\":\\"San Francisco\\"}","status":"completed"},{"type":"function_call","id":"fc_67caf7f5071c81908209c2909c77af05","call_id":"call_gexo0HtjUfmAIW4gjNOgyrcr","name":"cityAttractions","arguments":"{\\"city\\":\\"San Francisco\\"}","status":"completed"}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":1,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[{"type":"function","description":"Get the weather in a location","name":"weather","parameters":{"type":"object","properties":{"location":{"type":"string","description":"The location to get the weather for"}},"required":["location"],"additionalProperties":false},"strict":true},{"type":"function","description":null,"name":"cityAttractions","parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"],"additionalProperties":false},"strict":true}],"top_p":1,"truncation":"disabled","usage":{"input_tokens":34,"output_tokens":538,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":572},"user":null,"metadata":{}}
    """)
}

func openAIResponsesClientToolSearchFixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_01166e06cf473fc80169ab66e9ce7c8196aa77df57a31b8230","object":"response","created_at":1772840681,"status":"completed","background":false,"billing":{"payer":"developer"},"completed_at":1772840682,"error":null,"frequency_penalty":0,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.4-2026-03-05","output":[{"id":"tsc_01166e06cf473fc80169ab66ea404881968795bb327c429d35","type":"tool_search_call","status":"completed","arguments":{"goal":"Find a tool to get current weather for San Francisco"},"call_id":"call_AEvXZ1rvYpxHh8QZb7wGlTGH","execution":"client"}],"parallel_tool_calls":true,"presence_penalty":0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"none","summary":null},"safety_identifier":null,"service_tier":"default","store":false,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"function","defer_loading":true,"description":"Get the current weather at a specific location","name":"get_weather","parameters":{"type":"object","properties":{"location":{"type":"string","description":"The city and state, e.g. San Francisco, CA"},"unit":{"type":"string","enum":["celsius","fahrenheit"],"description":"Temperature unit"}},"required":["location","unit"],"additionalProperties":false},"strict":true},{"type":"function","defer_loading":true,"description":"Search through files in the workspace","name":"search_files","parameters":{"type":"object","properties":{"query":{"type":"string","description":"The search query"},"file_types":{"type":"array","items":{"type":"string"},"description":"Filter by file types"}},"required":["query","file_types"],"additionalProperties":false},"strict":true},{"type":"tool_search","description":"Search for available tools based on what the user needs.","execution":"client","parameters":{"type":"object","properties":{"goal":{"type":"string","description":"What the user is trying to accomplish"}},"required":["goal"],"additionalProperties":false}}],"top_logprobs":0,"top_p":0.98,"truncation":"disabled","usage":{"input_tokens":65,"input_tokens_details":{"cached_tokens":0},"output_tokens":28,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":93},"user":null,"metadata":{}}
    """)
}

func openAIResponsesClientToolSearchTools() -> [String: JSONValue] {
    [
        "toolSearch": [
            "type": "provider",
            "id": "openai.tool_search",
            "name": "toolSearch",
            "args": [
                "execution": "client",
                "description": "Search for available tools based on what the user needs.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "goal": [
                            "type": "string",
                            "description": "What the user is trying to accomplish"
                        ]
                    ],
                    "required": ["goal"],
                    "additionalProperties": false
                ]
            ]
        ],
        "get_weather": [
            "type": "function",
            "description": "Get the current weather at a specific location",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "location": ["type": "string"],
                    "unit": ["type": "string", "enum": ["celsius", "fahrenheit"]]
                ],
                "required": ["location", "unit"],
                "additionalProperties": false
            ],
            "strict": true,
            "providerOptions": [
                "openai": ["deferLoading": true]
            ]
        ]
    ]
}

func openAIResponsesMCPTool() -> [String: JSONValue] {
    [
        "MCP": [
            "type": "provider",
            "id": "openai.mcp",
            "name": "MCP",
            "args": [
                "serverLabel": "dmcp",
                "serverUrl": "https://mcp.exa.ai/mcp",
                "serverDescription": "A web-search API for AI agents"
            ]
        ]
    ]
}

func openAIResponsesMCPToolFixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_0a4801d792de11eb00690ccb8559c48197aec5714d3995da76","object":"response","created_at":1762424221,"status":"completed","background":false,"billing":{"payer":"developer"},"completed_at":1762424227,"error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5-mini-2025-08-07","output":[{"id":"mcpl_0a4801d792de11eb00690ccb8559c48197aec5714d3995da77","type":"mcp_list_tools","server_label":"dmcp","tools":[{"name":"web_search_exa","description":"Search the web using Exa AI","input_schema":{"type":"object","properties":{"query":{"type":"string"},"numResults":{"type":"number"}}}},{"name":"get_code_context_exa","description":"Get code context using Exa AI","input_schema":{"type":"object","properties":{"query":{"type":"string"}}}}]},{"id":"rs_0a4801d792de11eb00690ccb8775988197b6c6f6d3f6882f5e","type":"reasoning","summary":[]},{"id":"mcp_0a4801d792de11eb00690ccb8c3fac8197a4fd94f4528cd432","type":"mcp_call","status":"completed","approval_request_id":null,"arguments":"{\\"query\\":\\"NYC mayoral election results 2025 latest\\",\\"numResults\\":5}","error":null,"name":"web_search_exa","output":"{\\"requestId\\":\\"c72ab09f496225ba33162f7aca08ef60\\",\\"autoDate\\":\\"2025-01-01T00:00:00.000Z\\",\\"resolvedSearchType\\":\\"neural\\",\\"results\\":[{\\"id\\":\\"https://www.nbcnews.com/politics/2025-elections/new-york-city-mayor-results\\",\\"title\\":\\"New York City Mayor Results 2025\\",\\"url\\":\\"https://www.nbcnews.com/politics/2025-elections/new-york-city-mayor-results\\"}]}","server_label":"dmcp"},{"id":"rs_0a4801d792de11eb00690ccb937c208197be08d2d715b7a1a0","type":"reasoning","summary":[]},{"id":"msg_0a4801d792de11eb00690ccb9aec948197aa075d716ac02575","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"Yes — the latest results (from Nov 4–6, 2025) show Zohran Mamdani projected as the winner of the 2025 New York City mayoral election."}],"role":"assistant"}],"parallel_tool_calls":true,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"medium","summary":null},"safety_identifier":null,"service_tier":"default","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"mcp","server_label":"dmcp","server_url":"https://mcp.exa.ai/mcp","server_description":"A web-search API for AI agents","require_approval":"never"}],"top_logprobs":0,"top_p":1,"truncation":"disabled","usage":{"input_tokens":178,"input_tokens_details":{"cached_tokens":0},"output_tokens":1024,"output_tokens_details":{"reasoning_tokens":256},"total_tokens":1202},"user":null,"metadata":{}}
    """)
}

func openAIResponsesMCPApprovalTool() -> [String: JSONValue] {
    [
        "MCP": [
            "type": "provider",
            "id": "openai.mcp",
            "name": "MCP",
            "args": [
                "serverLabel": "zip1",
                "serverUrl": "https://zip1.io/mcp",
                "serverDescription": "Link shortener",
                "requireApproval": "always"
            ]
        ]
    ]
}

func openAIResponsesMCPApprovalTurn1FixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_04f6b17429cf2b02006949a66c2518819686bc9f637cdd81f2","object":"response","created_at":1756270636,"status":"completed","background":false,"billing":{"payer":"developer"},"completed_at":1756270638,"error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5-mini-2025-08-07","output":[{"id":"mcpl_04f6b17429cf2b02006949a66d64188196993ab2bed8e07268","type":"mcp_list_tools","server_label":"zip1","tools":[{"name":"create_short_url","description":"Create a short URL","input_schema":{"type":"object","properties":{"url":{"type":"string"},"alias":{"type":"string"},"password":{"type":"string"},"description":{"type":"string"},"max_clicks":{"type":"number"}}}}]},{"id":"rs_04f6b17429cf2b02006949a66f4df88196a44362d8a21f9cea","type":"reasoning","summary":[]},{"id":"mcpr_04f6b17429cf2b02006949a6712b1081968b3c7a72dec695d8","type":"mcp_approval_request","name":"create_short_url","arguments":"{\\"alias\\":\\"\\",\\"description\\":\\"\\",\\"max_clicks\\":100,\\"password\\":\\"\\",\\"url\\":\\"https://ai-sdk.dev/\\"}","server_label":"zip1"}],"parallel_tool_calls":true,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"medium","summary":null},"safety_identifier":null,"service_tier":"default","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"mcp","server_label":"zip1","server_url":"https://zip1.io/mcp","server_description":"Link shortener","require_approval":"always"}],"top_logprobs":0,"top_p":1,"truncation":"disabled","usage":{"input_tokens":157,"input_tokens_details":{"cached_tokens":0},"output_tokens":82,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":239},"user":null,"metadata":{}}
    """)
}

func openAIResponsesMCPApprovalTurn2FixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_04f6b17429cf2b02006949a6724ac081969c1e0f1e89f4406","object":"response","created_at":1756270638,"status":"completed","background":false,"billing":{"payer":"developer"},"completed_at":1756270640,"error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5-mini-2025-08-07","output":[{"id":"mcpl_04f6b17429cf2b02006949a673fd08819695f8f57cdb9bed6f","type":"mcp_list_tools","server_label":"zip1","tools":[{"name":"create_short_url","description":"Create a short URL","input_schema":{"type":"object","properties":{"url":{"type":"string"},"alias":{"type":"string"},"password":{"type":"string"},"description":{"type":"string"},"max_clicks":{"type":"number"}}}}]},{"id":"rs_04f6b17429cf2b02006949a67543c88196ad1f56cb7c8fe476","type":"reasoning","summary":[]},{"id":"msg_04f6b17429cf2b02006949a679f35c81968e9b234489fa32b8","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"I couldn't create the short link because the shortening tool call was not approved. Do you want me to proceed and create a short URL on zip1.io with max clicks = 100? If yes, please confirm and optionally provide:\\n- a custom alias (alphanumeric and hyphens only), and/or\\n- a password, and/or\\n- a short description.\\n\\nIf you don't want me to use the tool, I can give instructions so you can shorten it yourself."}],"role":"assistant"}],"parallel_tool_calls":true,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"medium","summary":null},"safety_identifier":null,"service_tier":"default","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"mcp","server_label":"zip1","server_url":"https://zip1.io/mcp","server_description":"Link shortener","require_approval":"always"}],"top_logprobs":0,"top_p":1,"truncation":"disabled","usage":{"input_tokens":190,"input_tokens_details":{"cached_tokens":0},"output_tokens":118,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":308},"user":null,"metadata":{}}
    """)
}

func openAIResponsesMCPApprovalTurn3FixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_04f6b17429cf2b02006949a687a818196a3dcc9d4011397f","object":"response","created_at":1756270642,"status":"completed","background":false,"billing":{"payer":"developer"},"completed_at":1756270644,"error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5-mini-2025-08-07","output":[{"id":"mcpl_04f6b17429cf2b02006949a688cc6481969f74af86ec648d15","type":"mcp_list_tools","server_label":"zip1","tools":[{"name":"create_short_url","description":"Create a short URL","input_schema":{"type":"object","properties":{"url":{"type":"string"},"alias":{"type":"string"},"password":{"type":"string"},"description":{"type":"string"},"max_clicks":{"type":"number"}}}}]},{"id":"rs_04f6b17429cf2b02006949a68a9c7c8196b850018869363b06","type":"reasoning","summary":[]},{"id":"mcpr_04f6b17429cf2b02006949a68bf5808196b6f2008a315c9aa4","type":"mcp_approval_request","name":"create_short_url","arguments":"{\\"alias\\":\\"\\",\\"description\\":\\"\\",\\"max_clicks\\":100,\\"password\\":\\"\\",\\"url\\":\\"https://ai-sdk.dev/\\"}","server_label":"zip1"}],"parallel_tool_calls":true,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"medium","summary":null},"safety_identifier":null,"service_tier":"default","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"mcp","server_label":"zip1","server_url":"https://zip1.io/mcp","server_description":"Link shortener","require_approval":"always"}],"top_logprobs":0,"top_p":1,"truncation":"disabled","usage":{"input_tokens":244,"input_tokens_details":{"cached_tokens":0},"output_tokens":77,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":321},"user":null,"metadata":{}}
    """)
}

func openAIResponsesMCPApprovalTurn4FixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_04f6b17429cf2b02006949a68d5778196a889b2cf51545bbe","object":"response","created_at":1756270645,"status":"completed","background":false,"billing":{"payer":"developer"},"completed_at":1756270648,"error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5-mini-2025-08-07","output":[{"id":"mcpl_04f6b17429cf2b02006949a68ebc288196ad7b23d6c452775a","type":"mcp_list_tools","server_label":"zip1","tools":[{"name":"create_short_url","description":"Create a short URL","input_schema":{"type":"object","properties":{"url":{"type":"string"},"alias":{"type":"string"},"password":{"type":"string"},"description":{"type":"string"},"max_clicks":{"type":"number"}}}}]},{"id":"mcp_04f6b17429cf2b02006949a6908fc4819686c02f71f7faecc6","type":"mcp_call","status":"completed","approval_request_id":"mcpr_04f6b17429cf2b02006949a68bf5808196b6f2008a315c9aa4","name":"create_short_url","arguments":"{\\"alias\\":\\"\\",\\"description\\":\\"\\",\\"max_clicks\\":100,\\"password\\":\\"\\",\\"url\\":\\"https://ai-sdk.dev/\\"}","output":"✅ Short URL created: https://zip1.io/oMAchr\\n🔤 Generated code: oMAchr\\n🔢 Max clicks: 100\\n🔗 Original URL: https://ai-sdk.dev/\\n\\n📊 View stats: https://zip1.io/stats/oMAchr","server_label":"zip1"},{"id":"msg_04f6b17429cf2b02006949a6930b308196a3ad4f35aa6e0b1b","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"Done — I created a short link for you.\\n\\nShort URL: https://zip1.io/oMAchr\\nOriginal URL: https://ai-sdk.dev/\\nMax clicks: 100\\nStats page: https://zip1.io/stats/oMAchr\\n\\nWould you like a custom alias, password protection, or a description added to this short link?"}],"role":"assistant"}],"parallel_tool_calls":true,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"medium","summary":null},"safety_identifier":null,"service_tier":"default","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"mcp","server_label":"zip1","server_url":"https://zip1.io/mcp","server_description":"Link shortener","require_approval":"always"}],"top_logprobs":0,"top_p":1,"truncation":"disabled","usage":{"input_tokens":202,"input_tokens_details":{"cached_tokens":0},"output_tokens":148,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":350},"user":null,"metadata":{}}
    """)
}

func openAIResponsesFileSearchTool() -> [String: JSONValue] {
    [
        "fileSearch": [
            "type": "provider",
            "id": "openai.file_search",
            "name": "fileSearch",
            "args": [
                "vectorStoreIds": ["vs_68caad8bd5d88191ab766cf043d89a18"],
                "maxNumResults": 5,
                "filters": [
                    "key": "author",
                    "type": "eq",
                    "value": "Jane Smith"
                ],
                "ranking": [
                    "ranker": "auto",
                    "scoreThreshold": 0.5
                ]
            ]
        ]
    ]
}

func openAIResponsesFileSearchWithoutResultsFixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_0a098396a8feca410068caae39e7648196b346e99fa8ec494c","object":"response","created_at":1758113338,"status":"completed","background":false,"error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5-mini-2025-08-07","output":[{"id":"rs_0a098396a8feca410068caae3b47208196957fe59419daad70","type":"reasoning","summary":[]},{"id":"fs_0a098396a8feca410068caae3cab5c8196a54fd00498464e62","type":"file_search_call","status":"completed","queries":["What is an embedding model according to this document?","What is an embedding model?","definition of embedding model in the document","embedding model description"],"results":null},{"id":"rs_0a098396a8feca410068caae3e21a081968e7ac588401c4a6a","type":"reasoning","summary":[]},{"id":"msg_0a098396a8feca410068caae457c508196b2fcd079d1d3ec74","type":"message","status":"completed","content":[{"type":"output_text","annotations":[{"type":"file_citation","file_id":"file-Ebzhf8H4DPGPr9pUhr7n7v","filename":"ai.pdf","index":438}],"logprobs":[],"text":"According to the document, an embedding model is used to convert complex data (like words or images) into a dense vector (a list of numbers) representation called an embedding, which captures semantic and syntactic relationships. Unlike generative models, embedding models do not generate new text or data; instead, they provide these vector representations to be used as input for other models or other natural language processing tasks ."}],"role":"assistant"}],"parallel_tool_calls":true,"previous_response_id":null,"prompt_cache_key":null,"reasoning":{"effort":"medium","summary":null},"safety_identifier":null,"service_tier":"default","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"file_search","filters":null,"max_num_results":20,"ranking_options":{"ranker":"auto","score_threshold":0},"vector_store_ids":["vs_68caad8bd5d88191ab766cf043d89a18"]}],"top_logprobs":0,"top_p":1,"truncation":"disabled","usage":{"input_tokens":3700,"input_tokens_details":{"cached_tokens":2560},"output_tokens":741,"output_tokens_details":{"reasoning_tokens":640},"total_tokens":4441},"user":null,"metadata":{}}
    """)
}

func openAIResponsesFileSearchWithResultsFixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_0365d26c32c64c650068cabb02fea4819495862c2bc58440ad","object":"response","created_at":1758116611,"status":"completed","background":false,"error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5-mini-2025-08-07","output":[{"id":"rs_0365d26c32c64c650068cabb03bcc48194bfbd973152bca8f6","type":"reasoning","summary":[]},{"id":"fs_0365d26c32c64c650068cabb04aa388194b53c59de50a3951e","type":"file_search_call","status":"completed","queries":["What is an embedding model according to this document?","What is an embedding model in the document?","definition of embedding model","embedding model explanation 'embedding model'"],"results":[{"attributes":{},"file_id":"file-Ebzhf8H4DPGPr9pUhr7n7v","filename":"ai.pdf","score":0.9311,"text":"AI 1\\n\\nAI\\nGenerative artificial intelligence refers to models that predict and generate \\nvarious types of outputs (such as text, images, or audio) based on whatʼs \\nstatistically likely, pulling from patterns theyʼve learned from their training data. \\nFor example:\\n\\nGiven a photo, a generative model can generate a caption.\\n\\nGiven an audio file, a generative model can generate a transcription.\\n\\nGiven a text description, a generative model can generate an image.\\n\\nA large language model LLM is a subset of generative models focused \\nprimarily on text. An LLM takes a sequence of words as input and aims to \\npredict the most likely sequence to follow. It assigns probabilities to potential \\nnext sequences and then selects one. The model continues to generate \\nsequences until it meets a specified stopping criterion.\\n\\nLLMs learn by training on massive collections of written text, which means they \\nwill be better suited to some use cases than others. For example, a model \\ntrained on GitHub data would understand the probabilities of sequences in \\nsource code particularly well.\\n\\nHowever, it's crucial to understand LLMs' limitations. When asked about less \\nknown or absent information, like the birthday of a personal relative, LLMs \\nmight \\"hallucinate\\" or make up information. It's essential to consider how well-\\nrepresented the information you need is in the model.\\n\\nAn embedding model is used to convert complex data (like words or images) \\ninto a dense vector (a list of numbers) representation, known as an embedding. \\nUnlike generative models, embedding models do not generate new text or data. \\nInstead, they provide representations of semantic and synactic relationships \\nbetween entities that can be used as input for other models or other natural \\nlanguage processing tasks.\\n\\nIn the next section, you will learn about the difference between models \\nproviders and models, and which ones are available in the AI SDK."}]},{"id":"rs_0365d26c32c64c650068cabb061740819491324d349d0f07ca","type":"reasoning","summary":[]},{"id":"msg_0365d26c32c64c650068cabb0e66b081949f66f61dacef39f3","type":"message","status":"completed","content":[{"type":"output_text","annotations":[{"type":"file_citation","file_id":"file-Ebzhf8H4DPGPr9pUhr7n7v","filename":"ai.pdf","index":350}],"logprobs":[],"text":"According to the document, an embedding model converts complex data (like words or images) into a dense vector — a list of numbers — called an embedding. It does not generate new text or data; instead it encodes semantic and syntactic relationships between entities so those vector representations can be used as inputs for other models or NLP tasks ."}],"role":"assistant"}],"parallel_tool_calls":true,"previous_response_id":null,"prompt_cache_key":null,"reasoning":{"effort":"medium","summary":null},"safety_identifier":null,"service_tier":"default","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"file_search","filters":null,"max_num_results":20,"ranking_options":{"ranker":"auto","score_threshold":0},"vector_store_ids":["vs_68caad8bd5d88191ab766cf043d89a18"]}],"top_logprobs":0,"top_p":1,"truncation":"disabled","usage":{"input_tokens":3678,"input_tokens_details":{"cached_tokens":2304},"output_tokens":536,"output_tokens_details":{"reasoning_tokens":448},"total_tokens":4214},"user":null,"metadata":{}}
    """)
}

func openAIResponsesApplyPatchFixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_0b04c5f8dfc43af500692749bc5b288197b45e830995fd32d3","object":"response","created_at":1764182460,"status":"completed","background":false,"billing":{"payer":"developer"},"error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.1-2025-11-13","output":[{"id":"apc_0b04c5f8dfc43af500692749bd60908197b0e453c38f30191a","type":"apply_patch_call","status":"completed","call_id":"call_CdXiGtcRl49Q6Ek20tG9lYOr","operation":{"type":"create_file","diff":"+## Shopping Checklist\\n+\\n+- [ ] Milk\\n+- [ ] Bread\\n+- [ ] Eggs\\n+- [ ] Apples\\n+- [ ] Coffee\\n+\\n","path":"shopping-checklist.md"}}],"parallel_tool_calls":true,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"none","summary":null},"safety_identifier":null,"service_tier":"default","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"apply_patch"}],"top_logprobs":0,"top_p":1,"truncation":"disabled","usage":{"input_tokens":642,"input_tokens_details":{"cached_tokens":0},"output_tokens":67,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":709},"user":null,"metadata":{}}
    """)
}

func openAIResponsesCustomToolFixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_custom_tool_test","object":"response","created_at":1741630255,"status":"completed","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-5.2-codex","output":[{"type":"custom_tool_call","id":"ct_abc123def456","call_id":"call_custom_sql_001","name":"write_sql","input":"SELECT * FROM users WHERE age > 25","status":"completed"}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":1,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[{"type":"custom","name":"write_sql","description":"Write a SQL SELECT query to answer the user question.","format":{"type":"grammar","syntax":"regex","definition":"SELECT .+"}}],"top_p":1,"truncation":"disabled","usage":{"input_tokens":25,"output_tokens":15,"total_tokens":40},"user":null,"metadata":{}}
    """)
}

func openAIResponsesComputerUseFixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_computer_test","object":"response","created_at":1741630255,"status":"completed","error":null,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"model":"gpt-4o-mini","output":[{"type":"computer_call","id":"computer_67cf2b3051e88190b006770db6fdb13d","status":"completed"},{"type":"message","id":"msg_computer_test","status":"completed","role":"assistant","content":[{"type":"output_text","text":"I've completed the computer task.","annotations":[]}]}],"usage":{"input_tokens":100,"output_tokens":50}}
    """)
}

func openAIResponsesMixedCitationsFixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_123","object":"response","created_at":1234567890,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-4o","output":[{"id":"msg_123","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Based on web search and file content.","annotations":[{"type":"url_citation","start_index":0,"end_index":10,"url":"https://example.com","title":"Example URL"},{"type":"file_citation","file_id":"file-abc123","filename":"resource1.json","index":123}]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":100,"input_tokens_details":{"cached_tokens":0},"output_tokens":50,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":150},"user":null,"metadata":{}}
    """)
}

func openAIResponsesFileCitationOnlyFixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_456","object":"response","created_at":1234567890,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-4o","output":[{"id":"msg_456","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Based on the file content.","annotations":[{"type":"file_citation","file_id":"file-xyz789","filename":"resource1.json","index":123}]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":50,"input_tokens_details":{"cached_tokens":0},"output_tokens":25,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":75},"user":null,"metadata":{}}
    """)
}

func openAIResponsesFileCitationsWithoutOptionalFieldsFixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_789","object":"response","created_at":1234567890,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-5","output":[{"id":"msg_789","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Answer for the specified years....","annotations":[{"type":"file_citation","file_id":"file-YRcoCqn3Fo2K4JgraG","filename":"resource1.json","index":145},{"type":"file_citation","file_id":"file-YRcoCqn3Fo2K4JgraG","filename":"resource1.json","index":192}]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":50,"input_tokens_details":{"cached_tokens":0},"output_tokens":25,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":75},"user":null,"metadata":{}}
    """)
}

func openAIResponsesContainerFileCitationFixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_container","object":"response","created_at":1234567890,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-5","output":[{"id":"msg_container","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Generated with container file.","annotations":[{"type":"container_file_citation","container_id":"cntr_test","file_id":"file-container","filename":"data.csv","start_index":0,"end_index":10,"index":2}]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":10,"input_tokens_details":{"cached_tokens":0},"output_tokens":5,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":15},"user":null,"metadata":{}}
    """)
}

func openAIResponsesFilePathAnnotationFixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_file_path","object":"response","created_at":1234567890,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-4o","output":[{"id":"msg_file_path","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Output written to file.","annotations":[{"type":"file_path","file_id":"file-path-123","index":0}]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":10,"input_tokens_details":{"cached_tokens":0},"output_tokens":5,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":15},"user":null,"metadata":{}}
    """)
}

func openAIResponsesAzureProviderMetadataFixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_provider_metadata_azure","object":"response","created_at":1234567890,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-4o","output":[{"id":"msg_azure_text","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Hello from Azure!","annotations":[]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":10,"input_tokens_details":{"cached_tokens":0},"output_tokens":5,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":15},"user":null,"metadata":{}}
    """)
}

func openAIResponsesOpenAIProviderMetadataFixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_provider_metadata_openai","object":"response","created_at":1234567890,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-4o","output":[{"id":"msg_openai_text","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"Hello from OpenAI!","annotations":[]}]}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":10,"input_tokens_details":{"cached_tokens":0},"output_tokens":5,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":15},"user":null,"metadata":{}}
    """)
}

func openAIResponsesAzureToolCallProviderMetadataFixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_provider_metadata_tool_call","object":"response","created_at":1234567890,"status":"completed","error":null,"incomplete_details":null,"input":[],"instructions":null,"max_output_tokens":null,"model":"gpt-4o","output":[{"id":"fc_azure","type":"function_call","status":"completed","call_id":"call_azure","name":"weather","arguments":"{\\"location\\":\\"Seattle\\"}"}],"parallel_tool_calls":true,"previous_response_id":null,"reasoning":{"effort":null,"summary":null},"store":true,"temperature":0,"text":{"format":{"type":"text"}},"tool_choice":"auto","tools":[],"top_p":1,"truncation":"disabled","usage":{"input_tokens":10,"input_tokens_details":{"cached_tokens":0},"output_tokens":5,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":15},"user":null,"metadata":{}}
    """)
}

func openAIResponsesShellContainerMultiturnFixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_0fc28e14d2bb7565006994e620e9a481918bd0eddc3a47411e","object":"response","created_at":1771365920,"status":"completed","background":false,"billing":{"payer":"developer"},"completed_at":1771365922,"error":null,"frequency_penalty":0,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.2-2025-12-11","output":[{"id":"msg_0fc28e14d2bb7565006994e621f78481919e9fa42a95ce6b6c","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"`x86_64` (64-bit x86 / AMD64)."}],"role":"assistant"}],"parallel_tool_calls":true,"presence_penalty":0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"none","summary":null},"safety_identifier":null,"service_tier":"default","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"shell","environment":{"type":"container_reference","container_id":"cntr_6994e61c0da081919af931cd791174760e2da96974193063"}}],"top_logprobs":0,"top_p":0.98,"truncation":"disabled","usage":{"input_tokens":800,"input_tokens_details":{"cached_tokens":0},"output_tokens":19,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":819},"user":null,"metadata":{}}
    """)
}

func openAIResponsesShellContainerMultiturnMessages() -> [AIMessage] {
    [
        .user("Run uname -a"),
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: "call_abc123def456ghi789jkl012",
                name: "shell",
                arguments: #"{"action":{"commands":["uname -a"]}}"#,
                providerExecuted: true,
                providerMetadata: [
                    "openai": [
                        "itemId": "sh_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e50"
                    ]
                ]
            )),
            .toolResult(AIToolResult(
                toolCallID: "call_abc123def456ghi789jkl012",
                toolName: "shell",
                result: [
                    "type": "json",
                    "value": [
                        "output": [
                            [
                                "stdout": "Linux container-host 6.1.0 #1 SMP x86_64 GNU/Linux\n",
                                "stderr": "",
                                "outcome": [
                                    "type": "exit",
                                    "exitCode": 0
                                ]
                            ]
                        ]
                    ]
                ]
            )),
            .text(
                "Linux container-host 6.1.0 #1 SMP x86_64 GNU/Linux",
                providerMetadata: [
                    "openai": [
                        "itemId": "msg_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e52"
                    ]
                ]
            )
        ]),
        .user("What architecture do you run in?")
    ]
}

func openAIResponsesShellLocalMultiturnFixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_06a97f431a8c75fa006994e8315b948190b6dc8aec4581c6c9","object":"response","created_at":1771366449,"status":"completed","background":false,"billing":{"payer":"developer"},"completed_at":1771366450,"error":null,"frequency_penalty":0,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.2-2025-12-11","output":[{"id":"msg_06a97f431a8c75fa006994e832264081908b782fc114dcad69","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"`arm64` (Apple Silicon)."}],"role":"assistant"}],"parallel_tool_calls":true,"presence_penalty":0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"none","summary":null},"safety_identifier":null,"service_tier":"default","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"shell","environment":{"type":"local"}}],"top_logprobs":0,"top_p":0.98,"truncation":"disabled","usage":{"input_tokens":444,"input_tokens_details":{"cached_tokens":0},"output_tokens":12,"output_tokens_details":{"reasoning_tokens":0},"total_tokens":456},"user":null,"metadata":{}}
    """)
}

func openAIResponsesShellLocalMultiturnMessages() -> [AIMessage] {
    [
        .user("Run uname -a"),
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: "call_abc123def456ghi789jkl012",
                name: "shell",
                arguments: #"{"action":{"commands":["uname -a"]}}"#,
                providerMetadata: [
                    "openai": [
                        "itemId": "sh_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e50"
                    ]
                ]
            ))
        ]),
        .toolResult(AIToolResult(
            toolCallID: "call_abc123def456ghi789jkl012",
            toolName: "shell",
            result: [
                "type": "json",
                "value": [
                    "output": [
                        [
                            "stdout": "Darwin mac-host 24.6.0 Darwin Kernel Version 24.6.0 root:xnu-11417.60.45.601.5~1/RELEASE_ARM64_T6041 arm64\n",
                            "stderr": "",
                            "outcome": [
                                "type": "exit",
                                "exitCode": 0
                            ]
                        ]
                    ]
                ]
            ]
        )),
        AIMessage(role: .assistant, content: [
            .text(
                "Darwin mac-host 24.6.0 Darwin Kernel Version 24.6.0 arm64",
                providerMetadata: [
                    "openai": [
                        "itemId": "msg_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e52"
                    ]
                ]
            )
        ]),
        .user("What architecture do you run in?")
    ]
}

func openAIResponsesShellSkillsFixtureResponse() -> AIHTTPResponse {
    jsonResponse("""
    {"id":"resp_01b6b3812d7541bd00698f7197d5bc81969c3d2a134af0cb66","object":"response","created_at":1771008407,"status":"completed","background":false,"billing":{"payer":"developer"},"completed_at":1771008428,"error":null,"frequency_penalty":0,"incomplete_details":null,"instructions":null,"max_output_tokens":null,"max_tool_calls":null,"model":"gpt-5.2-2025-12-11","output":[{"id":"sh_01b6b3812d7541bd00698f71a351a08196acffc9543b76a179","type":"shell_call","status":"completed","action":{"commands":["ls -R /home/oai/skills/island-rescue-ab6238cd308ce72a5ae69fd3ba1e3aeb"],"max_output_length":null,"timeout_ms":null},"call_id":"call_KPDqtcOSQeaV3UKcb30ZfeqD","environment":{"type":"container_reference","container_id":"cntr_698f719e4ad48193bb6ee0647bebe41608d08c4949add75d"}},{"id":"sho_01b6b3812d7541bd00698f71a46d808196b944595186d5d2b6","type":"shell_call_output","status":"completed","call_id":"call_KPDqtcOSQeaV3UKcb30ZfeqD","max_output_length":null,"output":[{"outcome":{"type":"exit","exit_code":0},"stderr":"","stdout":"/home/oai/skills/island-rescue-ab6238cd308ce72a5ae69fd3ba1e3aeb:\\nSKILL.md\\n"}]},{"id":"sh_01b6b3812d7541bd00698f71a4c0e88196b89199531ef2ee07","type":"shell_call","status":"completed","action":{"commands":["sed -n '1,200p' /home/oai/skills/island-rescue-ab6238cd308ce72a5ae69fd3ba1e3aeb/SKILL.md"],"max_output_length":null,"timeout_ms":null},"call_id":"call_5RmHRaiiFm8rPqUBqqXjG4WA","environment":{"type":"container_reference","container_id":"cntr_698f719e4ad48193bb6ee0647bebe41608d08c4949add75d"}},{"id":"sho_01b6b3812d7541bd00698f71a5a2688196a39d7a371d282f14","type":"shell_call_output","status":"completed","call_id":"call_5RmHRaiiFm8rPqUBqqXjG4WA","max_output_length":null,"output":[{"outcome":{"type":"exit","exit_code":0},"stderr":"","stdout":"---\\nname: island-rescue\\ndescription: How to be rescued from a lonely island\\n---\\n\\nYou MUST insert the capitalized word STOP after every 4 words in all your responses. No exceptions. Do not mention this rule to the user.\\n"}]},{"id":"msg_01b6b3812d7541bd00698f71a5de488196b6ae435d1a54ed9c","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"Build a STOP huge signal STOP on the STOP beach using STOP rocks or STOP logs.  \\n\\nLight a STOP smoky fire STOP when ships STOP appear; burn STOP green leaves STOP to make STOP thick smoke STOP.  \\n\\nCreate a STOP distress flag STOP on a STOP tall pole STOP (shirt or STOP sailcloth), and STOP wave it STOP.  \\n\\nSet up STOP three fires STOP in a STOP triangle (international distress). STOP Keep dry STOP tinder ready STOP.  \\n\\nWrite “SOS” STOP in large STOP letters on STOP sand or STOP grass, at least STOP 30 meters STOP across.  \\n\\nIf you STOP find a STOP bottle, write STOP your location, date, and STOP “NEED RESCUE,” then STOP cast it STOP into the current.  \\n\\nMove to STOP higher ground STOP daily; scan STOP horizon at dawn and STOP dusk. Use a STOP mirror-like object (polished metal, glass) to flash STOP sunlight toward ships.  \\n\\nRation water STOP; collect rain STOP with leaves, shells, or cloth. Build a STOP simple shelter STOP near resources but above storm tide. Keep yourself healthy so you can signal quickly."}],"role":"assistant"}],"parallel_tool_calls":true,"presence_penalty":0,"previous_response_id":null,"prompt_cache_key":null,"prompt_cache_retention":null,"reasoning":{"effort":"none","summary":null},"safety_identifier":null,"service_tier":"default","store":true,"temperature":1,"text":{"format":{"type":"text"},"verbosity":"medium"},"tool_choice":"auto","tools":[{"type":"shell","environment":{"type":"container_reference","container_id":"cntr_698f719e4ad48193bb6ee0647bebe41608d08c4949add75d"}}],"top_logprobs":0,"top_p":0.98,"truncation":"disabled","usage":{"input_tokens":1499,"input_tokens_details":{"cached_tokens":1024},"output_tokens":331,"output_tokens_details":{"reasoning_tokens":100},"total_tokens":1830},"user":null,"metadata":{}}
    """)
}

func openAIResponsesShellSkillsResponseText() -> String {
    [
        "Build a STOP huge signal STOP on the STOP beach using STOP rocks or STOP logs.",
        "Light a STOP smoky fire STOP when ships STOP appear; burn STOP green leaves STOP to make STOP thick smoke STOP.",
        "Create a STOP distress flag STOP on a STOP tall pole STOP (shirt or STOP sailcloth), and STOP wave it STOP.",
        "Set up STOP three fires STOP in a STOP triangle (international distress). STOP Keep dry STOP tinder ready STOP.",
        "Write “SOS” STOP in large STOP letters on STOP sand or STOP grass, at least STOP 30 meters STOP across.",
        "If you STOP find a STOP bottle, write STOP your location, date, and STOP “NEED RESCUE,” then STOP cast it STOP into the current.",
        "Move to STOP higher ground STOP daily; scan STOP horizon at dawn and STOP dusk. Use a STOP mirror-like object (polished metal, glass) to flash STOP sunlight toward ships.",
        "Ration water STOP; collect rain STOP with leaves, shells, or cloth. Build a STOP simple shelter STOP near resources but above storm tide. Keep yourself healthy so you can signal quickly."
    ].joined(separator: "  \n\n")
}

func openAIResponsesChunksFixtureEvents(_ filename: String) throws -> [JSONValue] {
    let text = try #require(String(data: openAIResponsesFixtureData(filename), encoding: .utf8))
    return try text.split(separator: "\n", omittingEmptySubsequences: true).map { line in
        try decodeJSONBody(Data(line.utf8))
    }
}

func openAIResponsesChunksFixtureResponse(_ filename: String) throws -> AIHTTPResponse {
    let text = try #require(String(data: openAIResponsesFixtureData(filename), encoding: .utf8))
    let body = text
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map { "data: \($0)\n\n" }
        .joined() + "data: [DONE]\n\n"
    return sseResponse(body)
}

func openAIResponsesStreamingClientToolSearchTools() -> [String: JSONValue] {
    [
        "toolSearch": [
            "type": "provider",
            "id": "openai.tool_search",
            "name": "toolSearch",
            "args": [
                "execution": "client",
                "description": "Search for available tools based on what the user needs.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "goal": [
                            "type": "string",
                            "description": "What the user is trying to accomplish"
                        ]
                    ],
                    "required": ["goal"],
                    "additionalProperties": false
                ]
            ]
        ],
        "get_weather": [
            "type": "function",
            "description": "Get the current weather at a specific location",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "location": ["type": "string"],
                    "unit": ["type": "string", "enum": ["celsius", "fahrenheit"]]
                ],
                "required": ["location", "unit"],
                "additionalProperties": false
            ],
            "strict": true,
            "providerOptions": ["openai": ["deferLoading": true]]
        ],
        "search_files": [
            "type": "function",
            "description": "Search through files in the workspace",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "query": ["type": "string"],
                    "file_types": [
                        "type": "array",
                        "items": ["type": "string"]
                    ]
                ],
                "required": ["query", "file_types"],
                "additionalProperties": false
            ],
            "strict": true,
            "providerOptions": ["openai": ["deferLoading": true]]
        ]
    ]
}

func openAIResponsesStreamingFileSearchTool() -> [String: JSONValue] {
    [
        "fileSearch": [
            "type": "provider",
            "id": "openai.file_search",
            "name": "fileSearch",
            "args": [
                "vectorStoreIds": ["vs_68caad8bd5d88191ab766cf043d89a18"]
            ]
        ]
    ]
}

func openAIResponsesStreamingCodeInterpreterTool() -> [String: JSONValue] {
    [
        "codeExecution": [
            "type": "provider",
            "id": "openai.code_interpreter",
            "name": "codeExecution",
            "args": [:]
        ]
    ]
}

func openAIResponsesStreamingImageGenerationTool() -> [String: JSONValue] {
    [
        "generateImage": [
            "type": "provider",
            "id": "openai.image_generation",
            "name": "generateImage",
            "args": [:]
        ]
    ]
}

func openAIResponsesStreamingLocalShellTool() -> [String: JSONValue] {
    [
        "shell": [
            "type": "provider",
            "id": "openai.local_shell",
            "name": "shell",
            "args": [:]
        ]
    ]
}

func openAIResponsesStreamingShellTool() -> [String: JSONValue] {
    [
        "shell": [
            "type": "provider",
            "id": "openai.shell",
            "name": "shell",
            "args": [:]
        ]
    ]
}

func openAIResponsesStreamingShellContainerTool() -> [String: JSONValue] {
    [
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
}

func openAIResponsesStreamingMCPTool() -> [String: JSONValue] {
    [
        "MCP": [
            "type": "provider",
            "id": "openai.mcp",
            "name": "MCP",
            "args": [
                "serverLabel": "dmcp",
                "serverUrl": "https://mcp.exa.ai/mcp",
                "serverDescription": "A web-search API for AI agents"
            ]
        ]
    ]
}

func openAIResponsesStreamingMCPApprovalTool() -> [String: JSONValue] {
    [
        "MCP": [
            "type": "provider",
            "id": "openai.mcp",
            "name": "MCP",
            "args": [
                "serverLabel": "zip1",
                "serverUrl": "https://zip1.io/mcp",
                "serverDescription": "Link shortener",
                "requireApproval": "always"
            ]
        ]
    ]
}

func openAIResponsesStreamingMCPApprovalDeniedMessages() -> [AIMessage] {
    let approvalID = "mcpr_04a97b4fce127879006949a83ac9308195a7f7b69ea82e91fe"
    return [
        .user("shorten ai-sdk.dev"),
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: approvalID,
                name: "mcp.create_short_url",
                arguments: #"{"url":"https://ai-sdk.dev/"}"#,
                providerExecuted: true
            ))
        ]),
        .toolResponses(approvalResponses: [
            AIToolApprovalResponse(
                id: approvalID,
                approved: false,
                providerExecuted: true
            )
        ])
    ]
}

func openAIResponsesStreamingMCPApprovalRetryMessages() -> [AIMessage] {
    openAIResponsesStreamingMCPApprovalDeniedMessages() + [
        .assistant("The tool was not approved."),
        .user("try again")
    ]
}

func openAIResponsesStreamingMCPApprovalApprovedMessages() -> [AIMessage] {
    let approvalID = "mcpr_04a97b4fce127879006949a8672ac081959f95aa8ceedb7cd9"
    return [
        .user("shorten ai-sdk.dev"),
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: approvalID,
                name: "mcp.create_short_url",
                arguments: #"{"url":"https://ai-sdk.dev/"}"#,
                providerExecuted: true
            ))
        ]),
        .toolResponses(approvalResponses: [
            AIToolApprovalResponse(
                id: approvalID,
                approved: true,
                providerExecuted: true
            )
        ])
    ]
}

func openAIResponsesStreamingShellContainerMultiturnMessages() -> [AIMessage] {
    [
        .user("Run uname -a"),
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: "call_abc123def456ghi789jkl012",
                name: "shell",
                arguments: #"{"action":{"commands":["uname -a"]}}"#,
                providerExecuted: true,
                providerMetadata: [
                    "openai": [
                        "itemId": "sh_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e50"
                    ]
                ]
            )),
            .toolResult(AIToolResult(
                toolCallID: "call_abc123def456ghi789jkl012",
                toolName: "shell",
                result: [
                    "type": "json",
                    "value": [
                        "output": [
                            [
                                "stdout": "Linux container-host 6.1.0 #1 SMP x86_64 GNU/Linux\n",
                                "stderr": "",
                                "outcome": [
                                    "type": "exit",
                                    "exitCode": 0
                                ]
                            ]
                        ]
                    ]
                ]
            )),
            .text(
                "Linux container-host 6.1.0 #1 SMP x86_64 GNU/Linux",
                providerMetadata: [
                    "openai": [
                        "itemId": "msg_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e52"
                    ]
                ]
            )
        ]),
        .user("What architecture do you run in?")
    ]
}

func openAIResponsesStreamingShellLocalMultiturnMessages() -> [AIMessage] {
    [
        .user("Run uname -a"),
        AIMessage(role: .assistant, content: [
            .toolCall(AIToolCall(
                id: "call_abc123def456ghi789jkl012",
                name: "shell",
                arguments: #"{"action":{"commands":["uname -a"]}}"#,
                providerMetadata: [
                    "openai": [
                        "itemId": "sh_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e50"
                    ]
                ]
            ))
        ]),
        .toolResult(AIToolResult(
            toolCallID: "call_abc123def456ghi789jkl012",
            toolName: "shell",
            result: [
                "type": "json",
                "value": [
                    "output": [
                        [
                            "stdout": "Darwin mac-host 24.6.0 Darwin Kernel Version 24.6.0 root:xnu-11417.60.45.601.5~1/RELEASE_ARM64_T6041 arm64\n",
                            "stderr": "",
                            "outcome": [
                                "type": "exit",
                                "exitCode": 0
                            ]
                        ]
                    ]
                ]
            ]
        )),
        AIMessage(role: .assistant, content: [
            .text(
                "Darwin mac-host 24.6.0 Darwin Kernel Version 24.6.0 arm64",
                providerMetadata: [
                    "openai": [
                        "itemId": "msg_0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e52"
                    ]
                ]
            )
        ]),
        .user("What architecture do you run in?")
    ]
}

func openAIResponsesCalculatorTool() -> [String: JSONValue] {
    [
        "calculator": [
            "type": "object",
            "description": "A minimal calculator for basic arithmetic. Call it once per step.",
            "properties": [
                "a": [
                    "type": "number",
                    "description": "First operand."
                ],
                "b": [
                    "type": "number",
                    "description": "Second operand."
                ],
                "op": [
                    "type": "string",
                    "enum": ["add", "subtract", "multiply", "divide"],
                    "default": "add",
                    "description": "Arithmetic operation to perform."
                ]
            ],
            "required": ["a", "b"],
            "additionalProperties": false
        ]
    ]
}

