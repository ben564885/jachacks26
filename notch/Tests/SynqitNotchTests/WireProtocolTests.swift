import XCTest
@testable import SynqitNotch

/// These decode the exact payloads printed in the spec (§6), so the seam is pinned by test
/// rather than by comment.
final class WireProtocolTests: XCTestCase {
    private let escalationJSON = """
    {
      "type": "escalation",
      "conflict_id": "c_a1b2c3",
      "dev_id": "dev_ben",
      "title": "Conflict in login()",
      "summary": "Your change to login()'s return type collides with Ana's guard clause, merged 18s ago, which calls login() and expects the old shape.",
      "file": "auth/login.py",
      "colliding_edge": "auth/login.py:login() <- auth/session.py:validate()",
      "your_change": {
        "intent": "Return a User object instead of a bool from login()",
        "diff_summary": "login() now returns User | None"
      },
      "their_change": {
        "dev_id": "dev_ana",
        "intent": "Add a guard clause that early-returns False on missing credentials",
        "diff_summary": "added `if not creds: return False` at top of login()"
      },
      "options": [
        { "id": "green", "label": "Keep mine",   "detail": "Return type change wins; reconcile the guard clause around it." },
        { "id": "red",   "label": "Keep theirs", "detail": "Guard clause wins; drop the return-type change." },
        { "id": "other", "label": "Instruct",    "input": true }
      ],
      "expires_at": "2026-07-26T20:14:00Z"
    }
    """

    func testDecodesSpecEscalation() throws {
        let event = try SynqitJSON.decoder.decode(InboundEvent.self, from: Data(escalationJSON.utf8))
        guard case let .escalation(escalation) = event else {
            return XCTFail("expected an escalation, got \(event)")
        }

        XCTAssertEqual(escalation.conflictId, "c_a1b2c3")
        XCTAssertEqual(escalation.devId, "dev_ben")
        XCTAssertEqual(escalation.file, "auth/login.py")
        XCTAssertEqual(escalation.collidingEdge, "auth/login.py:login() <- auth/session.py:validate()")
        XCTAssertEqual(escalation.theirChange?.devId, "dev_ana")
        XCTAssertEqual(escalation.resolutionOptions.count, 3)
        XCTAssertTrue(escalation.resolutionOptions[2].requiresInput)
        XCTAssertFalse(escalation.resolutionOptions[0].requiresInput)
        // 2026-07-26T20:14:00Z
        XCTAssertEqual(escalation.expiresAt?.timeIntervalSince1970, 1_785_096_840)
        XCTAssertTrue(escalation.hasDetail)
    }

    func testOptionAccentsFallBackForUnknownIds() {
        XCTAssertEqual(ResolutionOption(id: "green", label: "a").accent, .affirmative)
        XCTAssertEqual(ResolutionOption(id: "red", label: "b").accent, .negative)
        XCTAssertEqual(ResolutionOption(id: "other", label: "c", input: true).accent, .instruct)
        XCTAssertEqual(ResolutionOption(id: "rebase_both", label: "d").accent, .neutral)
    }

    func testMissingOptionsFallBackToSpecDefaults() throws {
        let json = """
        {"type":"escalation","conflict_id":"c1","dev_id":"dev_ben","title":"t","summary":"s"}
        """
        let event = try SynqitJSON.decoder.decode(InboundEvent.self, from: Data(json.utf8))
        guard case let .escalation(escalation) = event else { return XCTFail("wrong case") }
        XCTAssertEqual(escalation.resolutionOptions.map(\.id), ["green", "red", "other"])
        XCTAssertNil(escalation.expiresAt)
        XCTAssertFalse(escalation.hasExpired())
        XCTAssertFalse(escalation.hasDetail)
    }

    func testDecodesWithdrawWithUnknownReason() throws {
        let json = #"{"type":"withdraw","conflict_id":"c_a1b2c3","reason":"reason_from_the_future"}"#
        let event = try SynqitJSON.decoder.decode(InboundEvent.self, from: Data(json.utf8))
        guard case let .withdraw(withdrawal) = event else { return XCTFail("wrong case") }
        XCTAssertEqual(withdrawal.conflictId, "c_a1b2c3")
        XCTAssertEqual(withdrawal.reason, .other("reason_from_the_future"))
    }

    func testUnknownEventTypeIsInert() throws {
        let json = #"{"type":"launch_missiles","target":"everything"}"#
        let event = try SynqitJSON.decoder.decode(InboundEvent.self, from: Data(json.utf8))
        guard case let .unrecognised(type) = event else { return XCTFail("wrong case") }
        XCTAssertEqual(type, "launch_missiles")
    }

    func testResolutionEncodesExplicitNullCustomText() throws {
        let resolution = Resolution(conflictId: "c_a1b2c3", devId: "dev_ben", choice: "green", customText: nil)
        let data = try SynqitJSON.encoder.encode(OutboundMessage.resolution(resolution))
        let text = String(decoding: data, as: UTF8.self)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["type"] as? String, "resolution")
        XCTAssertEqual(object["conflict_id"] as? String, "c_a1b2c3")
        XCTAssertEqual(object["dev_id"] as? String, "dev_ben")
        XCTAssertEqual(object["choice"] as? String, "green")
        XCTAssertTrue(object["custom_text"] is NSNull, "custom_text must be an explicit null, got: \(text)")
    }

    func testFetchPendingUsesSnakeCase() throws {
        let data = try SynqitJSON.encoder.encode(OutboundMessage.fetchPending(devId: "dev_ben"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "fetch_pending")
        XCTAssertEqual(object["dev_id"] as? String, "dev_ben")
    }

    func testDecodesPendingSync() throws {
        let json = """
        {"type":"pending","escalations":[
          {"conflict_id":"c1","dev_id":"dev_ben","title":"t1","summary":"s1"},
          {"conflict_id":"c2","dev_id":"dev_ben","title":"t2","summary":"s2"}
        ]}
        """
        let event = try SynqitJSON.decoder.decode(InboundEvent.self, from: Data(json.utf8))
        guard case let .pending(escalations) = event else { return XCTFail("wrong case") }
        XCTAssertEqual(escalations.map(\.conflictId), ["c1", "c2"])
    }
}
