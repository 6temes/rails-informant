#!/usr/bin/env bash
# Informant: Check for unresolved production errors on Claude Code startup.
# Requires: curl, jq
# Env vars: INFORMANT_PRODUCTION_URL, INFORMANT_PRODUCTION_TOKEN
#           INFORMANT_PRODUCTION_PATH_PREFIX (optional, default: /informant)

set -euo pipefail

# Silent exit if env vars are missing
[[ -z "${INFORMANT_PRODUCTION_URL:-}" ]] && exit 0
[[ -z "${INFORMANT_PRODUCTION_TOKEN:-}" ]] && exit 0

# Silent exit if jq is not installed
command -v jq >/dev/null 2>&1 || exit 0

path_prefix="${INFORMANT_PRODUCTION_PATH_PREFIX:-/informant}"
url="${INFORMANT_PRODUCTION_URL}${path_prefix}/api/v1/status"

# Fetch status (silent on failure)
response=$(curl -s -f \
  --connect-timeout 3 \
  --max-time 5 \
  -H "Authorization: Bearer ${INFORMANT_PRODUCTION_TOKEN}" \
  "$url" 2>/dev/null) || exit 0

# Parse unresolved count
unresolved=$(echo "$response" | jq -r '.unresolved_count // 0') || exit 0
[[ "$unresolved" -eq 0 ]] && exit 0

# Format error summary
label="error"
[[ "$unresolved" -gt 1 ]] && label="errors"
count=$(printf "%'d" "$unresolved" 2>/dev/null || echo "$unresolved")

echo "🚨 Informant: ${count} unresolved ${label} in production"

echo "$response" | jq -r '
  .top_errors[]? |
  "  - \(.error_class) (\(.total_occurrences) \(if .total_occurrences == 1 then "occurrence" else "occurrences" end))"
' 2>/dev/null || true
