#!/usr/bin/env bash
# Builds a Release DMG of Momentum and a signed Sparkle appcast for it.
#
#   scripts/release.sh             build only (output in build/releases/<version>/)
#   scripts/release.sh --publish   build, then create the GitHub release with the DMG and appcast.xml
#
# Before each release, bump MARKETING_VERSION (e.g. 1.1) and CURRENT_PROJECT_VERSION (e.g. 2) in Xcode.
# Sparkle compares CURRENT_PROJECT_VERSION, so it must increase every release.
# Optional release notes: put build/releases/<version>/Momentum-<version>.md next to the DMG before
# the appcast step, or pass them to the GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME=Momentum
SCHEME=MyApp
REPO=jvrviegas/momentum
SPARKLE_ACCOUNT=momentum   # Keychain account holding the EdDSA private key (see generate_keys --account)

setting() {
    xcodebuild -project "$APP_NAME.xcodeproj" -target "$APP_NAME" -configuration Release -showBuildSettings 2>/dev/null \
        | awk -v key="$1" '$1 == key && !found { print $3; found = 1 }'
}
VERSION=$(setting MARKETING_VERSION)
BUILD_NUMBER=$(setting CURRENT_PROJECT_VERSION)
TAG="v$VERSION"
WORK=build/work
OUT="build/releases/$VERSION"
DMG="$OUT/$APP_NAME-$VERSION.dmg"

echo "==> Momentum $VERSION ($BUILD_NUMBER)"
rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT"

echo "==> Archiving"
xcodebuild archive -quiet \
    -project "$APP_NAME.xcodeproj" -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$WORK/$APP_NAME.xcarchive"
APP="$WORK/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app"
codesign --verify --deep --strict "$APP"
# No early `exit` in awk: with pipefail, closing the pipe early would fail the script.
IDENTITY=$(codesign -dv --verbose=2 "$APP" 2>&1 | awk -F= '/^Authority=/ && !found { print $2; found = 1 }')
echo "    signed by: $IDENTITY"

echo "==> Building DMG"
mkdir -p "$WORK/dmg"
cp -R "$APP" "$WORK/dmg/"
ln -s /Applications "$WORK/dmg/Applications"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$WORK/dmg" -format UDZO "$DMG"
codesign --sign "$IDENTITY" "$DMG"

echo "==> Generating appcast"
SPARKLE_BIN=${SPARKLE_BIN:-$(ls -d ~/Library/Developer/Xcode/DerivedData/"$APP_NAME"-*/SourcePackages/artifacts/sparkle/Sparkle/bin 2>/dev/null | head -1)}
if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
    echo "Sparkle tools not found; build the project in Xcode once, or set SPARKLE_BIN." >&2
    exit 1
fi
"$SPARKLE_BIN/generate_appcast" --account "$SPARKLE_ACCOUNT" \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    "$OUT"

echo "==> Done: $DMG"
echo "          $OUT/appcast.xml"

if [[ "${1:-}" == "--publish" ]]; then
    echo "==> Publishing $TAG to github.com/$REPO"
    gh release create "$TAG" "$DMG" "$OUT/appcast.xml" \
        --repo "$REPO" --title "$APP_NAME $VERSION" --generate-notes
fi
