#!/bin/zsh
# Build Quicklet (app + Finder Sync extension) and re-sign with a real
# development certificate.
#
# Why the two-step signing:
#   1. Xcode's automatic/manual signing demands a provisioning profile for
#      the App Groups entitlement, which requires a logged-in Apple ID.
#   2. Ad-hoc ("-") signing builds fine but macOS refuses to initialize
#      App Sandbox for ad-hoc signed binaries at runtime.
# So we build with ad-hoc and then re-sign with the "Apple Development"
# certificate found in the keychain, embedding the full entitlements.

set -e
cd "$(dirname "$0")/.."

CERT="${QUICKLET_SIGN_CERT:-Apple Development}"
TEAM="${QUICKLET_TEAM:-}"
ENTITLEMENTS="scripts/resign.entitlements"
DERIVED="${QUICKLET_BUILD_DIR:-build}"

APP="$DERIVED/Build/Products/Debug/Quicklet.app"
APPEX="$APP/Contents/PlugIns/QuickletFinder.appex"

# 1. Build (ad-hoc). -disable-sandbox is required when building from
#    sandboxed host environments; harmless in a normal terminal.
xcodebuild -project Quicklet.xcodeproj -scheme Quicklet \
  -configuration Debug -derivedDataPath "$DERIVED" build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" \
  ${TEAM:+DEVELOPMENT_TEAM=$TEAM} \
  OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'

# 2. Re-sign extension first, then the app bundle.
codesign -f -s "$CERT" --entitlements "$ENTITLEMENTS" "$APPEX"
codesign -f -s "$CERT" --entitlements "$ENTITLEMENTS" "$APP"

echo "Signed OK: $APP"
