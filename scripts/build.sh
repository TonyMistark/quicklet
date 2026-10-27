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
DERIVED="${QUICKLET_BUILD_DIR:-build}"

APP="$DERIVED/Build/Products/Debug/Quicklet.app"
APPEX="$APP/Contents/PlugIns/QuickletFinder.appex"

# 1. Build (ad-hoc). -disable-sandbox is required when building from
#    sandboxed host environments; harmless in a normal terminal.
#    CODE_SIGN_ENTITLEMENTS= skips entitlement embedding during the ad-hoc
#    build: xcodebuild would otherwise demand a provisioning profile for
#    the App Groups entitlement. The full entitlements are embedded in the
#    re-sign step below.
xcodebuild -project Quicklet.xcodeproj -scheme Quicklet \
  -configuration Debug -derivedDataPath "$DERIVED" build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_ENTITLEMENTS= \
  ${TEAM:+DEVELOPMENT_TEAM=$TEAM} \
  OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'

# 2. Re-sign: extension (sandboxed) first, then the unsandboxed app bundle.
codesign -f -s "$CERT" --entitlements scripts/appex.entitlements "$APPEX"
codesign -f -s "$CERT" --entitlements scripts/app.entitlements "$APP"

echo "Signed OK: $APP"
