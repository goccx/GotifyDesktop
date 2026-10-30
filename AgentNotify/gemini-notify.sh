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
# ============================================================================

shell_folder="$(cd "$(dirname "$0")" && pwd)"
script_name="$(basename "$0" .sh)"
cd "$shell_folder"

log_file="$shell_folder/${script_name}.log"

# Keep fd 3 for clean JSON on stdout; redirect all logs to the log file.
# Gemini CLI Hook 要求 stdout 只输出纯 JSON，保留 fd 3 输出 JSON，日志写入文件。
exec 3>&1
exec >> "$log_file" 2>&1

log() {
    local level="$1"
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*"
}

input_json="$(cat)"

# Gemini CLI AfterAgent event fields / AfterAgent 事件字段: cwd, prompt_response, message
cwd="$(echo "$input_json" | jq -r '.cwd // empty')"
project_name="${cwd:+$(basename "$cwd")}"
title="${project_name:+[$project_name] }Task Completed"
message="$(echo "$input_json" | jq -r '.prompt_response // .message // "Task finished."')"

log "INFO" "Sending Gemini CLI notification: title=${title}"

curl -sS --connect-timeout 5 --max-time 10 \
    -X POST "${GOTIFY_URL%/}/message" \
    -H "X-Gotify-Key: ${GOTIFY_TOKEN}" \
    -F "title=${title}" \
    -F "message=${message}" \
    -F "priority=${GOTIFY_PRIORITY}" >/dev/null || log "ERROR" "Gotify push failed"

log "INFO" "Notification finished"

echo '{}' >&3
