#!/usr/bin/env bash
# release-to-mine-app.sh — one-shot loop for getting library changes into mine-app.
#
# Runs the full local validation + pack + install pipeline:
#   1. Validate iOS Swift compiles (~1-2 min)
#   2. Validate Android Kotlin compiles (~30-60s)
#   3. Rebuild TS
#   4. npm pack into mine-app/vendor/ (versioned filename)
#   5. Update mine-app/package.json to reference the new versioned tarball
#   6. Clear yarn cache + lockfile entry
#   7. yarn install in mine-app
#   8. Run mine-app's tsc --noEmit
#
# Versioning: the tarball filename includes the library version (e.g.
# `expo-realtime-ivs-broadcast-0.2.9.tgz`) so git diffs make pin changes
# obvious and rollbacks are a single `git checkout` away. Bump
# `package.json#version` before running this script.
#
# Exits non-zero at the first failure so you can stop and fix before wasting an
# EAS build.
#
# Usage:
#   ./scripts/release-to-mine-app.sh
#   SKIP_ANDROID=1 ./scripts/release-to-mine-app.sh   # iOS-only validation

set -euo pipefail

LIB_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MINE_APP="${MINE_APP:-/Users/arvin-medina/Dev/PixelGroup/mine-app}"
PKG_NAME="expo-realtime-ivs-broadcast"

if [ ! -d "$MINE_APP" ]; then
  echo "❌ mine-app not found at $MINE_APP. Set MINE_APP env var."
  exit 1
fi

cd "$LIB_ROOT"

# Read the version we're about to ship from package.json.
VERSION="$(node -p "require('./package.json').version")"
if [ -z "$VERSION" ]; then
  echo "❌ Could not read version from $LIB_ROOT/package.json"
  exit 1
fi
echo "🏷  Releasing $PKG_NAME@$VERSION → $MINE_APP/vendor/"
echo ""

echo "━━━━━ 1/7  iOS Swift compile check ━━━━━"
./scripts/verify-ios.sh

if [ "${SKIP_ANDROID:-}" != "1" ]; then
  echo ""
  echo "━━━━━ 2/7  Android Kotlin compile check ━━━━━"
  ./scripts/verify-android.sh
else
  echo "⏭  skipping Android (SKIP_ANDROID=1)"
fi

echo ""
echo "━━━━━ 3/7  Build JS (tsc → build/) ━━━━━"
npm run build

echo ""
echo "━━━━━ 4/7  npm pack (versioned filename) ━━━━━"
rm -f "$LIB_ROOT/$PKG_NAME-"*.tgz
npm pack >/dev/null
SOURCE_TARBALL="$LIB_ROOT/$PKG_NAME-$VERSION.tgz"
DEST_TARBALL="$MINE_APP/vendor/$PKG_NAME-$VERSION.tgz"
if [ ! -f "$SOURCE_TARBALL" ]; then
  echo "❌ npm pack did not produce $SOURCE_TARBALL"
  ls "$LIB_ROOT"/*.tgz 2>/dev/null || true
  exit 1
fi
echo "    packed $(basename "$SOURCE_TARBALL")"

# Remove any prior versioned tarballs of this package so vendor/ only ever
# holds the currently-pinned version (git history preserves the rest).
mkdir -p "$MINE_APP/vendor"
find "$MINE_APP/vendor" -maxdepth 1 -name "$PKG_NAME-*.tgz" -not -name "$PKG_NAME-$VERSION.tgz" -delete
# Also remove the legacy unversioned filename if it still exists.
rm -f "$MINE_APP/vendor/$PKG_NAME.tgz"
cp "$SOURCE_TARBALL" "$DEST_TARBALL"
echo "    copied → $DEST_TARBALL"

echo ""
echo "━━━━━ 5/7  Update mine-app/package.json pin ━━━━━"
# Use node to rewrite the dependency value safely (preserves formatting).
node -e "
  const fs = require('fs');
  const path = '$MINE_APP/package.json';
  const pkg = JSON.parse(fs.readFileSync(path, 'utf8'));
  const target = 'file:./vendor/$PKG_NAME-$VERSION.tgz';
  const current = pkg.dependencies && pkg.dependencies['$PKG_NAME'];
  if (current === target) {
    console.log('    pin already up-to-date: ' + target);
  } else {
    pkg.dependencies['$PKG_NAME'] = target;
    fs.writeFileSync(path, JSON.stringify(pkg, null, 2) + '\n');
    console.log('    pin updated → ' + target + (current ? ' (was: ' + current + ')' : ''));
  }
"

echo ""
echo "━━━━━ 6/7  Clear stale yarn cache + lockfile entry ━━━━━"
find ~/Library/Caches/Yarn -maxdepth 4 -name "npm-$PKG_NAME*" -prune -exec rm -rf {} + 2>/dev/null || true
# IMPORTANT: yarn classic (v1) writes a .yarn-metadata.json under
# ~/Library/Caches/Yarn/v6/.tmp/<hash>/ during install of file: deps. That
# metadata embeds the SHA1 of the tarball at the time of install. If we
# only clear npm-<pkg>-<ver>-<sha>/ but leave .tmp/, yarn re-reads the
# stale metadata on the next install and writes the OLD SHA1 into
# yarn.lock — even though the actual tarball has new content. EAS then
# fails its frozen-lockfile integrity check. Wiping .tmp/ here closes
# that hole. (See: yarn-pkg/yarn classic v1 file: dependency caching.)
rm -rf ~/Library/Caches/Yarn/v6/.tmp 2>/dev/null || true
rm -rf "$MINE_APP/node_modules/$PKG_NAME" "$MINE_APP/node_modules/.yarn-integrity"
# Drop every prior lockfile entry for this package (any version path) so yarn
# re-resolves cleanly against the new versioned filename.
sed -i '' "/^\"$PKG_NAME@file:/,/^$/d" "$MINE_APP/yarn.lock"

echo ""
echo "━━━━━ 7/7  yarn install + tsc check ━━━━━"
(cd "$MINE_APP" && yarn install)

# Verify the install actually pulled the new tarball.
INSTALLED_PKG="$MINE_APP/node_modules/$PKG_NAME/package.json"
if [ ! -f "$INSTALLED_PKG" ]; then
  echo "❌ Install verification failed — $PKG_NAME missing from node_modules"
  exit 1
fi
INSTALLED_VERSION="$(node -p "require('$INSTALLED_PKG').version")"
if [ "$INSTALLED_VERSION" != "$VERSION" ]; then
  echo "❌ Install verification failed — node_modules has $PKG_NAME@$INSTALLED_VERSION but expected @$VERSION"
  exit 1
fi
echo "    ✅ node_modules has $PKG_NAME@$INSTALLED_VERSION"

(cd "$MINE_APP" && npx tsc --noEmit)

echo ""
echo "✅ $PKG_NAME@$VERSION validated, packed, installed into mine-app, and TS-checked."
echo "   Don't forget to update vendor/README.md changelog and commit."
echo "   You can now safely trigger eas build."
