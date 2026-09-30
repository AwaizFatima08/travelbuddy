#!/usr/bin/env bash
# Builds the signed release bundle (AAB) for Google Play.
# The upload-key password is typed here, kept only in memory, and never written to any file.
set -euo pipefail
cd "$(dirname "$0")/.."

SECRETS="$(cd .. && pwd)/travelbuddy-secrets"
KS="${TB_KEYSTORE:-$SECRETS/travelbuddy-upload.jks}"
[ -f "$KS" ] || { echo "Upload keystore not found at $KS"; exit 1; }
[ -f app/google-services.json ] || cp "$SECRETS/google-services.json" app/

read -rsp "Upload key password: " TB_STORE_PASSWORD; echo
export TB_STORE_PASSWORD TB_KEYSTORE="$KS"
./gradlew --console=plain clean bundleRelease
unset TB_STORE_PASSWORD

AAB=app/build/outputs/bundle/release/app-release.aab
jarsigner -verify "$AAB" >/dev/null && echo "Signed OK."
grep -E "versionCode|versionName" app/build.gradle.kts | sed 's/^ */  /'
echo "Upload this file to Play Console: $(pwd)/$AAB"
