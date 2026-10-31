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
# Antigravity Hook 要求 stdout 只输出纯 JSON（{"decision": "stop"}），保留 fd 3 输出 JSON，日志写入文件。
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

input_json="$(cat)"

# Antigravity Stop event fields / Stop 事件字段: terminationReason, workspacePaths, lastUserInput, error
reason="$(echo "$input_json" | jq -r '.terminationReason // "UNKNOWN"')"

if [[ "$reason" == "USER_CANCELED" ]]; then
    echo '{"decision": "stop"}' >&3
    exit 0
fi

workspace="$(echo "$input_json" | jq -r '.workspacePaths[0] // empty')"
project_name="${workspace:+$(basename "$workspace")}"
user_input="$(echo "$input_json" | jq -r '.lastUserInput // "-"')"
error_msg="$(echo "$input_json" | jq -r '.error // empty')"

if [[ "$reason" == "ERROR" || -n "$error_msg" ]]; then
    title="${project_name:+[$project_name] }Task Error"
    message="Status: ${reason}"$'\n'"Prompt: ${user_input}"${error_msg:+$'\n'"Error: ${error_msg}"}
else
    title="${project_name:+[$project_name] }Task Completed"
    message="Prompt: ${user_input}"
fi

log "INFO" "Sending Antigravity notification: title=${title}"
send_gotify || true

echo '{"decision": "stop"}' >&3
