import Testing
@testable import SwiftAISDK

@Suite(.serialized)
struct AiTelemetryDispatcherUpstreamTests {
    @Test func telemetryDispatcherNoopsWhenNoIntegrationsAreConfiguredLikeUpstream() async throws {
        Telemetry.removeAllIntegrations()
        defer { Telemetry.removeAllIntegrations() }

        let dispatcher = TelemetryDispatcher(options: nil)

        await dispatcher.record(dispatcherTestEvent(kind: .start))
        let languageResult = try await dispatcher.executeLanguageModelCall(
            callID: "call-1",
            operationID: "ai.test",
            providerID: "mock",
            modelID: "mock-model"
        ) {
            "language-result"
        }
        let toolResult = try await dispatcher.executeTool(
            callID: "call-1",
            toolCallID: "tool-1",
            toolName: "tool"
        ) {
            "tool-result"
        }

        #expect(!dispatcher.isEnabled)
        #expect(languageResult == "language-result")
        #expect(toolResult == "tool-result")
    }

    @Test func telemetryDispatcherBroadcastsEventsToLocalIntegrationsLikeUpstream() async {
        Telemetry.removeAllIntegrations()
        defer { Telemetry.removeAllIntegrations() }
        let log = ExecutionWrapperLog()
        let dispatcher = TelemetryDispatcher(options: Telemetry.Options(integrations: [
            DispatcherRecordingTelemetry(name: "first", log: log),
            DispatcherRecordingTelemetry(name: "second", log: log)
        ]))

        await dispatcher.record(dispatcherTestEvent(kind: .start))

        #expect(await log.entries() == [
            "first:record:start:ai.test",
            "second:record:start:ai.test"
        ])
    }

    @Test func telemetryDispatcherDisablesLocalAndGlobalIntegrationsWhenIsEnabledFalseLikeUpstream() async throws {
        Telemetry.removeAllIntegrations()
        defer { Telemetry.removeAllIntegrations() }
        let log = ExecutionWrapperLog()
        Telemetry.register(DispatcherRecordingTelemetry(name: "global", log: log))
        let dispatcher = TelemetryDispatcher(options: Telemetry.Options(
            isEnabled: false,
            integrations: [DispatcherRecordingTelemetry(name: "local", log: log)]
        ))

        await dispatcher.record(dispatcherTestEvent(kind: .start))
        let languageResult = try await dispatcher.executeLanguageModelCall(
            callID: "call-1",
            operationID: "ai.test",
            providerID: "mock",
            modelID: nil
        ) {
            await log.append("execute-language")
            return "done"
        }

        #expect(!dispatcher.isEnabled)
        #expect(languageResult == "done")
        #expect(await log.entries() == ["execute-language"])
    }

    @Test func telemetryDispatcherUsesGlobalIntegrationsWhenNoLocalIntegrationsProvidedLikeUpstream() async {
        Telemetry.removeAllIntegrations()
        defer { Telemetry.removeAllIntegrations() }
        let log = ExecutionWrapperLog()
        Telemetry.register(DispatcherRecordingTelemetry(name: "global", log: log))
        let dispatcher = TelemetryDispatcher(options: Telemetry.Options())

        await dispatcher.record(dispatcherTestEvent(kind: .end))

        #expect(await log.entries() == ["global:record:end:ai.test"])
    }

    @Test func telemetryDispatcherUsesOnlyLocalIntegrationsWhenProvidedLikeUpstream() async {
        Telemetry.removeAllIntegrations()
        defer { Telemetry.removeAllIntegrations() }
        let log = ExecutionWrapperLog()
        Telemetry.register(DispatcherRecordingTelemetry(name: "global", log: log))
        let dispatcher = TelemetryDispatcher(options: Telemetry.Options(integrations: [
            DispatcherRecordingTelemetry(name: "local", log: log)
        ]))

        await dispatcher.record(dispatcherTestEvent(kind: .start))

        #expect(await log.entries() == ["local:record:start:ai.test"])
    }

    @Test func telemetryDispatcherWrapsLanguageModelExecutionLikeUpstream() async throws {
        Telemetry.removeAllIntegrations()
        defer { Telemetry.removeAllIntegrations() }
        let log = ExecutionWrapperLog()
        let dispatcher = TelemetryDispatcher(options: Telemetry.Options(integrations: [
            DispatcherRecordingTelemetry(name: "wrapper", log: log)
        ]))

        let result = try await dispatcher.executeLanguageModelCall(
            callID: "call-1",
            operationID: "ai.test",
            providerID: "mock",
            modelID: "mock-model"
        ) {
            await log.append("execute-language")
            return "result"
        }

        #expect(result == "wrapper:result")
        #expect(await log.entries() == [
            "wrapper:language-before:ai.test:mock-model",
            "execute-language",
            "wrapper:language-after"
        ])
    }

    @Test func telemetryDispatcherWrapsToolExecutionLikeUpstream() async throws {
        Telemetry.removeAllIntegrations()
        defer { Telemetry.removeAllIntegrations() }
        let log = ExecutionWrapperLog()
        let dispatcher = TelemetryDispatcher(options: Telemetry.Options(integrations: [
            DispatcherRecordingTelemetry(name: "wrapper", log: log)
        ]))

        let result = try await dispatcher.executeTool(
            callID: "call-1",
            toolCallID: "tool-1",
            toolName: "lookup"
        ) {
            await log.append("execute-tool")
            return "result"
        }

        #expect(result == "wrapper:result")
        #expect(await log.entries() == [
            "wrapper:tool-before:tool-1:lookup",
            "execute-tool",
            "wrapper:tool-after"
        ])
    }
}

private struct DispatcherRecordingTelemetry: Telemetry.Integration {
    var name: String
    var log: ExecutionWrapperLog

    func record(_ event: Telemetry.Event) async {
        await log.append("\(name):record:\(event.kind):\(event.operationID)")
    }

    func executeLanguageModelCall<Output: Sendable>(_ context: Telemetry.LanguageModelCallContext<Output>) async throws -> Output {
        await log.append("\(name):language-before:\(context.operationID):\(context.modelID ?? "unknown")")
        let result = try await context.execute()
        await log.append("\(name):language-after")
        guard let string = result as? String, let output = "\(name):\(string)" as? Output else {
            return result
        }
        return output
    }

    func executeTool<Output: Sendable>(_ context: Telemetry.ToolExecutionContext<Output>) async throws -> Output {
        await log.append("\(name):tool-before:\(context.toolCallID):\(context.toolName)")
        let result = try await context.execute()
        await log.append("\(name):tool-after")
        guard let string = result as? String, let output = "\(name):\(string)" as? Output else {
            return result
        }
        return output
    }
}

private func dispatcherTestEvent(kind: Telemetry.Event.Kind) -> Telemetry.Event {
    Telemetry.Event(
        kind: kind,
        callID: "call-1",
        operationID: "ai.test",
        providerID: "mock",
        modelID: "mock-model"
    )
}
