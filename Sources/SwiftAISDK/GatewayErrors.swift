import Foundation

public enum GatewayErrorType: String, Equatable, Hashable, Sendable {
    case authenticationError = "authentication_error"
    case invalidRequestError = "invalid_request_error"
    case rateLimitExceeded = "rate_limit_exceeded"
    case modelNotFound = "model_not_found"
    case failedDependency = "failed_dependency"
    case internalServerError = "internal_server_error"
    case responseError = "response_error"
    case timeoutError = "timeout_error"
}

public struct GatewayError: Error, Equatable, Sendable, CustomStringConvertible {
    public var type: GatewayErrorType
    public var message: String
    public var statusCode: Int
    public var generationID: String?
    public var modelID: String?
    public var response: JSONValue?
    public var headers: [String: String]
    public var isRetryable: Bool

    public init(
        type: GatewayErrorType,
        message: String,
        statusCode: Int = 500,
        generationID: String? = nil,
        modelID: String? = nil,
        response: JSONValue? = nil,
        headers: [String: String] = [:],
        isRetryable: Bool? = nil
    ) {
        self.type = type
        self.message = message
        self.statusCode = statusCode
        self.generationID = generationID
        self.modelID = modelID
        self.response = response
        self.headers = headers
        self.isRetryable = isRetryable ?? gatewayStatusIsRetryable(statusCode)
    }

    public var name: String {
        switch type {
        case .authenticationError:
            return "GatewayAuthenticationError"
        case .invalidRequestError:
            return "GatewayInvalidRequestError"
        case .rateLimitExceeded:
            return "GatewayRateLimitError"
        case .modelNotFound:
            return "GatewayModelNotFoundError"
        case .failedDependency:
            return "GatewayFailedDependencyError"
        case .internalServerError:
            return "GatewayInternalServerError"
        case .responseError:
            return "GatewayResponseError"
        case .timeoutError:
            return "GatewayTimeoutError"
        }
    }

    public var description: String {
        if let generationID {
            return "\(message) [\(generationID)]"
        }
        return message
    }
}

func gatewayErrorFromHTTPStatus(statusCode: Int, body: String, headers: [String: String]) -> GatewayError {
    if let raw = try? secureJSONParse(body) {
        if let error = raw["error"],
           let message = error["message"]?.stringValue {
            return GatewayError(
                type: gatewayErrorType(error["type"]?.stringValue),
                message: message,
                statusCode: statusCode,
                generationID: raw["generationId"]?.stringValue,
                modelID: error["param"]?["modelId"]?.stringValue,
                response: raw,
                headers: headers
            )
        }
        if raw["type"]?.stringValue == "error", let message = raw["message"]?.stringValue {
            return GatewayError(
                type: gatewayErrorType(raw["errorType"]?.stringValue),
                message: message,
                statusCode: raw["statusCode"]?.intValue ?? statusCode,
                response: raw,
                headers: headers
            )
        }
        return GatewayError(
            type: .responseError,
            message: "Invalid error response format: Gateway request failed",
            statusCode: statusCode,
            response: raw,
            headers: headers
        )
    }

    return GatewayError(
        type: .responseError,
        message: "Invalid error response format: \(body.isEmpty ? "Gateway request failed" : body)",
        statusCode: statusCode,
        response: body.isEmpty ? nil : .string(body),
        headers: headers
    )
}

private func gatewayErrorType(_ raw: String?) -> GatewayErrorType {
    switch raw {
    case GatewayErrorType.authenticationError.rawValue:
        return .authenticationError
    case GatewayErrorType.invalidRequestError.rawValue:
        return .invalidRequestError
    case GatewayErrorType.rateLimitExceeded.rawValue:
        return .rateLimitExceeded
    case GatewayErrorType.modelNotFound.rawValue:
        return .modelNotFound
    case GatewayErrorType.failedDependency.rawValue:
        return .failedDependency
    case GatewayErrorType.internalServerError.rawValue:
        return .internalServerError
    case GatewayErrorType.timeoutError.rawValue:
        return .timeoutError
    default:
        return .internalServerError
    }
}

private func gatewayStatusIsRetryable(_ statusCode: Int) -> Bool {
    statusCode == 408 || statusCode == 409 || statusCode == 429 || statusCode >= 500
}
