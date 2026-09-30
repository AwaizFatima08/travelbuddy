#!/usr/bin/env bash
# Deploys security rules, indexes and the 30-day TTL policies to the real project.
set -euo pipefail
cd "$(dirname "$0")/.."
firebase deploy --only firestore:rules,firestore:indexes --project travelbuddy-12d76
