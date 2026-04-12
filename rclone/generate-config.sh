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
#   RCLONE_CLIENT_ID       – OAuth client ID
#   RCLONE_CLIENT_SECRET   – OAuth client secret
#
# The OAuth token is NOT stored in .env. It is written to the rclone-config
# volume by the one-time "rclone-auth" setup service and is preserved here
# across restarts.

set -e

CONFIG_DIR="/config/rclone"
CONFIG_FILE="${CONFIG_DIR}/rclone.conf"
REMOTE="${RCLONE_REMOTE:-gdrive}"
TYPE="${RCLONE_TYPE:-drive}"
SCOPE="${RCLONE_SCOPE:-drive}"

mkdir -p "${CONFIG_DIR}"

# Preserve the OAuth token that was saved by the rclone-auth setup service.
EXISTING_TOKEN=""
if [ -f "${CONFIG_FILE}" ]; then
    EXISTING_TOKEN=$(grep "^token = " "${CONFIG_FILE}" | sed 's/^token = //' || true)
fi

echo "Generating rclone.conf ..."
cat > "${CONFIG_FILE}" <<EOF
[${REMOTE}]
type = ${TYPE}
client_id = ${RCLONE_CLIENT_ID:-}
client_secret = ${RCLONE_CLIENT_SECRET:-}
scope = ${SCOPE}
EOF

if [ -n "${EXISTING_TOKEN}" ]; then
    echo "token = ${EXISTING_TOKEN}" >> "${CONFIG_FILE}"
    echo "rclone.conf written to ${CONFIG_FILE} (existing token preserved)"
else
    echo "rclone.conf written to ${CONFIG_FILE}"
    echo "WARNING: No OAuth token found. Run 'docker compose run --rm rclone-auth' to authorize."
fi
