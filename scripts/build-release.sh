#!/usr/bin/env bash
# Builds the signed Android App Bundle (AAB) for Google Play from the Flutter client.
# The upload-key password is typed here, kept only in memory, and never written to any file.
set -euo pipefail
cd "$(dirname "$0")/.."
SECRETS="$(cd .. && pwd)/travelbuddy-secrets"
KS="${TB_KEYSTORE:-$SECRETS/travelbuddy-upload.jks}"
[ -f "$KS" ] || { echo "Upload keystore not found at $KS"; exit 1; }
python3 scripts/gen-firebase-options.py

read -rsp "Upload key password: " TB_STORE_PASSWORD; echo
export TB_STORE_PASSWORD TB_KEYSTORE="$KS"
(cd client && flutter build appbundle --release)
unset TB_STORE_PASSWORD

AAB=client/build/app/outputs/bundle/release/app-release.aab
if keytool -printcert -jarfile "$AAB" | grep -q "7D:32:D9:8D"; then
  echo "Signed with the TravelBuddy upload key."
else
  echo "WARNING: not signed with the upload key!"
fi
grep -E "^version:" client/pubspec.yaml
echo "Upload this file to Play Console: $(pwd)/$AAB"
