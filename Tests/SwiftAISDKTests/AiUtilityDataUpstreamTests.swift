import Foundation
import Testing
@testable import SwiftAISDK

@Test func aiGetPotentialStartIndexReturnsNilForEmptySearchLikeUpstream() {
    #expect(getPotentialStartIndex("1234567890", "") == nil)
}

@Test func aiGetPotentialStartIndexReturnsNilWhenSearchIsNotInTextLikeUpstream() {
    #expect(getPotentialStartIndex("1234567890", "a") == nil)
}

@Test func aiGetPotentialStartIndexReturnsIndexForContainedSearchLikeUpstream() {
    #expect(getPotentialStartIndex("1234567890", "1234567890") == 0)
}

@Test func aiGetPotentialStartIndexReturnsPotentialSuffixStartLikeUpstream() {
    #expect(getPotentialStartIndex("1234567890", "0123") == 9)
    #expect(getPotentialStartIndex("1234567890", "90123") == 8)
    #expect(getPotentialStartIndex("1234567890", "890123") == 7)
}

@Test func aiMergeObjectsMergesTwoFlatObjectsLikeUpstream() {
    let target: [String: JSONValue] = ["a": 1, "b": 2]
    let source: [String: JSONValue] = ["b": 3, "c": 4]

    #expect(mergeObjects(target, source) == ["a": 1, "b": 3, "c": 4])
    #expect(target == ["a": 1, "b": 2])
    #expect(source == ["b": 3, "c": 4])
}

@Test func aiMergeObjectsDeeplyMergesNestedObjectsLikeUpstream() {
    let target: [String: JSONValue] = ["a": 1, "b": ["c": 2, "d": 3]]
    let source: [String: JSONValue] = ["b": ["c": 4, "e": 5]]

    #expect(mergeObjects(target, source) == ["a": 1, "b": ["c": 4, "d": 3, "e": 5]])
}

@Test func aiMergeObjectsReplacesArraysInsteadOfMergingLikeUpstream() {
    let target: [String: JSONValue] = ["a": [1, 2, 3], "b": 2]
    let source: [String: JSONValue] = ["a": [4, 5]]

    #expect(mergeObjects(target, source) == ["a": [4, 5], "b": 2])
}

@Test func aiMergeObjectsHandlesNullValuesLikeUpstream() {
    let target: [String: JSONValue] = ["a": 1, "b": nil]
    let source: [String: JSONValue] = ["a": nil, "b": 2, "d": nil]

    #expect(mergeObjects(target, source) == ["a": nil, "b": 2, "d": nil])
}

@Test func aiMergeObjectsHandlesComplexNestedStructuresLikeUpstream() {
    let target: [String: JSONValue] = [
        "a": 1,
        "b": [
            "c": [1, 2, 3],
            "d": ["e": 4, "f": 5]
        ]
    ]
    let source: [String: JSONValue] = [
        "b": [
            "c": [4, 5],
            "d": ["f": 6, "g": 7]
        ],
        "h": 8
    ]

    #expect(mergeObjects(target, source) == [
        "a": 1,
        "b": [
            "c": [4, 5],
            "d": ["e": 4, "f": 6, "g": 7]
        ],
        "h": 8
    ])
}

@Test func aiMergeObjectsHandlesEmptyAndNilObjectsLikeUpstream() {
    #expect(mergeObjects([:], ["a": 1]) == ["a": 1])
    #expect(mergeObjects(["a": 1], [:]) == ["a": 1])
    #expect(mergeObjects(nil, nil) == nil)
    #expect(mergeObjects(["a": 1], nil) == ["a": 1])
    #expect(mergeObjects(nil, ["b": 2]) == ["b": 2])
}

@Test func aiMergeObjectsIgnoresDangerousPrototypeKeysLikeUpstream() {
    let malicious: [String: JSONValue] = [
        "__proto__": ["a": 1],
        "constructor": ["prototype": ["b": 2]],
        "prototype": ["c": 3],
        "safe": "value"
    ]

    #expect(mergeObjects(["existing": "ok"], malicious) == ["existing": "ok", "safe": "value"])
}

@Test func aiMergeObjectsIgnoresNestedDangerousKeysLikeUpstream() {
    let base: [String: JSONValue] = ["metadata": ["user": "alice"]]
    let malicious: [String: JSONValue] = [
        "metadata": [
            "__proto__": ["polluted": true],
            "role": "admin"
        ]
    ]

    #expect(mergeObjects(base, malicious) == ["metadata": ["user": "alice", "role": "admin"]])
}

@Test func aiIsDeepEqualDataComparesPrimitivesLikeUpstream() {
    #expect(isDeepEqualData(1, 1))
    #expect(!isDeepEqualData(1, 2))
}

@Test func aiIsDeepEqualDataReturnsFalseForDifferentTypesLikeUpstream() {
    #expect(!isDeepEqualData(["a": 1], 1))
    #expect(!isDeepEqualData(["a": 1], nil))
}

@Test func aiIsDeepEqualDataComparesObjectsLikeUpstream() {
    #expect(isDeepEqualData(["a": 1, "b": 2], ["a": 1, "b": 2]))
    #expect(!isDeepEqualData(["a": 1, "b": 2], ["a": 1, "b": 3]))
    #expect(!isDeepEqualData(["a": 1, "b": 2], ["a": 1, "b": 2, "c": 3]))
}

@Test func aiIsDeepEqualDataComparesNestedObjectsLikeUpstream() {
    #expect(isDeepEqualData(["a": ["c": 1], "b": 2], ["a": ["c": 1], "b": 2]))
    #expect(!isDeepEqualData(["a": ["c": 1], "b": 2], ["a": ["c": 2], "b": 2]))
}

@Test func aiIsDeepEqualDataComparesArraysLikeUpstream() {
    #expect(isDeepEqualData([1, 2, 3], [1, 2, 3]))
    #expect(!isDeepEqualData([1, 2, 3], [1, 2, 4]))
}

@Test func aiIsDeepEqualDataDistinguishesArrayAndObjectLikeUpstream() {
    #expect(!isDeepEqualData(["0": "one", "1": "two", "length": 2], ["one", "two"]))
}
