import AppKit
import Combine
import DynamicNotchKit
import SwiftUI

/// The presentation layer (§5.3). Owns a single `DynamicNotch` and drives it from store state.
///
/// DynamicNotchKit captures its content views once at construction, so the notch is built
/// exactly one time and stays reactive through the `EscalationStore` the views observe. This
/// class only decides *which* of the library's three appearances should be on screen.
@MainActor
final class NotchPresenter {
    private enum Target: Equatable {
        case hidden
        case compact
        case expanded
    }

    private let store: EscalationStore
    private let notch: DynamicNotch<EscalationView, CompactLeadingView, CompactTrailingView>

    private var cancellables = Set<AnyCancellable>()
    /// Transitions are chained rather than fired concurrently: the library's expand/compact/hide
    /// each animate for ~0.4s and will fight each other if overlapped.
    private var transition: Task<Void, Never>?
    private var target: Target = .hidden
    private var didActivateForInstruction = false

    init(store: EscalationStore, connection: SynqitClient) {
        self.store = store
        self.notch = DynamicNotch(
            hoverBehavior: [.keepVisible, .increaseShadow],
            style: .auto,
            expanded: { EscalationView(store: store, connection: connection) },
            compactLeading: { CompactLeadingView(store: store) },
            compactTrailing: { CompactTrailingView(store: store) }
        )

        // `objectWillChange` fires before the mutation lands, so hop to the next main-actor
        // turn and read the settled state.
        store.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.sync() }
            }
            .store(in: &cancellables)
    }

    /// Force the escalation back on screen (menu bar "Show current escalation").
    func reveal() {
        store.restore()
        sync()
    }

    private func sync() {
        let desired: Target
        if store.queue.isEmpty, store.phase == .idle {
            desired = .hidden
        } else if store.isMinimized {
            desired = .compact
        } else {
            desired = .expanded
        }

        updateKeyWindow()

        guard desired != target else { return }
        target = desired

        let previous = transition
        transition = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await self.apply(self.target)
        }
    }

    private func apply(_ target: Target) async {
        switch target {
        case .hidden:
            await notch.hide()
        case .compact:
            guard let screen = Self.targetScreen() else { return }
            await notch.compact(on: screen)
        case .expanded:
            guard let screen = Self.targetScreen() else { return }
            await notch.expand(on: screen)
        }
    }

    /// The notch panel is `.nonactivatingPanel`, and this is an accessory app with no windows,
    /// so the instruction field only receives keystrokes if we explicitly take focus. We do
    /// that only when the developer opens the field, and hand focus back when they leave it.
    private func updateKeyWindow() {
        if store.isInstructing, !didActivateForInstruction {
            didActivateForInstruction = true
            NSApp.activate()
            notch.windowController?.window?.makeKeyAndOrderFront(nil)
        } else if !store.isInstructing, didActivateForInstruction {
            didActivateForInstruction = false
            NSApp.deactivate()
        }
    }

    /// §10: present on the currently active screen, never split across displays. The screen
    /// under the cursor is the best proxy for "where the developer is looking"; the library
    /// falls back to its floating capsule automatically if that screen has no notch.
    private static func targetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
}
