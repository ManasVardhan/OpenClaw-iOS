import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var gateway: GatewayClient
    @EnvironmentObject var notifications: NotificationService

    var body: some View {
        ZStack {
            Color.surfaceBase.ignoresSafeArea()
            BlueprintGrid()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel(text: "Configuration")
                        Text("Settings")
                            .font(.headline(28))
                            .foregroundStyle(Color.textPrimary)
                    }
                    .padding(.top, 16)

                    // Notifications
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Notifications")

                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(Color.ocPrimary)
                            Text("Push Notifications")
                                .font(.body(14, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            if notifications.isAuthorized {
                                HStack(spacing: 4) {
                                    StatusLED(color: Color.ocSuccess)
                                    Text("ENABLED")
                                        .font(.label(9, weight: .bold))
                                        .tracking(1)
                                        .foregroundStyle(Color.ocSuccess)
                                }
                            } else {
                                Button {
                                    notifications.requestPermission()
                                } label: {
                                    Text("ENABLE")
                                        .font(.label(10, weight: .bold))
                                        .tracking(1)
                                        .foregroundStyle(Color.ocPrimary)
                                }
                            }
                        }
                        .padding(14)
                        .vanguardCard()
                    }

                    // Connection
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Gateway Connection")

                        VStack(spacing: 0) {
                            if let config = ConnectionStore.load() {
                                SettingsRow(label: "HOST", value: config.displayName)
                                SettingsRow(label: "TLS", value: config.useTLS ? "Enabled" : "Disabled")
                            }
                            SettingsRow(label: "STATUS", value: statusText, valueColor: statusColor)
                            if !gateway.serverVersion.isEmpty {
                                SettingsRow(label: "VERSION", value: gateway.serverVersion)
                            }
                            if !gateway.serverHost.isEmpty {
                                SettingsRow(label: "SERVER", value: gateway.serverHost)
                            }
                        }
                        .vanguardCard()
                    }

                    // Diagnostics
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Diagnostics")

                        NavigationLink {
                            HealthView()
                        } label: {
                            HStack {
                                Image(systemName: "heart.text.square.fill")
                                    .foregroundStyle(Color.ocPrimary)
                                Text("Health & Channels")
                                    .font(.body(14, weight: .medium))
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(Color.textTertiary)
                            }
                            .padding(14)
                            .vanguardCard()
                        }
                    }

                    // Disconnect
                    Button(role: .destructive) {
                        gateway.disconnect()
                        ConnectionStore.clear()
                    } label: {
                        HStack {
                            Image(systemName: "wifi.slash")
                            Text("DISCONNECT")
                                .font(.label(12, weight: .bold))
                                .tracking(1.5)
                        }
                        .foregroundStyle(Color.ocError)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.ocError.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(Color.ocError.opacity(0.2), lineWidth: 1)
                        )
                    }

                    // About
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "About")

                        VStack(spacing: 0) {
                            SettingsRow(label: "APP", value: "OpenClaw iOS v0.2.0")
                            SettingsRow(label: "DOCS", value: "docs.openclaw.ai", isLink: true)
                            SettingsRow(label: "SOURCE", value: "github.com/openclaw", isLink: true)
                        }
                        .vanguardCard()
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationTitle("")
    }

    private var statusText: String {
        switch gateway.connectionState {
        case .connected: "Connected"
        case .connecting: "Connecting..."
        case .disconnected: "Disconnected"
        case .error(let msg): msg
        }
    }

    private var statusColor: Color {
        switch gateway.connectionState {
        case .connected: Color.ocSuccess
        case .connecting: Color.ocTertiary
        default: Color.ocError
        }
    }
}

struct SettingsRow: View {
    let label: String
    let value: String
    var valueColor: Color = .textSecondary
    var isLink: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.label(10, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Color.textTertiary)
            Spacer()
            Text(value)
                .font(.body(13))
                .foregroundStyle(isLink ? Color.ocPrimary : valueColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
