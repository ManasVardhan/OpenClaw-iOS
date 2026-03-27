import Foundation
import Combine

/// Manages agent chat interactions over the gateway protocol.
/// Uses chat.send / chat.history / chat events (the same API as the Control UI).
@MainActor
final class ChatService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isAgentTyping = false
    @Published var currentStreamText = ""
    @Published var hasLoadedHistory = false

    private let gateway: GatewayClient
    private var currentRunId: String?
    private(set) var sessionKey: String = "agent:main:main"

    init(gateway: GatewayClient) {
        self.gateway = gateway
        setupEventHandlers()
    }

    // MARK: - Resolve Session

    func resolveSession() async {
        do {
            let response = try await gateway.sendRequest(
                method: "sessions.list",
                params: ["limit": 30, "includeLastMessage": true]
            )
            if response.ok,
               let payload = response.payload?.dict,
               let sessions = payload["sessions"] as? [[String: Any]] {
                for sess in sessions {
                    if let key = sess["key"] as? String,
                       key.hasSuffix(":main") && !key.contains("cron") && !key.contains("subagent") {
                        sessionKey = key
                        break
                    }
                }
            }
        } catch {
            NSLog("[Chat] session resolve failed: \(error)")
        }
    }

    // MARK: - Load History

    func loadHistory() async {
        guard !hasLoadedHistory else { return }

        await resolveSession()

        do {
            let response = try await gateway.sendRequest(
                method: "chat.history",
                params: ["sessionKey": sessionKey, "limit": 50]
            )

            guard response.ok,
                  let payload = response.payload?.dict,
                  let history = payload["messages"] as? [[String: Any]] else {
                hasLoadedHistory = true
                return
            }

            var loaded: [ChatMessage] = []
            for msg in history {
                let roleStr = msg["role"] as? String ?? "system"

                // Only show user and assistant messages
                guard roleStr == "user" || roleStr == "assistant" else { continue }

                // Content can be string or array of content blocks
                let content: String
                if let str = msg["content"] as? String {
                    content = str
                } else if let blocks = msg["content"] as? [[String: Any]] {
                    content = blocks.compactMap { block -> String? in
                        let type = block["type"] as? String
                        if type == "text" { return block["text"] as? String }
                        if type == "thinking" { return nil } // Skip thinking blocks
                        return nil
                    }.joined(separator: "\n")
                } else {
                    continue
                }

                guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                let role: ChatMessage.Role = roleStr == "user" ? .user : .assistant
                loaded.append(ChatMessage(role: role, content: content))
            }

            // Only show the last ~20 messages to avoid overwhelming the UI
            messages = Array(loaded.suffix(20))
            hasLoadedHistory = true
            NSLog("[Chat] Loaded \(loaded.count) messages, showing last \(messages.count)")
        } catch {
            NSLog("[Chat] history load failed: \(error)")
            hasLoadedHistory = true
        }
    }

    // MARK: - Send Message

    func send(_ text: String) async throws {
        let userMsg = ChatMessage(role: .user, content: text)
        messages.append(userMsg)

        isAgentTyping = true
        currentStreamText = ""

        let idempotencyKey = UUID().uuidString

        do {
            let response = try await gateway.sendRequest(
                method: "chat.send",
                params: [
                    "sessionKey": sessionKey,
                    "message": text,
                    "idempotencyKey": idempotencyKey
                ]
            )

            if !response.ok {
                isAgentTyping = false
                let errorMsg = response.error?.message ?? "Unknown error"
                messages.append(ChatMessage(role: .system, content: "Error: \(errorMsg)"))
                return
            }

            if let payload = response.payload?.dict,
               let runId = payload["runId"] as? String {
                currentRunId = runId
            }
        } catch {
            isAgentTyping = false
            messages.append(ChatMessage(role: .system, content: "Send failed: \(error.localizedDescription)"))
        }
    }

    // MARK: - Event Handlers

    private func setupEventHandlers() {
        // The gateway sends "chat" events with state: delta/final/aborted/error
        gateway.onEvent("chat") { [weak self] payload in
            Task { @MainActor in
                self?.handleChatEvent(payload)
            }
        }
    }

    private func handleChatEvent(_ payload: AnyCodable?) {
        guard let dict = payload?.dict else { return }

        let state = dict["state"] as? String
        let runId = dict["runId"] as? String

        // Only process events for our current run (or if we don't have a runId yet)
        if let currentRunId, let runId, currentRunId != runId { return }

        switch state {
        case "delta":
            // Streaming text
            if let message = dict["message"] as? String {
                currentStreamText += message
            } else if let message = dict["message"] as? [String: Any],
                      let text = message["text"] as? String {
                currentStreamText += text
            }

        case "final":
            isAgentTyping = false

            if !currentStreamText.isEmpty {
                // We got streaming deltas, use the accumulated text
                messages.append(ChatMessage(role: .assistant, content: currentStreamText))
                currentStreamText = ""
            } else {
                // No streaming, fetch the latest response from history
                Task {
                    await fetchLatestResponse()
                }
            }
            currentRunId = nil

        case "error":
            isAgentTyping = false
            currentStreamText = ""
            let errorMsg = dict["errorMessage"] as? String ?? "Agent error"
            messages.append(ChatMessage(role: .system, content: "Error: \(errorMsg)"))
            currentRunId = nil

        case "aborted":
            isAgentTyping = false
            currentStreamText = ""
            messages.append(ChatMessage(role: .system, content: "Response cancelled"))
            currentRunId = nil

        default:
            break
        }
    }

    /// Fetch the latest assistant message after a run completes (fallback when no streaming deltas arrive)
    private func fetchLatestResponse() async {
        do {
            let response = try await gateway.sendRequest(
                method: "chat.history",
                params: ["sessionKey": sessionKey, "limit": 3]
            )

            guard response.ok,
                  let payload = response.payload?.dict,
                  let history = payload["messages"] as? [[String: Any]] else { return }

            // Find the last assistant message
            for msg in history.reversed() {
                let roleStr = msg["role"] as? String
                guard roleStr == "assistant" else { continue }

                let content: String
                if let str = msg["content"] as? String {
                    content = str
                } else if let blocks = msg["content"] as? [[String: Any]] {
                    content = blocks.compactMap { block -> String? in
                        if block["type"] as? String == "text" { return block["text"] as? String }
                        return nil
                    }.joined(separator: "\n")
                } else {
                    continue
                }

                guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                messages.append(ChatMessage(role: .assistant, content: content))
                break
            }
        } catch {
            NSLog("[Chat] fetchLatestResponse failed: \(error)")
        }
    }
}
