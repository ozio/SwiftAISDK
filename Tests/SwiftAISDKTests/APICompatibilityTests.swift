import Foundation
import Testing
@testable import SwiftAISDK

@Suite("SwiftAISDK 1.9 source compatibility")
struct APICompatibilityTests {
    @Test func legacyCallableSymbolsRemainReferencable() {
        let directEvaluation: (
            any AIEvaluationModelV4,
            JSONValue,
            [String: AIEvaluationQuestion],
            Int?,
            AIAbortSignal?,
            [String: String],
            [String: JSONValue]
        ) async throws -> AIEvaluationResult = AI.experimentalEvaluate(
            model:state:questions:maxRetries:abortSignal:headers:providerOptions:
        )
        let modelIDEvaluation: (
            String,
            JSONValue,
            [String: AIEvaluationQuestion],
            Int?,
            AIAbortSignal?,
            [String: String],
            [String: JSONValue]
        ) async throws -> AIEvaluationResult = AI.experimentalEvaluate(
            model:state:questions:maxRetries:abortSignal:headers:providerOptions:
        )
        let modelReferenceEvaluation: (
            AIEvaluationModelReference,
            JSONValue,
            [String: AIEvaluationQuestion],
            Int?,
            AIAbortSignal?,
            [String: String],
            [String: JSONValue]
        ) async throws -> AIEvaluationResult = AI.experimentalEvaluate(
            model:state:questions:maxRetries:abortSignal:headers:providerOptions:
        )
        let snapshots: (
            AsyncThrowingStream<LanguageStreamPart, Error>,
            String,
            Bool
        ) -> AsyncThrowingStream<AIUIMessage, Error> = AIUIMessageStreamReducer.snapshots(
            from:messageID:terminateOnError:
        )
        let approvalRequest: (
            String,
            String,
            String,
            String?,
            JSONValue?,
            String?,
            Bool,
            [String: JSONValue]
        ) -> AIToolApprovalRequest = AIToolApprovalRequest.init(
            id:toolName:arguments:toolCallID:descriptor:reason:isAutomatic:providerMetadata:
        )
        let openResponses: (
            String,
            String,
            ProviderSettings
        ) throws -> OpenAICompatibleProvider = AIProviders.openResponses(name:url:settings:)
        let telemetryEvent: (
            Telemetry.Event.Kind,
            String,
            String,
            String,
            String?,
            String?,
            Int?,
            Int?,
            UInt64?,
            UInt64?,
            JSONValue?,
            JSONValue?,
            TokenUsage?,
            [AIWarning],
            [String: JSONValue],
            AIResponseMetadata,
            String?,
            [String: JSONValue],
            Bool,
            Bool
        ) -> Telemetry.Event = Telemetry.Event.init(
            kind:callID:operationID:providerID:modelID:functionID:attempt:maxRetries:
                delayNanoseconds:durationNanoseconds:input:output:usage:warnings:
                providerMetadata:responseMetadata:errorDescription:metadata:
                includesInput:includesOutput:
        )
        let telemetryOptions: (
            Bool,
            Bool,
            Bool,
            String?,
            [String: JSONValue],
            [any Telemetry.Integration]?
        ) -> Telemetry.Options = Telemetry.Options.init(
            isEnabled:includesInput:includesOutput:functionID:metadata:integrations:
        )

        _ = directEvaluation
        _ = modelIDEvaluation
        _ = modelReferenceEvaluation
        _ = snapshots
        _ = approvalRequest
        _ = openResponses
        _ = telemetryEvent
        _ = telemetryOptions
    }

    @Test func legacyInitializersUseNewDefaultsWithoutLosingOldFields() {
        let request = AIToolApprovalRequest(
            id: "approval",
            toolName: "delete_record",
            arguments: #"{"id":"record-1"}"#,
            toolCallID: "call-1",
            descriptor: ["risk": "high"],
            reason: "Needs confirmation",
            isAutomatic: true,
            providerMetadata: ["provider": ["trace": "trace-1"]]
        )
        let event = Telemetry.Event(
            kind: .start,
            callID: "call",
            operationID: "operation",
            providerID: "provider",
            metadata: ["key": "value"]
        )
        let options = Telemetry.Options(
            isEnabled: true,
            includesInput: false,
            includesOutput: false,
            functionID: "function",
            metadata: ["key": "value"],
            integrations: nil
        )

        #expect(request.inputSchemaInput == nil)
        #expect(request.descriptor == ["risk": "high"])
        #expect(request.reason == "Needs confirmation")
        #expect(event.runtimeContext.isEmpty)
        #expect(options.includeRuntimeContext == nil)
    }
}
