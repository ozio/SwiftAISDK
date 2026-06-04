import Foundation

public struct AIJSONInstruction: Equatable, Hashable, Sendable {
    public var isEnabled: Bool
    public var schemaPrefix: String?
    public var schemaSuffix: String?

    public init(
        isEnabled: Bool = true,
        schemaPrefix: String? = nil,
        schemaSuffix: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.schemaPrefix = schemaPrefix
        self.schemaSuffix = schemaSuffix
    }

    public static let automatic = AIJSONInstruction()
    public static let disabled = AIJSONInstruction(isEnabled: false)
}

public protocol AIObjectSchema: Sendable {
    associatedtype Output: Decodable & Sendable

    var jsonSchema: JSONValue { get }
    var name: String? { get }
    var description: String? { get }
}

public extension AIObjectSchema {
    var name: String? { nil }
    var description: String? { nil }
}

public struct AIJSONSchema<Output: Decodable & Sendable>: AIObjectSchema {
    public var jsonSchema: JSONValue
    public var name: String?
    public var description: String?

    public init(
        _ jsonSchema: JSONValue,
        name: String? = nil,
        description: String? = nil,
        as type: Output.Type = Output.self
    ) {
        self.jsonSchema = jsonSchema
        self.name = name
        self.description = description
    }
}

