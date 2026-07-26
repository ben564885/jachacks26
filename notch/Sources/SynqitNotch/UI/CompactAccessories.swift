import SwiftUI

/// Shown to the left of the physical notch when the developer has collapsed an escalation
/// without resolving it. It keeps the decision visible without taking over the screen.
struct CompactLeadingView: View {
    @ObservedObject var store: EscalationStore

    var body: some View {
        Image(systemName: "arrow.triangle.pull")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.negative)
            .padding(.leading, 4)
    }
}

/// The queue count from §7. Tapping either accessory reopens the escalation.
struct CompactTrailingView: View {
    @ObservedObject var store: EscalationStore

    var body: some View {
        Text(store.pendingCount > 1 ? "\(store.pendingCount)" : "1")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background {
                Capsule().fill(Theme.negative.opacity(0.85))
            }
            .padding(.trailing, 4)
            .onTapGesture { store.restore() }
    }
}
