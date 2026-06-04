import Foundation

func telemetryEvent(
    kind: Telemetry.Event.Kind,
    callID: String,
    operationID: String,
    providerID: String,
    modelID: String?,
    options: Telemetry.Options?,
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
) -> Telemetry.Event {
    let includesInput = options?.includesInput ?? true
    let includesOutput = options?.includesOutput ?? true
    return Telemetry.Event(
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
        input: includesInput ? input : nil,
        output: includesOutput ? output : nil,
        usage: usage,
        warnings: warnings,
        providerMetadata: providerMetadata,
        responseMetadata: responseMetadata,
        errorDescription: errorDescription,
        metadata: options?.metadata ?? [:],
        includesInput: includesInput,
        includesOutput: includesOutput
    )
}
