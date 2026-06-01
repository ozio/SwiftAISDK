import Foundation

public func addAdditionalPropertiesToJSONSchema(_ schema: JSONValue) -> JSONValue {
    guard case var .object(object) = schema else {
        return schema
    }

    if jsonSchemaTypeIncludesObject(object["type"]) {
        object["additionalProperties"] = .bool(false)
        if let properties = object["properties"]?.objectValue {
            object["properties"] = .object(properties.mapValues(addAdditionalPropertiesToJSONSchema))
        }
    }

    if let items = object["items"] {
        if let tupleItems = items.arrayValue {
            object["items"] = .array(tupleItems.map(addAdditionalPropertiesToJSONSchema))
        } else {
            object["items"] = addAdditionalPropertiesToJSONSchema(items)
        }
    }

    for key in ["anyOf", "allOf", "oneOf"] {
        if let schemas = object[key]?.arrayValue {
            object[key] = .array(schemas.map(addAdditionalPropertiesToJSONSchema))
        }
    }

    if let definitions = object["definitions"]?.objectValue {
        object["definitions"] = .object(definitions.mapValues(addAdditionalPropertiesToJSONSchema))
    }

    return .object(object)
}

private func jsonSchemaTypeIncludesObject(_ type: JSONValue?) -> Bool {
    if type?.stringValue == "object" {
        return true
    }
    return type?.arrayValue?.contains(where: { $0.stringValue == "object" }) == true
}

struct AIJSONSchemaValidationIssue: Error, CustomStringConvertible, Sendable {
    var path: String
    var message: String

    var description: String {
        "\(path): \(message)"
    }
}

enum AIJSONSchemaValidator {
    static func validate(_ value: JSONValue, schema: JSONValue, path: String = "$") throws {
        guard let object = schema.objectValue else { return }

        if let anyOf = object["anyOf"]?.arrayValue {
            guard anyOf.contains(where: { schema in
                (try? validate(value, schema: schema, path: path)) != nil
            }) else {
                throw issue(path, "does not match any allowed schema")
            }
        }

        if let oneOf = object["oneOf"]?.arrayValue {
            let matches = oneOf.reduce(0) { count, schema in
                count + ((try? validate(value, schema: schema, path: path)) != nil ? 1 : 0)
            }
            guard matches == 1 else {
                throw issue(path, "must match exactly one schema")
            }
        }

        if let allOf = object["allOf"]?.arrayValue {
            for schema in allOf {
                try validate(value, schema: schema, path: path)
            }
        }

        if let not = object["not"], (try? validate(value, schema: not, path: path)) != nil {
            throw issue(path, "matches a disallowed schema")
        }

        if let enumValues = object["enum"]?.arrayValue, !enumValues.contains(value) {
            throw issue(path, "must be one of \(enumValues.map(describe).joined(separator: ", "))")
        }

        if let constant = object["const"], constant != value {
            throw issue(path, "must equal \(describe(constant))")
        }

        if let type = object["type"] {
            let allowedTypes = schemaTypes(from: type)
            if !allowedTypes.isEmpty && !allowedTypes.contains(where: { matches(value, type: $0) }) {
                throw issue(path, "expected \(allowedTypes.joined(separator: " or ")), got \(typeName(for: value))")
            }
        }

        try validateObject(value, schema: object, path: path)
        try validateArray(value, schema: object, path: path)
        try validateString(value, schema: object, path: path)
        try validateNumber(value, schema: object, path: path)
    }

    private static func validateObject(_ value: JSONValue, schema: [String: JSONValue], path: String) throws {
        guard let valueObject = value.objectValue else { return }

        if let required = schema["required"]?.arrayValue {
            for field in required.compactMap(\.stringValue) where valueObject[field] == nil {
                throw issue(childPath(path, field), "is required")
            }
        }

        let properties = schema["properties"]?.objectValue ?? [:]
        for (key, propertySchema) in properties {
            if let propertyValue = valueObject[key] {
                try validate(propertyValue, schema: propertySchema, path: childPath(path, key))
            }
        }

        let knownProperties = Set(properties.keys)
        let additionalProperties = schema["additionalProperties"]
        let unknownKeys = valueObject.keys.filter { !knownProperties.contains($0) }.sorted()

        if additionalProperties?.boolValue == false, let key = unknownKeys.first {
            throw issue(childPath(path, key), "additional properties are not allowed")
        }

        if let additionalSchema = additionalProperties?.objectValue.map(JSONValue.object) {
            for key in unknownKeys {
                try validate(valueObject[key] ?? .null, schema: additionalSchema, path: childPath(path, key))
            }
        }
    }

    private static func validateArray(_ value: JSONValue, schema: [String: JSONValue], path: String) throws {
        guard let array = value.arrayValue else { return }

        if let minItems = schema["minItems"]?.intValue, array.count < minItems {
            throw issue(path, "must contain at least \(minItems) item(s)")
        }
        if let maxItems = schema["maxItems"]?.intValue, array.count > maxItems {
            throw issue(path, "must contain at most \(maxItems) item(s)")
        }

        if schema["uniqueItems"]?.boolValue == true && Set(array).count != array.count {
            throw issue(path, "must contain unique items")
        }

        if let itemSchema = schema["items"] {
            if let tupleSchemas = itemSchema.arrayValue {
                for (index, item) in array.enumerated() where index < tupleSchemas.count {
                    try validate(item, schema: tupleSchemas[index], path: "\(path)[\(index)]")
                }
            } else {
                for (index, item) in array.enumerated() {
                    try validate(item, schema: itemSchema, path: "\(path)[\(index)]")
                }
            }
        }
    }

    private static func validateString(_ value: JSONValue, schema: [String: JSONValue], path: String) throws {
        guard let string = value.stringValue else { return }
        if let minLength = schema["minLength"]?.intValue, string.count < minLength {
            throw issue(path, "must contain at least \(minLength) character(s)")
        }
        if let maxLength = schema["maxLength"]?.intValue, string.count > maxLength {
            throw issue(path, "must contain at most \(maxLength) character(s)")
        }
    }

    private static func validateNumber(_ value: JSONValue, schema: [String: JSONValue], path: String) throws {
        guard let number = value.doubleValue else { return }
        if let minimum = schema["minimum"]?.doubleValue, number < minimum {
            throw issue(path, "must be >= \(minimum)")
        }
        if let maximum = schema["maximum"]?.doubleValue, number > maximum {
            throw issue(path, "must be <= \(maximum)")
        }
        if let exclusiveMinimum = schema["exclusiveMinimum"]?.doubleValue, number <= exclusiveMinimum {
            throw issue(path, "must be > \(exclusiveMinimum)")
        }
        if let exclusiveMaximum = schema["exclusiveMaximum"]?.doubleValue, number >= exclusiveMaximum {
            throw issue(path, "must be < \(exclusiveMaximum)")
        }
        if let multipleOf = schema["multipleOf"]?.doubleValue, multipleOf != 0 {
            let divided = number / multipleOf
            if divided.rounded() != divided {
                throw issue(path, "must be a multiple of \(multipleOf)")
            }
        }
    }

    private static func schemaTypes(from value: JSONValue) -> [String] {
        if let string = value.stringValue { return [string] }
        return value.arrayValue?.compactMap(\.stringValue) ?? []
    }

    private static func matches(_ value: JSONValue, type: String) -> Bool {
        switch type {
        case "object":
            return value.objectValue != nil
        case "array":
            return value.arrayValue != nil
        case "string":
            return value.stringValue != nil
        case "number":
            return value.doubleValue != nil
        case "integer":
            guard let number = value.doubleValue else { return false }
            return number.rounded() == number
        case "boolean":
            return value.boolValue != nil
        case "null":
            return value == .null
        default:
            return true
        }
    }

    private static func typeName(for value: JSONValue) -> String {
        switch value {
        case .object:
            return "object"
        case .array:
            return "array"
        case .string:
            return "string"
        case let .number(number):
            return number.rounded() == number ? "integer" : "number"
        case .bool:
            return "boolean"
        case .null:
            return "null"
        }
    }

    private static func childPath(_ path: String, _ key: String) -> String {
        key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) == nil ? "\(path)[\"\(key)\"]" : "\(path).\(key)"
    }

    private static func describe(_ value: JSONValue) -> String {
        switch value {
        case let .string(string):
            return "\"\(string)\""
        case let .number(number):
            return String(number)
        case let .bool(bool):
            return String(bool)
        case .null:
            return "null"
        case .array, .object:
            return String(data: (try? encodeJSONBody(value)) ?? Data(), encoding: .utf8) ?? "\(value)"
        }
    }

    private static func issue(_ path: String, _ message: String) -> AIJSONSchemaValidationIssue {
        AIJSONSchemaValidationIssue(path: path, message: message)
    }
}
