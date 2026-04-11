#!/bin/sh
# rclone/sync.sh – Periodically sync Paperless-ngx data to Google Drive
#
# Environment variables (set in docker-compose.yml / .env):
#   RCLONE_REMOTE          – name of the rclone remote (default: gdrive)
#   RCLONE_DEST_PATH       – destination folder inside Google Drive (default: paperless-backup)
#   SYNC_INTERVAL_SECONDS  – seconds between syncs (default: 3600)

set -e

REMOTE="${RCLONE_REMOTE:-gdrive}"
DEST="${RCLONE_DEST_PATH:-paperless-backup}"
INTERVAL="${SYNC_INTERVAL_SECONDS:-3600}"

echo "============================================"
echo " rclone Google Drive sync started"
echo " Remote  : ${REMOTE}:${DEST}"
echo " Interval: ${INTERVAL}s"
echo "============================================"

while true; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting sync to ${REMOTE}:${DEST} ..."

    # Sync media directory (original documents + thumbnails)
    rclone sync /data/media "${REMOTE}:${DEST}/media" \
        --log-level INFO \
        --stats 60s \
        --transfers 4 \
        --checkers 8 \
        --contimeout 60s \
        --timeout 300s \
        --retries 3 \
        || echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: media sync encountered errors"

    # Sync export directory (Paperless-ngx document exports)
    rclone sync /data/export "${REMOTE}:${DEST}/export" \
        --log-level INFO \
        --stats 60s \
        --transfers 4 \
        --checkers 8 \
        --contimeout 60s \
        --timeout 300s \
        --retries 3 \
        || echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: export sync encountered errors"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sync complete. Next sync in ${INTERVAL}s."
    sleep "${INTERVAL}"
done
