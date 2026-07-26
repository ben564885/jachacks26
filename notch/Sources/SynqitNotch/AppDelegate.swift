import AppKit
import OSLog

/// Wires the three layers together and keeps them alive for the process lifetime.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config: AppConfig?
    private var store: EscalationStore?
    private var client: SynqitClient?
    private var presenter: NotchPresenter?
    private var menuBar: MenuBarController?

    private let log = Logger(subsystem: "com.synqit.notch", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config: AppConfig
        do {
            config = try AppConfig.load()
        } catch {
            presentConfigFailure(error)
            return
        }
        self.config = config

        if config.isTransportInsecure {
            // §12 expects TLS. A plaintext socket to a non-loopback host is worth a line in
            // the log even though we still connect — refusing outright would be worse than
            // telling the developer what they configured.
            log.warning("connecting over plaintext ws:// to \(config.serverURL.host() ?? "?", privacy: .public)")
        }

        let store = EscalationStore(devId: config.devId)
        let client = SynqitClient(config: config, tokenProvider: { config.token() })

        // Connection layer feeds the state layer; the state layer relays choices back out.
        // Neither knows about the other's type.
        client.onEvent = { [weak store] event in
            store?.receive(event)
        }
        store.sendResolution = { [weak client] resolution in
            try await client?.send(.resolution(resolution))
        }

        let presenter = NotchPresenter(store: store, connection: client)
        let menuBar = MenuBarController(store: store, connection: client, config: config, presenter: presenter)

        self.store = store
        self.client = client
        self.presenter = presenter
        self.menuBar = menuBar

        client.start()

        if config.token() == nil {
            promptForMissingToken(config: config)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        client?.stop()
        store?.shutdown()
    }

    // MARK: - First-run problems

    private func presentConfigFailure(_ error: Error) {
        NSApp.activate()

        let alert = NSAlert()
        alert.messageText = "Synqit Notch isn't configured yet"
        alert.informativeText = """
        \(error.localizedDescription)

        Create \(AppConfig.defaultPath.path) with your server URL and developer id, then set \
        an access token from the menu bar.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Create config…")
        alert.addButton(withTitle: "Quit")

        if alert.runModal() == .alertFirstButtonReturn {
            do {
                _ = try AppConfig.writeTemplate()
                NSWorkspace.shared.activateFileViewerSelecting([AppConfig.defaultPath])
            } catch {
                log.error("couldn't write config template: \(error.localizedDescription, privacy: .public)")
            }
        }
        NSApp.terminate(nil)
    }

    private func promptForMissingToken(config: AppConfig) {
        NSApp.activate()

        let alert = NSAlert()
        alert.messageText = "No access token for \(config.devId)"
        alert.informativeText = "The notch can't authenticate until you provide one. It is stored in your login keychain."
        alert.addButton(withTitle: "Set token…")
        alert.addButton(withTitle: "Later")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Bearer token"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let token = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        do {
            try Keychain.setToken(token, for: config.devId)
            client?.reconnectNow()
        } catch {
            log.error("couldn't store token: \(error.localizedDescription, privacy: .public)")
        }
    }
}
