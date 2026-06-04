import Foundation

func partialObject(from text: String) -> JSONValue? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let value = try? decodeJSONBody(Data(trimmed.utf8)) {
        return value
    }
    let repaired = fixPartialJSON(trimmed)
    guard repaired != trimmed, !repaired.isEmpty else { return nil }
    return try? decodeJSONBody(Data(repaired.utf8))
}

func typedPartialObject<Object: Decodable>(_ type: Object.Type, from partial: JSONValue) -> Object? {
    guard let data = try? encodeJSONBody(partial) else { return nil }
    return try? JSONDecoder().decode(Object.self, from: data)
}

enum PartialJSONState {
    case root
    case finish
    case insideString
    case insideStringEscape
    case insideLiteral
    case insideNumber
    case insideObjectStart
    case insideObjectKey
    case insideObjectAfterKey
    case insideObjectBeforeValue
    case insideObjectAfterValue
    case insideObjectAfterComma
    case insideArrayStart
    case insideArrayAfterValue
    case insideArrayAfterComma
}

func fixPartialJSON(_ input: String) -> String {
    let characters = Array(input)
    var stack: [PartialJSONState] = [.root]
    var lastValidIndex: Int?
    var literalStart: Int?

    func replaceTop(with states: PartialJSONState...) {
        _ = stack.popLast()
        stack.append(contentsOf: states)
    }

    func processValueStart(_ character: Character, index: Int, swapState: PartialJSONState) {
        switch character {
        case "\"":
            lastValidIndex = index
            replaceTop(with: swapState, .insideString)
        case "f", "t", "n":
            lastValidIndex = index
            literalStart = index
            replaceTop(with: swapState, .insideLiteral)
        case "-":
            replaceTop(with: swapState, .insideNumber)
        case "0"..."9":
            lastValidIndex = index
            replaceTop(with: swapState, .insideNumber)
        case "{":
            lastValidIndex = index
            replaceTop(with: swapState, .insideObjectStart)
        case "[":
            lastValidIndex = index
            replaceTop(with: swapState, .insideArrayStart)
        default:
            break
        }
    }

    func processAfterObjectValue(_ character: Character, index: Int) {
        switch character {
        case ",":
            _ = stack.popLast()
            stack.append(.insideObjectAfterComma)
        case "}":
            lastValidIndex = index
            _ = stack.popLast()
        default:
            break
        }
    }

    func processAfterArrayValue(_ character: Character, index: Int) {
        switch character {
        case ",":
            _ = stack.popLast()
            stack.append(.insideArrayAfterComma)
        case "]":
            lastValidIndex = index
            _ = stack.popLast()
        default:
            break
        }
    }

    for (index, character) in characters.enumerated() {
        guard let currentState = stack.last else { break }
        switch currentState {
        case .root:
            processValueStart(character, index: index, swapState: .finish)

        case .insideObjectStart:
            switch character {
            case "\"":
                _ = stack.popLast()
                stack.append(.insideObjectKey)
            case "}":
                lastValidIndex = index
                _ = stack.popLast()
            default:
                break
            }

        case .insideObjectAfterComma:
            if character == "\"" {
                _ = stack.popLast()
                stack.append(.insideObjectKey)
            }

        case .insideObjectKey:
            if character == "\"" {
                _ = stack.popLast()
                stack.append(.insideObjectAfterKey)
            }

        case .insideObjectAfterKey:
            if character == ":" {
                _ = stack.popLast()
                stack.append(.insideObjectBeforeValue)
            }

        case .insideObjectBeforeValue:
            processValueStart(character, index: index, swapState: .insideObjectAfterValue)

        case .insideObjectAfterValue:
            processAfterObjectValue(character, index: index)

        case .insideString:
            switch character {
            case "\"":
                _ = stack.popLast()
                lastValidIndex = index
            case "\\":
                stack.append(.insideStringEscape)
            default:
                lastValidIndex = index
            }

        case .insideArrayStart:
            if character == "]" {
                lastValidIndex = index
                _ = stack.popLast()
            } else {
                lastValidIndex = index
                processValueStart(character, index: index, swapState: .insideArrayAfterValue)
            }

        case .insideArrayAfterValue:
            switch character {
            case ",":
                _ = stack.popLast()
                stack.append(.insideArrayAfterComma)
            case "]":
                lastValidIndex = index
                _ = stack.popLast()
            default:
                lastValidIndex = index
            }

        case .insideArrayAfterComma:
            processValueStart(character, index: index, swapState: .insideArrayAfterValue)

        case .insideStringEscape:
            _ = stack.popLast()
            lastValidIndex = index

        case .insideNumber:
            switch character {
            case "0"..."9":
                lastValidIndex = index
            case "e", "E", "-", ".":
                break
            case ",":
                _ = stack.popLast()
                if stack.last == .insideArrayAfterValue {
                    processAfterArrayValue(character, index: index)
                }
                if stack.last == .insideObjectAfterValue {
                    processAfterObjectValue(character, index: index)
                }
            case "}":
                _ = stack.popLast()
                if stack.last == .insideObjectAfterValue {
                    processAfterObjectValue(character, index: index)
                }
            case "]":
                _ = stack.popLast()
                if stack.last == .insideArrayAfterValue {
                    processAfterArrayValue(character, index: index)
                }
            default:
                _ = stack.popLast()
            }

        case .insideLiteral:
            let start = literalStart ?? index
            let partialLiteral = String(characters[start...index])
            if !"false".hasPrefix(partialLiteral),
               !"true".hasPrefix(partialLiteral),
               !"null".hasPrefix(partialLiteral) {
                _ = stack.popLast()
                if stack.last == .insideObjectAfterValue {
                    processAfterObjectValue(character, index: index)
                } else if stack.last == .insideArrayAfterValue {
                    processAfterArrayValue(character, index: index)
                }
            } else {
                lastValidIndex = index
            }

        case .finish:
            break
        }
    }

    guard let lastValidIndex else { return "" }
    var result = String(characters[0...lastValidIndex])

    for state in stack.reversed() {
        switch state {
        case .insideString:
            result += "\""
        case .insideObjectKey,
             .insideObjectAfterKey,
             .insideObjectAfterComma,
             .insideObjectStart,
             .insideObjectBeforeValue,
             .insideObjectAfterValue:
            result += "}"
        case .insideArrayStart,
             .insideArrayAfterComma,
             .insideArrayAfterValue:
            result += "]"
        case .insideLiteral:
            let start = literalStart ?? characters.count
            let partialLiteral = start < characters.count ? String(characters[start..<characters.count]) : ""
            if "true".hasPrefix(partialLiteral) {
                result += String("true".dropFirst(partialLiteral.count))
            } else if "false".hasPrefix(partialLiteral) {
                result += String("false".dropFirst(partialLiteral.count))
            } else if "null".hasPrefix(partialLiteral) {
                result += String("null".dropFirst(partialLiteral.count))
            }
        case .root, .finish, .insideStringEscape, .insideNumber:
            break
        }
    }

    return result
}
