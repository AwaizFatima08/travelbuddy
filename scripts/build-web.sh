#!/usr/bin/env bash
# Builds the web app for https://travelbuddy.homilabs.org/app/ and packs it as a zip
# to upload into the site's "app" folder in Hostinger File Manager (then Extract).
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/gen-firebase-options.py
(cd client && flutter build web --release --base-href /app/)
VER=$(grep -E "^version:" client/pubspec.yaml | awk '{print $2}')
OUT="$HOME/Downloads/travelbuddy-webapp-$VER.zip"
rm -f "$OUT"
(cd client/build/web && zip -qr "$OUT" .)
echo "Upload $OUT into the site's 'app' folder (create it first), then Extract it there."
