import Foundation

func googleOpenAPISchema(from schema: JSONValue, isRoot: Bool) throws -> JSONValue? {
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
    for key in ["description", "required", "format", "minLength"] {
        if let value = object[key] {
            result[key] = value
        }
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

    let enumValues = object["enum"]?.arrayValue ?? object["const"].map { [$0] }
    if let enumValues {
        try googleAddEnumToSchema(values: enumValues, declaredType: object["type"], result: &result)
    }

    if let properties = object["properties"]?.objectValue {
        var converted: [String: JSONValue] = [:]
        for (name, propertySchema) in properties {
            converted[name] = try googleOpenAPISchema(from: propertySchema, isRoot: false) ?? .object([:])
        }
        result["properties"] = .object(converted)
    }
    if let items = object["items"] {
        if let array = items.arrayValue {
            result["items"] = .array(try array.map { try googleOpenAPISchema(from: $0, isRoot: false) ?? .object([:]) })
        } else if let converted = try googleOpenAPISchema(from: items, isRoot: false) {
            result["items"] = converted
        }
    }
    for key in ["allOf", "oneOf"] {
        if let array = object[key]?.arrayValue {
            result[key] = .array(try array.map { try googleOpenAPISchema(from: $0, isRoot: false) ?? .object([:]) })
        }
    }
    if let anyOf = object["anyOf"]?.arrayValue {
        let nonNullSchemas = anyOf.filter { $0["type"]?.stringValue != "null" }
        if nonNullSchemas.count != anyOf.count {
            result["nullable"] = true
            if nonNullSchemas.count == 1, let converted = try googleOpenAPISchema(from: nonNullSchemas[0], isRoot: false)?.objectValue {
                result.merge(converted) { _, new in new }
            } else {
                result["anyOf"] = .array(try nonNullSchemas.map { try googleOpenAPISchema(from: $0, isRoot: false) ?? .object([:]) })
            }
        } else {
            result["anyOf"] = .array(try anyOf.map { try googleOpenAPISchema(from: $0, isRoot: false) ?? .object([:]) })
        }
    }

    return result.isEmpty ? nil : .object(result)
}

private enum GoogleEnumPrimitiveType: String {
    case string
    case number
    case integer
    case boolean
}

private func googleAddEnumToSchema(
    values: [JSONValue],
    declaredType: JSONValue?,
    result: inout [String: JSONValue]
) throws {
    let declaredTypes = googleDeclaredSchemaTypes(declaredType)
    let nullable = declaredTypes.contains("null") || (declaredType == nil && values.contains(.null))
    let enumValues = nullable ? values.filter { $0 != .null } : values

    if !values.isEmpty, values.allSatisfy({ $0 == .null }) {
        let typeAllowsNull = declaredType == nil || declaredTypes.contains("null")
        if typeAllowsNull {
            result["type"] = .string("null")
            if declaredType?.arrayValue != nil {
                result.removeValue(forKey: "anyOf")
            }
            return
        }
    }

    guard let enumType = googleEnumPrimitiveType(values: enumValues, declaredType: declaredType) else {
        throw AIError.invalidArgument(
            argument: "schema",
            message: "Google does not support this JSON Schema enum. Enum values must share one supported primitive type and match the schema type."
        )
    }

    result["type"] = .string(enumType.rawValue)
    if declaredType?.arrayValue != nil {
        result.removeValue(forKey: "anyOf")
    }
    if nullable {
        result["nullable"] = .bool(true)
    }

    if enumType == .string {
        result["enum"] = .array(enumValues)
    } else {
        result["format"] = .string("enum")
        result["enum"] = .array(enumValues.map { .string(googleEnumWireValue($0)) })
    }
}

private func googleEnumPrimitiveType(values: [JSONValue], declaredType: JSONValue?) -> GoogleEnumPrimitiveType? {
    guard !values.isEmpty else { return nil }

    let allows: (GoogleEnumPrimitiveType) -> Bool = { type in
        guard declaredType != nil else { return true }
        return googleDeclaredSchemaTypes(declaredType).contains(type.rawValue)
    }

    if allows(.string), values.allSatisfy({ $0.stringValue != nil }) {
        return .string
    }

    let numbers = values.compactMap(\.doubleValue)
    if numbers.count == values.count, numbers.allSatisfy(\.isFinite) {
        if allows(.number) {
            return .number
        }
        if allows(.integer), numbers.allSatisfy({ $0.rounded() == $0 }) {
            return .integer
        }
    }

    if allows(.boolean), values.allSatisfy({ $0.boolValue != nil }) {
        return .boolean
    }

    return nil
}

private func googleDeclaredSchemaTypes(_ value: JSONValue?) -> Set<String> {
    if let string = value?.stringValue {
        return [string]
    }
    return Set(value?.arrayValue?.compactMap(\.stringValue) ?? [])
}

private func googleEnumWireValue(_ value: JSONValue) -> String {
    switch value {
    case let .number(number):
        if number.rounded() == number,
           number >= Double(Int.min),
           number <= Double(Int.max) {
            return String(Int(number))
        }
        return String(number)
    case let .bool(boolean):
        return boolean ? "true" : "false"
    default:
        return getErrorMessage(value)
    }
}
