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
#
#    The previous product is removed first: its embedded extension still
#    carries the developer certificate from the last re-sign, and an
#    incremental ad-hoc build would fail with "embedded binary is not signed
#    with the same certificate as the parent app".
rm -rf "$APP"
xcodebuild -project Quicklet.xcodeproj -scheme Quicklet \
  -configuration Debug -derivedDataPath "$DERIVED" build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_ENTITLEMENTS= \
  ${TEAM:+DEVELOPMENT_TEAM=$TEAM} \
  OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'

# 1.5 Stamp build metadata into Info.plist so the about page can name the
#     exact commit. This has to happen before re-signing: editing a plist
#     inside a bundle invalidates its signature.
PLIST="$APP/Contents/Info.plist"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  COMMIT="${COMMIT}-dirty"
fi
BUILD_DATE="$(date '+%Y-%m-%d %H:%M')"
/usr/libexec/PlistBuddy -c "Delete :QuickletGitCommit" "$PLIST" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :QuickletGitCommit string $COMMIT" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :QuickletBuildDate" "$PLIST" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :QuickletBuildDate string $BUILD_DATE" "$PLIST"
echo "Stamped: commit=$COMMIT date=$BUILD_DATE"

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
  # Overwrite in place instead of replacing the bundle. Both `rm -rf` and
  # `mv` on this path get rewritten into a move-to-Trash by some sandboxed
  # hosts, which leaves a timestamped copy behind on every build. Those
  # copies keep claiming quicklet:// with a different code identity, and
  # once enough pile up Launch Services starts handing URLs to a copy that
  # cannot run, so every command silently does nothing. ditto merges over
  # the existing bundle and never creates a stray.
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
#
#    The Trash is listed with find instead of a glob: zsh aborts on an
#    unmatched pattern, and there is usually nothing to match in there.
#    Claims are enumerated from Launch Services instead of the filesystem:
#    the Trash is unreadable from a sandboxed host, so a find-based sweep
#    never matches anything and the strays keep their registration forever.
#    Unregistering a path does not require read access to it.
while IFS= read -r stray; do
  [[ -z "$stray" ]] && continue
  [[ "$stray" == "$INSTALL_DIR/Quicklet.app" ]] && continue
  "$LSREGISTER" -u "$stray" >/dev/null 2>&1 || true
done < <("$LSREGISTER" -dump 2>/dev/null \
  | grep -E '^path:.*[Qq]uicklet' \
  | sed -e 's/^path:[[:space:]]*//' -e 's/[[:space:]]*(0x[0-9a-f]*)$//')
