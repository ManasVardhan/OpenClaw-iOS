import UIKit
import UserNotifications

/// AppDelegate handles notification delegation and background tasks.
final class AppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BackgroundTaskManager.register()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackgroundTaskManager.scheduleRefresh()
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications even when app is in foreground (for exec approvals)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let category = notification.request.content.categoryIdentifier

        // Always show exec approvals as banners, even in foreground
        if category == NotificationService.approvalCategory {
            completionHandler([.banner, .sound])
        } else {
            // Don't show message notifications if app is active (already visible in chat)
            completionHandler([])
        }
    }

    /// Handle notification action responses (reply, approve, reject)
    @MainActor
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NotificationService.shared.handleNotificationResponse(response)
        completionHandler()
    }
}
