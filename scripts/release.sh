#!/bin/bash
# Cut a release.
#
# GitHub (origin) is the development remote: every commit goes there.
# Gitee is a release mirror only, so it receives tags (and the matching
# main commit) here and nowhere else.
#
# Usage: scripts/release.sh v1.2.3 [--build]
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD=false
VERSION=""
for arg in "$@"; do
  case "$arg" in
    --build) BUILD=true ;;
    -h|--help)
      echo "usage: scripts/release.sh v1.2.3 [--build]"
      exit 0
      ;;
    *) VERSION="$arg" ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "error: missing version, e.g. scripts/release.sh v1.2.3" >&2
  exit 1
fi
[[ "$VERSION" == v* ]] || VERSION="v$VERSION"

# --- Preflight -------------------------------------------------------------
branch=$(git rev-parse --abbrev-ref HEAD)
if [[ "$branch" != "main" ]]; then
  echo "error: releases are cut from main (currently on $branch)" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree is dirty, commit or stash first" >&2
  git status --short >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null; then
  echo "error: tag $VERSION already exists" >&2
  exit 1
fi

plist_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Quicklet/Info.plist 2>/dev/null || echo "?")
echo "==> releasing $VERSION (bundle version $plist_version, branch $branch)"

# --- Optional build --------------------------------------------------------
if $BUILD; then
  echo "==> building"
  ./scripts/build.sh
  mkdir -p dist
  # Same reason as build/: an .app under the home directory is indexed as a
  # second installed copy of the app.
  : > dist/.metadata_never_index
  rm -f "dist/Quicklet-$VERSION.zip"
  ditto -c -k --sequesterRsrc --keepParent /Applications/Quicklet.app "dist/Quicklet-$VERSION.zip"
  echo "    artifact: dist/Quicklet-$VERSION.zip"
fi

# --- Tag and publish to GitHub --------------------------------------------
git tag -a "$VERSION" -m "$VERSION"
echo "==> pushing to GitHub"
git push origin main
git push origin "$VERSION"

# --- Mirror to Gitee -------------------------------------------------------
echo "==> mirroring $VERSION to Gitee"
git push gitee main
git push gitee "$VERSION"

echo
echo "done: $VERSION published to both remotes"
if $BUILD; then
  echo "next: create the release on Gitee and upload dist/Quicklet-$VERSION.zip"
fi
