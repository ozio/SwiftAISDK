import Foundation

func telemetryEvent(
    kind: AITelemetryEventKind,
    callID: String,
    operationID: String,
    providerID: String,
    modelID: String?,
    options: AITelemetryOptions?,
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
    errorDescription: String? = nil
) -> AITelemetryEvent {
    let recordInputs = options?.recordInputs ?? true
    let recordOutputs = options?.recordOutputs ?? true
    return AITelemetryEvent(
        kind: kind,
        callID: callID,
        operationID: operationID,
        providerID: providerID,
        modelID: modelID,
        functionID: options?.functionID,
        attempt: attempt,
        maxRetries: maxRetries,
        delayNanoseconds: delayNanoseconds,
        durationNanoseconds: durationNanoseconds,
        input: recordInputs ? input : nil,
        output: recordOutputs ? output : nil,
        usage: usage,
        warnings: warnings,
        providerMetadata: providerMetadata,
        responseMetadata: responseMetadata,
        errorDescription: errorDescription,
        metadata: options?.metadata ?? [:],
        recordInputs: options?.recordInputs,
        recordOutputs: options?.recordOutputs
    )
}
