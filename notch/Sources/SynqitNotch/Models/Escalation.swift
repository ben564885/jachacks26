import Foundation

/// One conflict awaiting this developer's decision.
///
/// Mirrors the inbound `escalation` payload in the spec (§6). Everything except
/// `conflict_id`, `dev_id`, `title` and `summary` is optional: the notch renders whatever the
/// backend sends and degrades gracefully rather than dropping an escalation because a
/// detail field was absent. Inbound events are data, never commands (§12).
struct Escalation: Codable, Identifiable, Equatable, Sendable {
    var conflictId: String
    var devId: String
    var title: String
    var summary: String
    var file: String?
    var collidingEdge: String?
    var yourChange: ChangeSide?
    var theirChange: ChangeSide?
    var options: [ResolutionOption]?
    var expiresAt: Date?

    var id: String { conflictId }

    /// The options to render. Falls back to the spec's default triple if the backend omits them,
    /// so a decision surface is always presented.
    var resolutionOptions: [ResolutionOption] {
        if let options, !options.isEmpty { return options }
        return ResolutionOption.defaults
    }

    /// True once `expires_at` has passed. Escalations without an expiry never go stale.
    func hasExpired(asOf now: Date = .now) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }

    /// Whether there is enough material to render the expanded detail section.
    var hasDetail: Bool {
        file != nil || collidingEdge != nil
            || yourChange?.isPresentable == true || theirChange?.isPresentable == true
    }
}

/// One side of a collision — the pusher's change or the already-merged change it hit.
///
/// Both sides carry intent, not just a diff. §9: without the *other* side's intent the notch
/// is a coin flip rather than a decision surface.
struct ChangeSide: Codable, Equatable, Sendable {
    var devId: String? = nil
    var intent: String? = nil
    var diffSummary: String? = nil

    var isPresentable: Bool {
        intent?.isEmpty == false || diffSummary?.isEmpty == false
    }
}

/// A resolution the developer can pick. `input == true` means the choice carries free text.
struct ResolutionOption: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var label: String
    var detail: String? = nil
    var input: Bool? = nil

    /// Whether picking this option should open the inline instruction field instead of
    /// submitting immediately.
    var requiresInput: Bool { input == true }

    static let defaults: [ResolutionOption] = [
        .init(id: "green", label: "Keep mine", detail: nil, input: nil),
        .init(id: "red", label: "Keep theirs", detail: nil, input: nil),
        .init(id: "other", label: "Instruct", detail: nil, input: true)
    ]
}

// MARK: - Presentation intent

/// How an option should be styled. Derived from the option, never sent by the backend, so a
/// backend that invents new option ids still renders sensibly.
enum OptionAccent: Sendable {
    case affirmative
    case negative
    case instruct
    case neutral
}

extension ResolutionOption {
    /// Recognised ids get their semantic colour; an option that takes input is always the
    /// instruct treatment; anything else falls back to neutral rather than guessing.
    var accent: OptionAccent {
        if requiresInput { return .instruct }
        switch id.lowercased() {
        case "green", "mine", "keep_mine", "accept": return .affirmative
        case "red", "theirs", "keep_theirs", "reject": return .negative
        case "other", "instruct", "custom": return .instruct
        default: return .neutral
        }
    }
}
