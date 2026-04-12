#!/bin/sh
# rclone/sync.sh – Sync Paperless-ngx data with Google Drive (source of truth)
#
# On startup the script first restores local data FROM Google Drive, so a fresh
# host always starts with the latest documents.  Afterwards it enters a periodic
# loop that pushes any local changes back TO Google Drive.
#
# Google Drive is the authoritative source of truth:
#   startup  : Google Drive → local  (restore)
#   every N s: local → Google Drive  (backup)
#
# Environment variables (set in docker-compose.yml / .env):
#   RCLONE_REMOTE          – name of the rclone remote (default: gdrive)
#   RCLONE_DEST_PATH       – folder inside Google Drive   (default: paperless-backup)
#   SYNC_INTERVAL_SECONDS  – seconds between upload syncs (default: 3600)

set -e

REMOTE="${RCLONE_REMOTE:-gdrive}"
DEST="${RCLONE_DEST_PATH:-paperless-backup}"
INTERVAL="${SYNC_INTERVAL_SECONDS:-3600}"

RCLONE_OPTS="
    --log-level INFO
    --stats 60s
    --transfers 4
    --checkers 8
    --contimeout 60s
    --timeout 300s
    --retries 3
    --create-empty-src-dirs
"

echo "============================================"
echo " rclone Google Drive sync started"
echo " Remote  : ${REMOTE}:${DEST}"
echo " Interval: ${INTERVAL}s"
echo " Mode    : GDrive is source of truth"
echo "============================================"

# ── Initial restore: Google Drive → local ─────────────────────────────────────
# Runs once at startup so a fresh host gets all documents from Google Drive.
# Uses 'rclone sync' which makes the local directory an exact mirror of GDrive.
# If GDrive is empty this is a no-op.

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restoring from ${REMOTE}:${DEST} (initial restore)..."

rclone sync "${REMOTE}:${DEST}/media" /data/media \
    $RCLONE_OPTS \
    || echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: initial media restore encountered errors"

rclone sync "${REMOTE}:${DEST}/export" /data/export \
    $RCLONE_OPTS \
    || echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: initial export restore encountered errors"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Initial restore complete. Starting periodic upload loop (every ${INTERVAL}s)."

# ── Periodic backup: local → Google Drive ─────────────────────────────────────
while true; do
    sleep "${INTERVAL}"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting upload sync to ${REMOTE}:${DEST} ..."

    rclone sync /data/media "${REMOTE}:${DEST}/media" \
        $RCLONE_OPTS \
        || echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: media upload sync encountered errors"

    rclone sync /data/export "${REMOTE}:${DEST}/export" \
        $RCLONE_OPTS \
        || echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: export upload sync encountered errors"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Upload sync complete. Next sync in ${INTERVAL}s."
done
