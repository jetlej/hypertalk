#!/usr/bin/env bash
# Releases Hypertalk from this Mac, with no CI secrets:
#   scripts/release.sh <version>      e.g. scripts/release.sh 0.3.1
#
# 1. Builds, signs, notarizes and staples Hypertalk.app and its DMG
#    (scripts/make-dmg.sh), with the notarytool keychain profile
#    NOTARY_KEYCHAIN_PROFILE (default SPEED_NOTARY, the team's profile).
# 2. Signs the update archive and writes appcast.xml with the Sparkle key in
#    the login Keychain (generate_keys --account hypertalk), after checking
#    its public half is SUPublicEDKey in packaging/Info.plist.
# 3. Tags v<version>, pushes the tag, and publishes the GitHub release with
#    the DMG, the update archive and the appcast. Every installed copy reads
#    releases/latest/download/appcast.xml once a day and updates itself.
#
# Needs a clean, pushed working tree, `gh` signed in, and the Developer ID
# identity in the keychain (scripts/build-app.sh).

set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "release: $*" >&2; exit 1; }

VERSION="${1:?usage: scripts/release.sh <version>}"
VERSION="${VERSION#v}"
TAG="v$VERSION"
REPO="${HYPERTALK_REPO:-jetlej/hypertalk}"
KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-hypertalk}"
export NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-SPEED_NOTARY}"
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must be MAJOR.MINOR.PATCH, not $VERSION"
[ -z "$(git status --porcelain)" ] || fail "commit everything first"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "$TAG already exists locally"
gh release view "$TAG" -R "$REPO" >/dev/null 2>&1 && fail "$TAG is already released"

echo "→ pushing $(git branch --show-current)"
git push origin HEAD

# Sparkle's tools come with the package; resolve it if this is a fresh clone.
[ -x "$SPARKLE_BIN/generate_appcast" ] || swift package resolve
EXPECTED="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" packaging/Info.plist)"
ACTUAL="$("$SPARKLE_BIN/generate_keys" --account "$KEY_ACCOUNT" -p)"
[ "$ACTUAL" = "$EXPECTED" ] || fail "the Keychain's '$KEY_ACCOUNT' key ($ACTUAL) is not SUPublicEDKey ($EXPECTED)"
xcrun notarytool history --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" >/dev/null \
    || fail "notarytool keychain profile '$NOTARY_KEYCHAIN_PROFILE' doesn't work"

scripts/make-dmg.sh "$VERSION"

echo "→ signing the update and writing the appcast"
ZIP="Hypertalk-$VERSION.zip"
FEED="build/appcast"
rm -rf "$FEED" && mkdir -p "$FEED"
cp "dist/$ZIP" "$FEED/"
# The feed holds only this release: every client reads the latest one.
"$SPARKLE_BIN/generate_appcast" --account "$KEY_ACCOUNT" \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    --full-release-notes-url "https://github.com/$REPO/releases/tag/$TAG" \
    --link "https://github.com/$REPO" \
    --maximum-versions 1 \
    "$FEED"
SIGNATURE="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$FEED/appcast.xml")"
[ -n "$SIGNATURE" ] || fail "appcast.xml has no edSignature"
"$SPARKLE_BIN/sign_update" --account "$KEY_ACCOUNT" --verify "dist/$ZIP" "$SIGNATURE"
"$SPARKLE_BIN/sign_update" --account "$KEY_ACCOUNT" --verify "$FEED/appcast.xml"
grep -q "releases/download/$TAG/$ZIP" "$FEED/appcast.xml" || fail "appcast.xml doesn't point at $ZIP"
cp "$FEED/appcast.xml" dist/appcast.xml

# Stable names, for the README's latest/download link.
cp "dist/Hypertalk-$VERSION.dmg" dist/Hypertalk.dmg
(cd dist && shasum -a 256 Hypertalk.dmg > Hypertalk.dmg.sha256)

echo "→ tagging and publishing $TAG"
git tag -a "$TAG" -m "Hypertalk $TAG"
git push origin "$TAG"
gh release create "$TAG" -R "$REPO" --title "Hypertalk $TAG" --generate-notes \
    "dist/Hypertalk-$VERSION.dmg" "dist/Hypertalk-$VERSION.dmg.sha256" \
    dist/Hypertalk.dmg dist/Hypertalk.dmg.sha256 \
    "dist/$ZIP" dist/appcast.xml

echo "✓ released $TAG: https://github.com/$REPO/releases/tag/$TAG"
