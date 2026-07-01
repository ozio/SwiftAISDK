import Foundation

func prepareToolChoice(_ toolChoice: JSONValue?) -> JSONValue {
    guard let toolChoice else {
        return ["type": "auto"]
    }
    if let string = toolChoice.stringValue {
        return ["type": .string(string)]
    }
    var output: [String: JSONValue] = ["type": "tool"]
    if let toolName = toolChoice["toolName"] ?? toolChoice["name"] {
        output["toolName"] = toolName
    }
    return .object(output)
}
