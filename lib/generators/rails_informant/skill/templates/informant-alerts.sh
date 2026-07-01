#!/usr/bin/env bash
# Informant: On the first Claude Code prompt of a session, check for unresolved
# production errors — unless that first prompt is the /informant command.
# Requires: curl, jq
# Env vars: INFORMANT_PRODUCTION_URL, INFORMANT_PRODUCTION_TOKEN
#           INFORMANT_PRODUCTION_PATH_PREFIX (optional, default: /informant)

set -euo pipefail

# Silent exit if env vars are missing or URL is not HTTPS
[[ -z "${INFORMANT_PRODUCTION_URL:-}" ]] && exit 0
[[ -z "${INFORMANT_PRODUCTION_TOKEN:-}" ]] && exit 0
[[ "$INFORMANT_PRODUCTION_URL" == https://* ]] || exit 0

# Silent exit if jq is not installed (needed to parse the hook payload)
command -v jq >/dev/null 2>&1 || exit 0

# UserPromptSubmit delivers a JSON payload on stdin carrying session_id and prompt.
payload=$(cat)
session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || true)
prompt=$(printf '%s' "$payload" | jq -r '.prompt // empty' 2>/dev/null || true)

# Run at most once per session, on the first prompt. A marker keyed by session_id
# records that this session has been handled, so later prompts stay silent.
if [[ -n "$session_id" ]]; then
  marker="${TMPDIR:-/tmp}/rails-informant-alert-${session_id}"
  [[ -e "$marker" ]] && exit 0
  : > "$marker" 2>/dev/null || true
fi

# Stay quiet for the whole session when the first prompt is the /informant command —
# the user is already triaging errors, so the startup alert would be redundant.
[[ "$prompt" =~ ^/informant($|[[:space:]]) ]] && exit 0

path_prefix="${INFORMANT_PRODUCTION_PATH_PREFIX:-/informant}"
url="${INFORMANT_PRODUCTION_URL}${path_prefix}/api/v1/status"

# Fetch status (silent on failure)
response=$(curl -s -f \
  --connect-timeout 3 \
  --max-time 5 \
  -H @- \
  "$url" <<< "Authorization: Bearer ${INFORMANT_PRODUCTION_TOKEN}" \
  2>/dev/null) || exit 0

# Parse unresolved count
unresolved=$(echo "$response" | jq -r '.unresolved_count // 0') || exit 0
[[ "$unresolved" -eq 0 ]] && exit 0

# Format error summary
label="error"
[[ "$unresolved" -gt 1 ]] && label="errors"
cat <<ALERT
🚨 Informant: ${unresolved} unresolved ${label} in production
$(echo "$response" | jq -r '.top_errors[]? | "  - \(.error_class) (\(.total_occurrences) \(if .total_occurrences == 1 then "occurrence" else "occurrences" end))"' 2>/dev/null || true)

START your response by casually mentioning these errors, then ask the user if they want to investigate or continue with their request. Do NOT proceed with the user's request until they answer.
ALERT
