import Foundation

public enum GoogleTools {
    public static func googleSearch(searchTypes: JSONValue? = nil, timeRangeFilter: JSONValue? = nil) -> JSONValue {
        providerTool(id: "google.google_search", name: "google_search", args: JSONValue.object([
            "searchTypes": searchTypes,
            "timeRangeFilter": timeRangeFilter
        ]).objectValue ?? [:])
    }

    public static func enterpriseWebSearch() -> JSONValue {
        providerTool(id: "google.enterprise_web_search", name: "enterprise_web_search")
    }

    public static func googleMaps() -> JSONValue {
        providerTool(id: "google.google_maps", name: "google_maps")
    }

    public static func urlContext() -> JSONValue {
        providerTool(id: "google.url_context", name: "url_context")
    }

    public static func fileSearch(fileSearchStoreNames: [String], metadataFilter: String? = nil, topK: Int? = nil) -> JSONValue {
        providerTool(id: "google.file_search", name: "file_search", args: JSONValue.object([
            "fileSearchStoreNames": .array(fileSearchStoreNames),
            "metadataFilter": metadataFilter.map(JSONValue.string),
            "topK": topK.map { .number(Double($0)) }
        ]).objectValue ?? [:])
    }

    public static func codeExecution() -> JSONValue {
        providerTool(id: "google.code_execution", name: "code_execution")
    }

    public static func vertexRagStore(ragCorpus: String, topK: Int? = nil) -> JSONValue {
        providerTool(id: "google.vertex_rag_store", name: "vertex_rag_store", args: JSONValue.object([
            "ragCorpus": .string(ragCorpus),
            "topK": topK.map { .number(Double($0)) }
        ]).objectValue ?? [:])
    }

    static func providerTool(id: String, name: String, args: [String: JSONValue] = [:]) -> JSONValue {
        .object([
            "type": .string("provider"),
            "id": .string(id),
            "name": .string(name),
            "args": .object(args)
        ])
    }
}

public enum GoogleVertexTools {
    public static func googleSearch(searchTypes: JSONValue? = nil, timeRangeFilter: JSONValue? = nil) -> JSONValue {
        GoogleTools.googleSearch(searchTypes: searchTypes, timeRangeFilter: timeRangeFilter)
    }

    public static func enterpriseWebSearch() -> JSONValue {
        GoogleTools.enterpriseWebSearch()
    }

    public static func googleMaps() -> JSONValue {
        GoogleTools.googleMaps()
    }

    public static func urlContext() -> JSONValue {
        GoogleTools.urlContext()
    }

    public static func fileSearch(fileSearchStoreNames: [String], metadataFilter: String? = nil, topK: Int? = nil) -> JSONValue {
        GoogleTools.fileSearch(fileSearchStoreNames: fileSearchStoreNames, metadataFilter: metadataFilter, topK: topK)
    }

    public static func codeExecution() -> JSONValue {
        GoogleTools.codeExecution()
    }

    public static func vertexRagStore(ragCorpus: String, topK: Int? = nil) -> JSONValue {
        GoogleTools.vertexRagStore(ragCorpus: ragCorpus, topK: topK)
    }
}

struct GooglePreparedTools {
    var tools: [JSONValue]
    var toolConfig: JSONValue?
    var warnings: [AIWarning] = []
}

struct GooglePreparedGenerateContentOptions {
    var options: [String: JSONValue]
    var warnings: [AIWarning]
    var headers: [String: String]
}

struct GooglePreparedProviderTool {
    var tool: JSONValue?
    var warnings: [AIWarning] = []
}

