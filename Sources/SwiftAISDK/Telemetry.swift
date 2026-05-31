import Foundation

public enum AITelemetryEventKind: String, Equatable, Sendable {
    case start
    case retry
    case end
    case error
}

public struct AITelemetryEvent: Equatable, Sendable {
    public var kind: AITelemetryEventKind
    public var callID: String
    public var operationID: String
    public var providerID: String
    public var modelID: String?
    public var functionID: String?
    public var attempt: Int?
    public var maxRetries: Int?
    public var delayNanoseconds: UInt64?
    public var durationNanoseconds: UInt64?
    public var input: JSONValue?
    public var output: JSONValue?
    public var usage: TokenUsage?
    public var warnings: [AIWarning]
    public var providerMetadata: [String: JSONValue]
    public var responseMetadata: AIResponseMetadata
    public var errorDescription: String?
    public var metadata: [String: JSONValue]
    public var recordInputs: Bool?
    public var recordOutputs: Bool?

    public init(
        kind: AITelemetryEventKind,
        callID: String,
        operationID: String,
        providerID: String,
        modelID: String? = nil,
        functionID: String? = nil,
        attempt: Int? = nil,
        maxRetries: Int? = nil,
        delayNanoseconds: UInt64? = nil,
        durationNanoseconds: UInt64? = nil,
        input: JSONValue? = nil,
        output: JSONValue? = nil,
        usage: TokenUsage? = nil,
        warnings: [AIWarning] = [],
        providerMetadata: [String: JSONValue] = [:],
        responseMetadata: AIResponseMetadata = AIResponseMetadata(),
        errorDescription: String? = nil,
        metadata: [String: JSONValue] = [:],
        recordInputs: Bool? = nil,
        recordOutputs: Bool? = nil
    ) {
        self.kind = kind
        self.callID = callID
        self.operationID = operationID
        self.providerID = providerID
        self.modelID = modelID
        self.functionID = functionID
        self.attempt = attempt
        self.maxRetries = maxRetries
        self.delayNanoseconds = delayNanoseconds
        self.durationNanoseconds = durationNanoseconds
        self.input = input
        self.output = output
        self.usage = usage
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.responseMetadata = responseMetadata
        self.errorDescription = errorDescription
        self.metadata = metadata
        self.recordInputs = recordInputs
        self.recordOutputs = recordOutputs
    }
}

public protocol AITelemetryIntegration: Sendable {
    func record(_ event: AITelemetryEvent) async
}

public struct AITelemetryOptions: Sendable {
    public var isEnabled: Bool?
    public var recordInputs: Bool
    public var recordOutputs: Bool
    public var functionID: String?
    public var metadata: [String: JSONValue]
    public var integrations: [any AITelemetryIntegration]?

    public init(
        isEnabled: Bool? = nil,
        recordInputs: Bool = true,
        recordOutputs: Bool = true,
        functionID: String? = nil,
        metadata: [String: JSONValue] = [:],
        integrations: [any AITelemetryIntegration]? = nil
    ) {
        self.isEnabled = isEnabled
        self.recordInputs = recordInputs
        self.recordOutputs = recordOutputs
        self.functionID = functionID
        self.metadata = metadata
        self.integrations = integrations
    }

    public static let disabled = AITelemetryOptions(isEnabled: false)
}

public enum AITelemetry {
    private static let registry = AITelemetryRegistry()

    public static func register(_ integrations: any AITelemetryIntegration...) {
        registry.register(integrations)
    }

    public static func register(_ integrations: [any AITelemetryIntegration]) {
        registry.register(integrations)
    }

    public static func registeredIntegrations() -> [any AITelemetryIntegration] {
        registry.integrations()
    }

    static func removeAllIntegrations() {
        registry.removeAll()
    }
}

private final class AITelemetryRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [any AITelemetryIntegration] = []

    func register(_ integrations: [any AITelemetryIntegration]) {
        lock.lock()
        values.append(contentsOf: integrations)
        lock.unlock()
    }

    func integrations() -> [any AITelemetryIntegration] {
        lock.lock()
        let result = values
        lock.unlock()
        return result
    }

    func removeAll() {
        lock.lock()
        values.removeAll()
        lock.unlock()
    }
}
