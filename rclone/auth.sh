#!/bin/sh
# rclone/auth.sh – One-time interactive OAuth authorization for Google Drive.
#
# Run this ONCE (or whenever you need to re-authorize) with:
#   docker compose run --rm rclone-auth
#
# What this script does:
#   1. Writes a base rclone.conf (client ID + secret) to the rclone-config volume.
#   2. Runs "rclone config reconnect" to complete the OAuth flow.
#      rclone will print an authorization URL.  Open it in a browser, grant
#      access, and the token is automatically saved to the volume.
#   3. After this step rclone-sync uses the token on every run – no .env entry
#      needed.
#
# Note: port 53682 must be reachable from your browser for the OAuth callback.
# If Docker is running on a remote server, forward the port first:
#   ssh -L 53682:localhost:53682 your-server
# then run: docker compose run --rm rclone-auth

set -e

CONFIG_DIR="/config/rclone"
CONFIG_FILE="${CONFIG_DIR}/rclone.conf"
REMOTE="${RCLONE_REMOTE:-gdrive}"
TYPE="${RCLONE_TYPE:-drive}"
SCOPE="${RCLONE_SCOPE:-drive}"

mkdir -p "${CONFIG_DIR}"

# Write base config (without token – rclone will add it after the OAuth flow).
cat > "${CONFIG_FILE}" <<EOF
[${REMOTE}]
type = ${TYPE}
client_id = ${RCLONE_CLIENT_ID:-}
client_secret = ${RCLONE_CLIENT_SECRET:-}
scope = ${SCOPE}
EOF

echo "============================================"
echo " rclone OAuth authorization"
echo " Remote: ${REMOTE}"
echo "============================================"
echo ""
echo "A browser window will open for authorization."
echo "If it does not open automatically, copy the URL printed below and"
echo "open it manually.  After granting access the token is saved"
echo "automatically – you do not need to copy anything to .env."
echo ""

rclone config reconnect "${REMOTE}:" \
    --config "${CONFIG_FILE}" \
    --auth-no-open-browser

echo ""
echo "Authorization complete. Token saved to the rclone-config volume."
echo "You can now start the full stack with: docker compose up -d"
