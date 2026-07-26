import AppKit

// Small CLI in front of the app so a token can be provisioned from a terminal or a setup
// script, without shipping a login window (§5 config, §12 security).

let arguments = Array(CommandLine.arguments.dropFirst())

func printUsage() {
    print("""
    Synqit Notch — the human-in-the-loop escalation surface for Synqit.

    Usage:
      SynqitNotch                    Run the background app (default).
      SynqitNotch --init             Write a starter ~/.synqit/config.json.
      SynqitNotch --login [TOKEN]    Store an access token in the keychain.
                                     Omit TOKEN to read it from stdin.
      SynqitNotch --logout           Remove the stored token.
      SynqitNotch --status           Print the current configuration.
      SynqitNotch --help             Show this message.

    Configuration lives in ~/.synqit/config.json:
      { "server_url": "wss://api.synqit.dev/notch", "dev_id": "dev_ben" }

    SYNQIT_SERVER_URL / SYNQIT_DEV_ID / SYNQIT_TOKEN override the file when set, which is
    how the bundled mock server is usually driven. Note that a login item inherits no shell
    environment, so real installs should use the config file.
    """)
}

func loadConfigOrExit() -> AppConfig {
    do {
        return try AppConfig.load()
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

if arguments.contains("--help") || arguments.contains("-h") {
    printUsage()
    exit(0)
}

if arguments.contains("--init") {
    do {
        let created = try AppConfig.writeTemplate()
        print(created
            ? "Wrote \(AppConfig.defaultPath.path)"
            : "\(AppConfig.defaultPath.path) already exists — leaving it alone.")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

if arguments.contains("--status") {
    let config = loadConfigOrExit()
    print("server_url: \(config.serverURL.absoluteString)")
    print("dev_id:     \(config.devId)")
    print("token:      \(config.token() == nil ? "not set" : "set (keychain)")")
    if config.isTransportInsecure {
        print("warning:    plaintext ws:// to a non-loopback host")
    }
    exit(0)
}

if arguments.contains("--logout") {
    let config = loadConfigOrExit()
    do {
        let removed = try Keychain.deleteToken(for: config.devId)
        print(removed ? "Removed the token for \(config.devId)." : "No token was stored for \(config.devId).")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

if let index = arguments.firstIndex(of: "--login") {
    let config = loadConfigOrExit()

    // Reading from stdin keeps the token out of shell history, which is the reason the
    // inline form is optional.
    let inline = arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
    let token = (inline ?? String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !token.isEmpty else {
        FileHandle.standardError.write(Data("error: no token provided\n".utf8))
        exit(1)
    }

    do {
        try Keychain.setToken(token, for: config.devId)
        print("Stored an access token for \(config.devId).")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

if let unknown = arguments.first(where: { $0.hasPrefix("-") }) {
    FileHandle.standardError.write(Data("error: unknown option \(unknown)\n".utf8))
    printUsage()
    exit(1)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// Belt and braces alongside LSUIElement in Info.plist: this also covers running the bare
// SPM binary during development, where there is no bundle to read.
application.setActivationPolicy(.accessory)
application.run()
