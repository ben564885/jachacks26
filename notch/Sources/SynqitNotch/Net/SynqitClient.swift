import Foundation
import OSLog

/// The connection layer (§5.1): one authenticated, always-on socket to the Synqit backend,
/// tagged with this developer's id.
///
/// It owns reconnection, heartbeats, and the pending-sync request that runs on every
/// (re)connect so nothing is missed while offline (§8). It has no opinion about conflicts —
/// it hands decoded events to `onEvent` and sends whatever `send(_:)` is given.
@MainActor
final class SynqitClient: ObservableObject {
    enum ConnectionState: Equatable, Sendable {
        case idle
        case connecting
        case connected
        /// Disconnected, retrying at `at`.
        case waiting(until: Date, reason: String)
        /// Authentication was rejected. Retrying, but slowly — a bad token won't fix itself.
        case unauthorized

        var isConnected: Bool { self == .connected }
    }

    @Published private(set) var state: ConnectionState = .idle

    /// Called on the main actor for every decoded inbound event.
    var onEvent: (@MainActor (InboundEvent) -> Void)?

    private let config: AppConfig
    private let tokenProvider: @MainActor () -> String?
    private let session: URLSession
    private let log = Logger(subsystem: "com.synqit.notch", category: "socket")

    private var runTask: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?

    /// §8: exponential backoff with jitter.
    private let baseBackoff: TimeInterval = 1
    private let maxBackoff: TimeInterval = 30
    private let unauthorizedBackoff: TimeInterval = 60
    private let heartbeatInterval: Duration = .seconds(20)

    init(
        config: AppConfig,
        tokenProvider: @escaping @MainActor () -> String? = { nil },
        session: URLSession = .shared
    ) {
        self.config = config
        self.tokenProvider = tokenProvider
        self.session = session
    }

    // MARK: - Lifecycle

    func start() {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            await self?.supervise()
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        state = .idle
    }

    /// Drops the current connection so the supervisor reconnects immediately. Used by the
    /// menu bar's "Reconnect now" and after a token change.
    func reconnectNow() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    // MARK: - Supervision

    private func supervise() async {
        var attempt = 0

        while !Task.isCancelled {
            state = .connecting
            var wasAuthFailure = false
            var reason = "connection closed"

            do {
                try await runConnection()
                // A clean return means the socket closed without error; treat it as a normal
                // disconnect and reconnect promptly.
                attempt = 0
            } catch let error as ClientError {
                switch error {
                case .unauthorized:
                    wasAuthFailure = true
                    reason = "authentication rejected"
                case let .missingToken(message):
                    wasAuthFailure = true
                    reason = message
                }
            } catch {
                reason = error.localizedDescription
                log.error("socket error: \(error.localizedDescription, privacy: .public)")
            }

            socket = nil
            if Task.isCancelled { break }

            let delay: TimeInterval
            if wasAuthFailure {
                state = .unauthorized
                delay = unauthorizedBackoff
            } else {
                delay = backoffDelay(forAttempt: attempt)
                attempt += 1
                state = .waiting(until: Date().addingTimeInterval(delay), reason: reason)
            }

            try? await Task.sleep(for: .seconds(delay))
        }

        state = .idle
    }

    /// Exponential backoff capped at `maxBackoff`, with ±20% jitter so a fleet of clients
    /// doesn't reconnect in lockstep after a backend restart.
    private func backoffDelay(forAttempt attempt: Int) -> TimeInterval {
        let exponential = min(maxBackoff, baseBackoff * pow(2, Double(min(attempt, 10))))
        let jitter = Double.random(in: 0.8...1.2)
        return min(maxBackoff, exponential * jitter)
    }

    private enum ClientError: Error {
        case unauthorized
        case missingToken(String)
    }

    /// Opens one connection and pumps it until it fails or is cancelled.
    private func runConnection() async throws {
        guard let token = tokenProvider(), !token.isEmpty else {
            throw ClientError.missingToken("no token stored for \(config.devId)")
        }

        var request = URLRequest(url: config.serverURL)
        // §12: bearer token on the connection request, scoped to one developer.
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(config.devId, forHTTPHeaderField: "X-Synqit-Dev-Id")
        request.timeoutInterval = 30

        let task = session.webSocketTask(with: request)
        self.socket = task
        task.resume()

        defer { task.cancel(with: .goingAway, reason: nil) }

        // A ping only completes once the HTTP upgrade has succeeded, which makes it a clean
        // handshake check — and lets us distinguish a rejected token from a dead network.
        do {
            try await task.sendPing()
        } catch {
            if let response = task.response as? HTTPURLResponse, response.statusCode == 401 || response.statusCode == 403 {
                throw ClientError.unauthorized
            }
            throw error
        }

        state = .connected
        log.info("connected as \(self.config.devId, privacy: .public)")

        try await send(.hello(devId: config.devId, client: Self.clientIdentifier))
        // §8: reconcile against the backend on every (re)connect.
        try await send(.fetchPending(devId: config.devId))

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [heartbeatInterval = self.heartbeatInterval] in
                while !Task.isCancelled {
                    try await Task.sleep(for: heartbeatInterval)
                    try await task.sendPing()
                }
            }
            group.addTask { [weak self] in
                while !Task.isCancelled {
                    let message = try await task.receive()
                    await self?.handle(message)
                }
            }
            // Whichever arm fails first tears down the connection.
            try await group.next()
            group.cancelAll()
        }
    }

    private static let clientIdentifier: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "synqit-notch-macos/\(version ?? "dev")"
    }()

    // MARK: - Messages

    func send(_ message: OutboundMessage) async throws {
        guard let socket else { return }
        let data = try SynqitJSON.encoder.encode(message)
        guard let text = String(data: data, encoding: .utf8) else { return }
        try await socket.send(.string(text))
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case let .string(text):
            data = Data(text.utf8)
        case let .data(payload):
            data = payload
        @unknown default:
            return
        }

        do {
            let event = try SynqitJSON.decoder.decode(InboundEvent.self, from: data)
            if case let .unrecognised(type) = event {
                // §12: anything outside the schema is inert.
                log.notice("ignoring unrecognised event type \(type, privacy: .public)")
                return
            }
            onEvent?(event)
        } catch {
            log.error("undecodable payload: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Ping bridging

private extension URLSessionWebSocketTask {
    /// `sendPing` is still completion-handler only; this bridges it to async so the heartbeat
    /// reads like the rest of the connection code.
    func sendPing() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
