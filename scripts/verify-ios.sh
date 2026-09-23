#!/usr/bin/env bash
# verify-ios.sh — local Swift compile check for expo-realtime-ivs-broadcast.
#
# Runs xcodebuild against the example app's Pods/xcworkspace so we get the
# real Amazon IVS SDK symbols. Catches Swift compile errors locally in
# ~1-2 minutes instead of waiting 15-30 minutes for an EAS build to fail.
#
# Usage:
#   ./scripts/verify-ios.sh           # Build + report errors only
#   ./scripts/verify-ios.sh --verbose # Include warnings
#
# If you've never run this before, run `cd example/ios && pod install` first.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXAMPLE_IOS="$ROOT/example/ios"
VERBOSE="${1:-}"

if [ ! -d "$EXAMPLE_IOS/Pods" ]; then
  echo "❌ $EXAMPLE_IOS/Pods missing — running pod install first."
  (cd "$EXAMPLE_IOS" && pod install)
fi

WORKSPACE="$EXAMPLE_IOS/exporealtimeivsbroadcastexample.xcworkspace"
SCHEME="exporealtimeivsbroadcastexample"

# Filter: keep error lines + the line just before (which has the file:line context).
# Drop warnings unless --verbose.
FILTER='/error:|fatal error:/'
if [ "$VERBOSE" = "--verbose" ]; then
  FILTER='/error:|warning:|fatal error:/'
fi

# Build BOTH Debug and Release. EAS runs CocoaPods builds in Release config
# even on dev profiles, and Release defines no `DEBUG` macro — so any code
# that references types/symbols only declared inside `#if DEBUG` will compile
# fine here in Debug but blow up at EAS in Release with "cannot find type
# 'X' in scope". Catching this locally costs ~2 extra minutes; missing it
# costs 15-30 minutes per failed EAS build.
build_config() {
  local CONFIG="$1"
  local LOG="/tmp/expo-ivs-build-${CONFIG}.log"
  echo ""
  echo "🔨 Building ${SCHEME} for iOS Simulator (${CONFIG})..."

  set +e
  xcodebuild \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination 'generic/platform=iOS Simulator' \
    -quiet \
    build CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$LOG" | grep -E "error:|fatal error:|BUILD SUCCEEDED|BUILD FAILED"
  local RC=${PIPESTATUS[0]}
  set -e

  if grep -q "error:" "$LOG" 2>/dev/null; then
    echo ""
    echo "❌ ${CONFIG} build failed. See above. Full log: $LOG"
    exit 1
  fi

  if [ "$RC" -ne 0 ]; then
    echo "❌ xcodebuild (${CONFIG}) exited with code $RC. See $LOG"
    exit "$RC"
  fi
}

build_config Debug
build_config Release

echo ""
echo "✅ Swift compile clean (Debug + Release). Safe to npm pack and ship to EAS."
