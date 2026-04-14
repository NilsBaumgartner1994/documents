#!/bin/sh
# rclone/sync.sh – Periodically sync Paperless-ngx data to/from Google Drive
#
# Environment variables (set in docker-compose.yml / .env):
#   RCLONE_REMOTE          – name of the rclone remote (default: gdrive)
#   RCLONE_DEST_PATH       – destination folder inside Google Drive (default: paperless-backup)
#   SYNC_INTERVAL_SECONDS  – seconds between syncs
#   RCLONE_SYNC_MODE       – sync direction (default: upload)
#       upload   – local → Google Drive  (default, current behaviour)
#       download – Google Drive → local  (consume only, no upload)
#       none     – disable sync entirely (container stays running but does nothing)

set -e

REMOTE="${RCLONE_REMOTE:-gdrive}"
DEST="${RCLONE_DEST_PATH:-paperless-backup}"
INTERVAL="${SYNC_INTERVAL_SECONDS:-3600}"
MODE="${RCLONE_SYNC_MODE:-upload}"

# Copy the read-only config to a writable location so rclone can persist
# refreshed OAuth tokens without hitting a read-only filesystem error.
RCLONE_CONFIG_FILE="/tmp/rclone.conf"
cp /config/rclone/rclone.conf "${RCLONE_CONFIG_FILE}"

echo "============================================"
echo " rclone Google Drive sync started"
echo " Remote  : ${REMOTE}:${DEST}"
echo " Mode    : ${MODE}"
echo " Interval: ${INTERVAL}s"
echo "============================================"

# Common rclone flags reused by every sync call
RCLONE_FLAGS="--config ${RCLONE_CONFIG_FILE} --log-level INFO --stats 60s --transfers 4 --checkers 8 --contimeout 60s --timeout 300s --retries 3"

sync_upload() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting upload sync (local → ${REMOTE}:${DEST}) ..."

    # Sync media directory (original documents + thumbnails)
    rclone sync /data/media "${REMOTE}:${DEST}/media" ${RCLONE_FLAGS} \
        || echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: media upload sync encountered errors"

    # Sync export directory (Paperless-ngx document exports)
    rclone sync /data/export "${REMOTE}:${DEST}/export" ${RCLONE_FLAGS} \
        || echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: export upload sync encountered errors"
}

sync_download() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting download sync (${REMOTE}:${DEST} → local) ..."

    # Use 'rclone copy' instead of 'rclone sync' to avoid deleting local files
    # that are not present on Google Drive.
    rclone copy "${REMOTE}:${DEST}/media" /data/media ${RCLONE_FLAGS} \
        || echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: media download sync encountered errors"

    rclone copy "${REMOTE}:${DEST}/export" /data/export ${RCLONE_FLAGS} \
        || echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: export download sync encountered errors"
}

# Handle 'none' mode and validate before entering the sync loop.
if [ "${MODE}" = "none" ] || [ "${MODE}" = "disabled" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sync mode is '${MODE}' – sleeping indefinitely."
    while true; do sleep 86400; done
elif [ "${MODE}" != "upload" ] && [ "${MODE}" != "download" ]; then
    echo "ERROR: Unknown RCLONE_SYNC_MODE '${MODE}'. Use 'upload', 'download', or 'none'." >&2
    exit 1
fi

while true; do
    case "${MODE}" in
        upload)   sync_upload   ;;
        download) sync_download ;;
    esac

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sync complete. Next sync in ${INTERVAL}s."
    sleep "${INTERVAL}"
done
