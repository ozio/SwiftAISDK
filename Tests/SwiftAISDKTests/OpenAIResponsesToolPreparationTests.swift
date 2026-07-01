import Foundation
import Testing
@testable import SwiftAISDK

@Test func openAIResponsesMapsFunctionAndProviderTools() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    let result = try await model.generate(LanguageModelRequest(
        messages: [.user("Search, inspect files, and generate an image.")],
        tools: [
            "lookup": [
                "type": "object",
                "description": "Look up a value.",
                "properties": ["query": ["type": "string"]],
                "strict": true,
                "deferLoading": true
            ],
            "web_search": OpenAITools.webSearch(
                filters: ["allowedDomains": ["example.com"]],
                externalWebAccess: true,
                searchContextSize: "high",
                userLocation: ["type": "approximate", "country": "US"]
            ),
            "file_search": OpenAITools.fileSearch(
                vectorStoreIDs: ["vs_123"],
                maxNumResults: 5,
                ranking: ["ranker": "auto", "scoreThreshold": 0.2]
            ),
            "code_interpreter": OpenAITools.codeInterpreter(container: ["fileIds": ["file_1", "file_2"]]),
            "computer_use": OpenAITools.computerUse(displayWidth: 1024, displayHeight: 768, environment: "browser"),
            "shell": OpenAITools.shell(environment: OpenAITools.shellContainerAutoEnvironment(
                fileIDs: ["file_shell_1"],
                memoryLimit: "4g",
                networkPolicy: OpenAITools.shellAllowlistNetworkPolicy(
                    allowedDomains: ["example.com"],
                    domainSecrets: [
                        OpenAITools.shellDomainSecret(domain: "example.com", name: "TOKEN", value: "secret")
                    ]
                ),
                skills: [
                    OpenAITools.shellSkillReference(providerReference: ["openai": "skill_123"], version: "1")
                ]
            )),
            "image_generation": OpenAITools.imageGeneration(
                inputFidelity: "high",
                inputImageMask: ["fileId": "file_mask", "imageUrl": "https://example.com/mask.png"],
                model: "gpt-image-1",
                outputCompression: 70,
                outputFormat: "webp",
                partialImages: 2,
                quality: "high",
                size: "1024x1024"
            ),
            "remote_docs": OpenAITools.mcp(
                serverLabel: "docs",
                allowedTools: ["readOnly": true, "toolNames": ["search"]],
                requireApproval: ["never": ["toolNames": ["search"]]],
                serverURL: "https://mcp.example.com"
            ),
            "grammar_tool": OpenAITools.customTool(
                name: "grammar_tool",
                description: "Return a code.",
                format: ["type": "grammar", "syntax": "regex", "definition": "[A-Z]+"]
            ),
            "tool_search": OpenAITools.toolSearch(execution: "client", description: "Find deferred tools.")
        ],
        extraBody: ["toolChoice": ["type": "tool", "toolName": "web_search"]]
    ))

    #expect(result.text == "done")
    let request = try #require(await transport.requests().first)
    let body = try decodeJSONBody(try #require(request.body))
    let tools = try #require(body["tools"]?.arrayValue)
    #expect(tools.count == 10)

    let functionTool = try #require(tools.first { $0["type"]?.stringValue == "function" })
    #expect(functionTool["name"]?.stringValue == "lookup")
    #expect(functionTool["description"]?.stringValue == "Look up a value.")
    #expect(functionTool["parameters"]?["properties"]?["query"]?["type"]?.stringValue == "string")
    #expect(functionTool["parameters"]?["strict"] == nil)
    #expect(functionTool["strict"]?.boolValue == true)
    #expect(functionTool["defer_loading"]?.boolValue == true)

    let webSearch = try #require(tools.first { $0["type"]?.stringValue == "web_search" })
    #expect(webSearch["external_web_access"]?.boolValue == true)
    #expect(webSearch["search_context_size"]?.stringValue == "high")
    #expect(webSearch["filters"]?["allowed_domains"]?[0]?.stringValue == "example.com")
    #expect(webSearch["user_location"]?["country"]?.stringValue == "US")

    let fileSearch = try #require(tools.first { $0["type"]?.stringValue == "file_search" })
    #expect(fileSearch["vector_store_ids"]?[0]?.stringValue == "vs_123")
    #expect(fileSearch["max_num_results"]?.intValue == 5)
    #expect(fileSearch["ranking_options"]?["score_threshold"]?.doubleValue == 0.2)

    let codeInterpreter = try #require(tools.first { $0["type"]?.stringValue == "code_interpreter" })
    #expect(codeInterpreter["container"]?["type"]?.stringValue == "auto")
    #expect(codeInterpreter["container"]?["file_ids"]?[1]?.stringValue == "file_2")

    let computerUse = try #require(tools.first { $0["type"]?.stringValue == "computer_use" })
    #expect(computerUse["display_width"]?.intValue == 1024)
    #expect(computerUse["display_height"]?.intValue == 768)
    #expect(computerUse["environment"]?.stringValue == "browser")

    let shell = try #require(tools.first { $0["type"]?.stringValue == "shell" })
    #expect(shell["environment"]?["type"]?.stringValue == "container_auto")
    #expect(shell["environment"]?["file_ids"]?[0]?.stringValue == "file_shell_1")
    #expect(shell["environment"]?["memory_limit"]?.stringValue == "4g")
    #expect(shell["environment"]?["network_policy"]?["type"]?.stringValue == "allowlist")
    #expect(shell["environment"]?["network_policy"]?["allowed_domains"]?[0]?.stringValue == "example.com")
    #expect(shell["environment"]?["network_policy"]?["domain_secrets"]?[0]?["name"]?.stringValue == "TOKEN")
    #expect(shell["environment"]?["skills"]?[0]?["type"]?.stringValue == "skill_reference")
    #expect(shell["environment"]?["skills"]?[0]?["skill_id"]?.stringValue == "skill_123")
    #expect(shell["environment"]?["skills"]?[0]?["version"]?.stringValue == "1")

    let imageGeneration = try #require(tools.first { $0["type"]?.stringValue == "image_generation" })
    #expect(imageGeneration["input_fidelity"]?.stringValue == "high")
    #expect(imageGeneration["input_image_mask"]?["file_id"]?.stringValue == "file_mask")
    #expect(imageGeneration["partial_images"]?.intValue == 2)
    #expect(imageGeneration["output_compression"]?.intValue == 70)
    #expect(imageGeneration["output_format"]?.stringValue == "webp")

    let mcp = try #require(tools.first { $0["type"]?.stringValue == "mcp" })
    #expect(mcp["server_label"]?.stringValue == "docs")
    #expect(mcp["allowed_tools"]?["read_only"]?.boolValue == true)
    #expect(mcp["allowed_tools"]?["tool_names"]?[0]?.stringValue == "search")
    #expect(mcp["require_approval"]?["never"]?["tool_names"]?[0]?.stringValue == "search")

    let custom = try #require(tools.first { $0["type"]?.stringValue == "custom" })
    #expect(custom["name"]?.stringValue == "grammar_tool")
    #expect(custom["format"]?["syntax"]?.stringValue == "regex")

    let toolSearch = try #require(tools.first { $0["type"]?.stringValue == "tool_search" })
    #expect(toolSearch["execution"]?.stringValue == "client")
    #expect(body["tool_choice"]?["type"]?.stringValue == "web_search")
    #expect(body["toolChoice"] == nil)
}

@Test func openAIResponsesPreparesCustomToolsLikeUpstream() async throws {
    let regexBody = try await recordedOpenAIResponsesBody(tools: [
        "write_sql": OpenAITools.customTool(
            name: "write_sql",
            description: "Write a SQL SELECT query.",
            format: ["type": "grammar", "syntax": "regex", "definition": "SELECT .+"]
        )
    ])

    let regexTools = try #require(regexBody["tools"]?.arrayValue)
    #expect(regexTools.count == 1)
    let regexTool = try #require(regexTools.first)
    #expect(regexTool["type"]?.stringValue == "custom")
    #expect(regexTool["name"]?.stringValue == "write_sql")
    #expect(regexTool["description"]?.stringValue == "Write a SQL SELECT query.")
    #expect(regexTool["format"]?["type"]?.stringValue == "grammar")
    #expect(regexTool["format"]?["syntax"]?.stringValue == "regex")
    #expect(regexTool["format"]?["definition"]?.stringValue == "SELECT .+")
    #expect(regexBody["tool_choice"] == nil)

    let larkBody = try await recordedOpenAIResponsesBody(tools: [
        "generate_json": OpenAITools.customTool(
            name: "generate_json",
            format: ["type": "grammar", "syntax": "lark", "definition": #"start: "{"  "}""#]
        )
    ])

    let larkTool = try #require(larkBody["tools"]?.arrayValue?.first)
    #expect(larkTool["type"]?.stringValue == "custom")
    #expect(larkTool["name"]?.stringValue == "generate_json")
    #expect(larkTool["description"] == nil)
    #expect(larkTool["format"]?["type"]?.stringValue == "grammar")
    #expect(larkTool["format"]?["syntax"]?.stringValue == "lark")
    #expect(larkTool["format"]?["definition"]?.stringValue == #"start: "{"  "}""#)

    let mixedBody = try await recordedOpenAIResponsesBody(tools: [
        "testFunction": [
            "type": "object",
            "description": "A test function",
            "properties": [
                "input": ["type": "string"]
            ]
        ],
        "write_sql": OpenAITools.customTool(
            name: "write_sql",
            description: "Write SQL.",
            format: ["type": "grammar", "syntax": "regex", "definition": "SELECT .+"]
        )
    ])

    let mixedTools = try #require(mixedBody["tools"]?.arrayValue)
    #expect(mixedTools.count == 2)
    let functionTool = try #require(mixedTools.first { $0["type"]?.stringValue == "function" })
    #expect(functionTool["name"]?.stringValue == "testFunction")
    #expect(functionTool["description"]?.stringValue == "A test function")
    #expect(functionTool["parameters"]?["type"]?.stringValue == "object")
    #expect(functionTool["parameters"]?["properties"]?["input"]?["type"]?.stringValue == "string")
    #expect(functionTool["parameters"]?["description"] == nil)
    let customTool = try #require(mixedTools.first { $0["type"]?.stringValue == "custom" })
    #expect(customTool["name"]?.stringValue == "write_sql")
    #expect(customTool["description"]?.stringValue == "Write SQL.")
    #expect(customTool["format"]?["syntax"]?.stringValue == "regex")

    let choiceBody = try await recordedOpenAIResponsesBody(
        tools: ["write_sql": OpenAITools.customTool(name: "write_sql")],
        extraBody: ["toolChoice": ["type": "tool", "toolName": "write_sql"]]
    )
    #expect(choiceBody["tool_choice"]?["type"]?.stringValue == "custom")
    #expect(choiceBody["tool_choice"]?["name"]?.stringValue == "write_sql")
}

@Test func openAIResponsesPreparesApplyPatchLikeUpstream() async throws {
    let applyPatchBody = try await recordedOpenAIResponsesBody(tools: [
        "apply_patch": OpenAITools.applyPatch()
    ])

    let applyPatchTools = try #require(applyPatchBody["tools"]?.arrayValue)
    #expect(applyPatchTools.count == 1)
    #expect(applyPatchTools.first?["type"]?.stringValue == "apply_patch")
    #expect(applyPatchBody["tool_choice"] == nil)

    let choiceBody = try await recordedOpenAIResponsesBody(
        tools: ["apply_patch": OpenAITools.applyPatch()],
        extraBody: ["toolChoice": ["type": "tool", "toolName": "apply_patch"]]
    )

    let choiceTools = try #require(choiceBody["tools"]?.arrayValue)
    #expect(choiceTools.count == 1)
    #expect(choiceTools.first?["type"]?.stringValue == "apply_patch")
    #expect(choiceBody["tool_choice"]?["type"]?.stringValue == "apply_patch")

    let mixedBody = try await recordedOpenAIResponsesBody(tools: [
        "testFunction": [
            "type": "object",
            "description": "A test function",
            "properties": [
                "input": ["type": "string"]
            ]
        ],
        "apply_patch": OpenAITools.applyPatch()
    ])

    let mixedTools = try #require(mixedBody["tools"]?.arrayValue)
    #expect(mixedTools.count == 2)
    let functionTool = try #require(mixedTools.first { $0["type"]?.stringValue == "function" })
    #expect(functionTool["name"]?.stringValue == "testFunction")
    #expect(functionTool["description"]?.stringValue == "A test function")
    #expect(functionTool["parameters"]?["properties"]?["input"]?["type"]?.stringValue == "string")
    #expect(functionTool["parameters"]?["description"] == nil)
    #expect(mixedTools.contains { $0["type"]?.stringValue == "apply_patch" })
}

@Test func openAIResponsesPreparesToolSearchWithDeferredFunctionLikeUpstream() async throws {
    let toolSearchBody = try await recordedOpenAIResponsesBody(tools: [
        "toolSearch": OpenAITools.toolSearch()
    ])

    let toolSearchTools = try #require(toolSearchBody["tools"]?.arrayValue)
    #expect(toolSearchTools.count == 1)
    #expect(toolSearchTools.first?["type"]?.stringValue == "tool_search")
    #expect(toolSearchTools.first?["execution"] == nil)
    #expect(toolSearchTools.first?["description"] == nil)
    #expect(toolSearchBody["tool_choice"] == nil)

    let mixedBody = try await recordedOpenAIResponsesBody(tools: [
        "toolSearch": OpenAITools.toolSearch(),
        "get_weather": [
            "type": "object",
            "description": "Get the current weather",
            "properties": ["location": ["type": "string"]],
            "required": ["location"],
            "additionalProperties": false,
            "providerOptions": ["openai": ["deferLoading": true]]
        ]
    ])

    let mixedTools = try #require(mixedBody["tools"]?.arrayValue)
    #expect(mixedTools.count == 2)
    #expect(mixedTools.contains { $0["type"]?.stringValue == "tool_search" })
    let functionTool = try #require(mixedTools.first { $0["type"]?.stringValue == "function" })
    #expect(functionTool["name"]?.stringValue == "get_weather")
    #expect(functionTool["description"]?.stringValue == "Get the current weather")
    #expect(functionTool["defer_loading"]?.boolValue == true)
    #expect(functionTool["parameters"]?["type"]?.stringValue == "object")
    #expect(functionTool["parameters"]?["properties"]?["location"]?["type"]?.stringValue == "string")
    #expect(functionTool["parameters"]?["required"]?[0]?.stringValue == "location")
    #expect(functionTool["parameters"]?["additionalProperties"]?.boolValue == false)
    #expect(functionTool["parameters"]?["description"] == nil)
    #expect(functionTool["parameters"]?["providerOptions"] == nil)
}

@Test func openAIResponsesGroupsFunctionToolsByOpenAINamespaceLikeUpstream() async throws {
    let body = try await recordedOpenAIResponsesBody(tools: [
        "toolSearch": OpenAITools.toolSearch(),
        "get_customer_profile": [
            "type": "object",
            "description": "Fetch a customer profile by customer ID.",
            "properties": ["customer_id": ["type": "string"]],
            "required": ["customer_id"],
            "additionalProperties": false,
            "providerOptions": [
                "openai": [
                    "namespace": [
                        "name": "crm",
                        "description": "CRM tools for customer lookup and order management."
                    ]
                ]
            ]
        ],
        "get_weather": [
            "type": "object",
            "description": "Get the current weather",
            "properties": ["location": ["type": "string"]],
            "required": ["location"],
            "additionalProperties": false
        ],
        "list_open_orders": [
            "type": "object",
            "description": "List open orders for a customer ID.",
            "properties": ["customer_id": ["type": "string"]],
            "required": ["customer_id"],
            "additionalProperties": false,
            "strict": true,
            "providerOptions": [
                "openai": [
                    "deferLoading": true,
                    "namespace": [
                        "name": "crm",
                        "description": "CRM tools for customer lookup and order management."
                    ]
                ]
            ]
        ]
    ])

    let tools = try #require(body["tools"]?.arrayValue)
    #expect(tools.count == 3)
    #expect(tools.contains { $0["type"]?.stringValue == "tool_search" })

    let namespace = try #require(tools.first { $0["type"]?.stringValue == "namespace" })
    #expect(namespace["name"]?.stringValue == "crm")
    #expect(namespace["description"]?.stringValue == "CRM tools for customer lookup and order management.")
    let namespaceTools = try #require(namespace["tools"]?.arrayValue)
    #expect(namespaceTools.count == 2)
    let profile = try #require(namespaceTools.first { $0["name"]?.stringValue == "get_customer_profile" })
    #expect(profile["description"]?.stringValue == "Fetch a customer profile by customer ID.")
    #expect(profile["parameters"]?["properties"]?["customer_id"]?["type"]?.stringValue == "string")
    #expect(profile["parameters"]?["description"] == nil)
    #expect(profile["parameters"]?["providerOptions"] == nil)
    let orders = try #require(namespaceTools.first { $0["name"]?.stringValue == "list_open_orders" })
    #expect(orders["description"]?.stringValue == "List open orders for a customer ID.")
    #expect(orders["defer_loading"]?.boolValue == true)
    #expect(orders["strict"]?.boolValue == true)
    #expect(orders["parameters"]?["description"] == nil)
    #expect(orders["parameters"]?["providerOptions"] == nil)
    let weather = try #require(tools.first { $0["name"]?.stringValue == "get_weather" })
    #expect(weather["type"]?.stringValue == "function")
    #expect(weather["description"]?.stringValue == "Get the current weather")
    #expect(weather["parameters"]?["properties"]?["location"]?["type"]?.stringValue == "string")
}

@Test func openAIResponsesRejectsConflictingNamespaceDescriptionsLikeUpstream() async throws {
    await #expect(throws: AIError.invalidArgument(
        argument: "tools",
        message: #"conflicting descriptions for OpenAI tool namespace "crm""#
    )) {
        _ = try await recordedOpenAIResponsesBody(tools: [
            "get_customer_profile": [
                "type": "object",
                "description": "Fetch a customer profile by customer ID.",
                "properties": [:],
                "providerOptions": [
                    "openai": [
                        "namespace": [
                            "name": "crm",
                            "description": "CRM tools."
                        ]
                    ]
                ]
            ],
            "list_open_orders": [
                "type": "object",
                "description": "List open orders for a customer ID.",
                "properties": [:],
                "providerOptions": [
                    "openai": [
                        "namespace": [
                            "name": "crm",
                            "description": "Different CRM tools."
                        ]
                    ]
                ]
            ]
        ])
    }
}

@Test func openAIResponsesEmitsAllowedToolsChoiceLikeUpstream() async throws {
    let autoBody = try await recordedOpenAIResponsesBody(
        tools: [
            "get_weather": ["type": "object", "description": "Get weather", "properties": [:]],
            "get_time": ["type": "object", "description": "Get time", "properties": [:]]
        ],
        extraBody: ["allowedTools": ["toolNames": ["get_weather"]]]
    )

    #expect(autoBody["tools"]?.arrayValue?.count == 2)
    #expect(autoBody["tool_choice"]?["type"]?.stringValue == "allowed_tools")
    #expect(autoBody["tool_choice"]?["mode"]?.stringValue == "auto")
    #expect(autoBody["tool_choice"]?["tools"]?[0]?["type"]?.stringValue == "function")
    #expect(autoBody["tool_choice"]?["tools"]?[0]?["name"]?.stringValue == "get_weather")
    #expect(autoBody["allowedTools"] == nil)
    #expect(autoBody["allowed_tools"] == nil)

    let requiredBody = try await recordedOpenAIResponsesBody(
        tools: [
            "get_weather": ["type": "object", "description": "Get weather", "properties": [:]],
            "get_time": ["type": "object", "description": "Get time", "properties": [:]]
        ],
        extraBody: [
            "allowedTools": [
                "toolNames": ["get_weather", "get_time"],
                "mode": "required"
            ]
        ]
    )

    #expect(requiredBody["tools"]?.arrayValue?.count == 2)
    #expect(requiredBody["tool_choice"]?["type"]?.stringValue == "allowed_tools")
    #expect(requiredBody["tool_choice"]?["mode"]?.stringValue == "required")
    let requiredAllowedTools = try #require(requiredBody["tool_choice"]?["tools"]?.arrayValue)
    #expect(requiredAllowedTools.count == 2)
    #expect(requiredAllowedTools.contains { $0["name"]?.stringValue == "get_weather" })
    #expect(requiredAllowedTools.contains { $0["name"]?.stringValue == "get_time" })

    let overrideBody = try await recordedOpenAIResponsesBody(
        tools: [
            "get_weather": ["type": "object", "description": "Get weather", "properties": [:]]
        ],
        extraBody: [
            "toolChoice": ["type": "required"],
            "allowedTools": ["toolNames": ["get_weather"]]
        ]
    )

    #expect(overrideBody["tool_choice"]?["type"]?.stringValue == "allowed_tools")
    #expect(overrideBody["tool_choice"]?["mode"]?.stringValue == "auto")
    #expect(overrideBody["tool_choice"]?["tools"]?[0]?["name"]?.stringValue == "get_weather")
}

@Test func openAIResponsesPassesThroughMixedFunctionToolStrictModeLikeUpstream() async throws {
    let transport = RecordingTransport(response: jsonResponse(#"{"id":"resp-1","status":"completed","output_text":"done"}"#))
    let provider = try AIProviders.openAI(settings: ProviderSettings(apiKey: "test-key", transport: transport))
    let model = try provider.languageModel("gpt-5.1")

    _ = try await model.generate(LanguageModelRequest(
        messages: [.user("Use tools.")],
        tools: [
            "strictTool": [
                "type": "object",
                "description": "A strict tool",
                "properties": [:],
                "strict": true
            ],
            "nonStrictTool": [
                "type": "object",
                "description": "A non-strict tool",
                "properties": [:],
                "strict": false
            ],
            "defaultTool": [
                "type": "object",
                "description": "A tool without strict setting",
                "properties": [:]
            ]
        ]
    ))

    let body = try decodeJSONBody(try #require((await transport.requests()).first?.body))
    let tools = try #require(body["tools"]?.arrayValue)
    let strictTool = try #require(tools.first { $0["name"]?.stringValue == "strictTool" })
    let nonStrictTool = try #require(tools.first { $0["name"]?.stringValue == "nonStrictTool" })
    let defaultTool = try #require(tools.first { $0["name"]?.stringValue == "defaultTool" })

    #expect(strictTool["strict"]?.boolValue == true)
    #expect(strictTool["parameters"]?["strict"] == nil)
    #expect(nonStrictTool["strict"]?.boolValue == false)
    #expect(nonStrictTool["parameters"]?["strict"] == nil)
    #expect(defaultTool["strict"] == nil)
    #expect(defaultTool["parameters"]?["strict"] == nil)
}

