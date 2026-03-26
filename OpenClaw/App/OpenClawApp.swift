import SwiftUI

@main
struct OpenClawApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var gateway = GatewayClient.shared
    @StateObject private var appState = AppState()
    @StateObject private var notifications = NotificationService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(gateway)
                .environmentObject(appState)
                .environmentObject(notifications)
                .preferredColorScheme(.dark)
                .onAppear {
                    notifications.configure()
                }
        }
    }
}
