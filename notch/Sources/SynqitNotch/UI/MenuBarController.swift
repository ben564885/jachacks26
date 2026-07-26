import AppKit
import Combine
import ServiceManagement

/// The optional menu-bar surface from §5/§13: status, a way back to a dismissed escalation,
/// token management, and quit. The app is `LSUIElement`, so this is the only chrome it has.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let store: EscalationStore
    private let connection: SynqitClient
    private let config: AppConfig
    private let presenter: NotchPresenter
    private var cancellables = Set<AnyCancellable>()

    init(store: EscalationStore, connection: SynqitClient, config: AppConfig, presenter: NotchPresenter) {
        self.store = store
        self.connection = connection
        self.config = config
        self.presenter = presenter
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshButton()

        store.objectWillChange
            .sink { [weak self] _ in Task { @MainActor in self?.refreshButton() } }
            .store(in: &cancellables)
        connection.objectWillChange
            .sink { [weak self] _ in Task { @MainActor in self?.refreshButton() } }
            .store(in: &cancellables)
    }

    private func refreshButton() {
        guard let button = statusItem.button else { return }
        let pending = store.pendingCount
        let symbol = pending > 0 ? "arrow.triangle.pull" : "arrow.triangle.merge"

        button.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "Synqit"
        )
        button.image?.isTemplate = pending == 0
        button.contentTintColor = pending > 0 ? .systemRed : nil
        button.title = pending > 1 ? " \(pending)" : ""
        button.toolTip = tooltip
    }

    private var tooltip: String {
        let status = connection.state.shortDescription
        guard store.pendingCount > 0 else { return "Synqit · \(config.devId) · \(status)" }
        return "Synqit · \(store.pendingCount) conflict(s) awaiting you · \(status)"
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(header("Synqit · \(config.devId)"))
        menu.addItem(header(connection.state.menuDescription))

        if config.isTransportInsecure {
            menu.addItem(header("⚠︎ Insecure ws:// connection"))
        }

        menu.addItem(.separator())

        if store.pendingCount > 0 {
            menu.addItem(header(store.pendingCount == 1
                ? "1 conflict awaiting you"
                : "\(store.pendingCount) conflicts awaiting you"))
            menu.addItem(item("Show escalation", action: #selector(showEscalation), key: "s"))
        } else {
            menu.addItem(header("No conflicts awaiting you"))
        }

        menu.addItem(.separator())
        menu.addItem(item("Reconnect now", action: #selector(reconnect), key: "r"))
        menu.addItem(item("Set access token…", action: #selector(setToken), key: ""))

        let launchItem = item("Launch at login", action: #selector(toggleLaunchAtLogin), key: "")
        launchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())
        menu.addItem(item("Quit Synqit Notch", action: #selector(quit), key: "q"))
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func item(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func showEscalation() {
        presenter.reveal()
    }

    @objc private func reconnect() {
        connection.reconnectNow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // Registration needs a real bundled app; running the bare SPM binary will fail here.
            present(alert: "Couldn't change the login item", detail: error.localizedDescription)
        }
    }

    @objc private func setToken() {
        NSApp.activate()

        let alert = NSAlert()
        alert.messageText = "Access token for \(config.devId)"
        alert.informativeText = "Stored in your login keychain and sent as a bearer token when the notch connects."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Bearer token"
        field.stringValue = Keychain.token(for: config.devId) ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let token = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if token.isEmpty {
                try Keychain.deleteToken(for: config.devId)
            } else {
                try Keychain.setToken(token, for: config.devId)
            }
            connection.reconnectNow()
        } catch {
            present(alert: "Couldn't save the token", detail: error.localizedDescription)
        }
    }

    private func present(alert title: String, detail: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }
}

extension SynqitClient.ConnectionState {
    /// Longer form for the menu, including when the next retry lands.
    var menuDescription: String {
        switch self {
        case .idle:
            return "Not connected"
        case .connecting:
            return "Connecting…"
        case .connected:
            return "Connected"
        case let .waiting(until, reason):
            let seconds = max(0, Int(until.timeIntervalSinceNow.rounded()))
            return "Reconnecting in \(seconds)s — \(reason)"
        case .unauthorized:
            return "Token rejected — set a valid access token"
        }
    }
}
