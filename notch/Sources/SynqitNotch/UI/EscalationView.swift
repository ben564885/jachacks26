import SwiftUI

/// The expanded notch content — the whole decision surface (§7).
///
/// It renders the backend's summary faithfully and never derives a recommendation of its own.
/// Everything it can do is call into the store, which relays the choice.
struct EscalationView: View {
    @ObservedObject var store: EscalationStore
    @ObservedObject var connection: SynqitClient

    @State private var isHovering = false
    @FocusState private var instructionFocused: Bool

    private var showsDetail: Bool {
        (isHovering || store.isDetailExpanded) && store.current?.hasDetail == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch store.phase {
            case .idle:
                EmptyView()
            case .presenting, .submitting:
                active
            case let .confirmed(choice):
                ConfirmationBanner(
                    symbol: "checkmark.circle.fill",
                    tint: Theme.affirmative,
                    headline: store.resolvedLabel.map { "Sent · \($0)" } ?? "Resolution sent",
                    detail: choice == "other"
                        ? "Your instruction is with the reconciler."
                        : "The merge is proceeding on the backend."
                )
            case let .dismissed(reason):
                ConfirmationBanner(
                    symbol: reason == .expired ? "clock.badge.xmark" : "arrow.uturn.backward.circle.fill",
                    tint: Theme.neutral,
                    headline: reason.displayText,
                    detail: reason == .expired
                        ? "This conflict timed out and no longer needs you."
                        : "Another surface handled this one."
                )
            }
        }
        .frame(width: Theme.contentWidth, alignment: .leading)
        .padding(.horizontal, Theme.horizontalPadding)
        .padding(.top, Theme.topPadding)
        .padding(.bottom, Theme.bottomPadding)
        .onHover { hovering in
            withAnimation(Theme.stateChange) { isHovering = hovering }
        }
        .animation(Theme.stateChange, value: store.phase)
        .animation(Theme.stateChange, value: showsDetail)
        .animation(Theme.stateChange, value: store.isInstructing)
        .onChange(of: store.isInstructing) { _, isInstructing in
            instructionFocused = isInstructing
        }
    }

    // MARK: - Active escalation

    @ViewBuilder
    private var active: some View {
        if let escalation = store.current {
            VStack(alignment: .leading, spacing: 12) {
                header(escalation)

                Text(escalation.summary)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)

                if showsDetail {
                    DetailPanel(escalation: escalation)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let error = store.lastError {
                    errorBanner(error)
                }

                footer(escalation)
            }
        }
    }

    private func header(_ escalation: Escalation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            AttentionDot(tint: Theme.negative, isAnimating: store.phase == .presenting)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }

            Text(escalation.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            if !connection.state.isConnected {
                Chip(text: connection.state.shortDescription, tint: Theme.negative)
            }

            if let expiresAt = escalation.expiresAt {
                ExpiryCountdown(expiresAt: expiresAt)
            }

            if store.queuedBehindCount > 0 {
                Chip(text: "+\(store.queuedBehindCount) more", tint: Theme.neutral)
            }

            if escalation.hasDetail {
                Image(systemName: showsDetail ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.tertiaryText)
                    .onTapGesture { store.isDetailExpanded.toggle() }
            }
        }
    }

    @ViewBuilder
    private func footer(_ escalation: Escalation) -> some View {
        if case let .submitting(choice) = store.phase {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.secondaryText)
                Text(choice == "other" ? "Sending your instruction…" : "Sending your decision…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
            }
            .frame(height: 34)
            .transition(.opacity)
        } else if store.isInstructing {
            instructionField(escalation)
        } else {
            optionRow(escalation)
        }
    }

    /// §3: green and red are the two primary buttons; "Instruct" is secondary and sizes to
    /// its label rather than sharing the row equally.
    private func isPrimary(_ option: ResolutionOption) -> Bool {
        option.accent == .affirmative || option.accent == .negative
    }

    private func optionRow(_ escalation: Escalation) -> some View {
        HStack(spacing: 10) {
            ForEach(escalation.resolutionOptions) { option in
                Button {
                    store.choose(option)
                } label: {
                    Text(option.label)
                }
                .buttonStyle(NotchButtonStyle(
                    accent: Theme.accentColor(option.accent),
                    isProminent: isPrimary(option),
                    fill: isPrimary(option)
                ))
                // §7: each option's `detail` explains what picking it actually does.
                .help(option.detail ?? option.label)
            }
        }
        .transition(.opacity)
    }

    private func instructionField(_ escalation: Escalation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                "Describe how these should merge…",
                text: $store.instructionText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.primaryText)
            .lineLimit(1...4)
            .focused($instructionFocused)
            .onSubmit { store.submitInstruction() }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                            .strokeBorder(Theme.instruct.opacity(0.45), lineWidth: 1)
                    }
            }

            HStack(spacing: 8) {
                Text("Sent to the reconciler as a natural-language merge instruction.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button("Cancel") {
                    store.isInstructing = false
                }
                .buttonStyle(NotchQuietButtonStyle())

                Button("Send instruction") {
                    store.submitInstruction()
                }
                .buttonStyle(NotchButtonStyle(accent: Theme.instruct))
                .disabled(!store.canSubmitInstruction)
                .opacity(store.canSubmitInstruction ? 1 : 0.45)
                .fixedSize()
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .transition(.opacity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text(message)
                .font(.system(size: 12))
                .lineLimit(2)
            Spacer(minLength: 4)
            Button {
                store.dismissError()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.negative)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.negative.opacity(0.14))
        }
        .transition(.opacity)
    }
}

// MARK: - Detail

/// §7 "Expanded / hover": the affected file, the dependency edge that collided, and both
/// sides' intent side by side.
private struct DetailPanel: View {
    let escalation: Escalation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)

            if let file = escalation.file {
                MetaRow(label: "File", value: file)
            }
            if let edge = escalation.collidingEdge {
                MetaRow(label: "Edge", value: edge)
            }

            HStack(alignment: .top, spacing: 16) {
                if let yours = escalation.yourChange, yours.isPresentable {
                    ChangeColumn(title: "Yours", side: yours, tint: Theme.affirmative)
                }
                if let theirs = escalation.theirChange, theirs.isPresentable {
                    ChangeColumn(
                        title: theirs.devId.map { "Theirs · \($0)" } ?? "Theirs",
                        side: theirs,
                        tint: Theme.negative
                    )
                }
            }
        }
    }
}

private struct MetaRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 34, alignment: .leading)

            Text(value)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.secondaryText)
                .textSelection(.enabled)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One side of the collision. Intent first — that is the part that makes this a decision
/// rather than a guess (§9).
private struct ChangeColumn: View {
    let title: String
    let side: ChangeSide
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 5, height: 5)
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(tint.opacity(0.9))
                    .lineLimit(1)
            }

            if let intent = side.intent, !intent.isEmpty {
                Text(intent)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.primaryText.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let diff = side.diffSummary, !diff.isEmpty {
                Text(diff)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Small parts

private struct ConfirmationBanner: View {
    let symbol: String
    let tint: Color
    let headline: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .frame(height: 44)
        .transition(.opacity)
    }
}

private struct Chip: View {
    let text: String
    var tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule().fill(tint.opacity(0.16))
            }
            .fixedSize()
    }
}

/// The subtle attention cue from §3 — a slow outward pulse, not a flash.
private struct AttentionDot: View {
    let tint: Color
    var isAnimating: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 7, height: 7)
            .overlay {
                Circle()
                    .stroke(tint.opacity(0.5), lineWidth: 4)
                    .scaleEffect(pulse ? 2.6 : 1)
                    .opacity(pulse ? 0 : 0.7)
            }
            .onAppear {
                guard isAnimating else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
    }
}

/// Counts `expires_at` down so the developer can see the decision has a clock on it.
private struct ExpiryCountdown: View {
    let expiresAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, expiresAt.timeIntervalSince(context.date))
            Chip(
                text: Self.format(remaining),
                tint: remaining <= 30 ? Theme.negative : Theme.neutral
            )
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total >= 3600 { return "\(total / 3600)h left" }
        return String(format: "%d:%02d left", total / 60, total % 60)
    }
}

// MARK: - Connection state text

extension SynqitClient.ConnectionState {
    var shortDescription: String {
        switch self {
        case .idle: "Offline"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .waiting: "Reconnecting…"
        case .unauthorized: "Auth failed"
        }
    }
}
