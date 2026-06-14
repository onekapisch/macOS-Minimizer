#!/bin/bash
# Builds, Developer ID-signs (Hardened Runtime), notarizes, staples, and packages
# Minimizer into a distributable Minimizer.dmg.
#
# PREREQUISITES (one-time):
#   1) A "Developer ID Application" certificate in your keychain
#      (Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application).
#   2) A stored notary credential profile named "MinimizerNotary":
#        xcrun notarytool store-credentials "MinimizerNotary" \
#          --key   /path/to/AuthKey_XXXXXX.p8 \
#          --key-id YOUR_KEY_ID \
#          --issuer YOUR_ISSUER_ID
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Minimizer"
BUNDLE="${APP_NAME}.app"
DMG="${APP_NAME}.dmg"
NOTARY_PROFILE="MinimizerNotary"
CONFIG="release"

# --- Resolve the Developer ID Application identity ---
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 | sed -E 's/^[[:space:]]*[0-9]+\) [0-9A-F]+ "(.*)"$/\1/')
if [ -z "$IDENTITY" ]; then
    echo "ERROR: No 'Developer ID Application' certificate found."
    echo "Create one: Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application."
    exit 1
fi
echo "==> Signing identity: $IDENTITY"

# --- Build + assemble the .app (reuses the SwiftPM build) ---
echo "==> Building ($CONFIG)…"
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"

echo "==> Assembling $BUNDLE…"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
cp "Resources/Minimizer.icns" "$BUNDLE/Contents/Resources/Minimizer.icns"

# --- Sign with Hardened Runtime + secure timestamp (required for notarization) ---
echo "==> Codesigning (Developer ID, Hardened Runtime)…"
codesign --force --options runtime --timestamp \
    --sign "$IDENTITY" "$BUNDLE"
codesign --verify --strict --verbose=2 "$BUNDLE"

# --- Build the DMG (drag-to-Applications) ---
echo "==> Building $DMG…"
rm -rf "$DMG" dmg_staging
mkdir dmg_staging
cp -R "$BUNDLE" dmg_staging/
ln -s /Applications dmg_staging/Applications
hdiutil create -volname "$APP_NAME" -srcfolder dmg_staging -ov -format UDZO "$DMG"
rm -rf dmg_staging
codesign --force --sign "$IDENTITY" "$DMG"

# --- Notarize + staple ---
echo "==> Submitting to Apple notary service (this can take a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling…"
xcrun stapler staple "$DMG"
xcrun stapler staple "$BUNDLE" || true
spctl --assess --type open --context context:primary-signature -v "$DMG" || true

echo "==> Done: $(pwd)/$DMG"
echo "    Verify on a clean machine: download, open the .dmg, drag to Applications,"
echo "    launch — Gatekeeper should allow it with no warnings."
