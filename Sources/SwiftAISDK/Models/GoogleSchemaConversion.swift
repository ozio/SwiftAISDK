import Foundation

func googleOpenAPISchema(from schema: JSONValue, isRoot: Bool) -> JSONValue? {
    if case let .bool(value) = schema {
        return value ? .object(["type": .string("boolean"), "properties": .object([:])]) : nil
    }
    guard let object = schema.objectValue else { return schema }

    if isRoot,
       object["type"]?.stringValue == "object",
       (object["properties"]?.objectValue?.isEmpty ?? true),
       object["additionalProperties"]?.boolValue != true {
        return nil
    }

    var result: [String: JSONValue] = [:]
    for key in ["description", "required", "format", "enum", "minLength"] {
        if let value = object[key] {
            result[key] = value
        }
    }
    if let constValue = object["const"] {
        result["enum"] = .array([constValue])
    }

    if let type = object["type"] {
        if let types = type.arrayValue?.compactMap(\.stringValue) {
            let nonNullTypes = types.filter { $0 != "null" }
            if nonNullTypes.isEmpty {
                result["type"] = .string("null")
            } else {
                result["anyOf"] = .array(nonNullTypes.map { .object(["type": .string($0)]) })
                if types.contains("null") {
                    result["nullable"] = true
                }
            }
        } else {
            result["type"] = type
        }
    }

    if let properties = object["properties"]?.objectValue {
        result["properties"] = .object(properties.mapValues { googleOpenAPISchema(from: $0, isRoot: false) ?? .object([:]) })
    }
    if let items = object["items"] {
        if let array = items.arrayValue {
            result["items"] = .array(array.map { googleOpenAPISchema(from: $0, isRoot: false) ?? .object([:]) })
        } else if let converted = googleOpenAPISchema(from: items, isRoot: false) {
            result["items"] = converted
        }
    }
    for key in ["allOf", "oneOf"] {
        if let array = object[key]?.arrayValue {
            result[key] = .array(array.map { googleOpenAPISchema(from: $0, isRoot: false) ?? .object([:]) })
        }
    }
    if let anyOf = object["anyOf"]?.arrayValue {
        let nonNullSchemas = anyOf.filter { $0["type"]?.stringValue != "null" }
        if nonNullSchemas.count != anyOf.count {
            result["nullable"] = true
            if nonNullSchemas.count == 1, let converted = googleOpenAPISchema(from: nonNullSchemas[0], isRoot: false)?.objectValue {
                result.merge(converted) { _, new in new }
            } else {
                result["anyOf"] = .array(nonNullSchemas.map { googleOpenAPISchema(from: $0, isRoot: false) ?? .object([:]) })
            }
        } else {
            result["anyOf"] = .array(anyOf.map { googleOpenAPISchema(from: $0, isRoot: false) ?? .object([:]) })
        }
    }

    return result.isEmpty ? nil : .object(result)
}
