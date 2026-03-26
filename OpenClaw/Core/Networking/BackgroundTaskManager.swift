import Foundation
import BackgroundTasks
import UIKit

/// Manages background app refresh to maintain gateway connection
/// and deliver notifications when the app is backgrounded.
enum BackgroundTaskManager {
    static let refreshTaskId = "ai.openclaw.mobile.refresh"

    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshTaskId,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            Task { @MainActor in
                handleRefresh(refreshTask)
            }
        }
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    private static func handleRefresh(_ task: BGAppRefreshTask) {
        // Schedule the next refresh
        scheduleRefresh()

        let gateway = GatewayClient.shared

        task.expirationHandler = {
            // Clean up if we run out of time
        }

        Task { @MainActor in
            // If disconnected, try to reconnect
            if gateway.connectionState != .connected {
                if let config = ConnectionStore.load() {
                    try? await gateway.connect(config: config)
                }
            }

            // Send a ping to keep connection alive
            if gateway.connectionState == .connected {
                _ = try? await gateway.sendRequest(method: "ping")
            }

            task.setTaskCompleted(success: true)
        }
    }
}
