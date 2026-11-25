#!/usr/bin/env bash
# Builds the FFL web app (webapp/, Firebase project gen-lang-client-0717949368) for
# https://travelbuddy.homilabs.org/app/ and packs it as a zip for Hostinger's File Manager:
# upload the zip into the site's "app" folder (empty it first), then Extract.
# Heavy: run through jobq →  jobq run --name tb-ffl-web -- scripts/build-ffl-web.sh
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/gen-ffl-web-options.py
(cd webapp && flutter build web --release --base-href /app/)
VER=$(grep -E "^version:" webapp/pubspec.yaml | awk '{print $2}')
OUT="$HOME/Downloads/travelbuddy-ffl-webapp-$VER.zip"
rm -f "$OUT"
(cd webapp/build/web && zip -qr "$OUT" .)
echo "Built webapp $VER → $OUT"
echo "Hostinger: delete the old contents of public_html/app/, upload the zip there and Extract."
