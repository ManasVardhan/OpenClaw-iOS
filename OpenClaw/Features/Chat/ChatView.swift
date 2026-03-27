import SwiftUI

struct ChatView: View {
    @EnvironmentObject var gateway: GatewayClient
    @StateObject private var chatService = ChatService(gateway: .shared)
    @StateObject private var approvalService = ExecApprovalService(gateway: .shared)
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Exec approval banner
                ExecApprovalBanner(service: approvalService)
                    .animation(.spring(duration: 0.3), value: approvalService.pendingApprovals.count)

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(chatService.messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }

                            // Streaming indicator
                            if chatService.isAgentTyping {
                                StreamingBubble(text: chatService.currentStreamText)
                                    .id("streaming")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: chatService.messages.count) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            if let lastId = chatService.messages.last?.id {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: chatService.isAgentTyping) {
                        if chatService.isAgentTyping {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("streaming", anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Input bar
                HStack(spacing: 12) {
                    TextField("Message...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...6)
                        .focused($isInputFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .onSubmit { sendMessage() }

                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(canSend ? Color.orange : Color.gray)
                    }
                    .disabled(!canSend)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ConnectionStatusDot(state: gateway.connectionState)
                }
            }
            .task {
                await chatService.loadHistory()
            }
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !chatService.isAgentTyping
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        Haptics.impact(.light)

        Task {
            try? await chatService.send(text)
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Group {
                    if message.role == .assistant && message.content.contains("```") {
                        RichMarkdownView(content: message.content)
                    } else if message.role == .assistant {
                        MarkdownText(content: message.content)
                            .font(.body)
                    } else {
                        Text(message.content)
                            .font(.body)
                    }
                }
                .foregroundStyle(message.role == .user ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleColor)
                .clipShape(RoundedRectangle(cornerRadius: 18))

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if message.role != .user { Spacer(minLength: 60) }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.content
                Haptics.notification(.success)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }

    private var bubbleColor: Color {
        switch message.role {
        case .user: .orange
        case .assistant: Color(.systemGray5)
        case .system: Color(.systemGray6)
        }
    }
}

// MARK: - Streaming Bubble

struct StreamingBubble: View {
    let text: String
    @State private var dotCount = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if text.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(Color.orange.opacity(i <= dotCount ? 1 : 0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .onReceive(timer) { _ in
                        dotCount = (dotCount + 1) % 3
                    }
                } else {
                    MarkdownText(content: text)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }
            Spacer(minLength: 60)
        }
    }
}
