import Foundation

func transcriptionSegments(from items: JSONValue?, textKey: String = "text", startKey: String = "start", endKey: String = "end") -> [TranscriptionSegment] {
    items?.arrayValue?.compactMap { item in
        guard let text = item[textKey]?.stringValue, !text.isEmpty else { return nil }
        let start = item[startKey]?.doubleValue ?? 0
        let end = item[endKey]?.doubleValue ?? start
        return TranscriptionSegment(text: text, startSecond: start, endSecond: end)
    } ?? []
}

func transcriptionDuration(from segments: [TranscriptionSegment]) -> Double? {
    segments.map(\.endSecond).max()
}

func standardTranscriptionSegments(from raw: JSONValue) -> [TranscriptionSegment] {
    transcriptionSegments(from: raw["segments"])
}

func deepgramTranscriptionSegments(from raw: JSONValue) -> [TranscriptionSegment] {
    transcriptionSegments(from: raw["results"]?["channels"]?[0]?["alternatives"]?[0]?["words"], textKey: "word")
}

func elevenLabsTranscriptionSegments(from raw: JSONValue) -> [TranscriptionSegment] {
    transcriptionSegments(from: raw["words"])
}

func assemblyAITranscriptionSegments(from raw: JSONValue) -> [TranscriptionSegment] {
    transcriptionSegments(from: raw["words"])
}

func revAITranscriptionSegments(from raw: JSONValue) -> [TranscriptionSegment] {
    var segments: [TranscriptionSegment] = []
    for monologue in raw["monologues"]?.arrayValue ?? [] {
        var currentText = ""
        var segmentStart = 0.0
        var hasStartedSegment = false
        var duration = 0.0
        for element in monologue["elements"]?.arrayValue ?? [] {
            currentText += element["value"]?.stringValue ?? ""
            guard element["type"]?.stringValue == "text" else { continue }
            if let end = element["end_ts"]?.doubleValue {
                duration = max(duration, end)
            }
            if !hasStartedSegment, let start = element["ts"]?.doubleValue {
                segmentStart = start
                hasStartedSegment = true
            }
            if let end = element["end_ts"]?.doubleValue, hasStartedSegment {
                let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    segments.append(TranscriptionSegment(text: trimmed, startSecond: segmentStart, endSecond: end))
                }
                currentText = ""
                hasStartedSegment = false
            }
        }
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasStartedSegment, !trimmed.isEmpty {
            let end = duration > segmentStart ? duration : segmentStart + 1
            segments.append(TranscriptionSegment(text: trimmed, startSecond: segmentStart, endSecond: end))
        }
    }
    return segments
}

func gladiaTranscriptionSegments(from raw: JSONValue) -> [TranscriptionSegment] {
    transcriptionSegments(from: raw["result"]?["transcription"]?["utterances"])
}
