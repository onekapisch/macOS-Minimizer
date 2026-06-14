#!/bin/bash
# Builds Minimizer.app from the SwiftPM executable and signs it with a STABLE,
# self-signed code-signing identity. A stable identity is what makes macOS
# Accessibility (TCC) permission persist across rebuilds — ad-hoc signing does
# NOT, because its identity is the binary hash, which changes every build.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Minimizer"
BUNDLE="${APP_NAME}.app"
CONFIG="release"

SELFSIGN_NAME="Minimizer Local Signing"
KEYCHAIN="$HOME/Library/Keychains/minimizer-signing.keychain-db"
APP_SUPPORT="$HOME/Library/Application Support/Minimizer"
KCPASS_FILE="$APP_SUPPORT/signing-keychain-password"

# Resolved at runtime by ensure_identity().
SIGN_IDENTITY=""
SIGN_KEYCHAIN_ARGS=()

signing_keychain_password() {
    mkdir -p "$APP_SUPPORT"
    chmod 700 "$APP_SUPPORT"
    if [ ! -f "$KCPASS_FILE" ]; then
        openssl rand -base64 48 > "$KCPASS_FILE"
        chmod 600 "$KCPASS_FILE"
    fi
    tr -d '\n' < "$KCPASS_FILE"
}

# --- Resolve a STABLE signing identity ----------------------------------------
# Prefer a real identity already in the keychain (Developer ID / Apple
# Development) — its designated requirement is stable across rebuilds. Only fall
# back to creating a self-signed cert if no real identity is present.
ensure_identity() {
    local real
    real=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -E 'Developer ID Application|Apple Development' \
        | head -1 | sed -E 's/^[[:space:]]*[0-9]+\) [0-9A-F]+ "(.*)"$/\1/' \
        || true)
    if [ -n "$real" ]; then
        SIGN_IDENTITY="$real"
        echo "==> Using existing stable identity: $SIGN_IDENTITY"
        return 0
    fi

    SIGN_IDENTITY="$SELFSIGN_NAME"
    SIGN_KEYCHAIN_ARGS=(--keychain "$KEYCHAIN")
    local kcpass
    kcpass=$(signing_keychain_password)
    if [ -f "$KEYCHAIN" ]; then
        security unlock-keychain -p "$kcpass" "$KEYCHAIN"
    fi
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SELFSIGN_NAME"; then
        echo "==> Using self-signed identity: $SELFSIGN_NAME"
        return 0
    fi

    echo "==> Creating a self-signed code-signing identity (one time only)..."

    if [ ! -f "$KEYCHAIN" ]; then
        security create-keychain -p "$kcpass" "$KEYCHAIN"
    fi
    security set-keychain-settings "$KEYCHAIN"            # no auto-lock timeout
    security unlock-keychain -p "$kcpass" "$KEYCHAIN"

    # Add our keychain to the user search list, preserving the existing ones.
    local existing
    existing=$(security list-keychains -d user | sed -e 's/^[[:space:]]*//' -e 's/"//g')
    # shellcheck disable=SC2086
    security list-keychains -d user -s "$KEYCHAIN" $existing

    local TMP
    TMP=$(mktemp -d)
    cat > "$TMP/openssl.cnf" <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[ dn ]
CN = Minimizer Local Signing
[ v3 ]
basicConstraints   = critical,CA:false
keyUsage           = critical,digitalSignature
extendedKeyUsage   = critical,codeSigning
EOF

    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
        -config "$TMP/openssl.cnf" -extensions v3 >/dev/null 2>&1

    openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
        -out "$TMP/id.p12" -passout pass:"$kcpass" -name "$SELFSIGN_NAME" >/dev/null 2>&1

    security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$kcpass" -T /usr/bin/codesign -A
    # Authorize codesign to use the key without an interactive prompt.
    security set-key-partition-list -S apple-tool:,apple:,codesign: \
        -s -k "$kcpass" "$KEYCHAIN" >/dev/null 2>&1

    rm -rf "$TMP"
    echo "    Identity '$SELFSIGN_NAME' created in $KEYCHAIN"
}

# --- Build --------------------------------------------------------------------
echo "==> Building (${CONFIG})..."
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"

# --- Assemble bundle ----------------------------------------------------------
echo "==> Assembling ${BUNDLE}..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
if [ -f "Resources/Minimizer.icns" ]; then
    cp "Resources/Minimizer.icns" "$BUNDLE/Contents/Resources/Minimizer.icns"
fi

# --- Sign with the stable identity -------------------------------------------
ensure_identity
echo "==> Signing with '${SIGN_IDENTITY}'..."
codesign --force --sign "$SIGN_IDENTITY" "${SIGN_KEYCHAIN_ARGS[@]+"${SIGN_KEYCHAIN_ARGS[@]}"}" "$BUNDLE"
codesign --verify --verbose "$BUNDLE"

echo "==> Done: $(pwd)/$BUNDLE"
echo "    Designated requirement (stable across rebuilds):"
codesign -dr - "$BUNDLE" 2>/dev/null | sed 's/^/      /'
