import Foundation

/// The server's error envelope, decoded.
///
/// Every failure at every status code arrives in one shape, so this is the
/// only error type the UI renders. `message` is written server-side for a
/// person to read, which is why it is shown as-is rather than mapped to a
/// second set of client strings that would have to be kept in sync.
struct APIError: Error, Equatable {
    let code: String
    let message: String
    let status: Int
    let requestID: String?
    let fieldErrors: [String: String]
    /// Extra machine-readable detail, e.g. why the AI is unavailable.
    let reason: String?

    static func transport(_ underlying: Error) -> APIError {
        APIError(
            code: "NETWORK_UNREACHABLE",
            message: "Can't reach the server. Check your connection and try again.",
            status: 0, requestID: nil, fieldErrors: [:], reason: nil
        )
    }

    static func decoding(_ underlying: Error) -> APIError {
        APIError(
            code: "RESPONSE_MALFORMED",
            message: "The server sent something we couldn't read.",
            status: 0, requestID: nil, fieldErrors: [:], reason: nil
        )
    }

    var isAuthFailure: Bool {
        status == 401 || code == "TOKEN_INVALID" || code == "TOKEN_EXPIRED"
    }

    /// The AI gateway specifically, as opposed to the whole product. Worth its
    /// own case because the app stays fully usable without it and should say
    /// so rather than showing a generic failure.
    var isAIUnavailable: Bool { code == "AI_UNAVAILABLE" }

    var isRetryable: Bool {
        code == "NETWORK_UNREACHABLE" || status >= 500 || status == 429
    }

    func message(for field: String) -> String? { fieldErrors[field] }
}

// MARK: - Wire format

private struct ErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String
        let message: String
        let requestID: String?
        let details: Details?

        enum CodingKeys: String, CodingKey {
            case code, message, details
            case requestID = "request_id"
        }
    }

    /// `details` carries two shapes: FastAPI's body validation produces
    /// `fields: [{field, reason}]`, while the service layer produces a single
    /// `field`. Both flatten to one dictionary so forms read only one.
    struct Details: Decodable {
        struct FieldError: Decodable {
            let field: String
            let reason: String
        }
        let fields: [FieldError]?
        let field: String?
        let reason: String?
    }

    let error: Body
}

extension APIError {
    static func decode(from data: Data, status: Int) -> APIError {
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            var fields: [String: String] = [:]
            for f in envelope.error.details?.fields ?? [] where fields[f.field] == nil {
                fields[f.field] = f.reason
            }
            // A service-layer error names one field but puts the human message
            // at the top level; the two halves are joined here.
            if let single = envelope.error.details?.field, fields[single] == nil {
                fields[single] = envelope.error.message
            }
            return APIError(
                code: envelope.error.code,
                message: envelope.error.message,
                status: status,
                requestID: envelope.error.requestID,
                fieldErrors: fields,
                reason: envelope.error.details?.reason
            )
        }
        // Not our envelope: something in front of the API answered — a proxy,
        // a captive portal. Saying so beats printing whatever HTML it sent.
        return APIError(
            code: "UNEXPECTED_RESPONSE",
            message: "The server returned \(status).",
            status: status, requestID: nil, fieldErrors: [:], reason: nil
        )
    }
}
