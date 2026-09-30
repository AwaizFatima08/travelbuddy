#!/usr/bin/env bash
# Runs the Firestore security-rules tests in the local emulator (needs Java 21+).
set -euo pipefail
cd "$(dirname "$0")/.."
JDK21=$(ls -d "$HOME"/.local/jdk/jdk-21* 2>/dev/null | head -1 || true)
[ -n "$JDK21" ] && export JAVA_HOME="$JDK21" PATH="$JDK21/bin:$PATH"
[ -d firestore-tests/node_modules ] || npm --prefix firestore-tests install
firebase emulators:exec --only firestore --project travelbuddy-rules-test \
  "npm --prefix firestore-tests test" 2>&1 | grep -E "^(not )?ok |^# (tests|pass|fail)"
