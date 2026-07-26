import XCTest
@testable import SynqitNotch

@MainActor
final class EscalationStoreTests: XCTestCase {
    private func makeStore(devId: String = "dev_ben") -> (EscalationStore, Recorder) {
        let store = EscalationStore(devId: devId)
        let recorder = Recorder()
        store.sendResolution = { resolution in
            recorder.record(resolution)
        }
        return (store, recorder)
    }

    private func escalation(
        _ id: String,
        devId: String = "dev_ben",
        expiresAt: Date? = nil
    ) -> Escalation {
        Escalation(
            conflictId: id,
            devId: devId,
            title: "Conflict in login()",
            summary: "summary",
            file: "auth/login.py",
            collidingEdge: "a <- b",
            yourChange: ChangeSide(intent: "mine"),
            theirChange: ChangeSide(devId: "dev_ana", intent: "theirs"),
            options: ResolutionOption.defaults,
            expiresAt: expiresAt
        )
    }

    // MARK: - Routing

    func testDropsEscalationAddressedToAnotherDeveloper() {
        let (store, _) = makeStore()
        defer { store.shutdown() }

        store.receive(.escalation(escalation("c1", devId: "dev_ana")))

        XCTAssertTrue(store.queue.isEmpty)
        XCTAssertEqual(store.phase, .idle)
    }

    func testPresentsFirstEscalation() {
        let (store, _) = makeStore()
        defer { store.shutdown() }

        store.receive(.escalation(escalation("c1")))

        XCTAssertEqual(store.current?.conflictId, "c1")
        XCTAssertEqual(store.phase, .presenting)
        XCTAssertEqual(store.pendingCount, 1)
        XCTAssertEqual(store.queuedBehindCount, 0)
    }

    // MARK: - Queueing (§10)

    func testSimultaneousConflictsQueueRatherThanReplace() {
        let (store, _) = makeStore()
        defer { store.shutdown() }

        store.receive(.escalation(escalation("c1")))
        store.receive(.escalation(escalation("c2")))
        store.receive(.escalation(escalation("c3")))

        XCTAssertEqual(store.current?.conflictId, "c1")
        XCTAssertEqual(store.pendingCount, 3)
        XCTAssertEqual(store.queuedBehindCount, 2)
    }

    func testResendOfSameConflictUpdatesInPlace() {
        let (store, _) = makeStore()
        defer { store.shutdown() }

        store.receive(.escalation(escalation("c1")))
        var updated = escalation("c1")
        updated.title = "Retitled"
        store.receive(.escalation(updated))

        XCTAssertEqual(store.pendingCount, 1)
        XCTAssertEqual(store.current?.title, "Retitled")
    }

    // MARK: - Resolution

    func testChoosingSendsResolutionAndEntersSubmitting() async {
        let (store, recorder) = makeStore()
        defer { store.shutdown() }
        store.receive(.escalation(escalation("c1")))

        store.choose(ResolutionOption(id: "green", label: "Keep mine"))
        XCTAssertEqual(store.phase, .submitting(choice: "green"))

        await recorder.waitForFirst()
        XCTAssertEqual(recorder.resolutions.count, 1)
        XCTAssertEqual(recorder.resolutions.first?.choice, "green")
        XCTAssertNil(recorder.resolutions.first?.customText)
    }

    /// §10: rapid resubmission must not emit two conflicting choices.
    func testDoubleClickEmitsOneResolution() async {
        let (store, recorder) = makeStore()
        defer { store.shutdown() }
        store.receive(.escalation(escalation("c1")))

        store.choose(ResolutionOption(id: "green", label: "Keep mine"))
        store.choose(ResolutionOption(id: "red", label: "Keep theirs"))
        store.choose(ResolutionOption(id: "green", label: "Keep mine"))

        await recorder.waitForFirst()
        XCTAssertEqual(recorder.resolutions.count, 1)
        XCTAssertEqual(recorder.resolutions.first?.choice, "green")
    }

    func testInstructOptionOpensFieldBeforeSubmitting() async {
        let (store, recorder) = makeStore()
        defer { store.shutdown() }
        store.receive(.escalation(escalation("c1")))

        let instruct = ResolutionOption(id: "other", label: "Instruct", input: true)
        store.choose(instruct)

        XCTAssertTrue(store.isInstructing)
        XCTAssertEqual(store.phase, .presenting, "opening the field must not submit")
        XCTAssertTrue(recorder.resolutions.isEmpty)

        store.instructionText = "  keep both, guard first  "
        store.submitInstruction()

        await recorder.waitForFirst()
        XCTAssertEqual(recorder.resolutions.first?.choice, "other")
        XCTAssertEqual(recorder.resolutions.first?.customText, "keep both, guard first")
    }

    func testEmptyInstructionIsNotSubmittable() {
        let (store, recorder) = makeStore()
        defer { store.shutdown() }
        store.receive(.escalation(escalation("c1")))

        store.choose(ResolutionOption(id: "other", label: "Instruct", input: true))
        store.instructionText = "   "

        XCTAssertFalse(store.canSubmitInstruction)
        store.submitInstruction()
        XCTAssertTrue(recorder.resolutions.isEmpty)
        XCTAssertEqual(store.phase, .presenting)
    }

    func testAckAdvancesToConfirmed() {
        let (store, _) = makeStore()
        defer { store.shutdown() }
        store.receive(.escalation(escalation("c1")))
        store.receive(.escalation(escalation("c2")))

        store.choose(ResolutionOption(id: "green", label: "Keep mine"))
        store.receive(.acknowledgement(Acknowledgement(conflictId: "c1", status: "applied")))

        XCTAssertEqual(store.phase, .confirmed(choice: "green"))
        XCTAssertEqual(store.current?.conflictId, "c2", "queue advances after the resolved item leaves")
        XCTAssertEqual(store.pendingCount, 1)
    }

    func testFailedAckReturnsToPresentingWithError() {
        let (store, _) = makeStore()
        defer { store.shutdown() }
        store.receive(.escalation(escalation("c1")))

        store.choose(ResolutionOption(id: "green", label: "Keep mine"))
        store.receive(.acknowledgement(
            Acknowledgement(conflictId: "c1", status: "error", message: "reconciler refused")
        ))

        XCTAssertEqual(store.phase, .presenting)
        XCTAssertEqual(store.lastError, "reconciler refused")
        XCTAssertEqual(store.pendingCount, 1, "a rejected resolution keeps the conflict")
    }

    // MARK: - Withdrawal (§10)

    func testWithdrawOfOnScreenItemDismissesIt() {
        let (store, _) = makeStore()
        defer { store.shutdown() }
        store.receive(.escalation(escalation("c1")))

        store.receive(.withdraw(Withdrawal(conflictId: "c1", reason: .resolvedElsewhere)))

        XCTAssertEqual(store.phase, .dismissed(reason: .resolvedElsewhere))
        XCTAssertTrue(store.queue.isEmpty)
    }

    func testWithdrawOfQueuedItemLeavesCurrentAlone() {
        let (store, _) = makeStore()
        defer { store.shutdown() }
        store.receive(.escalation(escalation("c1")))
        store.receive(.escalation(escalation("c2")))

        store.receive(.withdraw(Withdrawal(conflictId: "c2", reason: .superseded)))

        XCTAssertEqual(store.phase, .presenting)
        XCTAssertEqual(store.current?.conflictId, "c1")
        XCTAssertEqual(store.pendingCount, 1)
    }

    func testWithdrawForUnknownConflictIsIgnored() {
        let (store, _) = makeStore()
        defer { store.shutdown() }
        store.receive(.escalation(escalation("c1")))

        store.receive(.withdraw(Withdrawal(conflictId: "nope", reason: .expired)))

        XCTAssertEqual(store.phase, .presenting)
        XCTAssertEqual(store.pendingCount, 1)
    }

    // MARK: - Pending sync (§8)

    func testPendingSyncIsAuthoritative() {
        let (store, _) = makeStore()
        defer { store.shutdown() }
        store.receive(.escalation(escalation("c1")))
        store.receive(.escalation(escalation("c2")))

        // Backend says only c2 and c3 are still live.
        store.receive(.pending([escalation("c2"), escalation("c3")]))

        XCTAssertEqual(store.queue.map(\.conflictId).sorted(), ["c2", "c3"])
    }

    func testPendingSyncKeepsOnScreenItemInPlace() {
        let (store, _) = makeStore()
        defer { store.shutdown() }
        store.receive(.escalation(escalation("c1")))

        store.receive(.pending([escalation("c9"), escalation("c1")]))

        XCTAssertEqual(store.current?.conflictId, "c1", "the item under the cursor must not shuffle")
        XCTAssertEqual(store.pendingCount, 2)
    }

    func testPendingSyncDroppingCurrentDismissesIt() {
        let (store, _) = makeStore()
        defer { store.shutdown() }
        store.receive(.escalation(escalation("c1")))

        store.receive(.pending([escalation("c2")]))

        XCTAssertEqual(store.phase, .dismissed(reason: .resolvedElsewhere))
    }

    /// An empty pending-sync while something is on screen must not blank silently — §7 wants
    /// the quiet "resolved elsewhere" note first. Idling happens after the dwell.
    func testEmptyPendingSyncNotesTheDisappearance() {
        let (store, _) = makeStore()
        defer { store.shutdown() }
        store.receive(.escalation(escalation("c1")))

        store.receive(.pending([]))

        XCTAssertTrue(store.queue.isEmpty)
        XCTAssertEqual(store.phase, .dismissed(reason: .resolvedElsewhere))
    }

    func testEmptyPendingSyncWhenIdleStaysIdle() {
        let (store, _) = makeStore()
        defer { store.shutdown() }

        store.receive(.pending([]))

        XCTAssertTrue(store.queue.isEmpty)
        XCTAssertEqual(store.phase, .idle)
    }

    func testPendingSyncIgnoresOtherDevelopersItems() {
        let (store, _) = makeStore()
        defer { store.shutdown() }

        store.receive(.pending([escalation("c1"), escalation("c2", devId: "dev_ana")]))

        XCTAssertEqual(store.queue.map(\.conflictId), ["c1"])
    }

    // MARK: - Expiry

    func testAlreadyExpiredEscalationIsNeverPresented() {
        let (store, _) = makeStore()
        defer { store.shutdown() }

        store.receive(.escalation(escalation("c1", expiresAt: Date().addingTimeInterval(-5))))

        XCTAssertTrue(store.queue.isEmpty)
        XCTAssertEqual(store.phase, .idle)
    }

    // MARK: - Minimize / restore

    func testMinimizeKeepsItemQueued() {
        let (store, _) = makeStore()
        defer { store.shutdown() }
        store.receive(.escalation(escalation("c1")))

        store.minimize()
        XCTAssertTrue(store.isMinimized)
        XCTAssertEqual(store.pendingCount, 1)

        store.restore()
        XCTAssertFalse(store.isMinimized)
        XCTAssertEqual(store.phase, .presenting)
    }
}

/// Captures resolutions the store hands to the connection layer. Everything here runs on the
/// main actor — same as the store — so no locking is involved.
@MainActor
private final class Recorder {
    private(set) var resolutions: [Resolution] = []

    func record(_ resolution: Resolution) {
        resolutions.append(resolution)
    }

    /// The store submits from a `Task`, so tests yield until the send lands rather than
    /// sleeping for a fixed interval.
    func waitForFirst(timeout: Duration = .seconds(2)) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while resolutions.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
}
