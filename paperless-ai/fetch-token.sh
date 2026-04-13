#!/bin/sh
# paperless-ai/fetch-token.sh – Entrypoint wrapper for the paperless-ai container.
#
# If PAPERLESS_API_TOKEN is empty (or set to "auto") and admin credentials are
# available, this script waits for Paperless-ngx to become reachable, obtains
# an API token via the /api/token/ endpoint, and exports it so the paperless-ai
# application can use it.
#
# Required environment variables (for automatic token fetching):
#   PAPERLESS_API_URL        – e.g. http://paperless:8000/api
#   PAPERLESS_ADMIN_USER     – Paperless-ngx admin username
#   PAPERLESS_ADMIN_PASSWORD – Paperless-ngx admin password
#
# If PAPERLESS_API_TOKEN is already set to a real token value, the script
# skips the fetch and starts the application immediately.

set -e

# ── Helper: strip trailing /api or /api/ from the URL to get the base URL ─────
paperless_base_url() {
    echo "${PAPERLESS_API_URL}" | sed 's|/api/*$||'
}

# ── Token auto-fetch ──────────────────────────────────────────────────────────
if [ -z "${PAPERLESS_API_TOKEN}" ] || [ "${PAPERLESS_API_TOKEN}" = "auto" ]; then
    if [ -n "${PAPERLESS_ADMIN_USER}" ] && [ -n "${PAPERLESS_ADMIN_PASSWORD}" ]; then
        BASE_URL=$(paperless_base_url)
        TOKEN_URL="${BASE_URL}/api/token/"

        echo "[fetch-token] Waiting for Paperless-ngx at ${BASE_URL} ..."

        # Wait up to ~180 s for Paperless-ngx to respond (90 × 2 s).
        attempts=0
        max_attempts=90
        while [ "$attempts" -lt "$max_attempts" ]; do
            # A simple GET to /api/ should return 200 once Django is up.
            if wget -qO /dev/null --timeout=3 "${BASE_URL}/api/" 2>/dev/null; then
                break
            fi
            attempts=$((attempts + 1))
            echo "[fetch-token] Paperless-ngx not ready yet (attempt ${attempts}/${max_attempts}), retrying in 2 s ..."
            sleep 2
        done

        if [ "$attempts" -ge "$max_attempts" ]; then
            echo "[fetch-token] ERROR: Paperless-ngx did not become available within the timeout." >&2
            echo "[fetch-token] Continuing without an API token – paperless-ai may fail to connect." >&2
        else
            echo "[fetch-token] Paperless-ngx is up. Requesting API token ..."

            RESPONSE=$(wget -qO- --timeout=10 \
                --header="Content-Type: application/json" \
                --post-data="{\"username\":\"${PAPERLESS_ADMIN_USER}\",\"password\":\"${PAPERLESS_ADMIN_PASSWORD}\"}" \
                "${TOKEN_URL}" 2>&1) || true

            # Extract the token value from the JSON response {"token":"<value>"}
            TOKEN=$(echo "${RESPONSE}" | sed -n 's/.*"token" *: *"\([^"]*\)".*/\1/p')

            if [ -n "${TOKEN}" ]; then
                export PAPERLESS_API_TOKEN="${TOKEN}"
                echo "[fetch-token] Successfully obtained API token."
            else
                echo "[fetch-token] WARNING: Could not obtain an API token." >&2
                echo "[fetch-token] Response: ${RESPONSE}" >&2
                echo "[fetch-token] Make sure PAPERLESS_ADMIN_USER and PAPERLESS_ADMIN_PASSWORD are correct." >&2
            fi
        fi
    else
        echo "[fetch-token] PAPERLESS_API_TOKEN is not set and no admin credentials provided." >&2
        echo "[fetch-token] Set PAPERLESS_ADMIN_USER + PAPERLESS_ADMIN_PASSWORD in .env to auto-fetch a token," >&2
        echo "[fetch-token] or set PAPERLESS_API_TOKEN directly." >&2
    fi
fi

# ── Start the application ────────────────────────────────────────────────────
# If arguments were passed (from CMD), run them; otherwise fall back to npm start.
if [ $# -gt 0 ]; then
    exec "$@"
else
    exec npm start
fi
