import Foundation

// MARK: - Inbound

/// Everything the backend can send us. Unknown `type` values decode to `.unrecognised`
/// and are logged, never acted on (§12: inbound events are data, not commands).
enum InboundEvent: Sendable {
    case escalation(Escalation)
    case withdraw(Withdrawal)
    case pending([Escalation])
    case acknowledgement(Acknowledgement)
    case unrecognised(type: String)
}

/// Backend told us to drop a conflict we may be showing (§6, §10).
struct Withdrawal: Codable, Equatable, Sendable {
    var conflictId: String
    var reason: WithdrawReason?
}

/// Spec lists `resolved_elsewhere`, `expired`, `superseded`. Anything else decodes to
/// `.other` so a new backend reason can't break an old client.
enum WithdrawReason: RawRepresentable, Codable, Equatable, Sendable {
    case resolvedElsewhere
    case expired
    case superseded
    case other(String)

    init(rawValue: String) {
        switch rawValue {
        case "resolved_elsewhere": self = .resolvedElsewhere
        case "expired": self = .expired
        case "superseded": self = .superseded
        default: self = .other(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .resolvedElsewhere: "resolved_elsewhere"
        case .expired: "expired"
        case .superseded: "superseded"
        case let .other(value): value
        }
    }

    /// Shown briefly in place of an escalation that vanished from under the developer.
    var displayText: String {
        switch self {
        case .resolvedElsewhere: "Resolved elsewhere"
        case .expired: "Expired"
        case .superseded: "Superseded"
        case .other: "Withdrawn"
        }
    }
}

/// Backend confirming it applied a resolution. Not in §6 — the notch needs it to leave the
/// "submitting" state defined in §7, so it is an additive extension: a backend that never
/// sends one just means the client falls back to its confirmation timeout.
struct Acknowledgement: Codable, Equatable, Sendable {
    var conflictId: String
    var status: String?
    var message: String?

    /// Anything that isn't an explicit failure counts as applied.
    var isFailure: Bool {
        guard let status = status?.lowercased() else { return false }
        return status == "error" || status == "rejected" || status == "failed"
    }
}

extension InboundEvent: Decodable {
    private enum TypeKey: String, CodingKey { case type }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "escalation":
            self = .escalation(try Escalation(from: decoder))
        case "withdraw":
            self = .withdraw(try Withdrawal(from: decoder))
        case "pending":
            self = .pending(try PendingEnvelope(from: decoder).escalations)
        case "ack":
            self = .acknowledgement(try Acknowledgement(from: decoder))
        default:
            self = .unrecognised(type: type)
        }
    }
}

/// Response to `fetch_pending`. §6 describes it as "an array of any active escalation
/// objects for this developer"; it is wrapped in a typed envelope so it can share the
/// single `type`-tagged message channel with everything else.
private struct PendingEnvelope: Decodable {
    var escalations: [Escalation]
}

// MARK: - Outbound

/// Everything the notch sends. Only `resolution` is specified in §6; `hello` and
/// `fetch_pending` implement the connect/reconnect handshake described in §8.
enum OutboundMessage: Encodable, Sendable {
    case hello(devId: String, client: String)
    case fetchPending(devId: String)
    case resolution(Resolution)

    private enum Keys: String, CodingKey {
        case type, devId, client
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .hello(devId, client):
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode("hello", forKey: .type)
            try container.encode(devId, forKey: .devId)
            try container.encode(client, forKey: .client)
        case let .fetchPending(devId):
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode("fetch_pending", forKey: .type)
            try container.encode(devId, forKey: .devId)
        case let .resolution(resolution):
            try resolution.encode(to: encoder)
        }
    }
}

/// The developer's decision, relayed verbatim to the backend (§6). The notch never resolves
/// anything locally — this message is the entire extent of its authority.
struct Resolution: Codable, Equatable, Sendable {
    var type: String = "resolution"
    var conflictId: String
    var devId: String
    var choice: String
    /// Populated only for options that take input; `null` otherwise, per the spec's example.
    var customText: String?

    private enum Keys: String, CodingKey {
        case type, conflictId, devId, choice, customText
    }

    /// Hand-written so `custom_text` is emitted as an explicit `null` rather than omitted,
    /// which is what §6's example shows on the wire.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(type, forKey: .type)
        try container.encode(conflictId, forKey: .conflictId)
        try container.encode(devId, forKey: .devId)
        try container.encode(choice, forKey: .choice)
        try container.encode(customText, forKey: .customText)
    }
}

// MARK: - Coding

enum SynqitJSON {
    /// New instances per call: `JSONDecoder`/`JSONEncoder` are not `Sendable`, and the message
    /// volume here (a handful of events per conflict) makes caching them pointless.
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // `expires_at` is ISO-8601; accept it with or without fractional seconds so the
        // backend's formatter choice can't break parsing.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = try? Date(raw, strategy: .iso8601) { return date }
            if let date = try? Date(raw, strategy: .iso8601.time(includingFractionalSeconds: true)) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 timestamp, got \(raw)"
            )
        }
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
