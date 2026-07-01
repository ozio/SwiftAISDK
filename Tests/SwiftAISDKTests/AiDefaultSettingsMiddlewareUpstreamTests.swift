import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiDefaultSettingsMiddlewareAppliesDefaultLanguageSettingsLikeUpstream() {
    let settings = AIDefaultLanguageModelSettings(
        temperature: 0.7,
        topP: 0.9,
        maxOutputTokens: 100,
        stopSequences: ["stop"]
    )

    let result = applyingDefaultSettings(settings, to: LanguageModelRequest(messages: [.user("Hello")]))

    #expect(result.temperature == 0.7)
    #expect(result.topP == 0.9)
    #expect(result.maxOutputTokens == 100)
    #expect(result.stopSequences == ["stop"])
}

@Test func aiDefaultSettingsMiddlewarePreservesUserProvidedLanguageSettingsLikeUpstream() {
    let settings = AIDefaultLanguageModelSettings(
        temperature: 0.7,
        topP: 0.9,
        maxOutputTokens: 100,
        stopSequences: ["stop"]
    )

    let result = applyingDefaultSettings(settings, to: LanguageModelRequest(
        messages: [.user("Hello")],
        temperature: 0,
        topP: 0.5,
        maxOutputTokens: 50,
        stopSequences: ["end"]
    ))

    #expect(result.temperature == 0)
    #expect(result.topP == 0.5)
    #expect(result.maxOutputTokens == 50)
    #expect(result.stopSequences == ["end"])
}

@Test func aiDefaultSettingsMiddlewareMergesProviderOptionsDeeplyLikeUpstream() {
    let settings = AIDefaultLanguageModelSettings(providerOptions: [
        "anthropic": [
            "cacheControl": ["type": "ephemeral"],
            "feature": ["enabled": true],
            "tools": [
                "retrieval": ["enabled": true],
                "math": ["enabled": true]
            ]
        ],
        "openai": ["logit_bias": ["50256": -100]]
    ])

    let result = applyingDefaultSettings(settings, to: LanguageModelRequest(
        messages: [.user("Hello")],
        providerOptions: [
            "anthropic": [
                "feature": ["enabled": false],
                "otherSetting": "value",
                "tools": [
                    "retrieval": ["enabled": false],
                    "code": ["enabled": true]
                ]
            ]
        ]
    ))

    #expect(result.providerOptions == [
        "anthropic": [
            "cacheControl": ["type": "ephemeral"],
            "feature": ["enabled": false],
            "otherSetting": "value",
            "tools": [
                "retrieval": ["enabled": false],
                "math": ["enabled": true],
                "code": ["enabled": true]
            ]
        ],
        "openai": ["logit_bias": ["50256": -100]]
    ])
}

@Test func aiDefaultSettingsMiddlewareMergesHeadersAndHandlesEmptyCasesLikeUpstream() {
    let result = applyingDefaultSettings(
        AIDefaultLanguageModelSettings(headers: [
            "X-Custom-Header": "test",
            "X-Another-Header": "test2"
        ]),
        to: LanguageModelRequest(messages: [.user("Hello")], headers: [
            "X-Custom-Header": "test2"
        ])
    )

    #expect(result.headers == [
        "X-Custom-Header": "test2",
        "X-Another-Header": "test2"
    ])

    let emptyDefaults = applyingDefaultSettings(
        AIDefaultLanguageModelSettings(headers: [:]),
        to: LanguageModelRequest(messages: [.user("Hello")], headers: ["X-Param-Header": "param"])
    )
    let emptyRequest = applyingDefaultSettings(
        AIDefaultLanguageModelSettings(headers: ["X-Default-Header": "default"]),
        to: LanguageModelRequest(messages: [.user("Hello")], headers: [:])
    )
    let bothEmpty = applyingDefaultSettings(
        AIDefaultLanguageModelSettings(),
        to: LanguageModelRequest(messages: [.user("Hello")])
    )

    #expect(emptyDefaults.headers == ["X-Param-Header": "param"])
    #expect(emptyRequest.headers == ["X-Default-Header": "default"])
    #expect(bothEmpty.headers.isEmpty)
}

@Test func aiDefaultSettingsMiddlewareHandlesEmptyProviderOptionsLikeUpstream() {
    let emptyDefaults = applyingDefaultSettings(
        AIDefaultLanguageModelSettings(providerOptions: [:]),
        to: LanguageModelRequest(messages: [.user("Hello")], providerOptions: [
            "openai": ["user": "param-user"]
        ])
    )
    let emptyRequest = applyingDefaultSettings(
        AIDefaultLanguageModelSettings(providerOptions: [
            "anthropic": ["user": "default-user"]
        ]),
        to: LanguageModelRequest(messages: [.user("Hello")], providerOptions: [:])
    )
    let bothEmpty = applyingDefaultSettings(
        AIDefaultLanguageModelSettings(),
        to: LanguageModelRequest(messages: [.user("Hello")])
    )

    #expect(emptyDefaults.providerOptions == ["openai": ["user": "param-user"]])
    #expect(emptyRequest.providerOptions == ["anthropic": ["user": "default-user"]])
    #expect(bothEmpty.providerOptions.isEmpty)
}

@Test func aiDefaultEmbeddingSettingsMiddlewareMergesHeadersLikeUpstream() {
    let result = applyingDefaultEmbeddingSettings(
        AIDefaultEmbeddingModelSettings(headers: [
            "X-Custom-Header": "test",
            "X-Another-Header": "test2"
        ]),
        to: EmbeddingRequest(values: ["hello world"], headers: [
            "X-Custom-Header": "test2"
        ])
    )

    #expect(result.headers == [
        "X-Custom-Header": "test2",
        "X-Another-Header": "test2"
    ])

    let emptyDefaults = applyingDefaultEmbeddingSettings(
        AIDefaultEmbeddingModelSettings(headers: [:]),
        to: EmbeddingRequest(values: ["hello world"], headers: ["X-Param-Header": "param"])
    )
    let emptyRequest = applyingDefaultEmbeddingSettings(
        AIDefaultEmbeddingModelSettings(headers: ["X-Default-Header": "default"]),
        to: EmbeddingRequest(values: ["hello world"], headers: [:])
    )
    let bothEmpty = applyingDefaultEmbeddingSettings(
        AIDefaultEmbeddingModelSettings(),
        to: EmbeddingRequest(values: ["hello world"])
    )

    #expect(emptyDefaults.headers == ["X-Param-Header": "param"])
    #expect(emptyRequest.headers == ["X-Default-Header": "default"])
    #expect(bothEmpty.headers.isEmpty)
}

@Test func aiDefaultEmbeddingSettingsMiddlewareHandlesProviderOptionsLikeUpstream() {
    let emptyDefaults = applyingDefaultEmbeddingSettings(
        AIDefaultEmbeddingModelSettings(providerOptions: [:]),
        to: EmbeddingRequest(values: ["hello world"], providerOptions: [
            "google": [
                "outputDimensionality": 512,
                "taskType": "SEMANTIC_SIMILARITY"
            ]
        ])
    )
    let emptyRequest = applyingDefaultEmbeddingSettings(
        AIDefaultEmbeddingModelSettings(providerOptions: [
            "google": [
                "outputDimensionality": 512,
                "taskType": "SEMANTIC_SIMILARITY"
            ]
        ]),
        to: EmbeddingRequest(values: ["hello world"], providerOptions: [:])
    )
    let bothEmpty = applyingDefaultEmbeddingSettings(
        AIDefaultEmbeddingModelSettings(),
        to: EmbeddingRequest(values: ["hello world"])
    )

    #expect(emptyDefaults.providerOptions == [
        "google": [
            "outputDimensionality": 512,
            "taskType": "SEMANTIC_SIMILARITY"
        ]
    ])
    #expect(emptyRequest.providerOptions == [
        "google": [
            "outputDimensionality": 512,
            "taskType": "SEMANTIC_SIMILARITY"
        ]
    ])
    #expect(bothEmpty.providerOptions.isEmpty)
}
