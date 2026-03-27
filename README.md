<p align="center">
  <img src="assets/banner.png" alt="OpenClaw iOS" width="100%">
</p>

# OpenClaw iOS

Native iOS client for [OpenClaw](https://github.com/openclaw/openclaw) -- talk to your AI agent from anywhere.

## Features

- **Chat** -- Full conversational UI with streaming responses, markdown rendering, and code blocks
- **Sessions** -- Browse and manage active agent sessions
- **Cron Jobs** -- View, toggle, and trigger scheduled jobs
- **Nodes** -- See paired devices and their capabilities
- **Settings** -- Connection management, server info, quick links

## Architecture

```
iPhone App (operator role)
    |
    v  WebSocket (JSON, protocol v3)
OpenClaw Gateway (your Mac, VPS, Pi)
    |
    v
Your AI agent
```

The app connects to your OpenClaw Gateway over WebSocket using the native gateway protocol. It authenticates as an `operator` client with read/write scopes.

## Requirements

- iOS 17.0+
- Xcode 16+
- An OpenClaw Gateway running somewhere reachable from your phone

## Setup

1. Open `OpenClaw.xcodeproj` in Xcode
2. Set your development team in Signing & Capabilities
3. Build and run on your device or simulator
4. Enter your gateway host, port, and auth token
5. Chat away

## Project Structure

```
OpenClaw/
  App/              -- App entry point, root navigation, state
  Core/
    Auth/           -- Connection config and keychain storage
    Networking/     -- GatewayClient (WebSocket), ChatService
    Protocol/       -- Gateway protocol types, AnyCodable
    Storage/        -- Keychain helper
  Features/
    Chat/           -- Chat UI, connect screen
    Sessions/       -- Session list and details
    Cron/           -- Cron job management
    Nodes/          -- Paired device browser
    Settings/       -- Connection info, links
  Shared/
    Components/     -- Reusable UI (status dot, markdown renderer)
    Extensions/     -- Haptics, utilities
    Models/         -- Domain models
  Resources/        -- Assets, Info.plist
```

## Network Requirements

The gateway must be reachable from your phone:
- **Local**: Same Wi-Fi network (ws://192.168.x.x:18789)
- **Tailscale**: Via tailnet hostname (ws://mybox.tail...:18789)
- **Remote**: Public endpoint with TLS (wss://gateway.example.com:18789)

Enable `NSAllowsLocalNetworking` in Info.plist for local connections (already configured).

## Built With

- SwiftUI + Swift 6
- URLSessionWebSocketTask (no dependencies)
- XcodeGen for project generation
