# Gotify Notification Scripts Guide

English | [简体中文](README.zh-CN.md)

This directory provides **5 standalone, single-file scripts** (each script is completely independent—copy only the one you need):

| Script | Use Case |
| :--- | :--- |
| [`gotify-notify.sh`](./gotify-notify.sh) | **General-purpose notification script** (traffic reports, disk alerts, cron jobs; pass title and message directly) |
| [`antigravity-notify.sh`](./antigravity-notify.sh) | **Antigravity** dedicated lifecycle hook script |
| [`claude-notify.sh`](./claude-notify.sh) | **Claude Code** dedicated lifecycle hook script |
| [`gemini-notify.sh`](./gemini-notify.sh) | **Gemini CLI** dedicated lifecycle hook script |
| [`codex-notify.sh`](./codex-notify.sh) | **OpenAI Codex CLI** dedicated notification hook script |

---

## Prerequisites: Deploy a Gotify Server

Before using these scripts and GotifyDesk, you need a running **Gotify server**:

1. **Install Gotify Server**: If you haven't deployed Gotify yet, you can quickly spin one up via Docker or a prebuilt binary. Follow the official installation guide: [https://gotify.net/docs/install](https://gotify.net/docs/install).
2. **Understand the Two Token Types**:
   - **Application Token**: Created under `[Apps]` in the Gotify Web UI, used for **sending messages** (configure this in the scripts below).
   - **Client Token**: Created under `[Clients]` in the Gotify Web UI, used for **receiving messages** (configure this in the GotifyDesk app settings).

---

## Step 1: Configure the 3 Lines at the Top of the Script

Gotify and the GotifyDesk sidebar distinguish message sources (**Applications**) by their **Application Token**.  
In your Gotify Web UI -> **`[Apps]`** -> **`[Create Application]`**, create the corresponding application (e.g., `Traffic Alert`, `Disk Monitor`, `Antigravity`, `Claude Code`), then open the `.sh` script you want to use and edit the 3 lines at the top:

```bash
# ==================== Gotify Configuration / Gotify 配置 ====================
# 1. Server URL (do not append /message) / 服务端地址（末尾不要加 /message）
GOTIFY_URL="${GOTIFY_URL:-https://gotify.example.com}"

# 2. Application Token (Gotify Web UI -> [Apps] -> [Create Application]; do NOT use a Client Token)
#    应用令牌（Gotify 网页后台 -> [Apps] -> [Create Application] 生成的 Token，不能用 Clients 的 Token）
GOTIFY_TOKEN="${GOTIFY_TOKEN:-YOUR_APPLICATION_TOKEN}"

# 3. Message Priority (integer 0-10, default 5) / 消息优先级（0~10 的整数，默认 5）
GOTIFY_PRIORITY="${GOTIFY_PRIORITY:-5}"
# ============================================================================
```

Place the script in any permanent location (e.g., `~/.gotify/`—**wherever you place the script, use that exact absolute path in the hook configuration below**) and make it executable:

```bash
mkdir -p ~/.gotify
cp *.sh ~/.gotify/
chmod +x ~/.gotify/*.sh

# Print the full path to use in your hook configs below
realpath ~/.gotify/
```

---

## Step 2: Usage by Scenario

### 1. General Scenarios (Traffic Alerts / Disk Monitoring / Cron Jobs)
Call [`gotify-notify.sh`](./gotify-notify.sh) directly with `<title>` and `<message>`:

```bash
~/.gotify/gotify-notify.sh "Daily Traffic" "Outbound traffic today: 128 GB"
~/.gotify/gotify-notify.sh "Disk Alert" "Root partition / usage reached 92%"
```

---

### 2. AI Coding Tool Completion Hooks (Requires `jq`: `brew install jq`)

Replace `/Users/your-username/.gotify/xxx-notify.sh` below with the actual absolute path on your machine.

#### A. Antigravity
Edit `~/.gemini/config/hooks.json` (supports both `Stop` completion notifications and `PreToolUse` approval alerts):
```json
{
  "gotify-notify": {
    "enabled": true,
    "PreToolUse": [
      {
        "matcher": "run_command|read_file|write_file|edit_file|ask_question",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/your-username/.gotify/antigravity-notify.sh",
            "timeout": 15
          }
        ]
      }
    ],
    "Stop": [
      {
        "type": "command",
        "command": "/Users/your-username/.gotify/antigravity-notify.sh",
        "timeout": 15
      }
    ]
  }
}
```

#### B. Claude Code
Edit `~/.claude/settings.json` (supports both `Stop` completion notifications and `Notification` approval alerts):
```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "permission_prompt|idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/your-username/.gotify/claude-notify.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/your-username/.gotify/claude-notify.sh"
          }
        ]
      }
    ]
  }
}
```

#### C. Gemini CLI
Edit `~/.gemini/settings.json` (supports both `AfterAgent` completion notifications and `Notification` approval alerts):
```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "ToolPermission",
        "hooks": [
          {
            "name": "gotify-approval",
            "type": "command",
            "command": "/Users/your-username/.gotify/gemini-notify.sh"
          }
        ]
      }
    ],
    "AfterAgent": [
      {
        "matcher": "*",
        "hooks": [
          {
            "name": "gotify-notify",
            "type": "command",
            "command": "/Users/your-username/.gotify/gemini-notify.sh"
          }
        ]
      }
    ]
  }
}
```

#### D. OpenAI Codex CLI
Edit `~/.codex/config.toml` and add at the very top of the file:
```toml
notify = ["/Users/your-username/.gotify/codex-notify.sh"]
```
