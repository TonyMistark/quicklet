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
INSTALL_DIR="${QUICKLET_INSTALL_DIR:-/Applications}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

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

# 3. Install. Leaving a second copy in the build directory lets Launch
#    Services hand quicklet:// URLs to either copy; macOS then sees a
#    different code identity depending on which one answers and drops the
#    saved privacy grants, so every command asks for folder access again.
if [[ -w "$INSTALL_DIR" ]]; then
  pkill -x Quicklet 2>/dev/null || true
  pkill -x QuickletFinder 2>/dev/null || true
  sleep 1
  rm -rf "$INSTALL_DIR/Quicklet.app"
  ditto "$APP" "$INSTALL_DIR/Quicklet.app"
  "$LSREGISTER" -f -R "$INSTALL_DIR/Quicklet.app" >/dev/null 2>&1 || true
  open "$INSTALL_DIR/Quicklet.app"
  echo "Installed: $INSTALL_DIR/Quicklet.app"
else
  echo "Skipped install: $INSTALL_DIR is not writable"
fi

# 4. Only one bundle may claim quicklet://. The build output and any copy
#    that ended up in the Trash also claim it, and each copy has its own
#    code identity, which is what makes macOS ask for folder access again
#    and again. Unregister everything except the installed bundle.
for stray in "$APP" "$HOME"/.Trash/Quicklet.app*; do
  [[ -d "$stray" ]] || continue
  "$LSREGISTER" -u "$stray" >/dev/null 2>&1 || true
done
