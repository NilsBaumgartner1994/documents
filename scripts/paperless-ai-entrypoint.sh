#!/bin/bash
# ── paperless-ai-entrypoint.sh ───────────────────────────────────────────────
# Wrapper entrypoint for the paperless-ai container.
#
# If PAPERLESS_API_TOKEN is already set, this script simply starts the
# original paperless-ai command.
#
# Otherwise, if PAPERLESS_ADMIN_USER and PAPERLESS_ADMIN_PASSWORD are
# provided, it waits for the Paperless-ngx API to become available, then
# authenticates with those credentials to obtain an API token automatically.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

readonly LOG_PREFIX="[paperless-ai-entrypoint]"

# ── Helper: derive base URL from PAPERLESS_API_URL ────────────────────────
# PAPERLESS_API_URL is typically "http://paperless:8000/api" – we need the
# base "http://paperless:8000" to call /api/token/.
paperless_base_url() {
  # Strip trailing slash, then strip the last path component ("/api")
  local url="${PAPERLESS_API_URL%/}"
  echo "${url%/api}"
}

# ── Fetch token from Paperless-ngx API ────────────────────────────────────
fetch_token() {
  local base_url
  base_url="$(paperless_base_url)"
  local token_url="${base_url}/api/token/"

  echo "${LOG_PREFIX} Waiting for Paperless-ngx API at ${base_url} ..."

  # The docker-compose healthcheck ensures Paperless is healthy before this
  # container starts.  A short retry loop handles residual race conditions.
  local attempts=0
  local max_attempts=12
  until curl -sf --max-time 5 "${base_url}/api/" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "${attempts}" -ge "${max_attempts}" ]; then
      echo "${LOG_PREFIX} ERROR: Paperless-ngx API not reachable after ${max_attempts} attempts. Giving up." >&2
      return 1
    fi
    echo "${LOG_PREFIX} Paperless-ngx not ready yet (attempt ${attempts}/${max_attempts}). Retrying in 5 s ..."
    sleep 5
  done

  echo "${LOG_PREFIX} Paperless-ngx API is ready. Requesting token for user '${PAPERLESS_ADMIN_USER}' ..."

  local response
  response=$(curl -sf --max-time 10 -X POST "${token_url}" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"${PAPERLESS_ADMIN_USER}\",\"password\":\"${PAPERLESS_ADMIN_PASSWORD}\"}" 2>&1) || {
    echo "${LOG_PREFIX} ERROR: Failed to obtain token from ${token_url}." >&2
    echo "${LOG_PREFIX} Response: ${response}" >&2
    return 1
  }

  # Extract the token value.  We use grep+cut instead of jq because the
  # paperless-ai base image (node:22-slim) does not ship jq.  The Paperless-ngx
  # /api/token/ endpoint returns a simple {"token":"<value>"} JSON object.
  local token
  token=$(echo "${response}" | grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4)

  if [ -z "${token}" ]; then
    echo "${LOG_PREFIX} ERROR: Could not parse token from API response." >&2
    echo "${LOG_PREFIX} Response: ${response}" >&2
    return 1
  fi

  echo "${LOG_PREFIX} Token obtained successfully."
  export PAPERLESS_API_TOKEN="${token}"
}

# ── Main ──────────────────────────────────────────────────────────────────
if [ -n "${PAPERLESS_API_TOKEN:-}" ]; then
  echo "${LOG_PREFIX} PAPERLESS_API_TOKEN already set – skipping auto-fetch."
else
  if [ -n "${PAPERLESS_ADMIN_USER:-}" ] && [ -n "${PAPERLESS_ADMIN_PASSWORD:-}" ]; then
    fetch_token
  else
    echo "${LOG_PREFIX} WARNING: Neither PAPERLESS_API_TOKEN nor PAPERLESS_ADMIN_USER/PASSWORD are set." >&2
    echo "${LOG_PREFIX} paperless-ai may fail to connect to Paperless-ngx." >&2
  fi
fi

# Hand off to the original paperless-ai start command
exec ./start-services.sh
