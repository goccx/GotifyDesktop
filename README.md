# GotifyDesktop

[![Release](https://img.shields.io/github/v/release/goccx/GotifyDesktop?label=Release)](https://github.com/goccx/GotifyDesktop/releases/latest)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014%2B%20(Apple%20Silicon%20%26%20Intel)-blue)](https://github.com/goccx/GotifyDesktop/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

English | [简体中文](README.zh-CN.md)

A lightweight native macOS desktop and menu bar client for [Gotify](https://gotify.net/). Browse messages by application, receive real-time updates over WebSocket, and get native macOS notification banners with custom alert sounds.

GotifyDesktop focuses on lightweight, real-time notification reading: messages belong to your Gotify server and are held only in process memory while the app is running. There is no local message database, and closing the main window keeps the app resident in the macOS menu bar to continue receiving notifications in the background.

## Download & Install

### Supported Platforms & Downloads

Requires **macOS 14.0 (Sonoma)** or later. Choose the installer matching your Mac processor:

| Architecture | Devices | Download |
| :--- | :--- | :--- |
| **Apple Silicon (`arm64`)** | Mac with M1 / M2 / M3 / M4 series chip | 📦 [**GotifyDesktop-macOS-arm64.dmg**](https://github.com/goccx/GotifyDesktop/releases/latest/download/GotifyDesktop-macOS-arm64.dmg) |
| **Intel (`amd64`)** | Mac with Intel `x86_64` processor | 📦 [**GotifyDesktop-macOS-amd64.dmg**](https://github.com/goccx/GotifyDesktop/releases/latest/download/GotifyDesktop-macOS-amd64.dmg) |

🔗 [View All Releases & Changelog (GitHub Releases)](https://github.com/goccx/GotifyDesktop/releases)

### First Launch

After dragging `GotifyDesktop.app` into `Applications`, if macOS shows **"Apple could not verify GotifyDesktop is free of malware"**, allow it via either method:

- **Terminal**: `xattr -rd com.apple.quarantine /Applications/GotifyDesktop.app`
- **System Settings**: Click **Done** on the prompt → **System Settings → Privacy & Security** → click **Open Anyway** at the bottom.

## Features

- **Two-column layout**: Navigate by Gotify Application in the left sidebar and read message lists or details in the right canvas.
- **Live & history sync**: A single WebSocket connection receives live messages in real time, while REST history paginates automatically on demand.
- **Message deletion**: Delete individual messages, clear all messages for a specific application, or delete all messages on the server.
- **Session-only attention state**: In-memory new-message indicators, per-application counts, and a centered top new-message prompt bar.
- **Native macOS integration**: Menu bar extra, native notification banners, and the optional Gotify notification sound.
- **Appearance & localization**: System, Dark, and White themes, plus instant in-app switching between English and Simplified Chinese.

## Prerequisites: Deploy a Gotify Server

Before using GotifyDesktop, you need a running Gotify server. If you do not have one yet, you can quickly deploy it using Docker or a prebuilt binary—see the [official Gotify installation guide](https://gotify.net/docs/install).

- **Client Token**: Created under `[Clients]` in the Gotify Web UI; enter this in **GotifyDesktop Settings** to receive messages.
- **Application Token**: Created under `[Apps]` in the Gotify Web UI; used by scripts or services to push messages to your server.

## Build from Source

Requirements: macOS 14 or later, Swift 6.1 or later, and Apple's Xcode Command Line Tools.

```sh
make build    # Build and assemble debug GotifyDesktop.app
make run      # Build and launch debug GotifyDesktop.app
make test     # Run unit tests
make release  # Package arm64 and amd64 release .dmg installers in .build/dist/
```

## Connect to a Server

1. Click the gear icon in the main window toolbar to open **Settings**.
2. Enter your Gotify **Server URL** and **Client Token**.
3. Toggle on **Receive messages**. The app verifies the connection before starting the session.

Turn off **Receive messages** before editing the server configuration (disabling it stops the active session and clears in-memory messages without deleting your saved settings).

**HTTPS** is strongly recommended. Plaintext HTTP is also supported after confirming the transport-security warning. Enable **System notifications** in Settings to deliver macOS banners when live messages arrive.

## Notification Scripts

[`AgentNotify/`](AgentNotify/README.md) provides standalone single-file shell scripts for pushing messages to your Gotify server using an **Application Token**:

- [`gotify-notify.sh`](AgentNotify/gotify-notify.sh): General-purpose sender script for traffic reports, disk alerts, cron jobs, and CI tasks.
- [`antigravity-notify.sh`](AgentNotify/antigravity-notify.sh), [`claude-notify.sh`](AgentNotify/claude-notify.sh), [`gemini-notify.sh`](AgentNotify/gemini-notify.sh), [`codex-notify.sh`](AgentNotify/codex-notify.sh): Dedicated lifecycle hook scripts for Antigravity, Claude Code, Gemini CLI, and OpenAI Codex CLI task completion notifications.

See [`AgentNotify/README.md`](AgentNotify/README.md) ([简体中文](AgentNotify/README.zh-CN.md)) for setup instructions.

## Language and Appearance

- **Language**: In **Settings → Interface → Language**, choose **System**, **English**, or **Simplified Chinese** to update the UI and date formatting immediately (server-provided application names and message content remain unchanged). Absolute timestamps use a 24-hour clock in the current macOS time zone.
- **Appearance**: In **Settings → Interface → Appearance**, choose **System**, **Dark**, or **White**.

## Local Data and Privacy

- **In-memory messages only**: Message content, pagination state, and new-message indicators exist only in process memory. Quitting the app clears them, and relaunching fetches fresh history from the server.
- **Configuration storage**: Server URL, appearance, and notification preferences are stored in `UserDefaults`. The `Client Token` is encrypted using Apple `CryptoKit` (AES-GCM) with an application-scoped key so plaintext tokens are not written to preference files.
- **Application icon cache**: `Nuke` caches original application icon files in `~/Library/Caches/com.gotify.desktop/ApplicationIcons` (capped at 50 MiB), which can be revealed in Finder or cleared from Settings. Dragging `.app` to the Trash does not automatically remove `UserDefaults` preferences or this icon cache directory.

## Development

- Main source code lives in `Sources/GotifyDesktop/` and unit tests in `Tests/GotifyDesktopTests/`.
- `OpenAPI/` contains the upstream Swagger specification and generator config, while `Tools/OpenAPIGenerator/Generated/` contains the generated Swift package (do not hand-edit). Java is not required for normal builds because the generated client is committed.
- To regenerate the OpenAPI client (requires Java 17+ and OpenAPI Generator 7.24.0):
  ```sh
  openapi-generator generate \
    --generator-name swift6 \
    --input-spec OpenAPI/gotify-openapi.json \
    --config OpenAPI/config.yaml \
    --output Tools/OpenAPIGenerator/Generated
  ```
- UI localization strings are located in `Sources/GotifyDesktop/SharedUI/Localization/Resources/` (`en.lproj` and `zh-Hans.lproj`).

## License and Third-Party Notices

- **License**: GotifyDesktop is licensed under the [MIT License](LICENSE). Commercial use, modification, and redistribution are permitted subject to preserving the copyright and license notice.
- **Third-Party Notices**: [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) lists third-party attributions and licenses (such as SwiftUIIntrospect and the Gotify alert sound) and is bundled inside the packaged app.

## Disclaimer

1. **Unofficial Client**: GotifyDesktop is an independent third-party open-source client and is not affiliated with, sponsored by, or endorsed by the official [Gotify](https://gotify.net/) project.
2. **Provided "AS IS"**: This software is provided "AS IS" under the MIT License without warranty of any kind, express or implied.
3. **Security Responsibility**: Please keep your Gotify `Client Token` and `Application Token` confidential and prefer HTTPS for your self-hosted server. You are solely responsible for the security of your server configuration and network transport.
