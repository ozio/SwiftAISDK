import Foundation

func openAIResponsesTools(from tools: [String: JSONValue]) -> (tools: [JSONValue], customToolNames: Set<String>) {
    var customToolNames: Set<String> = []
    var namespaceIndexes: [String: Int] = [:]
    var mapped: [JSONValue] = []
    for (name, schema) in tools {
        let object = schema.objectValue
        let providerToolID = object?["id"]?.stringValue
        if object?["type"]?.stringValue == "provider" || providerToolID?.hasPrefix("openai.") == true {
            if let tool = openAIResponsesProviderTool(name: object?["name"]?.stringValue ?? name, id: providerToolID ?? name, args: object?["args"]?.objectValue ?? [:], customToolNames: &customToolNames) {
                mapped.append(tool)
            }
            continue
        }

        var parameters = schema
        let openAIOptions = object?["providerOptions"]?["openai"]?.objectValue ?? object?["openai"]?.objectValue
        var function: [String: JSONValue] = [
            "type": .string("function"),
            "name": .string(name),
            "parameters": parameters
        ]
        if var parameterObject = parameters.objectValue {
            parameterObject.removeValue(forKey: "providerOptions")
            parameterObject.removeValue(forKey: "openai")
            parameters = .object(parameterObject)
            function["parameters"] = parameters
            if let description = parameterObject["description"]?.stringValue {
                function["description"] = .string(description)
            }
            if let strict = parameterObject.removeValue(forKey: "strict") {
                function["strict"] = strict
                parameters = .object(parameterObject)
                function["parameters"] = parameters
            }
            if let deferLoading = parameterObject.removeValue(forKey: "deferLoading") ?? parameterObject.removeValue(forKey: "defer_loading") {
                function["defer_loading"] = deferLoading
                parameters = .object(parameterObject)
                function["parameters"] = parameters
            }
        }
        if let deferLoading = openAIOptions?["deferLoading"] ?? openAIOptions?["defer_loading"] {
            function["defer_loading"] = deferLoading
        }
        if let namespace = openAIOptions?["namespace"]?.objectValue,
           let namespaceName = namespace["name"]?.stringValue,
           let namespaceDescription = namespace["description"]?.stringValue {
            if let index = namespaceIndexes[namespaceName],
               var namespaceTool = mapped[index].objectValue {
                var nestedTools = namespaceTool["tools"]?.arrayValue ?? []
                nestedTools.append(.object(function))
                namespaceTool["tools"] = .array(nestedTools)
                mapped[index] = .object(namespaceTool)
            } else {
                namespaceIndexes[namespaceName] = mapped.count
                mapped.append(.object([
                    "type": .string("namespace"),
                    "name": .string(namespaceName),
                    "description": .string(namespaceDescription),
                    "tools": .array([.object(function)])
                ]))
            }
        } else {
            mapped.append(.object(function))
        }
    }
    return (mapped, customToolNames)
}

func openAIResponsesProviderTool(name: String, id: String, args: [String: JSONValue], customToolNames: inout Set<String>) -> JSONValue? {
    switch id {
    case "openai.file_search":
        var tool: [String: JSONValue] = ["type": .string("file_search")]
        if let vectorStoreIds = args["vectorStoreIds"] ?? args["vector_store_ids"] { tool["vector_store_ids"] = vectorStoreIds }
        if let maxNumResults = args["maxNumResults"] ?? args["max_num_results"] { tool["max_num_results"] = maxNumResults }
        if let ranking = (args["ranking"] ?? args["ranking_options"])?.objectValue {
            tool["ranking_options"] = .object([
                "ranker": ranking["ranker"],
                "score_threshold": ranking["scoreThreshold"] ?? ranking["score_threshold"]
            ])
        }
        if let filters = args["filters"] { tool["filters"] = filters }
        return .object(tool)
    case "openai.local_shell":
        return .object(["type": .string("local_shell")])
    case "openai.shell":
        var tool: [String: JSONValue] = ["type": .string("shell")]
        if let environment = args["environment"]?.objectValue {
            tool["environment"] = openAIResponsesShellEnvironment(environment)
        }
        return .object(tool)
    case "openai.apply_patch":
        return .object(["type": .string("apply_patch")])
    case "openai.web_search_preview":
        var tool: [String: JSONValue] = ["type": .string("web_search_preview")]
        if let searchContextSize = args["searchContextSize"] ?? args["search_context_size"] { tool["search_context_size"] = searchContextSize }
        if let userLocation = args["userLocation"] ?? args["user_location"] { tool["user_location"] = userLocation }
        return .object(tool)
    case "openai.web_search":
        var tool: [String: JSONValue] = ["type": .string("web_search")]
        if let filters = args["filters"]?.objectValue {
            var mappedFilters = filters
            if let allowedDomains = mappedFilters.removeValue(forKey: "allowedDomains") {
                mappedFilters["allowed_domains"] = allowedDomains
            }
            tool["filters"] = .object(mappedFilters)
        }
        if let externalWebAccess = args["externalWebAccess"] ?? args["external_web_access"] { tool["external_web_access"] = externalWebAccess }
        if let searchContextSize = args["searchContextSize"] ?? args["search_context_size"] { tool["search_context_size"] = searchContextSize }
        if let userLocation = args["userLocation"] ?? args["user_location"] { tool["user_location"] = userLocation }
        return .object(tool)
    case "openai.code_interpreter":
        var tool: [String: JSONValue] = ["type": .string("code_interpreter")]
        if let container = args["container"] {
            if let containerID = container.stringValue {
                tool["container"] = .string(containerID)
            } else if let containerObject = container.objectValue {
                tool["container"] = .object([
                    "type": .string("auto"),
                    "file_ids": containerObject["fileIds"] ?? containerObject["file_ids"]
                ])
            }
        } else {
            tool["container"] = .object(["type": .string("auto")])
        }
        return .object(tool)
    case "openai.computer_use":
        var tool = openAIResponsesSnakeCasedObject(args)
        tool["type"] = .string("computer_use")
        return .object(tool)
    case "openai.image_generation":
        var tool: [String: JSONValue] = ["type": .string("image_generation")]
        for key in ["background", "model", "moderation", "quality", "size"] {
            if let value = args[key] { tool[key] = value }
        }
        if let value = args["inputFidelity"] ?? args["input_fidelity"] { tool["input_fidelity"] = value }
        if let value = args["inputImageMask"]?.objectValue ?? args["input_image_mask"]?.objectValue {
            tool["input_image_mask"] = .object([
                "file_id": value["fileId"] ?? value["file_id"],
                "image_url": value["imageUrl"] ?? value["image_url"]
            ])
        }
        if let value = args["partialImages"] ?? args["partial_images"] { tool["partial_images"] = value }
        if let value = args["outputCompression"] ?? args["output_compression"] { tool["output_compression"] = value }
        if let value = args["outputFormat"] ?? args["output_format"] { tool["output_format"] = value }
        return .object(tool)
    case "openai.mcp":
        var tool: [String: JSONValue] = ["type": .string("mcp")]
        if let value = args["serverLabel"] ?? args["server_label"] { tool["server_label"] = value }
        if let value = args["allowedTools"] ?? args["allowed_tools"] { tool["allowed_tools"] = openAIResponsesMCPAllowedTools(value) }
        if let value = args["authorization"] { tool["authorization"] = value }
        if let value = args["connectorId"] ?? args["connector_id"] { tool["connector_id"] = value }
        if let value = args["headers"] { tool["headers"] = value }
        tool["require_approval"] = openAIResponsesMCPRequireApproval(args["requireApproval"] ?? args["require_approval"]) ?? .string("never")
        if let value = args["serverDescription"] ?? args["server_description"] { tool["server_description"] = value }
        if let value = args["serverUrl"] ?? args["server_url"] { tool["server_url"] = value }
        return .object(tool)
    case "openai.custom":
        customToolNames.insert(name)
        var tool: [String: JSONValue] = ["type": .string("custom"), "name": .string(name)]
        if let description = args["description"] { tool["description"] = description }
        if let format = args["format"] { tool["format"] = format }
        return .object(tool)
    case "openai.tool_search":
        var tool: [String: JSONValue] = ["type": .string("tool_search")]
        if let execution = args["execution"] { tool["execution"] = execution }
        if let description = args["description"] { tool["description"] = description }
        if let parameters = args["parameters"] { tool["parameters"] = parameters }
        return .object(tool)
    case "xai.web_search":
        var tool: [String: JSONValue] = ["type": .string("web_search")]
        if let value = args["allowedDomains"] ?? args["allowed_domains"] { tool["allowed_domains"] = value }
        if let value = args["excludedDomains"] ?? args["excluded_domains"] { tool["excluded_domains"] = value }
        if let value = args["enableImageSearch"] ?? args["enable_image_search"] { tool["enable_image_search"] = value }
        if let value = args["enableImageUnderstanding"] ?? args["enable_image_understanding"] { tool["enable_image_understanding"] = value }
        return .object(tool)
    case "xai.x_search":
        var tool: [String: JSONValue] = ["type": .string("x_search")]
        if let value = args["allowedXHandles"] ?? args["allowed_x_handles"] { tool["allowed_x_handles"] = value }
        if let value = args["excludedXHandles"] ?? args["excluded_x_handles"] { tool["excluded_x_handles"] = value }
        if let value = args["fromDate"] ?? args["from_date"] { tool["from_date"] = value }
        if let value = args["toDate"] ?? args["to_date"] { tool["to_date"] = value }
        if let value = args["enableImageUnderstanding"] ?? args["enable_image_understanding"] { tool["enable_image_understanding"] = value }
        if let value = args["enableVideoUnderstanding"] ?? args["enable_video_understanding"] { tool["enable_video_understanding"] = value }
        return .object(tool)
    case "xai.code_execution":
        return .object(["type": .string("code_interpreter")])
    case "xai.view_image":
        return .object(["type": .string("view_image")])
    case "xai.view_x_video":
        return .object(["type": .string("view_x_video")])
    case "xai.file_search":
        var tool: [String: JSONValue] = ["type": .string("file_search")]
        if let value = args["vectorStoreIds"] ?? args["vector_store_ids"] { tool["vector_store_ids"] = value }
        if let value = args["maxNumResults"] ?? args["max_num_results"] { tool["max_num_results"] = value }
        return .object(tool)
    case "xai.mcp":
        var tool: [String: JSONValue] = ["type": .string("mcp")]
        if let value = args["serverUrl"] ?? args["server_url"] { tool["server_url"] = value }
        if let value = args["serverLabel"] ?? args["server_label"] { tool["server_label"] = value }
        if let value = args["serverDescription"] ?? args["server_description"] { tool["server_description"] = value }
        if let value = args["allowedTools"] ?? args["allowed_tools"] { tool["allowed_tools"] = value }
        if let value = args["headers"] { tool["headers"] = value }
        if let value = args["authorization"] { tool["authorization"] = value }
        return .object(tool)
    default:
        return nil
    }
}

func openAIResponsesToolChoice(from value: JSONValue?, customToolNames: Set<String>) -> JSONValue? {
    if let string = value?.stringValue {
        switch string {
        case "auto", "none", "required":
            return .string(string)
        default:
            return nil
        }
    }
    guard let object = value?.objectValue else { return nil }
    switch object["type"]?.stringValue {
    case "auto", "none", "required":
        return object["type"]
    case "tool":
        guard let name = object["toolName"]?.stringValue ?? object["tool_name"]?.stringValue else { return nil }
        let providerToolTypes: Set<String> = ["code_interpreter", "file_search", "image_generation", "web_search_preview", "web_search", "mcp", "apply_patch"]
        if providerToolTypes.contains(name) {
            return .object(["type": .string(name)])
        }
        if customToolNames.contains(name) {
            return .object(["type": .string("custom"), "name": .string(name)])
        }
        return .object(["type": .string("function"), "name": .string(name)])
    default:
        return nil
    }
}

func openAIResponsesMCPAllowedTools(_ value: JSONValue) -> JSONValue {
    guard var object = value.objectValue else { return value }
    if let readOnly = object.removeValue(forKey: "readOnly") { object["read_only"] = readOnly }
    if let toolNames = object.removeValue(forKey: "toolNames") { object["tool_names"] = toolNames }
    return .object(object)
}

func openAIResponsesMCPRequireApproval(_ value: JSONValue?) -> JSONValue? {
    guard let value else { return nil }
    if value.stringValue != nil { return value }
    guard var object = value.objectValue else { return value }
    if var never = object["never"]?.objectValue {
        if let toolNames = never.removeValue(forKey: "toolNames") {
            never["tool_names"] = toolNames
        }
        object["never"] = .object(never)
    }
    return .object(object)
}

func openAIResponsesShellEnvironment(_ environment: [String: JSONValue]) -> JSONValue {
    switch environment["type"]?.stringValue {
    case "containerReference":
        return .object([
            "type": .string("container_reference"),
            "container_id": environment["containerId"] ?? environment["container_id"]
        ])
    case "containerAuto":
        var mapped: [String: JSONValue] = ["type": .string("container_auto")]
        if let fileIds = environment["fileIds"] ?? environment["file_ids"] { mapped["file_ids"] = fileIds }
        if let memoryLimit = environment["memoryLimit"] ?? environment["memory_limit"] { mapped["memory_limit"] = memoryLimit }
        if let networkPolicy = environment["networkPolicy"]?.objectValue ?? environment["network_policy"]?.objectValue {
            mapped["network_policy"] = openAIResponsesShellNetworkPolicy(networkPolicy)
        }
        if let skills = environment["skills"]?.arrayValue {
            mapped["skills"] = .array(skills.map(openAIResponsesShellSkill))
        }
        return .object(mapped)
    default:
        var mapped: [String: JSONValue] = ["type": .string("local")]
        if let skills = environment["skills"] { mapped["skills"] = skills }
        return .object(mapped)
    }
}

func openAIResponsesShellSkill(_ skill: JSONValue) -> JSONValue {
    guard let object = skill.objectValue else { return skill }
    if object["type"]?.stringValue == "skillReference" {
        var mapped: [String: JSONValue] = ["type": .string("skill_reference")]
        if let skillID = object["skillId"] ?? object["skill_id"] {
            mapped["skill_id"] = skillID
        } else if let providerReference = object["providerReference"]?.objectValue ?? object["provider_reference"]?.objectValue {
            mapped["skill_id"] = providerReference["openai"] ?? providerReference.values.first
        }
        if let version = object["version"] {
            mapped["version"] = version
        }
        return .object(mapped)
    }
    if object["type"]?.stringValue == "inline" {
        var mapped: [String: JSONValue] = ["type": .string("inline")]
        if let name = object["name"] {
            mapped["name"] = name
        }
        if let description = object["description"] {
            mapped["description"] = description
        }
        if var source = object["source"]?.objectValue {
            if let mediaType = source.removeValue(forKey: "mediaType") {
                source["media_type"] = mediaType
            }
            mapped["source"] = .object(source)
        }
        return .object(mapped)
    }
    return skill
}

func openAIResponsesShellNetworkPolicy(_ policy: [String: JSONValue]) -> JSONValue {
    guard policy["type"]?.stringValue == "allowlist" else {
        return .object(policy)
    }
    var mapped = policy
    if let allowedDomains = mapped.removeValue(forKey: "allowedDomains") {
        mapped["allowed_domains"] = allowedDomains
    }
    if let domainSecrets = mapped.removeValue(forKey: "domainSecrets") {
        mapped["domain_secrets"] = domainSecrets
    }
    return .object(mapped)
}

func openAIResponsesMoveKey(_ source: String, to destination: String, in values: inout [String: JSONValue]) {
    if let value = values.removeValue(forKey: source) {
        values[destination] = value
    }
}

func openAIResponsesSnakeCasedObject(_ values: [String: JSONValue]) -> [String: JSONValue] {
    Dictionary(uniqueKeysWithValues: values.map { key, value in
        (openAIResponsesSnakeCasedKey(key), value)
    })
}

func openAIResponsesSnakeCasedKey(_ key: String) -> String {
    var output = ""
    for character in key {
        if character.isUppercase {
            output.append("_")
            output.append(character.lowercased())
        } else {
            output.append(character)
        }
    }
    return output
}
