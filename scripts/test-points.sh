#!/usr/bin/env bash
# Runs the points-system suite (firestore-tests/points.test.mjs) against the local emulators
# (auth + firestore + functions). Needs Java 21 in ~/.local/jdk. One heavy job: ~1 GB RAM.
set -euo pipefail
cd "$(dirname "$0")/.."
JDK21=$(ls -d "$HOME"/.local/jdk/jdk-21* 2>/dev/null | head -1 || true)
[ -n "$JDK21" ] && export JAVA_HOME="$JDK21" PATH="$JDK21/bin:$PATH"
[ -d firestore-tests/node_modules ] || npm --prefix firestore-tests install
[ -d functions/node_modules ] || npm --prefix functions install
firebase emulators:exec --only auth,firestore,functions --project travelbuddy-12d76 \
  "node --test firestore-tests/points.test.mjs" 2>&1 | grep -E "^(not )?ok |^# (tests|pass|fail)|AssertionError|Error:|expected|actual" | head -80
