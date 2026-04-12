#!/bin/sh
# rclone/generate-config.sh – Generate rclone.conf from environment variables.
#
# This script is executed by the rclone-config init container at every startup.
# It writes /config/rclone/rclone.conf so that the rclone-sync container can
# mount the same named volume and find a ready-made configuration.
#
# Required environment variables (set in .env):
#   RCLONE_REMOTE          – remote name used in the config block (default: gdrive)
#   RCLONE_TYPE            – backend type (default: drive)
#   RCLONE_SCOPE           – OAuth scope (default: drive)
#
# Option A – OAuth (personal Google account):
#   RCLONE_TOKEN           – token JSON from "rclone config" (required)
#   RCLONE_CLIENT_ID       – OAuth client ID   (optional, leave empty for rclone defaults)
#   RCLONE_CLIENT_SECRET   – OAuth client secret (optional, leave empty for rclone defaults)
#
# Option B – Service Account (Google Workspace / automated):
#   RCLONE_SERVICE_ACCOUNT_FILE – path inside the container to the JSON key file
#                                  (when set, Option A variables are ignored)

set -e

CONFIG_DIR="/config/rclone"
CONFIG_FILE="${CONFIG_DIR}/rclone.conf"
REMOTE="${RCLONE_REMOTE:-gdrive}"
TYPE="${RCLONE_TYPE:-drive}"
SCOPE="${RCLONE_SCOPE:-drive}"

mkdir -p "${CONFIG_DIR}"

if [ -n "${RCLONE_SERVICE_ACCOUNT_FILE:-}" ]; then
    # ── Option B – Service Account ────────────────────────────────────────────
    echo "Generating rclone.conf (service account mode) ..."
    cat > "${CONFIG_FILE}" <<EOF
[${REMOTE}]
type = ${TYPE}
scope = ${SCOPE}
service_account_file = ${RCLONE_SERVICE_ACCOUNT_FILE}
EOF
else
    # ── Option A – OAuth ──────────────────────────────────────────────────────
    if [ -z "${RCLONE_TOKEN:-}" ]; then
        echo "ERROR: RCLONE_TOKEN is not set. Add it to your .env file." >&2
        exit 1
    fi
    echo "Generating rclone.conf (OAuth mode) ..."
    cat > "${CONFIG_FILE}" <<EOF
[${REMOTE}]
type = ${TYPE}
client_id = ${RCLONE_CLIENT_ID:-}
client_secret = ${RCLONE_CLIENT_SECRET:-}
scope = ${SCOPE}
token = ${RCLONE_TOKEN}
EOF
fi

echo "rclone.conf written to ${CONFIG_FILE}"
