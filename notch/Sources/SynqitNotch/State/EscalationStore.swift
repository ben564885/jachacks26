import Foundation
import OSLog

/// The state layer (§5.2). Holds the escalation currently on screen plus any queued behind it,
/// ingests inbound events, and exposes display state to the UI.
///
/// It never mutates conflict state itself — it reflects the backend and relays the developer's
/// choice. Every transition here is either "the backend told us" or "the human clicked".
@MainActor
final class EscalationStore: ObservableObject {
    /// The per-item lifecycle from §7.
    enum Phase: Equatable {
        case idle
        case presenting
        case submitting(choice: String)
        case confirmed(choice: String)
        /// The item vanished from under the developer; shown briefly so the disappearance
        /// isn't silent.
        case dismissed(reason: WithdrawReason)
    }

    @Published private(set) var queue: [Escalation] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastError: String?
    /// Label of the option the developer just picked, so the confirmation micro-state can say
    /// what was chosen after the escalation itself has left the queue.
    @Published private(set) var resolvedLabel: String?

    /// Hover/click reveal of the detail section (§7 "Expanded / hover").
    @Published var isDetailExpanded = false
    /// Inline instruction field is open.
    @Published var isInstructing = false
    @Published var instructionText = ""
    /// Developer collapsed the escalation to the compact notch; it stays queued and can be
    /// reopened from the menu bar.
    @Published private(set) var isMinimized = false

    /// Injected by the app so the store has no direct dependency on the socket.
    var sendResolution: (@MainActor (Resolution) async throws -> Void)?

    private let devId: String
    private let log = Logger(subsystem: "com.synqit.notch", category: "store")

    private var confirmationTimeout: Task<Void, Never>?
    private var dwellTask: Task<Void, Never>?
    private var expiryTicker: Task<Void, Never>?

    /// How long the confirmed / dismissed micro-states stay on screen before collapsing.
    private let confirmedDwell: Duration = .milliseconds(1_100)
    private let dismissedDwell: Duration = .milliseconds(1_800)
    /// If the backend never sends an `ack`, don't strand the developer in "submitting".
    private let ackTimeout: Duration = .seconds(4)

    init(devId: String) {
        self.devId = devId
        startExpiryTicker()
    }

    /// The store is app-lifetime; this exists so tests and previews can stop the tickers.
    func shutdown() {
        confirmationTimeout?.cancel()
        dwellTask?.cancel()
        expiryTicker?.cancel()
    }

    // MARK: - Derived state

    var current: Escalation? { queue.first }
    var pendingCount: Int { queue.count }
    /// Number of items waiting behind the one on screen.
    var queuedBehindCount: Int { max(0, queue.count - 1) }
    var hasWork: Bool { !queue.isEmpty || phase != .idle }

    // MARK: - Ingest

    func receive(_ event: InboundEvent) {
        switch event {
        case let .escalation(escalation):
            ingest(escalation)
        case let .pending(escalations):
            reconcile(with: escalations)
        case let .withdraw(withdrawal):
            withdraw(conflictId: withdrawal.conflictId, reason: withdrawal.reason ?? .other("withdrawn"))
        case let .acknowledgement(ack):
            acknowledge(ack)
        case .unrecognised:
            break
        }
    }

    private func ingest(_ escalation: Escalation) {
        // §12: defence in depth. The backend enforces dev_id scoping; if something addressed
        // to another developer ever reaches this socket, it does not get rendered.
        guard escalation.devId == devId else {
            log.error("dropped escalation \(escalation.conflictId, privacy: .public) addressed to \(escalation.devId, privacy: .public)")
            return
        }
        guard !escalation.hasExpired() else { return }

        if let index = queue.firstIndex(where: { $0.conflictId == escalation.conflictId }) {
            // A re-send updates in place rather than queueing a duplicate.
            queue[index] = escalation
        } else {
            queue.append(escalation)
        }

        if phase == .idle {
            present()
        }
    }

    /// §8: the backend's pending-sync is authoritative on every reconnect. Anything the
    /// backend no longer considers active is dropped, and the on-screen item keeps its place
    /// if it survived.
    private func reconcile(with escalations: [Escalation]) {
        let mine = escalations.filter { $0.devId == devId && !$0.hasExpired() }
        let currentId = current?.conflictId

        var reordered = mine
        if let currentId, let index = reordered.firstIndex(where: { $0.conflictId == currentId }), index != 0 {
            reordered.swapAt(0, index)
        }
        queue = reordered

        if let currentId, !queue.contains(where: { $0.conflictId == currentId }) {
            // The item on screen is gone from the server's view — treat exactly like a withdraw.
            finishCurrent(with: .dismissed(reason: .resolvedElsewhere))
        } else if queue.isEmpty {
            clear()
        } else if phase == .idle {
            present()
        }
    }

    private func withdraw(conflictId: String, reason: WithdrawReason) {
        guard queue.contains(where: { $0.conflictId == conflictId }) else { return }

        if current?.conflictId == conflictId {
            queue.removeFirst()
            // §10: react promptly so the developer can't double-resolve.
            finishCurrent(with: .dismissed(reason: reason))
        } else {
            queue.removeAll { $0.conflictId == conflictId }
        }
    }

    private func acknowledge(_ ack: Acknowledgement) {
        guard case let .submitting(choice) = phase, current?.conflictId == ack.conflictId else { return }
        confirmationTimeout?.cancel()

        if ack.isFailure {
            lastError = ack.message ?? "The backend rejected that resolution."
            phase = .presenting
            return
        }

        queue.removeFirst()
        finishCurrent(with: .confirmed(choice: choice))
    }

    // MARK: - User actions

    /// Handles a tapped option. Options that take input open the field instead of submitting.
    func choose(_ option: ResolutionOption) {
        if option.requiresInput, !isInstructing {
            isInstructing = true
            isDetailExpanded = true
            return
        }
        submit(
            choice: option.id,
            label: option.label,
            customText: option.requiresInput ? trimmedInstruction : nil
        )
    }

    /// Submits the typed instruction for whichever option takes input.
    func submitInstruction() {
        guard let option = current?.resolutionOptions.first(where: { $0.requiresInput }) else { return }
        guard !trimmedInstruction.isEmpty else { return }
        submit(choice: option.id, label: option.label, customText: trimmedInstruction)
    }

    var trimmedInstruction: String {
        instructionText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmitInstruction: Bool {
        !trimmedInstruction.isEmpty && phase == .presenting
    }

    private func submit(choice: String, label: String, customText: String?) {
        // §10: rapid resubmission. Only a presenting item can be resolved, so a double-click
        // cannot emit two conflicting choices.
        guard phase == .presenting, let escalation = current else { return }

        lastError = nil
        resolvedLabel = label
        phase = .submitting(choice: choice)

        let resolution = Resolution(
            conflictId: escalation.conflictId,
            devId: devId,
            choice: choice,
            customText: customText
        )

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sendResolution?(resolution)
                self.startConfirmationTimeout(for: escalation.conflictId, choice: choice)
            } catch {
                self.lastError = "Couldn't reach the backend. Try again."
                self.phase = .presenting
            }
        }
    }

    /// The backend is the source of truth, but a missing `ack` must not strand the UI. After
    /// the timeout we collapse optimistically — the next pending-sync will restore the item
    /// if it was never actually applied.
    private func startConfirmationTimeout(for conflictId: String, choice: String) {
        confirmationTimeout?.cancel()
        confirmationTimeout = Task { [weak self, ackTimeout = self.ackTimeout] in
            try? await Task.sleep(for: ackTimeout)
            guard !Task.isCancelled, let self else { return }
            guard case .submitting = self.phase, self.current?.conflictId == conflictId else { return }
            self.queue.removeFirst()
            self.finishCurrent(with: .confirmed(choice: choice))
        }
    }

    /// Collapse the escalation to the compact notch without resolving it.
    func minimize() {
        guard !queue.isEmpty else { return }
        isMinimized = true
        isInstructing = false
        isDetailExpanded = false
    }

    func restore() {
        guard !queue.isEmpty else { return }
        isMinimized = false
        if phase == .idle { phase = .presenting }
    }

    func dismissError() {
        lastError = nil
    }

    // MARK: - Transitions

    private func present() {
        guard !queue.isEmpty else { return clear() }
        dwellTask?.cancel()
        isDetailExpanded = false
        isInstructing = false
        instructionText = ""
        isMinimized = false
        phase = .presenting
    }

    /// Shows a terminal micro-state, then advances to the next item (or idles).
    private func finishCurrent(with terminal: Phase) {
        confirmationTimeout?.cancel()
        isInstructing = false
        isDetailExpanded = false
        phase = terminal

        let dwell: Duration = {
            if case .confirmed = terminal { return confirmedDwell }
            return dismissedDwell
        }()

        dwellTask?.cancel()
        dwellTask = Task { [weak self] in
            try? await Task.sleep(for: dwell)
            guard !Task.isCancelled, let self else { return }
            if self.queue.isEmpty {
                self.clear()
            } else {
                self.present()
            }
        }
    }

    private func clear() {
        dwellTask?.cancel()
        confirmationTimeout?.cancel()
        phase = .idle
        isMinimized = false
        isDetailExpanded = false
        isInstructing = false
        instructionText = ""
    }

    // MARK: - Expiry

    /// §7/§10: an item whose `expires_at` passes is dismissed even if the backend never sends
    /// a withdraw for it.
    private func startExpiryTicker() {
        expiryTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.dropExpired()
            }
        }
    }

    private func dropExpired() {
        guard !queue.isEmpty else { return }
        let now = Date.now

        if let current, current.hasExpired(asOf: now) {
            // Don't yank an item out from under an in-flight submission.
            if case .submitting = phase { return }
            queue.removeFirst()
            finishCurrent(with: .dismissed(reason: .expired))
            return
        }
        queue.removeAll { $0.hasExpired(asOf: now) }
    }
}
