#!/bin/sh
# rclone/generate-config.sh – Generate rclone.conf from environment variables.
#
# This script is executed by the rclone-config init container at every startup.
# It writes /config/rclone/rclone.conf so that the rclone-sync container can
# mount the same named volume and find a ready-made configuration.
#
# Required environment variables (set in .env):
#   RCLONE_TOKEN           – token JSON from "rclone config" (required)
#   RCLONE_REMOTE          – remote name used in the config block (default: gdrive)
#   RCLONE_TYPE            – backend type (default: drive)
#   RCLONE_SCOPE           – OAuth scope (default: drive)

set -e

CONFIG_DIR="/config/rclone"
CONFIG_FILE="${CONFIG_DIR}/rclone.conf"
REMOTE="${RCLONE_REMOTE:-gdrive}"
TYPE="${RCLONE_TYPE:-drive}"
SCOPE="${RCLONE_SCOPE:-drive}"

mkdir -p "${CONFIG_DIR}"

if [ -z "${RCLONE_TOKEN:-}" ]; then
    echo "ERROR: RCLONE_TOKEN is not set. Add it to your .env file." >&2
    exit 1
fi

echo "Generating rclone.conf (OAuth mode) ..."
cat > "${CONFIG_FILE}" <<EOF
[${REMOTE}]
type = ${TYPE}
scope = ${SCOPE}
token = ${RCLONE_TOKEN}
EOF

echo "rclone.conf written to ${CONFIG_FILE}"
