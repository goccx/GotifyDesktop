# Gotify 通知脚本使用指南

[English](README.md) | 简体中文

本目录提供 **5 个完全独立的单文件脚本**（互不依赖，用哪个复制哪个）：

| 脚本文件 | 适用场景 |
| :--- | :--- |
| [`gotify-notify.sh`](./gotify-notify.sh) | **通用通知脚本**（用于流量通知、磁盘告警、定时任务等，直接传标题和正文） |
| [`antigravity-notify.sh`](./antigravity-notify.sh) | **Antigravity（反重力）** 专用 Hook 脚本 |
| [`claude-notify.sh`](./claude-notify.sh) | **Claude Code** 专用 Hook 脚本 |
| [`gemini-notify.sh`](./gemini-notify.sh) | **Gemini CLI** 专用 Hook 脚本 |
| [`codex-notify.sh`](./codex-notify.sh) | **OpenAI Codex CLI** 专用 Hook 脚本 |

---

## 前提条件：部署 Gotify 服务端

使用本目录中的推送脚本及 GotifyDesk 客户端前，你需要先拥有一个运行中的 **Gotify 服务端**：

1. **安装服务端**：如果你还没有部署 Gotify，可以通过 Docker 一条命令或二进制文件快速搭建，详见官方安装文档：[https://gotify.net/docs/install](https://gotify.net/docs/install)。
2. **理解两种 Token 的区别**：
   - **Application Token（应用令牌）**：在 Gotify 网页后台 `[Apps]` 中创建，专门用于**发送消息**（填入本目录的脚本中）。
   - **Client Token（客户端令牌）**：在 Gotify 网页后台 `[Clients]` 中创建，专门用于**接收消息**（填入 GotifyDesk 客户端设置中）。

---

## 第一步：修改脚本顶部的 3 行配置

Gotify 和 GotifyDesk 左侧栏通过 **Application Token** 区分消息归属哪个 **Application（应用来源）**。  
你可以根据需要在 Gotify 网页后台 -> **`[Apps]`** -> **`[Create Application]`** 创建对应的应用（如 `流量通知`、`磁盘告警`、`Antigravity`、`Claude Code` 等），然后打开你要用的那个 `.sh` 脚本，修改开头的 3 行：

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

将改好的脚本放到任意固定位置（以下以 `~/.gotify/` 目录为例，**脚本放在哪，后续配置路径就写哪**）并赋予执行权限：

```bash
mkdir -p ~/.gotify
cp *.sh ~/.gotify/
chmod +x ~/.gotify/*.sh

# 查看你的脚本完整绝对路径（用于下方 Hook 配置）
realpath ~/.gotify/
```

---

## 第二步：各场景使用方法

### 1. 通用场景（流量通知 / 磁盘告警 / 定时任务）
直接使用 [`gotify-notify.sh`](./gotify-notify.sh)，传入 `<标题>` 和 `<消息正文>`：

```bash
~/.gotify/gotify-notify.sh "流量日报" "今日已使用流量 128 GB"
~/.gotify/gotify-notify.sh "磁盘告警" "根目录 / 使用率已达 92%"
```

---

### 2. AI 工具完成通知（需先执行 `brew install jq`）

将下方配置中的 `/Users/你的用户名/.gotify/xxx-notify.sh` 替换为你本机的实际绝对路径。

#### A. Antigravity（反重力）
> **说明**：不同于 Claude Code / Gemini CLI 拥有专门的 `Notification` 审批事件，Antigravity 目前无法从 Hook 传递的 `stdin` 信息中优雅判断某次工具调用是否触发了客户端内部审批。因此本脚本采用**“高危命令拦截触发审批通知 + 外部权限配置默认放行”**方案：建议在 Antigravity 设置中将日常权限设为默认放行（如 Turbo / Auto），由 `PreToolUse` 钩子专门拦截高危命令（返回 `ask` 强制弹窗并推送 Gotify 通知）及交互提问（`ask_question`），其余常规命令直接放行，配合 `Stop` 钩子推送任务完成通知。

打开 `~/.gemini/config/hooks.json`（支持 `Stop` 任务完成通知与 `PreToolUse` 高危命令拦截/提问提醒）：
```json
{
  "gotify-notify": {
    "enabled": true,
    "PreToolUse": [
      {
        "matcher": "run_command|ask_question|ask_permission|ask_custom_permission",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/你的用户名/.gotify/antigravity-notify.sh",
            "timeout": 15
          }
        ]
      }
    ],
    "Stop": [
      {
        "type": "command",
        "command": "/Users/你的用户名/.gotify/antigravity-notify.sh",
        "timeout": 15
      }
    ]
  }
}
```

#### B. Claude Code
打开 `~/.claude/settings.json`（支持 `Stop` 任务完成通知与 `Notification` 权限审批提醒）：
```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "permission_prompt|elicitation_dialog",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/你的用户名/.gotify/claude-notify.sh"
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
            "command": "/Users/你的用户名/.gotify/claude-notify.sh"
          }
        ]
      }
    ]
  }
}
```

#### C. Gemini CLI
打开 `~/.gemini/settings.json`（支持 `AfterAgent` 任务完成通知与 `Notification` 权限审批提醒）：
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
            "command": "/Users/你的用户名/.gotify/gemini-notify.sh"
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
            "command": "/Users/你的用户名/.gotify/gemini-notify.sh"
          }
        ]
      }
    ]
  }
}
```

#### D. OpenAI Codex CLI
打开 `~/.codex/config.toml`，在文件最顶部添加：
```toml
notify = ["/Users/你的用户名/.gotify/codex-notify.sh"]
```
