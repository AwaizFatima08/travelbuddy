#!/usr/bin/env bash
# Local snapshot of the project (source only — no build output, no secrets).
set -euo pipefail
cd "$(dirname "$0")/.."
DEST=/mnt/storage/project_backups/travelbuddy_backup/$(date +%Y-%m-%d_%H%M)
mkdir -p "$DEST"
rsync -a --exclude build/ --exclude .gradle/ --exclude .kotlin/ --exclude node_modules/ \
      --exclude 'Old AI Studio project/' --exclude google-services.json --exclude '*.jks' \
      ./ "$DEST/"
echo "Snapshot saved to $DEST ($(du -sh "$DEST" | cut -f1))"
echo "Reminder: copy this snapshot to Google Drive:"
echo "  https://drive.google.com/drive/folders/1arvKHZ4hQwMMZ7mhVvQODKEA0Vt4nS_f"
