import SwiftUI

struct HealthView: View {
    @EnvironmentObject var gateway: GatewayClient
    @State private var channelStatuses: [[String: Any]] = []
    @State private var isLoading = false

    var body: some View {
        ZStack {
            Color.surfaceBase.ignoresSafeArea()
            BlueprintGrid()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Gateway
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Gateway")

                        VStack(spacing: 0) {
                            SettingsRow(label: "VERSION", value: gateway.serverVersion)
                            SettingsRow(label: "HOST", value: gateway.serverHost)
                            SettingsRow(label: "STATUS", value: "Running", valueColor: Color.ocSuccess)
                        }
                        .vanguardCard()
                    }

                    // Channels
                    if !channelStatuses.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(text: "Channels")

                            VStack(spacing: 8) {
                                ForEach(Array(channelStatuses.enumerated()), id: \.offset) { _, channel in
                                    let name = channel["channel"] as? String ?? "Unknown"
                                    let status = channel["status"] as? String ?? "unknown"
                                    let connected = status == "connected" || status == "ready"

                                    HStack(spacing: 12) {
                                        Image(systemName: channelIcon(name))
                                            .foregroundStyle(connected ? Color.ocSuccess : Color.ocError)
                                            .frame(width: 20)
                                        Text(name.capitalized)
                                            .font(.body(14, weight: .medium))
                                            .foregroundStyle(Color.textPrimary)
                                        Spacer()
                                        HStack(spacing: 4) {
                                            StatusLED(color: connected ? Color.ocSuccess : Color.ocError)
                                            Text(status.uppercased())
                                                .font(.label(9, weight: .bold))
                                                .tracking(1)
                                                .foregroundStyle(connected ? Color.ocSuccess : Color.ocError)
                                        }
                                    }
                                    .padding(14)
                                    .vanguardCard()
                                }
                            }
                        }
                    }

                    // Usage
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Usage")

                        NavigationLink {
                            UsageView()
                        } label: {
                            HStack {
                                Image(systemName: "chart.bar.fill")
                                    .foregroundStyle(Color.ocPrimary)
                                Text("Session Usage")
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

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
        .navigationTitle("Health")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await loadHealth() } } label: {
                    Image(systemName: "arrow.clockwise").foregroundStyle(Color.ocPrimary)
                }
            }
        }
        .task { await loadHealth() }
    }

    private func loadHealth() async {
        isLoading = true
        defer { isLoading = false }
        if let response = try? await gateway.sendRequest(method: "channels.status"),
           response.ok,
           let payload = response.payload?.dict,
           let channels = payload["channels"] as? [[String: Any]] {
            channelStatuses = channels
        }
    }

    private func channelIcon(_ name: String) -> String {
        switch name.lowercased() {
        case "telegram": "paperplane.fill"
        case "whatsapp": "phone.fill"
        case "discord": "gamecontroller.fill"
        case "slack": "number"
        case "signal": "lock.fill"
        default: "bubble.fill"
        }
    }
}

struct UsageView: View {
    @EnvironmentObject var gateway: GatewayClient
    @State private var usageData: [[String: Any]] = []

    var body: some View {
        ZStack {
            Color.surfaceBase.ignoresSafeArea()
            BlueprintGrid()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "Token Usage")
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    if usageData.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 40))
                                .foregroundStyle(Color.textTertiary)
                            Text("NO USAGE DATA")
                                .font(.label(11, weight: .bold))
                                .tracking(2)
                                .foregroundStyle(Color.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(usageData.enumerated()), id: \.offset) { _, session in
                                let key = session["key"] as? String ?? "Unknown"
                                let input = session["inputTokens"] as? Int ?? 0
                                let output = session["outputTokens"] as? Int ?? 0

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(key)
                                        .font(.body(13, weight: .semibold))
                                        .foregroundStyle(Color.textPrimary)
                                        .lineLimit(1)
                                    HStack(spacing: 16) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.right")
                                                .font(.system(size: 9))
                                            Text("\(input)")
                                                .font(.label(11))
                                        }
                                        .foregroundStyle(Color.textTertiary)
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.left")
                                                .font(.system(size: 9))
                                            Text("\(output)")
                                                .font(.label(11))
                                        }
                                        .foregroundStyle(Color.ocPrimary)
                                    }
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .vanguardCard()
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
        .navigationTitle("Usage")
        .task {
            if let response = try? await gateway.sendRequest(method: "sessions.usage", params: ["limit": 20]),
               response.ok,
               let payload = response.payload?.dict,
               let sessions = payload["sessions"] as? [[String: Any]] {
                usageData = sessions
            }
        }
    }
}
