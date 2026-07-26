import Foundation

/// Where the notch points and who it claims to be.
///
/// Read from `~/.synqit/config.json` at launch; the bearer token comes from the keychain, not
/// from this file. Environment variables override the file for development against the mock
/// server — note that a GUI app launched from Finder or as a login item inherits no shell
/// environment, so the file is the real configuration path.
struct AppConfig: Equatable, Sendable {
    var serverURL: URL
    var devId: String

    static let defaultPath = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: ".synqit/config.json")

    enum Failure: LocalizedError {
        case missingFile(URL)
        case malformed(URL, underlying: String)
        case invalidURL(String)

        var errorDescription: String? {
            switch self {
            case let .missingFile(url):
                "No config at \(url.path). Create it with: SynqitNotch --init"
            case let .malformed(url, underlying):
                "Config at \(url.path) could not be read: \(underlying)"
            case let .invalidURL(raw):
                "server_url is not a valid ws:// or wss:// URL: \(raw)"
            }
        }
    }

    private struct FileShape: Codable {
        var serverUrl: String?
        var devId: String?
    }

    /// Loads config, applying environment overrides on top of the file. If both env vars are
    /// set the file need not exist at all, which is what the mock-server workflow relies on.
    static func load(path: URL = defaultPath, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> AppConfig {
        var rawURL = environment["SYNQIT_SERVER_URL"]
        var rawDevId = environment["SYNQIT_DEV_ID"]

        if rawURL == nil || rawDevId == nil {
            guard FileManager.default.fileExists(atPath: path.path) else {
                throw Failure.missingFile(path)
            }
            let shape: FileShape
            do {
                let data = try Data(contentsOf: path)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                shape = try decoder.decode(FileShape.self, from: data)
            } catch {
                throw Failure.malformed(path, underlying: error.localizedDescription)
            }
            rawURL = rawURL ?? shape.serverUrl
            rawDevId = rawDevId ?? shape.devId
        }

        guard let rawURL, let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(), scheme == "ws" || scheme == "wss"
        else {
            throw Failure.invalidURL(rawURL ?? "<missing>")
        }
        guard let rawDevId, !rawDevId.isEmpty else {
            throw Failure.malformed(path, underlying: "dev_id is missing")
        }

        return AppConfig(serverURL: url, devId: rawDevId)
    }

    /// Token for this developer. The env var is a development convenience; the keychain is
    /// the real storage.
    func token(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        environment["SYNQIT_TOKEN"] ?? Keychain.token(for: devId)
    }

    /// `wss://` in production. A plaintext `ws://` connection to anything but loopback is a
    /// misconfiguration worth surfacing rather than silently accepting (§12).
    var isTransportInsecure: Bool {
        guard serverURL.scheme?.lowercased() == "ws" else { return false }
        let host = serverURL.host()?.lowercased()
        return !(host == "localhost" || host == "127.0.0.1" || host == "::1")
    }

    /// Writes a starter config, without clobbering one that already exists.
    static func writeTemplate(to path: URL = defaultPath) throws -> Bool {
        guard !FileManager.default.fileExists(atPath: path.path) else { return false }
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let template = """
        {
          "server_url": "ws://127.0.0.1:8787",
          "dev_id": "dev_ben"
        }
        """
        try Data(template.utf8).write(to: path, options: .atomic)
        return true
    }
}
