import Foundation
import Combine

/// Core WebSocket client for the OpenClaw Gateway protocol.
@MainActor
final class GatewayClient: ObservableObject {
    static let shared = GatewayClient()

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    // MARK: - Published State
    @Published var connectionState: ConnectionState = .disconnected
    @Published var serverVersion: String = ""
    @Published var serverHost: String = ""
    @Published var connId: String = ""
    @Published var uptimeMs: Int = 0

    // MARK: - Private
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var pendingRequests: [String: CheckedContinuation<ResponseFrame, Error>] = [:]
    private var eventHandlers: [String: [(AnyCodable?) -> Void]] = [:]
    private var challengeContinuation: CheckedContinuation<String, Error>?
    private var tickTimer: Timer?
    private var reconnectTask: Task<Void, Never>?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var isReceiving = false

    private var config: ConnectionConfig? {
        ConnectionStore.load()
    }

    private init() {}

    // MARK: - Connect

    func connect(config: ConnectionConfig? = nil) async throws {
        let cfg = config ?? self.config
        guard let cfg else {
            throw GatewayError.noConfig
        }

        NSLog("[GW] connect() called, url=\(cfg.websocketURL)")

        // Clean up any existing connection
        cleanupConnection()

        connectionState = .connecting
        ConnectionStore.save(cfg)

        let url = cfg.websocketURL
        let session = URLSession(configuration: .default)
        self.urlSession = session

        let ws = session.webSocketTask(with: url)
        self.webSocket = ws
        ws.resume()

        // Start the receive loop
        startReceiving()

        // Step 1: Wait for connect.challenge event from gateway
        let nonce: String
        do {
            nonce = try await withCheckedThrowingContinuation { continuation in
                self.challengeContinuation = continuation

                // Timeout after 10 seconds
                Task {
                    try? await Task.sleep(for: .seconds(10))
                    if let cont = self.challengeContinuation {
                        self.challengeContinuation = nil
                        NSLog("[GW] TIMEOUT waiting for challenge!")
                        cont.resume(throwing: GatewayError.timeout)
                    }
                }
            }
            NSLog("[GW] Got challenge nonce=\(nonce.prefix(8))...")
        } catch {
            NSLog("[GW] Challenge wait failed: \(error)")
            connectionState = .error("No challenge from gateway: \(error.localizedDescription)")
            throw error
        }

        // Step 2: Send connect request
        NSLog("[GW] Sending connect request...")
        let connectParams: [String: Any] = [
            "minProtocol": GatewayProtocolVersion.current,
            "maxProtocol": GatewayProtocolVersion.current,
            "client": [
                "id": "openclaw-ios",
                "version": "0.1.0",
                "platform": "ios",
                "mode": "ui"
            ] as [String: Any],
            "role": "operator",
            "scopes": ["operator.read", "operator.write", "operator.admin", "operator.approvals"],
            "auth": ["token": cfg.token] as [String: Any],
            "locale": Locale.current.identifier,
            "userAgent": "openclaw-ios/0.1.0"
        ]

        let response = try await sendRequest(method: "connect", params: connectParams)
        NSLog("[GW] Connect response ok=\(response.ok)")

        guard response.ok else {
            let msg = response.error?.message ?? "Connection rejected"
            connectionState = .error(msg)
            throw GatewayError.connectionRejected(msg)
        }

        // Step 3: Parse hello-ok
        if let payloadData = try? JSONSerialization.data(withJSONObject: (response.payload?.value as? [String: Any]) ?? [:]),
           let hello = try? decoder.decode(HelloOkPayload.self, from: payloadData) {
            serverVersion = hello.server?.version ?? ""
            serverHost = hello.server?.host ?? ""
            connId = hello.server?.connId ?? ""
            if let tickMs = hello.policy?.tickIntervalMs {
                startTickTimer(intervalMs: tickMs)
            }
            NSLog("[GW] hello-ok parsed: version=\(serverVersion) host=\(serverHost)")
        }

        connectionState = .connected
        NSLog("[GW] CONNECTION ESTABLISHED!")
    }

    func disconnect() {
        cleanupConnection()
        connectionState = .disconnected
    }

    private func cleanupConnection() {
        reconnectTask?.cancel()
        reconnectTask = nil
        tickTimer?.invalidate()
        tickTimer = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        isReceiving = false

        // Fail all pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: GatewayError.notConnected)
        }
        pendingRequests.removeAll()

        // Clear challenge continuation
        if let cont = challengeContinuation {
            challengeContinuation = nil
            cont.resume(throwing: GatewayError.notConnected)
        }
    }

    // MARK: - Send Request

    @discardableResult
    func sendRequest(method: String, params: [String: Any]? = nil) async throws -> ResponseFrame {
        let frame = RequestFrame(method: method, params: params)
        let data = try encoder.encode(frame)

        guard let ws = webSocket else {
            throw GatewayError.notConnected
        }

        // Protocol requires text frames
        guard let text = String(data: data, encoding: .utf8) else {
            throw GatewayError.invalidResponse
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[frame.id] = continuation
            ws.send(.string(text)) { [weak self] error in
                if let error {
                    Task { @MainActor in
                        self?.pendingRequests.removeValue(forKey: frame.id)
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Fire-and-forget send (for ticks, etc.)
    func sendFrame(_ frame: RequestFrame) {
        guard let data = try? encoder.encode(frame),
              let text = String(data: data, encoding: .utf8),
              let ws = webSocket else { return }
        ws.send(.string(text)) { _ in }
    }

    // MARK: - Event Subscription

    func onEvent(_ eventName: String, handler: @escaping (AnyCodable?) -> Void) {
        eventHandlers[eventName, default: []].append(handler)
    }

    func removeAllEventHandlers(for eventName: String) {
        eventHandlers.removeValue(forKey: eventName)
    }

    // MARK: - Private

    private func startReceiving() {
        guard !isReceiving else { return }
        isReceiving = true
        receiveNext()
    }

    private func receiveNext() {
        guard let ws = webSocket else {
            isReceiving = false
            return
        }

        ws.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.receiveNext()
                case .failure(let error):
                    NSLog("[GW] receive FAILED: \(error)")
                    self.isReceiving = false
                    if self.connectionState == .connected {
                        self.connectionState = .error(error.localizedDescription)
                        self.attemptReconnect()
                    }
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return
        }

        guard let frame = try? decoder.decode(GatewayFrame.self, from: data) else { return }


        switch frame.type {
        case "res":
            if let id = frame.id, let continuation = pendingRequests.removeValue(forKey: id) {
                let response = ResponseFrame(
                    type: "res",
                    id: id,
                    ok: frame.ok ?? false,
                    payload: frame.payload,
                    error: frame.error
                )
                continuation.resume(returning: response)
            } else {
            }

        case "event":
            if let eventName = frame.event {
                // Handle connect.challenge specially
                if eventName == "connect.challenge" {
                    if let cont = challengeContinuation {
                        challengeContinuation = nil
                        let nonce = (frame.payload?.dict?["nonce"] as? String) ?? ""
                        cont.resume(returning: nonce)
                    } else {
                    }
                }

                // Dispatch to all registered handlers
                let handlerCount = eventHandlers[eventName]?.count ?? 0
                eventHandlers[eventName]?.forEach { $0(frame.payload) }
            }

        default:
            break
        }
    }

    private func startTickTimer(intervalMs: Int) {
        tickTimer?.invalidate()
        let interval = TimeInterval(intervalMs) / 1000.0
        tickTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendTick()
            }
        }
    }

    private func sendTick() {
        let frame = RequestFrame(method: "tick", params: ["ts": Int(Date().timeIntervalSince1970 * 1000)])
        sendFrame(frame)
    }

    private func attemptReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task {
            var delay: TimeInterval = 2
            for attempt in 1...5 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }

                guard let config else { return }

                do {
                    try await connect(config: config)
                    return // Success
                } catch {
                    delay = min(delay * 1.5, 30) // Exponential backoff, max 30s
                }
            }
            // Give up after 5 attempts
            connectionState = .error("Reconnection failed")
        }
    }
}

// MARK: - Errors

enum GatewayError: LocalizedError {
    case noConfig
    case notConnected
    case connectionRejected(String)
    case timeout
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noConfig: "No gateway configuration found"
        case .notConnected: "Not connected to gateway"
        case .connectionRejected(let msg): "Connection rejected: \(msg)"
        case .timeout: "Request timed out"
        case .invalidResponse: "Invalid response from gateway"
        }
    }
}
