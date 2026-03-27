import SwiftUI

struct ConnectView: View {
    @EnvironmentObject var gateway: GatewayClient
    @StateObject private var discovery = BonjourDiscovery()
    @State private var host = ""
    @State private var port = "18789"
    @State private var token = ""
    @State private var useTLS = false
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Logo
                    VStack(spacing: 12) {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.orange)

                        Text("OpenClaw")
                            .font(.largeTitle.bold())

                        Text("Connect to your gateway")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    // Discovered gateways
                    if !discovery.gateways.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Discovered on Network", systemImage: "wifi")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 24)

                            ForEach(discovery.gateways) { gw in
                                Button {
                                    host = gw.host
                                    port = String(gw.port)
                                    useTLS = gw.useTLS
                                    Haptics.selection()
                                } label: {
                                    HStack {
                                        Image(systemName: "antenna.radiowaves.left.and.right")
                                            .foregroundStyle(.orange)
                                        VStack(alignment: .leading) {
                                            Text(gw.displayName ?? gw.name)
                                                .font(.subheadline.bold())
                                            Text("\(gw.host):\(gw.port)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if host == gw.host && port == String(gw.port) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                    .padding(12)
                                    .background(Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 24)
                            }
                        }
                    } else if discovery.isSearching {
                        HStack {
                            ProgressView()
                            Text("Searching for gateways...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Connection form
                    VStack(spacing: 16) {
                        FormField(title: "Host", placeholder: "192.168.1.10 or mybox.tail...", text: $host)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)

                        FormField(title: "Port", placeholder: "18789", text: $port)
                            .keyboardType(.numberPad)

                        FormField(title: "Token", placeholder: "Gateway auth token", text: $token, isSecure: true)

                        Toggle(isOn: $useTLS) {
                            Label("Use TLS (wss://)", systemImage: "lock.fill")
                                .font(.subheadline)
                        }
                        .tint(.orange)
                    }
                    .padding(.horizontal, 24)

                    // Error message
                    if let errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 24)
                    }

                    // Connect button
                    Button {
                        connect()
                    } label: {
                        HStack {
                            if isConnecting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isConnecting ? "Connecting..." : "Connect")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canConnect ? Color.orange : Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!canConnect || isConnecting)
                    .padding(.horizontal, 24)

                    // QR scan hint
                    Button {
                        // TODO: QR code scanning for gateway config
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                loadSavedConfig()
                discovery.startBrowsing()
                // Auto-connect if config is saved
                if let saved = ConnectionStore.load(), !saved.host.isEmpty, !saved.token.isEmpty {
                    connect()
                }
            }
        }
    }

    private var canConnect: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !port.isEmpty &&
        !token.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func loadSavedConfig() {
        if let saved = ConnectionStore.load() {
            host = saved.host
            port = String(saved.port)
            token = saved.token
            useTLS = saved.useTLS
        }
    }

    private func connect() {
        guard let portNum = Int(port) else {
            errorMessage = "Invalid port number"
            return
        }

        let config = ConnectionConfig(
            host: host.trimmingCharacters(in: .whitespaces),
            port: portNum,
            useTLS: useTLS,
            token: token.trimmingCharacters(in: .whitespaces)
        )

        isConnecting = true
        errorMessage = nil

        Task {
            do {
                try await gateway.connect(config: config)
                isConnecting = false
            } catch {
                isConnecting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Form Field

struct FormField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isSecure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
