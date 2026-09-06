#!/usr/bin/env bash
# AFFiNE weekly backup: local snapshot + encrypted upload to Google Drive.
# Invoked by the affine-backup.timer systemd user unit (Sundays 03:00).
set -euo pipefail

DEPLOY_DIR="/home/bas-server/code/affine-bas"
BACKUP_ROOT="$HOME/affine-backups"
RCLONE="$HOME/.local/bin/rclone"
STAMP="$(date +%F)"
BK="$BACKUP_ROOT/$STAMP"
KEEP_LOCAL_DAYS=90
KEEP_REMOTE=12  # number of Drive backup directories to keep

mkdir -p "$BK"

# 1. PostgreSQL dump
podman exec affine_bas_postgres pg_dump -U affine affine > "$BK/affine-db.sql"

# 2. App files and config
cd "$DEPLOY_DIR"
cp -a config data/storage compose.yml "$BK/"
cp .env "$BK/env"
chmod 600 "$BK/env"
podman inspect --format '{{.Config.Image}}' affine_bas_server > "$BK/image.txt"

# 3. Caddy volumes (Tailscale node identity + certificates)
podman volume export affine-bas_caddy_ts_state -o "$BK/caddy_ts_state.tar"
podman volume export affine-bas_caddy_data -o "$BK/caddy_data.tar"

# 4. Checksums
cd "$BK"
sha256sum affine-db.sql env compose.yml image.txt caddy_ts_state.tar caddy_data.tar > SHA256SUMS

# 5. Encrypted off-host upload
"$RCLONE" copy "$BK" "gdrive-crypt:$STAMP"

# 6. Prune old local snapshots
find "$BACKUP_ROOT" -maxdepth 1 -mindepth 1 -type d -name "20*" -mtime +"$KEEP_LOCAL_DAYS" -exec rm -rf {} +

# 7. Prune old Drive backups (keep the newest KEEP_REMOTE directories)
"$RCLONE" lsf "gdrive-crypt:" --dirs-only | sort | head -n -"$KEEP_REMOTE" | while read -r d; do
  d="${d%/}"
  [ -n "$d" ] && "$RCLONE" purge "gdrive-crypt:$d"
done

echo "Backup $STAMP complete."
