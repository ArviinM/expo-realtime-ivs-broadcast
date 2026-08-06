#!/usr/bin/env bash
# verify-android.sh — local Kotlin compile check for expo-realtime-ivs-broadcast.
#
# Runs gradle against the example android project so we get the real Amazon IVS
# Android SDK symbols. Catches Kotlin compile errors locally in ~30-60s instead
# of waiting for an EAS build to fail.
#
# Usage:
#   ./scripts/verify-android.sh            # compileDebugKotlin only (fast)
#   ./scripts/verify-android.sh --assemble # full assembleDebug (slower, catches manifest/resource issues too)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXAMPLE_ANDROID="$ROOT/example/android"

if [ ! -x "$EXAMPLE_ANDROID/gradlew" ]; then
  echo "❌ $EXAMPLE_ANDROID/gradlew missing or not executable"
  exit 1
fi

cd "$EXAMPLE_ANDROID"

TASK=":expo-realtime-ivs-broadcast:compileDebugKotlin"
if [ "${1:-}" = "--assemble" ]; then
  TASK=":expo-realtime-ivs-broadcast:assembleDebug"
fi

echo "🔨 Running gradle ${TASK}..."

set +e
./gradlew "$TASK" 2>&1 | tee /tmp/expo-ivs-android-build.log | tail -25
RC=${PIPESTATUS[0]}
set -e

if grep -qE "^e: |error:" /tmp/expo-ivs-android-build.log 2>/dev/null; then
  echo ""
  echo "❌ Kotlin compile failed. Full log: /tmp/expo-ivs-android-build.log"
  exit 1
fi

if [ "$RC" -ne 0 ]; then
  echo "❌ gradle exited with code $RC. See /tmp/expo-ivs-android-build.log"
  exit "$RC"
fi

echo ""
echo "✅ Kotlin compile clean. Safe to npm pack and ship to EAS."
