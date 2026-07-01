#!/usr/bin/env bash
# Informant: on the first Claude Code prompt of a session, surface two things —
# an out-of-date Claude Code integration (drift), and unresolved production
# errors — unless that first prompt is the /informant command. Either channel
# may fire on its own; when both fire, they share one combined message with a
# single pause instruction.
# Requires: jq (and curl, for the production check)
# Env vars: INFORMANT_PRODUCTION_URL, INFORMANT_PRODUCTION_TOKEN
#           INFORMANT_PRODUCTION_PATH_PREFIX (optional, default: /informant)

set -euo pipefail

# Silent exit if jq is not installed (needed to parse the hook payload).
command -v jq >/dev/null 2>&1 || exit 0

# UserPromptSubmit delivers a JSON payload on stdin carrying session_id and prompt.
payload=$(cat)
session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || true)
prompt=$(printf '%s' "$payload" | jq -r '.prompt // empty' 2>/dev/null || true)

# Require a token-shaped session_id (it is interpolated into the marker path below).
[[ "$session_id" =~ ^[A-Za-z0-9_-]+$ ]] || exit 0

# Is the committed Claude Code integration out of date? The Ruby channels (dev
# boot warning, informant:doctor) write this flag under Rails.root/tmp. This hook
# reads it relative to the session's working directory, assuming that cwd is the
# Rails app root. In a monorepo where the Rails root is a subdirectory of the
# session cwd, this channel stays silent — the boot warning and informant:doctor
# still cover that case.
drift=0
[[ -e "tmp/rails-informant-drift" ]] && drift=1

# Can we check production errors? Needs both env vars and an HTTPS URL.
production=1
[[ -z "${INFORMANT_PRODUCTION_URL:-}" ]] && production=0
[[ -z "${INFORMANT_PRODUCTION_TOKEN:-}" ]] && production=0
[[ "${INFORMANT_PRODUCTION_URL:-}" == https://* ]] || production=0

# Nothing either channel could say → exit without claiming the session, so a
# later prompt (e.g. once env vars are set) still gets its chance. This also
# keeps a drift-free, production-unconfigured app a true silent no-op.
[[ "$drift" -eq 0 && "$production" -eq 0 ]] && exit 0

# Run at most once per session, on the first prompt: a marker keyed by session_id
# records that this session was handled, so later prompts short-circuit here.
# Stay silent when we can't record the marker, rather than re-firing every prompt.
marker="${TMPDIR:-/tmp}/rails-informant-alert-${session_id}"
[[ -e "$marker" ]] && exit 0
: > "$marker" 2>/dev/null || exit 0

# Stay quiet for the whole session when the first prompt is the /informant command —
# the user is already triaging, so these startup nudges would be redundant.
[[ "$prompt" =~ ^/informant($|[[:space:]]) ]] && exit 0

# Assemble the data blocks first (the instruction comes last, on purpose).
body=""

if [[ "$drift" -eq 1 ]]; then
  body+="🧭 Informant: this app's Claude Code integration is out of date.
The installed rails-informant gem would now generate different .claude/ files than the ones committed here.
Update it by running: bin/rails g rails_informant:skill
"
fi

errors=0
if [[ "$production" -eq 1 ]]; then
  path_prefix="${INFORMANT_PRODUCTION_PATH_PREFIX:-/informant}"
  url="${INFORMANT_PRODUCTION_URL}${path_prefix}/api/v1/status"

  # Fetch status. A failure here must not suppress a pending drift nudge, so
  # swallow the error into an empty response rather than exiting.
  response=$(curl -s -f \
    --connect-timeout 3 \
    --max-time 5 \
    -H @- \
    "$url" <<< "Authorization: Bearer ${INFORMANT_PRODUCTION_TOKEN}" \
    2>/dev/null) || response=""

  if [[ -n "$response" ]]; then
    unresolved=$(printf '%s' "$response" | jq -r '.unresolved_count // 0' 2>/dev/null || echo 0)
    if [[ "$unresolved" =~ ^[0-9]+$ && "$unresolved" -gt 0 ]]; then
      label="error"
      [[ "$unresolved" -gt 1 ]] && label="errors"
      [[ -n "$body" ]] && body+="
"
      body+="🚨 Informant: ${unresolved} unresolved ${label} in production
$(printf '%s' "$response" | jq -r '.top_errors[]? | "  - \(.error_class) (\(.total_occurrences) \(if .total_occurrences == 1 then "occurrence" else "occurrences" end))"' 2>/dev/null || true)
"
      errors=1
    fi
  fi
fi

# Nothing to report (e.g. drift flag absent and zero unresolved errors).
[[ -z "$body" ]] && exit 0

# One conversational instruction, last — with a specific behavior, a concrete
# question, and a single explicit pause (see the prompt-engineering notes).
if [[ "$drift" -eq 1 && "$errors" -eq 1 ]]; then
  instruction="START your response by casually mentioning both the out-of-date integration (show the one-command fix) and these production errors, then ask the user how they want to proceed — update, investigate, or continue. Do NOT proceed with their request until they answer."
elif [[ "$drift" -eq 1 ]]; then
  instruction="START your response by casually mentioning that the integration is out of date and showing the one-command fix, then ask the user whether to update it now or continue with their request. Do NOT proceed with their request until they answer."
else
  instruction="START your response by casually mentioning these errors, then ask the user if they want to investigate or continue with their request. Do NOT proceed with the user's request until they answer."
fi

printf '%s\n%s\n' "$body" "$instruction"
