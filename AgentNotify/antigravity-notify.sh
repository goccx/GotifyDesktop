#!/bin/bash
set -euo pipefail

# -e: Exit immediately if a command exits with a non-zero status / 命令失败立即退出
# -u: Treat unset variables as an error / 使用未定义变量时报错
# -o pipefail: Return value of a pipeline is the status of the last failed command / 管道中任一命令失败则整体失败

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# ==================== Gotify Configuration / Gotify 配置 ====================
# 1. Server URL (do not append /message) / 服务端地址（末尾不要加 /message）
GOTIFY_URL="${GOTIFY_URL:-https://gotify.example.com}"

# 2. Application Token (Gotify Web UI -> [Apps] -> [Create Application]; do NOT use a Client Token)
#    应用令牌（Gotify 网页后台 -> [Apps] -> [Create Application] 生成的 Token，不能用 Clients 的 Token）
GOTIFY_TOKEN="${GOTIFY_TOKEN:-YOUR_APPLICATION_TOKEN}"

# 3. Message Priority (integer 0-10, default 5) / 消息优先级（0~10 的整数，默认 5）
GOTIFY_PRIORITY="${GOTIFY_PRIORITY:-5}"

# 4. Retry Configuration (default 3 attempts, 2s interval) / 重试配置（默认最多尝试 3 次，间隔 2 秒）
GOTIFY_MAX_RETRIES="${GOTIFY_MAX_RETRIES:-3}"
GOTIFY_RETRY_DELAY="${GOTIFY_RETRY_DELAY:-2}"
# ============================================================================

shell_folder="$(cd "$(dirname "$0")" && pwd)"
script_name="$(basename "$0" .sh)"
cd "$shell_folder"

log_file="$shell_folder/${script_name}.log"

# Keep fd 3 for the final Hook JSON output; redirect all logs to the log file.
# Antigravity Hook 要求 stdout 只输出纯 JSON，保留 fd 3 输出 JSON，日志写入文件。
exec 3>&1
exec >> "$log_file" 2>&1

log() {
    local level="$1"
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] [pid:$$] $*"
}

send_gotify() {
    local attempt=1
    local err_msg=""
    while (( attempt <= GOTIFY_MAX_RETRIES )); do
        if err_msg="$(curl -fsS --connect-timeout 5 --max-time 10 \
            -X POST "${GOTIFY_URL%/}/message" \
            -H "X-Gotify-Key: ${GOTIFY_TOKEN}" \
            -F "title=${title}" \
            -F "message=${message}" \
            -F "priority=${GOTIFY_PRIORITY}" 2>&1 >/dev/null)"; then
            log "INFO" "Notification sent successfully (attempt ${attempt}/${GOTIFY_MAX_RETRIES})"
            return 0
        fi

        err_msg="${err_msg//$'\n'/ }"
        if (( attempt < GOTIFY_MAX_RETRIES )); then
            log "WARN" "Send failed (attempt ${attempt}/${GOTIFY_MAX_RETRIES}): ${err_msg}. Retrying in ${GOTIFY_RETRY_DELAY}s..."
            sleep "$GOTIFY_RETRY_DELAY"
        else
            log "ERROR" "Send failed after ${GOTIFY_MAX_RETRIES} attempts: ${err_msg}"
        fi
        (( attempt++ ))
    done
    return 1
}

extract_last_reply() {
    local transcript_path="$1"
    if [[ -z "$transcript_path" ]]; then
        return 0
    fi

    local full_transcript="${transcript_path%/transcript.jsonl}/transcript_full.jsonl"
    local target_file="$transcript_path"
    if [[ -f "$full_transcript" ]]; then
        target_file="$full_transcript"
    fi

    if [[ ! -f "$target_file" ]]; then
        return 0
    fi

    jq -sr '
        [.[] | select(.type == "PLANNER_RESPONSE" and ((.content // "") | length > 0)) | .content]
        | last // empty
    ' "$target_file" 2>/dev/null || true
}

input_json="$(cat)"

workspace="$(echo "$input_json" | jq -r '.workspacePaths[0] // empty')"
project_name="${workspace:+$(basename "$workspace")}"
user_input="$(echo "$input_json" | jq -r '.lastUserInput // empty')"
tool_name="$(echo "$input_json" | jq -r '.toolCall.name // empty')"

# 1. PreToolUse (Approval / Tool Execution Gate) / 工具执行与审批事件
if [[ -n "$tool_name" ]]; then
    # Only notify when the tool call actually requires manual user approval:
    # 1) `run_command` with `BypassSandbox: true` (sandboxed commands auto-run without prompting)
    # 2) File tools (`Path` argument) targeting a path outside `workspacePaths`, `/tmp`, and `~/.gemini/antigravity`
    # 3) `ask_question` (interactive user question)
    requires_approval="$(echo "$input_json" | jq -r --arg home "$HOME" '
        .workspacePaths as $ws
        | if .toolCall.name == "run_command" then
            (if .toolCall.args.BypassSandbox == true then "true" else "false" end)
          elif .toolCall.name == "ask_question" then
            "true"
          elif (.toolCall.args.Path // "") != "" then
            (.toolCall.args.Path) as $p
            | if (
                ($p | startswith("/tmp/")) or ($p == "/tmp") or
                ($p | startswith($home + "/.gemini/antigravity/")) or
                any($ws[]?; $p == . or ($p | startswith(. + "/")))
              ) then "false" else "true" end
          else
            "false"
          end
    ' 2>/dev/null || echo "false")"

    if [[ "$requires_approval" == "true" ]]; then
        tool_detail="$(echo "$input_json" | jq -r '
            .toolCall.args
            | if .CommandLine then "Command: " + .CommandLine
              elif .questions then "Question: " + (.questions[0].question // (tojson))
              elif .Path then "Path: " + .Path
              else (tojson)
              end
        ' 2>/dev/null || true)"

        title="${project_name:+[$project_name] }Approval Required: ${tool_name}"
        message="${tool_detail}"
        if [[ -n "$user_input" ]]; then
            message="${message}"$'\n\n'"---"$'\n'"Prompt: ${user_input}"
        fi

        log "INFO" "Sending Antigravity approval notification: title=${title}"
        send_gotify || true

        if [[ "$tool_name" == "ask_question" ]]; then
            echo '{"decision": "allow"}' >&3
        else
            echo '{"decision": "ask"}' >&3
        fi
    else
        echo '{"decision": "allow"}' >&3
    fi
    exit 0
fi

# 2. Stop (Task Completion / Error) / 任务完成与错误事件
reason="$(echo "$input_json" | jq -r '.terminationReason // "UNKNOWN"')"
fully_idle="$(echo "$input_json" | jq -r 'if .fullyIdle == false then "false" else "true" end')"
error_msg="$(echo "$input_json" | jq -r '.error // empty')"

# Skip notification if canceled by user, or if background tasks/subagents are still running (`fullyIdle == false`).
# 用户取消，或后台仍有命令/子任务在运行（尚未真正完成）时不发送通知。
if [[ "$reason" == "USER_CANCELED" ]]; then
    echo '{"decision": "stop"}' >&3
    exit 0
fi

if [[ "$fully_idle" == "false" && "$reason" != "ERROR" && -z "$error_msg" ]]; then
    log "INFO" "Skipping notification: background tasks still running (fullyIdle=false)"
    echo '{"decision": "stop"}' >&3
    exit 0
fi

transcript_path="$(echo "$input_json" | jq -r '.transcriptPath // empty')"
assistant_reply="$(extract_last_reply "$transcript_path")"

if [[ "$reason" == "ERROR" || -n "$error_msg" ]]; then
    title="${project_name:+[$project_name] }Task Error"
    body="${error_msg:-Status: ${reason}}"
    if [[ -n "$assistant_reply" ]]; then
        body="${assistant_reply}"$'\n\n'"Error: ${body}"
    fi
else
    title="${project_name:+[$project_name] }Task Completed"
    body="${assistant_reply}"
fi

if [[ -n "$body" && -n "$user_input" ]]; then
    message="${body}"$'\n\n'"---"$'\n'"Prompt: ${user_input}"
elif [[ -n "$body" ]]; then
    message="${body}"
else
    message="Prompt: ${user_input:--}"
fi

log "INFO" "Sending Antigravity notification: title=${title}"
send_gotify || true

echo '{"decision": "stop"}' >&3
