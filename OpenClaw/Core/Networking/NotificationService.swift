import Foundation
import UserNotifications
import UIKit

/// Handles local push notifications for agent messages and exec approvals.
/// Supports inline reply directly from the notification banner.
@MainActor
final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    // MARK: - Categories & Actions
    static let messageCategory = "AGENT_MESSAGE"
    static let approvalCategory = "EXEC_APPROVAL"
    static let replyAction = "REPLY_ACTION"
    static let approveAction = "APPROVE_ACTION"
    static let rejectAction = "REJECT_ACTION"

    @Published var isAuthorized = false

    private var gateway: GatewayClient { GatewayClient.shared }
    private var isAppActive = true

    private override init() {
        super.init()
    }

    // MARK: - Setup

    func configure() {
        registerCategories()
        requestPermission()
        observeAppState()
        listenForEvents()
    }

    private func registerCategories() {
        // Reply action (text input from notification)
        let replyAction = UNTextInputNotificationAction(
            identifier: Self.replyAction,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type a reply..."
        )

        // Message category with reply
        let messageCategory = UNNotificationCategory(
            identifier: Self.messageCategory,
            actions: [replyAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        // Approval actions
        let approveAction = UNNotificationAction(
            identifier: Self.approveAction,
            title: "Approve",
            options: [.authenticationRequired]
        )
        let rejectAction = UNNotificationAction(
            identifier: Self.rejectAction,
            title: "Reject",
            options: [.destructive]
        )

        // Approval category
        let approvalCategory = UNNotificationCategory(
            identifier: Self.approvalCategory,
            actions: [approveAction, rejectAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            messageCategory,
            approvalCategory,
        ])
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { [weak self] granted, _ in
            Task { @MainActor in
                self?.isAuthorized = granted
            }
        }
    }

    // MARK: - App State

    private func observeAppState() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isAppActive = true }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isAppActive = false }
        }
    }

    // MARK: - Event Listeners

    private func listenForEvents() {
        // Agent done (full message ready)
        gateway.onEvent("agent.done") { [weak self] payload in
            Task { @MainActor in
                guard let self, !self.isAppActive else { return }

                let dict = payload?.dict
                let text = dict?["text"] as? String
                    ?? dict?["message"] as? String
                    ?? "New message from your agent"
                let sessionKey = dict?["sessionKey"] as? String

                self.showMessageNotification(text: text, sessionKey: sessionKey)
            }
        }

        // Exec approval requested
        gateway.onEvent("exec.approval.requested") { [weak self] payload in
            Task { @MainActor in
                guard let self else { return }

                let dict = payload?.dict
                let requestId = dict?["requestId"] as? String ?? ""
                let command = dict?["command"] as? String ?? "Unknown command"

                self.showApprovalNotification(requestId: requestId, command: command)
            }
        }
    }

    // MARK: - Show Notifications

    private func showMessageNotification(text: String, sessionKey: String?) {
        let content = UNMutableNotificationContent()
        content.title = "OpenClaw"
        content.body = String(text.prefix(256))
        content.sound = .default
        content.categoryIdentifier = Self.messageCategory
        if let sessionKey {
            content.userInfo["sessionKey"] = sessionKey
        }

        let request = UNNotificationRequest(
            identifier: "agent-msg-\(UUID().uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func showApprovalNotification(requestId: String, command: String) {
        let content = UNMutableNotificationContent()
        content.title = "Approval Required"
        content.body = command.prefix(200).description
        content.sound = .default
        content.categoryIdentifier = Self.approvalCategory
        content.userInfo["requestId"] = requestId
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "approval-\(requestId)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Handle Notification Responses

    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        let categoryId = response.notification.request.content.categoryIdentifier

        switch (categoryId, response.actionIdentifier) {

        // Reply to agent message
        case (Self.messageCategory, Self.replyAction):
            if let textResponse = response as? UNTextInputNotificationResponse {
                let replyText = textResponse.userText
                let sessionKey = userInfo["sessionKey"] as? String
                Task {
                    try? await gateway.sendRequest(
                        method: "agent",
                        params: [
                            "message": replyText,
                            "sessionKey": sessionKey as Any,
                            "idempotencyKey": UUID().uuidString,
                        ].compactMapValues { $0 }
                    )
                }
            }

        // Approve exec
        case (Self.approvalCategory, Self.approveAction):
            if let requestId = userInfo["requestId"] as? String {
                Task {
                    _ = try? await gateway.sendRequest(
                        method: "exec.approval.resolve",
                        params: ["requestId": requestId, "approved": true]
                    )
                }
            }

        // Reject exec
        case (Self.approvalCategory, Self.rejectAction):
            if let requestId = userInfo["requestId"] as? String {
                Task {
                    _ = try? await gateway.sendRequest(
                        method: "exec.approval.resolve",
                        params: ["requestId": requestId, "approved": false]
                    )
                }
            }

        default:
            break
        }
    }
}
